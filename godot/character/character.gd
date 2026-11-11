class_name Character
extends Node3D
## Personnages façon pâte à modeler : corps « haricot » ou boule, gros yeux collés, membres en tube souple
## animés par ressorts, squelette cartoon à l'intérieur et peau qui s'efface autour des impacts (shader).
## Huit modèles, décrits par la table SPECS ;
## les tubes des membres sont déformés dans le vertex shader au lieu d'être recalculés à chaque image.

const MAX_HITS := 12
const CENTER := 0.85
const T_RINGS := 10
const T_CAP := 4
const T_SEG := 10

const SPECS := {
	"haricot": {
		"y0": 0.5, "y1": 1.62, "radii": [[0.0, 0.21], [0.3, 0.27], [0.55, 0.22], [0.82, 0.25], [1.0, 0.2]], "cap": [0.22, 0.22],
		"eye_t": 0.8, "eye_r": 0.105,
		"arm": {"t": 0.62, "r": 0.07, "rest": [0.5, 0.62, 0.0], "reach": 0.8}, "leg": {"x": 0.12, "r": 0.07, "foot": 0.13, "stride": 1.0},
	},
	"casquette": {
		"y0": 0.42, "y1": 1.5, "radii": [[0.0, 0.3], [1.0, 0.3]], "cap": [0.3, 0.3],
		"eye_t": 0.66, "eye_r": 0.115,
		"arm": {"t": 0.5, "r": 0.085, "rest": [0.52, 0.55, 0.0], "reach": 0.7}, "leg": {"x": 0.14, "r": 0.085, "foot": 0.15, "stride": 1.0},
		"acc": "casquette", "acc_y": 1.2, "acc_dead": [0.5, 0.12, -1.2],
	},
	"spaghetti": {
		"y0": 0.56, "y1": 1.72, "radii": [[0.0, 0.19], [0.4, 0.21], [1.0, 0.24]], "cap": [0.2, 0.24],
		"eye_t": 0.84, "eye_r": 0.1,
		"arm": {"t": 0.55, "r": 0.06, "rest": [0.55, 0.6, 0.0], "reach": 0.9}, "leg": {"x": 0.1, "r": 0.06, "foot": 0.12, "stride": 1.15},
	},
	"hélice": {
		"y0": 0.3, "y1": 1.14, "radii": [[0.0, 0.42], [1.0, 0.42]], "cap": [0.42, 0.42],
		"eye_t": 0.68, "eye_r": 0.11,
		"arm": {"t": 0.55, "r": 0.1, "rest": [0.6, 0.5, 0.0], "reach": 0.5}, "leg": {"x": 0.17, "r": 0.09, "foot": 0.14, "stride": 0.8},
		"acc": "hélice", "acc_y": 0.72, "acc_dead": [0.3, 0.1, -1.2],
	},
	"bouée": {
		"y0": 0.42, "y1": 1.5, "radii": [[0.0, 0.25], [1.0, 0.27]], "cap": [0.25, 0.27],
		"eye_t": 0.78, "eye_r": 0.1,
		"arm": {"t": 0.6, "r": 0.085, "rest": [0.62, 0.98, 0.05], "reach": 0.55}, "leg": {"x": 0.13, "r": 0.085, "foot": 0.14, "stride": 1.0},
		"acc": "bouée", "acc_y": 0.78, "acc_dead": [0.0, 0.12, 0.0],
	},
	"crochet": {
		"y0": 0.5, "y1": 1.72, "radii": [[0.0, 0.18], [0.5, 0.17], [0.8, 0.2], [1.0, 0.2]], "cap": [0.18, 0.2],
		"eye_t": 0.86, "eye_r": 0.1,
		"arm": {"t": 0.5, "r": 0.065, "rest": [0.5, 0.55, 0.0], "reach": 0.95}, "leg": {"x": 0.1, "r": 0.065, "foot": 0.12, "stride": 1.2},
	},
	"bandeau": {
		"y0": 0.3, "y1": 1.14, "radii": [[0.0, 0.42], [1.0, 0.42]], "cap": [0.42, 0.42],
		"eye_t": 0.62, "eye_r": 0.105,
		"arm": {"t": 0.55, "r": 0.1, "rest": [0.6, 0.5, 0.0], "reach": 0.5}, "leg": {"x": 0.17, "r": 0.09, "foot": 0.14, "stride": 0.8},
		"acc": "bandeau", "acc_y": 0.72, "acc_dead": [0.0, -0.15, 0.0],
	},
	"arche": {
		"y0": 0.5, "y1": 1.08, "radii": [[0.0, 0.28], [1.0, 0.3]], "cap": [0.28, 0.3],
		"eye_t": 0.55, "eye_r": 0.1,
		"arm": {"t": 0.75, "r": 0.13, "rest": [0.62, 0.09, 0.12], "reach": 1.15, "lift": 0.5}, "leg": {"x": 0.13, "r": 0.09, "foot": 0.13, "stride": 0.7},
		"arms_walk": true,
	},
}


class Limb extends RefCounted:
	var leg := false
	var side := 1.0
	var anchor := Vector3.ZERO
	var anchor0 := Vector3.ZERO
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var upper: MeshInstance3D
	var lower: MeshInstance3D
	var joint: MeshInstance3D
	var end: MeshInstance3D
	var foot: MeshInstance3D
	var pile_anchor := Vector3.ZERO
	var pile_end := Vector3.ZERO


static var _shader: Shader
static var _bone_mat: StandardMaterial3D
static var _dark_mat: StandardMaterial3D
static var _white_mat: StandardMaterial3D
static var _seg_mesh: Mesh
static var _sph_mesh: Mesh
static var _skin_sph: Mesh
static var _box_mesh: Mesh
static var _tubes_mesh: ArrayMesh

var dead := false
var hanging := false  # suspendu à une tyrolienne : bras tendus vers le câble, jambes ballantes

var _squash := Node3D.new()
var _pivot := Node3D.new()
var _content := Node3D.new()
var _bones: Node3D
var _limb_bones: Node3D
var _hat: Node3D
var _eyes: Node3D
var _pupils: Array[MeshInstance3D] = []
var _propeller: Node3D
var _skin := ShaderMaterial.new()
var _skin_meshes: Array[Node3D] = []
var _limbs: Array[Limb] = []
var _hits: Array = []  # { p: Vector3, r: float, cur: float }
var _hits_world := PackedVector4Array()
var _hits_dirty := false
var _la := PackedVector3Array()
var _lc := PackedVector3Array()
var _le := PackedVector3Array()
var _kind := ""
var _sp: Dictionary = SPECS["haricot"]
var _eye_y := 1.0
var _shoulder_y := 1.0
var _pile_z := -0.75

var _phase := randf() * 6.0
var _time := randf() * 10.0
var _spin := 0.0
var _sq := 1.0
var _sq_v := 0.0
var _was_grounded := true
var _last_vy := 0.0
var _last_pos := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _acc := Vector3.ZERO
var _first := true
var _blink := 2.0 + randf() * 3.0
var _dead_t := 0.0
var _pile_y := 0.0
var _pile_rx := 0.0
var _pile_rz := 0.0


static func _statics() -> void:
	if _shader:
		return
	_shader = load("res://gfx/shaders/skin.gdshader")
	_bone_mat = Gfx.mat(0xfffbea, {"rough": 0.5})
	_dark_mat = Gfx.flat(0x15151c)
	_white_mat = Gfx.mat(0xffffff, {"rough": 0.45})
	_seg_mesh = Shapes.cylinder(1.0, 1.0, 1.0, 12)
	_sph_mesh = Shapes.sphere(1.0, 24, 14)
	_skin_sph = Shapes.sphere_part(1.0, 20, 12, 0.0, TAU, 0.0, PI, true)
	_box_mesh = Shapes.box()
	_tubes_mesh = _build_tubes()


## Les quatre membres dans un seul maillage : UV = (numéro d'anneau, angle), UV2.x = numéro du membre (1..4).
static func _build_tubes() -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var rings := T_RINGS + T_CAP
	for l in 4:
		var base := v.size()
		for k in rings:
			for j in T_SEG:
				v.append(Vector3.ZERO)
				uv.append(Vector2(k, float(j) / T_SEG * TAU))
				uv2.append(Vector2(l + 1, 0))
		for k in rings - 1:
			for j in T_SEG:
				var a := base + k * T_SEG + j
				var b := base + k * T_SEG + ((j + 1) % T_SEG)
				var c := a + T_SEG
				var d := b + T_SEG
				idx.append_array([a, d, b, a, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.custom_aabb = AABB(Vector3(-1.6, -0.4, -1.6), Vector3(3.2, 3.2, 3.2))
	return m


static func _ss(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _radius_at(y: float) -> float:
	var sp := _sp
	var t: float = (y - sp["y0"]) / (sp["y1"] - sp["y0"])
	if t <= 0.0 or t >= 1.0:
		return 0.0
	var radii: Array = sp["radii"]
	var r: float = radii[radii.size() - 1][1]
	for i in range(1, radii.size()):
		var t0: float = radii[i - 1][0]
		var r0: float = radii[i - 1][1]
		var t1: float = radii[i][0]
		var r1: float = radii[i][1]
		if t <= t1:
			r = r0 + (r1 - r0) * _ss((t - t0) / (t1 - t0))
			break
	var h: float = y - sp["y0"]
	var g: float = sp["y1"] - y
	var cap: Array = sp["cap"]
	if h < cap[0]:
		r *= sqrt(1.0 - (1.0 - h / cap[0]) ** 2)
	if g < cap[1]:
		r *= sqrt(1.0 - (1.0 - g / cap[1]) ** 2)
	return r


## Décalage du corps vers l'avant à la hauteur y.
func _lean_at(y: float) -> float:
	var t: float = (y - _sp["y0"]) / (_sp["y1"] - _sp["y0"])
	match _kind:
		"haricot":
			return 0.1 * (t - 0.5) + 0.06 * sin(PI * t)
		"spaghetti":
			return 0.05 * sin(PI * t)
		"crochet":
			return 0.32 * _ss((t - 0.45) / 0.55) ** 2
	return 0.0


func _body_mesh() -> ArrayMesh:
	var n_rings := 36
	var m_seg := 28
	var sp := _sp
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in n_rings + 1:
		var y: float = sp["y0"] + (sp["y1"] - sp["y0"]) * (1.0 - cos(PI * i / n_rings)) / 2.0
		var r := _radius_at(y)
		var dz := _lean_at(y)
		for j in m_seg:
			var a := float(j) / m_seg * TAU
			pos.append(Vector3(r * cos(a), y, r * sin(a) + dz))
	var nor := PackedVector3Array()
	nor.resize(pos.size())
	for i in n_rings:
		for j in m_seg:
			var a := i * m_seg + j
			var b := i * m_seg + ((j + 1) % m_seg)
			var c := a + m_seg
			var d := b + m_seg
			# faces orientées vers l'extérieur dans le sens trigonométrique (a, d, b) et (a, c, d)
			for tri: Array in [[a, d, b], [a, c, d]]:
				var fn := (pos[tri[1]] - pos[tri[0]]).cross(pos[tri[2]] - pos[tri[0]])
				for k: int in tri:
					nor[k] += fn
				idx.append_array(tri)
	for i in nor.size():
		nor[i] = nor[i].normalized() if nor[i].length_squared() > 1e-16 else Vector3.UP
	# les pôles sont dégénérés : normales verticales
	for j in m_seg:
		nor[j] = Vector3.DOWN
		nor[n_rings * m_seg + j] = Vector3.UP
	return Shapes.build(pos, nor, PackedVector2Array(), idx, Transform3D.IDENTITY, true)


func _init(color: int, kind: String) -> void:
	_statics()
	_hits_world.resize(MAX_HITS)
	_la.resize(4)
	_lc.resize(4)
	_le.resize(4)
	_skin.shader = _shader
	_skin.set_shader_parameter("hits", _hits_world)
	add_child(_squash)
	_squash.add_child(_pivot)
	_pivot.position.y = CENTER
	_pivot.add_child(_content)
	_content.position.y = -CENTER
	set_look(color, kind)


## Change la couleur et, si besoin, reconstruit le personnage avec un autre modèle.
func set_look(color: int, kind: String) -> void:
	_skin.set_shader_parameter("albedo", Gfx.col(color))
	if not SPECS.has(kind):
		kind = "haricot"
	if kind == _kind:
		return
	_kind = kind
	_sp = SPECS[kind]
	var sp := _sp
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_skin_meshes.clear()
	_limbs.clear()
	_pupils.clear()
	_propeller = null
	_eye_y = sp["y0"] + sp["eye_t"] * (sp["y1"] - sp["y0"])
	_shoulder_y = sp["y0"] + sp["arm"]["t"] * (sp["y1"] - sp["y0"])

	var body := Gfx.mesh(_body_mesh(), _skin, 0, 0, 0, _content)
	_skin_meshes.append(body)
	var tubes := Gfx.mesh(_tubes_mesh, _skin, 0, 0, 0, _content)
	_skin_meshes.append(tubes)
	_bones = Node3D.new()
	_build_skeleton()
	_content.add_child(_bones)
	_bones.visible = false
	_limb_bones = Node3D.new()
	_content.add_child(_limb_bones)
	_limb_bones.visible = false
	_eyes = Node3D.new()
	_build_eyes()
	_content.add_child(_eyes)
	_hat = Node3D.new()
	_content.add_child(_hat)
	_hat.position = Vector3(0, sp.get("acc_y", 0.0), 0)
	_build_accessory()

	var arm: Dictionary = sp["arm"]
	var leg: Dictionary = sp["leg"]
	var rest: Array = arm["rest"]
	var foot_y: float = leg["foot"] * 0.55
	var radii := PackedVector2Array()
	for side in [-1.0, 1.0]:
		var sh := Vector3(side * _radius_at(_shoulder_y) * 0.8, _shoulder_y, _lean_at(_shoulder_y))
		_limbs.append(_make_limb(false, side, sh, Vector3(side * rest[0], rest[1], rest[2])))
		radii.append(Vector2(arm["r"], arm["r"] * 1.25))
		var hip := Vector3(side * leg["x"], sp["y0"] + 0.1, _lean_at(sp["y0"] + 0.1))
		_limbs.append(_make_limb(true, side, hip, Vector3(side * (leg["x"] + 0.03), foot_y, 0)))
		radii.append(Vector2(leg["r"], leg["r"]))
	_skin.set_shader_parameter("limb_r", radii)
	_pose_limbs()
	if dead:
		dead = false
		die()


func _bone(m: Mesh, r: float) -> MeshInstance3D:
	var b := Gfx.mesh(m, _bone_mat, 0, 0, 0, _limb_bones)
	b.scale = Vector3(r, 1, r) if m == _seg_mesh else Vector3(r, r, r)
	return b


func _make_limb(leg: bool, side: float, anchor: Vector3, rest: Vector3) -> Limb:
	var l := Limb.new()
	l.leg = leg
	l.side = side
	l.anchor = anchor
	l.anchor0 = anchor
	l.pos = rest
	if leg:  # gros pied rond, un peu allongé vers l'avant
		var f: float = _sp["leg"]["foot"]
		l.foot = Gfx.mesh(_skin_sph, _skin, 0, 0, 0, _content)
		l.foot.scale = Vector3(f, f * 0.7, f * 1.5)
		_skin_meshes.append(l.foot)
	l.upper = _bone(_seg_mesh, 0.028)
	l.lower = _bone(_seg_mesh, 0.026)
	l.joint = _bone(_sph_mesh, 0.042)
	l.end = _bone(_sph_mesh, 0.055)
	return l


func _add(parent: Node, m: Mesh, material: Material, x: float, y: float, z: float, sx := 1.0, sy := -1.0, sz := -1.0) -> MeshInstance3D:
	var mi := Gfx.mesh(m, material, x, y, z, parent)
	mi.scale = Vector3(sx, sx if sy < 0.0 else sy, sx if sz < 0.0 else sz)
	return mi


func _build_skeleton() -> void:
	var sp := _sp
	var head_y := _eye_y
	var head_z := _lean_at(head_y)
	var k := minf(1.0, (_radius_at(head_y) * 0.72) / 0.21)
	var skull := Node3D.new()
	skull.position = Vector3(0, head_y, head_z)
	skull.scale = Vector3(k, k, k)
	_add(skull, _sph_mesh, _bone_mat, 0, 0, 0, 0.21, 0.2, 0.2)  # crâne
	_add(skull, _sph_mesh, _dark_mat, -0.08, 0.03, 0.16, 0.055, 0.065, 0.04)  # orbites
	_add(skull, _sph_mesh, _dark_mat, 0.08, 0.03, 0.16, 0.055, 0.065, 0.04)
	_add(skull, _sph_mesh, _dark_mat, 0, -0.05, 0.19, 0.02, 0.03, 0.02)  # nez
	_add(skull, _box_mesh, _bone_mat, 0, -0.17, 0.1, 0.17, 0.07, 0.1)  # mâchoire
	for i in range(-2, 3):
		_add(skull, _box_mesh, _dark_mat, i * 0.033, -0.16, 0.152, 0.006, 0.05, 0.004)  # dents
	_bones.add_child(skull)

	var pelvis_y: float = sp["y0"] + 0.1
	var neck_y := head_y - 0.2 * k
	for i in 5:  # colonne, en tronçons qui suivent la courbure du corps
		var ya := pelvis_y + ((neck_y - pelvis_y) * i) / 5.0
		var yb := pelvis_y + ((neck_y - pelvis_y) * (i + 1)) / 5.0
		Gfx.stretch(Gfx.mesh(_seg_mesh, _bone_mat, 0, 0, 0, _bones), Vector3(0, ya, _lean_at(ya)), Vector3(0, yb, _lean_at(yb)), 0.03)
	var length := neck_y - pelvis_y
	var n := 3 if length > 0.4 else (1 if length > 0.15 else 0)
	for i in n:  # côtes
		var y := neck_y - 0.08 - (i * length * 0.5) / maxf(1.0, n - 1.0)
		var r := minf(0.2, _radius_at(y) * 0.66)
		Gfx.mesh(Shapes.torus(r, 0.022, 14, 6), _bone_mat, 0, y, _lean_at(y), _bones)
	_add(_bones, _box_mesh, _bone_mat, 0, pelvis_y, _lean_at(pelvis_y), minf(0.3, _radius_at(pelvis_y) * 1.2), 0.08, 0.13)  # bassin
	_pile_z = -(head_y + pelvis_y) / 2.0


func _build_eyes() -> void:
	var er: float = _sp["eye_r"] * 1.12
	var x := er * 0.88
	var surf := _radius_at(_eye_y)
	var z := _lean_at(_eye_y) + sqrt(maxf(0.0, surf * surf - x * x)) - er * 0.3
	for s in [-1.0, 1.0]:
		var eye := _add(_eyes, _sph_mesh, _white_mat, s * x, _eye_y, z, er)
		var pupil := _add(eye, _sph_mesh, _dark_mat, 0, 0, 0.66, 0.5)
		_pupils.append(pupil)


func _build_accessory() -> void:
	var g := Node3D.new()
	_hat.add_child(g)
	var acc: String = _sp.get("acc", "")
	if acc == "casquette":  # casquette jaune portée à l'envers
		var cr := 0.315
		var yellow := Gfx.mat(0xf7b92b, {"rough": 0.6})
		g.rotation.x = -0.18
		Gfx.mesh(Shapes.sphere_part(cr, 28, 12, 0.0, TAU, 0.0, 1.05), yellow, 0, 0, 0, g)
		var visor := Gfx.mesh(Shapes.cyl_part(0.27, 0.27, 0.04, 24, PI / 2.0, PI), yellow, 0, cr * cos(1.05) + 0.015, -0.2, g)
		visor.scale.z = 1.35
		visor.rotation.x = -0.12
		# ouverture de réglage à l'avant : on voit la tête au travers
		var hole := Gfx.mesh(_skin_sph, _skin, 0, cr * cos(0.72), cr * sin(0.72), g, false)
		hole.scale = Vector3(0.085, 0.06, 0.02)
		hole.rotation.x = -0.72
		_skin_meshes.append(hole)
		var strap := Gfx.mesh(Shapes.torus_arc(0.085, 0.016, 6, 16, PI), Gfx.mat(0xd99a12, {"rough": 0.6}), 0, cr * cos(0.76), cr * sin(0.76) + 0.008, g)
		strap.rotation.x = -0.72
	elif acc == "hélice":  # bonnet à quartiers rouges et blancs, hélice jaune
		g.rotation.z = -0.32
		var red := Gfx.mat(0xe8483f, {"rough": 0.6})
		var white := Gfx.mat(0xfff6ea, {"rough": 0.6})
		var yellow := Gfx.mat(0xffc93c, {"rough": 0.6})
		var base := 0.35
		var wedge := Shapes.sphere_part(0.2, 6, 8, 0.0, PI / 3.0, 0.0, PI / 2.0)
		for i in 6:
			var w := Gfx.mesh(wedge, white if i % 2 else red, 0, base, 0, g)
			w.rotation.y = i * PI / 3.0
		Gfx.mesh(Shapes.cylinder(0.016, 0.016, 0.1, 8), yellow, 0, base + 0.24, 0, g)
		var prop := Node3D.new()
		prop.position.y = base + 0.3
		g.add_child(prop)
		Gfx.mesh(Shapes.sphere(0.035, 10, 8), yellow, 0, 0, 0, prop)
		for s in [-1.0, 1.0]:
			_add(prop, _sph_mesh, yellow, s * 0.13, 0, 0, 0.13, 0.014, 0.055)
		_propeller = prop
	elif acc == "bouée":  # bouée à rayures orange et blanches
		var arc := Shapes.torus_arc(0.37, 0.125, 14, 6, PI / 4.0, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO))
		var orange := Gfx.mat(0xf58a3c, {"rough": 0.5})
		var white := Gfx.mat(0xfff6ea, {"rough": 0.5})
		for i in 8:
			var m := Gfx.mesh(arc, white if i % 2 else orange, 0, 0, 0, g)
			m.rotation.y = i * PI / 4.0
	elif acc == "bandeau":  # bandeau blanc à liseré rouge
		g.rotation.x = -0.14
		Gfx.mesh(Shapes.sphere_part(0.432, 32, 6, 0.0, TAU, 0.5, 0.48), Gfx.mat(0xfff6ea, {"rough": 0.6}), 0, 0, 0, g)
		Gfx.mesh(Shapes.sphere_part(0.438, 32, 3, 0.0, TAU, 0.67, 0.13), Gfx.mat(0xe8483f, {"rough": 0.6}), 0, 0, 0, g)


# ---------- dégâts ----------

## Ajoute un trou dans la peau (position locale au personnage).
func add_hit(p: Vector3, r: float) -> void:
	if _hits.size() >= MAX_HITS:
		# plus de place : on agrandit un trou existant, les trous finissent par fusionner
		var h: Dictionary = _hits.pick_random()
		h["r"] = minf(0.6, h["r"] + r * 0.5)
		return
	_hits.append({"p": p, "r": r, "cur": 0.02})


## Fait repousser la peau sur les `n` derniers trous.
func heal(n: int) -> void:
	for i in n:
		for j in range(_hits.size() - 1, -1, -1):
			if _hits[j]["r"] > 0.0:
				_hits[j]["r"] = 0.0
				break


func reset_damage() -> void:
	_hits.clear()
	for i in MAX_HITS:
		_hits_world[i] = Vector4.ZERO
	_skin.set_shader_parameter("hits", _hits_world)
	_bones.visible = false
	_limb_bones.visible = false
	if dead:
		_revive()


## PV à zéro : il ne reste que le squelette, qui s'écroule en tas d'os.
func die() -> void:
	if dead:
		return
	dead = true
	_dead_t = 0.0
	for m in _skin_meshes:
		m.visible = false
	_eyes.visible = false
	_bones.visible = true
	_limb_bones.visible = true
	for l in _limbs:
		l.pile_anchor = Vector3(randf_range(-0.3, 0.3), 0.06 + randf() * 0.1, randf_range(-0.3, 0.3))
		l.pile_end = Vector3(l.pile_anchor.x + randf_range(-0.35, 0.35), 0.05, l.pile_anchor.z + randf_range(-0.35, 0.35))
	_pile_y = 0.16
	_pile_rx = 1.42 + randf_range(-0.1, 0.1)
	_pile_rz = randf_range(-0.5, 0.5)


func _revive() -> void:
	dead = false
	for m in _skin_meshes:
		m.visible = true
	_eyes.visible = true
	_bones.position = Vector3.ZERO
	_bones.rotation = Vector3.ZERO
	_hat.position = Vector3(0, _sp.get("acc_y", 0.0), 0)
	_hat.rotation = Vector3.ZERO
	for l in _limbs:
		l.anchor = l.anchor0


# ---------- animation ----------

func update(dt: float, speed: float, vy: float, grounded: bool, tumble: bool, charging := false, dance := false) -> void:
	dt = minf(dt, 0.05)
	_time += dt
	var yaw := rotation.y
	var sp := _sp

	# accélération du corps dans son repère local → inertie des bras et des pupilles
	var wp := position
	if _first:
		_last_pos = wp
		_first = false
	var vel := (wp - _last_pos) / maxf(dt, 1e-3)
	if vel.length_squared() > 3600.0:
		vel = Vector3.ZERO  # téléportation
	_acc = ((vel - _last_vel) / maxf(dt, 1e-3)).limit_length(70.0)
	_last_vel = vel
	_last_pos = wp
	var co := cos(yaw)
	var si := sin(yaw)
	var ax := _acc.x * co - _acc.z * si
	var az := _acc.x * si + _acc.z * co
	var ay := _acc.y

	var k := minf(1.0, speed / 5.5)
	if grounded:
		_phase += speed * dt * 1.9
	else:
		_phase += dt * 9.0
	var ph := _phase

	# étirement / écrasement
	if grounded and not _was_grounded:
		_sq_v -= minf(5.0, 1.5 + absf(_last_vy) * 0.3)
	if not grounded and _was_grounded and vy > 1.0:
		_sq_v += 3.5
	_was_grounded = grounded
	_last_vy = vy
	_sq_v += ((1.0 - _sq) * 220.0 - _sq_v * 13.0) * dt
	_sq = clampf(_sq + _sq_v * dt, 0.55, 1.5)
	var stretch := 1.0 if dead else _sq + (0.0 if grounded else clampf(absf(vy) * 0.012, 0.0, 0.18))
	_squash.scale = Vector3(1.0 / sqrt(stretch), stretch, 1.0 / sqrt(stretch))

	# roulé-boulé
	if tumble and not dead:
		_spin += dt * 13.0
	else:
		_spin = atan2(sin(_spin), cos(_spin))
		_spin *= exp(-10.0 * dt)

	if dead:
		_update_dead(dt)
	else:
		var dn := 1.0 if dance else 0.0
		var bob := absf(sin(ph)) * 0.07 * k if grounded else 0.0
		_pivot.position.y = CENTER + bob + dn * absf(sin(_time * 7.0)) * 0.12
		_pivot.rotation = Vector3(k * 0.2 + _spin, 0, sin(ph) * 0.14 * k + dn * sin(_time * 7.0) * 0.2)
		_hat.rotation.x = sin(ph * 2.0) * 0.06 * k - clampf(az * 0.003, -0.2, 0.2)
		_hat.rotation.z = clampf(ax * 0.003, -0.2, 0.2)

		var leg: Dictionary = sp["leg"]
		var arm: Dictionary = sp["arm"]
		var rest: Array = arm["rest"]
		var lx: float = leg["x"] + 0.03
		var fy: float = leg["foot"] * 0.55
		var sd: float = leg["stride"]
		var sy := _shoulder_y
		var reach: float = arm["reach"]
		var arms_walk: bool = sp.get("arms_walk", false)
		for l in _limbs:
			var s := l.side
			var lp := ph + (0.0 if s > 0.0 else PI)
			var target: Vector3
			if l.leg:
				if hanging:
					target = Vector3(s * lx, fy + 0.05 + maxf(0.0, sin(_time * 6.0 + s * 1.3)) * 0.12, sin(_time * 5.0 + s) * 0.18 - 0.05)
				elif tumble:
					target = Vector3(s * 0.3, 0.3 + sin(_time * 15.0 + s) * 0.2, cos(_time * 13.0 + s) * 0.3)
				elif grounded:
					target = Vector3(s * lx, fy + maxf(0.0, sin(lp)) * 0.32 * k * sd + dn * maxf(0.0, sin(_time * 7.0 + s)) * 0.2, -cos(lp) * 0.44 * k * sd)
				else:
					target = Vector3(s * (lx + 0.05), fy + 0.13 + sin(_time * 13.0 + s * 2.0) * 0.09, -0.1 + s * 0.14 * sin(_time * 9.0))
				l.pos = l.pos.lerp(target, 1.0 - exp(-28.0 * dt))
			else:
				if hanging:
					target = Vector3(s * 0.14, sy + 1.2, 0.0)  # mains au câble
				elif tumble:
					target = Vector3(s * 0.7 * cos(_time * 17.0 + s), sy + 0.5 * sin(_time * 13.0), 0.5 * sin(_time * 11.0 + s))
				elif dance:
					target = Vector3(s * 0.55, sy + 0.5 + sin(_time * 7.0 + s * 1.5) * 0.25, 0.1)
				elif charging:
					target = Vector3(s * 0.2, sy - 0.05, 0.5)
				elif not grounded and vy < -3.0:
					target = Vector3(s * 0.62, sy + 0.5, 0)  # bras en l'air en tombant
				elif not grounded:
					target = Vector3(s * 0.72, sy - 0.05, 0)
				elif arms_walk:
					target = Vector3(s * rest[0], rest[1] + maxf(0.0, -sin(lp)) * 0.25 * k, rest[2] + cos(lp) * 0.4 * k)  # mains qui marchent
				else:
					target = Vector3(s * rest[0], rest[1], rest[2] + cos(lp) * 0.34 * k)
				# ressort sous-amorti : les bras traînent et rebondissent avec l'inertie
				var a := (target - l.pos) * 110.0
				a.x -= l.vel.x * 8.0 + ax * 0.55
				a.y -= l.vel.y * 8.0 + ay * 0.3
				a.z -= l.vel.z * 8.0 + az * 0.55
				l.vel += a * dt
				l.pos += l.vel * dt
				var d := l.pos - l.anchor
				if d.length() > reach:
					l.pos = l.anchor + d.normalized() * reach

		# yeux : clignement, pupilles qui ballottent, tournis pendant le roulé-boulé
		_blink -= dt
		if _blink < -0.12:
			_blink = 1.5 + randf() * 4.0
		_eyes.scale.y = 0.15 if _blink < 0.0 else 1.0
		_eyes.position.y = _eye_y * 0.85 if _blink < 0.0 else 0.0
		for i in _pupils.size():
			if tumble:
				_pupils[i].position = Vector3(cos(_time * 20.0 + i * 2.0) * 0.4, sin(_time * 20.0 + i * 2.0) * 0.4, 0.55)
			else:
				_pupils[i].position = Vector3(clampf(-ax * 0.008, -0.35, 0.35) + 0.1 + sin(_time * 0.7) * 0.1, 0.08 + clampf(-ay * 0.006, -0.35, 0.35), 0.66)
	if _propeller:
		_propeller.rotation.y += dt * (6.0 + speed * 4.0)

	_pose_limbs()

	# sphères d'impact en coordonnées monde pour le shader
	if not _hits.is_empty() or _hits_dirty:
		var xf := _content.global_transform
		for i in MAX_HITS:
			if i >= _hits.size():
				_hits_world[i] = Vector4.ZERO
				continue
			var h: Dictionary = _hits[i]
			h["cur"] += (h["r"] - h["cur"]) * minf(1.0, dt * 9.0)
			var w: Vector3 = xf * h["p"]
			_hits_world[i] = Vector4(w.x, w.y, w.z, 0.0 if h["cur"] < 0.015 else h["cur"])
		_skin.set_shader_parameter("hits", _hits_world)
		_hits = _hits.filter(func(h: Dictionary) -> bool: return h["r"] > 0.0 or h["cur"] > 0.02)
		_hits_dirty = not _hits.is_empty()
		if _hits.is_empty():
			for i in MAX_HITS:
				_hits_world[i] = Vector4.ZERO
			_skin.set_shader_parameter("hits", _hits_world)
		_bones.visible = dead or not _hits.is_empty()
		_limb_bones.visible = _bones.visible


## Pose des membres : tube de peau courbe (dans le shader), et deux os + articulation à l'intérieur.
func _pose_limbs() -> void:
	var lift: float = _sp["arm"].get("lift", 0.05)
	var foot_k: float = _sp["leg"]["foot"] * 0.3
	var show_bones := _limb_bones.visible
	for i in _limbs.size():
		var l := _limbs[i]
		var mid := (l.anchor + l.pos) * 0.5
		if not dead:
			if l.leg:
				mid.z += 0.12
			else:
				mid.x += l.side * 0.13
				mid.y += lift
				mid.z -= 0.04
			_la[i] = l.anchor
			_lc[i] = mid * 2.0 - l.anchor * 0.5 - l.pos * 0.5  # point de contrôle : la courbe passe par `mid`
			_le[i] = l.pos
			if l.foot:
				l.foot.position = Vector3(l.pos.x, l.pos.y, l.pos.z + foot_k)
		if show_bones:
			l.joint.position = mid
			l.end.position = l.pos
			Gfx.stretch(l.upper, l.anchor, mid, 0.028)
			Gfx.stretch(l.lower, mid, l.pos, 0.026)
	if not dead:
		_skin.set_shader_parameter("limb_a", _la)
		_skin.set_shader_parameter("limb_c", _lc)
		_skin.set_shader_parameter("limb_e", _le)


func _update_dead(dt: float) -> void:
	_dead_t += dt
	var t := minf(1.0, _dead_t / 0.45)
	var e := 1.0 - exp(-9.0 * dt)
	_pivot.position.y = CENTER
	_pivot.rotation = Vector3(_spin, 0, 0)
	# le crâne et les côtes basculent à plat, recentrés sur le tas
	_bones.position.y += (_pile_y - _bones.position.y) * e
	_bones.position.z += (_pile_z - _bones.position.z) * e
	_bones.rotation.x += (_pile_rx - _bones.rotation.x) * e
	_bones.rotation.z += (_pile_rz - _bones.rotation.z) * e
	var hd: Array = _sp.get("acc_dead", [0.0, 0.0, 0.0])
	_hat.position.y += (hd[1] - _hat.position.y) * e
	_hat.position.x += (hd[0] - _hat.position.x) * e
	_hat.rotation.x *= 1.0 - e
	_hat.rotation.z += (hd[2] - _hat.rotation.z) * e
	for l in _limbs:
		l.anchor = l.anchor.lerp(l.pile_anchor, e)
		l.pos = l.pos.lerp(l.pile_end, e)
		# petit rebond des os en touchant le sol
		l.pos.y += absf(sin(t * TAU)) * (1.0 - t) * 0.1
