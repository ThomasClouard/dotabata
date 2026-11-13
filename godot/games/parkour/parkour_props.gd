class_name ParkourProps
extends RefCounted
## Parcours délirant — décor et animation des éléments de la vague 1 : rouleaux, poinçonneurs, guillotines,
## plateaux tournants, balayeurs, grande roue, pistons, boule de démolition, étau, dalles clignotantes, lave,
## boules, faux murs, décor, panneaux, brouillard ; plus les arches gonflables et les confettis de l'arrivée.
## Chaque pièce mobile est replacée à chaque image par les fonctions pures de Level, au temps serveur :
## ce qu'on voit coïncide exactement avec les boîtes de collision.

const PASTELS := [0xff8fab, 0xffc971, 0x7fd8f0, 0xa5e07a, 0xc9a8e8, 0xfde68a, 0x8fb8ff]
const CONFETTI := [0xff4d6d, 0xffd60a, 0x70e000, 0x00b4d8, 0xc77dff, 0xff9e00]
const HAZARD_FX := {
	"lava": [0xff5400, 0xffb000, 0xffd60a, 0x5c1a00],
	"water": [0xffffff, 0x8fd3ff, 0x1e90ff, 0xcaf0f8],
	"acid": [0x7cff3a, 0xb5ff3a, 0x2dc653, 0xf1ff9e],
	"floor": [0xffffff, 0xe0c9a6, 0xc9a27e, 0xf1e3c8],
}
const FOG_DEFAULT := "#b9c2cf"

var ctx: Main
var level: Dictionary
var recs: Array = []  # un enregistrement (Dictionary) par élément animé
var arches: Array = []  # tubes gonflables qui « respirent »
var hazards: Array = []
var fog_boxes: Array = []  # brume visible de dehors (une par zone `fog`)
var _cols0: Array  # boîtes à t = 0, pour poser poteaux et piliers au sol
var _fx_timer := 0.0
var _confetti: Array = []  # { p: Vector3, w: float, until: float }
var _fog_k := 0.0  # 0 = hors du brouillard, 1 = dedans (lissé)
var _fog_target := 0.0
var _fog_color := Color(FOG_DEFAULT)
var _fog_density := 0.0
var _env_saved := {}
static var _hazard_mats := {}


func _init(c: Main, l: Dictionary) -> void:
	ctx = c
	level = l
	# sols fixes seulement (pas les obstacles ni les pièces mobiles)
	_cols0 = Level.build_colliders(l, 0.0).filter(func(c: Phys.Col) -> bool: return c.tag in ["start", "finish", "checkpoint", "platform", "ice", "conveyor", "crumble", "trampoline", "roller", "hazard"])
	var env := ctx.env.env
	_env_saved = {"begin": env.fog_depth_begin, "end": env.fog_depth_end, "sky": env.fog_sky_affect}


# ---------- outils ----------

static func _hash(a: float, b: float) -> float:
	var s := sin(a * 12.9898 + b * 78.233) * 43758.5453
	return s - floorf(s)


func _v(e: Dictionary) -> Vector3:
	return Vector3(e["pos"][0], e["pos"][1], e["pos"][2])


## Nœud racine posé sur l'élément (position et lacet), ajouté au monde.
func _root(e: Dictionary, with_yaw := true) -> Node3D:
	var g := Node3D.new()
	g.position = _v(e)
	if with_yaw:
		g.rotation.y = e.get("yaw", 0.0)
	ctx.world.add_child(g)
	return g


## Nœud libre dans le monde (pièce mobile replacée à chaque image).
func _free(n: Node3D) -> Node3D:
	ctx.world.add_child(n)
	return n


## Altitude du sol sous un point (boîtes à t = 0) ; `fallback` s'il n'y a rien à moins de `depth` m.
func _ground(p: Vector3, fallback: float, depth := 10.0) -> float:
	var g := Phys.ground_below(p.x, p.y, p.z, _cols0)
	return g if g > p.y - depth else fallback


func _place(n: Node3D, c: Phys.Col) -> void:
	n.position = Vector3(c.cx, c.cy, c.cz)
	n.rotation = Vector3(0, c.yaw, 0)


func _color(e: Dictionary, def: int) -> int:
	return Gfx.to_int(Color(e["color"])) if e.get("color") != null else def


## Tube gonflable rayé en arc (arche de départ / d'arrivée), dans le plan XY local.
func inflatable_arch(parent: Node3D, r: float, x: float, y: float, z: float, yaw: float, text: String, colors: Array) -> void:
	var g := Node3D.new()
	g.position = Vector3(x, y, z)
	g.rotation.y = yaw
	parent.add_child(g)
	var tube := Gfx.mesh(Shapes.torus_arc(r, 0.5, 14, 44, PI), Gfx.mat(0xffffff, {"map": Tex.stripes(colors[0], "#ffffff"), "uv": Vector2(12, 1), "rough": 0.25}), 0, 0, 0, g)
	# pieds lestés
	for s in [-1.0, 1.0]:
		Gfx.mesh(Shapes.cylinder(0.62, 0.7, 0.4, 16), Gfx.mat(Gfx.to_int(Color(colors[1])), {"rough": 0.35}), s * r, 0.2, 0, g)
	var board := Gfx.board(text, minf(4.5, r * 1.3), 1.0, "#2b2140", colors[1])
	board.position = Vector3(0, r + 0.95, 0)
	g.add_child(board)
	arches.append(tube)


# ---------- construction ----------

## Construit l'élément s'il est d'un type de la vague 1 ; renvoie le nœud racine (ou null).
func build(e: Dictionary, i: int) -> Node3D:
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var sz: float = e["size"][2]
	var yaw: float = e.get("yaw", 0.0)
	var rec := {"e": e, "i": i, "type": e["type"]}
	var root: Node3D = null
	match e["type"]:
		"roller":
			root = _root(e)
			var r := sy / 2.0
			var drum := Node3D.new()
			root.add_child(drum)
			var cyl := Gfx.mesh(Shapes.cylinder(r, r, sx, 24), Gfx.mat(0xffffff, {"map": Tex.stripes("#ff8c42", "#fff1d6"), "uv": Vector2(3, maxf(1.0, roundf(sx))), "rough": 0.35}), 0, 0, 0, drum)
			cyl.rotation.z = PI / 2.0
			# nervures parallèles à l'axe : on voit le rouleau tourner
			var rib_mat := Gfx.mat(0xd9480f, {"rough": 0.4})
			for k in 6:
				var a := k * TAU / 6.0
				var rib := Gfx.mesh(Shapes.cylinder(0.07, 0.07, sx * 0.96, 6), rib_mat, 0, r * cos(a), r * sin(a), drum)
				rib.rotation.z = PI / 2.0
			for s in [-1.0, 1.0]:
				var cap := Gfx.mesh(Shapes.cylinder(r * 1.08, r * 1.08, 0.16, 20), Gfx.mat(0xffd60a, {"rough": 0.3}), s * (sx / 2.0 + 0.04), 0, 0, root)
				cap.rotation.z = PI / 2.0
			rec["drum"] = drum
		"puncher":
			root = _root(e)
			var count := int(e.get("count", 4))
			var w := sx / count
			# caisson à l'arrière (côté -z local), d'où sortent les blocs
			Gfx.mesh(Shapes.rbox(sx + 0.3, sy + 0.3, 0.5, 0.15), Gfx.mat(0x3d4450, {"metal": 0.4, "rough": 0.4}), 0, 0, -sz / 2.0 - 0.3, root)
			var block_mat := Gfx.mat(0xf72585, {"rough": 0.3})
			var face_mat := Gfx.mat(0xffffff, {"map": Tex.stripes("#ffd60a", "#2b2140"), "uv": Vector2(2, 2)})
			var rod_mat := Gfx.mat(0xbfc7d1, {"metal": 0.8, "rough": 0.2})
			var blocks := []
			var rods := []
			var anchors := []
			var hw := maxf(0.1, w / 2.0 - 0.05)
			for k in count:
				var b := _free(Node3D.new())
				Gfx.mesh(Shapes.rbox(hw * 2.0, sy, sz, 0.18), block_mat, 0, 0, 0, b)
				Gfx.mesh(Shapes.rbox(hw * 2.0 * 1.04, sy * 1.04, 0.16, 0.07), face_mat, 0, 0, sz / 2.0, b)
				blocks.append(b)
				rods.append(Gfx.mesh(Shapes.cylinder(0.16, 0.16, 1.0, 10), rod_mat, 0, 0, 0, ctx.world))
				var a := Level._to_world(e, -sx / 2.0 + (k + 0.5) * w, 0.0, -sz / 2.0 - 0.1)
				anchors.append(Vector3(a[0], a[1], a[2]))
			rec["blocks"] = blocks
			rec["rods"] = rods
			rec["anchors"] = anchors
			rec["dir"] = Vector3(sin(yaw), 0, cos(yaw))
		"gate":
			root = _root(e)
			var drop: float = e.get("drop", 3.0)
			var yb := -sy / 2.0 - drop
			var yt := sy / 2.0 + 0.5
			var pole_mat := Gfx.mat(0xffffff, {"map": Tex.stripes("#2b2140", "#ffd60a"), "uv": Vector2(1, maxf(2.0, roundf(yt - yb)))})
			for s in [-1.0, 1.0]:
				Gfx.mesh(Shapes.rbox(0.42, yt - yb, maxf(0.6, sz + 0.3), 0.12), pole_mat, s * (sx / 2.0 + 0.3), (yt + yb) / 2.0, 0, root)
			Gfx.mesh(Shapes.rbox(sx + 1.3, 0.45, maxf(0.7, sz + 0.4), 0.15), Gfx.mat(0x3d4450, {"metal": 0.4, "rough": 0.4}), 0, yt, 0, root)
			var blade := _free(Node3D.new())
			Gfx.mesh(Shapes.rbox(sx, sy, sz, 0.08), Gfx.mat(0xbfc7d1, {"metal": 0.75, "rough": 0.22}), 0, 0, 0, blade)
			var edge := Gfx.mat(0xe5383b, {"rough": 0.3, "glow": 0.01})
			Gfx.mesh(Shapes.rbox(sx, minf(0.22, sy * 0.3), sz * 1.12, 0.05), edge, 0, -sy / 2.0 + minf(0.11, sy * 0.15), 0, blade)
			rec["blade"] = blade
			rec["edge"] = edge
			var ropes := []
			for s in [-0.3, 0.3]:
				ropes.append(Gfx.mesh(Shapes.cylinder(0.04, 0.04, 1.0, 5), Gfx.mat(0x5c6470, {"metal": 0.6}), 0, 0, 0, ctx.world, false))
			rec["ropes"] = ropes
			rec["top"] = _v(e).y + yt
		"turntable":
			root = _root(e, false)
			var r := sx / 2.0
			var spin := Node3D.new()
			root.add_child(spin)
			Gfx.mesh(Shapes.cylinder(r, r, sy, 40), Gfx.mat(0x3a86ff, {"rough": 0.35}), 0, 0, 0, spin)
			Gfx.mesh(Shapes.cylinder(r * 0.97, r * 0.97, 0.06, 40), Gfx.mat(0xffffff, {"map": Tex.target("#cfe8ff", "#8fb8ff"), "rough": 0.4}), 0, sy / 2.0 + 0.02, 0, spin)
			var spoke := Gfx.mat(0xffd60a, {"rough": 0.3})
			for k in 3:
				var bar := Gfx.mesh(Shapes.rbox(r * 1.8, 0.06, 0.26, 0.03), spoke, 0, sy / 2.0 + 0.05, 0, spin)
				bar.rotation.y = k * PI / 3.0
			var bulb := Gfx.mat(0xffd60a, {"glow": 1.4})
			for k in 12:
				var a := k * TAU / 12.0
				Gfx.mesh(Shapes.sphere(0.12, 8, 6), bulb, cos(a) * (r + 0.02), 0, sin(a) * (r + 0.02), spin, false)
			Gfx.mesh(Shapes.cylinder(0.45, 0.45, 0.12, 16), Gfx.mat(0xff4d6d, {"rough": 0.3}), 0, sy / 2.0 + 0.1, 0, spin)
			var rock := Gfx.rock_under(r * 1.4, minf(3.5, maxf(1.0, r * 0.5)), r * 1.4, 0x3d4a66, i)
			rock.position.y = -sy / 2.0 + 0.05
			root.add_child(rock)
			rec["spin"] = spin
		"sweeper":
			root = _root(e, false)
			var hi: float = e.get("highOffset", 2.1)
			var gy := _ground(_v(e), _v(e).y - 0.5, 3.0) - _v(e).y
			var top := hi + 0.45
			Gfx.mesh(Shapes.cylinder(0.2, 0.3, top - gy, 12), Gfx.mat(0x5c6470, {"metal": 0.6, "rough": 0.3}), 0, (top + gy) / 2.0, 0, root)
			Gfx.mesh(Shapes.sphere(0.32, 14, 10), Gfx.mat(0xffd60a, {"metal": 0.3, "rough": 0.25}), 0, top, 0, root)
			var bars := []
			for k in 2:
				var bar := Node3D.new()
				bar.position.y = hi if k == 1 else 0.0
				root.add_child(bar)
				var r := minf(sy, sz) / 2.0
				var cap := Gfx.mesh(Shapes.capsule(r, maxf(0.1, sx - 2.0 * r)), Gfx.mat(0xffffff, {"map": Tex.stripes("#4361ee" if k == 1 else "#ff4d6d", "#ffffff"), "uv": Vector2(1, maxf(2.0, roundf(sx)))}), 0, 0, 0, bar)
				cap.rotation.z = PI / 2.0
				Gfx.mesh(Shapes.sphere(r * 1.6, 14, 10), Gfx.mat(0xffd60a, {"metal": 0.3, "rough": 0.25}), 0, 0, 0, bar)
				bars.append(bar)
			rec["bars"] = bars
		"ferris":
			root = _root(e)
			var rr: float = e.get("radius", 5.0)
			var count := int(e.get("count", 4))
			var wheel := Node3D.new()
			root.add_child(wheel)
			var side_z := sz / 2.0 + 0.35
			var ring_mat := Gfx.mat(0xff4d6d, {"rough": 0.3})
			var spoke_mat := Gfx.mat(0xf1f3f5, {"rough": 0.4})
			var bulb := Gfx.mat(0xffd60a, {"glow": 1.5})
			var n_spokes := maxi(6, count * 2)
			for s in [-1.0, 1.0]:
				Gfx.mesh(Shapes.torus_arc(rr, 0.13, 8, 64), ring_mat, 0, 0, s * side_z, wheel)
				for k in n_spokes:
					var a := k * TAU / n_spokes
					var sp := Gfx.mesh(Shapes.cylinder(0.06, 0.06, rr, 5), spoke_mat, cos(a) * rr / 2.0, sin(a) * rr / 2.0, s * side_z, wheel)
					sp.rotation.z = a - PI / 2.0
				for k in n_spokes:
					var a := (k + 0.5) * TAU / n_spokes
					Gfx.mesh(Shapes.sphere(0.13, 8, 6), bulb, cos(a) * rr, sin(a) * rr, s * side_z, wheel, false)
			var axle := Gfx.mesh(Shapes.cylinder(0.3, 0.3, side_z * 2.0 + 0.8, 14), Gfx.mat(0xffd60a, {"metal": 0.3, "rough": 0.25}), 0, 0, 0, root)
			axle.rotation.x = PI / 2.0
			# chevalets en A de chaque côté, jusqu'au sol (ou un peu sous la roue)
			var gy := _ground(_v(e) + Vector3(0, -rr - 0.5, 0), _v(e).y - rr - 2.0, 12.0) - _v(e).y
			var leg_mat := Gfx.mat(0x3d4450, {"metal": 0.4, "rough": 0.4})
			for s in [-1.0, 1.0]:
				for lx in [-1.0, 1.0]:
					var leg := Gfx.mesh(Shapes.cylinder(0.14, 0.14, 1.0, 8), leg_mat, 0, 0, 0, root)
					Gfx.stretch(leg, Vector3(0, 0, s * (side_z + 0.4)), Vector3(lx * rr * 0.55, gy, s * (side_z + 0.9)))
			var cabins := []
			for k in count:
				var cab := _free(Gfx.slab(sx, sy, sz, PASTELS[(i + k) % PASTELS.size()], {"under": false, "seed": i + k}))
				Gfx.mesh(Shapes.rbox(sx * 0.7, 0.1, sz * 0.7, 0.05), bulb, 0, -sy / 2.0 - 0.04, 0, cab, false)
				cabins.append(cab)
			rec["wheel"] = wheel
			rec["cabins"] = cabins
		"pistons":
			root = _root(e)
			var count := int(e.get("count", 4))
			var w := sx / count
			Gfx.mesh(Shapes.rbox(sx + 0.2, 0.5, sz + 0.2, 0.15), Gfx.mat(0x3d4450, {"metal": 0.4, "rough": 0.45}), 0, -sy / 2.0 - 0.3, 0, root)
			var shaft_mat := Gfx.mat(0xbfc7d1, {"metal": 0.8, "rough": 0.2})
			var slabs := []
			var shafts := []
			var bases := []
			for k in count:
				slabs.append(_free(Gfx.slab(w, sy, sz, 0xff9e00 if k % 2 == 0 else 0xffd60a, {"under": false})))
				shafts.append(Gfx.mesh(Shapes.cylinder(1.0, 1.0, 1.0, 10), shaft_mat, 0, 0, 0, ctx.world))
				var b := Level._to_world(e, -sx / 2.0 + (k + 0.5) * w, -sy / 2.0 - 0.1, 0.0)
				bases.append(Vector3(b[0], b[1], b[2]))
			rec["slabs"] = slabs
			rec["shafts"] = shafts
			rec["bases"] = bases
			rec["shaft_r"] = minf(w, sz) * 0.16
		"wreckingball":
			root = _root(e, false)
			Gfx.mesh(Shapes.rbox(1.0, 0.5, 1.0, 0.15), Gfx.mat(0x3d4450, {"metal": 0.4, "rough": 0.4}), 0, 0.3, 0, root)
			Gfx.mesh(Shapes.sphere(0.35, 14, 10), Gfx.mat(0xffd60a, {"metal": 0.3, "rough": 0.25}), 0, 0, 0, root)
			var ball := _free(Node3D.new())
			var r := sx / 2.0
			Gfx.mesh(Shapes.sphere(r, 24, 16), Gfx.mat(0x2b2d42, {"metal": 0.55, "rough": 0.3}), 0, 0, 0, ball)
			Gfx.mesh(Shapes.torus(r * 0.98, r * 0.12, 32, 8), Gfx.mat(0xffd60a, {"rough": 0.3}), 0, 0, 0, ball)
			Gfx.mesh(Shapes.cylinder(r * 0.25, r * 0.3, r * 0.4, 10), Gfx.mat(0x5c6470, {"metal": 0.6}), 0, r * 0.95, 0, ball)
			rec["ball"] = ball
			rec["chain"] = Gfx.mesh(Shapes.cylinder(0.07, 0.07, 1.0, 6), Gfx.mat(0x8d99ae, {"metal": 0.7, "rough": 0.3}), 0, 0, 0, ctx.world)
		"crusher":
			root = _root(e)
			var th: float = e.get("thickness", 1.0)
			# rails au sol : les murs coulissent dessus
			for s in [-1.0, 1.0]:
				Gfx.mesh(Shapes.rbox(sx + th * 4.0, 0.16, 0.3, 0.06), Gfx.mat(0x5c6470, {"metal": 0.6, "rough": 0.3}), 0, -sy / 2.0 + 0.08, s * (sz / 2.0 - 0.3), root)
			var walls := []
			for s in [-1.0, 1.0]:
				var wall := _free(Node3D.new())
				Gfx.mesh(Shapes.rbox(th, sy, sz, 0.15), Gfx.mat(0x8d99ae, {"metal": 0.3, "rough": 0.4}), 0, 0, 0, wall)
				# tampon jaune rayé sur la face intérieure (on est poussé, jamais écrasé)
				Gfx.mesh(Shapes.rbox(0.18, sy * 0.86, sz * 0.86, 0.08), Gfx.mat(0xffffff, {"map": Tex.stripes("#ffd60a", "#2b2140"), "uv": Vector2(2, 2)}), -s * th / 2.0, 0, 0, wall)
				walls.append(wall)
			rec["walls"] = walls
		"blink":
			root = _root(e)
			var solid := Gfx.slab(sx, sy, sz, 0x4cc9f0, {"under": false, "glow": 0.35})
			root.add_child(solid)
			var cap: MeshInstance3D = solid.get_node("dessus")
			rec["cap"] = cap.material_override
			rec["solid"] = solid
			var ghost := Gfx.mesh(Shapes.rbox(sx, sy, sz, 0.2), Gfx.flat(0x4cc9f0, {"opacity": 0.14}), 0, 0, 0, root, false)
			rec["ghost"] = ghost
		"hazard":
			root = _root(e)
			var style: String = e.get("style", "lava")
			Gfx.mesh(Shapes.rbox(sx, sy, sz, minf(0.15, sy * 0.3)), _hazard_mat(style), 0, 0, 0, root, false)
			hazards.append({"e": e, "style": style})
		"boulder":
			root = _root(e, false)
			var r := sx / 2.0
			var delta: Array = e["delta"]
			var d := Vector3(delta[0], delta[1], delta[2])
			var dn := d.normalized() if d.length() > 0.01 else Vector3.FORWARD
			# portail de départ et cible d'arrivée : anneaux perpendiculaires au trajet
			for end in [0.0, 1.0]:
				var ring := Gfx.mesh(Shapes.torus(r * 1.35, 0.18, 32, 8), Gfx.mat(0x5c6470 if end == 0.0 else 0xff4d6d, {"metal": 0.4, "rough": 0.35}), d.x * end, d.y * end, d.z * end, root)
				ring.basis = Basis(Quaternion(Vector3.UP, dn))
			var interval: float = e.get("interval", 4.0)
			var travel: float = e.get("travel", 5.0)
			var pool := []
			var ball_mat := Gfx.mat(0xc8a27c, {"map": Tex.stone(), "uv": Vector2(2, 1), "rough": 0.85})
			for k in ceili(travel / interval) + 1:
				var b := _free(Node3D.new())
				Gfx.mesh(Shapes.sphere(r, 20, 14), ball_mat, 0, 0, 0, b)
				b.visible = false
				pool.append(b)
			rec["pool"] = pool
			rec["axis"] = Vector3(dn.z, 0, -dn.x).normalized() if absf(dn.x) + absf(dn.z) > 1e-3 else Vector3.RIGHT
		"fakewall":
			# identique à une plateforme ; seul indice : un très léger miroitement du dessus
			root = _root(e)
			var slab := Gfx.slab(sx, sy, sz, _color(e, PASTELS[i % PASTELS.size()]), {"seed": i})
			root.add_child(slab)
			var cap: MeshInstance3D = slab.get_node("dessus")
			var m: StandardMaterial3D = cap.material_override
			m.emission_enabled = true
			m.emission = Color.WHITE
			m.emission_energy_multiplier = 0.0
			rec["shimmer"] = m
		"deco":
			root = _build_deco(e, i, rec)
		"sign":
			root = _build_sign(e)
		"fog":
			var density: float = e.get("density", 0.6)
			var c := Color(e["color"]) if e.get("color") != null else Color(FOG_DEFAULT)
			root = _root(e)
			# vu de dehors : un amas de boules de brume translucides (un seul MultiMesh), qui dérivent lentement
			var n := clampi(int(sx * sy * sz / 25.0), 6, 28)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = Shapes.icosphere(1.0, 2)
			mm.instance_count = n
			var puffs := []
			for k in n:
				var r := minf(minf(sx, sz) * 0.5, sy * 0.6) * (0.45 + _hash(i, k) * 0.4)
				var p := Vector3((_hash(k, i + 1) - 0.5) * (sx - r), (_hash(k + 3, i) - 0.5) * (sy - r) * 0.8, (_hash(i + 5, k) - 0.5) * (sz - r))
				puffs.append([p, r, _hash(k, 7) * TAU])
				mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(r, r * 0.75, r)), p))
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			var fm := Gfx.flat(Gfx.to_int(c), {"opacity": 0.1 + 0.16 * density})
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			fm.roughness = 1.0
			fm.disable_receive_shadows = true
			mi.material_override = fm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			fog_boxes.append(mi)
			rec["puffs"] = puffs
			rec["mm"] = mm
	if root != null and rec.size() > 3:  # au-delà de e, i, type : il y a quelque chose à animer
		recs.append(rec)
	return root


static func _hazard_mat(style: String) -> StandardMaterial3D:
	if _hazard_mats.has(style) and is_instance_valid(_hazard_mats[style]):
		return _hazard_mats[style]
	var m: StandardMaterial3D
	match style:
		"floor":
			# parquet de la maison : on y tombe de haut, on revient au checkpoint
			m = Gfx.mat(0xffffff, {"map": Tex.planks(), "rough": 0.5})
		"water":
			m = Gfx.mat(0xffffff, {"map": Tex.soft("#1c7ed6", "#4dabf7"), "rough": 0.06, "metal": 0.1, "opacity": 0.88})
		"acid":
			m = Gfx.mat(0xffffff, {"map": Tex.soft("#5ad61a", "#b5ff3a"), "rough": 0.3})
			m.emission_enabled = true
			m.emission = Gfx.col(0x7cff3a)
			m.emission_energy_multiplier = 0.55
		_:
			m = Gfx.mat(0xffffff, {"map": Tex.soft("#d62800", "#ff9500"), "rough": 0.6})
			m.emission_enabled = true
			m.emission = Color(0.85, 0.3, 0.06)
			m.emission_texture = m.albedo_texture
			m.emission_energy_multiplier = 0.9
	# coordonnées monde : un seul matériau par style, quelle que soit la taille
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.22, 0.22, 0.22)
	_hazard_mats[style] = m
	return m


func _build_deco(e: Dictionary, i: int, rec: Dictionary) -> Node3D:
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var sz: float = e["size"][2]
	var g := _root(e)
	g.position.y -= sy / 2.0  # base en bas de la boîte
	var kind: String = e.get("kind", "tree")
	rec["kind"] = kind
	match kind:
		"tree":
			var t := Gfx.tree(sy, _color(e, 0x52d681))
			t.scale = Vector3(maxf(0.5, minf(sx, sz) / (sy * 0.55)), 1, maxf(0.5, minf(sx, sz) / (sy * 0.55)))
			g.add_child(t)
			rec["sway"] = t
		"rock":
			var m := Gfx.mesh(Shapes.icosphere(1.0, 1), Gfx.mat(_color(e, 0x8d99ae), {"rough": 0.9}), 0, sy * 0.42, 0, g)
			m.scale = Vector3(sx / 2.0, sy / 2.0, sz / 2.0)
			m.rotation.y = i * 1.3
			var m2 := Gfx.mesh(Shapes.icosphere(1.0, 1), Gfx.mat(Gfx.shade(_color(e, 0x8d99ae), 0.8), {"rough": 0.9}), sx * 0.32, sy * 0.2, sz * 0.2, g)
			m2.scale = Vector3(sx / 4.0, sy / 3.5, sz / 4.0)
		"balloon":
			var n := clampi(int(sx * sz / 1.5) + 2, 2, 7)
			var items := []
			for k in n:
				var b := Gfx.balloon(_color(e, PASTELS[(i + k * 3) % PASTELS.size()]) if k == 0 else PASTELS[(i + k * 3) % PASTELS.size()])
				var bx := (_hash(i, k) - 0.5) * sx * 0.7
				var bz := (_hash(k, i + 7) - 0.5) * sz * 0.7
				b.position = Vector3(bx, maxf(1.0, sy - 0.8 - _hash(i + k, 3) * minf(1.5, sy * 0.3)), bz)
				g.add_child(b)
				items.append([b, b.position.y, _hash(k, 11) * TAU])
			rec["balloons"] = items
		"arrow":
			var arrow := Node3D.new()
			arrow.position.y = sy / 2.0
			g.add_child(arrow)
			var am := Gfx.mat(_color(e, 0xffd60a), {"glow": 0.6, "rough": 0.3})
			Gfx.mesh(Shapes.rbox(sx * 0.4, minf(sy, 0.5), sz * 0.55, 0.1), am, 0, 0, -sz * 0.2, arrow)
			var head := Gfx.mesh(Shapes.cylinder(0.0, sx * 0.55, sz * 0.45, 4), am, 0, 0, sz * 0.27, arrow)
			head.rotation = Vector3(PI / 2.0, 0, 0)
			head.scale = Vector3(1, 1, minf(sy, 0.5) / (sx * 0.55))
			rec["arrow"] = arrow
		"flag":
			Gfx.mesh(Shapes.cylinder(0.06, 0.08, sy, 8), Gfx.mat(0xf1f3f5, {"metal": 0.3}), 0, sy / 2.0, 0, g)
			Gfx.mesh(Shapes.sphere(0.12, 8, 6), Gfx.mat(0xffd60a, {"metal": 0.3}), 0, sy + 0.06, 0, g)
			var pieces := []
			var fw := maxf(0.6, sx * 0.8)
			var fh := minf(sy * 0.35, fw * 0.7)
			var fm := Gfx.mat(_color(e, 0xff4d6d), {"double": true, "rough": 0.5})
			for k in 4:
				var p := Gfx.mesh(Shapes.box(fw / 4.0 + 0.02, fh, 0.04), fm, 0.06 + (k + 0.5) * fw / 4.0, sy - fh / 2.0 - 0.1, 0, g)
				pieces.append(p)
			rec["flag"] = pieces
		"cactus":
			var cm := Gfx.mat(_color(e, 0x2d9c4a), {"rough": 0.6})
			var r := maxf(0.12, minf(sx, sz) * 0.18)
			Gfx.mesh(Shapes.capsule(r, sy - 2.0 * r), cm, 0, sy / 2.0, 0, g)
			for s in [-1.0, 1.0]:
				var h := sy * (0.35 if s < 0.0 else 0.25)
				var ay := sy * (0.45 if s < 0.0 else 0.6)
				var arm := Gfx.mesh(Shapes.capsule(r * 0.7, h), cm, s * r * 2.4, ay + h * 0.3, 0, g)
				arm.rotation.z = 0.0
				var link := Gfx.mesh(Shapes.capsule(r * 0.65, r * 1.6), cm, s * r * 1.4, ay, 0, g)
				link.rotation.z = PI / 2.0
			Gfx.mesh(Shapes.sphere(r * 0.6, 10, 8), Gfx.mat(0xff8fab, {"rough": 0.4}), 0, sy + r * 0.1, 0, g)
		"mushroom":
			var r := maxf(0.3, minf(sx, sz) / 2.0)
			Gfx.mesh(Shapes.cylinder(r * 0.28, r * 0.38, sy * 0.6, 12), Gfx.mat(0xfff1d6, {"rough": 0.6}), 0, sy * 0.3, 0, g)
			var cap := Gfx.mesh(Shapes.sphere_part(r, 20, 10, 0.0, TAU, 0.0, PI / 2.0), Gfx.mat(_color(e, 0xe5383b), {"rough": 0.35}), 0, sy * 0.58, 0, g)
			cap.scale = Vector3(1, maxf(0.4, (sy * 0.42) / r), 1)
			var dot := Gfx.mat(0xffffff, {"rough": 0.4})
			for k in 6:
				var a := k * TAU / 6.0 + i
				var el := 0.55 if k % 2 == 0 else 0.95
				var p := Vector3(cos(a) * sin(el) * r, cos(el) * r * cap.scale.y, sin(a) * sin(el) * r)
				Gfx.mesh(Shapes.sphere(r * 0.13, 8, 6), dot, p.x, sy * 0.58 + p.y, p.z, g, false)
		"crystal":
			var cm := Gfx.mat(_color(e, 0xc77dff), {"glow": 0.8, "rough": 0.1, "metal": 0.2})
			var shards := []
			for k in 5:
				var h := sy * (1.0 if k == 0 else 0.45 + _hash(i, k) * 0.35)
				var r := minf(sx, sz) * (0.22 if k == 0 else 0.13)
				var s := Node3D.new()
				s.position = Vector3((0.0 if k == 0 else cos(k * 1.7) * minf(sx, sz) * 0.28), 0, (0.0 if k == 0 else sin(k * 1.7) * minf(sx, sz) * 0.28))
				s.rotation = Vector3((0.0 if k == 0 else sin(k * 1.7) * 0.35), k, (0.0 if k == 0 else -cos(k * 1.7) * 0.35))
				g.add_child(s)
				Gfx.mesh(Shapes.cylinder(r, r * 0.8, h * 0.75, 6), cm, 0, h * 0.375, 0, s)
				Gfx.mesh(Shapes.cylinder(0.0, r, h * 0.25, 6), cm, 0, h * 0.875, 0, s)
				shards.append(s)
			rec["crystal"] = cm
		"crowd":
			_build_crowd(e, i, g, rec)
		_:
			Gfx.mesh(Shapes.icosphere(0.5, 1), Gfx.mat(_color(e, 0xa5e07a)), 0, 0.5, 0, g)
	return g


## Petits spectateurs qui sautillent : trois MultiMesh (corps colorés, têtes, yeux), soit trois appels de dessin.
func _build_crowd(e: Dictionary, i: int, g: Node3D, rec: Dictionary) -> void:
	var sx: float = e["size"][0]
	var sz: float = e["size"][2]
	var n := clampi(int(sx * sz / 1.1), 3, 48)
	var cols := maxi(1, int(round(sqrt(n * sx / maxf(0.5, sz)))))
	var rows := ceili(float(n) / cols)
	var base: int = _color(e, -1)
	var people := []
	var mms := []
	for part in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = part == 0
		match part:
			0:
				mm.mesh = Shapes.capsule(0.22, 0.42)
			1:
				mm.mesh = Shapes.sphere(0.2, 12, 8)
			_:
				mm.mesh = Shapes.sphere(0.045, 6, 4)
		mm.instance_count = n * (2 if part == 2 else 1)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var m := StandardMaterial3D.new()
		m.roughness = 0.5
		match part:
			0:
				m.vertex_color_use_as_albedo = true
				m.vertex_color_is_srgb = true
			1:
				m.albedo_color = Gfx.col(0xffd6a5)
			_:
				m.albedo_color = Gfx.col(0x2b2140)
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if part == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		g.add_child(mi)
		mms.append(mm)
	for k in n:
		var cx := k % cols
		var cz := k / cols
		var x := ((cx + 0.5) / cols - 0.5) * sx + (_hash(i + k, 1) - 0.5) * 0.25
		var z := ((cz + 0.5) / rows - 0.5) * sz + (_hash(k, i + 2) - 0.5) * 0.25
		var c: int = PASTELS[(k * 3 + i) % PASTELS.size()] if base < 0 else Gfx.shade(base, 0.75 + _hash(k, 5) * 0.6)
		mms[0].set_instance_color(k, Gfx.col(c))
		people.append([Vector3(x, 0, z), 5.0 + _hash(k, 9) * 3.0, _hash(k, 13) * TAU, 0.18 + _hash(k, 17) * 0.2])
	rec["crowd"] = mms
	rec["people"] = people
	rec["root"] = g


func _build_sign(e: Dictionary) -> Node3D:
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var th := clampf(e["size"][2], 0.08, 0.3)
	var g := _root(e)
	Gfx.mesh(Shapes.rbox(sx, sy, th, minf(0.08, th * 0.4)), Gfx.mat(0xffffff, {"map": Tex.planks(), "uv": Vector2(maxf(1.0, sx / 2.0), maxf(1.0, sy / 1.5)), "rough": 0.7}), 0, 0, 0, g)
	Gfx.mesh(Shapes.rbox(sx + 0.16, 0.12, th + 0.06, 0.05), Gfx.mat(0x9c6644, {"rough": 0.7}), 0, sy / 2.0, 0, g)
	# texte sur la face +z, sur 1 à 4 lignes selon la place
	var text: String = e.get("text", "")
	if text != "":
		var chars := maxf(4.0, text.length())
		var best_h := 0.0
		var best_lines := 1
		for lines in range(1, 5):
			var h := minf((sy * 0.82) / (lines * 1.25), (sx * 0.9 * lines) / (chars * 0.56))
			if h > best_h * 1.05:
				best_h = h
				best_lines = lines
		var l := Gfx.label3d(text, best_h, Color("#2b2140"), Color(1, 1, 1, 0.5))
		l.outline_size = 6
		if best_lines > 1:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.width = (sx * 0.9) / l.pixel_size
		l.position = Vector3(0, 0, th / 2.0 + 0.01)
		g.add_child(l)
		# face principale vers +z local ; on recopie le texte au dos pour qu'il se lise des deux côtés
		var back: Label3D = l.duplicate()
		back.position = Vector3(0, 0, -th / 2.0 - 0.01)
		back.rotation.y = PI
		g.add_child(back)
	# poteaux jusqu'au sol s'il y en a un pas trop loin dessous
	var p := _v(e)
	var bottom := p.y - sy / 2.0
	var gy := _ground(Vector3(p.x, bottom, p.z), bottom - 1.2, 8.0)
	if bottom - gy > 0.05:
		for s in [-1.0, 1.0]:
			Gfx.mesh(Shapes.cylinder(0.07, 0.08, bottom - gy + 0.1, 8), Gfx.mat(0x9c6644, {"rough": 0.7}), s * sx * 0.32, -sy / 2.0 - (bottom - gy) / 2.0 + 0.05, 0, g)
	return g


# ---------- animation ----------

func update(t: float, dt: float) -> void:
	for rec: Dictionary in recs:
		var e: Dictionary = rec["e"]
		match rec["type"]:
			"roller":
				rec["drum"].rotation.x = Level.roller_angle(e, t)
			"puncher":
				var parts := Level.puncher_blocks(e, t)
				var dir: Vector3 = rec["dir"]
				var sz: float = e["size"][2]
				for k in parts.size():
					var c: Phys.Col = parts[k]
					var b: Node3D = rec["blocks"][k]
					_place(b, c)
					var rod: MeshInstance3D = rec["rods"][k]
					var a: Vector3 = rec["anchors"][k]
					var tip := b.position - dir * (sz / 2.0)
					rod.visible = a.distance_to(tip) > 0.08
					if rod.visible:
						Gfx.stretch(rod, a, tip)
			"gate":
				var c := Level.gate_part(e, t)
				var blade: Node3D = rec["blade"]
				_place(blade, c)
				# le liseré rouge s'allume juste avant la chute
				var until := Level.gate_until_fall(e, t)
				var edge: StandardMaterial3D = rec["edge"]
				edge.emission_energy_multiplier = 2.5 if until == 0.0 else (1.5 + sin(t * 30.0) * 1.2 if until < 0.8 else 0.01)
				var yaw: float = e.get("yaw", 0.0)
				var ropes: Array = rec["ropes"]
				for k in ropes.size():
					var lx: float = (-0.3 if k == 0 else 0.3) * e["size"][0]
					var off := Vector3(lx * cos(yaw), 0, -lx * sin(yaw))
					Gfx.stretch(ropes[k], blade.position + off + Vector3(0, c.hy, 0), Vector3(blade.position.x, rec["top"], blade.position.z) + off)
			"turntable":
				rec["spin"].rotation.y = Level.spin_angle(e, t)
			"sweeper":
				var a := Level.spin_angle(e, t)
				rec["bars"][0].rotation.y = a
				rec["bars"][1].rotation.y = a + PI / 2.0
			"ferris":
				rec["wheel"].rotation.z = TAU * (t / e.get("period", 14.0) + e.get("phase", 0.0))
				var parts := Level.ferris_cabins(e, t)
				for k in parts.size():
					_place(rec["cabins"][k], parts[k])
			"pistons":
				var parts := Level.piston_slabs(e, t)
				var r: float = rec["shaft_r"]
				for k in parts.size():
					var c: Phys.Col = parts[k]
					_place(rec["slabs"][k], c)
					var base: Vector3 = rec["bases"][k]
					var top := Vector3(c.cx, c.cy - c.hy, c.cz)
					var sh: MeshInstance3D = rec["shafts"][k]
					sh.visible = top.y - base.y > 0.05
					if sh.visible:
						Gfx.stretch(sh, base, top, r)
			"wreckingball":
				var c := Level.wrecking_ball(e, t)
				var ball: Node3D = rec["ball"]
				ball.position = Vector3(c.cx, c.cy, c.cz)
				var pivot := _v(e)
				ball.quaternion = Quaternion(Vector3.UP, (pivot - ball.position).normalized())
				Gfx.stretch(rec["chain"], pivot, ball.position)
			"crusher":
				var parts := Level.crusher_walls(e, t)
				for k in 2:
					_place(rec["walls"][k], parts[k])
			"blink":
				var st := Level.blink_state(e, t)
				var left: float = st["left"]
				var solid: Node3D = rec["solid"]
				var cap: StandardMaterial3D = rec["cap"]
				if st["solid"]:
					# clignote de plus en plus vite pendant la dernière seconde, et vire au rouge
					var warn := clampf(1.0 - left, 0.0, 1.0)
					solid.visible = warn <= 0.0 or sin(TAU * (3.0 + warn * 9.0) * left) > -0.35
					cap.emission = Gfx.col(0x4cc9f0).lerp(Gfx.col(0xff4d6d), warn)
					cap.emission_energy_multiplier = 0.35 + warn * 1.2
					rec["ghost"].visible = not solid.visible
				else:
					solid.visible = false
					rec["ghost"].visible = true
					rec["ghost"].scale = Vector3.ONE * (1.0 + 0.02 * sin(t * 6.0))
			"boulder":
				var balls := Level.boulder_balls(e, t)
				var pool: Array = rec["pool"]
				var axis: Vector3 = rec["axis"]
				var r: float = e["size"][0] / 2.0
				for j in pool.size():
					var b: Node3D = pool[j]
					b.visible = j < balls.size()
					if not b.visible:
						continue
					var c: Phys.Col = balls[j][0]
					var k: float = balls[j][1]
					# la boule grossit en sortant du portail et fond à l'arrivée
					var sc := clampf(minf(k / 0.04, (1.0 - k) / 0.06), 0.05, 1.0)
					b.transform = Transform3D(Basis(axis, balls[j][2]).scaled(Vector3.ONE * sc), Vector3(c.cx, c.cy - r * (1.0 - sc), c.cz))
			"fog":
				var mm: MultiMesh = rec["mm"]
				var puffs: Array = rec["puffs"]
				for k in puffs.size():
					var pf: Array = puffs[k]
					var r: float = pf[1] * (1.0 + 0.06 * sin(t * 0.7 + pf[2]))
					mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(r, r * 0.75, r)), pf[0] + Vector3(sin(t * 0.25 + pf[2]) * 0.4, 0, cos(t * 0.2 + pf[2]) * 0.4)))
			"fakewall":
				var m: StandardMaterial3D = rec["shimmer"]
				m.emission_energy_multiplier = maxf(0.0, sin(t * 0.9 + rec["i"])) * 0.07
			"deco":
				_update_deco(rec, t)
	_update_fx(t, dt)
	_update_fog(dt)
	# surface des liquides qui coule doucement
	for style: String in _hazard_mats:
		if style == "floor":
			continue
		var m: StandardMaterial3D = _hazard_mats[style]
		m.uv1_offset = Vector3(fposmod(t * 0.025, 1.0), 0, fposmod(t * 0.017, 1.0))


func _update_deco(rec: Dictionary, t: float) -> void:
	var i: int = rec["i"]
	match rec["kind"]:
		"tree":
			rec["sway"].rotation.z = sin(t * 0.9 + i) * 0.03
		"balloon":
			for b: Array in rec["balloons"]:
				var n: Node3D = b[0]
				n.position.y = b[1] + sin(t * 1.1 + b[2]) * 0.3
				n.rotation.z = sin(t * 0.8 + b[2]) * 0.12
		"arrow":
			var a: Node3D = rec["arrow"]
			a.position.z = sin(t * 3.0 + i) * 0.25
			a.position.y = rec["e"]["size"][1] / 2.0 + absf(sin(t * 1.5 + i)) * 0.25
		"flag":
			var pieces: Array = rec["flag"]
			for k in pieces.size():
				var p: MeshInstance3D = pieces[k]
				p.position.z = sin(t * 5.0 - k * 0.9 + i) * 0.07 * (k + 1)
				p.rotation.y = cos(t * 5.0 - k * 0.9 + i) * 0.25
		"crystal":
			var m: StandardMaterial3D = rec["crystal"]
			m.emission_energy_multiplier = 0.6 + 0.35 * sin(t * 2.0 + i)
		"crowd":
			var mms: Array = rec["crowd"]
			var root: Node3D = rec["root"]
			var cam := root.to_local(ctx.camera.global_position)
			var people: Array = rec["people"]
			for k in people.size():
				var p: Array = people[k]
				var at: Vector3 = p[0]
				var hop: float = absf(sin(t * p[1] + p[2])) * p[3]
				var face := atan2(cam.x - at.x, cam.z - at.z)
				var b := Basis(Vector3.UP, face)
				var squash: float = 1.0 - 0.12 * cos(t * p[1] * 2.0 + p[2] * 2.0)
				var body := at + Vector3(0, 0.43 + hop, 0)
				mms[0].set_instance_transform(k, Transform3D(b.scaled(Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))), body))
				var head := body + Vector3(0, 0.55 * squash, 0)
				mms[1].set_instance_transform(k, Transform3D(b, head))
				for s in 2:
					var eye := head + b * Vector3(-0.07 if s == 0 else 0.07, 0.03, 0.18)
					mms[2].set_instance_transform(k * 2 + s, Transform3D(Basis.IDENTITY, eye))


## Bulles de lave / d'eau / d'acide, poussière des boules, confettis.
func _update_fx(t: float, dt: float) -> void:
	_fx_timer -= dt
	if _fx_timer < 0.0:
		_fx_timer = 0.08
		for h: Dictionary in hazards:
			if h["style"] == "floor":
				continue  # un parquet ne bouillonne pas
			var e: Dictionary = h["e"]
			var cs: Array = HAZARD_FX[h["style"]] if HAZARD_FX.has(h["style"]) else HAZARD_FX["lava"]
			var n := clampi(int(e["size"][0] * e["size"][2] / 40.0), 1, 3)
			for k in n:
				var p := Level._to_world(e, (randf() - 0.5) * e["size"][0] * 0.9, e["size"][1] / 2.0 + 0.05, (randf() - 0.5) * e["size"][2] * 0.9)
				ctx.particles.emit(p[0], p[1], p[2], (randf() - 0.5) * 0.6, 1.2 + randf() * 1.8, (randf() - 0.5) * 0.6, cs[randi() % 3], 0.1 + randf() * 0.12, 0.6 + randf() * 0.5, 3.0)
		for rec: Dictionary in recs:
			if rec["type"] != "boulder":
				continue
			for b: Node3D in rec["pool"]:
				if b.visible and randf() < 0.6:
					var r: float = rec["e"]["size"][0] / 2.0
					ctx.particles.emit(b.position.x + (randf() - 0.5) * r, b.position.y - r * 0.9, b.position.z + (randf() - 0.5) * r, (randf() - 0.5) * 1.5, 0.6 + randf(), (randf() - 0.5) * 1.5, 0xd6c6a8, 0.16, 0.5, 2.0)
	# confettis qui pleuvent de l'arche d'arrivée
	var i := 0
	while i < _confetti.size():
		var c: Dictionary = _confetti[i]
		if t > c["until"]:
			_confetti.remove_at(i)
			continue
		var p: Vector3 = c["p"]
		var w: float = c["w"]
		for k in 3:
			var a := randf() * TAU
			ctx.particles.emit(p.x + (randf() - 0.5) * w, p.y + randf() * 0.5, p.z + (randf() - 0.5) * 1.0, cos(a) * 2.5, 2.0 + randf() * 4.0, sin(a) * 2.5, CONFETTI[randi() % CONFETTI.size()], 0.09, 2.2, 3.5)
		i += 1
	for a: MeshInstance3D in arches:
		var k := 1.0 + sin(t * 2.2) * 0.015
		a.scale = Vector3(k, k, 1.0 + sin(t * 2.2 + 1.0) * 0.06)


## Pluie de confettis pendant `seconds` au-dessus d'un point (arche d'arrivée).
func confetti(p: Vector3, width: float, seconds := 2.5) -> void:
	_confetti.append({"p": p, "w": width, "until": ctx.now() + seconds})


## Brouillard local : épais quand la caméra ou le joueur est dans une zone `fog`.
func _update_fog(dt: float) -> void:
	if fog_boxes.is_empty():
		return
	var cam := ctx.camera.global_position
	var f: Variant = Level.fog_at(level, cam.x, cam.y, cam.z)
	var fp: Variant = Level.fog_at(level, ctx.body.px, ctx.body.py + 1.0, ctx.body.pz)
	if fp != null and (f == null or fp["density"] > f["density"]):
		f = fp
	_fog_target = 0.0
	if f != null:
		_fog_target = 1.0
		_fog_density = f["density"]
		_fog_color = Color(f["color"]) if f["color"] != null else Color(FOG_DEFAULT)
	_fog_k = move_toward(_fog_k, _fog_target, dt * 1.8)
	var inside_cam := Level.fog_at(level, cam.x, cam.y, cam.z) != null
	for b: GeometryInstance3D in fog_boxes:
		b.visible = not inside_cam
	var env := ctx.env.env
	var k := _fog_k * _fog_k * (3.0 - 2.0 * _fog_k)
	env.fog_depth_begin = lerpf(_env_saved["begin"], 0.0, k)
	env.fog_depth_end = lerpf(_env_saved["end"], lerpf(80.0, 7.0, _fog_density), k)
	env.fog_sky_affect = lerpf(_env_saved["sky"], 1.0, k)
	env.fog_light_color = ctx.env.horizon.lerp(_fog_color, k)
	ctx.env.clouds.visible = k < 0.5  # les nuages ignorent le brouillard : on les cache dedans


func restore() -> void:
	if fog_boxes.is_empty():
		return
	var env := ctx.env.env
	env.fog_depth_begin = _env_saved["begin"]
	env.fog_depth_end = _env_saved["end"]
	env.fog_sky_affect = _env_saved["sky"]
	env.fog_light_color = ctx.env.horizon
	ctx.env.clouds.visible = true
