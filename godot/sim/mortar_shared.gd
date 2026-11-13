class_name MortarShared
extends RefCounted
## Abri & mortier — constantes, géométrie de l'arène et balistique, portées de games/mortar/shared.ts.

const ISLAND := 12.0  # côté d'une île (m)
const THICK := 1.5
const GRID := 8  # cases constructibles par côté
const MAX_H := 4
const G := 18.0
const ELEV := 60.0 * PI / 180.0
const V_MIN := 8.0
const V_MAX := 40.0
const CHARGE_TIME := 1.3
const RELOAD := 1.3
const ZONE_R0 := 8.6
const ZONE_R1 := 2.0

const MATS := {
	"wood": {"cost": 1, "hp": 1, "name": "Bois", "color": 0xc98a4b},
	"stone": {"cost": 2, "hp": 3, "name": "Pierre", "color": 0x9aa3ad},
	"tramp": {"cost": 3, "hp": 2, "name": "Trampoline", "color": 0x39c5ff},
}
const MAT_KEYS := ["wood", "stone", "tramp"]
## Obus : rayon d'explosion, dégâts aux joueurs, dégâts aux blocs, rayon du trou creusé dans l'île (option).
const SHELLS := {
	"normal": {"r": 2.6, "dmg": 38.0, "block": 1, "hole": 1.1},
	"mega": {"r": 4.6, "dmg": 70.0, "block": 3, "hole": 1.9},
	"cluster": {"r": 1.6, "dmg": 15.0, "block": 1, "hole": 0.8},
	"sub": {"r": 1.9, "dmg": 24.0, "block": 1, "hole": 0.75},
}
## Trous dans les îles : l'île est découpée en cases de HOLE_CELL m (HOLE_N × HOLE_N) qu'une explosion au sol peut
## détruire. Les trous d'une île : holes[plot] = {Vector2i(cx, cz): true}.
const HOLE_CELL := 0.5
const HOLE_N := 24  # ISLAND / HOLE_CELL


static func block_key(plot: int, x: int, y: int, z: int) -> String:
	return "%d:%d:%d:%d" % [plot, x, y, z]


static func ring_radius(n: int) -> float:
	if n < 2:
		return 13.0
	# les coins intérieurs de deux îles voisines doivent rester hors de portée de saut
	var a := PI / n
	var half := ISLAND / 2.0
	return maxf(13.0, half + (3.0 + half * cos(a)) / sin(a))


## Chaque île est tournée face au centre de l'arène.
static func plot_yaw(i: int, n: int) -> float:
	return (float(i) / n) * TAU


static func plot_cx(i: int, n: int) -> float:
	return sin((float(i) / n) * TAU) * ring_radius(n)


static func plot_cz(i: int, n: int) -> float:
	return cos((float(i) / n) * TAU) * ring_radius(n)


static func plot_center(i: int, n: int) -> Vector3:
	return Vector3(plot_cx(i, n), 0.0, plot_cz(i, n))


## Monde → repère de l'île : [lx, lz].
static func to_local(plot: int, n: int, x: float, z: float) -> Array:
	var a := plot_yaw(plot, n)
	var co := cos(a)
	var si := sin(a)
	var dx := x - plot_cx(plot, n)
	var dz := z - plot_cz(plot, n)
	return [dx * co - dz * si, dx * si + dz * co]


## Repère de l'île → monde : [x, z].
static func to_world(plot: int, n: int, lx: float, lz: float) -> Array:
	var a := plot_yaw(plot, n)
	var co := cos(a)
	var si := sin(a)
	return [plot_cx(plot, n) + lx * co + lz * si, plot_cz(plot, n) - lx * si + lz * co]


## Centre d'un bloc : [x, y, z].
static func block_center(plot: int, bx: int, by: int, bz: int, n: int) -> Array:
	var w := to_world(plot, n, bx - (GRID - 1) / 2.0, bz - (GRID - 1) / 2.0)
	return [w[0], by + 0.5, w[1]]


## Case de la grille sous un point monde : Vector2i, ou null hors grille.
static func cell_at(plot: int, n: int, x: float, z: float) -> Variant:
	var l := to_local(plot, n, x, z)
	var cx := floori(l[0] + GRID / 2.0)
	var cz := floori(l[1] + GRID / 2.0)
	if cx >= 0 and cz >= 0 and cx < GRID and cz < GRID:
		return Vector2i(cx, cz)
	return null


static func column_height(blocks: Dictionary, plot: int, x: int, z: int) -> int:
	var h := 0
	while h < MAX_H and blocks.has(block_key(plot, x, h, z)):
		h += 1
	return h


## Case de trou (repère de l'île) sous un point monde, ou null hors de l'île.
static func hole_cell_at(plot: int, n: int, x: float, z: float) -> Variant:
	var l := to_local(plot, n, x, z)
	var cx := floori((l[0] + ISLAND / 2.0) / HOLE_CELL)
	var cz := floori((l[1] + ISLAND / 2.0) / HOLE_CELL)
	if cx >= 0 and cz >= 0 and cx < HOLE_N and cz < HOLE_N:
		return Vector2i(cx, cz)
	return null


## Le sol de l'île manque-t-il sous ce point ?
static func is_hole(holes: Dictionary, plot: int, n: int, x: float, z: float) -> bool:
	var h: Dictionary = holes.get(plot, {})
	if h.is_empty():
		return false
	var c: Variant = hole_cell_at(plot, n, x, z)
	return c != null and h.has(c)


## Centre (repère de l'île) d'une case de trou : [lx, lz].
static func hole_cell_center(c: Vector2i) -> Array:
	return [-ISLAND / 2.0 + (c.x + 0.5) * HOLE_CELL, -ISLAND / 2.0 + (c.y + 0.5) * HOLE_CELL]


## Cases dont le centre est à moins de « r » du point monde (x, z) : les cases que l'explosion arrache.
static func hole_cells(plot: int, n: int, x: float, z: float, r: float) -> Array:
	var l := to_local(plot, n, x, z)
	var out: Array = []
	var k := ceili(r / HOLE_CELL) + 1
	var c0 := Vector2i(floori((l[0] + ISLAND / 2.0) / HOLE_CELL), floori((l[1] + ISLAND / 2.0) / HOLE_CELL))
	for dz in range(-k, k + 1):
		for dx in range(-k, k + 1):
			var c := Vector2i(c0.x + dx, c0.y + dz)
			if c.x < 0 or c.y < 0 or c.x >= HOLE_N or c.y >= HOLE_N:
				continue
			var cc := hole_cell_center(c)
			if Vector2(cc[0] - l[0], cc[1] - l[1]).length() <= r:
				out.append(c)
	return out


## Sol d'une île trouée en rectangles pleins (repère de l'île, en cases) : [[cx0, cz0, cx1, cz1], …] bornes exclues.
## Par lignes de cases pleines contiguës, fusionnées avec la ligne du dessous quand elles ont la même étendue.
static func island_rects(h: Dictionary) -> Array:
	if h.is_empty():
		return [[0, 0, HOLE_N, HOLE_N]]
	var out: Array = []
	var open := {}  # Vector2i(cx0, cx1) → index dans out (rectangle encore extensible)
	for cz in HOLE_N:
		var runs: Array = []
		var cx := 0
		while cx < HOLE_N:
			if h.has(Vector2i(cx, cz)):
				cx += 1
				continue
			var s := cx
			while cx < HOLE_N and not h.has(Vector2i(cx, cz)):
				cx += 1
			runs.append(Vector2i(s, cx))
		var next := {}
		for r: Vector2i in runs:
			if open.has(r):
				var idx: int = open[r]
				out[idx][3] = cz + 1
				next[r] = idx
			else:
				out.append([r.x, cz, r.y, cz + 1])
				next[r] = out.size() - 1
		open = next
	return out


## Collisions : toutes les îles (trouées selon « holes ») + les blocs de la parcelle indiquée.
static func colliders(n: int, blocks: Dictionary, plot: int, holes: Dictionary = {}) -> Array:
	var out: Array = []
	var rid := 10000
	for i in n:
		var h: Dictionary = holes.get(i, {})
		if h.is_empty():
			out.append(Phys.Col.box(i, plot_cx(i, n), -THICK / 2.0, plot_cz(i, n), ISLAND / 2.0, THICK / 2.0, ISLAND / 2.0, plot_yaw(i, n), "island"))
			continue
		for r: Array in island_rects(h):
			var lx: float = -ISLAND / 2.0 + (r[0] + r[2]) * HOLE_CELL / 2.0
			var lz: float = -ISLAND / 2.0 + (r[1] + r[3]) * HOLE_CELL / 2.0
			var w := to_world(i, n, lx, lz)
			out.append(Phys.Col.box(rid, w[0], -THICK / 2.0, w[1], (r[2] - r[0]) * HOLE_CELL / 2.0, THICK / 2.0, (r[3] - r[1]) * HOLE_CELL / 2.0, plot_yaw(i, n), "island"))
			rid += 1
	var id := 1000
	for b: Dictionary in blocks.values():
		if b["plot"] != plot:
			continue
		var c := block_center(plot, b["x"], b["y"], b["z"], n)
		var col := Phys.Col.box(id, c[0], c[1], c[2], 0.5, 0.5, 0.5, plot_yaw(plot, n), b["mat"])
		if b["mat"] == "tramp":
			col.bounce = 13.0
		out.append(col)
		id += 1
	return out


# ---------- Balistique ----------

static func launch_speed(power: float) -> float:
	return V_MIN + (V_MAX - V_MIN) * clampf(power, 0.0, 1.0)


## Position et vitesse initiales d'un obus : [px, py, pz, vx, vy, vz].
static func launch(x: float, y: float, z: float, yaw: float, power: float) -> Array:
	var s := launch_speed(power)
	var ch := cos(ELEV) * s
	var fx := sin(yaw)
	var fz := cos(yaw)
	return [x + fx * 0.6, y + 1.4, z + fz * 0.6, fx * ch, sin(ELEV) * s, fz * ch]


static func shell_at(p0: Array, v0: Array, t: float) -> Vector3:
	return Vector3(p0[0] + v0[0] * t, p0[1] + v0[1] * t - 0.5 * G * t * t, p0[2] + v0[2] * t)


## Portée horizontale d'un tir `l` (résultat de launch) jusqu'à retomber à la hauteur `y`.
static func shell_range(l: Array, y := 0.0) -> float:
	var t: float = (l[4] + sqrt(l[4] * l[4] + 2.0 * G * (l[1] - y))) / G
	return sqrt(l[3] * l[3] + l[5] * l[5]) * t


## Puissance (0..1) pour toucher une cible à la distance horizontale `d`. Sert aux bots.
static func power_for_distance(d: float) -> float:
	var lo := 0.0
	var hi := 1.0
	for i in 20:
		var mid := (lo + hi) / 2.0
		if shell_range(launch(0.0, 0.0, 0.0, 0.0, mid)) + 0.6 < d:
			lo = mid
		else:
			hi = mid
	return (lo + hi) / 2.0


## Rayon de la zone sûre de chaque île à l'instant `t`.
static func zone_radius(t: float, shrink_start: float, battle_end: float) -> float:
	if t <= shrink_start or battle_end <= shrink_start:
		return ZONE_R0
	var k := minf(1.0, (t - shrink_start) / (battle_end - shrink_start))
	return ZONE_R0 + (ZONE_R1 - ZONE_R0) * k
