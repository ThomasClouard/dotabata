class_name SpaceShared
extends RefCounted
## Saut cosmique — règles communes au client (joueur local) et au serveur (bots) : planètes, gravité, vol.
## Une planète : {c: [x, y, z], r, pts, name, color, ring}. La planète 0 est celle du départ (centre à l'origine).

const HOME_R := 12.0
const SURF_G := 22.0  # gravité à la surface de la planète de départ (m/s²)
const K := SURF_G / HOME_R  # GM = K·r³ : la gravité de surface est proportionnelle au rayon
const SPEED := 15.0  # vitesse de vol, toujours la même : lente, pour avoir le temps de rectifier
const FLY_G := 0.15  # en vol, l'attraction ne fait que courber la trajectoire (fraction de la gravité de marche)
const TURN := deg_to_rad(6.0)  # rétro-fusées : rotation de la trajectoire vers la direction regardée (rad/s) ; 1,5 s de carburant ≈ 9°
const WALK := 6.0
const JUMP := 8.0
const ELEV_MIN := deg_to_rad(5.0)
const ELEV_MAX := deg_to_rad(85.0)
const OUT_R := 420.0  # au-delà : perdu dans l'espace
const PREVIEW_T := 1.0  # durée de vol montrée par les pointillés
const BUMP_R := 1.0  # distance de contact entre deux joueurs en vol

const NAMES := ["Petite Lune", "Caillou Bleu", "Planète Pastèque", "Boule Givrée", "Planète Bonbon", "Gros Nuage",
	"Planète Fromage", "Rocher Rouillé", "Planète Disco", "Géante Mauve", "Planète Myrtille", "Astéroïde Pépère",
	"Planète Biscuit", "Boule de Gomme", "Lune Pistache", "Planète Chaussette"]
const COLORS := [0xff6b6b, 0x4dabf7, 0x69db7c, 0xffd43b, 0xda77f2, 0xff922b, 0x63e6be, 0xf783ac, 0xa9e34b, 0x748ffc]


static func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Planète de départ + `n` planètes d'arrivée, de plus en plus loin, petites et rentables. Déterministe pour une graine.
static func layout(seed_: int, n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var out: Array = [{"c": [0.0, 0.0, 0.0], "r": HOME_R, "pts": 0, "name": "Départ", "color": 0x6fcf6a, "ring": false}]
	# « couloirs » bien répartis (spirale de Fibonacci tournée au hasard) : chacun aligne une planète proche et, un peu
	# décalée, une plus lointaine, sur laquelle on peut encore se rattraper si on rate la première
	var lanes := ceili(n / 2.0)
	var lane_dirs: Array = []
	var spin := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
	for i in lanes:
		var y := 1.0 - 2.0 * (i + 0.5) / lanes
		var rr := sqrt(maxf(0.0, 1.0 - y * y))
		var a := i * 2.399963
		lane_dirs.append(spin * Vector3(cos(a) * rr, y, sin(a) * rr))
	for i in range(lanes - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector3 = lane_dirs[i]
		lane_dirs[i] = lane_dirs[j]
		lane_dirs[j] = tmp
	var dirs: Array = []
	for i in n:
		var d: Vector3 = lane_dirs[i % lanes]
		if i >= lanes:
			var side := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized().rotated(d, rng.randf() * TAU)
			d = d.rotated(side, deg_to_rad(rng.randf_range(7.0, 13.0)))
		dirs.append(d)
	var names := NAMES.duplicate()
	for i in range(names.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = names[i]
		names[i] = names[j]
		names[j] = tmp
	for i in n:
		var k := float(i) / maxf(1.0, n - 1.0)
		var d := lerpf(42.0, 190.0, k) + rng.randf_range(-6.0, 6.0)
		var c: Vector3 = dirs[i] * d
		out.append({
			"c": [snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01)],
			"r": snappedf(lerpf(8.0, 3.5, k), 0.01),
			"pts": 1 + floori(k * 4.999),
			"name": names[i % names.size()],
			"color": COLORS[rng.randi_range(0, COLORS.size() - 1)],
			"ring": rng.randf() < 0.35,
		})
	return out


static func gm(pl: Dictionary) -> float:
	var r: float = pl["r"]
	return K * r * r * r


## Accélération gravitationnelle en `p` (somme de toutes les planètes).
static func accel(p: Vector3, planets: Array) -> Vector3:
	var a := Vector3.ZERO
	for pl: Dictionary in planets:
		var d := v3(pl["c"]) - p
		var d2 := maxf(d.length_squared(), 1.0)
		a += d * (gm(pl) / (d2 * sqrt(d2)))
	return a


## Planète la plus proche de `p` (distance à la surface) : son index.
static func nearest(p: Vector3, planets: Array) -> int:
	var best := 0
	var bd := INF
	for i in planets.size():
		var d := p.distance_to(v3(planets[i]["c"])) - float(planets[i]["r"])
		if d < bd:
			bd = d
			best = i
	return best


## Vertical local : depuis le centre de la planète la plus proche.
static func up_at(p: Vector3, planets: Array) -> Vector3:
	var u := p - v3(planets[nearest(p, planets)]["c"])
	return u.normalized() if u.length_squared() > 1e-6 else Vector3.UP


## Planète touchée en `p` en se dirigeant vers elle (vitesse `v`), ou -1. On ignore les sorties (décollage).
static func hit(p: Vector3, v: Vector3, planets: Array) -> int:
	for i in planets.size():
		var d := p - v3(planets[i]["c"])
		if d.length() <= float(planets[i]["r"]) and d.dot(v) < 0.0:
			return i
	return -1


## Un pas de vol. La vitesse garde toujours la même norme (SPEED) : l'attraction courbe la trajectoire, et les
## rétro-fusées (turn_to : direction regardée, ou zéro) la font tourner sans jamais accélérer. Renvoie [p, v].
static func step(p: Vector3, v: Vector3, dt: float, planets: Array, gravity: bool, turn_to := Vector3.ZERO) -> Array:
	if gravity:
		v += accel(p, planets) * FLY_G * dt
	if turn_to != Vector3.ZERO and v.length_squared() > 1e-6:
		var ang := v.angle_to(turn_to)
		if ang > 1e-4:
			var axis := v.cross(turn_to)
			if axis.length_squared() < 1e-8:
				axis = tangent_frame(v.normalized())[0]
			v = v.rotated(axis.normalized(), minf(ang, TURN * dt))
	v = v.normalized() * SPEED if v.length_squared() > 1e-6 else Vector3.UP * SPEED
	p += v * dt
	return [p, v]


## Trajectoire sans poussée sur `t` secondes : {pts: PackedVector3Array, hit: index ou -1, at: instant du contact,
## closest: [index de planète, distance minimale à sa surface] pour la planète `target` (-1 : aucune)}.
static func predict(p: Vector3, v: Vector3, planets: Array, gravity: bool, t: float, dt := 1.0 / 30.0, target := -1) -> Dictionary:
	var pts := PackedVector3Array([p])
	var closest := INF
	var tc := v3(planets[target]["c"]) if target >= 0 else Vector3.ZERO
	var tr: float = planets[target]["r"] if target >= 0 else 0.0
	var e := 0.0
	while e < t:
		var s := step(p, v, dt, planets, gravity)
		p = s[0]
		v = s[1]
		e += dt
		pts.append(p)
		if target >= 0:
			closest = minf(closest, p.distance_to(tc) - tr)
		var h := hit(p, v, planets)
		if h >= 0:
			return {"pts": pts, "hit": h, "at": e, "closest": closest}
		if p.length() > OUT_R:
			break
	return {"pts": pts, "hit": -1, "at": e, "closest": closest}


## Direction de tir depuis le point `p` de la surface : cap `fwd` (tangent) et élévation `elev` (radians).
static func aim_dir(up: Vector3, fwd: Vector3, elev: float) -> Vector3:
	return (fwd * cos(elev) + up * sin(elev)).normalized()


## Repère tangent de référence, pour transmettre un cap sous forme d'angle (yaw réseau).
static func tangent_frame(up: Vector3) -> Array:
	var ref := Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD
	var e1 := (ref - up * ref.dot(up)).normalized()
	return [e1, up.cross(e1)]


static func yaw_of(up: Vector3, fwd: Vector3) -> float:
	var f := tangent_frame(up)
	return atan2(fwd.dot(f[1]), fwd.dot(f[0]))


static func fwd_of(up: Vector3, yaw: float) -> Vector3:
	var f := tangent_frame(up)
	return (f[0] * cos(yaw) + f[1] * sin(yaw)).normalized()
