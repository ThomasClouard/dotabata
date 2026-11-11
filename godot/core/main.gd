class_name Main
extends Node3D
## Cœur du client : accueil (serveurs du réseau local, création d'un serveur), caméra troisième personne,
## personnage local, réseau, enchaînement lobby → manches → podium.
## Portage de client/src/main.ts. Ce nœud sert aussi de contexte (« ctx ») aux mini-jeux.

const H := 1.0 / 60.0  # pas fixe de la physique, comme le client d'origine

var net := Net.new()
var discovery := Discovery.new()
var host: ServerHost = null  # serveur hébergé par ce client (null si on rejoint celui d'un autre)
var input := GameInput.new()
var sfx := Sfx.new()
var env := GameEnv.new()
var particles := Particles.new()
var ui := GameUI.new()
var world := Node3D.new()  # contenu du jeu en cours ; vidé à chaque changement de scène
var char_layer := Node3D.new()
var camera := Camera3D.new()

var players := {}  # id → ClientPlayer
var body := Phys.Body.new()
var my_id := ""
var start_at := 0.0
var cam_yaw := PI
var hud: Control:
	get:
		return ui.hud

var _lobby: Variant = null  # dernier message « lobby »
var _phase := "boot"  # boot | menu | lobby | round | scores | podium
var _waiting := false
var _game: ClientGame
var _cols: Array = []
var _cam_pitch := 0.38
var _shake := 0.0
var _spectate: Variant = null  # { target: Vector3, dist: float }
var _active := true
var _aim_mode := false
var _charging := false
var _my_yaw := 0.0
var _acc := 0.0
var _send_acc := 0.0
var _last_count := -1
var _cam_target := Vector3(0, 1.5, 0)
var _address := ""
var _password := ""
var _join_name := ""  # nom du serveur qu'on rejoint (pour la demande de mot de passe)
var _bots_applied := false
var _autostarted := false
var _shadow_mesh: Mesh
var _shadow_mat: StandardMaterial3D
var _debug := Debug.new()
var _menu_cam := [Vector3.ZERO, Vector3.ZERO]  # caméra du menu (position, point visé), lissée
var _menu_cam_set := false


func _ready() -> void:
	Config.load_all()
	Config.apply_options()
	UI.init_theme()
	add_child(env)
	add_child(world)
	add_child(char_layer)
	add_child(particles)
	camera.fov = 58.0
	camera.near = 0.1
	camera.far = 900.0
	add_child(camera)
	camera.current = true
	add_child(input)
	add_child(sfx)
	add_child(net)
	add_child(discovery)
	add_child(ui)
	add_child(_debug)
	_debug.main = self
	body.set_pos(0, 2, 0)
	_shadow_mesh = Shapes.cylinder(0.5, 0.5, 0.01, 16)
	_shadow_mat = Gfx.flat(0x000000, {"opacity": 0.28})

	net.message.connect(_on_message)
	net.opened.connect(func() -> void: ui.hide_overlay())
	net.closed.connect(_on_closed)
	ui.profile_changed.connect(_on_profile)
	ui.settings_changed.connect(func(s: Dictionary) -> void: net.send({"t": "settings", "settings": s}))
	ui.bots_changed.connect(func(n: int) -> void: net.send({"t": "bots", "n": n}))
	ui.start_pressed.connect(func() -> void: net.send({"t": "start"}))
	ui.stop_pressed.connect(func() -> void: net.send({"t": "stop"}))
	ui.to_lobby_pressed.connect(func() -> void: net.send({"t": "toLobby"}))
	ui.quality_toggled.connect(_toggle_quality)
	var menu := ui.menu
	menu.can_host = Discovery.supported()
	menu.join_requested.connect(_join)
	menu.create_requested.connect(_create_server)
	menu.profile_changed.connect(func(p: Dictionary) -> void:
		var hat_changed: bool = p["hat"] != Config.profile["hat"]
		Config.profile = p
		Config.save()
		if hat_changed and _game is MenuScene:
			_game.show_look(p["color"], p["hat"]))
	menu.quality_changed.connect(func(q: int) -> void:
		Config.quality = q
		Config.save()
		env.apply_quality(q))
	menu.shot_changed.connect(func(n: String) -> void:
		if _game is MenuScene:
			_game.set_shot(n))
	menu.spin.connect(func(a: float) -> void:
		if _game is MenuScene:
			_game.spin(a))
	menu.quit_requested.connect(func() -> void: _notification(NOTIFICATION_WM_CLOSE_REQUEST))
	menu.sound.connect(func(k: String) -> void: sfx.play(k, 0.35 if k == "tick" else 0.6))
	if Config.args.has("menu"):
		menu.jump_to(str(Config.args["menu"]))
	ui.leave_pressed.connect(_on_leave)
	ui.server_cfg_changed.connect(func(cfg: Dictionary) -> void: net.send({"t": "server", "name": cfg["name"], "max": cfg["max"], "password": cfg["password"]}))
	discovery.changed.connect(func() -> void: ui.menu.update_servers(discovery.list()))
	get_tree().set_auto_accept_quit(false)
	_boot()


## Premier écran : options de lancement, sinon l'accueil.
func _boot() -> void:
	if Config.args.has("server"):
		_connect(str(Config.args["server"]))
	elif OS.has_feature("web"):
		_connect(Config.default_server())  # le serveur est a priori sur la machine qui sert la page
	elif Config.args.has("host") or Config.args.has("bots") or Config.args.has("autostart"):
		_create_server(Config.server_cfg)
	else:
		_show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# fermeture de la fenêtre : on prévient les joueurs connectés à notre serveur avant de quitter
		if host != null:
			net.close()
			host.shutdown()
			host = null
			await get_tree().create_timer(0.3).timeout
		get_tree().quit()


# ---------- contexte des mini-jeux ----------

## Horloge serveur synchronisée (secondes).
func now() -> float:
	return net.now()


func send_game(m: Dictionary) -> void:
	net.send({"t": "game", "m": m})


func shake(amount: float) -> void:
	_shake = minf(1.2, maxf(_shake, amount))


func set_sky(color: int) -> void:
	env.set_sky(color)


## Mer animée sous le décor, à l'altitude `y` (null = aucune).
func set_sea(y: Variant, color := 0x1fb6e0) -> void:
	env.set_sea(y, color)


## false = spectateur : plus de contrôle ni de physique pour le joueur local.
func set_active(a: bool) -> void:
	_active = a


## Caméra orbitale autour d'un point (null = retour sur le joueur).
func set_spectate(target: Variant, dist := 12.0) -> void:
	_spectate = {"target": target, "dist": dist} if target != null else null


## Le personnage regarde dans la direction de la caméra (visée).
func set_aim_mode(on: bool) -> void:
	_aim_mode = on


func set_charging(on: bool) -> void:
	_charging = on


func toast(text: String, seconds := 1.8) -> void:
	ui.toast(text, seconds)


func me() -> ClientPlayer:
	return players.get(my_id)


# ---------- connexion ----------

## Menu principal : écran titre, parties du réseau local, création, personnage, options.
## Après une erreur, il rouvre l'écran d'où l'on venait ; to_title : retour à l'écran titre (on a quitté une partie).
func _show_menu(error := "", to_title := false) -> void:
	if to_title:
		ui.menu.reset()
	net.close()
	_reset_session()
	_phase = "menu"
	_set_game(MenuScene.new(), null)  # décor : le terrain du lobby, ton personnage en vitrine
	_game.set_shot(ui.menu.current() if ui.menu.current() != "" else "titre")
	_menu_cam_set = false
	input.release_mouse()
	input.set_process_unhandled_input(false)  # pas de capture de la souris ni de touches de jeu dans le menu
	ui.set_server_form({})
	ui.hide_overlay()
	ui.dismiss_splash()
	discovery.start()
	ui.menu.scanning = discovery.is_running()
	ui.menu.last_address = Config.server
	ui.menu.update_servers(discovery.list())
	ui.menu.open(error)
	_update_chrome()


## Rejoindre un serveur depuis l'accueil (mot de passe "" si aucun).
func _join(address: String, password: String) -> void:
	_join_name = address
	for s: Dictionary in discovery.list():
		if s["address"] == address:
			_join_name = s["name"]
	_connect(address, password)


## Crée un serveur dans ce client, puis s'y connecte comme n'importe quel joueur.
func _create_server(cfg: Dictionary) -> void:
	var c := cfg.duplicate()
	if str(c.get("name", "")) == "":
		c["name"] = "Partie de %s" % Config.profile["name"]
	Config.server_cfg = c
	Config.save()
	_stop_host()
	host = ServerHost.new()
	add_child(host)
	var port := host.start(c)
	if port < 0:
		host.queue_free()
		host = null
		_show_menu("Impossible d'ouvrir un port réseau (%d à %d) : un autre programme les utilise peut-être." % [Protocol.PORT, Protocol.PORT + Protocol.PORT_SPAN - 1])
		return
	host.session.server_changed.connect(func(saved: Dictionary) -> void:
		Config.server_cfg = saved
		Config.save()
		ui.set_server_form(saved))
	ui.set_server_form(host.session.server_cfg)
	_join_name = c["name"]
	_connect("127.0.0.1:%d" % port)


func _stop_host() -> void:
	if host != null:
		host.shutdown()
		host = null
	ui.set_server_form({})


func _connect(address: String, password := "") -> void:
	if address == "":
		return
	discovery.stop()
	ui.menu.close()
	input.set_process_unhandled_input(true)
	_address = address
	_password = password
	_reset_session()
	ui.show_message("Connexion…", _join_name if _join_name != "" else address)
	var hello := {"t": "hello", "name": Config.profile["name"], "color": Config.profile["color"], "hat": Config.profile["hat"], "pw": password}
	if host != null and address == "127.0.0.1:%d" % host.port:
		hello["key"] = host.session.host_key  # le créateur du serveur en est l'hôte
	net.connect_to(address, hello)


func _on_closed(was_open: bool) -> void:
	input.release_mouse()
	if host != null:
		# notre propre serveur ne répond plus : on le ferme proprement
		_stop_host()
		_show_menu("La connexion à ton serveur a été perdue.")
		return
	match net.close_code:
		Session.CLOSE_PASSWORD:
			_show_menu()
			ui.menu.ask_password(_address, _join_name if _join_name != "" else _address, "Mot de passe incorrect." if _password != "" else "")
		Session.CLOSE_FULL:
			_show_menu("Ce serveur est complet.")
		Session.CLOSE_SHUTDOWN:
			_show_menu("L'hôte a fermé le serveur.")
		_:
			if was_open:
				ui.show_confirm("Connexion perdue", "Le serveur ne répond plus.", "Se reconnecter", func() -> void: _connect(_address, _password), "Accueil", func() -> void: _show_menu("", true))
			else:
				_show_menu("Impossible de joindre %s. Vérifie l'adresse, et que le pare-feu de l'hôte autorise Dotabata!." % _address)


## « Quitter » / « Fermer le serveur » / « Retour » : confirmation si on ferme un serveur où d'autres jouent.
func _on_leave() -> void:
	if host == null or my_id == "":
		_show_menu("", my_id != "")
		return
	var others := 0
	if _lobby != null:
		for p: Dictionary in _lobby["players"]:
			if not p["isBot"] and p["id"] != my_id:
				others += 1
	if others == 0:
		_close_own_server()
		return
	ui.show_confirm("Fermer le serveur ?", "%d autre%s joueur%s sera%s déconnecté%s." % [others, "s" if others > 1 else "", "s" if others > 1 else "", "nt" if others > 1 else "", "s" if others > 1 else ""],
		"Fermer le serveur", _close_own_server, "Annuler", func() -> void:
			ui.hide_overlay()
			_update_chrome())


func _close_own_server() -> void:
	net.close()
	_stop_host()
	_show_menu("", true)


func _reset_session() -> void:
	_set_game(null, null)
	for p: ClientPlayer in players.values():
		p.chr.queue_free()
		p.shadow.queue_free()
	players.clear()
	my_id = ""
	_lobby = null
	_phase = "boot"
	_waiting = false
	_bots_applied = false
	_autostarted = false
	ui.lobby.visible = false
	ui.wait.visible = false
	ui.stop.visible = false
	ui.hide_banner()


func _on_profile(p: Dictionary) -> void:
	Config.profile = p
	Config.save()
	net.send({"t": "profile", "name": p["name"], "color": p["color"], "hat": p["hat"]})


func _toggle_quality() -> void:
	Config.quality = (Config.quality + 1) % 3
	Config.save()
	env.apply_quality(Config.quality)
	if _lobby != null and _phase == "lobby":
		ui.render_lobby(_lobby, my_id)


# ---------- joueurs ----------

func _make_label(pname: String, color: int) -> Label3D:
	var l := Label3D.new()
	l.text = pname
	l.font = UI.font
	l.font_size = 40
	l.pixel_size = 0.0075
	l.modulate = Gfx.col(color)
	l.outline_size = 12
	l.outline_modulate = UI.INK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.render_priority = 10
	l.outline_render_priority = 9
	l.position.y = 2.25
	return l


func _sync_players(list: Array) -> void:
	var seen := {}
	for info: Dictionary in list:
		info["color"] = int(info["color"])
		var id: String = info["id"]
		seen[id] = true
		var p: ClientPlayer = players.get(id)
		if p == null:
			p = ClientPlayer.new()
			p.info = info
			p.chr = Character.new(info["color"], info["hat"])
			p.label = _make_label(info["name"], info["color"])
			p.chr.add_child(p.label)
			p.shadow = Gfx.mesh(_shadow_mesh, _shadow_mat, 0, 0, 0, char_layer, false)
			p.shadow.visible = false
			char_layer.add_child(p.chr)
			p.chr.visible = false
			players[id] = p
		else:
			if p.info["color"] != info["color"] or p.info["hat"] != info["hat"]:
				p.chr.set_look(info["color"], info["hat"])
			if p.info["name"] != info["name"] or p.info["color"] != info["color"]:
				p.label.text = info["name"]
				p.label.modulate = Gfx.col(info["color"])
			p.info = info
	for id: String in players.keys():
		if seen.has(id):
			continue
		var p: ClientPlayer = players[id]
		p.chr.queue_free()
		p.shadow.queue_free()
		players.erase(id)


# ---------- scènes ----------

func _set_game(g: ClientGame, init: Variant) -> void:
	if _game:
		_game.on_exit()
	for c in world.get_children():
		world.remove_child(c)
		c.queue_free()
	ui.hud_clear()
	_active = true
	_spectate = null
	_aim_mode = false
	_charging = false
	for p: ClientPlayer in players.values():
		p.pin = null
		p.hidden = false
	env.set_sea(null)
	_game = g
	_cols = []
	if g:
		g.on_enter(self, init)


func teleport(x: float, y: float, z: float) -> void:
	body.set_pos(x, y, z)
	body.vx = 0.0
	body.vy = 0.0
	body.vz = 0.0
	body.tumble = 0.0
	Phys.clear_motion_state(body)  # ni tyrolienne, ni vol, ni élan en arrivant


func _enter_lobby() -> void:
	_phase = "lobby"
	start_at = 0.0
	_set_game(LobbyScene.new(), null)
	for p: ClientPlayer in players.values():
		p.chr.reset_damage()
	var a := randf() * TAU
	teleport(sin(a) * 3.0, 1.0, cos(a) * 3.0 - 4.0)
	cam_yaw = PI
	ui.hide_overlay()
	ui.hide_banner()


func _is_host() -> bool:
	return _lobby != null and _lobby["hostId"] == my_id


func _update_chrome() -> void:
	ui.lobby.visible = _phase == "lobby" and not _waiting
	ui.wait.visible = _waiting
	var in_game := _phase != "lobby" and _phase != "boot" and _phase != "menu"
	ui.stop.visible = _is_host() and in_game
	ui.server_btn.visible = _is_host() and host != null and in_game
	ui.leave.visible = in_game or (_waiting and _phase != "boot")
	ui.corner.text = "" if _phase == "lobby" or _phase == "boot" or _phase == "menu" else "Z Q S D : bouger · Espace : sauter · Souris : caméra · Échap : libérer la souris"


func _meta(game_id: String) -> Dictionary:
	if _lobby != null:
		for g: Dictionary in _lobby["metas"]:
			if g["id"] == game_id:
				return g
	return {"name": game_id, "description": ""}


# ---------- réseau ----------

func _on_message(m: Dictionary) -> void:
	ui.dismiss_splash()
	match m["t"]:
		"welcome":
			my_id = m["id"]
			if host == null:
				Config.server = _address  # adresse proposée la fois suivante
				Config.save()
		"lobby":
			_lobby = m
			_sync_players(m["players"])
			if m["phase"] == "lobby":
				_waiting = false
				if _phase != "lobby":
					_enter_lobby()
				ui.render_lobby(m, my_id)
				_debug.on_lobby(m)
			elif _phase == "boot":
				_enter_lobby()
			_update_chrome()
		"wait":
			_waiting = true
			_update_chrome()
		"round":
			var g := Registry.create(m["gameId"])
			if g == null:
				return
			_waiting = false
			_phase = "round"
			ui.hide_overlay()
			for p: ClientPlayer in players.values():
				p.chr.reset_damage()
			start_at = m["startAt"]
			var spawns: Dictionary = m["spawns"]
			if spawns.has(my_id):
				var s: Array = spawns[my_id]
				teleport(s[0], s[1], s[2])
			# les objets de la manche précédente (super saut, bouclier) ne survivent pas
			body.super_jump = 0.0
			body.shield = 0.0
			_set_game(g, m["init"])
			var meta := _meta(m["gameId"])
			ui.show_banner(meta["name"], "Manche %d/%d — %s" % [int(m["index"]) + 1, int(m["total"]), meta["description"]])
			_last_count = -1
			_update_chrome()
		"roundEnd":
			_phase = "scores"
			input.release_mouse()
			ui.show_scores(m, _lobby["players"] if _lobby != null else [], my_id, _meta(m["gameId"])["name"])
			ui.hide_banner()
		"podium":
			_phase = "podium"
			ui.hide_overlay()
			input.release_mouse()
			var order := []
			for r: Array in GameUI.sorted_totals(m["totals"]):
				if players.has(r[0]):
					order.append(r[0])
			_set_game(PodiumScene.new(order), null)
			ui.show_podium(m["totals"], _lobby["players"] if _lobby != null else [], my_id, _is_host())
			_update_chrome()
		"states":
			for s: Array in m["s"]:
				var p: ClientPlayer = players.get(s[0])
				if p:
					p.net_p = Vector3(s[1], s[2], s[3])
					p.net_yaw = s[4]
					p.net_flags = int(s[5])
					p.net_v = Vector3(s[6], s[7], s[8])
		"game":
			if _phase == "round" and _game:
				_game.on_message(m["m"])
		"damage":
			var p: ClientPlayer = players.get(m["id"])
			if p:
				var hp: Array = m["hit"]["pos"]
				var local := Vector3(hp[0], hp[1], hp[2])
				p.chr.add_hit(local, m["hit"]["r"])
				particles.burst(p.chr.to_global(local), 8, [p.color, 0xffffff], 4.0, 0.1, 0.6)
				if m["id"] == my_id:
					sfx.hurt()
		"heal":
			var p: ClientPlayer = players.get(m["id"])
			if p:
				p.chr.heal(int(m["n"]))
		"impulse":
			var v: Array = m["v"]
			body.vx = v[0]
			body.vy = v[1]
			body.vz = v[2]
			body.tumble = m["tumble"]
			body.grounded = false
			body.coyote = 0.0
			_shake = maxf(_shake, 0.6)
		"teleport":
			var tp: Array = m["p"]
			teleport(tp[0], tp[1], tp[2])


# ---------- boucle ----------

static func _lerp_angle(a: float, b: float, k: float) -> float:
	return a + atan2(sin(b - a), cos(b - a)) * k


static func _b2i(v: bool) -> float:
	return 1.0 if v else 0.0


func _process(delta: float) -> void:
	var dt := clampf(delta, 0.001, 0.05)
	var t := net.now()
	input.begin_frame()
	_debug.drive(dt)

	if _phase == "menu":
		_menu_frame(dt)
		input.end_frame()
		return

	# caméra : souris, ou flèches du clavier
	cam_yaw -= input.dx * 0.0028 * Config.mouse_sens + (_b2i(input.down("ArrowRight")) - _b2i(input.down("ArrowLeft"))) * 2.0 * dt
	_cam_pitch += input.dy * 0.0022 * Config.mouse_sens + (_b2i(input.down("ArrowUp")) - _b2i(input.down("ArrowDown"))) * 1.2 * dt
	_cam_pitch = clampf(_cam_pitch, -0.3, 1.3)

	var mine := me()
	if _game:
		_cols = _game.colliders(t)
		if _active:
			var frozen := _phase == "round" and t < start_at
			var f := _b2i(input.down("KeyW")) - _b2i(input.down("KeyS"))
			var r := _b2i(input.down("KeyD")) - _b2i(input.down("KeyA"))
			var fx := sin(cam_yaw)
			var fz := cos(cam_yaw)
			var mx := fx * f - fz * r
			var mz := fz * f + fx * r
			var length := sqrt(mx * mx + mz * mz)
			if length > 1.0:
				mx /= length
				mz /= length
			if frozen:
				mx = 0.0
				mz = 0.0
			var jump := not frozen and input.down("Space")
			_acc = minf(_acc + dt, 4.0 * H)
			while _acc >= H:
				_acc -= H
				_game.pre_step(body, H)
				var contacts := Phys.step_body(body, mx, mz, jump, _cols, H)
				for p: ClientPlayer in players.values():
					if p != mine and p.pin == null and not p.hidden and not p.chr.dead:
						_game.jostle(body, p.pos, p.net_v)  # parcours : bousculade selon le réglage de la manche
				_game.post_step(body, contacts, H)
				if body.jumped:
					sfx.jump()
				if body.landed > 9.0:
					sfx.land()
			if _aim_mode:
				_my_yaw = _lerp_angle(_my_yaw, cam_yaw, 1.0 - exp(-18.0 * dt))
			elif mx != 0.0 or mz != 0.0:
				_my_yaw = _lerp_angle(_my_yaw, atan2(mx, mz), 1.0 - exp(-14.0 * dt))
	if mine and mine.pin == null:
		mine.pos = body.pos()
		mine.yaw = _my_yaw
		mine.flags = (Protocol.FLAG_GROUNDED if body.grounded or body.coyote > 0.0 else 0) | (Protocol.FLAG_TUMBLE if body.tumble > 0.0 else 0) | (Protocol.FLAG_CHARGING if _charging else 0) | (_game.pose_flags(body) if _game else 0)

	_send_acc += dt
	if _send_acc >= 1.0 / 30.0 and my_id != "":
		_send_acc = 0.0
		net.send_raw('{"t":"state","s":[%.2f,%.2f,%.2f,%.2f,%d,%.2f,%.2f,%.2f]}' % [body.px, body.py, body.pz, _my_yaw, mine.flags if mine else 0, body.vx, body.vy, body.vz])

	for p: ClientPlayer in players.values():
		var is_me := p == mine
		var speed := 0.0
		var vy := 0.0
		var flags := Protocol.FLAG_GROUNDED
		var dance := false
		if p.pin != null:
			p.pos = p.pin["p"]
			p.yaw = p.pin["yaw"]
			dance = p.pin["dance"]
		elif is_me:
			speed = sqrt((body.vx - body.gvx) ** 2 + (body.vz - body.gvz) ** 2)
			vy = body.vy
			flags = p.flags
		else:
			# autres joueurs : on glisse vers la dernière position reçue, légèrement extrapolée
			var target := p.net_p + p.net_v * 0.05
			if p.pos.distance_squared_to(target) > 36.0:
				p.pos = target
			else:
				p.pos = p.pos.lerp(target, 1.0 - exp(-16.0 * dt))
			p.yaw = _lerp_angle(p.yaw, p.net_yaw, 1.0 - exp(-12.0 * dt))
			speed = sqrt(p.net_v.x * p.net_v.x + p.net_v.z * p.net_v.z)
			vy = p.net_v.y
			flags = p.net_flags
			p.flags = flags
		var chr := p.chr
		chr.visible = not p.hidden and (not _waiting or is_me) and _phase != "boot"
		chr.position = p.pos
		chr.rotation.y = p.yaw
		if chr.visible:
			chr.update(dt, speed, vy, flags & Protocol.FLAG_GROUNDED != 0, flags & Protocol.FLAG_TUMBLE != 0, flags & Protocol.FLAG_CHARGING != 0, dance)
		# ombre « blob » sur le sol le plus proche en dessous (graphismes légers ; sinon les vraies ombres suffisent)
		var gy := -INF
		if chr.visible and Config.quality == 0:
			gy = Phys.ground_below(p.pos.x, p.pos.y + 0.3, p.pos.z, _cols)
		p.shadow.visible = gy > -INF and p.pos.y - gy < 12.0
		if p.shadow.visible:
			p.shadow.position = Vector3(p.pos.x, gy + 0.03, p.pos.z)
			var sc := maxf(0.35, 1.0 - (p.pos.y - gy) * 0.08)
			p.shadow.scale = Vector3(sc, 1, sc)

	# caméra troisième personne
	var dist: float = _spectate["dist"] if _spectate != null else 7.0
	var focus: Vector3 = _spectate["target"] if _spectate != null else Vector3(body.px, body.py + 1.3, body.pz)
	if _cam_target.distance_squared_to(focus) > 900.0:
		_cam_target = focus
	else:
		_cam_target = _cam_target.lerp(focus, 1.0 - exp(-14.0 * dt))
	var ch := cos(_cam_pitch) * dist
	var cam_pos := Vector3(_cam_target.x - sin(cam_yaw) * ch, _cam_target.y + sin(_cam_pitch) * dist + 0.4, _cam_target.z - cos(cam_yaw) * ch)
	if _shake > 0.01:
		cam_pos.x += (randf() - 0.5) * _shake
		cam_pos.y += (randf() - 0.5) * _shake
		_shake *= exp(-7.0 * dt)
	camera.look_at_from_position(cam_pos, _cam_target + Vector3(0, 0.4, 0))

	if _game:
		_game.on_frame(dt)

	# compte à rebours de début de manche
	if _phase == "round" and ui.banner_visible():
		var left := start_at - t
		var n := ceili(left)
		if n != _last_count:
			_last_count = n
			if n > 0 and n <= 3:
				ui.set_count(str(n))
				sfx.tick()
			elif n <= 0:
				ui.set_count("GO !")
				sfx.go()
			else:
				ui.set_count("")
		if left < -0.8:
			ui.hide_banner()

	particles.update(dt)
	env.update(t, _cam_target, dt)
	input.end_frame()


## Image du menu principal : le décor vit, la caméra glisse vers le cadrage de l'écran affiché.
func _menu_frame(dt: float) -> void:
	if _game is MenuScene:
		var shot: Array = _game.camera_shot()
		if not _menu_cam_set:
			_menu_cam = shot.duplicate()
			_menu_cam_set = true
		var k := 1.0 - exp(-3.5 * dt)
		_menu_cam[0] = _menu_cam[0].lerp(shot[0], k)
		_menu_cam[1] = _menu_cam[1].lerp(shot[1], k)
		camera.look_at_from_position(_menu_cam[0], _menu_cam[1])
		_cam_target = _menu_cam[1]
	if _game:
		_game.on_frame(dt)
	particles.update(dt)
	env.update(net.now(), _cam_target, dt)
