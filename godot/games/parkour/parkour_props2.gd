class_name ParkourProps2
extends RefCounted
## Parcours délirant — décor et animation des éléments de la vague 2 : boue, gélatine, rampes et toboggans,
## speed pads, canons à joueurs, trampolines directionnels, tyroliennes, téléporteurs, bulles, zones lunaires,
## rafales ; plus les effets des propulseurs (PreEvents) et la pose des joueurs suspendus.
## Les pièces mobiles sont replacées à chaque image par les fonctions pures de Level, au temps serveur.

const LEAVES := [0x8ac926, 0xffca3a, 0xff924c, 0xc9e265]

var ctx: Main
var level: Dictionary
var recs: Array = []
var winds: Array = []
var _fx := 0.0
var _pulleys: Array = []  # poulies des joueurs suspendus (réserve)
var _ziplines: Array = []  # éléments zipline (pour reconnaître les joueurs suspendus)
var _boost_snd := 0.0
var _trail := 0.0


func _init(c: Main, l: Dictionary) -> void:
	ctx = c
	level = l


func _v(e: Dictionary) -> Vector3:
	return Vector3(e["pos"][0], e["pos"][1], e["pos"][2])


static func _a3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _root(e: Dictionary, with_yaw := true) -> Node3D:
	var g := Node3D.new()
	g.position = _v(e)
	if with_yaw:
		g.rotation.y = e.get("yaw", 0.0)
	ctx.world.add_child(g)
	return g


## Tube creux (cylindre sans fond, deux faces) d'axe Y.
static func _tube(r: float, h: float, color: int, o: Dictionary = {}) -> MeshInstance3D:
	var o2 := o.duplicate()
	o2["double"] = true
	return Gfx.mesh(Shapes.cylinder(r, r, h, 24, false), Gfx.mat(color, o2))


## Chevron plat (speed pad), pointant vers +Z.
static func _chevron() -> ArrayMesh:
	var v := PackedVector3Array([
		Vector3(-0.5, 0, -0.25), Vector3(0, 0, 0.25), Vector3(0, 0, 0.0),
		Vector3(-0.5, 0, -0.25), Vector3(0, 0, 0.0), Vector3(-0.5, 0, -0.5),
		Vector3(0.5, 0, -0.25), Vector3(0, 0, 0.0), Vector3(0, 0, 0.25),
		Vector3(0.5, 0, -0.25), Vector3(0.5, 0, -0.5), Vector3(0, 0, 0.0),
	])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in v:
		st.set_normal(Vector3.UP)
		st.add_vertex(p)
	return st.commit()


## Maillage de la rampe à partir de ses 8 sommets monde (dalle cisaillée) : dessus (avec UV), dessous, côtés.
static func _ramp_mesh(cs: Array, sx: float, len_z: float) -> Array:
	var faces := [
		[[4, 5, 7, 6], true],  # dessus (iy = 1)
		[[0, 2, 3, 1], false],  # dessous
		[[0, 1, 5, 4], false],  # bord −z
		[[2, 6, 7, 3], false],  # bord +z
		[[0, 4, 6, 2], false],  # côté −x
		[[1, 3, 7, 5], false],  # côté +x
	]
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs := {4: Vector2(0, 0), 5: Vector2(sx, 0), 6: Vector2(0, len_z), 7: Vector2(sx, len_z)}
	for f: Array in faces:
		var q: Array = f[0]
		var st: SurfaceTool = top if f[1] else sides
		var p: Array = []
		for k: int in q:
			p.append(_a3(cs[k]))
		var n: Vector3 = (p[2] - p[0]).cross(p[1] - p[0]).normalized()
		# orientation : la normale doit sortir de la dalle
		var center := Vector3.ZERO
		for c: Array in cs:
			center += _a3(c) / 8.0
		var mid: Vector3 = (p[0] + p[1] + p[2] + p[3]) / 4.0
		var flip := n.dot(mid - center) < 0.0
		if flip:
			n = -n
		var tri := [0, 2, 1, 0, 3, 2] if not flip else [0, 1, 2, 0, 2, 3]
		for k: int in tri:
			st.set_normal(n)
			if f[1]:
				st.set_uv(uvs[q[k]] / 2.0)
			st.add_vertex(p[k])
	return [top.commit(), sides.commit()]


# ---------- construction ----------

func build(e: Dictionary, i: int) -> Node3D:
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var sz: float = e["size"][2]
	var rec := {"e": e, "i": i, "type": e["type"]}
	var root: Node3D = null
	match e["type"]:
		"mud":
			root = _root(e)
			root.add_child(Gfx.slab(sx, sy, sz, 0x6b4226, {"top": 0xffffff, "top_map": Tex.soft("#5a3820", "#7a4e2c"), "top_uv": Vector2(sx / 2.0, sz / 2.0), "seed": i}))
			# flaques luisantes
			var wet := Gfx.mat(0x4a2c17, {"rough": 0.08})
			for k in clampi(int(sx * sz / 10.0), 2, 7):
				var p := Vector3((ParkourProps._hash(i, k) - 0.5) * sx * 0.7, sy / 2.0 + 0.01, (ParkourProps._hash(k, i) - 0.5) * sz * 0.7)
				var d := Gfx.mesh(Shapes.cylinder(0.5, 0.5, 0.03, 16), wet, p.x, p.y, p.z, root, false)
				d.scale = Vector3(0.8 + ParkourProps._hash(k, 3) * 1.4, 1, 0.6 + ParkourProps._hash(k, 5))
			rec["mud"] = true
		"jelly":
			root = _root(e)
			var wob := Node3D.new()
			wob.position.y = -sy / 2.0
			root.add_child(wob)
			var m := Gfx.mat(0xff5fa2, {"rough": 0.12, "opacity": 0.78})
			m.rim_enabled = true
			m.rim = 0.6
			Gfx.mesh(Shapes.rbox(sx, sy, sz, minf(0.35, sy * 0.45)), m, 0, sy / 2.0, 0, wob, false)
			Gfx.mesh(Shapes.rbox(sx * 0.7, sy * 0.6, sz * 0.7, minf(0.25, sy * 0.3)), Gfx.mat(0xff8fc0, {"rough": 0.2, "opacity": 0.6}), 0, sy * 0.45, 0, wob, false)
			for k in 3:
				Gfx.mesh(Shapes.sphere(0.12 + k * 0.04, 8, 6), Gfx.mat(0xffffff, {"opacity": 0.5}), (k - 1) * sx * 0.25, sy * (0.35 + k * 0.15), (ParkourProps._hash(i, k) - 0.5) * sz * 0.5, wob, false)
			rec["wob"] = wob
			rec["kick"] = 0.0
		"ramp":
			root = Node3D.new()
			ctx.world.add_child(root)
			var slide: bool = e.get("slide", false)
			var cs := Level.ramp_corners(e)
			var meshes := _ramp_mesh(cs, sx, sqrt(sz * sz + pow(e.get("rise", 2.0), 2.0)))
			var col: int = Gfx.to_int(Color(e["color"])) if e.get("color") != null else (0x00b4d8 if slide else 0x8fb8ff)
			var top_mat: StandardMaterial3D
			if slide:
				top_mat = Gfx.mat(0xffffff, {"map": Tex.stripes("#00b4d8", "#90e0ef"), "rough": 0.12})
			else:
				top_mat = Gfx.mat(0xffffff, {"map": Tex.soft(UI.hex(col), UI.hex(Gfx.shade(col, 1.25))), "rough": 0.5})
			Gfx.mesh(meshes[0], top_mat, 0, 0, 0, root)
			Gfx.mesh(meshes[1], Gfx.mat(Gfx.shade(col, 0.7)), 0, 0, 0, root)
			if slide:
				# rebords du toboggan
				var rail := Gfx.mat(0xffd60a, {"rough": 0.3})
				for s in [0, 1]:
					var a := _a3(cs[4 + s]) + Vector3(0, 0.12, 0)
					var b := _a3(cs[6 + s]) + Vector3(0, 0.12, 0)
					Gfx.stretch(Gfx.mesh(Shapes.cylinder(0.12, 0.12, 1.0, 8), rail, 0, 0, 0, root), a, b)
		"boost":
			root = _root(e)
			Gfx.mesh(Shapes.rbox(sx, sy, sz, minf(0.2, sy * 0.4)), Gfx.mat(0x2b2140, {"rough": 0.5}), 0, 0, 0, root)
			var bv := Level.boost_vel(e)
			var ang: float = atan2(bv[0], bv[1]) - e.get("yaw", 0.0)  # sens d'entraînement dans le repère du pad
			var holder := Node3D.new()
			holder.rotation.y = ang
			holder.position.y = sy / 2.0 + 0.02
			root.add_child(holder)
			var w := minf(sx, sz) * 0.6
			var mats := []
			for k in 3:
				var m := Gfx.flat(0xff9e00, {"double": true})
				var ch := Gfx.mesh(_chevron(), m, 0, 0, (k - 1) * w * 0.38, holder, false)
				ch.scale = Vector3(w, 1, w * 0.7)
				mats.append(m)
			rec["chev"] = mats
		"launcher":
			root = Node3D.new()
			ctx.world.add_child(root)
			var arc := Level.launcher_arc(e)
			var base := Vector3(e["pos"][0], e["pos"][1] - sy / 2.0, e["pos"][2])
			# disque de départ au sol
			Gfx.mesh(Shapes.torus(minf(sx, sz) / 2.0 - 0.1, 0.1, 32, 8), Gfx.mat(0xff4d6d, {"glow": 0.8}), base.x, base.y + 0.08, base.z, root, false)
			# fût orienté selon la première tangente, posé à côté de la zone
			var tan: Vector3 = (arc[1] - arc[0]).normalized()
			var flat := Vector3(tan.x, 0, tan.z).normalized() if Vector3(tan.x, 0, tan.z).length() > 1e-3 else Vector3.FORWARD
			var cannon := Node3D.new()
			cannon.position = base - flat * (maxf(sx, sz) / 2.0 + 0.9) + Vector3(0, 0.7, 0)
			root.add_child(cannon)
			var barrel := Node3D.new()
			barrel.basis = Basis(Quaternion(Vector3.UP, tan))
			cannon.add_child(barrel)
			Gfx.mesh(Shapes.cylinder(0.42, 0.55, 2.0, 18), Gfx.mat(0x3d4450, {"metal": 0.6, "rough": 0.3}), 0, 0.6, 0, barrel)
			Gfx.mesh(Shapes.torus(0.45, 0.1, 18, 8), Gfx.mat(0xffd60a, {"metal": 0.3}), 0, 1.6, 0, barrel)
			for s in [-1.0, 1.0]:
				var side: Vector3 = flat.cross(Vector3.UP) * s * 0.6
				var wheel := Gfx.mesh(Shapes.cylinder(0.5, 0.5, 0.18, 16), Gfx.mat(0x9c6644, {"rough": 0.7}), side.x, -0.2, side.z, cannon)
				wheel.basis = Basis(Quaternion(Vector3.UP, flat.cross(Vector3.UP).normalized()))
			rec["mouth"] = cannon.position + tan * 1.6
			# pointillés de la trajectoire (un MultiMesh) et cible à l'arrivée
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = Shapes.sphere(0.09, 6, 4)
			mm.instance_count = arc.size() - 2
			for k in range(1, arc.size() - 1):
				mm.set_instance_transform(k - 1, Transform3D(Basis.IDENTITY, arc[k]))
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = Gfx.flat(0xffffff, {"opacity": 0.55})
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			var to := _a3(e["to"])
			var tm := Gfx.flat(0xffffff)
			tm.albedo_texture = Tex.target("#ff4d6d", "#ffffff")
			Gfx.mesh(Shapes.cylinder(0.9, 0.9, 0.04, 24), tm, to.x, to.y + 0.03, to.z, root, false)
		"jumppad":
			root = _root(e)
			var r := minf(sx, sz) / 2.0
			Gfx.mesh(Shapes.rbox(sx, sy, sz, 0.2), Gfx.mat(0xff9e00), 0, 0, 0, root)
			var spring := Node3D.new()
			spring.position.y = sy / 2.0
			root.add_child(spring)
			Gfx.mesh(Shapes.cylinder(r * 0.8, r * 0.8, 0.08, 24), Gfx.mat(0xffffff, {"map": Tex.target("#ffd60a", "#ff4d6d")}), 0, 0.05, 0, spring)
			# flèche 3D dans la direction du lancer (repère monde → local du pad)
			var jv := Level.jumppad_vel(e)
			var dir := Vector3(jv[0], jv[1], jv[2]).normalized()
			var arrow := Node3D.new()
			arrow.position = Vector3(0, sy / 2.0 + 0.9, 0)
			root.add_child(arrow)
			arrow.global_basis = Basis(Quaternion(Vector3.UP, dir))
			var am := Gfx.mat(0x70e000, {"glow": 0.7})
			Gfx.mesh(Shapes.cylinder(0.09, 0.09, 0.9, 8), am, 0, 0, 0, arrow, false)
			Gfx.mesh(Shapes.cylinder(0.0, 0.25, 0.4, 12), am, 0, 0.6, 0, arrow, false)
			rec["spring"] = spring
			rec["arrow"] = arrow
			rec["kick"] = 0.0
		"zipline":
			root = Node3D.new()
			ctx.world.add_child(root)
			var cb := Level.zip_cable(e)
			var a := _a3(cb["a"])
			var b := _a3(cb["b"])
			var pole := Gfx.mat(0x9c6644, {"rough": 0.7})
			for p: Vector3 in [a, b]:
				Gfx.mesh(Shapes.rbox(sx, sy, sz, minf(0.1, sx * 0.3)), pole, p.x, p.y + 0.25 - sy / 2.0, p.z, root)
				Gfx.mesh(Shapes.sphere(maxf(0.18, sx * 0.6), 10, 8), Gfx.mat(0xffd60a, {"metal": 0.3}), p.x, p.y + 0.25, p.z, root)
			Gfx.stretch(Gfx.mesh(Shapes.cylinder(0.035, 0.035, 1.0, 6), Gfx.mat(0x2b2140, {"metal": 0.5, "rough": 0.3}), 0, 0, 0, root, false), a, b)
			# poignée qui attend au départ (là où les mains attrapent)
			var handle := _pulley()
			handle.position = a
			root.add_child(handle)
			rec["handle"] = handle
			_ziplines.append(e)
		"teleport":
			root = Node3D.new()
			ctx.world.add_child(root)
			var r := minf(sx, sy) / 2.0
			var yaw: float = e.get("yaw", 0.0)
			var enter := Node3D.new()
			enter.position = _v(e)
			enter.rotation.y = yaw
			root.add_child(enter)
			rec["swirl_in"] = _pipe(enter, r, maxf(0.6, sz), 0x2dc653, 0x7cff3a)
			var ev: Array = e.get("exitVel", [0.0, 0.0, 0.0])
			var exit := Node3D.new()
			exit.position = _a3(e["to"]) + Vector3(0, r, 0)
			exit.rotation.y = atan2(ev[0], ev[2]) if absf(ev[0]) + absf(ev[2]) > 0.1 else yaw
			root.add_child(exit)
			rec["swirl_out"] = _pipe(exit, r, 0.8, 0xff9e00, 0xffd60a)
		"bubble":
			root = Node3D.new()
			ctx.world.add_child(root)
			var p := _v(e)
			var r := maxf(sx, sz) / 2.0
			# chaudron à bulles au départ
			Gfx.mesh(Shapes.cylinder(r * 0.9, r * 0.7, 0.8, 20), Gfx.mat(0x3d4450, {"metal": 0.4, "rough": 0.4}), p.x, p.y - sy / 2.0 - 0.5, p.z, root)
			Gfx.mesh(Shapes.cylinder(r * 0.82, r * 0.82, 0.05, 20), Gfx.mat(0x90e0ef, {"glow": 0.5}), p.x, p.y - sy / 2.0 - 0.08, p.z, root, false)
			var disc := Gfx.mat(0xcaf0f8, {"rough": 0.1, "opacity": 0.82})
			var dome := Gfx.mat(0xe0fbff, {"rough": 0.05, "opacity": 0.22})
			dome.rim_enabled = true
			dome.rim = 1.0
			var pool := []
			for k in int(e.get("count", 3)):
				var bn := Node3D.new()
				ctx.world.add_child(bn)
				Gfx.mesh(Shapes.cylinder(minf(sx, sz) / 2.0, minf(sx, sz) / 2.0, sy, 24), disc, 0, 0, 0, bn)
				var d := Gfx.mesh(Shapes.sphere_part(r * 1.02, 20, 10, 0.0, TAU, 0.0, PI / 2.0), dome, 0, sy / 2.0, 0, bn, false)
				d.scale.y = 0.8
				pool.append(bn)
			rec["pool"] = pool
			rec["last_u"] = []
		"lowgrav":
			root = _root(e)
			var vol := Gfx.mesh(Shapes.rbox(sx, sy, sz, minf(1.0, minf(sx, sz) * 0.2)), Gfx.flat(0x9d4edd, {"opacity": 0.07, "double": true}), 0, 0, 0, root, false)
			vol.name = "volume"
			# étoiles qui flottent (un MultiMesh)
			var n := clampi(int(sx * sy * sz / 30.0), 10, 40)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = Shapes.sphere(0.07, 6, 4)
			mm.instance_count = n
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = Gfx.mat(0xfff3b0, {"glow": 2.0})
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			var stars := []
			for k in n:
				stars.append(Vector3((ParkourProps._hash(i, k) - 0.5) * sx, ParkourProps._hash(k, i + 3), (ParkourProps._hash(k + 9, i) - 0.5) * sz))
			rec["stars"] = stars
			rec["mm"] = mm
		"wind":
			winds.append(e)
			root = _root(e, false)
			# manche à air sur le bord d'où vient le vent
			var f: Array = e.get("force", [24.0, 0.0, 0.0])
			var fh := Vector3(f[0], 0, f[2])
			if fh.length() > 0.1:
				var back := -fh.normalized() * (maxf(sx, sz) / 2.0)
				var pole := Gfx.mesh(Shapes.cylinder(0.05, 0.06, 2.4, 6), Gfx.mat(0xf1f3f5), back.x, -sy / 2.0 + 1.2, back.z, root)
				var sock := Node3D.new()
				sock.position = Vector3(back.x, -sy / 2.0 + 2.3, back.z)
				root.add_child(sock)
				var cone := Gfx.mesh(Shapes.cylinder(0.12, 0.28, 1.2, 12, false), Gfx.mat(0xffffff, {"map": Tex.stripes("#ff4d6d", "#ffffff"), "double": true}), 0, 0, 0.6, sock)
				cone.rotation.x = -PI / 2.0
				rec["sock"] = sock
				rec["sock_dir"] = atan2(fh.x, fh.z)
				pole.name = "mât"
	if root != null and rec.size() > 3:
		recs.append(rec)
	return root


## Tuyau de téléportation (axe +z local) : tube, rebord, disque tourbillonnant au fond. Renvoie le disque.
func _pipe(parent: Node3D, r: float, length: float, col: int, glow: int) -> Node3D:
	var t := _tube(r, length, col, {"rough": 0.3})
	t.rotation.x = PI / 2.0
	parent.add_child(t)
	var rim := Gfx.mesh(Shapes.torus(r, 0.16, 32, 10), Gfx.mat(Gfx.shade(col, 1.2), {"rough": 0.3}), 0, 0, length / 2.0, parent)
	rim.rotation.x = PI / 2.0
	var swirl := Node3D.new()
	swirl.position.z = -length / 2.0 + 0.05
	parent.add_child(swirl)
	var disc := Gfx.mesh(Shapes.cylinder(r * 0.95, r * 0.95, 0.02, 32), Gfx.flat(0xffffff, {"double": true}), 0, 0, 0, swirl, false)
	disc.material_override.albedo_texture = Tex.target(UI.hex(glow), "#2b2140")
	disc.rotation.x = PI / 2.0
	return swirl


## Poulie + poignée de tyrolienne (mains en y = 0).
func _pulley() -> Node3D:
	var g := Node3D.new()
	var wheel := Gfx.mesh(Shapes.cylinder(0.16, 0.16, 0.08, 14), Gfx.mat(0xffd60a, {"metal": 0.4, "rough": 0.3}), 0, 0.08, 0, g)
	wheel.rotation.x = PI / 2.0
	Gfx.mesh(Shapes.cylinder(0.025, 0.025, 0.45, 5), Gfx.mat(0x5c6470, {"metal": 0.6}), 0, -0.14, 0, g)
	var bar := Gfx.mesh(Shapes.cylinder(0.045, 0.045, 0.6, 8), Gfx.mat(0xff4d6d), 0, -0.36, 0, g)
	bar.rotation.z = PI / 2.0
	return g


# ---------- animation ----------

func update(t: float, dt: float) -> void:
	for rec: Dictionary in recs:
		var e: Dictionary = rec["e"]
		match rec["type"]:
			"jelly":
				rec["kick"] = maxf(0.0, rec["kick"] - dt * 1.5)
				var amp: float = 0.025 + rec["kick"] * 0.18
				var w: float = sin(t * 9.0 + rec["i"]) * amp
				rec["wob"].scale = Vector3(1.0 - w * 0.5, 1.0 + w, 1.0 - w * 0.5)
			"boost":
				var mats: Array = rec["chev"]
				for k in mats.size():
					var on := fposmod(t * 3.0 - k * 0.33, 1.0) < 0.4
					mats[k].albedo_color = Gfx.col(0xffd60a if on else 0xff6d00)
			"jumppad":
				rec["kick"] = maxf(0.0, rec["kick"] - dt * 3.0)
				rec["spring"].scale.y = 1.0 + sin(rec["kick"] * 20.0) * rec["kick"] * 2.0
				rec["arrow"].position.y = e["size"][1] / 2.0 + 0.9 + sin(t * 3.0) * 0.12
			"teleport":
				rec["swirl_in"].rotation.z = t * 3.0
				rec["swirl_out"].rotation.z = -t * 3.0
			"bubble":
				_update_bubbles(rec, t)
			"lowgrav":
				var mm: MultiMesh = rec["mm"]
				var stars: Array = rec["stars"]
				var sy: float = e["size"][1]
				for k in stars.size():
					var s: Vector3 = stars[k]
					var y := (fposmod(s.y + t * 0.04, 1.0) - 0.5) * sy
					mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, Vector3(s.x + sin(t * 0.5 + k) * 0.3, y, s.z)))
			"wind":
				if rec.has("sock"):
					var gust := Level.wind_gust(e, t)
					var sock: Node3D = rec["sock"]
					sock.rotation = Vector3(-(1.0 - gust) * 1.1, rec["sock_dir"] + sin(t * 7.0) * 0.08 * gust, 0)
	_update_fx(t, dt)
	_update_riders()


func _update_bubbles(rec: Dictionary, t: float) -> void:
	var e: Dictionary = rec["e"]
	var parts := Level.bubble_parts(e, t)
	var pool: Array = rec["pool"]
	var last: Array = rec["last_u"]
	for k in parts.size():
		var c: Phys.Col = parts[k][0]
		var u: float = parts[k][1]
		var left: float = parts[k][2]
		var bn: Node3D = pool[k]
		# grossit en sortant du chaudron, tremble avant d'éclater
		var sc := clampf(u / 0.06, 0.05, 1.0)
		var shake := Vector3(sin(t * 47.0 + k) * 0.06, 0, cos(t * 41.0 + k) * 0.06) if left < 0.6 else Vector3.ZERO
		bn.position = Vector3(c.cx, c.cy, c.cz) + shake
		bn.scale = Vector3(sc, sc, sc) * (1.0 + (0.08 * sin(t * 30.0) if left < 0.6 else 0.0))
		if k < last.size() and u < last[k] - 0.5:
			# elle vient d'éclater en haut : gerbe de gouttelettes
			ctx.particles.burst(Vector3(c.cx, e["pos"][1] + e.get("rise", 6.0), c.cz), 14, [0xcaf0f8, 0xffffff, 0x90e0ef], 4.0, 0.1, 0.5, 6.0)
		if k < last.size():
			last[k] = u
		else:
			last.append(u)


## Particules : rafales (feuilles), bulles de boue, traînée de vitesse après un speed pad.
func _update_fx(t: float, dt: float) -> void:
	_fx -= dt
	_boost_snd -= dt
	if _fx < 0.0:
		_fx = 0.07
		for e: Dictionary in winds:
			var gust := Level.wind_gust(e, t)
			var f: Array = e.get("force", [24.0, 0.0, 0.0])
			var n := int(roundf(gust * clampf(e["size"][0] * e["size"][2] / 40.0, 1.0, 4.0)))
			for k in n:
				var p := Level._to_world(e, (randf() - 0.5) * e["size"][0], (randf() - 0.5) * e["size"][1], (randf() - 0.5) * e["size"][2])
				ctx.particles.emit(p[0], p[1], p[2], f[0] * gust * 0.45, f[1] * gust * 0.45 + (randf() - 0.5), f[2] * gust * 0.45, LEAVES[randi() % LEAVES.size()], 0.09, 0.9, 0.5)
		for rec: Dictionary in recs:
			if rec["type"] == "mud" and randf() < 0.3:
				var e: Dictionary = rec["e"]
				var p := Level._to_world(e, (randf() - 0.5) * e["size"][0] * 0.8, e["size"][1] / 2.0, (randf() - 0.5) * e["size"][2] * 0.8)
				ctx.particles.emit(p[0], p[1], p[2], 0, 0.6, 0, 0x5a3820, 0.12, 0.4, 2.0)
	var b := ctx.body
	if b.boost > 0.0 or b.flight > 0.0:
		_trail -= dt
		if _trail < 0.0:
			_trail = 0.03
			ctx.particles.emit(b.px + (randf() - 0.5) * 0.4, b.py + 0.3 + randf() * 0.9, b.pz + (randf() - 0.5) * 0.4, -b.vx * 0.1, 0, -b.vz * 0.1, 0xffffff if b.boost > 0.0 else 0xffd60a, 0.07, 0.35, 0.0)


## Joueurs suspendus : pose bras levés et poulie au-dessus des mains (joueur local : body.zip ; autres : FLAG_ZIP).
func _update_riders() -> void:
	if _ziplines.is_empty():
		return
	for rec: Dictionary in recs:
		if rec.has("handle"):
			rec["handle"].visible = ctx.body.zip != rec["i"]  # la poignée part avec le joueur local
	var used := 0
	for p: ClientPlayer in ctx.players.values():
		var hang := false
		var hand := Vector3.ZERO
		if p.id == ctx.my_id:
			hang = ctx.body.zip >= 0
			hand = p.pos + Vector3(0, Phys.ZIP_HANG, 0)
		else:
			# autres joueurs : drapeau de pose FLAG_ZIP de l'état réseau (vague 3)
			hang = p.flags & Protocol.FLAG_ZIP != 0
			hand = p.pos + Vector3(0, Phys.ZIP_HANG, 0)
		p.chr.hanging = hang
		if hang:
			if used >= _pulleys.size():
				var pl := _pulley()
				ctx.world.add_child(pl)
				_pulleys.append(pl)
			_pulleys[used].visible = true
			_pulleys[used].position = hand
			used += 1
	for k in range(used, _pulleys.size()):
		_pulleys[k].visible = false


# ---------- événements ----------

## Effets des PreEvents du joueur local (canon, téléporteur, tyrolienne).
func on_pre(ev: Dictionary, b: Phys.Body, from: Vector3) -> void:
	if ev["launched"] >= 0:
		ctx.sfx.boom(0.6)
		ctx.sfx.fire()
		ctx.shake(0.5)
		for rec: Dictionary in recs:
			if rec["i"] == ev["launched"] and rec.has("mouth"):
				ctx.particles.burst(rec["mouth"], 18, [0xffffff, 0xd6d6d6, 0xffd60a], 4.0, 0.25, 0.8, -1.0)
		ctx.particles.burst(from + Vector3(0, 0.3, 0), 10, [0xffffff, 0xffd60a], 3.0, 0.15, 0.5)
	if ev["teleported"] >= 0:
		ctx.sfx.pickup()
		ctx.particles.burst(from + Vector3(0, 0.8, 0), 20, [0x7cff3a, 0x2dc653, 0xffffff], 5.0, 0.14, 0.6, 0.0)
		ctx.particles.burst(Vector3(b.px, b.py + 0.8, b.pz), 20, [0xff9e00, 0xffd60a, 0xffffff], 5.0, 0.14, 0.6, 0.0)
	if ev["grabbed"] >= 0:
		ctx.sfx.place()
	if ev["released"] >= 0:
		ctx.sfx.jump()


## Après le pas : speed pad (son), atterrissages sur gélatine / trampoline directionnel (secousse du décor).
func on_contacts(contacts: Array, ev: Dictionary) -> void:
	if ev["boosted"] and _boost_snd <= 0.0:
		_boost_snd = 0.6
		ctx.sfx.go()
	for c: Phys.Contact in contacts:
		if not c.bounced:
			continue
		for rec: Dictionary in recs:
			if rec["i"] == c.id and rec.has("kick"):
				rec["kick"] = 1.0
