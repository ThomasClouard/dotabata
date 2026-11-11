class_name MortarServer
extends ServerGame
## Abri & mortier — autorité serveur : construction, obus, explosions, dégâts, caisses, zone, bots.
## Portage de games/mortar/server.ts.



class MP extends RefCounted:
	var plot := 0
	var hp := 0
	var alive := true
	var dead_at := 0
	var last_fire := 0.0
	var ammo := "normal"
	var budget := 0


class Shell extends RefCounted:
	var id := 0
	var p: Array = []
	var v: Array = []
	var kind := "normal"
	var owner := ""
	var born := 0.0


class Bot extends RefCounted:
	var next_act := 0.0
	var target: Array = [0.0, 0.0, 0.0]
	var next_move := 0.0


var n := 0
var build_end := 0.0
var battle_end := 0.0
var shrink_start := 0.0
var mps := {}  # id → MP
var blocks := {}  # clé → {plot, x, y, z, mat, hp}
var shells := {}  # id → Shell
var crates := {}  # id → {id, p, kind, landAt}
var bots := {}  # id → Bot
var next_id := 1
var next_crate := 0.0
var next_zone := 0.0
var ending_at := 0.0
var death_order := 0


static func rnd(a: float, b: float) -> float:
	return a + randf() * (b - a)


func has_bots() -> bool:
	return true


## [[id, MP], …] des joueurs vivants.
func _alive() -> Array:
	var out: Array = []
	for id: String in mps:
		if mps[id].alive:
			out.append([id, mps[id]])
	return out


func _kill(id: String, cause: String) -> void:
	var m: MP = mps.get(id)
	if m == null or not m.alive:
		return
	m.alive = false
	m.hp = 0
	death_order += 1
	m.dead_at = death_order
	ctx.broadcast({"t": "dead", "id": id, "cause": cause})


func _hurt(id: String, dmg: float, from: Variant) -> void:
	var m: MP = mps.get(id)
	var p: ServerPlayer = ctx.players.get(id)
	if m == null or p == null or not m.alive or dmg <= 0.0:
		return
	m.hp = maxi(0, m.hp - roundi(dmg))
	# l'impact est placé du côté d'où vient le coup, en coordonnées locales du personnage
	var a := randf() * TAU
	if from != null:
		a = atan2(from[0] - p.p[0], from[2] - p.p[2]) - p.yaw + rnd(-0.5, 0.5)
	ctx.damage(id, {"pos": [sin(a) * 0.32, rnd(0.4, 1.3), cos(a) * 0.32], "r": minf(0.42, 0.16 + dmg / 180.0)})
	ctx.broadcast({"t": "hp", "id": id, "hp": m.hp})
	if m.hp <= 0:
		_kill(id, "hp")


## Un bloc de la parcelle se trouve-t-il entre l'explosion et le joueur ? (test segment / boîte)
func _covered(plot: int, wa: Array, wb: Array) -> bool:
	# on travaille dans le repère de l'île, où les blocs sont alignés sur les axes
	var la := MortarShared.to_local(plot, n, wa[0], wa[2])
	var lb := MortarShared.to_local(plot, n, wb[0], wb[2])
	var a := [la[0], wa[1], la[1]]
	var b := [lb[0], wb[1], lb[1]]
	var off := (MortarShared.GRID - 1) / 2.0
	for blk: Dictionary in blocks.values():
		if blk["plot"] != plot:
			continue
		var c := [blk["x"] - off, blk["y"] + 0.5, blk["z"] - off]
		var t0 := 0.0
		var t1 := 1.0
		var hit := true
		for k in 3:
			if not hit:
				break
			var d: float = b[k] - a[k]
			var lo: float = c[k] - 0.5
			var hi: float = c[k] + 0.5
			if absf(d) < 1e-6:
				if a[k] < lo or a[k] > hi:
					hit = false
				continue
			var u0: float = (lo - a[k]) / d
			var u1: float = (hi - a[k]) / d
			if u0 > u1:
				var tmp := u0
				u0 = u1
				u1 = tmp
			t0 = maxf(t0, u0)
			t1 = minf(t1, u1)
			if t0 > t1:
				hit = false
		if hit:
			return true
	return false


func _explode(s: Shell, pos: Array) -> void:
	shells.erase(s.id)
	var spec: Dictionary = MortarShared.SHELLS[s.kind]
	var victims: Array = []
	for pair: Array in _alive():
		var id: String = pair[0]
		var m: MP = pair[1]
		var p: ServerPlayer = ctx.players[id]
		var center := [p.p[0], p.p[1] + 0.8, p.p[2]]
		var dx: float = center[0] - pos[0]
		var dy: float = center[1] - pos[1]
		var dz: float = center[2] - pos[2]
		var d := sqrt(dx * dx + dy * dy + dz * dz)
		var big_r: float = spec["r"] + 0.5
		if d >= big_r:
			continue
		var cover := 0.35 if _covered(m.plot, pos, center) else 1.0
		var k := 1.0 - d / big_r
		var hl := sqrt(dx * dx + dz * dz)
		if hl == 0.0:
			hl = 1.0
		var f := (5.0 + 13.0 * k) * cover
		victims.append({"id": id, "dmg": (spec["dmg"] * k + 5.0) * cover, "imp": [(dx / hl) * f, 5.0 + 5.0 * k * cover, (dz / hl) * f]})
	var removed: Array = []
	for key: String in blocks.keys():
		var blk: Dictionary = blocks[key]
		var c := MortarShared.block_center(blk["plot"], blk["x"], blk["y"], blk["z"], n)
		if Vector3(c[0] - pos[0], c[1] - pos[1], c[2] - pos[2]).length() > spec["r"] + 0.4:
			continue
		blk["hp"] -= spec["block"]
		if blk["hp"] <= 0:
			blocks.erase(key)
			removed.append(key)
	ctx.broadcast({"t": "boom", "id": s.id, "p": pos, "r": spec["r"], "kind": s.kind, "removed": removed})
	for v: Dictionary in victims:
		ctx.impulse(v["id"], v["imp"], 1.0)
		_hurt(v["id"], v["dmg"], pos)
	if s.kind == "cluster":
		for i in 5:
			var a := (i / 5.0) * TAU + randf()
			_spawn_shell([pos[0], pos[1] + 0.5, pos[2]], [sin(a) * rnd(3, 7), rnd(7, 10), cos(a) * rnd(3, 7)], "sub", s.owner)


func _spawn_shell(p: Array, v: Array, kind: String, owner: String) -> void:
	var s := Shell.new()
	s.id = next_id
	next_id += 1
	s.p = p
	s.v = v
	s.kind = kind
	s.owner = owner
	s.born = ctx.now()
	shells[s.id] = s
	ctx.broadcast({"t": "shell", "id": s.id, "p": p, "v": v, "at": s.born, "kind": kind, "owner": owner})


func _step_shell(s: Shell, dt: float) -> void:
	s.v[1] -= MortarShared.G * dt
	s.p[0] += s.v[0] * dt
	s.p[1] += s.v[1] * dt
	s.p[2] += s.v[2] * dt
	if s.p[1] < -25.0:
		shells.erase(s.id)
		ctx.broadcast({"t": "gone", "id": s.id})
		return
	var young := ctx.now() - s.born < 0.35
	for pair: Array in _alive():
		var id: String = pair[0]
		if young and id == s.owner:
			continue
		var p: ServerPlayer = ctx.players[id]
		if Vector2(s.p[0] - p.p[0], s.p[2] - p.p[2]).length() < 0.6 and s.p[1] > p.p[1] - 0.1 and s.p[1] < p.p[1] + 1.6:
			_explode(s, s.p.duplicate())
			return
	for i in n:
		var l := MortarShared.to_local(i, n, s.p[0], s.p[2])
		if absf(l[0]) > MortarShared.ISLAND / 2.0 or absf(l[1]) > MortarShared.ISLAND / 2.0:
			continue
		var cell: Variant = MortarShared.cell_at(i, n, s.p[0], s.p[2])
		var y := floori(s.p[1])
		if cell != null and y >= 0 and y < MortarShared.MAX_H:
			var key := MortarShared.block_key(i, cell.x, y, cell.y)
			var blk: Variant = blocks.get(key)
			if blk != null:
				if blk["mat"] == "tramp" and s.v[1] < 0.0:
					# le trampoline renvoie l'obus et s'use
					s.p[1] = y + 1.05
					s.v = [s.v[0] * 0.9 + rnd(-1, 1), -s.v[1] * 0.85, s.v[2] * 0.9 + rnd(-1, 1)]
					s.owner = ""
					ctx.broadcast({"t": "bounce", "id": s.id, "p": s.p.duplicate(), "v": s.v.duplicate(), "at": ctx.now()})
					blk["hp"] -= 1
					if blk["hp"] <= 0:
						blocks.erase(key)
						ctx.broadcast({"t": "unblock", "keys": [key]})
					return
				_explode(s, s.p.duplicate())
				return
		if s.p[1] <= 0.0 and s.p[1] > -MortarShared.THICK:
			_explode(s, [s.p[0], 0.05, s.p[2]])
			return


static func _is_int(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v)) and float(v) == floorf(float(v))


func _place(id: String, x: Variant, z: Variant, mat: Variant) -> void:
	var m: MP = mps.get(id)
	if m == null or not m.alive or ctx.now() >= build_end or not mat is String or not MortarShared.MATS.has(mat):
		return
	if not _is_int(x) or not _is_int(z):
		return
	var xi := int(x)
	var zi := int(z)
	if xi < 0 or zi < 0 or xi >= MortarShared.GRID or zi >= MortarShared.GRID:
		return
	var y := MortarShared.column_height(blocks, m.plot, xi, zi)
	var cost: int = MortarShared.MATS[mat]["cost"]
	if y >= MortarShared.MAX_H or m.budget < cost:
		return
	m.budget -= cost
	var blk := {"plot": m.plot, "x": xi, "y": y, "z": zi, "mat": mat, "hp": MortarShared.MATS[mat]["hp"]}
	blocks[MortarShared.block_key(m.plot, xi, y, zi)] = blk
	ctx.broadcast({"t": "block", "b": blk.duplicate(), "by": id, "budget": m.budget})


func _unplace(id: String, x: Variant, z: Variant) -> void:
	var m: MP = mps.get(id)
	if m == null or not m.alive or ctx.now() >= build_end or not _is_int(x) or not _is_int(z):
		return
	var y := MortarShared.column_height(blocks, m.plot, int(x), int(z)) - 1
	var key := MortarShared.block_key(m.plot, int(x), y, int(z))
	var blk: Variant = blocks.get(key)
	if blk == null:
		return
	blocks.erase(key)
	m.budget += MortarShared.MATS[blk["mat"]]["cost"]
	ctx.broadcast({"t": "unblock", "keys": [key], "by": id, "budget": m.budget})


func _fire(id: String, yaw: Variant, power: Variant) -> void:
	var m: MP = mps.get(id)
	var p: ServerPlayer = ctx.players.get(id)
	var t := ctx.now()
	if m == null or p == null or not m.alive or t < build_end or t - m.last_fire < MortarShared.RELOAD - 0.1:
		return
	if not (yaw is float or yaw is int) or not (power is float or power is int) or not is_finite(yaw) or not is_finite(power):
		return
	m.last_fire = t
	var l := MortarShared.launch(p.p[0], p.p[1], p.p[2], yaw, power)
	_spawn_shell([l[0], l[1], l[2]], [l[3], l[4], l[5]], m.ammo, id)
	if m.ammo != "normal":
		m.ammo = "normal"
		ctx.send(id, {"t": "ammo", "kind": "normal"})


func on_start() -> Dictionary:
	n = ctx.players.size()
	var s := ctx.settings
	build_end = ctx.start_at + float(s["buildTime"])
	battle_end = build_end + float(s["battleTime"])
	shrink_start = battle_end - minf(s["shrink"], s["battleTime"])
	next_crate = build_end + rnd(6, 10)
	var plots := {}
	var spawns := {}
	var i := 0
	for p: ServerPlayer in ctx.players.values():
		plots[p.id] = i
		var c := MortarShared.plot_center(i, n)
		spawns[p.id] = [c.x, 0.1, c.z]
		var m := MP.new()
		m.plot = i
		m.hp = int(s["hp"])
		m.budget = int(s["budget"])
		mps[p.id] = m
		if p.is_bot:
			var bot := Bot.new()
			bot.next_act = ctx.start_at + rnd(0.5, 2)
			bot.target = [c.x, 0.0, c.z]
			bots[p.id] = bot
		i += 1
	var init := {"n": n, "plots": plots, "buildEnd": build_end, "battleEnd": battle_end, "shrinkStart": shrink_start, "budget": int(s["budget"]), "hp": int(s["hp"])}
	return {"init": init, "spawns": spawns}


func on_tick(dt: float) -> void:
	var t := ctx.now()
	if t < ctx.start_at:
		return
	for pair: Array in _alive():
		if ctx.players[pair[0]].p[1] < -10.0:
			_kill(pair[0], "fall")
	if t >= build_end:
		var sub := 4
		for s: Shell in shells.values():
			for k in sub:
				if not shells.has(s.id):
					break
				_step_shell(s, dt / sub)
		if ctx.settings.get("crates", true) and t >= next_crate and t < battle_end - 5.0:
			next_crate = t + rnd(9, 14)
			var live := _alive()
			if not live.is_empty():
				var m: MP = live[floori(randf() * live.size())][1]
				var cx := floori(rnd(0, MortarShared.GRID))
				var cz := floori(rnd(0, MortarShared.GRID))
				var c := MortarShared.block_center(m.plot, cx, MortarShared.column_height(blocks, m.plot, cx, cz), cz, n)
				var kind: String = ["mega", "cluster", "repair"][floori(randf() * 3)]
				var crate := {"id": next_id, "p": [c[0], c[1] - 0.1, c[2]], "kind": kind, "landAt": t + 3.5}
				next_id += 1
				crates[crate["id"]] = crate
				ctx.broadcast({"t": "crate", "id": crate["id"], "p": crate["p"], "kind": kind, "landAt": crate["landAt"]})
		for c: Dictionary in crates.values():
			if t < c["landAt"]:
				continue
			for pair: Array in _alive():
				var id: String = pair[0]
				var m: MP = pair[1]
				var p: ServerPlayer = ctx.players[id]
				if Vector2(p.p[0] - c["p"][0], p.p[2] - c["p"][2]).length() > 1.2 or absf(p.p[1] + 0.4 - c["p"][1]) > 1.5:
					continue
				crates.erase(c["id"])
				if c["kind"] == "repair":
					m.hp = mini(int(ctx.settings["hp"]), m.hp + 35)
					ctx.heal(id, 4)
					ctx.broadcast({"t": "hp", "id": id, "hp": m.hp})
				else:
					m.ammo = c["kind"]
					ctx.send(id, {"t": "ammo", "kind": c["kind"]})
				ctx.broadcast({"t": "crateTaken", "id": c["id"], "by": id, "kind": c["kind"]})
				break
		if t > shrink_start and t >= next_zone:
			next_zone = t + 0.5
			var r := MortarShared.zone_radius(t, shrink_start, battle_end)
			for pair: Array in _alive():
				var p: ServerPlayer = ctx.players[pair[0]]
				var c := MortarShared.plot_center(pair[1].plot, n)
				if Vector2(p.p[0] - c.x, p.p[2] - c.z).length() > r:
					_hurt(pair[0], 6.0, null)
	# fin : un seul survivant (on laisse 2,5 s pour savourer l'explosion) ou temps écoulé
	var left := _alive().size()
	if ending_at == 0.0 and (left <= (1 if n > 1 else 0) or t >= battle_end):
		ending_at = t + (0.0 if t >= battle_end else 2.5)
	if ending_at != 0.0 and t >= ending_at:
		ctx.end()


func on_player_message(id: String, msg: Dictionary) -> void:
	match msg.get("t"):
		"place":
			_place(id, msg.get("x"), msg.get("z"), msg.get("mat"))
		"remove":
			_unplace(id, msg.get("x"), msg.get("z"))
		"fire":
			_fire(id, msg.get("yaw"), msg.get("power"))


func on_player_leave(id: String) -> void:
	_kill(id, "fall")
	bots.erase(id)


func get_results() -> Array:
	var survivors: Array = []
	var dead: Array = []
	for id: String in mps:
		if not ctx.players.has(id):
			continue
		(survivors if mps[id].alive else dead).append(id)
	survivors.sort_custom(func(a: String, b: String) -> bool: return mps[a].hp > mps[b].hp)
	dead.sort_custom(func(a: String, b: String) -> bool: return mps[a].dead_at > mps[b].dead_at)
	var groups: Array = []
	for id: String in survivors:
		var lbl := {"id": id, "label": "Survivant · %d PV" % mps[id].hp}
		# même nombre de PV à la fin du temps : ex æquo
		if not groups.is_empty() and mps[groups[-1][0]["id"]].hp == mps[id].hp:
			groups[-1].append(lbl)
		else:
			groups.append([lbl])
	for id: String in dead:
		groups.append([{"id": id, "label": "Éliminé"}])
	return Scoring.ranks_from_groups(groups)


func bot_tick(pl: ServerPlayer, dt: float) -> void:
	var b := pl.body
	var bot: Bot = bots.get(pl.id)
	var m: MP = mps.get(pl.id)
	if b == null or bot == null or m == null:
		return
	var t := ctx.now()
	var c := MortarShared.plot_center(m.plot, n)
	var mx := 0.0
	var mz := 0.0
	if m.alive and t >= ctx.start_at:
		if t >= bot.next_act:
			if t < build_end:
				bot.next_act = minf(t + rnd(0.4, 1.1), build_end) + (rnd(1, 4) if t + 1.1 >= build_end else 0.0)
				var mat: String = MortarShared.MAT_KEYS[floori(randf() * 3)]
				# construit un muret autour du centre de l'île
				var a := randf() * TAU
				var r := rnd(1.5, 3)
				_place(pl.id, floori(MortarShared.GRID / 2.0 + sin(a) * r), floori(MortarShared.GRID / 2.0 + cos(a) * r), mat)
			else:
				bot.next_act = t + rnd(1.8, 4)
				var foes := _alive().filter(func(pair: Array) -> bool: return pair[0] != pl.id)
				if not foes.is_empty():
					var target: ServerPlayer = ctx.players[foes[floori(randf() * foes.size())][0]]
					var dx: float = target.p[0] - b.px
					var dz: float = target.p[2] - b.pz
					# visée volontairement approximative : un bot ne doit pas être un tireur d'élite
					pl.yaw = atan2(dx, dz) + rnd(-0.11, 0.11)
					_fire(pl.id, pl.yaw, MortarShared.power_for_distance(sqrt(dx * dx + dz * dz)) + rnd(-0.08, 0.08))
		if t >= bot.next_move:
			bot.next_move = t + rnd(1.5, 4)
			var r := minf(3.5, MortarShared.zone_radius(t, shrink_start, battle_end) - 1.0)
			bot.target = [c.x + rnd(-r, r), 0.0, c.z + rnd(-r, r)]
		var dx: float = bot.target[0] - b.px
		var dz: float = bot.target[2] - b.pz
		var d := sqrt(dx * dx + dz * dz)
		if d > 0.5:
			mx = (dx / d) * 0.6
			mz = (dz / d) * 0.6
	# le bot saute s'il pousse contre un bloc (vitesse presque nulle alors qu'il veut avancer)
	var blocked := b.grounded and (mx != 0.0 or mz != 0.0) and sqrt(b.vx * b.vx + b.vz * b.vz) < 1.0
	Phys.step_body(b, mx, mz, blocked, MortarShared.colliders(n, blocks, m.plot), dt)
