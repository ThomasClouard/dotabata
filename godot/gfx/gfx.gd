class_name Gfx
extends RefCounted
## Boîte à outils graphique commune : matériaux « plastique brillant », formes arrondies, décors.
## Tout est procédural : aucune texture ni modèle à charger.

static var font: Font


## Couleur 0xRRGGBB → Color.
static func col(c: int) -> Color:
	return Color.hex((c << 8) | 0xff)


static func to_int(c: Color) -> int:
	return (c.r8 << 16) | (c.g8 << 8) | c.b8


## Matériau façon jouet en plastique. Options : rough, metal, glow, map, uv (Vector2), opacity, double (bool).
static func mat(color: int, o: Dictionary = {}) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col(color)
	m.roughness = o.get("rough", 0.42)
	m.metallic = o.get("metal", 0.0)
	m.metallic_specular = 0.5
	if o.has("map"):
		m.albedo_texture = o["map"]
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var uv: Vector2 = o.get("uv", Vector2.ONE)
		m.uv1_scale = Vector3(uv.x, uv.y, 1.0)
	if o.get("glow", 0.0) > 0.0:
		m.emission_enabled = true
		m.emission = col(color)
		m.emission_energy_multiplier = o["glow"]
	if o.get("opacity", 1.0) < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = o["opacity"]
	if o.get("double", false):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Matériau non éclairé (lignes, fantômes, éclairs). Options : opacity, double, add (fusion additive), no_depth.
static func flat(color: int, o: Dictionary = {}) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col(color)
	if o.get("opacity", 1.0) < 1.0 or o.get("add", false):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = o.get("opacity", 1.0)
	if o.get("double", false):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if o.get("add", false):
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if o.get("no_depth", false):
		m.no_depth_test = true
	return m


## Éclaircit (k > 1) ou assombrit (k < 1) une couleur, en espace linéaire comme three.js.
static func shade(color: int, k: float) -> int:
	var c := col(color).srgb_to_linear()
	if k <= 1.0:
		c = Color(c.r * k, c.g * k, c.b * k)
	else:
		c = c.lerp(Color.WHITE, minf(1.0, k - 1.0))
	return to_int(c.linear_to_srgb())


static func mesh(m: Mesh, material: Material, x := 0.0, y := 0.0, z := 0.0, parent: Node = null, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = Vector3(x, y, z)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent:
		parent.add_child(mi)
	return mi


static func _hash(x: float, y: float, z: float) -> float:
	var s := sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453
	return s - floorf(s)


## Rocher lisse et irrégulier, plat sur le dessus : dessous des plateformes et îles flottantes.
static func rock_under(w: float, h: float, d: float, color: int, seed_ := 0) -> MeshInstance3D:
	var data := Shapes.icosphere_data(2)
	var v: PackedVector3Array = data[0]
	var idx: PackedInt32Array = data[1]
	for i in v.size():
		var x := v[i].x
		var y := v[i].y
		var z := v[i].z
		var n := 0.82 + _hash(roundf(x * 3.0) + seed_, roundf(y * 3.0), roundf(z * 3.0)) * 0.3
		# silhouette plus carrée vue de dessus, pointe vers le bas
		var sq := 1.0 / maxf(maxf(absf(x), absf(z)), 0.55)
		var k := 1.0 - pow(-y, 1.6) * 0.55 if y < 0.0 else 1.0
		x *= minf(sq, 1.35) * k * n
		z *= minf(sq, 1.35) * k * n
		y = 0.0 if y > 0.0 else y * n
		v[i] = Vector3(x * w * 0.5, y * h, z * d * 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in v.size():
		st.add_vertex(v[i])
	# l'icosaèdre de base est orienté sens trigonométrique : on inverse pour Godot
	for i in range(0, idx.size(), 3):
		st.add_index(idx[i])
		st.add_index(idx[i + 2])
		st.add_index(idx[i + 1])
	st.generate_normals()
	return mesh(st.commit(), mat(color, {"rough": 0.9}))


## Plateforme prête à poser : corps arrondi, dessus plus clair avec un léger débord, rocher flottant dessous.
## Options : top (int), top_map, top_uv, under (bool), seed, glow.
static func slab(w: float, h: float, d: float, color: int, o: Dictionary = {}) -> Node3D:
	var g := Node3D.new()
	var cap_h := minf(0.24, h * 0.42)
	var body := mesh(Shapes.rbox(w, h - cap_h * 0.6, d, minf(0.22, h * 0.4)), mat(shade(color, 0.7)), 0, -cap_h * 0.3, 0, g)
	body.name = "corps"
	var top_opts := {}
	if o.has("top_map"):
		top_opts["map"] = o["top_map"]
		top_opts["uv"] = o.get("top_uv", Vector2.ONE)
	if o.has("glow"):
		top_opts["glow"] = o["glow"]
	var cap := mesh(Shapes.rbox(w + 0.1, cap_h, d + 0.1, cap_h * 0.48), mat(o.get("top", color), top_opts), 0, h / 2.0 - cap_h / 2.0, 0, g)
	cap.name = "dessus"
	if o.get("under", true) and minf(w, d) >= 2.0:
		var rock := rock_under(w * 0.92, minf(4.5, maxf(1.0, minf(w, d) * 0.5)), d * 0.92, shade(color, 0.45), o.get("seed", 0))
		rock.position.y = -h / 2.0 + 0.05
		g.add_child(rock)
	return g


## Texte 3D (pancartes, numéros).
static func label3d(text: String, height: float, color: Color, outline := Color(0, 0, 0, 0.35)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 96
	l.pixel_size = height / 96.0
	l.modulate = color
	l.outline_size = 14
	l.outline_modulate = outline
	l.double_sided = false
	l.shaded = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return l


## Panneau avec du texte sur ses deux faces (pancarte, bannière).
static func board(text: String, w: float, h: float, bg: String, fg: String, thick := 0.18) -> MeshInstance3D:
	var m := mesh(Shapes.rbox(w, h, thick, minf(0.08, thick * 0.4)), mat(to_int(Color(bg)), {"rough": 0.6}))
	for s in [1.0, -1.0]:
		var l := label3d(text, h * 0.62, Color(fg))
		l.position = Vector3(0, 0, s * (thick / 2.0 + 0.006))
		if s < 0.0:
			l.rotation.y = PI
		m.add_child(l)
	return m


## Ballon décoratif avec sa ficelle.
static func balloon(color: int) -> Node3D:
	var g := Node3D.new()
	var b := mesh(Shapes.sphere(0.55, 16, 12), mat(color, {"rough": 0.2}), 0, 0, 0, g)
	b.scale.y = 1.2
	mesh(Shapes.cylinder(0.0, 0.1, 0.16, 8), mat(color), 0, -0.7, 0, g)
	mesh(Shapes.cylinder(0.012, 0.012, 1.6, 4), flat(0xffffff), 0, -1.55, 0, g, false)
	return g


## Petit arbre rond stylisé.
static func tree(h := 3.0, leaf := 0x52d681) -> Node3D:
	var g := Node3D.new()
	mesh(Shapes.cylinder(0.16, 0.24, h * 0.55, 8), mat(0x9c6644, {"rough": 0.8}), 0, h * 0.275, 0, g)
	var s := Shapes.sphere(1.0, 14, 10)
	var leaf_mat := mat(leaf, {"rough": 0.7})
	for b in [[0.0, h * 0.72, 0.0, 0.9], [0.5, h * 0.6, 0.2, 0.6], [-0.45, h * 0.62, -0.25, 0.65], [0.1, h * 0.95, -0.1, 0.6]]:
		var k: float = b[3] * h * 0.3
		mesh(s, leaf_mat, b[0], b[1], b[2], g).scale = Vector3(k, k, k)
	return g


## Place un nœud entre deux points, étiré le long de son axe Y (os, bras de marteau, tige de piston).
static func stretch(node: Node3D, a: Vector3, b: Vector3, radius := 1.0) -> void:
	var d := b - a
	var length := maxf(0.001, d.length())
	node.transform = Transform3D(Basis(Quaternion(Vector3.UP, d / length)) * Basis.from_scale(Vector3(radius, length, radius)), (a + b) * 0.5)
