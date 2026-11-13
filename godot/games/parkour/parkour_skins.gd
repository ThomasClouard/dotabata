class_name ParkourSkins
extends RefCounted
## Parcours délirant — vague 4 (parcours dessinés) : apparences des dalles (paramètre `skin` : table, crayon, tourne-disque,
## télé, pot et feuilles de tournesol, nuages, avion, cerf-volant, oiseau, hélicoptère, rochers, éboulis…), nouveaux
## décors (bouquet, tige, nuage, étendoir, murs de la maison) et rendu des castors, jets de lave et chutes de pierres.
## La collision reste la boîte de l'élément : les objets sont dessinés pour que leur dessus coïncide avec elle.

## Types de dalle dont seul le corps change (le reste — arche, portique, déplacement — reste géré par le client).
const BODY_TYPES := ["platform", "start", "finish", "checkpoint", "moving", "crumble"]
## Types dont l'apparence gère aussi l'animation (dalle clignotante, plateau tournant).
const OWN_TYPES := ["blink", "turntable"]
const NEW_DECO := ["flowers", "stem", "cloud", "rack", "room"]
const CORNERS := [[-1.0, -1.0], [1.0, -1.0], [-1.0, 1.0], [1.0, 1.0]]
const FLOWER_COLORS := [0xff4d6d, 0xffd60a, 0xc77dff, 0xff9e00, 0x4cc9f0]

var ctx: Main
var level: Dictionary
var lstate: Dictionary
var recs: Array = []
var wires: Array = []  # fils d'étendoir (éléments), pour la pose d'équilibriste des autres joueurs
var _fx_timer := 0.0


func _init(c: Main, l: Dictionary, st: Dictionary) -> void:
	ctx = c
	level = l
	lstate = st
	for e: Dictionary in l["elements"]:
		if e.get("skin", "") == "wire":
			wires.append(e)


# ---------- outils ----------

static func _hash(a: float, b: float) -> float:
	var s := sin(a * 12.9898 + b * 78.233) * 43758.5453
	return s - floorf(s)


func _v(e: Dictionary) -> Vector3:
	return Vector3(e["pos"][0], e["pos"][1], e["pos"][2])


func _root(e: Dictionary, with_yaw := true) -> Node3D:
	var g := Node3D.new()
	g.position = _v(e)
	if with_yaw:
		g.rotation.y = e.get("yaw", 0.0)
	ctx.world.add_child(g)
	return g


func _color(e: Dictionary, def: int) -> int:
	return Gfx.to_int(Color(e["color"])) if e.get("color") != null else def


## Altitude du sol de la pièce (dessus d'un `hazard`) sous le point p, sinon p.y - fallback.
func _floor_below(p: Vector3, fallback := 6.0) -> float:
	var best := -INF
	for e: Dictionary in level["elements"]:
		if e["type"] != "hazard":
			continue
		var top := Level.top_of(e)
		if top < p.y and top > best and Level.in_zone(e, p.x, e["pos"][1], p.z):
			best = top
	return best if best > -INF else p.y - fallback


## Amas de boules de nuage dont le dessus affleure à h/2 (dans la boîte w × h × d centrée).
func _puffs(parent: Node3D, w: float, h: float, d: float, seed_: int, color := 0xffffff) -> Node3D:
	var g := Node3D.new()
	parent.add_child(g)
	var m := Gfx.mat(color, {"rough": 0.95})
	m.rim = 0.6
	var core := Gfx.mesh(Shapes.sphere(1.0, 20, 12), m, 0, 0, 0, g)
	core.scale = Vector3(w / 2.0, h / 2.0, d / 2.0)
	var n := clampi(int(w * d / 3.0), 4, 14)
	for k in n:
		var a := k * TAU / n + _hash(seed_, k) * 0.6
		var r := minf(w, d) * (0.22 + _hash(k, seed_ + 3) * 0.12)
		var p := Vector3(cos(a) * (w / 2.0 - r * 0.55), h / 2.0 - r * 0.62, sin(a) * (d / 2.0 - r * 0.55))
		var s := Gfx.mesh(Shapes.sphere(1.0, 14, 10), m, p.x, p.y, p.z, g)
		s.scale = Vector3(r, r * 0.62, r)
	return g


## Triangle plat (double face), sommets dans le repère du parent.
static func _tri(a: Vector3, b: Vector3, c: Vector3) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var n := (b - a).cross(c - a).normalized()
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([a, b, c])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([n, n, n])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# ---------- construction ----------

## Corps d'une dalle avec apparence, centré sur sa boîte (non ajouté au monde), ou null sans `skin`.
func body(e: Dictionary, i: int) -> Node3D:
	var skin: String = e.get("skin", "")
	if skin == "" or not e["type"] in BODY_TYPES:
		return null
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var sz: float = e["size"][2]
	var g := Node3D.new()
	var rec := {"e": e, "i": i, "skin": skin, "type": e["type"]}
	match skin:
		"table":
			_table(g, e, sx, sy, sz)
		"notebook":
			_notebook(g, e, sx, sy, sz)
		"pencilcase":
			_pencilcase(g, e, sx, sy, sz)
		"pencil":
			_pencil(g, sx, sy, sz)
		"tv":
			_tv(g, e, sx, sy, sz)
		"pot":
			_pot(g, sx, sy, sz)
		"leaf":
			_leaf(g, sx, sy, sz)
		"wire":
			_wire(g, sx, sy, sz)
		"cloud":
			rec["puffs"] = _puffs(g, sx, sy, sz, i)
		"plane":
			_plane(g, e, sx, sy, sz, rec)
		"kite":
			_kite(g, sx, sy, sz, rec)
		"bird":
			_bird(g, e, sx, sy, sz)
		"heli":
			_heli(g, sx, sy, sz, rec)
		"rock", "scree":
			_rock(g, sx, sy, sz, i)
		_:
			# apparence sans corps propre à ce type (ex. "record" sur une plateforme) : dalle neutre
			g.add_child(Gfx.slab(sx, sy, sz, _color(e, 0xc9a8e8), {"seed": i}))
	rec["node"] = g
	if rec.size() > 5:
		recs.append(rec)
	return g


## Éléments rendus entièrement ici : nouvelles mécaniques, nouveaux décors, dalles clignotantes et plateaux habillés.
func build(e: Dictionary, i: int) -> Node3D:
	var type: String = e["type"]
	var skin: String = e.get("skin", "")
	var rec := {"e": e, "i": i, "type": type, "skin": skin}
	var root: Node3D = null
	if type == "popper":
		root = _popper(e, i, rec)
	elif type == "geyser":
		root = _geyser(e, rec)
	elif type == "rockfall":
		root = _rockfall(e, rec)
	elif type == "deco" and e.get("kind", "tree") in NEW_DECO:
		root = _deco(e, i, rec)
	elif type in OWN_TYPES and skin != "":
		match skin:
			"record":
				root = _record(e, rec)
			"sunflower":
				root = _sunflower(e, rec)
			"wing":
				root = _wing(e, rec)
			"scree":
				root = _scree(e, i, rec)
			"cloud":
				root = _root(e)
				rec["puffs"] = _puffs(root, e["size"][0], e["size"][1], e["size"][2], i)
				rec["ghost"] = Gfx.mesh(Shapes.rbox(e["size"][0], e["size"][1], e["size"][2], 0.3), Gfx.flat(0xffffff, {"opacity": 0.12}), 0, 0, 0, root, false)
		if root == null:
			return null
	if root != null:
		rec["root"] = root
		recs.append(rec)
	return root


# —— maison ——

func _table(g: Node3D, e: Dictionary, sx: float, sy: float, sz: float) -> void:
	var wood := _color(e, 0xc98846)
	Gfx.mesh(Shapes.rbox(sx, sy, sz, minf(0.15, sy * 0.3)), Gfx.mat(0xffffff, {"map": Tex.planks(), "uv": Vector2(maxf(1.0, sx / 3.0), maxf(1.0, sz / 3.0)), "rough": 0.55}), 0, 0, 0, g)
	# pieds jusqu'au sol de la pièce
	var p := _v(e)
	var bottom := -sy / 2.0
	var fy := _floor_below(p + Vector3(0, bottom, 0)) - p.y
	var legh := bottom - fy
	if legh > 0.2:
		var lr := clampf(minf(sx, sz) * 0.05, 0.18, 0.45)
		var lm := Gfx.mat(Gfx.shade(wood, 0.75), {"rough": 0.6})
		for c: Array in CORNERS:
			Gfx.mesh(Shapes.cylinder(lr, lr * 0.75, legh, 12), lm, c[0] * (sx / 2.0 - lr * 1.8), bottom - legh / 2.0, c[1] * (sz / 2.0 - lr * 1.8), g)


func _notebook(g: Node3D, e: Dictionary, sx: float, sy: float, sz: float) -> void:
	var cover := _color(e, 0x4361ee)
	var ch := minf(0.12, sy * 0.15)
	# couverture du dessous, pages, page ouverte lignée sur le dessus
	Gfx.mesh(Shapes.rbox(sx, ch, sz, ch * 0.4), Gfx.mat(cover, {"rough": 0.5}), 0, -sy / 2.0 + ch / 2.0, 0, g)
	Gfx.mesh(Shapes.rbox(sx * 0.97, sy - ch * 2.0, sz * 0.96, 0.04), Gfx.mat(0xf3eee0, {"rough": 0.8}), 0, 0, 0, g)
	Gfx.mesh(Shapes.rbox(sx * 0.98, ch, sz * 0.97, ch * 0.4), Gfx.mat(0xffffff, {"map": Tex.lined(), "uv": Vector2(maxf(1.0, sx / 3.0), maxf(1.0, sz / 3.0)), "rough": 0.8}), 0, sy / 2.0 - ch / 2.0, 0, g)
	# spirale le long du bord -x local
	var ring := Gfx.mat(0xc0c7d0, {"metal": 0.7, "rough": 0.25})
	var n := maxi(3, int(sz / 0.7))
	for k in n:
		var z := -sz / 2.0 + (k + 0.5) * sz / n
		var t := Gfx.mesh(Shapes.torus(sy * 0.42, 0.05, 16, 6), ring, -sx / 2.0, 0, z, g)
		t.rotation.x = PI / 2.0


func _pencilcase(g: Node3D, e: Dictionary, sx: float, sy: float, sz: float) -> void:
	var c := _color(e, 0xff7eb6)
	Gfx.mesh(Shapes.rbox(sx, sy, sz, minf(sy, minf(sx, sz)) * 0.42), Gfx.mat(c, {"rough": 0.55}), 0, 0, 0, g)
	# fermeture éclair le long du dessus, et sa tirette
	Gfx.mesh(Shapes.rbox(sx * 0.86, 0.06, 0.16, 0.03), Gfx.mat(0x2b2140, {"rough": 0.4}), 0, sy / 2.0 - 0.01, 0, g)
	Gfx.mesh(Shapes.rbox(0.18, 0.08, 0.36, 0.04), Gfx.mat(0xd9dde3, {"metal": 0.7, "rough": 0.25}), sx * 0.43, sy / 2.0 + 0.02, 0.18, g)


## Crayon couché le long de z local : gomme à -z, mine à +z.
func _pencil(g: Node3D, sx: float, sy: float, sz: float) -> void:
	var r := minf(sx, sy) / 2.0
	var parts := [[0.07, 0xff8fab, r * 0.95, r * 0.95], [0.05, 0xc0c7d0, r, r], [0.67, 0xffc300, r, r], [0.16, 0xf1c27d, r, 0.0], [0.05, 0x2b2140, r * 0.32, 0.0]]
	var z := -sz / 2.0
	for k in parts.size():
		var p: Array = parts[k]
		var h: float = p[0] * sz
		var bottom_r: float = p[2]
		var top_r: float = p[3]
		if k == 4:
			z -= h  # la mine est le bout du cône de bois
			bottom_r = r * 0.3
		var seg := 6 if k == 2 else 16
		var m := Gfx.mesh(Shapes.cylinder(top_r, bottom_r, h, seg), Gfx.mat(p[1], {"rough": 0.35 if k == 2 else 0.6, "metal": 0.6 if k == 1 else 0.0}), 0, 0, z + h / 2.0, g)
		# couché le long de z (le +y du cylindre vers +z) ; le corps hexagonal tourné d'1/12 de tour : une face à plat dessus
		m.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.UP, PI / 6.0 if k == 2 else 0.0)
		z += h
	# liseré vert du crayon
	var band := Gfx.mesh(Shapes.cylinder(r * 1.02, r * 1.02, sz * 0.03, 6), Gfx.mat(0x2d9c4a), 0, 0, -sz / 2.0 + sz * 0.15, g)
	band.basis = Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.UP, PI / 6.0)


func _tv(g: Node3D, e: Dictionary, sx: float, sy: float, sz: float) -> void:
	Gfx.mesh(Shapes.rbox(sx, sy, sz, 0.25), Gfx.mat(_color(e, 0x2b2d42), {"rough": 0.35}), 0, 0, 0, g)
	# écrans sur les deux grandes faces (x local), avec un dessin animé : soleil et colline
	for s in [-1.0, 1.0]:
		var scr := Gfx.mesh(Shapes.rbox(0.06, sy * 0.74, sz * 0.82, 0.04), Gfx.mat(0x4cc9f0, {"glow": 0.7, "rough": 0.1}), s * (sx / 2.0 + 0.01), sy * 0.04, 0, g)
		scr.name = "écran"
		Gfx.mesh(Shapes.sphere(sy * 0.12, 12, 8), Gfx.mat(0xffd60a, {"glow": 1.2}), s * (sx / 2.0 + 0.05), sy * 0.2, sz * 0.22, g, false)
		var hill := Gfx.mesh(Shapes.sphere(1.0, 16, 8), Gfx.mat(0x70e000, {"glow": 0.5}), s * (sx / 2.0 + 0.03), -sy * 0.3, -sz * 0.1, g, false)
		hill.scale = Vector3(0.05, sy * 0.25, sz * 0.32)
		for k in 3:
			Gfx.mesh(Shapes.sphere(0.12, 8, 6), Gfx.mat(0xd9dde3, {"metal": 0.5}), s * (sx / 2.0 + 0.04), -sy * 0.43, sz * (0.2 + k * 0.08), g)
	# pied jusqu'au sol de la pièce
	var p := _v(e)
	var fy := _floor_below(p + Vector3(0, -sy / 2.0, 0)) - p.y
	var h := -sy / 2.0 - fy
	if h > 0.2:
		var sm := Gfx.mat(0x5c6470, {"metal": 0.5, "rough": 0.3})
		Gfx.mesh(Shapes.cylinder(0.35, 0.45, h, 14), sm, 0, -sy / 2.0 - h / 2.0, 0, g)
		Gfx.mesh(Shapes.cylinder(minf(sx, sz) * 0.35, minf(sx, sz) * 0.4, 0.25, 24), sm, 0, fy + 0.12, 0, g)


func _pot(g: Node3D, sx: float, sy: float, sz: float) -> void:
	var r := minf(sx, sz) / 2.0
	var terra := Gfx.mat(0xd9734e, {"rough": 0.7})
	Gfx.mesh(Shapes.cylinder(r * 0.98, r * 0.76, sy, 28), terra, 0, 0, 0, g)
	Gfx.mesh(Shapes.torus(r * 0.98, minf(0.3, sy * 0.1), 36, 10), Gfx.mat(Gfx.shade(0xd9734e, 0.85), {"rough": 0.7}), 0, sy / 2.0 - 0.12, 0, g)
	Gfx.mesh(Shapes.cylinder(r * 0.93, r * 0.93, 0.1, 28), Gfx.mat(0x5b3a29, {"rough": 0.95}), 0, sy / 2.0 - 0.03, 0, g)


## Feuille de tournesol : la queue part du bord -x local (orienter la feuille avec yaw vers la tige).
func _leaf(g: Node3D, sx: float, sy: float, sz: float) -> void:
	var lm := Gfx.mat(0x52b043, {"rough": 0.5})
	var leaf := Gfx.mesh(Shapes.sphere(1.0, 20, 10), lm, 0, 0, 0, g)
	leaf.scale = Vector3(sx / 2.0, sy / 2.0, sz / 2.0)
	Gfx.mesh(Shapes.rbox(sx * 0.86, 0.05, 0.1, 0.02), Gfx.mat(0x95d56b), 0, sy / 2.0 - 0.01, 0, g, false)
	for s in [-1.0, 1.0]:
		for k in 3:
			var v := Gfx.mesh(Shapes.rbox(sz * 0.32, 0.04, 0.07, 0.02), Gfx.mat(0x95d56b), -sx * 0.25 + k * sx * 0.22, sy / 2.0 - 0.03 - k * 0.03, s * sz * 0.12, g, false)
			v.rotation.y = s * 0.9
	var stalk := Gfx.mesh(Shapes.cylinder(0.12, 0.12, 1.0, 8), lm, 0, 0, 0, g)
	Gfx.stretch(stalk, Vector3(-sx / 2.0 + 0.2, 0, 0), Vector3(-sx / 2.0 - 1.0, -0.35, 0), 0.14)


## Fil d'étendoir le long de x local : corde fine, pinces à linge.
func _wire(g: Node3D, sx: float, sy: float, _sz: float) -> void:
	var cord := Gfx.mesh(Shapes.cylinder(0.05, 0.05, sx, 8), Gfx.mat(0xf1f3f5, {"rough": 0.5}), 0, sy / 2.0 - 0.05, 0, g)
	cord.rotation.z = PI / 2.0
	var n := maxi(1, int(sx / 2.5))
	for k in n:
		var x := -sx / 2.0 + (k + 0.5) * sx / n + 0.4
		Gfx.mesh(Shapes.rbox(0.12, 0.34, 0.08, 0.03), Gfx.mat(FLOWER_COLORS[k % FLOWER_COLORS.size()], {"rough": 0.4}), x, sy / 2.0 - 0.2, 0, g)


# —— ciel ——

## Avion : fuselage le long de z local (nez à +z), ailes au ras du dessus, hublots, dérive et hélice.
func _plane(g: Node3D, e: Dictionary, sx: float, sy: float, sz: float, rec: Dictionary) -> void:
	var body_c := _color(e, 0xf8f9fa)
	var rad := sy / 2.0
	var fus := Gfx.mesh(Shapes.capsule(rad, maxf(0.1, sz - 2.0 * rad)), Gfx.mat(body_c, {"rough": 0.3}), 0, 0, 0, g)
	fus.rotation.x = PI / 2.0
	var red := Gfx.mat(0xe63946, {"rough": 0.3})
	var band := Gfx.mesh(Shapes.cylinder(rad * 1.02, rad * 1.02, sz * 0.12, 24), red, 0, 0, sz * 0.18, g)
	band.rotation.x = PI / 2.0
	# ailes : leur dessus affleure au dessus de la boîte (on marche dessus)
	Gfx.mesh(Shapes.rbox(sx, sy * 0.16, sz * 0.32, 0.08), red, 0, sy / 2.0 - sy * 0.08, -sz * 0.04, g)
	Gfx.mesh(Shapes.rbox(sx * 0.42, sy * 0.12, sz * 0.14, 0.06), red, 0, sy / 2.0 - sy * 0.06, -sz / 2.0 + sz * 0.08, g)
	# hublots
	var glass := Gfx.mat(0x2b5d9b, {"rough": 0.1, "metal": 0.2})
	var n := maxi(2, int(sz / 1.0))
	for s in [-1.0, 1.0]:
		for k in n:
			var z := -sz * 0.32 + k * (sz * 0.62 / maxf(1.0, n - 1))
			var w := Gfx.mesh(Shapes.cylinder(rad * 0.22, rad * 0.22, 0.06, 12), glass, s * rad * 0.97, rad * 0.1, z, g, false)
			w.rotation.z = PI / 2.0
	# dérive à l'arrière, hélice au nez
	Gfx.mesh(Shapes.rbox(0.14, rad * 1.5, rad * 1.3, 0.06), red, 0, rad * 1.1, -sz / 2.0 + rad * 0.3, g)
	var prop := Node3D.new()
	prop.position = Vector3(0, 0, sz / 2.0 + 0.12)
	g.add_child(prop)
	Gfx.mesh(Shapes.sphere(rad * 0.35, 12, 8), Gfx.mat(0xffd60a, {"metal": 0.3}), 0, 0, 0, prop)
	for k in 2:
		var b := Gfx.mesh(Shapes.rbox(0.18, rad * 2.4, 0.06, 0.03), Gfx.mat(0x3d4450, {"metal": 0.4}), 0, 0, 0.05, prop)
		b.rotation.z = k * PI / 2.0
	rec["prop"] = prop


## Cerf-volant : losange coloré à plat (dessus de la boîte), baguettes en croix, queue à nœuds qui ondule, ficelle.
func _kite(g: Node3D, sx: float, sy: float, sz: float, rec: Dictionary) -> void:
	var ax := sx * 0.72
	var az := sz * 0.72
	var y := sy / 2.0 - 0.03
	var c := Vector3(0, y, sz * 0.08)
	var pts := [Vector3(ax, y, c.z), Vector3(0, y, az), Vector3(-ax, y, c.z), Vector3(0, y, -az)]
	var cols := [0xff4d6d, 0xffd60a, 0x4cc9f0, 0x70e000]
	for k in 4:
		Gfx.mesh(_tri(c, pts[k], pts[(k + 1) % 4]), Gfx.mat(cols[k], {"double": true, "rough": 0.5}), 0, 0, 0, g)
	# épaisseur sous la toile (on marche sur un vrai objet)
	var under := Gfx.mesh(Shapes.rbox(sx * 0.6, sy * 0.6, sz * 0.6, 0.1), Gfx.mat(0xf1f3f5, {"rough": 0.6}), 0, -sy * 0.1, c.z * 0.5, g)
	under.rotation.y = PI / 4.0
	var stick := Gfx.mat(0x9c6644, {"rough": 0.7})
	var s1 := Gfx.mesh(Shapes.cylinder(0.05, 0.05, 1.0, 6), stick, 0, 0, 0, g)
	Gfx.stretch(s1, pts[0] + Vector3(0, 0.03, 0), pts[2] + Vector3(0, 0.03, 0), 0.06)
	var s2 := Gfx.mesh(Shapes.cylinder(0.05, 0.05, 1.0, 6), stick, 0, 0, 0, g)
	Gfx.stretch(s2, pts[1] + Vector3(0, 0.03, 0), pts[3] + Vector3(0, 0.03, 0), 0.06)
	# queue : nœuds à partir de la pointe arrière (-z)
	var bows := []
	for k in 6:
		var b := Node3D.new()
		g.add_child(b)
		for s in [-1.0, 1.0]:
			var w := Gfx.mesh(Shapes.sphere(0.22, 8, 6), Gfx.mat(cols[k % 4], {"rough": 0.5}), s * 0.2, 0, 0, b)
			w.scale = Vector3(1.0, 0.45, 0.7)
		bows.append(b)
	var ribbon := []
	for k in 6:
		ribbon.append(Gfx.mesh(Shapes.cylinder(0.025, 0.025, 1.0, 4), Gfx.flat(0xffffff), 0, 0, 0, g, false))
	rec["bows"] = bows
	rec["ribbon"] = ribbon
	rec["tip"] = pts[3]
	# ficelle qui descend vers l'avant
	var str_m := Gfx.mesh(Shapes.cylinder(0.02, 0.02, 1.0, 4), Gfx.flat(0xffffff), 0, 0, 0, g, false)
	Gfx.stretch(str_m, Vector3(0, -sy / 2.0, 0), Vector3(0, -sy / 2.0 - 14.0, 9.0), 1.0)


## Oiseau : corps rond (le dos est le dessus de la boîte), tête à +z local, queue en éventail à -z.
func _bird(g: Node3D, e: Dictionary, sx: float, sy: float, sz: float) -> void:
	var c := _color(e, 0x5aa9e6)
	var bm := Gfx.mat(c, {"rough": 0.45})
	var body_m := Gfx.mesh(Shapes.sphere(1.0, 24, 14), bm, 0, 0, 0, g)
	body_m.scale = Vector3(sx / 2.0, sy / 2.0, sz / 2.0)
	var belly := Gfx.mesh(Shapes.sphere(1.0, 20, 10), Gfx.mat(0xfff1d6, {"rough": 0.5}), 0, -sy * 0.12, sz * 0.05, g)
	belly.scale = Vector3(sx * 0.4, sy * 0.4, sz * 0.4)
	var hr := minf(sx, sy) * 0.42
	var head := Vector3(0, sy * 0.25, sz / 2.0 + hr * 0.45)
	Gfx.mesh(Shapes.sphere(hr, 20, 12), bm, head.x, head.y, head.z, g)
	var beak := Gfx.mesh(Shapes.cylinder(0.0, hr * 0.38, hr * 0.9, 12), Gfx.mat(0xff9e00, {"rough": 0.4}), head.x, head.y - hr * 0.1, head.z + hr * 1.2, g)
	beak.rotation.x = PI / 2.0
	for s in [-1.0, 1.0]:
		Gfx.mesh(Shapes.sphere(hr * 0.26, 10, 8), Gfx.mat(0xffffff), s * hr * 0.55, head.y + hr * 0.25, head.z + hr * 0.62, g)
		Gfx.mesh(Shapes.sphere(hr * 0.13, 8, 6), Gfx.flat(0x1a1a2e), s * hr * 0.62, head.y + hr * 0.28, head.z + hr * 0.82, g, false)
	for k in 3:
		var f := Gfx.mesh(Shapes.sphere(1.0, 12, 8), Gfx.mat(Gfx.shade(c, 0.8), {"rough": 0.5}), (k - 1) * sx * 0.16, sy * 0.05, -sz / 2.0 - sz * 0.12, g)
		f.scale = Vector3(sx * 0.1, sy * 0.08, sz * 0.22)
		f.rotation.y = (k - 1) * 0.35


## Hélicoptère : cabine (le toit est l'arrivée), bulle vitrée à +z local, poutre de queue à -z, patins, rotors qui tournent.
func _heli(g: Node3D, sx: float, sy: float, sz: float, rec: Dictionary) -> void:
	var paint := Gfx.mat(0xffd60a, {"rough": 0.3})
	Gfx.mesh(Shapes.rbox(sx, sy, sz, minf(1.0, sy * 0.45)), paint, 0, 0, 0, g)
	var bubble := Gfx.mesh(Shapes.sphere(1.0, 24, 14), Gfx.mat(0x8fd3ff, {"rough": 0.05, "metal": 0.2, "opacity": 0.82}), 0, -sy * 0.05, sz / 2.0, g)
	bubble.scale = Vector3(sx * 0.42, sy * 0.42, sz * 0.22)
	# H d'héliport sur le toit
	var white := Gfx.mat(0xffffff, {"rough": 0.4})
	var hh := minf(sx, sz) * 0.4
	for s in [-1.0, 1.0]:
		Gfx.mesh(Shapes.box(hh * 0.18, 0.04, hh), white, s * hh * 0.35, sy / 2.0 + 0.01, 0, g, false)
	Gfx.mesh(Shapes.box(hh * 0.7, 0.04, hh * 0.18), white, 0, sy / 2.0 + 0.01, 0, g, false)
	var boom := Gfx.mesh(Shapes.cylinder(sy * 0.12, sy * 0.2, sz * 0.9, 14), paint, 0, sy * 0.15, -sz / 2.0 - sz * 0.42, g)
	boom.rotation.x = PI / 2.0
	Gfx.mesh(Shapes.rbox(0.18, sy * 0.7, sz * 0.18, 0.06), Gfx.mat(0xe63946), 0, sy * 0.45, -sz / 2.0 - sz * 0.85, g)
	var trot := Node3D.new()
	trot.position = Vector3(0.2, sy * 0.45, -sz / 2.0 - sz * 0.85)
	g.add_child(trot)
	for k in 2:
		var b := Gfx.mesh(Shapes.rbox(0.06, sy * 0.8, 0.14, 0.03), Gfx.mat(0x3d4450), 0, 0, 0, trot)
		b.rotation.x = k * PI / 2.0
	# patins
	var skid := Gfx.mat(0x3d4450, {"metal": 0.5, "rough": 0.3})
	for s in [-1.0, 1.0]:
		var bar := Gfx.mesh(Shapes.cylinder(0.12, 0.12, sz * 1.1, 10), skid, s * sx * 0.38, -sy / 2.0 - 0.55, 0, g)
		bar.rotation.x = PI / 2.0
		for z in [-0.3, 0.3]:
			Gfx.mesh(Shapes.cylinder(0.08, 0.08, 0.6, 6), skid, s * sx * 0.38, -sy / 2.0 - 0.27, z * sz, g)
	# mât et grand rotor, bien au-dessus des têtes
	Gfx.mesh(Shapes.cylinder(0.14, 0.2, 3.2, 10), skid, 0, sy / 2.0 + 1.6, 0, g)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, sy / 2.0 + 3.2, 0)
	g.add_child(rotor)
	Gfx.mesh(Shapes.sphere(0.3, 12, 8), Gfx.mat(0xe63946), 0, 0, 0, rotor)
	for k in 2:
		var b := Gfx.mesh(Shapes.rbox(maxf(sx, sz) * 1.7, 0.08, 0.45, 0.04), Gfx.mat(0x2b2d42, {"rough": 0.4}), 0, 0, 0, rotor)
		b.rotation.y = k * PI / 2.0
	rec["rotor"] = rotor
	rec["trotor"] = trot


# —— volcan ——

func _rock(g: Node3D, sx: float, sy: float, sz: float, i: int) -> void:
	var slab := Gfx.slab(sx, sy, sz, 0x5a4a44, {"top": 0xffffff, "top_map": Tex.veins("#4a3c37", "#ff7b1c"), "top_uv": Vector2(maxf(1.0, sx / 4.0), maxf(1.0, sz / 4.0)), "seed": i})
	g.add_child(slab)
	var cap: MeshInstance3D = slab.get_node("dessus")
	var m: StandardMaterial3D = cap.material_override
	m.emission_enabled = true
	m.emission_texture = m.albedo_texture
	m.emission = Color(1.0, 0.45, 0.1)
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.85


# ---------- éléments rendus entièrement ici ----------

## Tourne-disque : socle en bois fixe, vinyle qui tourne (sillons, étiquette), bras de lecture sur le côté.
func _record(e: Dictionary, rec: Dictionary) -> Node3D:
	var root := _root(e, false)
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var r := sx / 2.0
	Gfx.mesh(Shapes.rbox(sx * 1.3, sy * 0.8, sx * 1.3, 0.25), Gfx.mat(0xffffff, {"map": Tex.planks(), "uv": Vector2(2, 2), "rough": 0.6}), 0, -sy * 0.45, 0, root)
	var spin := Node3D.new()
	root.add_child(spin)
	Gfx.mesh(Shapes.cylinder(r, r, sy * 0.5, 48), Gfx.mat(0x16161c, {"rough": 0.22, "metal": 0.25}), 0, sy * 0.25, 0, spin)
	var groove := Gfx.mat(0x34343f, {"rough": 0.3})
	for k in 5:
		Gfx.mesh(Shapes.torus(r * (0.42 + k * 0.11), 0.015, 64, 4), groove, 0, sy / 2.0, 0, spin, false)
	Gfx.mesh(Shapes.cylinder(r * 0.3, r * 0.3, 0.04, 32), Gfx.mat(0xe63946, {"rough": 0.4}), 0, sy / 2.0 + 0.01, 0, spin, false)
	Gfx.mesh(Shapes.rbox(r * 0.22, 0.05, r * 0.06, 0.02), Gfx.mat(0xffd60a), r * 0.12, sy / 2.0 + 0.04, 0, spin, false)
	Gfx.mesh(Shapes.cylinder(0.08, 0.08, 0.3, 8), Gfx.mat(0xd9dde3, {"metal": 0.8}), 0, sy / 2.0 + 0.15, 0, spin)
	# bras de lecture posé hors du disque
	var arm := Gfx.mat(0xd9dde3, {"metal": 0.8, "rough": 0.2})
	var base := Vector3(r * 1.12, sy / 2.0, -r * 0.95)
	Gfx.mesh(Shapes.cylinder(0.28, 0.32, 0.5, 14), arm, base.x, base.y + 0.1, base.z, root)
	var a := Gfx.mesh(Shapes.cylinder(0.07, 0.07, 1.0, 8), arm, 0, 0, 0, root)
	Gfx.stretch(a, base + Vector3(0, 0.35, 0), Vector3(r * 1.12, sy / 2.0 + 0.3, r * 0.5), 1.0)
	Gfx.mesh(Shapes.rbox(0.3, 0.18, 0.45, 0.05), Gfx.mat(0x2b2140), r * 1.12, sy / 2.0 + 0.25, r * 0.55, root)
	rec["spin"] = spin
	return root


## Cœur de tournesol qui tourne : disque de graines entouré de pétales.
func _sunflower(e: Dictionary, rec: Dictionary) -> Node3D:
	var root := _root(e, false)
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var r := sx / 2.0
	var spin := Node3D.new()
	root.add_child(spin)
	Gfx.mesh(Shapes.cylinder(r * 0.6, r * 0.55, sy, 36), Gfx.mat(0xffffff, {"map": Tex.target("#5a3418", "#7a4a24"), "rough": 0.9}), 0, 0, 0, spin)
	var seed_m := Gfx.mat(0x3d2210, {"rough": 0.9})
	for k in 24:
		var a := k * 2.39996
		var d := r * 0.55 * sqrt((k + 0.5) / 24.0)
		Gfx.mesh(Shapes.sphere(0.1, 6, 4), seed_m, cos(a) * d, sy / 2.0, sin(a) * d, spin, false)
	var petal := Gfx.mat(0xffd60a, {"rough": 0.45})
	var n := 18
	for k in n:
		var a := k * TAU / n
		var p := Gfx.mesh(Shapes.sphere(1.0, 12, 6), petal, cos(a) * r * 0.8, sy * 0.15 - (k % 2) * 0.08, sin(a) * r * 0.8, spin)
		p.scale = Vector3(r * 0.32, sy * 0.35, r * 0.12)
		p.rotation.y = -a
	var sepal := Gfx.mesh(Shapes.sphere(1.0, 20, 8), Gfx.mat(0x2d9c4a, {"rough": 0.6}), 0, -sy * 0.4, 0, root)
	sepal.scale = Vector3(r * 0.7, sy * 0.6, r * 0.7)
	rec["spin"] = spin
	return root


## Aile d'oiseau (dalle clignotante) : charnière au bord -x local ; elle se replie vers le haut quand la dalle disparaît.
func _wing(e: Dictionary, rec: Dictionary) -> Node3D:
	var root := _root(e)
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var sz: float = e["size"][2]
	var hinge := Node3D.new()
	hinge.position.x = -sx / 2.0
	root.add_child(hinge)
	var c := _color(e, 0x5aa9e6)
	var wm := Gfx.mat(c, {"rough": 0.45})
	var main := Gfx.mesh(Shapes.sphere(1.0, 20, 10), wm, sx / 2.0, 0, 0, hinge)
	main.scale = Vector3(sx / 2.0, sy / 2.0, sz / 2.0)
	for k in 4:
		var f := Gfx.mesh(Shapes.sphere(1.0, 12, 6), Gfx.mat(Gfx.shade(c, 0.8 if k % 2 else 1.1), {"rough": 0.5}), sx * (0.78 + k * 0.06), -sy * 0.05, (k - 1.5) * sz * 0.22, hinge)
		f.scale = Vector3(sx * 0.26, sy * 0.3, sz * 0.12)
	rec["hinge"] = hinge
	rec["ghost"] = Gfx.mesh(Shapes.rbox(sx, sy, sz, 0.2), Gfx.flat(0xffffff, {"opacity": 0.1}), 0, 0, 0, root, false)
	return root


## Éboulis (dalle clignotante) : tas de pierres qui s'écroule puis se reforme.
func _scree(e: Dictionary, i: int, rec: Dictionary) -> Node3D:
	var root := _root(e)
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var sz: float = e["size"][2]
	var base := Gfx.mesh(Shapes.rbox(sx, sy * 0.6, sz, 0.15), Gfx.mat(0x4a3c37, {"rough": 0.9}), 0, -sy * 0.2, 0, root)
	var stones := []
	var sm := Gfx.mat(0xffffff, {"map": Tex.veins("#5c4d47", "#ff7b1c"), "rough": 0.9})
	var n := clampi(int(sx * sz * 1.2), 6, 30)
	for k in n:
		var r := 0.3 + _hash(i, k) * 0.3
		var p := Vector3((_hash(k, i + 1) - 0.5) * (sx - r), sy / 2.0 - r * 0.7, (_hash(k + 2, i) - 0.5) * (sz - r))
		var s := Gfx.mesh(Shapes.icosphere(r, 1), sm, p.x, p.y, p.z, root)
		s.rotation = Vector3(k, k * 0.7, 0)
		stones.append([s, p, _hash(k, 9)])
	rec["base"] = base
	rec["stones"] = stones
	rec["ghost"] = Gfx.mesh(Shapes.rbox(sx, sy, sz, 0.2), Gfx.flat(0xff7b1c, {"opacity": 0.1}), 0, 0, 0, root, false)
	return root


## Castors : trous dans le plateau (bas de la boîte) et un castor par trou, qui sort selon Level.popper_state.
func _popper(e: Dictionary, i: int, rec: Dictionary) -> Node3D:
	var root := _root(e)
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var sz: float = e["size"][2]
	var cols := int(e.get("cols", 3))
	var rows := int(e.get("rows", 3))
	var pw := sx / cols
	var pd := sz / rows
	var hw := 0.32 * minf(pw, pd)
	var fur := Gfx.mat(0x9c6644, {"rough": 0.7})
	var belly := Gfx.mat(0xd9a066, {"rough": 0.7})
	var dark := Gfx.flat(0x1a120c)
	var beavers := []
	for row in rows:
		for col in cols:
			var x := -sx / 2.0 + (col + 0.5) * pw
			var z := -sz / 2.0 + (row + 0.5) * pd
			Gfx.mesh(Shapes.cylinder(hw * 1.25, hw * 1.25, 0.05, 24), dark, x, -sy / 2.0 + 0.03, z, root, false)
			Gfx.mesh(Shapes.torus(hw * 1.3, 0.08, 28, 6), Gfx.mat(0x6b4226, {"rough": 0.8}), x, -sy / 2.0 + 0.05, z, root)
			var bv := Node3D.new()
			root.add_child(bv)
			# corps (capsule de la hauteur de la boîte), ventre, tête tournée vers -z local (vers les joueurs qui arrivent)
			Gfx.mesh(Shapes.capsule(hw, maxf(0.1, sy - 2.0 * hw)), fur, 0, 0, 0, bv)
			var b := Gfx.mesh(Shapes.sphere(1.0, 14, 10), belly, 0, -sy * 0.05, -hw * 0.45, bv)
			b.scale = Vector3(hw * 0.75, sy * 0.32, hw * 0.6)
			var hy := sy / 2.0 - hw * 0.8
			for s in [-1.0, 1.0]:
				Gfx.mesh(Shapes.sphere(hw * 0.3, 10, 8), Gfx.mat(0xffffff), s * hw * 0.42, hy + hw * 0.2, -hw * 0.82, bv)
				Gfx.mesh(Shapes.sphere(hw * 0.15, 8, 6), dark, s * hw * 0.42, hy + hw * 0.22, -hw * 1.08, bv, false)
				Gfx.mesh(Shapes.sphere(hw * 0.26, 8, 6), fur, s * hw * 0.75, hy + hw * 0.75, 0, bv)
			Gfx.mesh(Shapes.sphere(hw * 0.2, 8, 6), dark, 0, hy - hw * 0.05, -hw * 1.0, bv, false)
			Gfx.mesh(Shapes.rbox(hw * 0.4, hw * 0.35, 0.06, 0.02), Gfx.mat(0xffffff), 0, hy - hw * 0.4, -hw * 0.95, bv)
			bv.position = Vector3(x, -sy, z)
			bv.visible = false
			beavers.append(bv)
	rec["beavers"] = beavers
	rec["seed"] = i
	rec["prev"] = []
	for k in beavers.size():
		rec["prev"].append(0.0)
	return root


## Jet de lave : cratère au pied de la colonne, colonne lumineuse qui jaillit (Level.geyser_state).
func _geyser(e: Dictionary, rec: Dictionary) -> Node3D:
	var root := _root(e)
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var sz: float = e["size"][2]
	var r := minf(sx, sz) / 2.0
	var rim := Gfx.mat(0x4a3c37, {"rough": 0.9})
	rim.emission_enabled = true
	rim.emission = Color(1.0, 0.4, 0.05)
	rim.emission_energy_multiplier = 0.0
	Gfx.mesh(Shapes.torus(r * 1.05, r * 0.35, 28, 8), rim, 0, -sy / 2.0, 0, root)
	Gfx.mesh(Shapes.cylinder(r * 0.95, r * 0.95, 0.1, 24), Gfx.mat(0xff5400, {"glow": 1.2}), 0, -sy / 2.0 + 0.02, 0, root, false)
	var jet := Node3D.new()
	jet.position.y = -sy / 2.0
	root.add_child(jet)
	Gfx.mesh(Shapes.cylinder(r * 0.85, r, sy, 20), ParkourProps._hazard_mat("lava"), 0, sy / 2.0, 0, jet, false)
	Gfx.mesh(Shapes.cylinder(r * 0.45, r * 0.6, sy * 1.02, 14), Gfx.mat(0xffd60a, {"glow": 2.0}), 0, sy / 2.0, 0, jet, false)
	Gfx.mesh(Shapes.sphere(r * 1.1, 16, 10), Gfx.mat(0xff7b1c, {"glow": 1.4}), 0, sy, 0, jet, false)
	jet.visible = false
	rec["jet"] = jet
	rec["rim"] = rim
	return root


## Chute de pierres : pierres qui tombent du haut de la zone et leur ombre au sol (Level.rockfall_stones).
func _rockfall(e: Dictionary, rec: Dictionary) -> Node3D:
	var root := _root(e, false)
	var stone: float = e.get("stone", 1.0)
	var sm := Gfx.mat(0xffffff, {"map": Tex.veins("#5c4d47", "#ff7b1c"), "rough": 0.9})
	var shadow_m := Gfx.flat(0x000000, {"opacity": 0.45})
	shadow_m.no_depth_test = false
	var stones := []
	var shadows := []
	for k in int(e.get("count", 2)):
		var s := _free(Gfx.mesh(Shapes.icosphere(stone / 2.0, 1), sm))
		s.visible = false
		stones.append(s)
		var sh := _free(Gfx.mesh(Shapes.cylinder(1.0, 1.0, 0.02, 24), shadow_m, 0, 0, 0, null, false))
		sh.visible = false
		shadows.append(sh)
	rec["stones"] = stones
	rec["shadows"] = shadows
	rec["prev"] = {}
	return root


func _free(n: Node3D) -> Node3D:
	ctx.world.add_child(n)
	return n


func _deco(e: Dictionary, i: int, rec: Dictionary) -> Node3D:
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var sz: float = e["size"][2]
	var g := _root(e)
	g.position.y -= sy / 2.0  # base en bas de la boîte
	var kind: String = e.get("kind", "tree")
	rec["kind"] = kind
	match kind:
		"flowers":
			var r := minf(sx, sz) * 0.28
			Gfx.mesh(Shapes.cylinder(r, r * 0.8, sy * 0.38, 20), Gfx.mat(_color(e, 0x4cc9f0), {"rough": 0.15, "metal": 0.1}), 0, sy * 0.19, 0, g)
			var stem := Gfx.mat(0x2d9c4a, {"rough": 0.6})
			var heads := []
			for k in 5:
				var a := k * TAU / 5.0 + i
				var top := Vector3(cos(a) * minf(sx, sz) * 0.32 * (0.4 if k == 0 else 1.0), sy * (0.82 + _hash(i, k) * 0.15), sin(a) * minf(sx, sz) * 0.32 * (0.4 if k == 0 else 1.0))
				var st := Gfx.mesh(Shapes.cylinder(0.05, 0.05, 1.0, 6), stem, 0, 0, 0, g)
				Gfx.stretch(st, Vector3(0, sy * 0.3, 0), top, 1.0)
				var h := Node3D.new()
				h.position = top
				g.add_child(h)
				var fc: int = FLOWER_COLORS[(k + i) % FLOWER_COLORS.size()]
				for p in 5:
					var pa := p * TAU / 5.0
					var pm := Gfx.mesh(Shapes.sphere(0.16, 8, 6), Gfx.mat(fc, {"rough": 0.4}), cos(pa) * 0.17, 0, sin(pa) * 0.17, h)
					pm.scale = Vector3(1, 0.5, 1)
				Gfx.mesh(Shapes.sphere(0.12, 8, 6), Gfx.mat(0xffd60a), 0, 0.04, 0, h)
				heads.append([h, _hash(k, i) * TAU])
			rec["heads"] = heads
		"stem":
			var r := minf(sx, sz) / 2.0
			Gfx.mesh(Shapes.cylinder(r * 0.85, r, sy, 16), Gfx.mat(0x3a9d3f, {"rough": 0.55}), 0, sy / 2.0, 0, g)
		"cloud":
			var p := _puffs(g, sx, sy, sz, i)
			p.position.y = sy / 2.0
			rec["drift"] = p
		"rack":
			_rack(g, e, sx, sy, sz, rec)
		"room":
			_room(g, sx, sy, sz)
	return g


## Étendoir : deux pieds en A aux bouts (x local = ±sx/2), barres du haut, et linge pendu sous les fils.
func _rack(g: Node3D, e: Dictionary, sx: float, sy: float, sz: float, rec: Dictionary) -> void:
	var metal := Gfx.mat(_color(e, 0xd9dde3), {"metal": 0.6, "rough": 0.25})
	for s in [-1.0, 1.0]:
		for f in [-1.0, 1.0]:
			var leg := Gfx.mesh(Shapes.cylinder(0.09, 0.09, 1.0, 8), metal, 0, 0, 0, g)
			Gfx.stretch(leg, Vector3(s * sx / 2.0, 0, f * sz / 2.0), Vector3(s * sx / 2.0, sy, f * sz * 0.42), 1.0)
		var top := Gfx.mesh(Shapes.cylinder(0.1, 0.1, sz * 0.9, 8), metal, s * sx / 2.0, sy, 0, g)
		top.rotation.x = PI / 2.0
		var mid := Gfx.mesh(Shapes.cylinder(0.07, 0.07, sz * 0.7, 8), metal, s * sx / 2.0, sy * 0.45, 0, g)
		mid.rotation.x = PI / 2.0
	# linge qui pend au bord de l'étendoir (sous les fils, sans gêner le passage)
	var clothes := []
	var cols := [0xff4d6d, 0x4cc9f0, 0xffd60a, 0xc77dff]
	for k in 4:
		var c := Node3D.new()
		var x := (-0.5 + (k + 0.5) / 4.0) * sx * 0.8
		c.position = Vector3(x, sy - 0.15, (sz * 0.45) * (1.0 if k % 2 == 0 else -1.0))
		g.add_child(c)
		var m := Gfx.mat(cols[k], {"rough": 0.6, "double": true})
		if k % 2 == 0:
			# t-shirt
			Gfx.mesh(Shapes.rbox(1.2, 1.3, 0.06, 0.05), m, 0, -0.7, 0, c)
			for s in [-1.0, 1.0]:
				var sl := Gfx.mesh(Shapes.rbox(0.45, 0.4, 0.06, 0.05), m, s * 0.75, -0.25, 0, c)
				sl.rotation.z = s * 0.5
		else:
			# chaussette
			Gfx.mesh(Shapes.rbox(0.35, 0.9, 0.08, 0.06), m, 0, -0.5, 0, c)
			Gfx.mesh(Shapes.rbox(0.55, 0.32, 0.08, 0.06), m, 0.12, -0.95, 0, c)
		clothes.append([c, _hash(k, 3) * TAU])
	rec["clothes"] = clothes


## Murs de la maison autour de la boîte (papier peint, plinthes, fenêtre, cadre), sans plafond.
func _room(g: Node3D, sx: float, sy: float, sz: float) -> void:
	var paper := Gfx.mat(0xffffff, {"map": Tex.stripes("#ffe8d6", "#ffd8c2"), "uv": Vector2(maxf(1.0, sx / 4.0), maxf(1.0, sy / 4.0)), "rough": 0.8})
	var paper_z := Gfx.mat(0xffffff, {"map": Tex.stripes("#ffe8d6", "#ffd8c2"), "uv": Vector2(maxf(1.0, sz / 4.0), maxf(1.0, sy / 4.0)), "rough": 0.8})
	var plinth := Gfx.mat(0xffffff, {"rough": 0.5})
	for s in [-1.0, 1.0]:
		Gfx.mesh(Shapes.box(sx, sy, 0.6), paper, 0, sy / 2.0, s * sz / 2.0, g)
		Gfx.mesh(Shapes.box(0.6, sy, sz), paper_z, s * sx / 2.0, sy / 2.0, 0, g)
		Gfx.mesh(Shapes.box(sx, 0.8, 0.8), plinth, 0, 0.4, s * (sz / 2.0 - 0.1), g)
		Gfx.mesh(Shapes.box(0.8, 0.8, sz), plinth, s * (sx / 2.0 - 0.1), 0.4, 0, g)
	# fenêtre sur le mur +x : ciel, croisillons blancs
	var wz := 0.0
	var wy := sy * 0.6
	var ww := minf(sz * 0.3, 16.0)
	var wh := sy * 0.45
	Gfx.mesh(Shapes.box(0.2, wh, ww), Gfx.flat(0xbfe9ff), sx / 2.0 - 0.35, wy, wz, g, false)
	Gfx.mesh(Shapes.box(0.3, wh + 0.8, 0.5), plinth, sx / 2.0 - 0.4, wy, wz, g)
	Gfx.mesh(Shapes.box(0.3, 0.5, ww + 0.8), plinth, sx / 2.0 - 0.4, wy, wz, g)
	for s in [-1.0, 1.0]:
		Gfx.mesh(Shapes.box(0.3, wh + 0.8, 0.5), plinth, sx / 2.0 - 0.4, wy, wz + s * (ww / 2.0 + 0.2), g)
		Gfx.mesh(Shapes.box(0.3, 0.5, ww + 0.8), plinth, sx / 2.0 - 0.4, wy + s * (wh / 2.0 + 0.2), wz, g)
	# tableau sur le mur -x : un soleil
	Gfx.mesh(Shapes.box(0.3, sy * 0.25, sz * 0.15), Gfx.mat(0xc98846), -sx / 2.0 + 0.4, sy * 0.6, sz * 0.15, g)
	Gfx.mesh(Shapes.box(0.32, sy * 0.21, sz * 0.13), Gfx.mat(0x8fd3ff), -sx / 2.0 + 0.42, sy * 0.6, sz * 0.15, g)
	Gfx.mesh(Shapes.sphere(sy * 0.05, 12, 8), Gfx.mat(0xffd60a, {"glow": 0.4}), -sx / 2.0 + 0.6, sy * 0.63, sz * 0.15, g)


# ---------- animation ----------

func update(t: float, dt: float) -> void:
	_fx_timer -= dt
	var fx := _fx_timer < 0.0
	if fx:
		_fx_timer = 0.08
	for rec: Dictionary in recs:
		var e: Dictionary = rec["e"]
		var i: int = rec["i"]
		match rec["type"]:
			"popper":
				_update_popper(rec, e, t, fx)
				continue
			"geyser":
				_update_geyser(rec, e, t, fx)
				continue
			"rockfall":
				_update_rockfall(rec, e, t)
				continue
			"deco":
				_update_deco(rec, t)
				continue
		match rec["skin"]:
			"record", "sunflower":
				rec["spin"].rotation.y = Level.spin_angle(e, t)
			"plane":
				rec["prop"].rotation.z = t * 22.0
			"heli":
				rec["rotor"].rotation.y = t * 9.0
				rec["trotor"].rotation.x = t * 16.0
			"kite":
				var tip: Vector3 = rec["tip"]
				var prev := tip
				var bows: Array = rec["bows"]
				for k in bows.size():
					var p := tip + Vector3(sin(t * 2.6 - k * 0.8) * 0.25 * (k + 1) * 0.5, -0.55 * (k + 1), -0.5 * (k + 1))
					bows[k].position = p
					bows[k].rotation.z = sin(t * 3.0 - k) * 0.4
					Gfx.stretch(rec["ribbon"][k], prev, p, 1.0)
					prev = p
			"cloud":
				if rec["type"] == "crumble":
					# nuage qui se dissout : il se ratatine pendant le délai, puis disparaît (visibilité gérée par le client)
					var at: Variant = lstate["crumbled"].get(i)
					var k := 1.0
					var delay: float = e.get("delay", 0.5)
					if at != null and t >= at and t < at + delay:
						k = 1.0 - 0.45 * (t - at) / delay
						if fx:
							var p := _v(e)
							ctx.particles.emit(p.x + (randf() - 0.5) * e["size"][0], p.y + e["size"][1] / 2.0, p.z + (randf() - 0.5) * e["size"][2], (randf() - 0.5) * 1.5, 0.8, (randf() - 0.5) * 1.5, 0xffffff, 0.3, 0.8, -0.5)
					rec["puffs"].scale = Vector3(1.0 + (1.0 - k) * 0.3, k, 1.0 + (1.0 - k) * 0.3)
				elif rec["type"] == "blink":
					_update_blink_fade(rec, e, t)
			"wing":
				var st := Level.blink_state(e, t)
				var left: float = st["left"]
				var fold := clampf((0.35 - left) / 0.35, 0.0, 1.0) if st["solid"] else clampf(left / 0.35, 0.0, 1.0)
				rec["hinge"].rotation.z = fold * 1.35 + (sin(t * 2.2 + i) * 0.04 if st["solid"] else 0.0)
				rec["ghost"].visible = not st["solid"]
			"scree":
				_update_scree(rec, e, t, fx)


func _update_blink_fade(rec: Dictionary, e: Dictionary, t: float) -> void:
	var st := Level.blink_state(e, t)
	var left: float = st["left"]
	var k := clampf(left / 0.6, 0.0, 1.0) if st["solid"] else 0.0
	var puffs: Node3D = rec["puffs"]
	puffs.visible = st["solid"]
	puffs.scale = Vector3(1.0, 0.4 + 0.6 * k, 1.0) if k < 1.0 else Vector3.ONE
	rec["ghost"].visible = not st["solid"]


func _update_scree(rec: Dictionary, e: Dictionary, t: float, fx: bool) -> void:
	var st := Level.blink_state(e, t)
	var left: float = st["left"]
	var period: float = e.get("period", 4.0)
	var on: float = e.get("on", 0.6)
	var base: MeshInstance3D = rec["base"]
	base.visible = st["solid"]
	rec["ghost"].visible = not st["solid"]
	for s: Array in rec["stones"]:
		var n: MeshInstance3D = s[0]
		var p: Vector3 = s[1]
		if st["solid"]:
			var warn := clampf(1.0 - left / 0.8, 0.0, 1.0)
			n.visible = true
			n.position = p + Vector3((randf() - 0.5) * 0.12 * warn, 0, (randf() - 0.5) * 0.12 * warn)
			n.scale = Vector3.ONE
		else:
			var since: float = (st["u"] - on) * period
			if left < 0.45:
				# se reforme : les pierres remontent
				var k := 1.0 - left / 0.45
				n.visible = true
				n.position = p - Vector3(0, (1.0 - k) * 2.5, 0)
				n.scale = Vector3.ONE * maxf(0.05, k)
			else:
				var f := since + float(s[2]) * 0.15
				n.visible = f < 0.9
				n.position = p - Vector3(0, 5.0 * f * f, 0)
				n.scale = Vector3.ONE * maxf(0.05, 1.0 - f)
	if fx and not st["solid"] and (st["u"] - on) * period < 0.3:
		var c := _v(e)
		ctx.particles.emit(c.x + (randf() - 0.5) * e["size"][0], c.y, c.z + (randf() - 0.5) * e["size"][2], (randf() - 0.5) * 2.0, 1.0, (randf() - 0.5) * 2.0, 0x8d7a70, 0.25, 0.7, 3.0)


func _update_popper(rec: Dictionary, e: Dictionary, t: float, fx: bool) -> void:
	var sy: float = e["size"][1]
	var seed_: int = rec["seed"]
	var beavers: Array = rec["beavers"]
	var prev: Array = rec["prev"]
	for k in beavers.size():
		var bv: Node3D = beavers[k]
		var st := Level.popper_state(e, k, t, seed_)
		var ext: float = st["ext"]
		var base_y := -sy / 2.0 - sy / 2.0  # castor rentré : son centre est une hauteur sous la surface
		if ext > 0.0:
			bv.visible = true
			bv.position.y = base_y + ext * sy
			bv.rotation.y = sin(t * 3.0 + k) * 0.25
			if prev[k] <= 0.0:
				# il jaillit : petite gerbe de copeaux et « pop »
				var w: Vector3 = rec["root"].to_global(Vector3(bv.position.x, -sy / 2.0, bv.position.z))
				ctx.particles.burst(w, 6, [0xd9a066, 0x9c6644, 0xffffff], 3.0, 0.08, 0.4)
				if ctx.body and Vector3(ctx.body.px, ctx.body.py, ctx.body.pz).distance_to(w) < 12.0:
					ctx.sfx.boing()
		elif st["warn"]:
			# il va sortir : le bout des oreilles dépasse et tremble
			bv.visible = true
			bv.position.y = base_y + 0.35 + (randf() - 0.5) * 0.08
		else:
			bv.visible = false
		prev[k] = ext
		if fx and st["warn"] and randf() < 0.5:
			var w: Vector3 = rec["root"].to_global(Vector3(bv.position.x, -sy / 2.0 + 0.05, bv.position.z))
			ctx.particles.emit(w.x, w.y, w.z, (randf() - 0.5) * 1.5, 1.5, (randf() - 0.5) * 1.5, 0x9c6644, 0.08, 0.4, 6.0)


func _update_geyser(rec: Dictionary, e: Dictionary, t: float, fx: bool) -> void:
	var st := Level.geyser_state(e, t)
	var period: float = e.get("period", 4.0)
	var jet: Node3D = rec["jet"]
	var rim: StandardMaterial3D = rec["rim"]
	var sy: float = e["size"][1]
	if st["active"]:
		var since: float = st["u"] * period
		var left: float = st["left"]
		var h := clampf(since / 0.2, 0.05, 1.0) * clampf(left / 0.15, 0.05, 1.0) if left < 0.15 else clampf(since / 0.2, 0.05, 1.0)
		jet.visible = true
		var wob := 1.0 + sin(t * 23.0) * 0.06
		jet.scale = Vector3(wob, h, wob)
		rim.emission_energy_multiplier = 1.6
		if fx:
			var p := _v(e) + Vector3(0, -sy / 2.0 + sy * h, 0)
			for k in 3:
				ctx.particles.emit(p.x + (randf() - 0.5) * 0.6, p.y, p.z + (randf() - 0.5) * 0.6, (randf() - 0.5) * 5.0, 3.0 + randf() * 4.0, (randf() - 0.5) * 5.0, ParkourProps.HAZARD_FX["lava"][randi() % 3], 0.12 + randf() * 0.1, 0.9, 12.0)
	else:
		jet.visible = false
		rim.emission_energy_multiplier = (0.9 + 0.7 * sin(t * 18.0)) if st["warn"] else 0.15
		if fx and st["warn"]:
			var p := _v(e) + Vector3(0, -sy / 2.0 + 0.1, 0)
			for k in 2:
				ctx.particles.emit(p.x + (randf() - 0.5) * e["size"][0], p.y, p.z + (randf() - 0.5) * e["size"][2], (randf() - 0.5) * 0.8, 2.0 + randf() * 2.0, (randf() - 0.5) * 0.8, ParkourProps.HAZARD_FX["lava"][randi() % 3], 0.12, 0.6, 4.0)


func _update_rockfall(rec: Dictionary, e: Dictionary, t: float) -> void:
	var stones: Array = rec["stones"]
	var shadows: Array = rec["shadows"]
	var prev: Dictionary = rec["prev"]
	var stone: float = e.get("stone", 1.0)
	var warn: float = e.get("warn", 1.4)
	var ground: float = e["pos"][1] - e["size"][1] / 2.0
	var seen := {}
	for s: Array in Level.rockfall_stones(e, t, rec["i"]):
		var c: Phys.Col = s[0]
		var k: int = s[1]
		var f: float = s[2]
		seen[k] = true
		var n: Node3D = stones[k]
		n.visible = true
		var sh: Node3D = shadows[k]
		if f < 1.0:
			n.position = Vector3(c.cx, c.cy, c.cz)
			n.rotation = Vector3(t * 3.0 + k, t * 2.0, 0)
			n.scale = Vector3.ONE
			sh.visible = true
			var r := stone * (0.25 + 0.4 * f)
			sh.transform = Transform3D(Basis.from_scale(Vector3(r, 1.0, r)), Vector3(s[3], ground + 0.04, s[4]))
		else:
			sh.visible = false
			var k2 := clampf((f - 1.0) * warn / Level.ROCK_REST, 0.0, 1.0)
			n.position = Vector3(c.cx, c.cy - k2 * stone * 0.3, c.cz)
			n.scale = Vector3(1.0 + k2 * 0.4, maxf(0.05, 1.0 - k2), 1.0 + k2 * 0.4)
			if float(prev.get(k, 0.0)) < 1.0:
				var w := Vector3(c.cx, ground + 0.2, c.cz)
				ctx.particles.burst(w, 14, [0x8d7a70, 0x5c4d47, 0xff7b1c], 5.0, 0.14, 0.6)
				var me := Vector3(ctx.body.px, ctx.body.py, ctx.body.pz)
				if me.distance_to(w) < 10.0:
					ctx.sfx.crumble()
					ctx.shake(0.15)
		prev[k] = f
	for k in stones.size():
		if not seen.has(k):
			stones[k].visible = false
			shadows[k].visible = false
			prev[k] = 0.0


func _update_deco(rec: Dictionary, t: float) -> void:
	var i: int = rec["i"]
	match rec["kind"]:
		"flowers":
			for h: Array in rec["heads"]:
				var n: Node3D = h[0]
				n.rotation = Vector3(sin(t * 1.3 + h[1]) * 0.15, 0, cos(t * 1.1 + h[1]) * 0.15)
		"cloud":
			var p: Node3D = rec["drift"]
			p.position.x = sin(t * 0.15 + i) * 1.2
			p.position.y = rec["e"]["size"][1] / 2.0 + sin(t * 0.4 + i) * 0.3
		"rack":
			for c: Array in rec["clothes"]:
				var n: Node3D = c[0]
				n.rotation.x = sin(t * 1.6 + c[1]) * 0.18
				n.rotation.z = sin(t * 1.1 + c[1]) * 0.06


## Les pieds (x, y, z) sont-ils posés sur un fil d'étendoir ? (pose d'équilibriste des autres joueurs)
func on_wire(p: Vector3) -> bool:
	for e: Dictionary in wires:
		if Level.stands_on(e, p.x, p.y, p.z):
			return true
	return false
