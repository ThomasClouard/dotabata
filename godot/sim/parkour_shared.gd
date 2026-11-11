class_name ParkourShared
extends RefCounted
## Parcours délirant — règles du joueur local, portées de games/parkour/shared.ts.


## Avant le pas de physique : ventilateurs et rafales, gravité réduite, tyroliennes, téléporteurs et canons à joueurs.
## `t` = horloge serveur (rafales). Ordre fixe, identique au TS. Renvoie les PreEvents
## { launched, teleported, grabbed, released } (index d'élément, -1 sinon).
static func pre_step(level: Dictionary, b: Phys.Body, dt: float, t := 0.0) -> Dictionary:
	var ev := {"launched": -1, "teleported": -1, "grabbed": -1, "released": -1}
	var a := Level.fan_accel(level, b.px, b.py, b.pz)
	b.vx += a[0] * dt
	b.vy += a[1] * dt
	b.vz += a[2] * dt
	var w := Level.wind_accel(level, b.px, b.py, b.pz, t)
	b.vx += w[0] * dt
	b.vy += w[1] * dt
	b.vz += w[2] * dt
	var g := Level.lowgrav_at(level, b.px, b.py, b.pz)
	if g < 1.0:
		b.vy += Phys.GRAVITY * (1.0 - g) * dt  # step_body retire g·dt : il reste g·gravity·dt
	var els: Array = level["elements"]
	if b.zip >= 0:
		# suspendu : on avance le long du câble ; au bout, on lâche avec l'élan du câble
		if b.zip >= els.size() or els[b.zip]["type"] != "zipline":
			b.zip = -1
			return ev
		var ze: Dictionary = els[b.zip]
		var cb := Level.zip_cable(ze)
		var sp: float = ze.get("speed", 10.0)
		b.zip_s += sp * dt
		if b.zip_s >= cb["len"]:
			b.zip_s = cb["len"]
			ev["released"] = b.zip
			b.zip = -1
			b.cool = Phys.ZIP_COOL
		_set_zip(b, ze, cb, sp)
		return ev
	for i in els.size():
		var e: Dictionary = els[i]
		var type: String = e["type"]
		if type == "zipline" and b.cool <= 0.0:
			var dx: float = b.px - e["pos"][0]
			var dy: float = b.py + Phys.ZIP_HANG - e["pos"][1]
			var dz: float = b.pz - e["pos"][2]
			if dx * dx + dy * dy + dz * dz > Phys.ZIP_GRAB * Phys.ZIP_GRAB:
				continue
			b.zip = i
			b.zip_s = 0.0
			_set_zip(b, e, Level.zip_cable(e), e.get("speed", 10.0))
			b.flight = 0.0
			b.boost = 0.0
			b.tumble = 0.0
			ev["grabbed"] = i
			return ev
		if type == "teleport" and b.cool <= 0.0 and Level.in_zone(e, b.px, b.py, b.pz):
			var to: Array = e["to"]
			var ex: Array = e.get("exitVel", [0.0, 0.0, 0.0])
			b.set_pos(to[0], to[1], to[2])
			b.vx = ex[0]
			b.vy = ex[1]
			b.vz = ex[2]
			b.cool = Phys.ZIP_COOL
			b.flight = 0.0
			_unground(b)
			ev["teleported"] = i
			return ev
		if type == "launcher" and b.flight <= 0.0 and Level.in_zone(e, b.px, b.py, b.pz):
			var l := Level.launch_velocity([b.px, b.py, b.pz], e["to"], e.get("apex", 3.0), dt)
			b.vx = l[0]
			b.vy = l[1]
			b.vz = l[2]
			b.flight = l[3]
			b.tumble = maxf(b.tumble, l[3])
			_unground(b)
			ev["launched"] = i
			return ev
	return ev


static func _set_zip(b: Phys.Body, e: Dictionary, cb: Dictionary, sp: float) -> void:
	var p := Level.zip_feet(e, b.zip_s)
	var dir: Array = cb["dir"]
	b.set_pos(p[0], p[1], p[2])
	b.vx = dir[0] * sp
	b.vy = dir[1] * sp
	b.vz = dir[2] * sp


static func _unground(b: Phys.Body) -> void:
	b.grounded = false
	b.coyote = 0.0
	b.gvx = 0.0
	b.gvy = 0.0
	b.gvz = 0.0
	b.ground_id = -1


## Coefficient d'éjection (vitesse de l'obstacle × k) et condition de frappe par type d'obstacle (0 = pas de frappe).
static func hit_factor(c: Phys.Contact) -> float:
	var speed := sqrt(c.cvx * c.cvx + c.cvz * c.cvz)
	var side := not c.ground
	match c.tag:
		"hammer":
			return 1.25 if speed > 1.5 else 0.0
		"spinner", "sweeper":
			return 1.4 if side and speed > 1.0 else 0.0
		"cannon", "puncher":
			return 1.1 if side and speed > 2.0 else 0.0
		"wreckingball":
			return 1.3 if speed > 1.5 else 0.0
		"boulder":
			return 1.2 if side and speed > 1.5 else 0.0
		"gate":
			return 1.0 if side and c.cvy < -2.0 else 0.0  # lame qui tombe
	return 0.0


## Réactions aux obstacles touchés pendant le pas : éjection (marteaux, barres, canons, poinçonneurs, guillotines,
## balayeurs, boules), dalles friables, et mort au contact d'un `hazard` (killed : l'appelant renvoie au checkpoint).
## Renvoie { knocked: bool, crumble: Array[int], bounced: bool, killed: bool, hazard: int, boosted: bool }.
static func post_step(b: Phys.Body, contacts: Array) -> Dictionary:
	var knocked := false
	var bounced := false
	var killed := false
	var hazard := -1
	var boosted := false
	var crumble: Array = []
	for c: Phys.Contact in contacts:
		if c.tag == "hazard":
			killed = true
			hazard = c.id
		if c.bounced:
			bounced = true
		if c.tag == "boost" and c.ground:
			boosted = true
		if c.tag == "crumble" and c.ground:
			crumble.append(c.id)
		if b.tumble > 0.4:
			continue  # déjà en train de valser
		if b.shield > 0.0:
			continue  # bouclier : aucune frappe
		var k := hit_factor(c)
		if k <= 0.0:
			continue
		if c.tag == "gate":
			# la lame tombe : on écarte le joueur à l'horizontale (selon la normale, sinon à rebours de sa course, sinon vers +z)
			var dx := c.nx
			var dz := c.nz
			var d := sqrt(dx * dx + dz * dz)
			if d < 0.3:
				dx = -b.vx
				dz = -b.vz
				d = sqrt(dx * dx + dz * dz)
			if d < 0.1:
				dx = 0.0
				dz = 1.0
				d = 1.0
			b.vx = (dx / d) * 7.0
			b.vz = (dz / d) * 7.0
			b.vy = minf(b.vy, 0.0)
		else:
			b.vx = c.cvx * k
			b.vz = c.cvz * k
			b.vy = maxf(b.vy, 5.5)
		b.tumble = 1.1
		b.grounded = false
		b.coyote = 0.0
		knocked = true
	return {"knocked": knocked, "crumble": crumble, "bounced": bounced, "killed": killed, "hazard": hazard, "boosted": boosted}


# —— vague 3 : interactions, objets, pièces ——

const ITEMS := ["super", "shield", "banana", "glove"]
## Réglages des objets et des interactions (serveur ; durées en secondes, distances en mètres).
const ITEM := {
	"superTime": 8.0, "shieldTime": 6.0,
	"bananaBack": 1.2, "bananaArm": 0.6, "bananaR": 0.7, "bananaLife": 60.0,
	"slipSpeed": 9.0, "slipUp": 4.0, "slipTumble": 1.3,
	"gloveRange": 3.5, "gloveDot": 0.4, "gloveV": 13.0, "gloveUp": 6.0, "gloveTumble": 1.1,
}
const ITEM_NAMES := {"super": "Super saut", "shield": "Bouclier", "banana": "Banane", "glove": "Gant de boxe"}


## Met à jour l'état de niveau (Level.new_state) avec un message du serveur. Vrai si le message le concernait.
static func apply_level_msg(st: Dictionary, m: Dictionary, my_id: String) -> bool:
	match m.get("t"):
		"crumble":
			var i := int(m["i"])
			var at: Variant = st["crumbled"].get(i)
			if at == null or absf(at - m["at"]) > 1.0:
				st["crumbled"][i] = float(m["at"])
			return true
		"open":
			st["links"][str(m["link"])] = [float(m["at"]), float(m["until"])]
			return true
		"lever":
			st["levers"][int(m["i"])] = float(m["at"])
			return true
		"tile":
			st["tiles"][Level.memory_key(int(m["i"]), int(m["k"]))] = float(m["at"])
			return true
		"safe":
			st["safe"][Level.memory_key(int(m["i"]), int(m["k"]))] = true
			return true
		"box":
			st["boxes"][int(m["i"])] = float(m["until"])
			return true
		"coin":
			if m["id"] == my_id:
				st["coins"][int(m["i"])] = true
			return true
		"banana":
			st["bananas"][int(m["k"])] = [float(m["p"][0]), float(m["p"][1]), float(m["p"][2])]
			return true
		"bananaGone":
			st["bananas"].erase(int(m["k"]))
			return true
	return false


## Applique au corps local un effet d'objet annoncé par le serveur (super saut, bouclier). Vrai si appliqué.
static func apply_effect_msg(b: Phys.Body, m: Dictionary, my_id: String, now: float) -> bool:
	if m.get("t") != "effect" or m.get("id") != my_id:
		return false
	var left := maxf(0.0, m["until"] - now)
	if m["kind"] == "super":
		b.super_jump = left
	elif m["kind"] == "shield":
		b.shield = left
	else:
		return false
	return true


## Bousculade selon le réglage de la manche (init.jostle) : sans effet si désactivée.
static func parkour_jostle(init: Dictionary, b: Phys.Body, ox: float, oy: float, oz: float, ovx: float, ovz: float) -> bool:
	return init.get("jostle") != false and Phys.jostle(b, ox, oy, oz, ovx, ovz)


## Disposition d'une grille mémoire (serveur seulement ; porté pour les tests) : true = piégée. `rnd` : Callable → [0, 1[.
static func memory_layout(cols: int, rows: int, traps: float, rnd: Callable) -> Array:
	var trap: Array = []
	for k in cols * rows:
		trap.append(rnd.call() < traps)
	var col := floori(rnd.call() * cols)
	for row in rows:
		trap[row * cols + col] = false
		col = maxi(0, mini(cols - 1, col + floori(rnd.call() * 3) - 1))
	return trap


static func format_time(s: float) -> String:
	var m := floori(s / 60.0)
	var r := s - m * 60.0
	return "%d:%s%.1f" % [m, "0" if r < 10.0 else "", r]
