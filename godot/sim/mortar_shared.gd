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


## Collisions : toutes les îles + les blocs de la parcelle indiquée.
static func colliders(n: int, blocks: Dictionary, plot: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(Phys.Col.box(i, plot_cx(i, n), -THICK / 2.0, plot_cz(i, n), ISLAND / 2.0, THICK / 2.0, ISLAND / 2.0, plot_yaw(i, n), "island"))
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


## Rayon de la zone sûre de chaque île à l'instant `t`.
static func zone_radius(t: float, shrink_start: float, battle_end: float) -> float:
	if t <= shrink_start or battle_end <= shrink_start:
		return ZONE_R0
	var k := minf(1.0, (t - shrink_start) / (battle_end - shrink_start))
	return ZONE_R0 + (ZONE_R1 - ZONE_R0) * k
