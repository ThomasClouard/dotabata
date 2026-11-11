class_name ParkourServer
extends ServerGame
## Parcours délirant — autorité serveur : checkpoints, arrivées, chrono, classement, bots.
## Portage de games/parkour/server.ts.

## Cibles sans surface : on y entre (ventilateur) ou elles nous emportent (canon, téléporteur, tyrolienne).
const ZONE_TARGETS := ["fan", "launcher", "teleport", "zipline", "lever", "itembox", "coin"]
const ITEM := ParkourShared.ITEM
## Mode « meilleur temps » : délai entre l'arrivée et le retour automatique au départ.
const RESTART_DELAY := 3.0

static var last_level := ""


class Progress extends RefCounted:
	var cp := -1
	var finished_at := -1.0
	var last_hit := 0.0
	var coins := {}  # pièces ramassées (index → true)
	var item := ""  # objet tenu ("" = rien)
	var shield_until := 0.0
	var last_killed := 0.0
	var run_start := 0.0  # début de l'essai en cours (mode meilleur temps)
	var best := -1.0  # meilleur temps (mode meilleur temps)
	var runs := 0  # arrivées (mode meilleur temps)
	var max_cp := -1  # checkpoint le plus loin atteint, tous essais confondus
	var restart_at := -1.0  # retour automatique au départ après une arrivée (mode meilleur temps)
	var grace_until := 0.0  # juste après « recommencer » : la position reçue est encore l'ancienne, on ne valide rien
	var away := true  # a quitté l'arrivée depuis le dernier « recommencer » (sinon pas de nouvelle arrivée)


class Bot extends RefCounted:
	var path_idx := 0
	var stuck := 0.0
	var pace := 1.0
	var wait_until := 0.0
	var detour := -1  # élément visité hors chemin (bouton, levier, boîte, pièce)
	var detour_until := 0.0
	var mem_tile := -1  # dalle mémoire visée (memory_key)
	var use_at := 0.0  # instant prévu pour utiliser l'objet tenu
	var tempted := {}  # leviers / pièces / boîtes déjà envisagés


var level := {}
var els: Array = []
var cps: Array = []
var finishes: Array = []
var start_idx := 0
var end_at := 0.0
var kill_y := -20.0
var path: Array = []
var prog := {}  # id → Progress
var bots := {}  # id → Bot
var st := Level.new_state()  # portes, leviers, dalles mémoire, boîtes, bananes, dalles friables
var traps := {}  # grille mémoire i → [bool] (secret serveur)
var bananas := {}  # k → {p, arm_at, until}
var next_banana := 1
var buttons: Array = []
var levers: Array = []
var memories: Array = []
var boxes: Array = []
var coin_els: Array = []
var finished_count := 0
var best_mode := false  # réglage « mode » : false = premier arrivé, true = meilleur temps (on recommence à volonté)
var _cols: Array = []
var _solid: Array = []  # sans les `hazard` : les bots ne prennent pas la lave pour un sol
var _cols_at := -1.0
## Tirage des boîtes surprise (→ [0, 1[), remplaçable par les tests.
var item_roll: Callable = randf


func has_bots() -> bool:
	return true


func _by_type(ty: String) -> Array:
	var out: Array = []
	for i in els.size():
		if els[i]["type"] == ty:
			out.append(i)
	return out


func colliders() -> Array:
	var t := ctx.now()
	if t != _cols_at:
		_cols = Level.build_colliders(level, t, st)
		_solid = _cols.filter(func(c: Phys.Col) -> bool: return c.tag != "hazard")
		_cols_at = t
	return _cols


static func _hypot(x: float, z: float) -> float:
	return sqrt(x * x + z * z)


# ---------- aides des bots ----------

## Boîte visée par un bot sur l'élément i (plusieurs boîtes : nacelles, dalles… → la plus proche, position anticipée).
func _target_box(i: int, b: Phys.Body, cs: Array) -> Phys.Col:
	var e: Dictionary = els[i]
	var best: Phys.Col = null
	var best_d := INF
	var cands: Array = cs
	if e["type"] == "bubble":
		# bulles : on ignore celles qui vont éclater ou qui seront trop hautes à l'atterrissage
		cands = []
		for part: Array in Level.bubble_parts(e, ctx.now() + 0.45):
			var c: Phys.Col = part[0]
			if part[2] > 1.3 and c.cy + c.hy <= b.py + Phys.jump_height() * 0.8:
				c.id = i
				cands.append(c)
	for c: Phys.Col in cands:
		if c.id != i:
			continue
		var cc := c
		if e["type"] == "ferris":
			# nacelle : on vise où elle sera à l'atterrissage
			var lead := 0.45
			cc = Phys.Col.box(c.id, c.cx + c.vx * lead, c.cy + c.vy * lead, c.cz + c.vz * lead, c.hx, c.hy, c.hz, c.yaw, c.tag)
			if cc.cy + cc.hy > b.py + Phys.jump_height() * 0.8:
				continue
		if e["type"] != "ferris" and e["type"] != "pistons" and e["type"] != "bubble":
			return cc
		var d := _hypot(maxf(0.0, absf(cc.cx - b.px) - cc.hx), maxf(0.0, absf(cc.cz - b.pz) - cc.hz)) + maxf(0.0, cc.cy + cc.hy - b.py) * 0.5
		if d < best_d:
			best_d = d
			best = cc
	return best


## La cible est-elle « prête » à recevoir un saut maintenant (dalle clignotante présente à l'atterrissage) ?
func _target_ready(i: int) -> bool:
	var e: Dictionary = els[i]
	var t := ctx.now()
	if e["type"] == "blink":
		return Level.blink_state(e, t + 0.3)["solid"] and Level.blink_state(e, t + 1.1)["solid"]
	if e["type"] == "trapdoor":
		return not Level.link_open(st, e["link"], t)
	return true


## Écart horizontal entre les pieds et la surface visée : boîte dans son repère tourné, plateau tournant = disque.
func _target_gap(el: Dictionary, col: Phys.Col, px: float, pz: float) -> float:
	if el["type"] == "turntable":
		return maxf(0.0, _hypot(px - el["pos"][0], pz - el["pos"][2]) - 0.97 * (el["size"][0] / 2.0))
	var cx: float = col.cx if col else el["pos"][0]
	var cz: float = col.cz if col else el["pos"][2]
	var yaw: float = col.yaw if col else el.get("yaw", 0.0)
	var hx: float = col.hx if col else el["size"][0] / 2.0
	var hz: float = col.hz if col else el["size"][2] / 2.0
	var co := cos(yaw)
	var si := sin(yaw)
	var dx := px - cx
	var dz := pz - cz
	var lx := dx * co - dz * si
	var lz := dx * si + dz * co
	return _hypot(maxf(0.0, absf(lx) - hx), maxf(0.0, absf(lz) - hz))


## Le segment horizontal a → b traverse-t-il la boîte c élargie de m ?
static func _seg_hits(ax0: float, az0: float, bx0: float, bz0: float, c: Phys.Col, m: float) -> bool:
	var co := cos(c.yaw)
	var si := sin(c.yaw)
	var adx := ax0 - c.cx
	var adz := az0 - c.cz
	var bdx := bx0 - c.cx
	var bdz := bz0 - c.cz
	var ax := adx * co - adz * si
	var az := adx * si + adz * co
	var bx := bdx * co - bdz * si
	var bz := bdx * si + bdz * co
	var t0 := 0.0
	var t1 := 1.0
	for axis: Array in [[ax, bx - ax, c.hx + m], [az, bz - az, c.hz + m]]:
		var p0: float = axis[0]
		var d: float = axis[1]
		var h: float = axis[2]
		if absf(d) < 1e-9:
			if absf(p0) > h:
				return false
			continue
		var ta := (-h - p0) / d
		var tb := (h - p0) / d
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true


func _near_el(pos: Array, b: Phys.Body) -> float:
	return _hypot(pos[0] - b.px, pos[2] - b.pz)


## Détours : bouton / levier d'une porte fermée sur le trajet, puis boîtes, pièces et leviers proches accessibles à pied.
func _update_detour(b: Phys.Body, bot: Bot, pr: Progress, target: Array, cs: Array, t: float) -> void:
	if bot.detour >= 0:
		var e: Dictionary = els[bot.detour]
		var done: bool = t > bot.detour_until \
			or (e["type"] == "button" and Level.link_open(st, e["link"], t)) \
			or (e["type"] == "lever" and Level.lever_down(e, bot.detour, st, t)) \
			or (e["type"] == "itembox" and (pr.item != "" or not Level.box_ready(bot.detour, st, t))) \
			or (e["type"] == "coin" and pr.coins.has(bot.detour))
		if not done:
			return
		bot.detour = -1
	if not b.grounded:
		return
	for c: Phys.Col in cs:
		if c.tag != "door":
			continue
		var e: Dictionary = els[c.id]
		if c.cy - c.hy > b.py + 1.5 or c.cy + c.hy < b.py + 0.2 or _near_el([c.cx, c.cy, c.cz], b) > 8.0 + maxf(c.hx, c.hz) or not _seg_hits(b.px, b.pz, target[0], target[2], c, 0.5):
			continue
		var best := -1
		var bd := 30.0
		for i: int in buttons + levers:
			var o: Dictionary = els[i]
			if o["link"] == e["link"] and _near_el(o["pos"], b) < bd:
				bd = _near_el(o["pos"], b)
				best = i
		if best >= 0:
			bot.detour = best
			bot.detour_until = t + 10.0
			return
	for i: int in boxes + coin_els + levers:
		var e: Dictionary = els[i]
		if bot.tempted.has(i) or _near_el(e["pos"], b) > 6.0:
			continue
		bot.tempted[i] = true  # envisagé une seule fois
		var floor_y := Phys.ground_below(e["pos"][0], b.py + 1.0, e["pos"][2], _solid)
		if absf(floor_y - b.py) > 0.4 or e["pos"][1] - e["size"][1] / 2.0 > b.py + 1.4:
			continue  # pas accessible à pied
		var want := false
		match e["type"]:
			"itembox":
				want = pr.item == "" and Level.box_ready(i, st, t) and randf() < 0.8
			"coin":
				want = not pr.coins.has(i) and randf() < 0.9
			"lever":
				want = not Level.lever_down(e, i, st, t) and randf() < 0.35
		if want:
			bot.detour = i
			bot.detour_until = t + 6.0
			return


## Grille mémoire : dalle visée dans la rangée suivante (sûres connues d'abord, sinon au hasard ; jamais une tombée).
func _memory_target(b: Phys.Body, bot: Bot, path_i: int) -> Phys.Col:
	var g: Variant = els[b.ground_id] if b.grounded and b.ground_id >= 0 and b.ground_id < els.size() else null
	var i := -1
	if g != null and g["type"] == "memory":
		i = b.ground_id
	elif els[path_i]["type"] == "memory":
		i = path_i
	if i < 0:
		bot.mem_tile = -1
		return null
	var e: Dictionary = els[i]
	var yaw: float = e["yaw"]
	var co := cos(yaw)
	var si := sin(yaw)
	var dx: float = b.px - e["pos"][0]
	var dz: float = b.pz - e["pos"][2]
	var cols: int = e["cols"]
	var rows: int = e["rows"]
	var pw: float = e["size"][0] / cols
	var pd: float = e["size"][2] / rows
	var col := clampi(floori((dx * co - dz * si + e["size"][0] / 2.0) / pw), 0, cols - 1)
	var row := clampi(floori((dx * si + dz * co + e["size"][2] / 2.0) / pd), 0, rows - 1) if g != null and g["type"] == "memory" else -1
	if row >= rows - 1:
		bot.mem_tile = -1  # dernière rangée : on poursuit le chemin
		return null
	var fallen := func(k: int) -> bool: return st["tiles"].has(Level.memory_key(i, k))
	var cur := row * cols + col
	var k_old := bot.mem_tile - i * 1024
	var keep: bool = bot.mem_tile >= 0 and floori(bot.mem_tile / 1024.0) == i and k_old != cur and not fallen.call(k_old) and floori(float(k_old) / cols) >= row
	if not keep:
		var pick := func(r: int, ok: Callable) -> int:
			var all: Array = []
			for c in cols:
				if ok.call(c) and not fallen.call(r * cols + c):
					all.append(r * cols + c)
			var safe := all.filter(func(k: int) -> bool: return st["safe"].has(Level.memory_key(i, k)))
			var from := safe if not safe.is_empty() else all
			return from[floori(randf() * from.size())] if not from.is_empty() else -1
		var k: int = pick.call(row + 1, func(c: int) -> bool: return row < 0 or absi(c - col) <= 1)
		if k < 0 and row >= 0:
			k = pick.call(row, func(c: int) -> bool: return absi(c - col) == 1)  # pas de côté
		if k < 0:
			bot.mem_tile = -1
			return null
		bot.mem_tile = Level.memory_key(i, k)
	var p: Phys.Col = Level.memory_tiles(e)[bot.mem_tile - i * 1024]
	p.id = i
	return p


## Secondes avant que la barre tournante `c` passe sur le point (barre symétrique : demi-tour).
static func _bar_eta(c: Phys.Col, px: float, pz: float) -> float:
	var sx := px - c.cx
	var sz := pz - c.cz
	var delta := fposmod(atan2(-sz, sx) - c.yaw, PI)  # angle entre la barre et le point
	return (delta if c.ang_vel > 0.0 else PI - delta) / absf(c.ang_vel)


func _spawn_at(el_idx: int, k: int, n: int) -> Array:
	var e: Dictionary = els[el_idx]
	var per_row := maxi(1, ceili(sqrt(n)))
	var sx := minf(1.4, (e["size"][0] - 1.5) / per_row)
	var sz := minf(1.4, (e["size"][2] - 1.5) / per_row)
	var col := k % per_row
	var row := floori(float(k) / per_row)
	return [e["pos"][0] + (col - (per_row - 1) / 2.0) * sx, Level.top_of(e) + 0.05, e["pos"][2] + (row - (per_row - 1) / 2.0) * sz]


## Point de réapparition : dernier checkpoint, départ, ou l'arrivée pour qui a déjà fini (premier arrivé).
func _respawn_point(pr: Progress) -> Array:
	var on_finish := pr.finished_at >= 0.0 and not best_mode
	var e: Dictionary = els[finishes[0] if on_finish else (start_idx if pr.cp < 0 else cps[pr.cp])]
	return [e["pos"][0] + (randf() - 0.5) * 1.5, Level.top_of(e) + 0.1, e["pos"][2] + (randf() - 0.5) * 1.5]


func _respawn_bot(b: Phys.Body, bot: Bot, pr: Progress) -> void:
	var p := _respawn_point(pr)
	b.set_pos(p[0], p[1], p[2])
	b.vx = 0.0
	b.vy = 0.0
	b.vz = 0.0
	b.tumble = 0.0
	Phys.clear_motion_state(b)
	bot.path_idx = path.size() - 1 if pr.finished_at >= 0.0 else maxi(0, path.find(start_idx if pr.cp < 0 else cps[pr.cp]))
	bot.stuck = 0.0
	# hésitation aléatoire : évite de retomber indéfiniment dans le même obstacle au même moment du cycle
	bot.wait_until = ctx.now() + randf() * 1.5
	bot.pace = 0.7 + randf() * 0.3


func _crumble(i: int) -> void:
	if i < 0 or i >= els.size() or els[i]["type"] != "crumble":
		return
	var e: Dictionary = els[i]
	var at: Variant = st["crumbled"].get(i)
	var t := ctx.now()
	if at != null and t < at + e["delay"] + e["respawn"]:
		return
	st["crumbled"][i] = t
	ctx.broadcast({"t": "crumble", "i": i, "at": t})


func _cosmetic_hit(id: String) -> void:
	var pr: Progress = prog.get(id)
	if pr == null or ctx.now() - pr.last_hit < 0.8:
		return
	pr.last_hit = ctx.now()
	var a := randf() * TAU
	ctx.damage(id, {"pos": [sin(a) * 0.3, 0.55 + randf() * 0.7, cos(a) * 0.3], "r": 0.14 + randf() * 0.08})


## Mort dans un hazard : relayée à tous pour l'effet lave / eau / acide (au plus 2 par seconde et par joueur).
func _relay_killed(id: String, i: int) -> void:
	var pr: Progress = prog.get(id)
	var pl: ServerPlayer = ctx.players.get(id)
	var t := ctx.now()
	if pr == null or pl == null or t - pr.last_killed < 0.5:
		return
	pr.last_killed = t
	ctx.broadcast({"t": "killed", "id": id, "i": i, "p": pl.p.duplicate()})


# ---------- vague 3 : interactions détectées sur les positions des joueurs, objets, pièces ----------

## Ouvre `link` pendant `duration` s (prolonge une ouverture en cours) ; by = bouton / levier.
func _open_link(link: String, duration: float, by: int) -> void:
	var t := ctx.now()
	var s: Variant = st["links"].get(link)
	var live: bool = s != null and t < s[1]
	if live and s[1] - t > duration - 0.5:
		return  # déjà ouvert pour (presque) toute la durée : pas de spam
	var at: float = s[0] if live else t
	var until := maxf(s[1] if live else 0.0, t + duration)
	st["links"][link] = [at, until]
	ctx.broadcast({"t": "open", "link": link, "at": at, "until": until, "by": by})


func _pull_lever(i: int) -> void:
	var e: Dictionary = els[i]
	var t := ctx.now()
	if Level.lever_down(e, i, st, t):
		return
	st["levers"][i] = t
	ctx.broadcast({"t": "lever", "i": i, "at": t})
	_open_link(e["link"], e["duration"], i)


## Un joueur se pose sur la dalle k de la grille i : piégée → elle tombe pour tous ; sûre → révélée.
func _step_tile(i: int, k: int) -> void:
	var key := Level.memory_key(i, k)
	var t := ctx.now()
	if st["tiles"].has(key):
		return
	if traps.has(i) and traps[i][k]:
		st["tiles"][key] = t
		ctx.broadcast({"t": "tile", "i": i, "k": k, "at": t})
	elif not st["safe"].has(key):
		st["safe"][key] = true
		ctx.broadcast({"t": "safe", "i": i, "k": k})


func _shielded(id: String) -> bool:
	var pr: Progress = prog.get(id)
	return pr != null and pr.shield_until > ctx.now()


func _give_item(id: String, pr: Progress, kind: String) -> void:
	pr.item = kind
	ctx.broadcast({"t": "item", "id": id, "kind": kind if kind != "" else null})
	var bot: Bot = bots.get(id)
	if bot != null and kind != "":
		bot.use_at = ctx.now() + 1.0 + randf() * 4.0


## Utilisation de l'objet tenu (message { t: 'use' } ou bot).
func _use_item(id: String) -> void:
	var pr: Progress = prog.get(id)
	var pl: ServerPlayer = ctx.players.get(id)
	var t := ctx.now()
	if pr == null or pl == null or pr.item == "" or pr.finished_at >= 0.0:
		return
	var kind := pr.item
	var fx := sin(pl.yaw)
	var fz := cos(pl.yaw)
	# banane : posée au sol derrière soi ; pas de sol (vide, lave) à moins de 6 m sous les pieds → on la garde
	var banana_at: Array = []
	if kind == "banana":
		var bx: float = pl.p[0] - fx * ITEM["bananaBack"]
		var bz: float = pl.p[2] - fz * ITEM["bananaBack"]
		colliders()
		var gy := Phys.ground_below(bx, pl.p[1] + 0.5, bz, _solid)
		if gy < pl.p[1] - 6.0:
			return
		banana_at = [bx, gy, bz]
	_give_item(id, pr, "")
	if kind == "super" or kind == "shield":
		var dur: float = ITEM["superTime"] if kind == "super" else ITEM["shieldTime"]
		var until := t + dur
		if kind == "shield":
			pr.shield_until = until
		if pl.body:
			if kind == "super":
				pl.body.super_jump = dur
			else:
				pl.body.shield = dur
		ctx.broadcast({"t": "effect", "id": id, "kind": kind, "until": until})
	elif kind == "banana":
		var k := next_banana
		next_banana += 1
		bananas[k] = {"p": banana_at, "arm_at": t + ITEM["bananaArm"], "until": t + ITEM["bananaLife"]}
		st["bananas"][k] = banana_at
		ctx.broadcast({"t": "banana", "k": k, "p": banana_at})
	else:
		# gant de boxe : repousse les joueurs proches devant soi
		var hit: Array = []
		for q: ServerPlayer in ctx.players.values():
			if q.id == id or not prog.has(q.id) or prog[q.id].finished_at >= 0.0:
				continue
			var dx: float = q.p[0] - pl.p[0]
			var dz: float = q.p[2] - pl.p[2]
			var d := _hypot(dx, dz)
			if d > ITEM["gloveRange"] or d < 0.01 or absf(q.p[1] - pl.p[1]) > 1.6 or (dx * fx + dz * fz) / d < ITEM["gloveDot"] or _shielded(q.id):
				continue
			ctx.impulse(q.id, [(dx / d) * ITEM["gloveV"], ITEM["gloveUp"], (dz / d) * ITEM["gloveV"]], ITEM["gloveTumble"])
			hit.append(q.id)
		ctx.broadcast({"t": "glove", "id": id, "hit": hit})


## Bananes : le premier qui passe dessus (une fois armée) glisse en roulé-boulé ; le bouclier protège mais l'écrase.
func _banana_tick(t: float) -> void:
	for k: int in bananas.keys():
		var bn: Dictionary = bananas[k]
		var by := ""
		if t >= bn["until"]:
			by = "-"
		elif t >= bn["arm_at"]:
			for q: ServerPlayer in ctx.players.values():
				if not prog.has(q.id) or prog[q.id].finished_at >= 0.0:
					continue
				if _hypot(q.p[0] - bn["p"][0], q.p[2] - bn["p"][2]) > ITEM["bananaR"] or absf(q.p[1] - bn["p"][1]) > 0.6:
					continue
				by = q.id
				if not _shielded(q.id):
					var sp := _hypot(q.v[0], q.v[2])
					var dx: float = q.v[0] / sp if sp > 1.0 else sin(q.yaw)
					var dz: float = q.v[2] / sp if sp > 1.0 else cos(q.yaw)
					ctx.impulse(q.id, [dx * ITEM["slipSpeed"], ITEM["slipUp"], dz * ITEM["slipSpeed"]], ITEM["slipTumble"])
				break
		if by == "":
			continue
		bananas.erase(k)
		st["bananas"].erase(k)
		ctx.broadcast({"t": "bananaGone", "k": k, "by": "" if by == "-" else by})


## Boutons, leviers, dalles mémoire, boîtes surprise et pièces touchés par le joueur p.
func _interactions(p: ServerPlayer, pr: Progress, t: float) -> void:
	var grounded := (p.flags & Protocol.FLAG_GROUNDED) != 0
	var x: float = p.p[0]
	var y: float = p.p[1]
	var z: float = p.p[2]
	for i: int in buttons:
		var e: Dictionary = els[i]
		if grounded and Level.stands_on(e, x, y, z):
			_open_link(e["link"], e["duration"], i)
	for i: int in levers:
		if Level.touches(els[i], x, y, z):
			_pull_lever(i)
	for i: int in memories:
		var e: Dictionary = els[i]
		if not grounded or not Level.stands_on(e, x, y, z):
			continue
		# joint compris : les dalles qui portent la capsule (piégée → tombe, sûre → révélée)
		for k: int in Level.memory_tiles_under(e, x, z):
			_step_tile(i, k)
	for i: int in boxes:
		var e: Dictionary = els[i]
		if pr.item != "" or not Level.box_ready(i, st, t) or not Level.touches(e, x, y, z):
			continue
		st["boxes"][i] = t + e["respawn"]
		ctx.broadcast({"t": "box", "i": i, "until": t + e["respawn"], "id": p.id})
		_give_item(p.id, pr, ParkourShared.ITEMS[floori(item_roll.call() * ParkourShared.ITEMS.size())])
	for i: int in coin_els:
		if pr.coins.has(i) or not Level.touches(els[i], x, y, z):
			continue
		pr.coins[i] = true
		ctx.broadcast({"t": "coin", "id": p.id, "i": i, "n": pr.coins.size()})


# ---------- manche ----------

## Niveaux proposés : autorisés (ou tous), présents et terminables.
static func playable_levels(allowed: Array) -> Array:
	var available := LevelStore.list_levels()
	var pool: Array = allowed.filter(func(n: Variant) -> bool: return available.has(n))
	if pool.is_empty():
		pool = available
	return pool.filter(func(n: String) -> bool:
		var lv := LevelStore.read_level(n)
		return not lv.is_empty() and LevelValidate.validate(lv)["ok"])


func on_start() -> Dictionary:
	var pool := playable_levels(ctx.settings.get("levels", []))
	if pool.is_empty():
		push_error("Aucun niveau de parcours valide.")
		return {}
	var fresh := pool.filter(func(n: String) -> bool: return n != last_level)
	var from := fresh if not fresh.is_empty() else pool
	var lname: String = from[floori(randf() * from.size())]
	last_level = lname
	return start_with(LevelStore.read_level(lname))


## Démarre la manche sur un niveau déjà lu (utilisé aussi par les tests).
func start_with(lv: Dictionary) -> Dictionary:
	level = lv
	els = level["elements"]
	path = LevelValidate.validate(level)["path"]
	for i in els.size():
		match els[i]["type"]:
			"checkpoint":
				cps.append(i)
			"finish":
				finishes.append(i)
			"start":
				start_idx = i
	kill_y = Level.kill_y(level)
	best_mode = ctx.settings.get("mode", "first") == "best"
	end_at = ctx.start_at + float(ctx.settings.get("duration", 150))
	buttons = _by_type("button")
	levers = _by_type("lever")
	memories = _by_type("memory")
	boxes = _by_type("itembox")
	coin_els = _by_type("coin")
	for i: int in memories:
		var e: Dictionary = els[i]
		traps[i] = ParkourShared.memory_layout(e["cols"], e["rows"], e["traps"], randf)
	var spawns := {}
	var k := 0
	for p: ServerPlayer in ctx.players.values():
		spawns[p.id] = _spawn_at(start_idx, k, ctx.players.size())
		k += 1
		var pr := Progress.new()
		pr.run_start = ctx.start_at
		prog[p.id] = pr
		if p.is_bot:
			var bot := Bot.new()
			bot.pace = 0.7 + randf() * 0.3
			bot.wait_until = ctx.start_at + randf() * 0.8
			bots[p.id] = bot
	var init := {"level": level, "endAt": end_at, "cps": cps, "jostle": ctx.settings.get("jostle") != false, "coins": ctx.settings.get("coins") != false, "mode": "best" if best_mode else "first"}
	return {"init": init, "spawns": spawns}


func on_tick(_dt: float) -> void:
	var t := ctx.now()
	if t < ctx.start_at:
		return
	_banana_tick(t)
	for p: ServerPlayer in ctx.players.values():
		var pr: Progress = prog.get(p.id)
		if pr == null:
			continue
		if pr.restart_at >= 0.0 and t >= pr.restart_at:
			restart(p.id, true)
		if pr.finished_at >= 0.0 or t < pr.grace_until:
			continue
		if not pr.away:
			pr.away = not finishes.any(func(f: int) -> bool: return Level.on_pad(els[f], p.p[0], p.p[1], p.p[2]))
			if not pr.away:
				continue
		_interactions(p, pr, t)
		for k in range(cps.size() - 1, pr.cp, -1):
			if Level.on_pad(els[cps[k]], p.p[0], p.p[1], p.p[2]):
				pr.cp = k
				pr.max_cp = maxi(pr.max_cp, k)
				ctx.broadcast({"t": "cp", "id": p.id, "k": k})
				break
		for f: int in finishes:
			if Level.on_pad(els[f], p.p[0], p.p[1], p.p[2]) and best_mode:
				# meilleur temps : chrono de l'essai, record éventuel, puis retour au départ dans quelques secondes
				var run := t - pr.run_start
				var record := pr.best < 0.0 or run < pr.best
				if record:
					pr.best = run
				pr.runs += 1
				pr.finished_at = t - ctx.start_at
				pr.restart_at = t + RESTART_DELAY
				ctx.broadcast({"t": "finish", "id": p.id, "time": run, "best": pr.best, "record": record, "runs": pr.runs})
				break
			if Level.on_pad(els[f], p.p[0], p.p[1], p.p[2]):
				pr.finished_at = t - ctx.start_at
				finished_count += 1
				ctx.broadcast({"t": "finish", "id": p.id, "time": pr.finished_at, "place": finished_count})
				var hurry := float(ctx.settings.get("hurry", 40))
				if finished_count == 1 and end_at - t > hurry:
					end_at = t + hurry
					ctx.broadcast({"t": "hurry", "endAt": end_at})
				break
	if t >= end_at or (not best_mode and prog.size() > 0 and finished_count >= prog.size()):
		ctx.end()


## Recommencer : au départ (to_start) ou au dernier checkpoint. Premier arrivé : impossible une fois arrivé.
## Meilleur temps : repartir du départ relance le chrono de l'essai.
func restart(id: String, to_start: bool) -> void:
	var pr: Progress = prog.get(id)
	var t := ctx.now()
	if pr == null or t < ctx.start_at or (pr.finished_at >= 0.0 and not best_mode):
		return
	if pr.finished_at >= 0.0:
		to_start = true
	if to_start:
		pr.cp = -1
		if best_mode:
			pr.run_start = t
	pr.finished_at = -1.0
	pr.restart_at = -1.0
	pr.grace_until = t + 0.6
	pr.away = false
	var bot: Bot = bots.get(id)
	var pl: ServerPlayer = ctx.players.get(id)
	if bot != null and pl != null and pl.body != null:
		_respawn_bot(pl.body, bot, pr)
	ctx.broadcast({"t": "restart", "id": id, "cp": pr.cp, "runStart": pr.run_start})


func on_player_message(id: String, msg: Dictionary) -> void:
	var mt: Variant = msg.get("t")
	var mi: Variant = msg.get("i")
	var is_int: bool = (mi is float or mi is int) and float(mi) == floorf(float(mi))
	if mt == "crumble" and is_int:
		_crumble(int(mi))
	elif mt == "hit":
		_cosmetic_hit(id)
	elif mt == "use":
		_use_item(id)
	elif mt == "restart":
		restart(id, msg.get("to") == "start")
	elif mt == "killed" and is_int and int(mi) >= 0 and int(mi) < els.size() and els[int(mi)]["type"] == "hazard":
		_relay_killed(id, int(mi))


func on_player_leave(id: String) -> void:
	var pr: Progress = prog.get(id)
	if pr != null and pr.finished_at >= 0.0 and not best_mode:
		finished_count -= 1
	prog.erase(id)
	bots.erase(id)


func get_results() -> Array:
	var targets: Array = cps + [finishes[0]]
	var rows: Array = []
	for id: String in prog:
		var pr: Progress = prog[id]
		var p: ServerPlayer = ctx.players.get(id)
		var tgt: Dictionary = els[targets[mini(pr.cp + 1, targets.size() - 1)]]
		var dist := 1e9
		if p != null:
			dist = Vector3(p.p[0] - tgt["pos"][0], p.p[1] - tgt["pos"][1], p.p[2] - tgt["pos"][2]).length()
		rows.append({"id": id, "pr": pr, "dist": dist})
	# pièces : départagent les temps égaux (au dixième affiché) et les checkpoints égaux, si le réglage le veut
	var use_coins: bool = ctx.settings.get("coins") != false
	var coin_cmp := func(a: Dictionary, b: Dictionary) -> int: return (b["pr"].coins.size() - a["pr"].coins.size()) if use_coins else 0
	var with_coins := func(label: String, n: int) -> String: return ("%s · %d pièce%s" % [label, n, "s" if n > 1 else ""]) if n > 0 else label
	if best_mode:
		return _best_results(rows, coin_cmp, with_coins)
	var done := rows.filter(func(r: Dictionary) -> bool: return r["pr"].finished_at >= 0.0)
	var rest := rows.filter(func(r: Dictionary) -> bool: return r["pr"].finished_at < 0.0)
	done.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := roundi(a["pr"].finished_at * 10.0)
		var tb := roundi(b["pr"].finished_at * 10.0)
		if ta != tb:
			return ta < tb
		var c: int = coin_cmp.call(a, b)
		if c != 0:
			return c < 0
		return a["pr"].finished_at < b["pr"].finished_at)
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["pr"].cp != b["pr"].cp:
			return a["pr"].cp > b["pr"].cp
		var c: int = coin_cmp.call(a, b)
		if c != 0:
			return c < 0
		return a["dist"] < b["dist"])
	var groups: Array = []
	for r: Dictionary in done:
		groups.append([{"id": r["id"], "label": with_coins.call(ParkourShared.format_time(r["pr"].finished_at), r["pr"].coins.size())}])
	for r: Dictionary in rest:
		var pr: Progress = r["pr"]
		groups.append([{"id": r["id"], "label": with_coins.call("Checkpoint %d/%d" % [pr.cp + 1, cps.size()] if pr.cp >= 0 else "Pas arrivé", pr.coins.size())}])
	return Scoring.ranks_from_groups(groups)


## Classement du mode meilleur temps : record (au dixième, puis pièces), sinon checkpoint le plus loin atteint.
func _best_results(rows: Array, coin_cmp: Callable, with_coins: Callable) -> Array:
	var done := rows.filter(func(r: Dictionary) -> bool: return r["pr"].best >= 0.0)
	var rest := rows.filter(func(r: Dictionary) -> bool: return r["pr"].best < 0.0)
	done.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := roundi(a["pr"].best * 10.0)
		var tb := roundi(b["pr"].best * 10.0)
		if ta != tb:
			return ta < tb
		var c: int = coin_cmp.call(a, b)
		if c != 0:
			return c < 0
		return a["pr"].best < b["pr"].best)
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["pr"].max_cp != b["pr"].max_cp:
			return a["pr"].max_cp > b["pr"].max_cp
		var c: int = coin_cmp.call(a, b)
		if c != 0:
			return c < 0
		return a["dist"] < b["dist"])
	var groups: Array = []
	for r: Dictionary in done:
		var pr: Progress = r["pr"]
		groups.append([{"id": r["id"], "label": with_coins.call("%s (%d arrivée%s)" % [ParkourShared.format_time(pr.best), pr.runs, "s" if pr.runs > 1 else ""], pr.coins.size())}])
	for r: Dictionary in rest:
		var pr: Progress = r["pr"]
		groups.append([{"id": r["id"], "label": with_coins.call("Checkpoint %d/%d" % [pr.max_cp + 1, cps.size()] if pr.max_cp >= 0 else "Pas arrivé", pr.coins.size())}])
	return Scoring.ranks_from_groups(groups)


# ---------- bots : suivent le chemin de la validation, sautent au bord, attendent les plateformes mobiles ----------

func bot_tick(pl: ServerPlayer, dt: float) -> void:
	var b := pl.body
	var bot: Bot = bots.get(pl.id)
	var pr: Progress = prog.get(pl.id)
	if b == null or bot == null or pr == null:
		return
	var cs := colliders()
	var t := ctx.now()
	var mx := 0.0
	var mz := 0.0
	var jump := false
	if b.zip >= 0:
		# suspendu à une tyrolienne : on se laisse porter jusqu'au bout (sauter ferait lâcher)
		var at := path.find(b.zip, bot.path_idx)
		if at > bot.path_idx:
			bot.path_idx = at
		bot.stuck = 0.0
	elif pr.finished_at < 0.0 and t > bot.wait_until:
		# recale la progression si on se tient sur un élément plus loin sur le chemin
		if b.grounded:
			var at := path.find(b.ground_id, bot.path_idx)
			if at > bot.path_idx:
				bot.path_idx = at
				bot.stuck = 0.0
		var path_i: int = path[mini(bot.path_idx + 1, path.size() - 1)]
		# détour (bouton d'une porte fermée, boîte, pièce, levier), sinon dalle mémoire, sinon la suite du chemin
		_update_detour(b, bot, pr, els[path_i]["pos"], cs, t)
		var mem_col: Phys.Col = _memory_target(b, bot, path_i) if bot.detour < 0 else null
		var next_i: int = bot.detour if bot.detour >= 0 else (mem_col.id if mem_col else path_i)
		var el: Dictionary = els[next_i]
		var col: Phys.Col = mem_col if mem_col else _target_box(next_i, b, cs)
		var on_mem := mem_col != null
		var multi: bool = el["type"] in ["ferris", "pistons", "bubble"]
		var zone: bool = el["type"] in ZONE_TARGETS
		var tcx: float = col.cx if col else el["pos"][0]
		var tcz: float = col.cz if col else el["pos"][2]
		var top: float = b.py if zone else (col.cy + col.hy if col else Level.top_of(el))
		if el["type"] == "ramp":
			top = Level.ramp_top_at(el, b.px, b.pz)  # hauteur du bord de rampe le plus proche
		if el["type"] == "fan" and absf(b.px - el["pos"][0]) < el["size"][0] / 2.0 and absf(b.pz - el["pos"][2]) < el["size"][2] / 2.0 and b.py > el["pos"][1] + el["size"][1] / 2.0 - 2.0:
			bot.path_idx += 1
		var dx := tcx - b.px
		var dz := tcz - b.pz
		var d := _hypot(dx, dz)
		if d == 0.0:
			d = 1.0
		var ux := dx / d
		var uz := dz / d
		var gap_to_target := _target_gap(el, col, b.px, b.pz)
		# arrivé au-dessus de la cible sans s'y être posé (ex. debout sur une barre tournante) : on passe à la suite
		if not zone and not on_mem and bot.detour < 0 and b.grounded and gap_to_target == 0.0 and b.py >= top - 0.1 and bot.path_idx + 1 < path.size() - 1:
			bot.path_idx += 1
			bot.stuck = 0.0
		# la lave n'est pas un sol : on saute par-dessus comme au-dessus du vide
		var edge := Phys.ground_below(b.px + ux * 0.8, b.py, b.pz + uz * 0.8, _solid) < b.py - 0.5
		# portée du saut selon le sol (boue, gélatine), l'élan d'un speed pad et la gravité locale (zone lunaire)
		var run_speed := maxf(Phys.SPEED * b.slow, _hypot(b.vx, b.vz)) if b.boost > 0.0 else Phys.SPEED * b.slow
		var v0 := Phys.JUMP_V * b.jump_k
		if b.super_jump > 0.0:
			v0 *= Phys.SUPER_JUMP
		var reach := Phys.jump_reach(top - b.py, v0, run_speed, Phys.GRAVITY * Level.lowgrav_at(level, b.px, b.py, b.pz))
		var ready := _target_ready(next_i) and (not multi or col != null)
		# sur une bulle on attend d'être presque à hauteur de la cible : le saut part sans élan
		var ground_el: Variant = els[b.ground_id] if b.grounded and b.ground_id >= 0 and b.ground_id < els.size() else null
		var riding: bool = ground_el != null and ground_el["type"] == "bubble" and top - b.py > 0.3
		var feasible: bool = zone or (ready and not riding and reach >= 0.0 and gap_to_target <= reach * 0.82)
		var waiting := false
		if d > 0.4:
			mx = ux * bot.pace
			mz = uz * bot.pace
		# perché sur une barre tournante (spinner, barre basse d'un balayeur) : ce n'est pas un bord où attendre, on en descend
		var on_bar: bool = ground_el != null and ground_el["type"] in ["spinner", "sweeper"]
		if b.grounded and edge and not (on_bar and not feasible):
			if feasible:
				jump = true
			else:
				mx = 0.0  # cible mobile trop loin / dalle absente : on attend au bord
				mz = 0.0
				waiting = true
		elif b.grounded and top > b.py + 0.25 and gap_to_target < 1.5 and ready:
			jump = true
		# grille mémoire : on marche de dalle en dalle (un saut pourrait atterrir deux rangées plus loin)
		if on_mem and gap_to_target < 0.6:
			jump = false
			if d > 0.4:
				mx = ux * bot.pace
				mz = uz * bot.pace
			waiting = false
		# tyrolienne trop haute pour l'attraper en marchant dessous : on saute
		if el["type"] == "zipline" and b.grounded and d < 1.2 and el["pos"][1] - Phys.ZIP_HANG - b.py > 0.6:
			jump = true
		# pistons : on grimpe sur la dalle voisine si elle est plus haute
		if b.grounded and not jump and ((ground_el != null and ground_el["type"] == "pistons") or el["type"] == "pistons"):
			if Phys.ground_below(b.px + ux * 0.7, b.py + 1.1, b.pz + uz * 0.7, _solid) > b.py + 0.3:
				jump = true
		# guillotine devant nous : on attend qu'elle soit levée et qu'il reste le temps de passer dessous
		for c: Phys.Col in cs:
			if c.tag != "gate":
				continue
			var g: Dictionary = els[c.id]
			if g["type"] != "gate" or g["pos"][1] - g["drop"] - g["size"][1] / 2.0 > b.py + 1.7 or g["pos"][1] + g["size"][1] / 2.0 < b.py:
				continue
			var co := cos(c.yaw)
			var si := sin(c.yaw)
			var gx := b.px - c.cx
			var gz := b.pz - c.cz
			var lx := gx * co - gz * si
			var lz := gx * si + gz * co
			if absf(lx) > c.hx + 0.5 or absf(lz) > c.hz + 1.6 or absf(lz) < c.hz + 0.45:
				continue  # loin, ou déjà dessous : on fonce
			var clear := c.cy - c.hy > b.py + 1.7 and Level.gate_until_fall(g, t) > 0.9
			if not clear and ux * -gx + uz * -gz > 0.0:
				mx = 0.0
				mz = 0.0
				jump = false
				waiting = true
		# barres tournantes sur le point de nous faucher : on saute par-dessus ; barre haute du balayeur : surtout pas
		var bar_jump := false
		var no_jump := false
		for c: Phys.Col in cs:
			if (c.tag != "spinner" and c.tag != "sweeper") or c.ang_vel == 0.0 or not b.grounded or b.ground_id == c.id:
				continue
			if _hypot(b.px - c.cx, b.pz - c.cz) > c.hx + 0.6:
				continue
			var lo := c.cy - c.hy
			var hi := c.cy + c.hy
			if hi >= b.py and lo <= b.py + 1.2:
				if _bar_eta(c, b.px, b.pz) < 0.3:
					bar_jump = true
			elif c.tag == "sweeper" and lo > b.py + 1.2 and lo < b.py + Phys.jump_height() + Phys.HEIGHT + 0.3 and _bar_eta(c, b.px, b.pz) < 0.9:
				no_jump = true
		if bar_jump:
			jump = true
		elif no_jump and jump:
			jump = false
			if edge:
				mx = 0.0
				mz = 0.0
				waiting = true
		# rouleau : on compense son entraînement pour garder le cap
		if ground_el != null and ground_el["type"] == "roller" and (mx != 0.0 or mz != 0.0):
			var ix: float = mx * Phys.SPEED - sin(ground_el["yaw"]) * ground_el["speed"]
			var iz: float = mz * Phys.SPEED - cos(ground_el["yaw"]) * ground_el["speed"]
			var nn := _hypot(ix, iz) / Phys.SPEED
			if nn > 1.0:
				ix /= nn
				iz /= nn
			mx = ix / Phys.SPEED
			mz = iz / Phys.SPEED
		bot.stuck += dt * 0.25 if waiting else dt  # attendre une nacelle / une dalle n'est pas être coincé
		if bot.stuck > 9.0:
			_respawn_bot(b, bot, pr)
	var pre := ParkourShared.pre_step(level, b, dt, t)
	# canon, téléporteur, tyrolienne : on est emporté vers la suite du chemin
	for i: int in [pre["launched"], pre["teleported"], pre["grabbed"]]:
		if i < 0:
			continue
		var at := path.find(i, bot.path_idx)
		if at > bot.path_idx:
			bot.path_idx = at
			bot.stuck = 0.0
	if b.zip >= 0:
		mx = 0.0
		mz = 0.0
		jump = false
	var contacts := Phys.step_body(b, mx, mz, jump, cs, dt)
	# un trampoline ne « pose » jamais le bot : on avance sur le chemin dès le rebond
	for c: Phys.Contact in contacts:
		if not c.bounced:
			continue
		var at := path.find(c.id, bot.path_idx)
		if at > bot.path_idx:
			bot.path_idx = at
			bot.stuck = 0.0
	var ev := ParkourShared.post_step(b, contacts)
	if ev["knocked"]:
		_cosmetic_hit(pl.id)
	for i: int in ev["crumble"]:
		_crumble(i)
	if ev["killed"]:
		_relay_killed(pl.id, ev["hazard"])
	if ev["killed"] or b.py < kill_y:
		_respawn_bot(b, bot, pr)
	# bousculades avec les autres joueurs (réglage de la manche)
	if ctx.settings.get("jostle") != false:
		for q: ServerPlayer in ctx.players.values():
			if q.id != pl.id and prog.has(q.id) and pr.finished_at < 0.0 and prog[q.id].finished_at < 0.0:
				Phys.jostle(b, q.p[0], q.p[1], q.p[2], q.v[0], q.v[2])  # ceux qui ont fini ne gênent personne
	if mx != 0.0 or mz != 0.0:
		pl.yaw = atan2(mx, mz)
	pl.flags = (Protocol.FLAG_GROUNDED if b.grounded or b.coyote > 0.0 else 0) | (Protocol.FLAG_TUMBLE if b.tumble > 0.0 else 0) | Protocol.pose_flags(b)
	# objet tenu : utilisé au hasard (le gant attend une cible devant, 5 s au plus)
	if pr.item != "" and pr.finished_at < 0.0 and t >= bot.use_at:
		var fx := sin(pl.yaw)
		var fz := cos(pl.yaw)
		var target := false
		for q: ServerPlayer in ctx.players.values():
			var qdx: float = q.p[0] - b.px
			var qdz: float = q.p[2] - b.pz
			var dd := _hypot(qdx, qdz)
			if q.id != pl.id and prog.has(q.id) and dd < ITEM["gloveRange"] and dd > 0.01 and (qdx * fx + qdz * fz) / dd >= ITEM["gloveDot"]:
				target = true
				break
		if pr.item != "glove" or target or t > bot.use_at + 5.0:
			_use_item(pl.id)
