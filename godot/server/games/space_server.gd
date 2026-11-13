class_name SpaceServer
extends ServerGame
## Saut cosmique — autorité serveur : planètes, décollages, atterrissages, classement, bots.
## Chacun décolle quand il veut pendant le temps imparti (sinon, décollage automatique à la fin) ; chaque client pilote
## son vol (comme ses déplacements ailleurs) et annonce son atterrissage, que le serveur vérifie.

const LAND_TOL := 5.0  # tolérance (m) sur la position reçue, en retard de quelques images sur l'atterrissage
const END_DELAY := 2.5


class SP extends RefCounted:
	var status := "aim"  # aim, fly, landed, lost
	var planet := -1
	var at := 0.0


class Bot extends RefCounted:
	var target := 1
	var spot := Vector3.ZERO  # point de décollage choisi
	var plan_at := 0.0
	var planned := false
	var go_at := 0.0  # instant du décollage
	var dir := Vector3.UP
	var p := Vector3.ZERO
	var v := Vector3.ZERO
	var fuel := 0.0
	var fix_at := 0.0
	var fixing := false


var planets: Array = []
var aim_end := 0.0
var flight_end := 0.0
var gravity := true
var fuel := 1.5
var sps := {}  # id → SP
var bots := {}  # id → Bot
var ending_at := 0.0


static func rnd(a: float, b: float) -> float:
	return a + randf() * (b - a)


func has_bots() -> bool:
	return true


## Points de départ répartis sur le haut de la planète.
static func spawn_point(i: int) -> Vector3:
	var a := i * 2.399963
	var th := 0.22 + 0.13 * (i % 4)
	return Vector3(sin(th) * cos(a), cos(th), sin(th) * sin(a)) * (SpaceShared.HOME_R + 0.05)


func start_with(seed_: int) -> Dictionary:
	var s := ctx.settings
	planets = SpaceShared.layout(seed_, int(s.get("planets", 7)))
	aim_end = ctx.start_at + float(s.get("aimTime", 30))
	flight_end = aim_end + float(s.get("flightTime", 30))
	gravity = bool(s.get("gravity", true))
	fuel = float(s.get("fuel", 1.5))
	var spawns := {}
	var i := 0
	for p: ServerPlayer in ctx.players.values():
		var sp := spawn_point(i)
		spawns[p.id] = [sp.x, sp.y, sp.z]
		sps[p.id] = SP.new()
		if p.is_bot:
			var bot := Bot.new()
			# préférence pour les planètes proches, mais on tente parfois le gros lot
			var w: Array = []
			var total := 0.0
			for k in range(1, planets.size()):
				var wk := 1.0 / k
				w.append(wk)
				total += wk
			var r := randf() * total
			bot.target = planets.size() - 1
			for k in w.size():
				r -= w[k]
				if r <= 0.0:
					bot.target = k + 1
					break
			var tdir := SpaceShared.v3(planets[bot.target]["c"]).normalized()
			var sdir := sp.normalized()
			bot.spot = sdir.slerp(tdir, 0.8).normalized() * (SpaceShared.HOME_R + 0.05) if sdir.dot(tdir) > -0.99 else tdir * (SpaceShared.HOME_R + 0.05)
			bot.plan_at = ctx.start_at + 1.0 + i * 0.15
			bot.go_at = lerpf(ctx.start_at, aim_end, rnd(0.3, 0.85))
			bot.fuel = fuel
			bots[p.id] = bot
		i += 1
	var init := {"planets": planets, "aimEnd": aim_end, "flightEnd": flight_end, "fuel": fuel, "gravity": gravity, "bump": bool(s.get("bump", true))}
	return {"init": init, "spawns": spawns}


func on_start() -> Dictionary:
	return start_with(randi())


func _launch(id: String) -> void:
	var sp: SP = sps.get(id)
	var t := ctx.now()
	if sp == null or sp.status != "aim" or t < ctx.start_at:
		return
	sp.status = "fly"
	sp.at = t
	ctx.broadcast({"t": "launch", "id": id, "at": t})


func _land(id: String, planet: int) -> void:
	var sp: SP = sps.get(id)
	if sp == null or sp.status != "fly":
		return
	sp.status = "landed"
	sp.planet = planet
	sp.at = ctx.now()
	ctx.broadcast({"t": "landed", "id": id, "planet": planet, "at": sp.at})


func _lose(id: String) -> void:
	var sp: SP = sps.get(id)
	if sp == null or sp.status != "fly":
		return
	sp.status = "lost"
	sp.at = ctx.now()
	ctx.broadcast({"t": "lost", "id": id})


func on_tick(_dt: float) -> void:
	var t := ctx.now()
	if t < ctx.start_at:
		return
	var busy := 0  # encore au sol ou en vol
	for id: String in sps:
		var sp: SP = sps[id]
		if sp.status == "aim" and t >= aim_end:
			_launch(id)  # temps écoulé : décollage automatique
		if sp.status == "aim":
			busy += 1
		elif sp.status == "fly":
			var p: ServerPlayer = ctx.players.get(id)
			if p != null and (t >= flight_end or Vector3(p.p[0], p.p[1], p.p[2]).length() > SpaceShared.OUT_R):
				_lose(id)
			else:
				busy += 1
	if ending_at == 0.0 and busy == 0:
		ending_at = t + (0.0 if t >= flight_end else END_DELAY)
	if ending_at != 0.0 and t >= ending_at:
		ctx.end()


func on_player_message(id: String, msg: Dictionary) -> void:
	match msg.get("t"):
		"launch":
			_launch(id)
		"landed":
			var i: Variant = msg.get("planet")
			var p: ServerPlayer = ctx.players.get(id)
			if p == null or not (i is float or i is int) or int(i) < 0 or int(i) >= planets.size():
				return
			var pl: Dictionary = planets[int(i)]
			if Vector3(p.p[0], p.p[1], p.p[2]).distance_to(SpaceShared.v3(pl["c"])) > float(pl["r"]) + LAND_TOL:
				return
			_land(id, int(i))
		"lost":
			_lose(id)
		"burn":
			var sp: SP = sps.get(id)
			if sp != null and sp.status == "fly":
				var d: Variant = msg.get("d")
				var out := {"t": "burn", "id": id, "on": msg.get("on") == true}
				if d is Array and d.size() == 3 and d.all(func(x: Variant) -> bool: return (x is float or x is int) and is_finite(x) and absf(x) <= 1.5):
					out["d"] = d
				ctx.broadcast(out)


func on_player_leave(id: String) -> void:
	_lose(id)
	sps.erase(id)
	bots.erase(id)


## Classement : points de la planète, puis le premier posé (le chrono part du début de la manche).
func get_results() -> Array:
	var ids: Array = []
	for id: String in sps:
		if ctx.players.has(id):
			ids.append(id)
	var pts := func(id: String) -> int:
		var sp: SP = sps[id]
		return int(planets[sp.planet]["pts"]) if sp.status == "landed" else -1
	ids.sort_custom(func(a: String, b: String) -> bool:
		var pa: int = pts.call(a)
		var pb: int = pts.call(b)
		if pa != pb:
			return pa > pb
		return sps[a].at < sps[b].at)
	var groups: Array = []
	var lost: Array = []
	var home: Array = []
	for id: String in ids:
		var sp: SP = sps[id]
		if sp.status != "landed":
			lost.append({"id": id, "label": "Perdu dans l'espace"})
		elif sp.planet == 0:
			home.append({"id": id, "label": "Retombé au départ"})
		else:
			var pl: Dictionary = planets[sp.planet]
			var secs := ("%.1f s" % (sp.at - ctx.start_at)).replace(".", ",")
			groups.append([{"id": id, "label": "%s · %d pt%s · %s" % [pl["name"], pl["pts"], "s" if int(pl["pts"]) > 1 else "", secs]}])
	if not home.is_empty():
		groups.append(home)
	if not lost.is_empty():
		groups.append(lost)
	return Scoring.ranks_from_groups(groups)


# ---------- bots ----------

## Cherche une direction de tir vers la planète visée, puis y ajoute une petite erreur humaine.
func _plan(bot: Bot) -> void:
	var up := bot.spot.normalized()
	var p0 := bot.spot + up * 0.3
	var tc := SpaceShared.v3(planets[bot.target]["c"])
	var to := (tc - p0).normalized()
	bot.dir = to
	if gravity:
		# l'attraction courbe la trajectoire : on essaie d'autres directions autour de l'axe direct
		var f := SpaceShared.tangent_frame(to)
		var best := INF
		for ax in range(-3, 4):
			for ay in range(-3, 4):
				var d: Vector3 = (to + f[0] * (ax * 0.07) + f[1] * (ay * 0.07)).normalized()
				if d.dot(up) < 0.05:
					continue
				var pr := SpaceShared.predict(p0, d * SpaceShared.SPEED, planets, true, 16.0, 0.1, bot.target)
				var score: float = 0.0 if pr["hit"] == bot.target else pr["closest"] + 1.0
				if score < best:
					best = score
					bot.dir = d
	var axis := bot.dir.cross(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)).normalized()
	if axis.length_squared() > 0.5:
		bot.dir = bot.dir.rotated(axis, deg_to_rad(rnd(0.0, 4.0)))
	bot.planned = true


func bot_tick(pl: ServerPlayer, dt: float) -> void:
	var b := pl.body
	var bot: Bot = bots.get(pl.id)
	var sp: SP = sps.get(pl.id)
	if b == null or bot == null or sp == null:
		return
	var t := ctx.now()
	if not bot.planned and t >= bot.plan_at:
		_plan(bot)
	if sp.status == "aim":
		# marche le long d'un grand cercle jusqu'au point de décollage, puis décolle
		var cur := Vector3(b.px, b.py, b.pz)
		var nxt := bot.spot
		if cur.distance_to(bot.spot) > 0.2:
			var ang := cur.normalized().angle_to(bot.spot.normalized())
			var k := minf(1.0, SpaceShared.WALK * 0.7 * dt / maxf(ang * SpaceShared.HOME_R, 1e-3))
			nxt = cur.normalized().slerp(bot.spot.normalized(), k) * (SpaceShared.HOME_R + 0.05)
		elif bot.planned and t >= bot.go_at:
			_launch(pl.id)
		var vel := (nxt - cur) / dt
		var up := nxt.normalized()
		var fwd := vel - up * vel.dot(up)
		if fwd.length() < 0.1:
			fwd = bot.dir - up * bot.dir.dot(up)
		if fwd.length_squared() > 1e-6:
			pl.yaw = SpaceShared.yaw_of(up, fwd.normalized())
		bot.p = nxt
		if sp.status == "aim":
			_put(b, nxt, vel, true)
			return
	if sp.status == "fly":
		if bot.v == Vector3.ZERO:
			if not bot.planned:
				_plan(bot)
			bot.p = Vector3(b.px, b.py, b.pz) + Vector3(b.px, b.py, b.pz).normalized() * 0.3
			bot.v = bot.dir * SpaceShared.SPEED
			bot.fix_at = t + rnd(1.5, 3.0)
		var turn := Vector3.ZERO
		if t >= bot.fix_at and bot.fuel > 0.0:
			var tc := SpaceShared.v3(planets[bot.target]["c"])
			if not bot.fixing:
				var pr := SpaceShared.predict(bot.p, bot.v, planets, gravity, 16.0, 0.1, bot.target)
				bot.fixing = pr["hit"] != bot.target
				if not bot.fixing:
					bot.fuel = 0.0
			if bot.fixing:
				var to := (tc - bot.p).normalized()
				if bot.v.normalized().angle_to(to) < deg_to_rad(1.0):
					bot.fixing = false
					bot.fuel = 0.0
				else:
					turn = to
					bot.fuel -= dt
		var s := SpaceShared.step(bot.p, bot.v, dt, planets, gravity, turn)
		bot.p = s[0]
		bot.v = s[1]
		var h := SpaceShared.hit(bot.p, bot.v, planets)
		if h >= 0:
			var c := SpaceShared.v3(planets[h]["c"])
			bot.p = c + (bot.p - c).normalized() * (float(planets[h]["r"]) + 0.02)
			_land(pl.id, h)
		elif bot.p.length() > SpaceShared.OUT_R:
			_lose(pl.id)
		_put(b, bot.p, bot.v if sps[pl.id].status == "fly" else Vector3.ZERO, false)
		return
	# posé (ou perdu) : on ne bouge plus
	_put(b, bot.p, Vector3.ZERO, sp.status == "landed")


static func _put(b: Phys.Body, p: Vector3, v: Vector3, grounded: bool) -> void:
	b.px = p.x
	b.py = p.y
	b.pz = p.z
	b.vx = v.x
	b.vy = v.y
	b.vz = v.z
	b.grounded = grounded
