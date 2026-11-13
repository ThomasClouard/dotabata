class_name SpaceClient
extends ClientGame
## Saut cosmique — côté client : marche sur une planète ronde, visée (cap, élévation, puissance), décollage commun,
## vol avec rétro-fusées, atterrissage. Le moteur suppose que le haut est l'axe Y : ici le jeu reprend la main sur la
## physique (post_step), la caméra et l'orientation des personnages (on_frame).

const DOTS := 12  # pointillés de la trajectoire, qui défilent doucement
const CAM_DIST := 7.0
const FLY_CAM := 9.0
const FOV := 58.0
const ZOOM_FOV := 16.0  # visée précise : longue-vue
const ZOOM_SENS := 0.22  # et souris ralentie
## Point visé : à cette distance sur l'axe du tir. Avec ou sans zoom, la caméra regarde exactement ce point : la mire
## reste sur la même cible quand on zoome ou dézoome.
const AIM_DIST := 80.0
const LAND_CAM := 1.4  # atterrissage : durée du passage de la caméra de vol à la caméra au sol (s)
const TURN_RATE := 9.0  # vitesse à laquelle les personnages pivotent vers leur orientation (vol ↔ debout)

var ctx: Main
var planets: Array = []
var aim_end := 0.0
var flight_end := 0.0
var gravity := true
var bump := true
var fuel_max := 1.5
var fuel := 1.5

var status := "aim"  # aim, fly, landed, lost
var status_of := {}  # id → {s: fly/landed/lost, planet}
var burn_of := {}  # id → bool (flammes des autres joueurs)
var fwd := Vector3.FORWARD  # cap au sol (tangent)
var elev := deg_to_rad(40.0)
var _want_launch := false
var launch_at := {}  # id → instant du décollage (flammes)
var burning := false
var f_up := Vector3.UP  # repère de vol, figé au décollage
var f_fwd := Vector3.FORWARD
var fl_yaw := 0.0
var fl_pitch := 0.0
var _last_cam_yaw := 0.0
var _cur_p := Vector3.ZERO
var _cur_v := Vector3.ZERO
var _pend_v := Vector3.ZERO
var _pend_p := Vector3.ZERO
var _bump_cd := 0.0
var _hud_timer := 0.0
var _cam_pos := Vector3.ZERO
var _cam_init := false
var _restore := {}
var _armed := false
var _burn_sent := false
var thrust := Vector3.ZERO  # rétro-fusées : direction de la poussée (monde), zéro si éteintes
var _thrust_sent := Vector3.ZERO
var _thrust_at := 0.0
var thrust_of := {}  # id → direction de poussée des autres joueurs
var launch_up := {}  # id → « haut » au décollage (le dos du personnage en vol)
var _rot := {}  # id → orientation affichée (lissée)
var _cam_look := Vector3.ZERO
var _cam_up := Vector3.UP
var _land_t := -10.0
var _land_from := {}  # caméra au moment du contact : {pos, look, up}

var gear := {}  # id → {flames: [MeshInstance3D], root: [Node3D]}
var labels: Array = []  # [Label3D, index de planète]
var zoom := 0.0  # 0 : caméra normale, 1 : visée précise (clic droit / LT)
var reticle: Control
var _cross: Control
var dots: MultiMeshInstance3D
var dot_mat: StandardMaterial3D

var top: Label
var hint: Label
var side: Label
var b_text: Label
var b_bar: ProgressBar
var b_card: PanelContainer


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _center(i: int) -> Vector3:
	return _v3(planets[i]["c"])


func on_enter(c: Main, p_init: Variant) -> void:
	ctx = c
	var init: Dictionary = p_init
	planets = init["planets"]
	aim_end = init["aimEnd"]
	flight_end = init["flightEnd"]
	gravity = init["gravity"]
	bump = init["bump"]
	fuel_max = init["fuel"]
	fuel = fuel_max
	_last_cam_yaw = ctx.cam_yaw
	# cap de départ : vers l'« équateur », loin du pôle où tout le monde apparaît
	# cap de départ : face à la planète la plus proche
	var up := ctx.body.pos().normalized()
	var to := _v3(planets[1]["c"]) - ctx.body.pos()
	var hf := to - up * to.dot(up)
	fwd = hf.normalized() if hf.length() > 0.05 else SpaceShared.tangent_frame(up)[0]
	elev = clampf(atan2(to.dot(up), hf.length()) + 0.2, SpaceShared.ELEV_MIN, SpaceShared.ELEV_MAX)
	_cur_p = ctx.body.pos()
	_space_env(true)
	_build_world()
	for id: String in ctx.players:
		_add_gear(id)
	_build_hud()


# ---------- décor ----------

func _space_env(on: bool) -> void:
	var e := ctx.env.env
	if on:
		_restore = {"bg": e.background_mode, "amb": e.ambient_light_source, "amb_c": e.ambient_light_color, "amb_e": e.ambient_light_energy,
			"fog": e.fog_enabled, "clouds": ctx.env.clouds.visible}
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color("#04050d")
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color("#8a97c8")
		e.ambient_light_energy = 0.55
		e.fog_enabled = false
		ctx.env.clouds.visible = false
		_restore["dof"] = ctx.env._cam_attr.dof_blur_far_enabled
		ctx.env._cam_attr.dof_blur_far_enabled = false  # les planètes lointaines doivent rester nettes
	elif not _restore.is_empty():
		e.background_mode = _restore["bg"]
		e.ambient_light_source = _restore["amb"]
		e.ambient_light_color = _restore["amb_c"]
		e.ambient_light_energy = _restore["amb_e"]
		e.fog_enabled = _restore["fog"]
		ctx.env.clouds.visible = _restore["clouds"]
		ctx.env._cam_attr.dof_blur_far_enabled = _restore["dof"]


func _build_world() -> void:
	# étoiles : un seul MultiMesh, loin derrière les planètes
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Shapes.sphere(1.0, 6, 4)
	mm.instance_count = 900
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in mm.instance_count:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var s := rng.randf_range(0.5, 1.7)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), d * rng.randf_range(620.0, 760.0)))
		mm.set_instance_color(i, Color(1, 1, 1).lerp(Color("#ffd8a8") if rng.randf() < 0.5 else Color("#a5d8ff"), rng.randf() * 0.6))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	var sm := Gfx.flat(0xffffff)
	sm.vertex_color_use_as_albedo = true
	sm.disable_fog = true
	stars.material_override = sm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.custom_aabb = AABB(Vector3(-800, -800, -800), Vector3(1600, 1600, 1600))
	ctx.world.add_child(stars)

	for i in planets.size():
		var pl: Dictionary = planets[i]
		var c := _center(i)
		var r: float = pl["r"]
		var col: int = pl["color"]
		var g := Node3D.new()
		g.position = c
		ctx.world.add_child(g)
		var hex := "#" + Gfx.col(col).to_html(false)
		var light := "#" + Gfx.col(Gfx.shade(col, 1.25)).to_html(false)
		if i == 0:
			Gfx.mesh(Shapes.sphere(r, 64, 40), Gfx.mat(0xffffff, {"map": Tex.soft("#6fcf6a", "#86dd78"), "uv": Vector2(6, 3), "rough": 0.8}), 0, 0, 0, g)
			_decorate_home(g, r)
		else:
			var map := Tex.stripes(hex, light) if i % 2 == 0 else Tex.soft(hex, light)
			Gfx.mesh(Shapes.sphere(r, 72, 44), Gfx.mat(0xffffff, {"map": map, "uv": Vector2(3, 2), "rough": 0.7}), 0, 0, 0, g)
			if pl["ring"]:
				var ring := Gfx.mesh(Shapes.ring(r * 1.35, r * 1.9, 64), Gfx.mat(Gfx.shade(col, 1.4), {"opacity": 0.75, "double": true}), 0, 0, 0, g, false)
				ring.rotation = Vector3(0.45 + i * 0.3, i * 1.1, 0.2)
			var lbl := Gfx.label3d("%s\n+%d" % [pl["name"], pl["pts"]], 1.0, Color.WHITE, Color(0, 0, 0, 0.6))
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.fixed_size = true
			lbl.pixel_size = 0.00045
			ctx.world.add_child(lbl)  # placé à chaque image, entre la planète et la caméra
			labels.append([lbl, i])
			# un petit drapeau planté au sommet, pour le plaisir
			Gfx.mesh(Shapes.cylinder(0.05, 0.05, 2.2, 6), Gfx.mat(0xffffff), 0, r + 1.0, 0, g)
			Gfx.mesh(Shapes.rbox(0.9, 0.55, 0.05, 0.02), Gfx.mat(Gfx.shade(col, 0.7)), 0.45, r + 1.8, 0, g)

	dot_mat = Gfx.flat(0xffe066, {"opacity": 0.9})
	var dm := MultiMesh.new()
	dm.transform_format = MultiMesh.TRANSFORM_3D
	dm.mesh = Shapes.sphere(0.13, 8, 6)
	dm.instance_count = DOTS
	dm.visible_instance_count = 0
	dots = MultiMeshInstance3D.new()
	dots.multimesh = dm
	dots.material_override = dot_mat
	dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dots.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	ctx.world.add_child(dots)


## Arbres, cailloux et rampe de lancement sur la planète de départ (orientés selon la verticale locale).
func _decorate_home(g: Node3D, r: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 22:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		if d.y > 0.75:
			continue  # le pôle reste dégagé : on y apparaît
		var n: Node3D
		if k % 3 == 0:
			n = Gfx.mesh(Shapes.icosphere(1.0, 1), Gfx.mat(0xaab3bd, {"rough": 0.8}))
			n.scale = Vector3(0.6, 0.4, 0.5) * rng.randf_range(0.6, 1.4)
		else:
			n = Gfx.tree(rng.randf_range(1.8, 3.0))
		n.position = d * (r - 0.05)
		var side := d.cross(Vector3.RIGHT if absf(d.x) < 0.9 else Vector3.FORWARD).normalized()
		n.basis = Basis(side, d, side.cross(d)) * Basis.from_scale(n.scale)
		g.add_child(n)


# ---------- équipement des astronautes ----------

func _add_gear(id: String) -> void:
	var p: ClientPlayer = ctx.players.get(id)
	if p == null:
		return
	var gd: Dictionary = p.chr.gear()
	var node: Node3D = gd["node"]
	var hr := maxf(0.26, float(gd["head_r"])) + 0.16
	var glass := Gfx.mat(0xd8f3ff, {"opacity": 0.3, "rough": 0.05, "metal": 0.2})
	var helmet := Gfx.mesh(Shapes.sphere(hr, 28, 18), glass, 0, gd["eye_y"], 0.03, node, false)
	var collar := Gfx.mesh(Shapes.torus(hr * 0.78, 0.06, 28, 8), Gfx.mat(0xf1f3f5, {"rough": 0.4}), 0, float(gd["eye_y"]) - hr * 0.72, 0.03, node)
	var roots: Array = [helmet, collar]
	var flames: Array = []
	var my: float = gd["mid_y"]
	var back := -maxf(0.2, float(gd["mid_r"])) - 0.1
	for s: float in [-1.0, 1.0]:
		var rocket := Node3D.new()
		rocket.position = Vector3(s * 0.15, my, back)
		Gfx.mesh(Shapes.cylinder(0.085, 0.085, 0.5, 12), Gfx.mat(0xf8f9fa, {"rough": 0.3}), 0, 0, 0, rocket)
		Gfx.mesh(Shapes.cylinder(0.0, 0.085, 0.18, 12), Gfx.mat(0xff6b6b, {"rough": 0.3}), 0, 0.34, 0, rocket)
		Gfx.mesh(Shapes.cylinder(0.1, 0.06, 0.1, 12), Gfx.mat(0x495057, {"metal": 0.6, "rough": 0.3}), 0, -0.28, 0, rocket)
		var flame := Gfx.mesh(Shapes.cylinder(0.08, 0.0, 0.6, 10), Gfx.mat(0xffa94d, {"glow": 4.0}), 0, -0.62, 0, rocket, false)
		flame.visible = false
		flames.append(flame)
		node.add_child(rocket)
		roots.append(rocket)
	gear[id] = {"roots": roots, "flames": flames}


func on_exit() -> void:
	for g: Dictionary in gear.values():
		for n: Node in g["roots"]:
			if is_instance_valid(n):
				n.queue_free()
	for p: ClientPlayer in ctx.players.values():
		p.chr.basis = Basis()
	ctx.camera.fov = FOV
	_space_env(false)


# ---------- HUD ----------

func _build_hud() -> void:
	top = UI.label("", 20)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint = UI.label("", 12, UI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(top)
	box.add_child(hint)
	ctx.ui.hud_card("top").add_child(box)
	side = UI.label("", 14)
	ctx.ui.hud_card("side").add_child(side)
	var bottom := VBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b_text = UI.label("", 15)
	b_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(b_text)
	b_bar = UI.bar(320, 14, UI.ACCENT)
	b_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(b_bar)
	b_card = ctx.ui.hud_card("bottom")
	b_card.add_child(bottom)
	reticle = CenterContainer.new()
	reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# croix dessinée (deux traits cerclés de noir), centrée au pixel près sur le centre de l'écran
	var cross := Control.new()
	cross.custom_minimum_size = Vector2(36, 36)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for bar: Rect2 in [Rect2(0, 16, 36, 4), Rect2(16, 0, 4, 36)]:
		var shadow := ColorRect.new()
		shadow.color = Color(0, 0, 0, 0.6)
		shadow.position = bar.position - Vector2(2, 2)
		shadow.size = bar.size + Vector2(4, 4)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cross.add_child(shadow)
	for bar: Rect2 in [Rect2(0, 16, 36, 4), Rect2(16, 0, 4, 36)]:
		var line := ColorRect.new()
		line.color = Color("#ffe066")  # jaune, comme les pointillés : ne se confond pas avec les noms des planètes
		line.position = bar.position
		line.size = bar.size
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cross.add_child(line)
	_cross = cross
	reticle.add_child(cross)
	reticle.visible = false
	ctx.ui.hud.add_child(reticle)


func _hud(t: float) -> void:
	var pad := Pad.device() >= 0
	if status == "aim":
		top.text = "Décolle quand tu veux ! Départ automatique dans %d s" % ceili(maxf(0.0, aim_end - maxf(t, ctx.start_at)))
		hint.text = ("Stick gauche : marcher · Stick droit : viser · %s (maintenu) : viser précisément · %s : décoller" % [Pad.label(Pad.bindings.get("retirer", Pad.LT)), Pad.label(Pad.bindings.get("sauter", JOY_BUTTON_A))]) if pad \
			else "Z Q S D : marcher · Souris : viser · Clic droit (maintenu) : viser précisément · Espace : décoller"
		var tgt := _aimed_planet()
		b_text.text = "Cap sur : %s" % (("%s (+%d)" % [planets[tgt]["name"], planets[tgt]["pts"]]) if tgt > 0 else "le vide…")
		b_bar.visible = false
		b_card.visible = true
	else:
		top.text = "Vol : %d s" % ceili(maxf(0.0, flight_end - t))
		if status == "fly":
			hint.text = ("Stick gauche : rétro-fusées (haut, bas, gauche, droite) · Stick droit : regarder · %s : viser précisément" % Pad.label(Pad.bindings.get("retirer", Pad.LT))) if pad \
				else "Z Q S D : rétro-fusées (haut, bas, gauche, droite) · Souris : regarder · Clic droit : viser précisément"
			b_text.text = "Carburant" if fuel > 0.0 else "Plus de carburant !"
		elif status == "landed":
			hint.text = "Bien posé ! On attend les autres…"
			b_text.text = ""
		else:
			hint.text = "Perdu dans l'espace… On attend les autres."
			b_text.text = ""
		b_bar.visible = status == "fly"
		b_card.visible = status == "fly"  # posé ou perdu : rien à afficher en bas
		b_bar.value = fuel / maxf(fuel_max, 0.01)
		UI.set_bar_color(b_bar, Color("#ff922b") if fuel > 0.0 else Color("#adb5bd"))
	var lines := PackedStringArray(["ASTRONAUTES"])
	for id: String in ctx.players:
		var p: ClientPlayer = ctx.players[id]
		var st: Dictionary = status_of.get(id, {})
		var what := "au sol"
		match st.get("s", ""):
			"fly":
				what = "en vol"
			"landed":
				var i: int = st["planet"]
				what = "retombé au départ" if i == 0 else "%s +%d" % [planets[i]["name"], planets[i]["pts"]]
			"lost":
				what = "perdu"
		lines.append("%s — %s" % [p.name, what])
	side.text = "\n".join(lines)


## Planète la plus proche de l'axe de visée (moins de 15°), ou -1.
func _aimed_planet() -> int:
	var o := _cur_p + _up() * 1.0
	var d := _aim()
	var best := -1
	var ba := deg_to_rad(15.0)
	for i in range(1, planets.size()):
		var a := d.angle_to(_center(i) - o)
		if a < ba:
			ba = a
			best = i
	return best


# ---------- physique ----------

func _up() -> Vector3:
	return SpaceShared.up_at(_cur_p, planets)


func _aim() -> Vector3:
	if status == "fly" or status == "lost":
		return SpaceShared.aim_dir(f_up, f_fwd.rotated(f_up, fl_yaw), fl_pitch)
	return SpaceShared.aim_dir(_up(), fwd, elev)


func colliders(_t: float) -> Array:
	return []


func pre_step(b: Phys.Body, _dt: float) -> void:
	_cur_p = b.pos()
	_cur_v = Vector3(b.vx, b.vy, b.vz)


func post_step(b: Phys.Body, _contacts: Array, dt: float) -> void:
	var p := _cur_p + _pend_p
	var v := _cur_v + _pend_v
	_pend_p = Vector3.ZERO
	_pend_v = Vector3.ZERO
	var t := ctx.now()
	var grounded := false
	if status == "aim" and t >= ctx.start_at and (_want_launch or t >= aim_end):
		_launch(p)
		var up0 := p.normalized()
		p += up0 * 0.3
		v = SpaceShared.aim_dir(up0, fwd, elev) * SpaceShared.SPEED
	if status == "fly" or status == "lost":
		var turn := Vector3.ZERO
		if status == "fly" and burning and thrust != Vector3.ZERO:
			# la poussée fait tourner la trajectoire vers le côté poussé (la vitesse ne change pas)
			turn = (v.normalized() + thrust).normalized()
			fuel = maxf(0.0, fuel - dt)
		var s := SpaceShared.step(p, v, dt, planets, gravity, turn)
		p = s[0]
		v = s[1]
		var h := SpaceShared.hit(p, v, planets)
		if h >= 0:
			var c := _center(h)
			p = c + (p - c).normalized() * float(planets[h]["r"])
			v = Vector3.ZERO
			grounded = true
			_touch_down(h, p)
		elif status == "fly" and p.length() > SpaceShared.OUT_R:
			status = "lost"
			burning = false
			ctx.send_game({"t": "lost"})
	else:
		# marche sur la planète la plus proche
		var i := SpaceShared.nearest(p, planets)
		var c := _center(i)
		var r: float = planets[i]["r"]
		var up := (p - c).normalized()
		var g := SpaceShared.K * r
		var frozen := t < ctx.start_at
		var inp := ctx.input
		var f := 0.0
		var rt := 0.0
		if not frozen:
			f = Main._b2i(inp.down("KeyW")) - Main._b2i(inp.down("KeyS")) - inp.move.y
			rt = Main._b2i(inp.down("KeyD")) - Main._b2i(inp.down("KeyA")) + inp.move.x
		var hf := (fwd - up * fwd.dot(up)).normalized()
		var want := (hf * f + hf.cross(up) * rt).limit_length(1.0) * SpaceShared.WALK
		var on_ground := p.distance_to(c) <= r + 0.06
		var vr := v.dot(up)
		var vt := v - up * vr
		vt = vt.move_toward(want, (45.0 if on_ground else 12.0) * dt)
		vr -= g * dt
		if on_ground and not frozen and status == "landed" and inp.down("Space") and vr <= 0.5:
			vr = SpaceShared.JUMP
			ctx.sfx.jump()
		v = vt + up * vr
		p += v * dt
		var d := p - c
		if d.length() <= r:
			var impact := -v.dot(d.normalized())
			p = c + d.normalized() * r
			v -= d.normalized() * minf(0.0, v.dot(d.normalized()))
			grounded = true
			if impact > 7.0:
				ctx.sfx.land()
	b.set_pos(p.x, p.y, p.z)
	b.vx = v.x
	b.vy = v.y
	b.vz = v.z
	b.grounded = grounded
	b.coyote = 0.0
	b.tumble = 0.0
	b.jumped = false
	b.landed = 0.0
	_cur_p = p
	_cur_v = v


func _launch(p: Vector3) -> void:
	status = "fly"
	_want_launch = false
	status_of[ctx.my_id] = {"s": "fly"}
	launch_at[ctx.my_id] = ctx.now()
	launch_up[ctx.my_id] = p.normalized()
	_armed = false
	ctx.send_game({"t": "launch"})
	var up := p.normalized()
	f_up = up
	f_fwd = fwd
	fl_yaw = 0.0
	fl_pitch = elev
	ctx.sfx.fire()
	ctx.sfx.boom(0.6)
	ctx.impact(0.7)
	ctx.particles.burst(p, 40, [0xffd43b, 0xff922b, 0xffffff], 7.0, 0.25, 0.9, 0.0)
	ctx.toast("Décollage !", 1.5)


func _touch_down(h: int, p: Vector3) -> void:
	status = "landed"
	burning = false
	_send_burn()
	# nouveau cap au sol : la direction regardée, ramenée sur la surface
	var up := (p - _center(h)).normalized()
	var look := _aim()
	var hf := look - up * look.dot(up)
	fwd = hf.normalized() if hf.length() > 0.05 else SpaceShared.tangent_frame(up)[0]
	elev = deg_to_rad(25.0)
	thrust = Vector3.ZERO
	# la caméra de vol rejoint en douceur celle du sol (au lieu de sauter d'un coup)
	_land_from = {"pos": _cam_pos, "look": _cam_look, "up": _cam_up}
	_land_t = ctx.now()
	ctx.sfx.land()
	ctx.shake(0.5)
	ctx.particles.burst(p, 24, [planets[h]["color"], 0xffffff], 5.0, 0.2, 0.8, 0.0)
	ctx.send_game({"t": "landed", "planet": h})


func _send_burn() -> void:
	var t := ctx.now()
	var turned := burning and thrust.distance_to(_thrust_sent) > 0.35 and t - _thrust_at > 0.12
	if burning != _burn_sent or turned:
		_burn_sent = burning
		_thrust_sent = thrust
		_thrust_at = t
		var d := [snappedf(thrust.x, 0.01), snappedf(thrust.y, 0.01), snappedf(thrust.z, 0.01)]
		ctx.send_game({"t": "burn", "on": burning, "d": d})


## Repère de vol : [direction du vol, dos du personnage, sa droite]. Le dos reste tourné vers le « haut » du
## décollage, qui est aussi le haut de la caméra : le personnage vole sur le ventre.
func _fly_frame(v: Vector3, back_ref: Vector3) -> Array:
	var f := v.normalized() if v.length_squared() > 1e-6 else _aim()
	var back := back_ref - f * back_ref.dot(f)
	if back.length_squared() < 0.01:
		back = SpaceShared.tangent_frame(f)[0]
	back = back.normalized()
	return [f, back, f.cross(back)]


## Collision entre astronautes en vol : rebond élastique (masses égales), appliqué au pas suivant.
func jostle(_b: Phys.Body, op: Vector3, ov: Vector3) -> void:
	if not bump or status != "fly":
		return
	var d := _cur_p - op
	var dist := d.length()
	if dist >= SpaceShared.BUMP_R * 1.2 or dist < 1e-3:
		return
	var n := d / dist
	var rel := (_cur_v - ov).dot(n)
	if rel < 0.0:
		_pend_v += -rel * n
		if _bump_cd <= 0.0:
			_bump_cd = 0.3
			ctx.sfx.boing()
			ctx.shake(0.4)
	_pend_p += n * (SpaceShared.BUMP_R * 1.2 - dist) * 0.5


func motion(p: Vector3, v: Vector3) -> Vector2:
	var up := SpaceShared.up_at(p, planets)
	var vr := v.dot(up)
	return Vector2((v - up * vr).length(), vr)


func net_yaw(_yaw: float) -> float:
	return SpaceShared.yaw_of(_up(), fwd)


# ---------- messages ----------

func on_message(m: Dictionary) -> void:
	match m["t"]:
		"landed":
			var id: String = m["id"]
			var i := int(m["planet"])
			status_of[id] = {"s": "landed", "planet": i}
			burn_of.erase(id)
			var p: ClientPlayer = ctx.players.get(id)
			if id == ctx.my_id:
				if i == 0:
					ctx.toast("Retombé sur la planète de départ…", 2.5)
				else:
					ctx.toast("Posé sur %s : +%d !" % [planets[i]["name"], planets[i]["pts"]], 3.0)
					ctx.sfx.win()
			elif p and i > 0:
				ctx.toast("%s s'est posé sur %s (+%d)" % [p.name, planets[i]["name"], planets[i]["pts"]], 1.8)
		"lost":
			var id: String = m["id"]
			status_of[id] = {"s": "lost"}
			burn_of.erase(id)
			if id == ctx.my_id:
				status = "lost"
				burning = false
				ctx.toast("Perdu dans l'espace…", 2.5)
				ctx.sfx.xylo()
		"burn":
			burn_of[m["id"]] = m["on"]
			var d: Variant = m.get("d")
			thrust_of[m["id"]] = Vector3(d[0], d[1], d[2]) if d is Array and d.size() == 3 else Vector3.ZERO
		"launch":
			var id: String = m["id"]
			if id != ctx.my_id:
				status_of[id] = {"s": "fly"}
				launch_at[id] = ctx.now()
				var lp: ClientPlayer = ctx.players.get(id)
				if lp:
					launch_up[id] = SpaceShared.up_at(lp.pos, planets)


# ---------- image ----------

func on_frame(dt: float) -> void:
	var t := ctx.now()
	var inp := ctx.input
	_bump_cd -= dt
	# visée : la souris tourne le cap (via cam_yaw de Main) et règle l'élévation
	var dyaw := ctx.cam_yaw - _last_cam_yaw
	_last_cam_yaw = ctx.cam_yaw
	var dpitch := inp.dy * 0.0022 * Config.mouse_sens - (Main._b2i(inp.down("ArrowUp")) - Main._b2i(inp.down("ArrowDown"))) * 1.2 * dt
	dpitch += inp.look.y * 1.6 * Pad.look_sens * dt * (-1.0 if Pad.invert_y else 1.0)
	# visée précise (clic droit ou LT maintenu) : longue-vue dans l'axe exact du tir, souris ralentie
	var precise := (status == "aim" or status == "fly") and inp.down("Mouse2", "PadRemove")
	zoom = move_toward(zoom, 1.0 if precise else 0.0, dt * 6.0)
	var sens := lerpf(1.0, ZOOM_SENS, zoom)
	dyaw *= sens
	dpitch *= sens
	if status == "fly" or status == "lost":
		fl_yaw += dyaw
		fl_pitch = clampf(fl_pitch - dpitch, -1.45, 1.45)
		# rétro-fusées au stick gauche (ou Z Q S D) : la poussée va dans la direction du stick, la flamme sort du côté
		# opposé (haut : par le ventre, vers le dos ; bas : par le dos, vers le ventre ; gauche / droite : par le flanc)
		var sx := Main._b2i(inp.down("KeyD")) - Main._b2i(inp.down("KeyA")) + inp.move.x
		var sy := Main._b2i(inp.down("KeyW")) - Main._b2i(inp.down("KeyS")) - inp.move.y
		var st := Vector2(sx, sy).limit_length(1.0)
		# stick déjà poussé au décollage (on marchait) : il faut le relâcher avant d'allumer les rétro-fusées
		if st.length() < 0.25:
			_armed = true
		burning = status == "fly" and _armed and fuel > 0.0 and st.length() >= 0.25
		thrust = Vector3.ZERO
		if burning:
			var fr := _fly_frame(_cur_v, f_up)
			thrust = (fr[1] * st.y + fr[2] * st.x).normalized()
		_send_burn()
	else:
		var up := _up()
		fwd = (fwd - up * fwd.dot(up)).normalized().rotated(up, dyaw)
		elev = clampf(elev - dpitch, SpaceShared.ELEV_MIN, SpaceShared.ELEV_MAX)
		if status == "aim" and t >= ctx.start_at and t < aim_end and inp.hit("Space"):
			_want_launch = true  # décollage au prochain pas de physique

	# pointillés : trajectoire des prochaines secondes (visée, puis vol)
	var show := (status == "aim" or status == "fly") and zoom < 0.6  # en visée précise, les points boucheraient la vue
	var mm := dots.multimesh
	if show:
		var o := _cur_p
		var v := _cur_v
		if status == "aim":
			o = _cur_p + _up() * 0.3
			v = _aim() * SpaceShared.SPEED
		# trajectoire fine (1/60 s), sur laquelle les points glissent en continu : aucun saut d'une image à l'autre
		var step := 1.0 / 60.0
		var pr := SpaceShared.predict(o, v, planets, gravity, SpaceShared.PREVIEW_T + 0.2, step)
		var pts: PackedVector3Array = pr["pts"]
		var gap := SpaceShared.PREVIEW_T / DOTS
		var shift := fmod(t * 0.6, 1.0) * gap
		var n := 0
		for k in DOTS:
			var tk := 0.15 + k * gap + shift
			var f := tk / step
			var i := int(f)
			if i + 1 >= pts.size():
				break
			var pos := pts[i].lerp(pts[i + 1], f - i)
			var s := 1.0 - clampf(tk / SpaceShared.PREVIEW_T, 0.0, 1.0) * 0.7  # de plus en plus petits
			mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(s, s, s)), pos))
			n += 1
		mm.visible_instance_count = n
		dot_mat.albedo_color = Color("#ffe066") if status == "aim" else Color("#ffffff", 0.6)
	else:
		mm.visible_instance_count = 0

	_orient_players(dt)
	_camera(dt)
	_place_labels()

	_hud_timer -= dt
	if _hud_timer < 0.0:
		_hud_timer = 0.1
		_hud(t)


## Nom et points de chaque planète : au-dessus d'elle à l'écran, avancés vers la caméra pour que la planète ne les
## cache jamais.
func _place_labels() -> void:
	var cam := ctx.camera.global_transform
	for e: Array in labels:
		var c := _center(e[1])
		var r: float = planets[e[1]]["r"]
		var to_cam := cam.origin - c
		if to_cam.length() < r * 1.5:
			e[0].visible = false
			continue
		e[0].visible = true
		e[0].position = c + to_cam.normalized() * r + cam.basis.y * (r * 1.15)


func _orient_players(dt: float) -> void:
	for id: String in ctx.players:
		var p: ClientPlayer = ctx.players[id]
		var up: Vector3
		var f: Vector3
		var pos := p.pos
		var flying := false
		if id == ctx.my_id:
			flying = status == "fly" or (status == "lost" and _cur_v.length() > 1.0)
			if flying:
				# en vol : la tête dans le sens du vol, le ventre vers le bas (le dos vers le haut de la caméra)
				var fr := _fly_frame(_cur_v, f_up)
				up = fr[0]
				f = -fr[1]
			else:
				up = _up()
				f = fwd
		else:
			var i := SpaceShared.nearest(pos, planets)
			flying = pos.distance_to(_center(i)) - float(planets[i]["r"]) > 1.5
			if flying and p.net_v.length() > 1.0:
				var fr := _fly_frame(p.net_v, launch_up.get(id, SpaceShared.up_at(pos, planets)))
				up = fr[0]
				f = -fr[1]
			else:
				up = SpaceShared.up_at(pos, planets)
				f = SpaceShared.fwd_of(up, p.yaw)
		f = f - up * f.dot(up)
		if f.length_squared() < 1e-6:
			f = SpaceShared.tangent_frame(up)[0]
		f = f.normalized()
		# on pivote en douceur : à l'atterrissage, le personnage se redresse au lieu d'apparaître debout d'un coup
		var want := Basis(up.cross(f), up, f).get_rotation_quaternion()
		var q: Quaternion = _rot.get(id, want)
		q = q.slerp(want, 1.0 - exp(-TURN_RATE * dt)).normalized()
		_rot[id] = q
		p.chr.basis = Basis(q)
		var g: Dictionary = gear.get(id, {})
		var burn_on: bool = burning if id == ctx.my_id else burn_of.get(id, false)
		var push: Vector3 = thrust if id == ctx.my_id else thrust_of.get(id, Vector3.ZERO)
		var launching: bool = status_of.get(id, {}).get("s", "") == "fly" and ctx.now() - launch_at.get(id, -10.0) < 0.9
		# les fusées du dos s'allument au décollage, et quand on pousse vers le ventre
		var belly := p.chr.basis.z.normalized()
		var on: bool = launching or (burn_on and push.dot(belly) > 0.5)
		for fl: MeshInstance3D in g.get("flames", []):
			if is_instance_valid(fl):
				fl.visible = on
				fl.scale = Vector3(1, randf_range(0.7, 1.3), 1)
		if launching and randf() < 0.5:
			var back := p.chr.to_global(Vector3(0, 0.6, -0.35))
			ctx.particles.emit(back.x, back.y, back.z, 0, 0, 0, 0xffa94d, 0.18, 0.4, 0.0)
		if burn_on and push != Vector3.ZERO:
			# jet de la rétro-fusée : il sort du côté opposé à la poussée
			var mid := p.chr.to_global(Vector3(0, 0.55, 0))
			for k in 2:
				var o := mid - push * randf_range(0.45, 0.6) + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.15
				var jv := -push * randf_range(4.0, 6.5)
				ctx.particles.emit(o.x, o.y, o.z, jv.x, jv.y, jv.z, 0xffa94d if k == 0 else 0xffe066, 0.16, 0.35, 0.0)


func _camera(dt: float) -> void:
	var cam_pos: Vector3
	var look_at: Vector3
	var up: Vector3
	var l := _aim()
	if status == "fly" or status == "lost":
		up = f_up
		var c := _cur_p + l.cross(f_up).cross(l).normalized() * 0.8
		cam_pos = c - l * FLY_CAM + up * 1.2
		# le centre de l'écran est le point regardé, avec ou sans zoom
		look_at = _cur_p + l * AIM_DIST
		if zoom > 0.0:
			# visée précise : la caméra se place sur l'axe exact de la direction regardée
			cam_pos = cam_pos.lerp(_cur_p - l * 1.0, zoom)
	else:
		up = _up()
		# la caméra suit la visée sans trop lever le nez : on garde l'horizon (et les planètes) en vue
		var head := _cur_p + up * 1.4
		# la caméra se place derrière le personnage (un peu moins haut que la visée, pour qu'il reste à l'image)
		var lc := SpaceShared.aim_dir(up, fwd, elev * 0.8)
		# un peu au-dessus de l'épaule droite, pour voir les pointillés partir devant le personnage
		var right := fwd.cross(up).normalized() * 1.1
		cam_pos = head - lc * CAM_DIST + up * 1.0 + right
		# et regarde exactement le point visé : la mire est au même endroit avec ou sans zoom
		var o := _cur_p + up * 0.3
		look_at = o + l * AIM_DIST
		if zoom > 0.0:
			# visée précise : la caméra se place juste derrière le point de départ, sur l'axe exact du tir
			cam_pos = cam_pos.lerp(o - l * 1.0, zoom)
		# jamais sous la surface
		var i := SpaceShared.nearest(cam_pos, planets)
		var c := _center(i)
		var minr: float = float(planets[i]["r"]) + 0.8
		if cam_pos.distance_to(c) < minr:
			cam_pos = c + (cam_pos - c).normalized() * minr
	var k := (ctx.now() - _land_t) / LAND_CAM
	if status == "landed" and k < 1.0 and not _land_from.is_empty():
		# atterrissage : de la caméra de vol à celle du sol, en douceur (position, visée et haut de l'image)
		var e := k * k * (3.0 - 2.0 * k)
		_cam_pos = (_land_from["pos"] as Vector3).lerp(cam_pos, e)
		look_at = (_land_from["look"] as Vector3).lerp(look_at, e)
		up = (_land_from["up"] as Vector3).slerp(up.normalized(), e).normalized()
		var ci := SpaceShared.nearest(_cam_pos, planets)
		var cc := _center(ci)
		var cr: float = float(planets[ci]["r"]) + 0.8
		if _cam_pos.distance_to(cc) < cr:
			_cam_pos = cc + (_cam_pos - cc).normalized() * cr
	elif not _cam_init or _cam_pos.distance_to(cam_pos) > 30.0:
		_cam_pos = cam_pos
		_cam_init = true
	else:
		_cam_pos = _cam_pos.lerp(cam_pos, 1.0 - exp(-lerpf(18.0, 60.0, zoom) * dt))
	_cam_look = look_at
	_cam_up = up.normalized()
	var shake := ctx._shake
	var jit := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * shake if shake > 0.01 else Vector3.ZERO
	if (look_at - _cam_pos).cross(up).length_squared() < 1e-6:
		up = SpaceShared.tangent_frame(up)[0]
	ctx.camera.look_at_from_position(_cam_pos + jit, look_at, up)
	ctx.camera.fov = lerpf(FOV, ZOOM_FOV, zoom)
	# mire : petite et discrète sans zoom, grande en visée précise
	reticle.visible = status == "aim" or status == "fly"
	_cross.modulate.a = lerpf(0.85, 1.0, zoom)
	_cross.pivot_offset = _cross.size / 2.0
	_cross.scale = Vector2.ONE * lerpf(0.65, 1.0, zoom)
	# son propre personnage gênerait la vue dans l'axe
	var me := ctx.me()
	if me and zoom > 0.6:
		me.chr.visible = false
