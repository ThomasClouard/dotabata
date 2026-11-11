class_name MortarClient
extends ClientGame
## Abri & mortier — côté client : îles, blocs instanciés, visée, obus, explosions, caisses, zone, HUD.

const SHELL_COLOR := {"normal": 0x2b2140, "mega": 0xd00000, "cluster": 0xff9f1c, "sub": 0xff9f1c}
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


func _block_pos(b: Dictionary) -> Vector3:
	var c := MortarShared.block_center(b["plot"], b["x"], b["y"], b["z"], n)
	return Vector3(c[0], c[1], c[2])


func _remove_blocks(keys: Array) -> void:
	for key: String in keys:
		if not blocks.has(key):
			continue
		var b: Dictionary = blocks[key]
		blocks.erase(key)
		ctx.particles.burst(_block_pos(b), 8, [MortarShared.MATS[b["mat"]]["color"]], 5.0, 0.22, 0.8)
	_rebuild()


func _explosion(p: Vector3, r: float, kind: String) -> void:
	ctx.particles.burst(p, 70 if kind == "mega" else 34, [0xffd60a, 0xff9f1c, 0xff4d6d, 0xffffff], r * 4.5, 0.3, 0.7, 10.0)
	ctx.particles.burst(p, 14, [0x6c757d, 0x495057], r * 2.0, 0.45, 1.3, 2.0, 0.8)
	var d := p.distance_to(ctx.body.pos())
	ctx.sfx.boom(clampf(14.0 / (d + 4.0), 0.15, 1.0) * (1.3 if kind == "mega" else 1.0))
	if d < 14.0:
		ctx.shake((1.0 - d / 14.0) * (1.1 if kind == "mega" else 0.7))
	# éclair : sphère qui gonfle puis disparaît, et onde de choc au sol
	var fm := Gfx.flat(0xffe28a, {"opacity": 0.9})
	var flash := Gfx.mesh(Shapes.sphere(1.0, 20, 14), fm, p.x, p.y, p.z, ctx.world, false)
	flashes.append({"mesh": flash, "mat": fm, "life": 0.28, "max": 0.28, "r": r, "wave": false})
	var wm := Gfx.flat(0xffffff, {"opacity": 0.8})
	var wave := Gfx.mesh(Shapes.torus(1.0, 0.07, 40, 8), wm, p.x, maxf(0.15, p.y), p.z, ctx.world, false)
	flashes.append({"mesh": wave, "mat": wm, "life": 0.45, "max": 0.45, "r": r * 1.5, "wave": true})


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
		Gfx.mesh(Shapes.rbox(s + 0.3, 0.5, s + 0.3, 0.24), grass, 0, -0.25, 0, g)
		Gfx.mesh(Shapes.rbox(s, MortarShared.THICK - 0.4, s, 0.3), Gfx.mat(0xb08968, {"rough": 0.85}), 0, -0.4 - (MortarShared.THICK - 0.4) / 2.0, 0, g)
		var rock := Gfx.rock_under(s * 0.98, 6.0, s * 0.98, 0x8a5a3c, p * 7)
		rock.position.y = -MortarShared.THICK + 0.1
		g.add_child(rock)
		# cadre lumineux de la zone constructible, à la couleur du propriétaire
		var owner: ClientPlayer = ctx.players.get(owners.get(p, ""))
		var color: int = owner.color if owner else 0xffffff
		var frame := Gfx.mat(color, {"glow": 0.9})
		var half := MortarShared.GRID / 2.0 + 0.1
		for sgn in [-1.0, 1.0]:
			Gfx.mesh(Shapes.rbox(MortarShared.GRID + 0.4, 0.08, 0.14, 0.04), frame, 0, 0.04, sgn * half, g)
			Gfx.mesh(Shapes.rbox(0.14, 0.08, MortarShared.GRID + 0.4, 0.04), frame, sgn * half, 0.04, 0, g)
		# drapeau, buissons et cailloux sur le pourtour (hors de la zone constructible)
		Gfx.mesh(Shapes.cylinder(0.06, 0.06, 3.0, 8), Gfx.mat(0xffffff), 5.3, 1.5, 5.3, g)
		Gfx.mesh(Shapes.rbox(1.1, 0.7, 0.06, 0.03), Gfx.mat(color, {"rough": 0.5}), 4.7, 2.6, 5.3, g)
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
			if k % 3 == 0:
				Gfx.mesh(pebble, Gfx.mat(0xaab3bd, {"rough": 0.8}), x, 0.15, z, g).scale = Vector3(0.35, 0.25, 0.3)
			else:
				Gfx.mesh(bush, Gfx.mat(0x3fbf6f if k % 2 else 0x55d07f, {"rough": 0.8}), x, 0.25, z, g).scale = Vector3(0.5, 0.38, 0.45)
		if p % 2 == 0:
			var t := Gfx.tree(2.4)
			t.position = Vector3(-5.3, 0, 5.3)
			g.add_child(t)
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
		var bar := UI.bar(170, 10, Gfx.col(p.color))
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
		cols = MortarShared.colliders(n, blocks, my_plot)
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
			var radius := 0.24
			if kind == "mega":
				radius = 0.42
			elif kind == "sub":
				radius = 0.16
			var shell := Gfx.mesh(Shapes.sphere(radius, 18, 12), Gfx.mat(SHELL_COLOR[kind], {"rough": 0.2, "metal": 0.5}), 0, 0, 0, ctx.world)
			# mèche incandescente, bien visible de loin grâce au halo lumineux
			Gfx.mesh(Shapes.sphere(0.4, 8, 6), Gfx.mat(0xffb703, {"glow": 3.0}), 0, 1, 0, shell, false)
			shell.position = _v3(m["p"])
			shells[int(m["id"])] = {"mesh": shell, "p": m["p"], "v": m["v"], "at": m["at"], "kind": kind}
			if kind != "sub":
				ctx.sfx.fire()
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
				shells[id]["mesh"].queue_free()
				shells.erase(id)
			if m["t"] == "boom":
				_explosion(_v3(m["p"]), m["r"], m["kind"])
				_remove_blocks(m["removed"])
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
		if cell != null and inp.hit("Mouse2", "KeyR"):
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
			marker.position = Vector3(l[0] + sin(yaw) * reach, 0.12, l[2] + cos(yaw) * reach)
			marker.visible = true
			marker.rotation.y = t * 3.0
			if inp.up("Mouse0", "KeyF") or not inp.down("Mouse0", "KeyF"):
				ctx.send_game({"t": "fire", "yaw": yaw, "power": power})
				last_fire = t
				charge_start = -1.0
		ctx.set_charging(charge_start >= 0.0)

	# ----- obus, éclairs, caisses, zone -----
	for sh: Dictionary in shells.values():
		var p := MortarShared.shell_at(sh["p"], sh["v"], t - sh["at"])
		sh["mesh"].position = p
		if randf() < 0.6:
			ctx.particles.emit(p.x, p.y, p.z, 0, 0.5, 0, 0xdee2e6 if sh["kind"] == "normal" else SHELL_COLOR[sh["kind"]], 0.13, 0.5, -1.0)
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
	for tube: Node in tubes:
		if is_instance_valid(tube):
			tube.queue_free()
	ctx.set_charging(false)
