class_name ParkourClient
extends ClientGame
## Parcours délirant — côté client : décor du niveau, obstacles animés, réactions du joueur local, HUD.
## Portage de games/parkour/client.ts.

const PASTELS := [0xff8fab, 0xffc971, 0x7fd8f0, 0xa5e07a, 0xc9a8e8, 0xfde68a, 0x8fb8ff]
const CORNERS := [[-1.0, -1.0], [1.0, -1.0], [-1.0, 1.0], [1.0, 1.0]]

var ctx: Main
var level: Dictionary
var els: Array
var cps: Array = []
var end_at := 0.0
var kill_y := -20.0
var cp := -1
var finished := false
var respawn := Vector3(0, 1, 0)
var last_hit := 0.0
var fan_timer := 0.0
var hud_timer := 0.0
var lstate := Level.new_state()  # état de niveau tenu à jour par les messages du serveur (portes, dalles, boîtes…)
var crumbled: Dictionary = lstate["crumbled"]  # index → instant du déclenchement (même dictionnaire)
var init_msg: Dictionary = {}  # init de la manche (réglage jostle…)
var objs: Array = []
var arms := {}  # index → bras de marteau ou tige de piston
var blades: Array = []
var gates := {}  # index du checkpoint → matériau du portique
var arrows: Array = []  # { el, meshes, len, dir }
var finishers: Array = []
var marker: MeshInstance3D
var deco: Array = []
var deco_y: Array = []
var top: Label
var side: Label
var _frame_cols: Array = []
var props: ParkourProps  # éléments de la vague 1, arches, confettis, brouillard
var props2: ParkourProps2  # éléments de la vague 2 (sols spéciaux, propulseurs), joueurs suspendus
var props3: ParkourProps3  # éléments de la vague 3 (interactions, objets, pièces), HUD de l'objet
var finish_tops: Array = []  # [haut de l'arche d'arrivée (monde), largeur]
var best_mode := false  # mode « meilleur temps » : on refait le parcours autant qu'on veut
var run_start := 0.0  # début de l'essai en cours (horloge serveur)
var bests := {}  # id → meilleur temps (mode meilleur temps)
var ghosts := {}  # joueurs arrivés : ils ne bousculent plus et ne sont plus bousculés
var hint: Label
var _restart_sent := 0.0


func _put(e: Dictionary, o: Node3D) -> Node3D:
	o.position = Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
	o.rotation.y = e.get("yaw", 0.0)
	ctx.world.add_child(o)
	return o


func _build(e: Dictionary, i: int) -> Node3D:
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var sz: float = e["size"][2]
	var pos := Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
	var yaw: float = e.get("yaw", 0.0)
	match e["type"]:
		"platform":
			var color: int = Gfx.to_int(Color(e["color"])) if e.get("color") != null else PASTELS[i % PASTELS.size()]
			return _put(e, Gfx.slab(sx, sy, sz, color, {"seed": i}))
		"start":
			var g := _put(e, Gfx.slab(sx, sy, sz, 0x8ecbff, {"top": 0xffffff, "top_map": Tex.soft("#ffffff", "#cfe8ff"), "top_uv": Vector2(sx / 4.0, sz / 4.0), "seed": i}))
			# arche gonflable « DÉPART » sur le bord tourné vers le premier objectif
			var tgt: Variant = _next_target()
			if tgt != null:
				var dx: float = tgt["pos"][0] - pos.x
				var dz: float = tgt["pos"][2] - pos.z
				var lx := dx * cos(yaw) - dz * sin(yaw)
				var lz := dx * sin(yaw) + dz * cos(yaw)
				if absf(lz) >= absf(lx):
					props.inflatable_arch(g, minf(5.0, sx / 2.0 - 0.6), 0, sy / 2.0, signf(lz) * (sz / 2.0 - 0.7), 0.0, "DÉPART", ["#00b4d8", "#ffd60a"])
				else:
					props.inflatable_arch(g, minf(5.0, sz / 2.0 - 0.6), signf(lx) * (sx / 2.0 - 0.7), sy / 2.0, 0, PI / 2.0, "DÉPART", ["#00b4d8", "#ffd60a"])
			# fanions aux quatre coins (rien au milieu : la caméra est derrière les joueurs au départ)
			for c: Array in CORNERS:
				var x: float = c[0] * (sx / 2.0 - 0.35)
				var z: float = c[1] * (sz / 2.0 - 0.35)
				Gfx.mesh(Shapes.cylinder(0.06, 0.06, 2.4, 8), Gfx.mat(0xffffff), x, sy / 2.0 + 1.2, z, g)
				Gfx.mesh(Shapes.rbox(0.8, 0.5, 0.05, 0.02), Gfx.mat(0xff4d6d if c[0] * c[1] > 0.0 else 0xffd60a), x - c[0] * 0.42, sy / 2.0 + 2.1, z, g)
			return g
		"finish":
			var g := _put(e, Gfx.slab(sx, sy, sz, 0xffd60a, {"top": 0xffffff, "top_map": Tex.checker("#ffffff", "#2b2140"), "top_uv": Vector2(sx / 2.0, sz / 2.0), "seed": i}))
			# arche gonflable rayée + bannière
			var r := sx / 2.0 - 0.5
			props.inflatable_arch(g, r, 0, sy / 2.0, -sz / 2.0 + 0.8, 0.0, "ARRIVÉE", ["#ff4d6d", "#ffd60a"])
			finish_tops.append([g.to_global(Vector3(0, sy / 2.0 + r + 0.4, -sz / 2.0 + 0.8)), r * 2.0])
			for s in [-1.0, 1.0]:
				var b := Gfx.balloon(0xff4d6d if s < 0.0 else 0x00b4d8)
				b.position = Vector3(s * (r + 0.3), sy / 2.0 + r * 0.9 + 1.6, -sz / 2.0 + 0.8)
				g.add_child(b)
			return g
		"checkpoint":
			var g := _put(e, Gfx.slab(sx, sy, sz, 0x52d681, {"top": 0xffffff, "top_map": Tex.soft("#7be495", "#a2f0b5"), "top_uv": Vector2(sx / 3.0, sz / 3.0), "seed": i}))
			# portique en anneau qui s'allume à la couleur du joueur quand il est validé
			var ring_mat := Gfx.mat(0xdde3ea, {"rough": 0.3})
			Gfx.mesh(Shapes.torus_arc(minf(sx, 5.0) / 2.0 - 0.3, 0.2, 12, 36, PI), ring_mat, 0, sy / 2.0, 0, g)
			gates[i] = ring_mat
			return g
		"ice":
			var m := Gfx.mesh(Shapes.rbox(sx, sy, sz, 0.2), Gfx.mat(0xc9f2ff, {"rough": 0.04, "metal": 0.1, "opacity": 0.86}), 0, 0, 0, null, false)
			_put(e, m)
			Gfx.mesh(Shapes.rbox(sx * 0.9, sy * 0.5, sz * 0.9, 0.15), Gfx.mat(0xffffff, {"rough": 0.1, "opacity": 0.55}), 0, 0, 0, m, false)
			return m
		"moving":
			var g := _put(e, Gfx.slab(sx, sy, sz, 0x9d4edd, {"under": false}))
			# dessous lumineux : on voit de loin que la plateforme bouge
			Gfx.mesh(Shapes.rbox(sx * 0.7, 0.14, sz * 0.7, 0.07), Gfx.mat(0x5ef2ff, {"glow": 2.2}), 0, -sy / 2.0 - 0.05, 0, g)
			var bulb := Gfx.mat(0xffd60a, {"glow": 1.5})
			for c: Array in CORNERS:
				Gfx.mesh(Shapes.sphere(0.16, 10, 8), bulb, c[0] * (sx / 2.0 - 0.3), sy / 2.0 - 0.02, c[1] * (sz / 2.0 - 0.3), g)
			return g
		"trampoline":
			var g := _put(e, Node3D.new())
			var r := minf(sx, sz) / 2.0
			Gfx.mesh(Shapes.rbox(sx, sy, sz, 0.25), Gfx.mat(0x3a56e0), 0, 0, 0, g)
			Gfx.mesh(Shapes.cylinder(r * 0.82, r * 0.82, 0.06, 32), Gfx.mat(0xffffff, {"map": Tex.target("#ffd60a", "#ff4d6d")}), 0, sy / 2.0 + 0.02, 0, g)
			Gfx.mesh(Shapes.torus(r * 0.86, 0.13, 32, 10), Gfx.mat(0xffffff, {"rough": 0.25}), 0, sy / 2.0 + 0.04, 0, g)
			return g
		"conveyor":
			var g := _put(e, Node3D.new())
			Gfx.mesh(Shapes.rbox(sx, sy, sz, 0.2), Gfx.mat(0x3d4450, {"rough": 0.6}), 0, 0, 0, g)
			Gfx.mesh(Shapes.rbox(sx - 0.5, 0.08, sz - 0.5, 0.04), Gfx.mat(0x23272e, {"rough": 0.85}), 0, sy / 2.0 - 0.02, 0, g)
			var n := sqrt(e["dir"][0] * e["dir"][0] + e["dir"][1] * e["dir"][1])
			if n == 0.0:
				n = 1.0
			var dir := Vector2(e["dir"][0] / n, e["dir"][1] / n)
			# longueur du tapis le long de la direction d'entraînement (en tenant compte de son orientation)
			var lx := dir.x * cos(yaw) - dir.y * sin(yaw)
			var lz := dir.x * sin(yaw) + dir.y * cos(yaw)
			var length := minf(sx / absf(lx) if absf(lx) > 1e-3 else INF, sz / absf(lz) if absf(lz) > 1e-3 else INF)
			# bordures de signalisation le long du tapis
			var along_x := absf(lx) > absf(lz)
			for s in [-1.0, 1.0]:
				var rail_mat := Gfx.mat(0xffffff, {"map": Tex.stripes("#ffd60a", "#2b2140"), "uv": Vector2(sx if along_x else 1.0, 1.0 if along_x else sz)})
				Gfx.mesh(Shapes.rbox(sx if along_x else 0.22, 0.16, 0.22 if along_x else sz, 0.07), rail_mat, 0.0 if along_x else s * (sx / 2.0 - 0.13), sy / 2.0 + 0.05, s * (sz / 2.0 - 0.13) if along_x else 0.0, g)
			var arrow_mesh := _arrow_mesh()
			var arrow_mat := Gfx.flat(0xffe14a, {"double": true})
			var meshes := []
			for k in maxi(1, floori(length / 1.5)):
				var a := Gfx.mesh(arrow_mesh, arrow_mat, 0, 0, 0, ctx.world, false)
				a.rotation.y = atan2(dir.x, dir.y)
				meshes.append(a)
			arrows.append({"el": e, "meshes": meshes, "len": length, "dir": dir})
			return g
		"crumble":
			return _put(e, Gfx.slab(sx, sy, sz, 0xe09f3e, {"top": 0xffffff, "top_map": Tex.cracks("#f0b458"), "under": false}))
		"spinner":
			var g := _put(e, Node3D.new())
			# barre rembourrée : le long de x (taille de la barre), section = hauteur / profondeur
			var r := minf(sy, sz) / 2.0
			var bar := Gfx.mesh(Shapes.capsule(r, maxf(0.1, sx - 2.0 * r)), Gfx.mat(0xffffff, {"map": Tex.stripes("#ff4d6d", "#ffffff"), "uv": Vector2(1, maxf(2.0, roundf(sx)))}), 0, 0, 0, g)
			bar.rotation.z = PI / 2.0
			Gfx.mesh(Shapes.sphere(r * 1.5, 16, 12), Gfx.mat(0xffd60a, {"metal": 0.3, "rough": 0.25}), 0, 0, 0, g)
			Gfx.mesh(Shapes.cylinder(0.16, 0.26, 1.4, 12), Gfx.mat(0x5c6470, {"metal": 0.6, "rough": 0.3}), pos.x, pos.y - 0.7, pos.z, ctx.world)
			return g
		"hammer":
			var g := _put(e, Node3D.new())
			# maillet : cylindre couché dans l'axe du balancement, avec deux faces de frappe
			var on_x: bool = e.get("axis", "x") == "x"
			var r := minf(sx, minf(sy, sz)) / 2.0
			var rot := Vector3(0.0 if on_x else PI / 2.0, 0, PI / 2.0 if on_x else 0.0)
			var head := Gfx.mesh(Shapes.cylinder(r, r, sx if on_x else sz, 24), Gfx.mat(0xe5383b, {"rough": 0.3}), 0, 0, 0, g)
			head.rotation = rot
			for s in [-1.0, 1.0]:
				var cap := Gfx.mesh(Shapes.cylinder(r * 1.08, r * 1.08, 0.22, 24), Gfx.mat(0xffd60a, {"rough": 0.3}), s * (sx / 2.0 - 0.1) if on_x else 0.0, 0, 0.0 if on_x else s * (sz / 2.0 - 0.1), g)
				cap.rotation = rot
			arms[i] = Gfx.mesh(Shapes.cylinder(0.13, 0.13, 1.0, 10), Gfx.mat(0x5c6470, {"metal": 0.6, "rough": 0.3}), 0, 0, 0, ctx.world)
			# potence : une poutre au-dessus du pivot
			Gfx.mesh(Shapes.rbox(0.5 if on_x else 3.4, 0.4, 3.4 if on_x else 0.5, 0.15), Gfx.mat(0x3d4450, {"metal": 0.4, "rough": 0.4}), pos.x, pos.y + 0.1, pos.z, ctx.world)
			Gfx.mesh(Shapes.sphere(0.34, 14, 10), Gfx.mat(0xffd60a, {"metal": 0.3, "rough": 0.25}), pos.x, pos.y, pos.z, ctx.world)
			return g
		"cannon":
			var g := _put(e, Node3D.new())
			Gfx.mesh(Shapes.rbox(sx, sy, sz, 0.25), Gfx.mat(0xf72585, {"rough": 0.3}), 0, 0, 0, g)
			var n := sqrt(e["dir"][0] * e["dir"][0] + e["dir"][1] * e["dir"][1])
			if n == 0.0:
				n = 1.0
			# plaque de frappe du côté où le piston pousse
			var lx: float = (e["dir"][0] / n) * cos(yaw) - (e["dir"][1] / n) * sin(yaw)
			var lz: float = (e["dir"][0] / n) * sin(yaw) + (e["dir"][1] / n) * cos(yaw)
			var along_x := absf(lx) > absf(lz)
			var sgn := signf(lx if along_x else lz)
			if sgn == 0.0:
				sgn = 1.0
			Gfx.mesh(Shapes.rbox(0.2 if along_x else sx * 1.04, sy * 1.04, sz * 1.04 if along_x else 0.2, 0.09), Gfx.mat(0xffffff, {"map": Tex.stripes("#ffd60a", "#2b2140"), "uv": Vector2(2, 2)}), (sgn * sx) / 2.0 if along_x else 0.0, 0, 0.0 if along_x else (sgn * sz) / 2.0, g)
			# tige du piston, étirée entre la position de repos et la tête
			var rod := Gfx.mesh(Shapes.cylinder(0.2, 0.2, 1.0, 12), Gfx.mat(0xbfc7d1, {"metal": 0.8, "rough": 0.2}), 0, 0, 0, ctx.world)
			rod.visible = false
			arms[i] = rod
			return g
		"fan":
			var g := _put(e, Node3D.new())
			var r := minf(sx, sz) / 2.0
			var by := -sy / 2.0
			Gfx.mesh(Shapes.cylinder(r, r, sy, 24, false), Gfx.flat(0xffffff, {"opacity": 0.07, "double": true}), 0, 0, 0, g, false)
			Gfx.mesh(Shapes.cylinder(r, r * 1.12, 0.35, 28), Gfx.mat(0x3d4450, {"metal": 0.5, "rough": 0.35}), 0, by + 0.17, 0, g)
			Gfx.mesh(Shapes.torus(r * 0.95, 0.09, 36, 10), Gfx.mat(0x5ef2ff, {"glow": 2.0}), 0, by + 0.38, 0, g)
			var hub := Node3D.new()
			hub.position.y = by + 0.5
			g.add_child(hub)
			Gfx.mesh(Shapes.sphere(0.28, 14, 10), Gfx.mat(0xffd60a), 0, 0, 0, hub)
			var blade_mat := Gfx.mat(0xffd60a, {"rough": 0.3})
			for k in 4:
				var blade := Gfx.mesh(Shapes.rbox(r * 0.8, 0.05, 0.5, 0.02), blade_mat, cos(k * PI / 2.0) * r * 0.45, 0, sin(k * PI / 2.0) * r * 0.45, hub)
				blade.basis = Basis.from_euler(Vector3(0.35, -k * PI / 2.0, 0), EULER_ORDER_XYZ)
			blades.append(hub)
			return g
	var o := props.build(e, i)  # types de la vague 1
	if o == null:
		o = props2.build(e, i)  # types de la vague 2
	return o if o != null else props3.build(e, i)  # types de la vague 3


## Flèche plate posée sur le tapis, pointant vers +Z.
static func _arrow_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.45, 0, -0.3), Vector3(0.45, 0, -0.3), Vector3(0, 0, 0.35)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _set_respawn() -> void:
	var idx: int = Level.find_type(level, "start") if cp < 0 else int(cps[cp])
	if finished and not best_mode:
		idx = Level.find_type(level, "finish")  # arrivé : on reste sur l'arrivée, même après une chute
	var e: Dictionary = els[idx]
	respawn = Vector3(e["pos"][0] + (randf() - 0.5) * 1.2, Level.top_of(e) + 0.2, e["pos"][2] + (randf() - 0.5) * 1.2)


func _next_target() -> Variant:
	if finished:
		return null
	var i: int = int(cps[cp + 1]) if cp + 1 < cps.size() else Level.find_type(level, "finish")
	return els[i] if i >= 0 else null


func on_enter(c: Main, init: Variant) -> void:
	ctx = c
	level = init["level"]
	els = level["elements"]
	cps = init["cps"]
	end_at = init["endAt"]
	kill_y = Level.kill_y(level)
	ctx.set_sky(Gfx.to_int(Color(level["sky"])) if level.get("sky") != null else 0x8fd3ff)
	props = ParkourProps.new(ctx, level)
	props2 = ParkourProps2.new(ctx, level)
	props3 = ParkourProps3.new(ctx, level, lstate)
	init_msg = init
	best_mode = init.get("mode", "first") == "best"
	run_start = ctx.start_at
	for i in els.size():
		objs.append(_build(els[i], i))
	marker = Gfx.mesh(Shapes.cylinder(0.55, 0.0, 1.1, 20), Gfx.mat(0xffd60a, {"glow": 1.2}), 0, 0, 0, ctx.world, false)
	# mer de « slime » sous le parcours, juste au-dessus de l'altitude où l'on réapparaît
	ctx.set_sea(kill_y + 3.0, 0xff5fb0)
	# ballons décoratifs le long du parcours
	for i in els.size():
		var e: Dictionary = els[i]
		if i % 3 != 1 or e["type"] in ["fan", "hammer", "hazard", "ferris", "wreckingball", "boulder", "launcher", "teleport", "zipline", "lowgrav", "wind", "bubble"] or e["type"] in Level.VISUAL_ONLY:
			continue
		var b := Gfx.balloon(PASTELS[(i * 5) % PASTELS.size()])
		b.position = Vector3(e["pos"][0] + (1.0 if i % 2 else -1.0) * (e["size"][0] / 2.0 + 3.0 + (i % 4)), e["pos"][1] + 2.0 + (i % 5), e["pos"][2] + ((i * 7) % 5) - 2.0)
		ctx.world.add_child(b)
		deco.append(b)
		deco_y.append(b.position.y)
	_set_respawn()
	# caméra tournée vers le premier objectif
	var t: Variant = _next_target()
	if t != null:
		ctx.cam_yaw = atan2(t["pos"][0] - ctx.body.px, t["pos"][2] - ctx.body.pz)
	top = UI.label("", 20)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var top_box := VBoxContainer.new()
	top_box.add_theme_constant_override("separation", 0)
	top_box.add_child(top)
	hint = UI.label("", 12, UI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_box.add_child(hint)
	ctx.ui.hud_card("top").add_child(top_box)
	side = UI.label("", 14)
	ctx.ui.hud_card("side").add_child(side)
	props3.build_hud()
	var title: String = level.get("title", "")
	ctx.toast(title if title != "" else str(level["name"]), 2.5)


func on_exit() -> void:
	if props:
		props.restore()
	for p: ClientPlayer in ctx.players.values():
		p.chr.hanging = false
	if props3:
		props3.clear()


func colliders(t: float) -> Array:
	_frame_cols = Level.build_colliders(level, t, lstate)
	return _frame_cols


func is_ghost(id: String) -> bool:
	return ghosts.has(id)


## Demande au serveur de recommencer (« start » : au départ, « cp » : au dernier checkpoint) ; il répond par « restart ».
func _ask_restart(to: String) -> void:
	var now := ctx.now()
	if now < ctx.start_at or now - _restart_sent < 0.4 or (finished and not best_mode):
		return
	_restart_sent = now
	ctx.send_game({"t": "restart", "to": to})


func _reset_gates() -> void:
	for mat: StandardMaterial3D in gates.values():
		mat.albedo_color = Gfx.col(0xdde3ea)
		mat.emission_enabled = false


## Bousculade entre joueurs selon le réglage de la manche (désactivée : on se traverse).
func jostle(b: Phys.Body, op: Vector3, ov: Vector3) -> void:
	if ParkourShared.parkour_jostle(init_msg, b, op.x, op.y, op.z, ov.x, ov.z):
		ctx.sfx.hit()
		ctx.shake(0.3)


func pose_flags(b: Phys.Body) -> int:
	return Protocol.pose_flags(b)


func pre_step(b: Phys.Body, dt: float) -> void:
	var from := Vector3(b.px, b.py, b.pz)
	var ev := ParkourShared.pre_step(level, b, dt, ctx.now())  # horloge serveur : rafales
	props2.on_pre(ev, b, from)


func post_step(b: Phys.Body, contacts: Array, _dt: float) -> void:
	var ev := ParkourShared.post_step(b, contacts)
	var now := ctx.now()
	if ev["knocked"]:
		ctx.sfx.hit()
		ctx.shake(0.5)
		ctx.particles.burst(Vector3(b.px, b.py + 0.8, b.pz), 12, [0xffffff, 0xffd60a], 6.0, 0.14, 0.5)
		if now - last_hit > 0.8:
			last_hit = now
			ctx.send_game({"t": "hit"})
	if ev["bounced"]:
		ctx.sfx.boing()
	props2.on_contacts(contacts, ev)
	for i: int in ev["crumble"]:
		var e: Dictionary = els[i]
		if e["type"] != "crumble":
			continue
		if crumbled.has(i) and now < crumbled[i] + e.get("delay", 0.5) + e.get("respawn", 4.0):
			continue
		crumbled[i] = now  # effet immédiat chez soi ; le serveur prévient les autres
		ctx.send_game({"t": "crumble", "i": i})
		ctx.sfx.crumble()
	# lave / eau / acide : traité exactement comme une chute (retour au checkpoint), avec un effet selon le style
	if ev["killed"]:
		_death_fx(int(ev["hazard"]), Vector3(b.px, b.py, b.pz))
		ctx.send_game({"t": "killed", "i": int(ev["hazard"])})  # le serveur rejoue l'effet chez les autres
	if ev["killed"] or b.py < kill_y:
		b.set_pos(respawn.x, respawn.y, respawn.z)
		b.vx = 0.0
		b.vy = 0.0
		b.vz = 0.0
		b.tumble = 0.0
		Phys.clear_motion_state(b)  # ni tyrolienne, ni vol, ni élan après une chute
		ctx.sfx.hurt()


func _death_fx(h: int, p: Vector3, flash_screen := true) -> void:
	var style: String = els[h].get("style", "lava") if h >= 0 and h < els.size() else "lava"
	var cs: Array = ParkourProps.HAZARD_FX.get(style, ParkourProps.HAZARD_FX["lava"])
	ctx.particles.burst(p + Vector3(0, 0.4, 0), 36, cs, 8.0, 0.2, 1.1, 12.0, 1.2)
	if flash_screen:
		ctx.shake(0.45)
	match style:
		"lava":
			ctx.sfx.boom(0.35)
		"water":
			ctx.sfx.land()
		_:
			ctx.sfx.crumble()
	if not flash_screen:
		return
	# voile coloré bref sur tout l'écran
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(Gfx.col(cs[0]), 0.45)
	ctx.ui.hud.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.6)
	tw.tween_callback(flash.queue_free)


func on_message(m: Dictionary) -> void:
	ParkourShared.apply_level_msg(lstate, m, ctx.my_id)  # portes, leviers, dalles, boîtes, pièces, bananes, friables
	ParkourShared.apply_effect_msg(ctx.body, m, ctx.my_id, ctx.now())  # super saut, bouclier
	props3.on_message(m)
	match m["t"]:
		"killed":
			if m["id"] != ctx.my_id:
				var p: Array = m["p"]
				_death_fx(int(m["i"]), Vector3(p[0], p[1], p[2]), false)
		"cp":
			var k := int(m["k"])
			if m["id"] == ctx.my_id and k > cp:
				cp = k
				_set_respawn()
				ctx.sfx.checkpoint()
				ctx.toast("Checkpoint %d/%d !" % [k + 1, cps.size()])
				var gate: StandardMaterial3D = gates.get(int(cps[k]))
				if gate:
					var who := ctx.me()
					gate.albedo_color = Gfx.col(who.color if who else 0xffd60a)
					gate.emission_enabled = true
					gate.emission = gate.albedo_color
					gate.emission_energy_multiplier = 1.4
		"restart":
			ghosts.erase(m["id"])
			if m["id"] == ctx.my_id:
				finished = false
				cp = int(m["cp"])
				run_start = float(m["runStart"])
				if cp < 0:
					_reset_gates()
				_set_respawn()
				ctx.teleport(respawn.x, respawn.y, respawn.z)
				ctx.sfx.checkpoint()
		"finish":
			ghosts[m["id"]] = true
			if best_mode:
				bests[m["id"]] = float(m["best"])
			else:
				finishers.append({"id": m["id"], "time": m["time"]})
			# confettis au-dessus de l'arche d'arrivée la plus proche de l'arrivant
			var who: ClientPlayer = ctx.players.get(m["id"])
			var best: Variant = null
			for f: Array in finish_tops:
				if best == null or (who != null and who.pos.distance_squared_to(f[0]) < who.pos.distance_squared_to(best[0])):
					best = f
			if best != null:
				props.confetti(best[0], best[1], 3.0 if m["id"] == ctx.my_id else 1.6)
			if m["id"] == ctx.my_id:
				finished = true
				_set_respawn()
				ctx.sfx.win()
				if best_mode:
					var txt := ParkourShared.format_time(m["time"])
					ctx.toast("Record : %s !" % txt if m["record"] else "%s  (record %s)" % [txt, ParkourShared.format_time(m["best"])], 3.0)
				else:
					var place := int(m["place"])
					ctx.toast("Premier !" if place == 1 else "Arrivé %de !" % place, 3.0)
				ctx.particles.burst(Vector3(ctx.body.px, ctx.body.py + 1.0, ctx.body.pz), 60, [0xff4d6d, 0xffd60a, 0x70e000, 0x00b4d8], 9.0, 0.18, 1.6, 8.0)
		"hurry":
			end_at = m["endAt"]
			if not finished:
				ctx.toast("Dépêche-toi !", 2.0)


func on_frame(dt: float) -> void:
	var t := ctx.now()
	if ctx.input.hit("KeyR", "PadCp"):
		_ask_restart("cp")
	elif ctx.input.hit("KeyT", "PadStart"):
		_ask_restart("start")
	var by_id := {}
	for c: Phys.Col in _frame_cols:
		by_id[c.id] = c
	for i in els.size():
		var o: Node3D = objs[i]
		if o == null:
			continue
		var e: Dictionary = els[i]
		var type: String = e["type"]
		var c: Phys.Col = by_id.get(i)
		if type == "crumble":
			# tremble avant de tomber, puis disparaît jusqu'à sa réapparition
			o.visible = c != null
			var shaking: bool = c != null and crumbled.has(i) and t > crumbled[i] and t < crumbled[i] + e.get("delay", 0.5)
			o.position = Vector3(e["pos"][0] + ((randf() - 0.5) * 0.12 if shaking else 0.0), e["pos"][1] - (0.05 if shaking else 0.0), e["pos"][2] + ((randf() - 0.5) * 0.12 if shaking else 0.0))
			continue
		if c == null or not (type == "moving" or type == "spinner" or type == "hammer" or type == "cannon"):
			continue
		o.position = Vector3(c.cx, c.cy, c.cz)
		o.rotation = Vector3(0, c.yaw, 0)
		var arm: MeshInstance3D = arms.get(i)
		if arm:
			var a := Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
			var d := o.position - a
			var length := d.length()
			arm.visible = length > 0.05
			if arm.visible:
				Gfx.stretch(arm, a, o.position)
				if type == "hammer":
					o.quaternion = Quaternion(Vector3.UP, d / length)  # la tête suit l'inclinaison du bras
	for a: Dictionary in arrows:
		var e: Dictionary = a["el"]
		var y := Level.top_of(e) + 0.03
		var meshes: Array = a["meshes"]
		var n := meshes.size()
		var spacing: float = a["len"] / n
		var dir: Vector2 = a["dir"]
		for k in n:
			var u: float = fposmod(k + (t * e.get("speed", 4.0)) / spacing, float(n)) * spacing - a["len"] / 2.0 + spacing / 2.0
			meshes[k].position = Vector3(e["pos"][0] + dir.x * u, y, e["pos"][2] + dir.y * u)
	for b: Node3D in blades:
		b.rotation.y += dt * 14.0
	props.update(t, dt)
	props2.update(t, dt)
	props3.update(t, dt)
	for i in deco.size():
		deco[i].position.y = deco_y[i] + sin(t * 0.8 + i) * 0.35
	fan_timer -= dt
	if fan_timer < 0.0:
		fan_timer = 0.06
		for e: Dictionary in els:
			if e["type"] != "fan":
				continue
			var f: Array = e.get("force", [0.0, 42.0, 0.0])
			ctx.particles.emit(e["pos"][0] + (randf() - 0.5) * e["size"][0] * 0.8, e["pos"][1] - e["size"][1] / 2.0 + 0.4, e["pos"][2] + (randf() - 0.5) * e["size"][2] * 0.8,
				f[0] * 0.15, f[1] * 0.2, f[2] * 0.15, 0xffffff, 0.09, 0.9, 0.0)
	var tgt: Variant = _next_target()
	marker.visible = tgt != null
	if tgt != null:
		marker.position = Vector3(tgt["pos"][0], Level.top_of(tgt) + 3.2 + sin(t * 4.0) * 0.3, tgt["pos"][2])
		marker.rotation.y = t * 2.0
	hud_timer -= dt
	if hud_timer < 0.0:
		hud_timer = 0.1
		var left := maxf(0.0, end_at - maxf(t, ctx.start_at))
		var state := "Fonce vers l'arrivée !"
		if finished:
			state = "Arrivé !"
		elif not cps.is_empty():
			state = "Checkpoint %d/%d" % [cp + 1, cps.size()]
		var keys := ["R", "T"]
		if Pad.device() >= 0:
			keys = [Pad.label(Pad.bindings.get("checkpoint", JOY_BUTTON_LEFT_SHOULDER)), Pad.label(Pad.bindings.get("depart", JOY_BUTTON_BACK))]
		var lines := PackedStringArray()
		if best_mode:
			var run := 0.0 if finished else maxf(0.0, t - maxf(run_start, ctx.start_at))
			top.text = "%s  ·  Essai %s  ·  %s" % [ParkourShared.format_time(left), ParkourShared.format_time(run), state]
			hint.text = "%s : dernier checkpoint  ·  %s : recommencer au départ (nouvel essai)" % keys
			lines.append("MEILLEURS TEMPS")
			var ids := bests.keys()
			ids.sort_custom(func(a: String, b: String) -> bool: return bests[a] < bests[b])
			for i in ids.size():
				var p: ClientPlayer = ctx.players.get(ids[i])
				lines.append("%d. %s — %s" % [i + 1, p.name if p else "?", ParkourShared.format_time(bests[ids[i]])])
			if ids.is_empty():
				lines.append("personne pour l'instant")
		else:
			top.text = "%s  ·  %s" % [ParkourShared.format_time(left), state]
			hint.text = "" if finished else "%s : dernier checkpoint  ·  %s : recommencer au départ" % keys
			lines.append("ARRIVÉES")
			for i in finishers.size():
				var p: ClientPlayer = ctx.players.get(finishers[i]["id"])
				lines.append("%d. %s — %s" % [i + 1, p.name if p else "?", ParkourShared.format_time(finishers[i]["time"])])
			if finishers.is_empty():
				lines.append("personne pour l'instant")
		side.text = "\n".join(lines)
