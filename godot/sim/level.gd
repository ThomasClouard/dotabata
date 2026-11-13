class_name Level
extends RefCounted
## Cinématique déterministe des obstacles du parcours, portée de shared/src/level.ts.
## Un niveau est le dictionnaire JSON envoyé par le serveur (valeurs par défaut déjà appliquées).


## Extension du piston d'un canon pousseur (0..1) et sa dérivée par unité de phase.
static func cannon_pulse(u: float) -> Array:
	if u < 0.12:
		return [u / 0.12, 1.0 / 0.12]
	if u < 0.35:
		return [1.0, 0.0]
	if u < 0.75:
		return [1.0 - (u - 0.35) / 0.4, -1.0 / 0.4]
	return [0.0, 0.0]


# —— vague 1 : fonctions pures des sous-parties (portées de shared/src/level.ts) ——

## Types sur lesquels on peut se tenir debout / sans collision / qui frappent (STANDABLE, VISUAL_ONLY, HITTERS).
const STANDABLE := ["start", "finish", "checkpoint", "platform", "ice", "moving", "trampoline", "conveyor", "crumble", "roller", "turntable", "ferris", "pistons", "blink", "mud", "jelly", "ramp", "boost", "jumppad", "bubble", "button", "trapdoor", "memory"]
const VISUAL_ONLY := ["fakewall", "deco", "sign", "fog"]
## Zones sans collision de la vague 2, testées sur la position des pieds (in_zone).
const ZONES := ["launcher", "teleport", "lowgrav", "wind"]
## Types sans aucune boîte de collision.
const NO_BOX := ["fan", "fakewall", "deco", "sign", "fog", "launcher", "teleport", "zipline", "lowgrav", "wind", "lever", "itembox", "coin"]
## Éléments qu'on touche pour les actionner / ramasser (détection serveur).
const PICKUPS := ["lever", "itembox", "coin"]
## Durée de l'animation d'ouverture / fermeture des portes et trappes.
const DOOR_ANIM := 0.3
const HITTERS := ["hammer", "spinner", "cannon", "puncher", "gate", "sweeper", "wreckingball", "boulder", "popper", "rockfall"]


## Partie fractionnaire positive (frac du TS).
static func frac(x: float) -> float:
	return x - floorf(x)


## Morceau mobile (Part du TS) sous forme de boîte sans id ni tag.
static func _part(x: float, y: float, z: float, hx: float, hy: float, hz: float, yaw: float, vx := 0.0, vy := 0.0, vz := 0.0) -> Phys.Col:
	var c := Phys.Col.box(0, x, y, z, hx, hy, hz, yaw)
	c.vx = vx
	c.vy = vy
	c.vz = vz
	return c


## Point local (lx, ly, lz) de l'élément tourné de yaw, en coordonnées monde : [x, y, z].
static func _to_world(e: Dictionary, lx: float, ly: float, lz: float) -> Array:
	var yaw: float = e.get("yaw", 0.0)
	var co := cos(yaw)
	var si := sin(yaw)
	return [e["pos"][0] + lx * co + lz * si, e["pos"][1] + ly, e["pos"][2] - lx * si + lz * co]


## Angle de rotation visuel du rouleau autour de son axe x local (le dessus avance vers +z local si speed > 0).
static func roller_angle(e: Dictionary, t: float) -> float:
	return (e.get("speed", 3.0) * t) / (e["size"][1] / 2.0)


## Blocs du mur poinçonneur (de -x à +x local), qui jaillissent vers +z local, en vague.
static func puncher_blocks(e: Dictionary, t: float) -> Array:
	var out: Array = []
	var count := int(e.get("count", 4))
	var period: float = e.get("period", 3.0)
	var stroke: float = e.get("stroke", 2.5)
	var stagger: float = e.get("stagger", 0.15)
	var phase: float = e.get("phase", 0.0)
	var yaw: float = e.get("yaw", 0.0)
	var size: Array = e["size"]
	var w: float = size[0] / count
	var hw := maxf(0.1, w / 2.0 - 0.05)
	var si := sin(yaw)
	var co := cos(yaw)
	for k in count:
		var pulse := cannon_pulse(frac(t / period + phase + k * stagger))
		var ext: float = pulse[0]
		var sp: float = (pulse[1] * stroke) / period
		var p := _to_world(e, -size[0] / 2.0 + (k + 0.5) * w, 0.0, ext * stroke)
		out.append(_part(p[0], p[1], p[2], hw, size[1] / 2.0, size[2] / 2.0, yaw, si * sp, 0.0, co * sp))
	return out


## Profil de la guillotine : [g, dg/du] (0 = en haut, 1 = en bas). Chute 10 %, en bas 20 %, remontée 40 %, en haut 30 %.
static func gate_profile(u: float) -> Array:
	if u < 0.1:
		return [(u / 0.1) * (u / 0.1), (2.0 * u) / 0.01]
	if u < 0.3:
		return [1.0, 0.0]
	if u < 0.7:
		var s := (u - 0.3) / 0.4
		return [1.0 - s * s * (3.0 - 2.0 * s), -(6.0 * s - 6.0 * s * s) / 0.4]
	return [0.0, 0.0]


## Lame de la guillotine (pos = position haute).
static func gate_part(e: Dictionary, t: float) -> Phys.Col:
	var period: float = e.get("period", 4.0)
	var drop: float = e.get("drop", 3.0)
	var g := gate_profile(frac(t / period + e.get("phase", 0.0)))
	var size: Array = e["size"]
	return _part(e["pos"][0], e["pos"][1] - drop * g[0], e["pos"][2], size[0] / 2.0, size[1] / 2.0, size[2] / 2.0, e.get("yaw", 0.0), 0.0, (-drop * g[1]) / period, 0.0)


## Secondes avant la prochaine chute de la guillotine (0 si elle tombe).
static func gate_until_fall(e: Dictionary, t: float) -> float:
	var period: float = e.get("period", 4.0)
	var u := frac(t / period + e.get("phase", 0.0))
	return 0.0 if u < 0.1 else (1.0 - u) * period


## Angle (lacet) courant d'un élément tournant (turntable, sweeper).
static func spin_angle(e: Dictionary, t: float) -> float:
	var def := 0.8 if e["type"] == "turntable" else 1.3
	return e.get("yaw", 0.0) + e.get("speed", def) * t + e.get("phase", 0.0) * TAU


## Plateau tournant : octogone régulier = 4 boîtes [2r × 2r·tan(π/8)] tournées de 45°, r = 0.97 × rayon.
static func turntable_boxes(e: Dictionary, t: float) -> Array:
	var size: Array = e["size"]
	var r: float = 0.97 * (size[0] / 2.0)
	var a := spin_angle(e, t)
	var out: Array = []
	for k in 4:
		var c := _part(e["pos"][0], e["pos"][1], e["pos"][2], r, size[1] / 2.0, r * tan(PI / 8.0), a + (k * PI) / 4.0)
		c.ang_vel = e.get("speed", 0.8)
		out.append(c)
	return out


## Balayeur double : barre basse (centre pos) puis barre haute perpendiculaire (pos.y + highOffset).
static func sweeper_bars(e: Dictionary, t: float) -> Array:
	var a := spin_angle(e, t)
	var size: Array = e["size"]
	var hi: float = e.get("highOffset", 2.1)
	var low := _part(e["pos"][0], e["pos"][1], e["pos"][2], size[0] / 2.0, size[1] / 2.0, size[2] / 2.0, a)
	var high := _part(e["pos"][0], e["pos"][1] + hi, e["pos"][2], size[0] / 2.0, size[1] / 2.0, size[2] / 2.0, a + PI / 2.0)
	low.ang_vel = e.get("speed", 1.3)
	high.ang_vel = low.ang_vel
	return [low, high]


## Nacelles de la grande roue (restent horizontales), dans le plan (x local, y).
static func ferris_cabins(e: Dictionary, t: float) -> Array:
	var out: Array = []
	var period: float = e.get("period", 14.0)
	var count := int(e.get("count", 4))
	var w := TAU / period
	var rr: float = e.get("radius", 5.0)
	var yaw: float = e.get("yaw", 0.0)
	var phase: float = e.get("phase", 0.0)
	var co := cos(yaw)
	var si := sin(yaw)
	var size: Array = e["size"]
	for k in count:
		var th := TAU * (t / period + phase + float(k) / count)
		var lx := rr * cos(th)
		var ly := rr * sin(th)
		var dlx := -rr * sin(th) * w
		var dly := rr * cos(th) * w
		out.append(_part(e["pos"][0] + lx * co, e["pos"][1] + ly, e["pos"][2] - lx * si, size[0] / 2.0, size[1] / 2.0, size[2] / 2.0, yaw, dlx * co, dly, -dlx * si))
	return out


## Dalles des pistons (de -x à +x local) : montent de 0 à `height` en sinusoïde, dalle k déphasée de k·stagger.
static func piston_slabs(e: Dictionary, t: float) -> Array:
	var out: Array = []
	var count := int(e.get("count", 4))
	var period: float = e.get("period", 3.0)
	var height: float = e.get("height", 2.0)
	var stagger: float = e.get("stagger", 0.25)
	var phase: float = e.get("phase", 0.0)
	var size: Array = e["size"]
	var w: float = size[0] / count
	for k in count:
		var ph := TAU * (t / period + phase + k * stagger)
		var lift := height * (0.5 - 0.5 * cos(ph))
		var vy := (height * 0.5 * sin(ph) * TAU) / period
		var p := _to_world(e, -size[0] / 2.0 + (k + 0.5) * w, lift, 0.0)
		out.append(_part(p[0], p[1], p[2], w / 2.0, size[1] / 2.0, size[2] / 2.0, e.get("yaw", 0.0), 0.0, vy, 0.0))
	return out


## Boule de démolition (pendule conique, pivot pos) : azimut φ = 2π(t/period + phase), de +x vers +z.
static func wrecking_ball(e: Dictionary, t: float) -> Phys.Col:
	var period: float = e.get("period", 4.0)
	var length: float = e.get("length", 6.0)
	var angle: float = e.get("angle", 0.7)
	var phi: float = TAU * (t / period + e.get("phase", 0.0))
	var w := TAU / period
	var rho := length * sin(angle)
	var size: Array = e["size"]
	return _part(e["pos"][0] + rho * cos(phi), e["pos"][1] - length * cos(angle), e["pos"][2] + rho * sin(phi), size[0] / 2.0, size[1] / 2.0, size[2] / 2.0, e.get("yaw", 0.0), -rho * w * sin(phi), 0.0, rho * w * cos(phi))


## Étau : [écart intérieur, dérivée temporelle].
static func crusher_gap(e: Dictionary, t: float) -> Array:
	var period: float = e.get("period", 4.0)
	var min_gap: float = e.get("minGap", 1.4)
	var ph: float = TAU * (t / period + e.get("phase", 0.0))
	var max_g := maxf(e["size"][0], min_gap)
	return [min_gap + (max_g - min_gap) * (0.5 + 0.5 * cos(ph)), (-(max_g - min_gap) * 0.5 * sin(ph) * TAU) / period]


## Les deux murs de l'étau (−x local puis +x local), épaisseur `thickness`.
static func crusher_walls(e: Dictionary, t: float) -> Array:
	var g := crusher_gap(e, t)
	var dgap: float = g[1]
	var th: float = e.get("thickness", 1.0)
	var off: float = g[0] / 2.0 + th / 2.0
	var yaw: float = e.get("yaw", 0.0)
	var co := cos(yaw)
	var si := sin(yaw)
	var size: Array = e["size"]
	var out: Array = []
	for s: float in [-1.0, 1.0]:
		var p := _to_world(e, s * off, 0.0, 0.0)
		out.append(_part(p[0], p[1], p[2], th / 2.0, size[1] / 2.0, size[2] / 2.0, yaw, (s * dgap * co) / 2.0, 0.0, (-s * dgap * si) / 2.0))
	return out


## Dalle clignotante : { solid, u, left } (left = secondes avant le changement d'état).
static func blink_state(e: Dictionary, t: float) -> Dictionary:
	var period: float = e.get("period", 4.0)
	var on: float = e.get("on", 0.6)
	var u := frac(t / period + e.get("phase", 0.0))
	if u < on:
		return {"solid": true, "u": u, "left": (on - u) * period}
	return {"solid": false, "u": u, "left": (1.0 - u) * period}


## Boules en vol : [[boîte, k (0..1 du trajet), roll (angle de roulement)], …], la plus récente d'abord.
static func boulder_balls(e: Dictionary, t: float) -> Array:
	var out: Array = []
	var interval: float = e.get("interval", 4.0)
	var travel: float = e.get("travel", 5.0)
	var delta: Array = e["delta"]
	var s: float = t / interval + e.get("phase", 0.0)
	var f: float = s - floorf(s)
	var r: float = e["size"][0] / 2.0
	var hb := 0.8 * r
	var yaw := atan2(delta[0], delta[2])
	var length := sqrt(delta[0] * delta[0] + delta[1] * delta[1] + delta[2] * delta[2])
	var j := 0
	while (f + j) * interval < travel:
		var k: float = ((f + j) * interval) / travel
		out.append([_part(e["pos"][0] + delta[0] * k, e["pos"][1] + delta[1] * k, e["pos"][2] + delta[2] * k, hb, hb, hb, yaw, delta[0] / travel, delta[1] / travel, delta[2] / travel), k, (length * k) / r])
		j += 1
	return out


# —— vague 4 : castors, jets de lave, chutes de pierres (portées de shared/src/level.ts) ——

const M32 := 0xffffffff
## Temps de pose d'une pierre tombée avant qu'elle s'émiette (s).
const ROCK_REST := 0.4


## Hachage entier déterministe de (a, b) vers [0, 1), identique au TS (hash01) : mêmes tirages partout.
static func hash01(a: int, b: int) -> float:
	var h := ((a * 73856093) & M32) ^ ((b * 19349663) & M32)
	h = h ^ (h >> 16)
	h = (h * 0x45d9f3b) & M32
	h = h ^ (h >> 16)
	h = (h * 0x45d9f3b) & M32
	h = h ^ (h >> 16)
	return float(h) / 4294967296.0


## Sortie d'un castor sur la fraction v de sa sortie : [ext, dext/dv] (jaillit 15 %, reste 60 %, redescend 25 %).
static func popper_profile(v: float) -> Array:
	if v < 0.0 or v >= 1.0:
		return [0.0, 0.0]
	if v < 0.15:
		return [v / 0.15, 1.0 / 0.15]
	if v < 0.75:
		return [1.0, 0.0]
	return [(1.0 - v) / 0.25, -1.0 / 0.25]


## Castor du trou k à l'instant t : { ext, dext (par seconde), warn (va sortir dans < 0.6 s) }. seed = index de l'élément.
static func popper_state(e: Dictionary, k: int, t: float, seed: int) -> Dictionary:
	var period: float = e.get("period", 2.4)
	var up: float = e.get("up", 0.45)
	var chance: float = e.get("chance", 0.45)
	var s: float = t / period + e.get("phase", 0.0) + hash01(seed, k)
	var n := int(floorf(s))
	var u := s - floorf(s)
	var key := seed * 64 + k
	var active := hash01(key, n) < chance
	var pr: Array = popper_profile(u / up) if active else [0.0, 0.0]
	var warn := not active and hash01(key, n + 1) < chance and (1.0 - u) * period < 0.6
	return {"ext": pr[0], "dext": pr[1] / (up * period), "warn": warn}


## Castors sortis : [[boîte, k], …] (le bas de la boîte de l'élément est la surface du plateau).
static func popper_parts(e: Dictionary, t: float, seed: int) -> Array:
	var out: Array = []
	var cols := int(e.get("cols", 3))
	var rows := int(e.get("rows", 3))
	var size: Array = e["size"]
	var pw: float = size[0] / cols
	var pd: float = size[2] / rows
	var hy: float = size[1] / 2.0
	var hw := 0.32 * minf(pw, pd)
	var yaw: float = e.get("yaw", 0.0)
	for row in rows:
		for col in cols:
			var k := row * cols + col
			var st := popper_state(e, k, t, seed)
			var ext: float = st["ext"]
			if ext <= 0.02:
				continue
			var p := _to_world(e, -size[0] / 2.0 + (col + 0.5) * pw, -2.0 * hy * (1.0 - ext), -size[2] / 2.0 + (row + 0.5) * pd)
			out.append([_part(p[0], p[1], p[2], hw, hy, hw, yaw, 0.0, 2.0 * hy * st["dext"], 0.0), k])
	return out


## Jet de lave : { active, u, left, warn } (éruption pendant la fraction on du début de cycle ; warn : dans < 1 s).
static func geyser_state(e: Dictionary, t: float) -> Dictionary:
	var period: float = e.get("period", 4.0)
	var on: float = e.get("on", 0.4)
	var u := frac(t / period + e.get("phase", 0.0))
	if u < on:
		return {"active": true, "u": u, "left": (on - u) * period, "warn": false}
	var left := (1.0 - u) * period
	return {"active": false, "u": u, "left": left, "warn": left < 1.0}


## Pierres de la chute de pierres : [[boîte, k, f (avancement de la chute, ≥ 1 : posée), x, z (point d'impact)], …].
static func rockfall_stones(e: Dictionary, t: float, seed: int) -> Array:
	var out: Array = []
	var interval: float = e.get("interval", 3.0)
	var warn: float = e.get("warn", 1.4)
	var stone: float = e.get("stone", 1.0)
	var count := int(e.get("count", 2))
	var size: Array = e["size"]
	var s: float = t / interval + e.get("phase", 0.0)
	var n := int(floorf(s))
	var tau := (s - floorf(s)) * interval
	var r := stone / 2.0
	var hb := 0.8 * r
	var big_h: float = size[1]
	var ground: float = e["pos"][1] - big_h / 2.0
	for k in count:
		var tk := tau - k * 0.35
		if tk < 0.0 or tk >= warn + ROCK_REST:
			continue
		var key := seed * 16 + k
		var lx := (hash01(key, 2 * n) - 0.5) * maxf(0.0, size[0] - stone)
		var lz := (hash01(key, 2 * n + 1) - 0.5) * maxf(0.0, size[2] - stone)
		var p := _to_world(e, lx, 0.0, lz)
		var f := tk / warn
		var y := ground + r + big_h * (1.0 - f * f) if f < 1.0 else ground + r
		var vy := (-2.0 * big_h * f) / warn if f < 1.0 else 0.0
		out.append([_part(p[0], y, p[2], hb, hb, hb, 0.0, 0.0, vy, 0.0), k, f, p[0], p[2]])
	return out


# —— vague 2 : fonctions pures (physique, rendu, portées de shared/src/level.ts) ——

## Les pieds (x, y, z) sont-ils dans la zone (boîte size centrée sur pos, tournée de yaw) ?
static func in_zone(e: Dictionary, x: float, y: float, z: float) -> bool:
	var yaw: float = e.get("yaw", 0.0)
	var co := cos(yaw)
	var si := sin(yaw)
	var dx: float = x - e["pos"][0]
	var dz: float = z - e["pos"][2]
	var lx := dx * co - dz * si
	var lz := dx * si + dz * co
	return absf(lx) <= e["size"][0] / 2.0 and absf(lz) <= e["size"][2] / 2.0 and absf(y - e["pos"][1]) <= e["size"][1] / 2.0


## Pente de la rampe (m de montée par m le long de z local).
static func ramp_slope(e: Dictionary) -> float:
	return e.get("rise", 2.0) / e["size"][2]


## Hauteur du dessus de la rampe à la verticale de (x, z), z local borné aux bords.
static func ramp_top_at(e: Dictionary, x: float, z: float) -> float:
	var yaw: float = e.get("yaw", 0.0)
	var lz: float = (x - e["pos"][0]) * sin(yaw) + (z - e["pos"][2]) * cos(yaw)
	var q := maxf(-e["size"][2] / 2.0, minf(e["size"][2] / 2.0, lz))
	return e["pos"][1] + e["size"][1] / 2.0 + ramp_slope(e) * q


## Les 8 sommets monde de la rampe : indice ix + 2·iz + 4·iy (0 = côté −, 1 = côté + ; iy 0 dessous, 1 dessus).
static func ramp_corners(e: Dictionary) -> Array:
	var out: Array = []
	var sl := ramp_slope(e)
	var hx: float = e["size"][0] / 2.0
	var hy: float = e["size"][1] / 2.0
	var hz: float = e["size"][2] / 2.0
	for iy in 2:
		for iz in 2:
			for ix in 2:
				var lx := hx if ix else -hx
				var lz := hz if iz else -hz
				out.append(_to_world(e, lx, (hy if iy else -hy) + sl * lz, lz))
	return out


## Vitesse horizontale imposée par un speed pad : [x, z] (dir monde normalisée × speed).
static func boost_vel(e: Dictionary) -> Array:
	var dir: Array = e.get("dir", [0.0, 1.0])
	var sp: float = e.get("speed", 18.0)
	var n := sqrt(dir[0] * dir[0] + dir[1] * dir[1])
	if n == 0.0:
		n = 1.0
	return [(dir[0] / n) * sp, (dir[1] / n) * sp]


## Vitesse monde d'un trampoline directionnel (launch en repère local tourné par yaw).
static func jumppad_vel(e: Dictionary) -> Array:
	var yaw: float = e.get("yaw", 0.0)
	var l: Array = e.get("launch", [0.0, 14.0, 8.0])
	var co := cos(yaw)
	var si := sin(yaw)
	return [l[0] * co + l[2] * si, l[1], -l[0] * si + l[2] * co]


## Tir en cloche de from vers to (pieds), apogée apex au-dessus du plus haut des deux : [vx, vy, vz, T].
static func launch_velocity(from: Array, to: Array, apex: float, dt: float) -> Array:
	var g := Phys.GRAVITY
	var hh := maxf(from[1], to[1]) + apex
	var tt := sqrt((2.0 * (hh - from[1])) / g) + sqrt((2.0 * (hh - to[1])) / g)
	var vy: float = (to[1] - from[1] + 0.5 * g * tt * tt + 0.5 * g * dt * tt) / tt
	return [(to[0] - from[0]) / tt, vy, (to[2] - from[2]) / tt, tt]


## Position à l'instant s d'un tir lancé de from à la vitesse v.
static func ballistic_point(from: Array, v: Array, s: float, dt := 0.0) -> Vector3:
	var g := Phys.GRAVITY
	return Vector3(from[0] + v[0] * s, from[1] + v[1] * s - 0.5 * g * s * s - 0.5 * g * dt * s, from[2] + v[2] * s)


## Trajectoire du canon pour le rendu : n + 1 points de la parabole partant du bas-centre de la zone.
static func launcher_arc(e: Dictionary, n := 24) -> Array:
	var from := [e["pos"][0], e["pos"][1] - e["size"][1] / 2.0, e["pos"][2]]
	var lv := launch_velocity(from, e["to"], e.get("apex", 3.0), 0.0)
	var out: Array = []
	for k in n + 1:
		out.append(ballistic_point(from, lv, (lv[3] * k) / n))
	return out


## Câble de la tyrolienne : { a, b, len, dir } (Array de 3 flottants pour a, b, dir).
static func zip_cable(e: Dictionary) -> Dictionary:
	var to: Array = e["to"]
	var d := [to[0] - e["pos"][0], to[1] - e["pos"][1], to[2] - e["pos"][2]]
	var length := maxf(1e-6, sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]))
	return {"a": [e["pos"][0], e["pos"][1], e["pos"][2]], "b": [to[0], to[1], to[2]], "len": length, "dir": [d[0] / length, d[1] / length, d[2] / length]}


## Pieds d'un joueur suspendu à s m du départ du câble (s borné à [0, len]) : [x, y, z].
static func zip_feet(e: Dictionary, s: float) -> Array:
	var cb := zip_cable(e)
	var a: Array = cb["a"]
	var dir: Array = cb["dir"]
	var q := maxf(0.0, minf(cb["len"], s))
	return [a[0] + dir[0] * q, a[1] + dir[1] * q - Phys.ZIP_HANG, a[2] + dir[2] * q]


## Bulles : [[boîte, u, left], …] ; bulle k monte de pos à pos + rise en period s, left = s avant d'éclater.
static func bubble_parts(e: Dictionary, t: float) -> Array:
	var out: Array = []
	var count := int(e.get("count", 3))
	var rise: float = e.get("rise", 6.0)
	var period: float = e.get("period", 6.0)
	var phase: float = e.get("phase", 0.0)
	var size: Array = e["size"]
	var vy := rise / period
	for k in count:
		var u := frac(t / period + phase + float(k) / count)
		out.append([_part(e["pos"][0], e["pos"][1] + rise * u, e["pos"][2], size[0] / 2.0, size[1] / 2.0, size[2] / 2.0, e.get("yaw", 0.0), 0.0, vy, 0.0), u, (1.0 - u) * period])
	return out


## Intensité d'une rafale (0..1).
static func wind_gust(e: Dictionary, t: float) -> float:
	return 0.5 + 0.5 * sin(TAU * (t / e.get("period", 3.0) + e.get("phase", 0.0)))


## Accélération des rafales aux pieds à l'instant t : [ax, ay, az].
static func wind_accel(level: Dictionary, x: float, y: float, z: float, t: float) -> Array:
	var a := [0.0, 0.0, 0.0]
	for e: Dictionary in level["elements"]:
		if e["type"] != "wind" or not in_zone(e, x, y, z):
			continue
		var k := wind_gust(e, t)
		var f: Array = e.get("force", [24.0, 0.0, 0.0])
		a[0] += f[0] * k
		a[1] += f[1] * k
		a[2] += f[2] * k
	return a


## Facteur de gravité aux pieds : minimum des zones lowgrav qui les contiennent, 1 sinon.
static func lowgrav_at(level: Dictionary, x: float, y: float, z: float) -> float:
	var g := 1.0
	for e: Dictionary in level["elements"]:
		if e["type"] == "lowgrav" and in_zone(e, x, y, z):
			g = minf(g, e.get("gravity", 0.35))
	return g


# —— vague 3 : état de niveau tenu par le serveur (fonctions pures, portées de shared/src/level.ts) ——

## État dynamique du niveau, reconstruit à partir des messages du serveur (ParkourShared.apply_level_msg).
## crumbled : index → instant ; links : lien → [at, until] ; levers : index → instant ; tiles : memory_key → instant de
## chute ; safe : memory_key → true ; boxes : index → réapparition ; coins : index → true (pièces prises par moi) ;
## bananas : clé → [x, y, z].
static func new_state() -> Dictionary:
	return {"crumbled": {}, "links": {}, "levers": {}, "tiles": {}, "safe": {}, "boxes": {}, "coins": {}, "bananas": {}}


## Le lien est-il ouvert à l'instant t (at ≤ t < until) ?
static func link_open(st: Dictionary, link: String, t: float) -> bool:
	var s: Variant = st.get("links", {}).get(link)
	return s != null and t >= s[0] and t < s[1]


## Ouverture visuelle d'une porte / trappe (0 fermée → 1 ouverte).
static func door_openness(e: Dictionary, st: Dictionary, t: float) -> float:
	var s: Variant = st.get("links", {}).get(e["link"])
	if s == null or t < s[0]:
		return 0.0
	if t < s[1]:
		return minf(1.0, (t - s[0]) / DOOR_ANIM)
	return maxf(0.0, 1.0 - (t - s[1]) / DOOR_ANIM)


## Levier abaissé (en recharge) à l'instant t ?
static func lever_down(e: Dictionary, i: int, st: Dictionary, t: float) -> bool:
	var at: Variant = st.get("levers", {}).get(i)
	return at != null and t >= at and t < at + e.get("cooldown", 8.0)


## Boîte surprise présente à l'instant t ?
static func box_ready(i: int, st: Dictionary, t: float) -> bool:
	var until: Variant = st.get("boxes", {}).get(i)
	return until == null or t >= until


## Clé d'une dalle mémoire (élément i, dalle k).
static func memory_key(i: int, k: int) -> int:
	return i * 1024 + k


## Dalles de la grille mémoire : k = row·cols + col (col le long de x local, row le long de z local).
static func memory_tiles(e: Dictionary) -> Array:
	var out: Array = []
	var cols := int(e.get("cols", 3))
	var rows := int(e.get("rows", 5))
	var gap: float = e.get("gap", 0.25)
	var size: Array = e["size"]
	var pw: float = size[0] / cols
	var pd: float = size[2] / rows
	var hx := maxf(0.05, pw / 2.0 - gap / 2.0)
	var hz := maxf(0.05, pd / 2.0 - gap / 2.0)
	for row in rows:
		for col in cols:
			var p := _to_world(e, -size[0] / 2.0 + (col + 0.5) * pw, 0.0, -size[2] / 2.0 + (row + 0.5) * pd)
			out.append(_part(p[0], p[1], p[2], hx, size[1] / 2.0, hz, e.get("yaw", 0.0)))
	return out


## Dalle mémoire à la verticale des pieds (hors joints), -1 sinon.
static func memory_tile_at(e: Dictionary, x: float, z: float) -> int:
	var yaw: float = e.get("yaw", 0.0)
	var co := cos(yaw)
	var si := sin(yaw)
	var dx: float = x - e["pos"][0]
	var dz: float = z - e["pos"][2]
	var size: Array = e["size"]
	var cols := int(e.get("cols", 3))
	var rows := int(e.get("rows", 5))
	var gap: float = e.get("gap", 0.25)
	var lx: float = dx * co - dz * si + size[0] / 2.0
	var lz: float = dx * si + dz * co + size[2] / 2.0
	var pw: float = size[0] / cols
	var pd: float = size[2] / rows
	var col := floori(lx / pw)
	var row := floori(lz / pd)
	if col < 0 or col >= cols or row < 0 or row >= rows:
		return -1
	var hx := maxf(0.05, pw / 2.0 - gap / 2.0)
	var hz := maxf(0.05, pd / 2.0 - gap / 2.0)
	if absf(lx - (col + 0.5) * pw) > hx or absf(lz - (row + 0.5) * pd) > hz:
		return -1
	return row * cols + col


## Dalles qui portent la capsule (pieds en x, z) : celle sous les pieds, sinon (joint) toutes celles à moins de r. Serveur.
static func memory_tiles_under(e: Dictionary, x: float, z: float, r := Phys.RADIUS * 0.9) -> Array:
	var k := memory_tile_at(e, x, z)
	if k >= 0:
		return [k]
	var yaw: float = e.get("yaw", 0.0)
	var co := cos(yaw)
	var si := sin(yaw)
	var dx: float = x - e["pos"][0]
	var dz: float = z - e["pos"][2]
	var size: Array = e["size"]
	var cols := int(e.get("cols", 3))
	var rows := int(e.get("rows", 5))
	var gap: float = e.get("gap", 0.25)
	var lx: float = dx * co - dz * si + size[0] / 2.0
	var lz: float = dx * si + dz * co + size[2] / 2.0
	var pw: float = size[0] / cols
	var pd: float = size[2] / rows
	var hx := maxf(0.05, pw / 2.0 - gap / 2.0)
	var hz := maxf(0.05, pd / 2.0 - gap / 2.0)
	var out: Array = []
	for row in rows:
		for col in cols:
			var ex := maxf(0.0, absf(lx - (col + 0.5) * pw) - hx)
			var ez := maxf(0.0, absf(lz - (row + 0.5) * pd) - hz)
			if ex * ex + ez * ez <= r * r:
				out.append(row * cols + col)
	return out


## Les pieds sont-ils posés sur le dessus de l'élément (empreinte tournée, ±0.35 m du dessus) ?
static func stands_on(e: Dictionary, x: float, y: float, z: float) -> bool:
	var yaw: float = e.get("yaw", 0.0)
	var dx: float = x - e["pos"][0]
	var dz: float = z - e["pos"][2]
	var lx := dx * cos(yaw) - dz * sin(yaw)
	var lz := dx * sin(yaw) + dz * cos(yaw)
	return absf(lx) <= e["size"][0] / 2.0 and absf(lz) <= e["size"][2] / 2.0 and absf(y - top_of(e)) <= 0.35


## Le corps (capsule debout aux pieds) touche-t-il la boîte de l'élément ?
static func touches(e: Dictionary, x: float, y: float, z: float) -> bool:
	var yaw: float = e.get("yaw", 0.0)
	var dx: float = x - e["pos"][0]
	var dz: float = z - e["pos"][2]
	var lx := dx * cos(yaw) - dz * sin(yaw)
	var lz := dx * sin(yaw) + dz * cos(yaw)
	var r := Phys.RADIUS
	return absf(lx) <= e["size"][0] / 2.0 + r and absf(lz) <= e["size"][2] / 2.0 + r and y <= e["pos"][1] + e["size"][1] / 2.0 and y + Phys.HEIGHT >= e["pos"][1] - e["size"][1] / 2.0


## Boîtes de collision du niveau à l'instant `t` (horloge serveur). Fonction pure.
## `state` : état de niveau (new_state) ou, ancienne forme, index de dalle friable → instant du déclenchement.
static func build_colliders(level: Dictionary, t: float, state: Dictionary = {}) -> Array:
	var st: Dictionary = state if state.has("links") or state.has("crumbled") or state.has("tiles") else {"crumbled": state}
	var crumbled: Dictionary = st.get("crumbled", {})
	var tiles: Dictionary = st.get("tiles", {})
	var out: Array = []
	var els: Array = level["elements"]
	for i in els.size():
		var e: Dictionary = els[i]
		var type: String = e["type"]
		if type in NO_BOX:
			continue  # zones et décor : pas de collision
		# un élément peut produire plusieurs boîtes (même id), émises dans l'ordre de ses sous-parties
		var ps: Variant = null
		match type:
			"puncher":
				ps = puncher_blocks(e, t)
			"turntable":
				ps = turntable_boxes(e, t)
			"sweeper":
				ps = sweeper_bars(e, t)
			"ferris":
				ps = ferris_cabins(e, t)
			"pistons":
				ps = piston_slabs(e, t)
			"crusher":
				ps = crusher_walls(e, t)
			"boulder":
				ps = []
				for b: Array in boulder_balls(e, t):
					ps.append(b[0])
			"wreckingball":
				ps = [wrecking_ball(e, t)]
			"gate":
				ps = [gate_part(e, t)]
			"popper":
				ps = []
				for b: Array in popper_parts(e, t, i):
					ps.append(b[0])
			"rockfall":
				ps = []
				for b: Array in rockfall_stones(e, t, i):
					ps.append(b[0])
			"geyser":
				if not geyser_state(e, t)["active"]:
					continue
			"door", "trapdoor":
				if link_open(st, e["link"], t):
					continue  # ouverte : escamotée
			"memory":
				ps = []
				var ts := memory_tiles(e)
				for k in ts.size():
					var at: Variant = tiles.get(memory_key(i, k))
					if at == null or t < at:
						ps.append(ts[k])
			"bubble":
				ps = []
				for b: Array in bubble_parts(e, t):
					ps.append(b[0])
			"blink":
				if not blink_state(e, t)["solid"]:
					continue
		if ps != null:
			for p: Phys.Col in ps:
				p.id = i
				p.tag = type
				out.append(p)
			continue
		var pos: Array = e["pos"]
		var size: Array = e["size"]
		var px: float = pos[0]
		var py: float = pos[1]
		var pz: float = pos[2]
		var col := Phys.Col.new()
		col.id = i
		col.tag = type
		col.cx = px
		col.cy = py
		col.cz = pz
		col.hx = size[0] / 2.0
		col.hy = size[1] / 2.0
		col.hz = size[2] / 2.0
		col.yaw = e.get("yaw", 0.0)
		match type:
			"roller":
				# tapis perpendiculaire à l'axe du rouleau : direction +z local
				var sp: float = e.get("speed", 3.0)
				col.has_conv = true
				col.conv_x = sin(col.yaw) * sp
				col.conv_z = cos(col.yaw) * sp
			"moving":
				var period: float = e.get("period", 4.0)
				var delta: Array = e["delta"]
				var ph: float = (t / period + e.get("phase", 0.0)) * TAU
				var k := 0.5 - 0.5 * cos(ph)
				var dk := (0.5 * sin(ph) * TAU) / period
				col.cx = px + delta[0] * k
				col.cy = py + delta[1] * k
				col.cz = pz + delta[2] * k
				col.vx = delta[0] * dk
				col.vy = delta[1] * dk
				col.vz = delta[2] * dk
			"spinner":
				var speed: float = e.get("speed", 1.5)
				col.yaw = col.yaw + speed * t + e.get("phase", 0.0) * TAU
				col.ang_vel = speed
			"hammer":
				var period: float = e.get("period", 3.0)
				var amp: float = e.get("amplitude", 1.1)
				var ph: float = (t / period + e.get("phase", 0.0)) * TAU
				var a := amp * sin(ph)
				var da := (amp * cos(ph) * TAU) / period
				var strike := int(e.get("strike", 0))
				if strike != 0:
					# marteau qui tape : de la verticale (en haut) à l'horizontale (posé), au rythme d'une guillotine
					var gp := gate_profile(frac(t / period + e.get("phase", 0.0)))
					a = strike * (PI - (PI / 2.0) * gp[0])
					da = (-strike * (PI / 2.0) * gp[1]) / period
				var ax := 1.0 if e.get("axis", "x") == "x" else 0.0
				var az := 1.0 - ax
				var l: float = e.get("length", 5.0)
				col.cx = px + ax * sin(a) * l
				col.cy = py - cos(a) * l
				col.cz = pz + az * sin(a) * l
				col.vx = ax * cos(a) * l * da
				col.vy = sin(a) * l * da
				col.vz = az * cos(a) * l * da
			"cannon":
				var period: float = e.get("period", 3.0)
				var stroke: float = e.get("stroke", 3.0)
				var dir: Array = e["dir"]
				var u := fposmod(t / period + e.get("phase", 0.0), 1.0)
				var pulse := cannon_pulse(u)
				var ext: float = pulse[0]
				var dext: float = pulse[1]
				var n := sqrt(dir[0] * dir[0] + dir[1] * dir[1])
				if n == 0.0:
					n = 1.0
				var dx: float = dir[0] / n
				var dz: float = dir[1] / n
				var sp := (dext * stroke) / period
				col.cx = px + dx * ext * stroke
				col.cz = pz + dz * ext * stroke
				col.vx = dx * sp
				col.vz = dz * sp
			"crumble":
				if crumbled.has(i):
					var at: float = crumbled[i]
					var delay: float = e.get("delay", 0.5)
					if t > at + delay and t < at + delay + e.get("respawn", 4.0):
						continue
			"mud":
				col.slow = e.get("slow", 0.45)
				col.jump = e.get("jumpFactor", 0.6)
			"jelly":
				col.jelly = e.get("bounciness", 0.6)
				col.jump = e.get("jumpFactor", 1.2)
			"ramp":
				col.slope = ramp_slope(e)
				col.slide = e.get("slide", false)
			"boost":
				var bv := boost_vel(e)
				col.has_boost = true
				col.boost_x = bv[0]
				col.boost_z = bv[1]
			"jumppad":
				var jv := jumppad_vel(e)
				col.has_launch = true
				col.launch_x = jv[0]
				col.launch_y = jv[1]
				col.launch_z = jv[2]
			"trampoline":
				col.bounce = e.get("bounce", 15.0)
			"ice":
				col.ice = true
			"conveyor":
				var dir: Array = e["dir"]
				var speed: float = e.get("speed", 4.0)
				var n := sqrt(dir[0] * dir[0] + dir[1] * dir[1])
				if n == 0.0:
					n = 1.0
				col.has_conv = true
				col.conv_x = (dir[0] / n) * speed
				col.conv_z = (dir[1] / n) * speed
		out.append(col)
	return out


## Accélération des ventilateurs à la position des pieds du personnage : [ax, ay, az].
static func fan_accel(level: Dictionary, x: float, y: float, z: float) -> Array:
	var ax := 0.0
	var ay := 0.0
	var az := 0.0
	for e: Dictionary in level["elements"]:
		if e["type"] != "fan":
			continue
		var pos: Array = e["pos"]
		var size: Array = e["size"]
		if absf(x - pos[0]) <= size[0] / 2.0 and absf(z - pos[2]) <= size[2] / 2.0 and absf(y + 0.75 - pos[1]) <= size[1] / 2.0:
			var f: Array = e.get("force", [0.0, 42.0, 0.0])
			ax += f[0]
			ay += f[1]
			az += f[2]
	return [ax, ay, az]


## Le joueur (pieds en x, y, z) est-il sur (ou juste au-dessus de) cette dalle ? Checkpoints et arrivée.
static func on_pad(e: Dictionary, x: float, y: float, z: float) -> bool:
	var yaw: float = e.get("yaw", 0.0)
	var co := cos(yaw)
	var si := sin(yaw)
	var dx: float = x - e["pos"][0]
	var dz: float = z - e["pos"][2]
	var lx := dx * co - dz * si
	var lz := dx * si + dz * co
	var top := top_of(e)
	return absf(lx) <= e["size"][0] / 2.0 + 0.3 and absf(lz) <= e["size"][2] / 2.0 + 0.3 and y > top - 0.6 and y < top + 3.5


static func top_of(e: Dictionary) -> float:
	return e["pos"][1] + e["size"][1] / 2.0


## Point le plus bas atteint par un élément (pour killY).
static func element_bottom(e: Dictionary) -> float:
	var b: float = e["pos"][1] - e["size"][1] / 2.0
	match e["type"]:
		"gate":
			return b - e.get("drop", 3.0)
		"ferris":
			return b - e.get("radius", 5.0)
		"wreckingball":
			return b - e.get("length", 6.0) * cos(e.get("angle", 0.7))
		"boulder":
			return minf(b, b + e["delta"][1])
		"ramp":
			return b - absf(e.get("rise", 2.0)) / 2.0
		"zipline":
			return minf(b, minf(e["pos"][1], e["to"][1]) - Phys.ZIP_HANG)
	return b


## Altitude sous laquelle on est tombé (le décor, les panneaux, le brouillard et les faux murs ne comptent pas).
static func kill_y(level: Dictionary) -> float:
	if level.get("killY") != null:
		return level["killY"]
	var mn := INF
	for e: Dictionary in level["elements"]:
		if not e["type"] in VISUAL_ONLY:
			mn = minf(mn, element_bottom(e))
	return mn - 12.0


## Brouillard au point (x, y, z) : { density, color } de la zone `fog` la plus dense qui le contient, ou null.
static func fog_at(level: Dictionary, x: float, y: float, z: float) -> Variant:
	var best: Variant = null
	for e: Dictionary in level["elements"]:
		if e["type"] != "fog":
			continue
		var yaw: float = e.get("yaw", 0.0)
		var co := cos(yaw)
		var si := sin(yaw)
		var dx: float = x - e["pos"][0]
		var dz: float = z - e["pos"][2]
		var lx := dx * co - dz * si
		var lz := dx * si + dz * co
		if absf(lx) > e["size"][0] / 2.0 or absf(lz) > e["size"][2] / 2.0 or absf(y - e["pos"][1]) > e["size"][1] / 2.0:
			continue
		var d: float = e.get("density", 0.6)
		if best == null or d > best["density"]:
			best = {"density": d, "color": e.get("color")}
	return best


static func find_type(level: Dictionary, type: String) -> int:
	var els: Array = level["elements"]
	for i in els.size():
		if els[i]["type"] == type:
			return i
	return -1
