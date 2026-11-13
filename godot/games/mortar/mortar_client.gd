class_name MortarClient
extends ClientGame
## Abri & mortier — côté client : îles, blocs instanciés, visée, obus, explosions, caisses, zone, HUD.

const SHELL_COLOR := {"normal": 0x2b2140, "mega": 0xd00000, "cluster": 0xff9f1c, "sub": 0xff9f1c}
## Missiles : [couleur du corps, couleur de la pointe et des ailerons, taille].
const MISSILE := {
	"normal": [0xf8f9fa, 0xff4d6d, 1.0],
	"mega": [0x2b2140, 0xd00000, 1.55],
	"cluster": [0xffd60a, 0xff7b00, 1.15],
	"sub": [0xffd60a, 0xff7b00, 0.6],
}
const FIRE := [0xfff3b0, 0xffd166, 0xff9f1c, 0xff6b35]
const SMOKE := [0xadb5bd, 0x868e96, 0xced4da]
const CRATE_INFO := {
	"mega": {"color": 0xd00000, "name": "Méga-obus"},
	"cluster": {"color": 0xff9f1c, "name": "Obus à fragmentation"},
	"repair": {"color": 0x70e000, "name": "Réparation"},
}

var ctx: Main
var init: Dictionary
var n := 0
var my_plot := 0
var budget := 0
var mat := "wood"
var ammo := "normal"
var charge_start := -1.0
var last_fire := -10.0
var power := 0.0
var dirty := true
var cols: Array = []
var hud_timer := 0.0
var announced := false
var build_end := 0.0
var battle_end := 0.0
var shrink_start := 0.0
var max_hp := 100.0
var blocks := {}  # clé → { plot, x, y, z, mat, hp }
var hp := {}  # id → points de vie
var hp_order: Array = []
var dead := {}
var shells := {}  # id → { mesh, p, v, at, kind }
var crates := {}  # id → { mesh, chute, p, land_at, kind }
var inst := {}  # matériau → MultiMeshInstance3D
var tubes: Array = []
var rings: Array = []
var flashes: Array = []  # { mesh, mat, life, max, r, wave }
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var marker: MeshInstance3D
var grid: MeshInstance3D

var top: Label
var side_box: VBoxContainer
var side_rows := {}  # id → { label, bar }
var b_text: Label
var b_mats: HBoxContainer
var b_hint: Label
var b_bar: ProgressBar
var mat_chips: Array = []
var holes_on := false  # option : les obus trouent les îles
var holes := {}  # île → {Vector2i(cx, cz): true}
var island_tops := {}  # île → MeshInstance3D du sol découpé en cases
var top_mat: StandardMaterial3D
var wall_mat: StandardMaterial3D
var owner_color := {}  # île → couleur du propriétaire
var decos: Array = []  # [nœud, île, lx, lz] : décor posé sur le pourtour, qui tombe si le sol disparaît
var falling: Array = []  # {node, vy, spin}
var fx: Array = []  # effets d'explosion animés (boule de feu, fumée, lumière, traces)


func _rebuild() -> void:
	var counts := {"wood": 0, "stone": 0, "tramp": 0}
	for b: Dictionary in blocks.values():
		var c := MortarShared.block_center(b["plot"], b["x"], b["y"], b["z"], n)
		var xf := Transform3D(Basis(Vector3.UP, MortarShared.plot_yaw(b["plot"], n)), Vector3(c[0], c[1], c[2]))
		var mm: MultiMesh = inst[b["mat"]].multimesh
		mm.set_instance_transform(counts[b["mat"]], xf)
		counts[b["mat"]] += 1
	for k: String in MortarShared.MAT_KEYS:
		inst[k].multimesh.visible_instance_count = counts[k]
	dirty = true
	_sync_ground()


## Décor solide des éclats et des os (Jolt) : toutes les îles et tous les blocs.
func _sync_ground() -> void:
	if Debris.enabled():
		var all: Array = MortarShared.colliders(n, {}, -1, holes)
		var islands := all.size()
		for p in n:
			all.append_array(MortarShared.colliders(n, blocks, p, holes).slice(islands))
		ctx.debris.set_ground(all)


func _block_pos(b: Dictionary) -> Vector3:
	var c := MortarShared.block_center(b["plot"], b["x"], b["y"], b["z"], n)
	return Vector3(c[0], c[1], c[2])


## Retire des blocs ; détruits par une explosion en `from`, ils volent en éclats (effets physiques activés).
func _remove_blocks(keys: Array, from: Variant = null) -> void:
	var shatter := from != null and Debris.enabled()
	for key: String in keys:
		if not blocks.has(key):
			continue
		var b: Dictionary = blocks[key]
		blocks.erase(key)
		var bp := _block_pos(b)
		ctx.particles.burst(bp, 4 if shatter else 8, [MortarShared.MATS[b["mat"]]["color"]], 5.0, 0.22, 0.8)
		if shatter:
			var basis := Basis(Vector3.UP, MortarShared.plot_yaw(b["plot"], n))
			ctx.debris.shatter(bp, basis, 0.98, inst[b["mat"]].material_override, from)
	_rebuild()


## Explosion : éclair aveuglant, boule de feu en plusieurs bouffées qui virent à la fumée noire et montent,
## gerbe d'étincelles, onde de choc, lueur sur le décor et trace de brûlé au sol.
func _explosion(p: Vector3, r: float, kind: String, burn_mark := true) -> void:
	var big := kind == "mega"
	var small := kind == "sub" or kind == "cluster"
	var d := p.distance_to(ctx.body.pos())
	ctx.sfx.boom(clampf(14.0 / (d + 4.0), 0.15, 1.0) * (1.3 if big else 1.0))
	if d < 14.0:
		ctx.impact((1.0 - d / 14.0) * (1.0 if big else 0.65), Color(1.0, 0.8, 0.45))
	# lueur orangée sur tout ce qui est autour
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.3)
	light.omni_range = r * 5.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.position = p + Vector3(0, 0.6, 0)
	ctx.world.add_child(light)
	fx.append({"k": "light", "node": light, "age": 0.0, "max": 0.45, "e": 9.0 if big else 6.0})
	# éclair blanc qui gonfle très vite
	var cm := Gfx.flat(0xfff8e1, {"add": true})
	var core := Gfx.mesh(Shapes.sphere(1.0, 18, 12), cm, p.x, p.y + 0.2, p.z, ctx.world, false)
	fx.append({"k": "core", "node": core, "mat": cm, "age": 0.0, "max": 0.22, "r": r * 0.75})
	# boule de feu : des bouffées qui gonflent, s'assombrissent en fumée et s'élèvent
	var puffs := 12 if big else (4 if small else 8)
	var sphere := Shapes.sphere(1.0, 14, 10)
	for k in puffs:
		var dir := Vector3(randf() - 0.5, randf() * 0.7 + 0.15, randf() - 0.5).normalized()
		var at := p + dir * r * randf_range(0.1, 0.4)
		var pm := Gfx.mat(FIRE[k % FIRE.size()], {"glow": 3.0, "opacity": 0.95, "rough": 1.0})
		pm.rim_enabled = false
		var puff := Gfx.mesh(sphere, pm, at.x, at.y, at.z, ctx.world, false)
		puff.scale = Vector3.ONE * 0.05
		fx.append({"k": "puff", "node": puff, "mat": pm, "age": -randf() * 0.08, "max": randf_range(1.3, 1.9),
			"size": r * randf_range(0.32, 0.5), "v": dir * r * randf_range(0.9, 1.6) + Vector3(0, 0.8, 0), "fire": FIRE[k % FIRE.size()]})
	# étincelles et éclats
	ctx.particles.burst(p, 60 if big else (18 if small else 34), [0xfff3b0, 0xffd166, 0xff9f1c, 0xffffff], r * 5.0, 0.12, 0.7, 14.0, 0.7)
	ctx.particles.burst(p, 10 if big else 5, [0x495057, 0x343a40], r * 3.0, 0.2, 1.1, 16.0, 0.9)
	# onde de choc : anneau qui file au ras du sol
	var wm := Gfx.flat(0xfff3b0, {"opacity": 0.85})
	var wave := Gfx.mesh(Shapes.torus(1.0, 0.06, 48, 8), wm, p.x, maxf(0.12, p.y), p.z, ctx.world, false)
	flashes.append({"mesh": wave, "mat": wm, "life": 0.4, "max": 0.4, "r": r * 1.7, "wave": true})
	# trace de brûlé sur l'île, qui s'estompe lentement
	if burn_mark and p.y < 0.6 and _on_island(p):
		var sm := Gfx.flat(0x1f1a17, {"opacity": 0.6})
		var scorch := Gfx.mesh(Shapes.cylinder(r * 0.55, r * 0.55, 0.01, 24), sm, p.x, 0.02, p.z, ctx.world, false)
		fx.append({"k": "scorch", "node": scorch, "mat": sm, "age": 0.0, "max": 9.0})


func _on_island(p: Vector3) -> bool:
	for i in n:
		var l := MortarShared.to_local(i, n, p.x, p.z)
		if absf(l[0]) < MortarShared.ISLAND / 2.0 and absf(l[1]) < MortarShared.ISLAND / 2.0:
			return not MortarShared.is_hole(holes, i, n, p.x, p.z)
	return false


func _update_fx(dt: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var e: Dictionary = fx[i]
		e["age"] += dt
		var a: float = e["age"]
		var k: float = clampf(a / e["max"], 0.0, 1.0)
		var node: Node3D = e["node"]
		match e["k"]:
			"light":
				(node as OmniLight3D).light_energy = e["e"] * (1.0 - k) * (1.0 - k) if a > 0.03 else e["e"] * a / 0.03
			"core":
				node.scale = Vector3.ONE * maxf(0.01, e["r"] * (0.3 + 0.9 * sqrt(k)))
				(e["mat"] as StandardMaterial3D).albedo_color.a = 1.0 - k
			"puff":
				if a < 0.0:
					continue
				# gonfle vite, puis ralentit ; feu → fumée noire qui monte et se dissipe
				var grow := 1.0 - pow(1.0 - minf(1.0, a / 0.35), 3.0)
				var v: Vector3 = e["v"]
				node.position += v * dt
				e["v"] = v * exp(-4.0 * dt) + Vector3(0, 1.4 * dt, 0)
				node.scale = Vector3.ONE * maxf(0.05, e["size"] * (0.25 + 0.75 * grow + 0.5 * k))
				var m: StandardMaterial3D = e["mat"]
				var burn := clampf((a - 0.12) / 0.45, 0.0, 1.0)
				var fire := Gfx.col(e["fire"])
				var smoke := Color(0.22, 0.2, 0.2).lerp(Color(0.5, 0.5, 0.52), k)
				m.albedo_color = Color(fire.lerp(smoke, burn), 0.95 * (1.0 - k * k))
				m.emission_energy_multiplier = 3.0 * (1.0 - burn)
			"scorch":
				(e["mat"] as StandardMaterial3D).albedo_color.a = 0.6 * (1.0 - k * k)
		if e["age"] >= e["max"]:
			node.queue_free()
			fx.remove_at(i)
	# décor qui tombe dans un trou
	for i in range(falling.size() - 1, -1, -1):
		var fl: Dictionary = falling[i]
		var nd: Node3D = fl["node"]
		if not is_instance_valid(nd):
			falling.remove_at(i)
			continue
		fl["vy"] -= 18.0 * dt
		nd.position.y += fl["vy"] * dt
		nd.rotation.x += fl["spin"] * dt
		if nd.position.y < -20.0:
			nd.queue_free()
			falling.remove_at(i)


# ---------- missiles ----------

## Missile stylé : corps, bague, pointe, ailerons, tuyère et flamme. Son axe +Y suit la trajectoire.
func _make_missile(kind: String) -> Dictionary:
	var spec: Array = MISSILE[kind]
	var root := Node3D.new()
	ctx.world.add_child(root)
	var body := Node3D.new()
	body.scale = Vector3.ONE * float(spec[2])
	root.add_child(body)
	var hull := Gfx.mat(spec[0], {"rough": 0.25, "metal": 0.25})
	var accent := Gfx.mat(spec[1], {"rough": 0.3, "metal": 0.2})
	Gfx.mesh(Shapes.cylinder(0.13, 0.13, 0.62, 16), hull, 0, 0, 0, body)
	Gfx.mesh(Shapes.cylinder(0.0, 0.13, 0.3, 16), accent, 0, 0.46, 0, body)
	Gfx.mesh(Shapes.cylinder(0.137, 0.137, 0.07, 16), accent, 0, 0.14, 0, body)
	Gfx.mesh(Shapes.cylinder(0.137, 0.137, 0.04, 16), accent, 0, 0.03, 0, body)
	Gfx.mesh(Shapes.cylinder(0.08, 0.11, 0.09, 12), Gfx.mat(0x343a40, {"metal": 0.7, "rough": 0.3}), 0, -0.35, 0, body)
	var fin := Shapes.rbox(0.17, 0.24, 0.03, 0.01)
	for k in 4:
		var a := k * PI / 2.0
		var f := Gfx.mesh(fin, accent, cos(a) * 0.2, -0.2, sin(a) * 0.2, body)
		f.rotation.y = -a
	# flamme : un cône extérieur orange et un cœur presque blanc, en fusion additive
	var flame := Gfx.mesh(Shapes.cylinder(0.11, 0.0, 0.7, 12), Gfx.flat(0xff7b00, {"add": true}), 0, -0.75, 0, body, false)
	var heart := Gfx.mesh(Shapes.cylinder(0.065, 0.0, 0.4, 10), Gfx.flat(0xfff3b0, {"add": true}), 0, -0.58, 0, body, false)
	return {"root": root, "body": body, "flame": flame, "heart": heart, "size": float(spec[2])}


func _update_missile(sh: Dictionary, t: float) -> void:
	var age: float = t - sh["at"]
	var p := MortarShared.shell_at(sh["p"], sh["v"], age)
	var v := Vector3(sh["v"][0], sh["v"][1] - MortarShared.G * age, sh["v"][2])
	var dir := v.normalized() if v.length_squared() > 1e-4 else Vector3.UP
	var root: Node3D = sh["root"]
	root.position = p
	# nez dans le sens du vol, et le missile tourne sur lui-même
	root.basis = Basis(Quaternion(Vector3.UP, dir)) * Basis(Vector3.UP, t * 9.0 + float(sh["roll"]))
	var fl: Node3D = sh["flame"]
	fl.scale = Vector3(randf_range(0.85, 1.15), randf_range(0.75, 1.35), randf_range(0.85, 1.15))
	(sh["heart"] as Node3D).scale = Vector3(1, randf_range(0.8, 1.2), 1)
	var sz: float = sh["size"]
	var tail := p - dir * 0.55 * sz
	# traînée : du feu juste derrière, puis une fumée qui reste en l'air
	for k in 2:
		var j := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.6
		var fv := -dir * randf_range(2.0, 4.0) + j
		ctx.particles.emit(tail.x, tail.y, tail.z, fv.x, fv.y, fv.z, FIRE[randi() % FIRE.size()], 0.15 * sz, 0.22, 0.0)
	if randf() < 0.8:
		var sv := -dir * 0.6 + Vector3(randf() - 0.5, randf() * 0.4, randf() - 0.5) * 0.5
		ctx.particles.emit(tail.x, tail.y, tail.z, sv.x, sv.y, sv.z, SMOKE[randi() % SMOKE.size()], 0.24 * sz, 1.0, -0.6)


## Case visée : 1,6 m devant le joueur, dans la direction de la caméra. Vector3i(x, hauteur, z) ou null.
func _aim_cell() -> Variant:
	var yaw := ctx.cam_yaw
	var cell: Variant = MortarShared.cell_at(my_plot, n, ctx.body.px + sin(yaw) * 1.6, ctx.body.pz + cos(yaw) * 1.6)
	if cell == null:
		return null
	return Vector3i(cell.x, MortarShared.column_height(blocks, my_plot, cell.x, cell.y), cell.y)


static func _grid_mesh(size: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var half := size / 2.0
	for i in size + 1:
		var k := -half + i
		v.append_array([Vector3(k, 0, -half), Vector3(k, 0, half), Vector3(-half, 0, k), Vector3(half, 0, k)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return m


# ---------- îles trouées (option) ----------

## Sol d'une île en cases de HOLE_CELL m : dessus herbeux (bruni au bord des trous, cadre de la zone constructible à la
## couleur du propriétaire), parois de terre tout autour des trous et du bord.
func _build_island(plot: int) -> void:
	var h: Dictionary = holes.get(plot, {})
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sw := SurfaceTool.new()
	sw.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cs := MortarShared.HOLE_CELL
	var half := MortarShared.ISLAND / 2.0
	var depth := MortarShared.THICK
	var frame := Gfx.col(owner_color.get(plot, 0xffffff)).lightened(0.25)
	var burnt := Color(0.45, 0.32, 0.2)
	var dirt := Color(0.69, 0.54, 0.41)
	var dark_dirt := Color(0.5, 0.36, 0.25)
	var zone := MortarShared.GRID / 2.0
	for cz in MortarShared.HOLE_N:
		for cx in MortarShared.HOLE_N:
			var c := Vector2i(cx, cz)
			if h.has(c):
				continue
			var x0 := -half + cx * cs
			var z0 := -half + cz * cs
			var x1 := x0 + cs
			var z1 := z0 + cs
			# couleur du dessus : cadre de la zone constructible, brûlé près d'un trou, ou herbe
			var col := Color.WHITE
			var mx := (x0 + x1) / 2.0
			var mz := (z0 + z1) / 2.0
			var on_frame := (absf(absf(mx) - zone) < cs * 0.6 and absf(mz) < zone + cs) or (absf(absf(mz) - zone) < cs * 0.6 and absf(mx) < zone + cs)
			if on_frame:
				col = frame
			var near := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				if h.has(c + d):
					near = true
					break
			if near:
				col = col * burnt
			_quad(st, Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1), Vector3.UP, col, true)
			# parois : vers un trou ou vers le vide du bord
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var o := c + d
				var outside := o.x < 0 or o.y < 0 or o.x >= MortarShared.HOLE_N or o.y >= MortarShared.HOLE_N
				if not outside and not h.has(o):
					continue
				var a: Vector3
				var b: Vector3
				if d.x == 1:
					a = Vector3(x1, 0, z1)
					b = Vector3(x1, 0, z0)
				elif d.x == -1:
					a = Vector3(x0, 0, z0)
					b = Vector3(x0, 0, z1)
				elif d.y == 1:
					a = Vector3(x0, 0, z1)
					b = Vector3(x1, 0, z1)
				else:
					a = Vector3(x1, 0, z0)
					b = Vector3(x0, 0, z0)
				var down := Vector3(0, -depth, 0)
				var wall := dirt if outside else dark_dirt
				_quad(sw, a, b, b + down, a + down, Vector3(d.x, 0, d.y), wall, false)
			_quad(sw, Vector3(x0, -depth, z1), Vector3(x1, -depth, z1), Vector3(x1, -depth, z0), Vector3(x0, -depth, z0), Vector3.DOWN, dark_dirt, false)
	var mesh := st.commit()
	sw.commit(mesh)
	mesh.surface_set_material(0, top_mat)
	mesh.surface_set_material(1, wall_mat)
	var top: MeshInstance3D = island_tops[plot]
	top.mesh = mesh


## Quadrilatère a b c d (dans le sens horaire vu du côté de la normale), de couleur unie ; UV pour la texture d'herbe.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, col: Color, grass: bool) -> void:
	var half := MortarShared.ISLAND / 2.0
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_normal(normal)
		st.set_color(col)
		st.set_uv(Vector2((v.x + half) / MortarShared.ISLAND, (v.z + half) / MortarShared.ISLAND) if grass else Vector2.ZERO)
		st.add_vertex(v)


## Trous creusés par une explosion : sol reconstruit, mottes de terre, décor qui tombe.
func _dig(cells: Array, from: Vector3) -> void:
	if cells.is_empty():
		return
	var touched := {}
	for c: Array in cells:
		var plot := int(c[0])
		var h: Dictionary = holes.get(plot, {})
		h[Vector2i(int(c[1]), int(c[2]))] = true
		holes[plot] = h
		touched[plot] = true
	for plot: int in touched:
		if island_tops.has(plot):
			_build_island(plot)
	ctx.particles.burst(from, 26, [0x8a5a3c, 0xb08968, 0x5c3d2e, 0x7fdc6b], 7.0, 0.2, 1.2, 16.0, 0.9)
	for i in range(decos.size() - 1, -1, -1):
		var dc: Array = decos[i]
		var plot: int = dc[1]
		if not touched.has(plot):
			continue
		var cell := Vector2i(floori((float(dc[2]) + MortarShared.ISLAND / 2.0) / MortarShared.HOLE_CELL), floori((float(dc[3]) + MortarShared.ISLAND / 2.0) / MortarShared.HOLE_CELL))
		if holes[plot].has(cell):
			falling.append({"node": dc[0], "vy": 2.0, "spin": randf_range(-4.0, 4.0)})
			decos.remove_at(i)
	dirty = true
	_sync_ground()


func on_enter(c: Main, p_init: Variant) -> void:
	ctx = c
	init = p_init
	n = int(init["n"])
	var plots: Dictionary = init["plots"]
	my_plot = int(plots.get(ctx.my_id, 0))
	budget = int(init["budget"])
	build_end = init["buildEnd"]
	battle_end = init["battleEnd"]
	shrink_start = init["shrinkStart"]
	max_hp = init["hp"]
	holes_on = init.get("holes", false) == true
	ctx.set_sky(0x86ccff)
	ctx.set_aim_mode(true)
	ctx.cam_yaw = MortarShared.plot_yaw(my_plot, n) + PI  # face au centre de l'arène
	ctx.set_sea(-9.5, 0x2a86e8)

	var owners := {}
	for id: String in plots:
		owners[int(plots[id])] = id
	var grass := Gfx.mat(0xffffff, {"map": Tex.soft("#7fdc6b", "#92e67c"), "uv": Vector2(3, 3), "rough": 0.7})
	var bush := Shapes.sphere(1.0, 12, 9)
	var pebble := Shapes.icosphere(1.0, 1)
	var s := MortarShared.ISLAND
	for p in n:
		var ctr := MortarShared.plot_center(p, n)
		var g := Node3D.new()
		g.position = ctr
		g.rotation.y = MortarShared.plot_yaw(p, n)
		var owner: ClientPlayer = ctx.players.get(owners.get(p, ""))
		var color: int = owner.color if owner else 0xffffff
		owner_color[p] = color
		if holes_on:
			# sol découpé en cases, reconstruit à chaque trou ; pas d'herbe ni de rocher dessous (on doit voir le vide)
			if top_mat == null:
				top_mat = Gfx.mat(0xffffff, {"map": Tex.soft("#7fdc6b", "#92e67c"), "uv": Vector2(3, 3), "rough": 0.7, "double": true})
				top_mat.vertex_color_use_as_albedo = true
				wall_mat = Gfx.mat(0xffffff, {"rough": 0.9, "double": true})
				wall_mat.vertex_color_use_as_albedo = true
			var top := MeshInstance3D.new()
			g.add_child(top)
			island_tops[p] = top
			_build_island(p)
		else:
			Gfx.mesh(Shapes.rbox(s + 0.3, 0.5, s + 0.3, 0.24), grass, 0, -0.25, 0, g)
			# herbe au vent sur le pourtour (pas dans la zone constructible)
			var herbe := Gfx.grass(Vector2(s, s), 6.0, 0x4fb945, 0xa9ea7e, [Rect2(-4.4, -4.4, 8.8, 8.8)], p + 3)
			if herbe:
				g.add_child(herbe)
			Gfx.mesh(Shapes.rbox(s, MortarShared.THICK - 0.4, s, 0.3), Gfx.mat(0xb08968, {"rough": 0.85}), 0, -0.4 - (MortarShared.THICK - 0.4) / 2.0, 0, g)
			var rock := Gfx.rock_under(s * 0.98, 6.0, s * 0.98, 0x8a5a3c, p * 7)
			rock.position.y = -MortarShared.THICK + 0.1
			g.add_child(rock)
			# cadre lumineux de la zone constructible, à la couleur du propriétaire (dessiné dans le sol sinon)
			var frame := Gfx.mat(color, {"glow": 0.9})
			var half := MortarShared.GRID / 2.0 + 0.1
			for sgn in [-1.0, 1.0]:
				Gfx.mesh(Shapes.rbox(MortarShared.GRID + 0.4, 0.08, 0.14, 0.04), frame, 0, 0.04, sgn * half, g)
				Gfx.mesh(Shapes.rbox(0.14, 0.08, MortarShared.GRID + 0.4, 0.04), frame, sgn * half, 0.04, 0, g)
		# drapeau, buissons et cailloux sur le pourtour (hors de la zone constructible)
		var pole := Gfx.mesh(Shapes.cylinder(0.06, 0.06, 3.0, 8), Gfx.mat(0xffffff), 5.3, 1.5, 5.3, g)
		var flag := Gfx.mesh(Shapes.rbox(1.1, 0.7, 0.06, 0.03), Gfx.mat(color, {"rough": 0.5}), 4.7, 2.6, 5.3, g)
		decos.append([pole, p, 5.3, 5.3])
		decos.append([flag, p, 5.3, 5.3])
		for k in 7:
			var a := int(fmod(k * 2.399 + p, 4.0))
			var u := fmod(k * 3.7 + p * 1.3, 9.0) - 4.5
			var edge := 5.3
			var x := u
			var z := edge
			if a == 1:
				z = -edge
			elif a == 2:
				x = edge
				z = u
			elif a == 3:
				x = -edge
				z = u
			var dn: MeshInstance3D
			if k % 3 == 0:
				dn = Gfx.mesh(pebble, Gfx.mat(0xaab3bd, {"rough": 0.8}), x, 0.15, z, g)
				dn.scale = Vector3(0.35, 0.25, 0.3)
			else:
				dn = Gfx.mesh(bush, Gfx.foliage(0x3fbf6f if k % 2 else 0x55d07f, 0.05), x, 0.25, z, g)
				dn.scale = Vector3(0.5, 0.38, 0.45)
			decos.append([dn, p, x, z])
		if p % 2 == 0:
			var t := Gfx.tree(2.4)
			t.position = Vector3(-5.3, 0, 5.3)
			g.add_child(t)
			decos.append([t, p, -5.3, 5.3])
		ctx.world.add_child(g)
		var ring := Gfx.mesh(Shapes.torus(1.0, 0.012, 72, 6), Gfx.flat(0xff2a6d), ctr.x, 0.12, ctr.z, ctx.world, false)
		ring.visible = false
		rings.append(ring)

	var cap := maxi(16, n * (budget + 2))
	var block_mesh := Shapes.rbox(0.98, 0.98, 0.98, 0.1)
	var maps := {"wood": Tex.planks(), "stone": Tex.stone(), "tramp": Tex.target("#39c5ff", "#ffffff")}
	for k: String in MortarShared.MAT_KEYS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = block_mesh
		mm.instance_count = cap
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = Gfx.mat(0xffffff, {"map": maps[k], "rough": 0.8 if k == "stone" else 0.5})
		mi.custom_aabb = AABB(Vector3(-200, -5, -200), Vector3(400, 20, 400))
		ctx.world.add_child(mi)
		inst[k] = mi
	ghost_mat = Gfx.flat(0xffffff, {"opacity": 0.45})
	ghost = Gfx.mesh(Shapes.box(), ghost_mat, 0, 0, 0, ctx.world, false)
	ghost.rotation.y = MortarShared.plot_yaw(my_plot, n)
	ghost.visible = false
	marker = Gfx.mesh(Shapes.ring(0.7, 1.0, 36), Gfx.flat(0xff2a6d, {"double": true, "no_depth": true}), 0, 0, 0, ctx.world, false)
	marker.visible = false
	var mc := MortarShared.plot_center(my_plot, n)
	grid = Gfx.mesh(_grid_mesh(MortarShared.GRID), Gfx.flat(0xffffff, {"opacity": 0.6}), mc.x, 0.06, mc.z, ctx.world, false)
	grid.rotation.y = MortarShared.plot_yaw(my_plot, n)
	_sync_ground()

	# chaque personnage porte son mortier
	for id: String in ctx.players:
		if not plots.has(id):
			continue
		hp[id] = max_hp
		hp_order.append(id)
		var p: ClientPlayer = ctx.players[id]
		var tube := Gfx.mesh(Shapes.cylinder(0.13, 0.17, 0.7, 16), Gfx.mat(0x343a40, {"metal": 0.7, "rough": 0.3}), 0.42, 0.85, 0.2, p.chr)
		Gfx.mesh(Shapes.torus(0.14, 0.035, 16, 8), Gfx.mat(0xffd60a, {"metal": 0.4, "rough": 0.3}), 0, 0.33, 0, tube)
		tube.rotation.x = PI / 2.0 - MortarShared.ELEV
		tubes.append(tube)

	top = UI.label("", 20)
	ctx.ui.hud_card("top").add_child(top)
	side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 1)
	side_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctx.ui.hud_card("side").add_child(side_box)
	for id: String in hp_order:
		var p: ClientPlayer = ctx.players[id]
		var l := UI.label("", 14)
		var bar := UI.lag_bar(170, 12, Gfx.col(p.color))
		side_box.add_child(l)
		side_box.add_child(bar)
		side_rows[id] = {"label": l, "bar": bar}
	var bottom := VBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctx.ui.hud_card("bottom").add_child(bottom)
	b_text = UI.label("", 15)
	b_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(b_text)
	b_mats = HBoxContainer.new()
	b_mats.alignment = BoxContainer.ALIGNMENT_CENTER
	b_mats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var k: String = MortarShared.MAT_KEYS[i]
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(UI.label("%d %s (%d)" % [i + 1, MortarShared.MATS[k]["name"], MortarShared.MATS[k]["cost"]], 14))
		b_mats.add_child(chip)
		mat_chips.append(chip)
	bottom.add_child(b_mats)
	b_hint = UI.label("Clic gauche ou F : poser · Clic droit ou R : retirer · 1 2 3 : matériau", 12, UI.MUTED)
	b_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(b_hint)
	b_bar = UI.bar(320, 14, UI.ACCENT)
	b_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(b_bar)


func colliders(_t: float) -> Array:
	if dirty:
		cols = MortarShared.colliders(n, blocks, my_plot, holes)
		dirty = false
	return cols


func post_step(_b: Phys.Body, contacts: Array, _dt: float) -> void:
	for ct: Phys.Contact in contacts:
		if ct.bounced:
			ctx.sfx.boing()
			return


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func on_message(m: Dictionary) -> void:
	match m["t"]:
		"block":
			var src: Dictionary = m["b"]
			var b := {"plot": int(src["plot"]), "x": int(src["x"]), "y": int(src["y"]), "z": int(src["z"]), "mat": str(src["mat"]), "hp": src["hp"]}
			blocks[MortarShared.block_key(b["plot"], b["x"], b["y"], b["z"])] = b
			_rebuild()
			if m.get("by") == ctx.my_id:
				budget = int(m["budget"])
				ctx.sfx.place()
		"unblock":
			_remove_blocks(m["keys"])
			if m.get("by") == ctx.my_id:
				budget = int(m["budget"])
				ctx.sfx.remove()
		"shell":
			var kind: String = m["kind"]
			var sh := _make_missile(kind)
			sh.merge({"p": m["p"], "v": m["v"], "at": m["at"], "kind": kind, "roll": randf() * TAU})
			shells[int(m["id"])] = sh
			_update_missile(sh, ctx.now())
			var p0 := _v3(m["p"])
			if kind != "sub":
				ctx.sfx.fire()
				# bouffée de départ au bout du tube
				ctx.particles.burst(p0, 10, FIRE, 3.0, 0.14, 0.3, 0.0, 0.6)
				ctx.particles.burst(p0, 6, SMOKE, 1.5, 0.22, 0.9, -0.5, 0.6)
		"bounce":
			var sh: Variant = shells.get(int(m["id"]))
			if sh != null:
				sh["p"] = m["p"]
				sh["v"] = m["v"]
				sh["at"] = m["at"]
			ctx.sfx.boing()
		"gone", "boom":
			var id := int(m["id"])
			if shells.has(id):
				shells[id]["root"].queue_free()
				shells.erase(id)
			if m["t"] == "boom":
				var dug: Array = m.get("holes", [])
				# un trou a déjà son bord brûlé : pas de trace au sol par-dessus
				_explosion(_v3(m["p"]), m["r"], m["kind"], dug.is_empty())
				_dig(dug, _v3(m["p"]))
				_remove_blocks(m["removed"], _v3(m["p"]))
		"hp":
			hp[m["id"]] = m["hp"]
		"dead":
			var id: String = m["id"]
			dead[id] = true
			hp[id] = 0.0
			var p: ClientPlayer = ctx.players.get(id)
			var by_hp: bool = m["cause"] == "hp"
			if p:
				if by_hp:
					p.chr.die()
					ctx.sfx.xylo()
				else:
					p.hidden = true
			if id == ctx.my_id:
				ctx.set_active(false)
				ctx.impact(1.0, Color(1.0, 0.35, 0.35) if by_hp else Color(0.6, 0.8, 1.0))
				ctx.set_charging(false)
				ctx.set_spectate(Vector3(0, 3, 0), maxf(18.0, MortarShared.plot_cz(0, n) * 1.6))
				ctx.toast("Tu n'es plus qu'un tas d'os !" if by_hp else "Tombé dans le vide !", 3.0)
			elif p:
				ctx.toast("%s est éliminé !" % p.name, 1.5)
		"ammo":
			ammo = m["kind"]
		"crate":
			var kind: String = m["kind"]
			var crate := Gfx.mesh(Shapes.rbox(0.8, 0.8, 0.8, 0.12), Gfx.mat(CRATE_INFO[kind]["color"], {"rough": 0.35}), 0, 0, 0, ctx.world)
			Gfx.mesh(Shapes.rbox(0.86, 0.2, 0.86, 0.06), Gfx.mat(0xffffff), 0, 0, 0, crate)
			Gfx.mesh(Shapes.rbox(0.2, 0.86, 0.86, 0.06), Gfx.mat(0xffffff), 0, 0, 0, crate)
			# parachute, replié à l'atterrissage
			var chute := Node3D.new()
			Gfx.mesh(Shapes.sphere_part(1.1, 16, 8, 0.0, TAU, 0.0, PI / 2.0), Gfx.mat(0xffffff, {"map": Tex.stripes("#ffffff", "#ff4d6d"), "uv": Vector2(6, 1), "double": true}), 0, 1.3, 0, chute)
			var cord := Gfx.flat(0xffffff)
			for d: Array in [[-1.0, 0.0], [1.0, 0.0], [0.0, -1.0], [0.0, 1.0]]:
				var line := Gfx.mesh(Shapes.cylinder(0.012, 0.012, 1.45, 4), cord, d[0] * 0.5, 0.95, d[1] * 0.5, chute, false)
				line.rotation = Vector3(d[1] * 0.38, 0, -d[0] * 0.38)
			crate.add_child(chute)
			crate.position = _v3(m["p"]) + Vector3(0, 30, 0)
			crates[int(m["id"])] = {"mesh": crate, "chute": chute, "p": _v3(m["p"]), "land_at": m["landAt"], "kind": kind}
		"crateTaken":
			var id := int(m["id"])
			if crates.has(id):
				var cr: Dictionary = crates[id]
				cr["mesh"].queue_free()
				crates.erase(id)
				ctx.particles.burst(cr["p"], 20, [CRATE_INFO[cr["kind"]]["color"], 0xffffff], 5.0, 0.14, 0.8)
			if m["by"] == ctx.my_id:
				ctx.sfx.pickup()
				ctx.toast("%s !" % CRATE_INFO[m["kind"]]["name"], 1.5)


func on_frame(dt: float) -> void:
	var t := ctx.now()
	var inp := ctx.input
	var started := t >= ctx.start_at
	var building := t < build_end
	var alive := not dead.has(ctx.my_id)
	if not building and not announced:
		announced = true
		ctx.toast("Feu à volonté !", 2.0)
		ctx.sfx.go()
	grid.visible = building

	# ----- construction -----
	ghost.visible = false
	if building and started and alive:
		for k in 3:
			if inp.hit("Digit%d" % (k + 1), "Numpad%d" % (k + 1)):
				mat = MortarShared.MAT_KEYS[k]
		if inp.hit("PadMat"):  # manette : matériau suivant
			mat = MortarShared.MAT_KEYS[(MortarShared.MAT_KEYS.find(mat) + 1) % MortarShared.MAT_KEYS.size()]
		var cell: Variant = _aim_cell()
		if cell != null and cell.y < MortarShared.MAX_H:
			var c := MortarShared.block_center(my_plot, cell.x, cell.y, cell.z, n)
			ghost.position = Vector3(c[0], c[1], c[2])
			ghost.visible = true
			var ok: bool = budget >= MortarShared.MATS[mat]["cost"]
			ghost_mat.albedo_color = Color(Gfx.col(MortarShared.MATS[mat]["color"] if ok else 0xff0000), 0.45)
		if cell != null and inp.hit("Mouse0", "KeyF"):
			ctx.send_game({"t": "place", "x": cell.x, "z": cell.z, "mat": mat})
		if cell != null and (inp.hit("Mouse2", "KeyR") or inp.hit("PadRemove")):
			ctx.send_game({"t": "remove", "x": cell.x, "z": cell.z})

	# ----- tir : maintenir pour charger, relâcher pour tirer -----
	marker.visible = false
	if not building and alive:
		var ready := t - last_fire >= MortarShared.RELOAD
		if charge_start < 0.0 and ready and inp.hit("Mouse0", "KeyF"):
			charge_start = t
		if charge_start >= 0.0:
			# la jauge monte puis redescend, pour pouvoir doser les tirs courts comme les longs
			var u := fmod((t - charge_start) / MortarShared.CHARGE_TIME, 2.0)
			power = u if u <= 1.0 else 2.0 - u
			var yaw := ctx.cam_yaw
			var l := MortarShared.launch(ctx.body.px, ctx.body.py, ctx.body.pz, yaw, power)
			var reach := MortarShared.shell_range(l)
			# en tombant dans le vide, l'obus ne remonterait jamais à y = 0 : portée indéfinie, pas de marqueur
			marker.visible = is_finite(reach)
			if marker.visible:
				marker.position = Vector3(l[0] + sin(yaw) * reach, 0.12, l[2] + cos(yaw) * reach)
			marker.rotation.y = t * 3.0
			if inp.up("Mouse0", "KeyF") or not inp.down("Mouse0", "KeyF"):
				ctx.send_game({"t": "fire", "yaw": yaw, "power": power})
				last_fire = t
				charge_start = -1.0
		ctx.set_charging(charge_start >= 0.0)

	# ----- obus, éclairs, caisses, zone -----
	for sh: Dictionary in shells.values():
		_update_missile(sh, t)
	_update_fx(dt)
	for i in range(flashes.size() - 1, -1, -1):
		var f: Dictionary = flashes[i]
		f["life"] -= dt
		var k: float = 1.0 - f["life"] / f["max"]
		var sc: float = f["r"] * (0.25 + (1.0 - (1.0 - k) * (1.0 - k)) * 0.95)
		f["mesh"].scale = Vector3(sc, 1, sc) if f["wave"] else Vector3(sc, sc, sc)
		var fm: StandardMaterial3D = f["mat"]
		fm.albedo_color.a = 0.9 * (1.0 - k)
		if f["life"] <= 0.0:
			f["mesh"].queue_free()
			flashes.remove_at(i)
	for cr: Dictionary in crates.values():
		var fall := maxf(0.0, cr["land_at"] - t)
		var cp: Vector3 = cr["p"]
		cr["mesh"].position = Vector3(cp.x, cp.y + fall * 7.0 + (0.0 if fall > 0.0 else sin(t * 3.0) * 0.08), cp.z)
		cr["mesh"].rotation.y = sin(t * 2.0) * 0.3 if fall > 0.0 else t * 1.5
		cr["chute"].visible = fall > 0.0
	var shrinking := t > shrink_start - 5.0 and shrink_start < battle_end
	var zr := MortarShared.zone_radius(t, shrink_start, battle_end)
	for r: MeshInstance3D in rings:
		r.visible = shrinking
		r.scale = Vector3(zr, 6.0 + sin(t * 6.0) * 2.0, zr)

	for row: Dictionary in side_rows.values():
		UI.tick_lag(row["bar"], dt)

	# ----- HUD -----
	hud_timer -= dt
	if hud_timer < 0.0:
		hud_timer = 0.08
		var left := maxf(0.0, (build_end if building else battle_end) - maxf(t, ctx.start_at))
		if building:
			top.text = "Construction : %d s" % roundi(left)
		else:
			top.text = "Bataille : %d s%s" % [roundi(left), " — la zone rétrécit !" if t > shrink_start else ""]
		# barres de vie, de la plus pleine à la plus vide (ordre stable à égalité)
		var order := hp_order.duplicate()
		order.sort_custom(func(a: String, b: String) -> bool:
			return hp[a] > hp[b] if hp[a] != hp[b] else hp_order.find(a) < hp_order.find(b))
		for i in order.size():
			var id: String = order[i]
			var row: Dictionary = side_rows[id]
			var p: ClientPlayer = ctx.players.get(id)
			var l: Label = row["label"]
			l.text = "%s%s%s" % ["[KO] " if dead.has(id) else "", p.name if p else "?", " (toi)" if id == ctx.my_id else ""]
			var bar: ProgressBar = row["bar"]
			bar.value = hp[id] / max_hp
			side_box.move_child(l, i * 2)
			side_box.move_child(bar, i * 2 + 1)
		b_mats.visible = alive and building
		b_hint.visible = alive and building
		b_bar.visible = alive and not building
		if not alive:
			b_text.text = "Éliminé — tu regardes la fin de la bataille"
		elif building:
			b_text.text = "Budget : %d" % budget
			for i in 3:
				var chip: PanelContainer = mat_chips[i]
				chip.add_theme_stylebox_override("panel", UI.sbox(UI.YELLOW if MortarShared.MAT_KEYS[i] == mat else Color("#eeeeee"), 10, 10, 4))
		else:
			var special := ""
			if ammo != "normal":
				special = " · Munition : %s" % ("Méga-obus" if ammo == "mega" else "Fragmentation")
			b_text.text = "Maintiens le clic gauche (ou F) pour charger, relâche pour tirer" + special
			var reload := minf(1.0, (t - last_fire) / MortarShared.RELOAD)
			if charge_start >= 0.0:
				b_bar.value = power
				UI.set_bar_color(b_bar, UI.ACCENT)
			else:
				b_bar.value = reload
				UI.set_bar_color(b_bar, Color("#adb5bd") if reload < 1.0 else Color("#70e000"))


func on_exit() -> void:
	for e: Dictionary in fx:
		if is_instance_valid(e["node"]):
			e["node"].queue_free()
	fx.clear()
	for tube: Node in tubes:
		if is_instance_valid(tube):
			tube.queue_free()
	ctx.set_charging(false)
