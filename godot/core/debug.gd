class_name Debug
extends Node
## Aides au test en ligne de commande (après `--`) :
##   --bots=9          remplit le lobby de bots (si l'on est l'hôte)
##   --autostart       lance la partie dès que les bots sont là
##   --games=mortar --rounds=1   restreint les jeux et le nombre de manches (si l'on est l'hôte)
##   --set=mortar.buildTime=5,parkour.duration=45   règle des options de jeu (si l'on est l'hôte) ;
##     liste avec « | » : parkour.levels=maison|ciel (ou maison| pour un seul niveau)
##   --auto            pilote automatique : court vers l'avant, saute et tire de temps en temps
##   --auto=fire       pilote automatique immobile : pose des blocs puis tire
##   --hits --die      perce la peau des personnages à 3 s, puis les réduit en tas d'os à 6 s
##   --shot=chemin.png --shot-at=5,12   captures d'écran à ces instants (secondes), puis quitte
##   --quit-at=30      quitte après ce délai
##   --use-at=14,20    envoie « utiliser l'objet » (parcours) à ces instants
##   --looks=x,y,z,yaw,pitch,dist;…   vue imposée 1.2 s avant chaque capture (dist = 0 : téléporte le joueur en x,y,z)
##   --menu=jouer|creer|personnage|options   ouvre directement cet écran du menu principal
##   --reglages=partie|parkour|mortar|serveur   ouvre la fenêtre des réglages de la partie au lobby, sur cet onglet
##   --keys=2:ui_down,2.5:ui_accept,3:joy0   actions d'interface ou boutons de manette (joyN) simulés à ces instants
##   --trace           affiche l'état du joueur et les performances à chaque capture
##   --perf=chemin.csv journal des performances toutes les 0,5 s (images/s, pire image, mémoire, objets, corps physiques)
##   --stress=40       pire cas des effets physiques à cet instant : tous les personnages meurent et 2 blocs éclatent sur chaque île (160 éclats, le plafond)
##   --quality=basse|moyenne|haute, --name=…, --hat=…, --no-save, --vsync=off

var main: Main
var _bots_applied := false
var _autostarted := false
var _settings_applied := false
var _settings_shown := false
var _shots: Array = []
var _shot_path := ""
var _shot_count := 0
var _t := 0.0
var _auto := false
var _quit_at := -1.0
var _looks: Array = []
var _uses: Array = []
var _look_at := 0
var _keys: Array = []  # [instant, action]
var _perf: FileAccess
var _perf_acc := 0.0
var _perf_frames := 0
var _perf_worst := 0.0


func _ready() -> void:
	_auto = Config.args.has("auto")
	_shot_path = Config.args.get("shot", "")
	if _shot_path != "":
		for s: String in str(Config.args.get("shot-at", "5")).split(",", false):
			_shots.append(float(s))
		_shot_count = _shots.size()
	if Config.args.has("vsync"):
		DisplayServer.window_set_vsync_mode({"mailbox": DisplayServer.VSYNC_MAILBOX, "adaptive": DisplayServer.VSYNC_ADAPTIVE, "off": DisplayServer.VSYNC_DISABLED}.get(Config.args["vsync"], DisplayServer.VSYNC_ENABLED))
	for l: String in str(Config.args.get("looks", "")).split(";", false):
		_looks.append(Array(l.split_floats(",")))
	for u: String in str(Config.args.get("use-at", "")).split(",", false):
		_uses.append(float(u))
	for k: String in str(Config.args.get("keys", "")).split(",", false):
		var parts := k.split(":")
		_keys.append([float(parts[0]), parts[1]])
	if Config.args.has("quit-at"):
		_quit_at = float(Config.args["quit-at"])
	if Config.args.has("perf"):
		_perf = FileAccess.open(str(Config.args["perf"]), FileAccess.WRITE)
		_perf.store_line("t;phase;fps;pire_ms;process_ms;physique_ms;objets;noeuds;orphelins;ressources;memoire_mo;corps_actifs;corps_debris;dessins")


func on_lobby(m: Dictionary) -> void:
	if Config.args.has("reglages") and not _settings_shown:
		_settings_shown = true
		main.ui.open_game_settings(str(Config.args["reglages"]))
	if m["hostId"] != main.my_id:
		return
	if not _settings_applied and (Config.args.has("games") or Config.args.has("rounds") or Config.args.has("set")):
		_settings_applied = true
		var s: Dictionary = m["settings"].duplicate(true)
		if Config.args.has("games"):
			s["games"] = Array(str(Config.args["games"]).split(",", false))
		if Config.args.has("rounds"):
			s["rounds"] = Config.arg_int("rounds")
		for kv: String in str(Config.args.get("set", "")).split(",", false):
			var key := kv.get_slice("=", 0)
			var game := key.get_slice(".", 0)
			if not s["game"].has(game):
				s["game"][game] = {}
			var val := kv.get_slice("=", 1)
			if val.contains("|"):
				s["game"][game][key.get_slice(".", 1)] = Array(val.split("|", false))  # liste : parkour.levels=maison|ciel
			else:
				s["game"][game][key.get_slice(".", 1)] = float(val) if val.is_valid_float() else val  # parkour.mode=best
		main.net.send({"t": "settings", "settings": s})
		return
	var want := Config.arg_int("bots")
	if not _bots_applied and want > 0:
		_bots_applied = true
		main.net.send({"t": "bots", "n": want})
		return
	if Config.args.has("autostart") and not _autostarted and (want == 0 or m["players"].size() > 1):
		_autostarted = true
		main.net.send({"t": "start"})


## Simule des entrées quand le pilote automatique est actif.
func drive(_dt: float) -> void:
	if not _auto:
		return
	var inp := main.input
	if Config.args["auto"] != "fire":
		inp._keys["KeyW"] = true
		if fmod(_t, 1.3) < 0.2:
			inp._keys["Space"] = true
		else:
			inp._keys.erase("Space")
	# clics périodiques : pose de blocs puis tirs dans le mortier
	var ph := fmod(_t, 1.6)
	if ph < 0.7:
		if not inp._keys.has("KeyF"):
			inp._pressed["KeyF"] = true
		inp._keys["KeyF"] = true
	elif inp._keys.erase("KeyF"):
		inp._released["KeyF"] = true
	inp.dx += 2.0 if Config.args["auto"] != "fire" else 0.5


func _process(dt: float) -> void:
	var before := _t
	_t += dt
	if _perf:
		_log_perf(dt)
	if Config.args.has("hits") and before < 3.0 and _t >= 3.0:
		for p: ClientPlayer in main.players.values():
			p.chr.add_hit(Vector3(0.12, 1.0, 0.2), 0.2)
			p.chr.add_hit(Vector3(-0.2, 0.7, 0.15), 0.14)
			p.chr.add_hit(Vector3(0.0, 1.35, 0.1), 0.12)
	if Config.args.has("die") and before < 6.0 and _t >= 6.0:
		for p: ClientPlayer in main.players.values():
			p.chr.die()
	var st := float(Config.args.get("stress", "-1"))
	if st > 0.0 and before < st and _t >= st:
		_stress()
	while not _keys.is_empty() and _t >= _keys[0][0]:
		var a: String = _keys.pop_front()[1]
		for pressed in [true, false]:
			if a.begins_with("joy"):
				var jb := InputEventJoypadButton.new()
				jb.button_index = int(a.substr(3)) as JoyButton
				jb.pressed = pressed
				Input.parse_input_event(jb)
			else:
				var ev := InputEventAction.new()
				ev.action = a
				ev.pressed = pressed
				Input.parse_input_event(ev)
	if not _uses.is_empty() and _t >= _uses[0]:
		_uses.pop_front()
		main.send_game({"t": "use"})
	if not _shots.is_empty() and _look_at < _looks.size() and _look_at == _shot_count - _shots.size() and _t >= _shots[0] - 1.2:
		_apply_look(_looks[_look_at])
		_look_at += 1
	if not _shots.is_empty() and _t >= _shots[0]:
		_shots.pop_front()
		_capture(_shots.is_empty())
	if _quit_at > 0.0 and _t >= _quit_at:
		get_tree().quit()


func _apply_look(l: Array) -> void:
	if l.size() < 6:
		return
	main.cam_yaw = l[3]
	main._cam_pitch = l[4]
	if l[5] <= 0.0:
		main.set_spectate(null)
		main.teleport(l[0], l[1], l[2])
	else:
		main.set_spectate(Vector3(l[0], l[1], l[2]), l[5])


func _capture(last: bool) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _shot_path
	if _shot_count > 1:
		path = path.replace(".png", "_%d.png" % (_shot_count - _shots.size()))
	img.save_png(path)
	print("capture : ", path)
	if Config.args.has("trace"):
		print("images/s : %d (rendu %s, qualité %s)" % [Engine.get_frames_per_second(), RenderingServer.get_current_rendering_method(), Config.QUALITY_NAMES[Config.quality]])
		print("écran : %d Hz, fenêtre active : %s" % [DisplayServer.screen_get_refresh_rate(), DisplayServer.window_is_focused()], " vsync=", DisplayServer.window_get_vsync_mode())
		print("appels de dessin : %d, triangles : %d, objets : %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		var b := main.body
		var me := main.me()
		print("corps p=(%.2f, %.2f, %.2f) v=(%.2f, %.2f, %.2f) sol=%s yaw=%.3f phase=%s" % [b.px, b.py, b.pz, b.vx, b.vy, b.vz, b.grounded, main._my_yaw, main._phase])
		if me:
			print("perso pos=", me.chr.position, " rot=", me.chr.rotation, " squash=", me.chr._squash.scale, " pivot=", me.chr._pivot.transform, " sq=", me.chr._sq, " spin=", me.chr._spin, " visible=", me.chr.visible)
	if last and _quit_at < 0.0:
		get_tree().quit()


## Une ligne du journal `--perf` toutes les 0,5 s : moyenne des images/s, pire image de la fenêtre, compteurs du moteur.
func _log_perf(dt: float) -> void:
	_perf_acc += dt
	_perf_frames += 1
	_perf_worst = maxf(_perf_worst, dt)
	if _perf_acc < 0.5:
		return
	var deb := Debris.current
	_perf.store_line("%.1f;%s;%.1f;%.1f;%.2f;%.2f;%d;%d;%d;%d;%.1f;%d;%d;%d" % [
		_t, main._phase, _perf_frames / _perf_acc, _perf_worst * 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), deb._bodies.size() if deb else 0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	_perf.flush()
	_perf_acc = 0.0
	_perf_frames = 0
	_perf_worst = 0.0


## `--stress` : le pire cas des effets physiques d'un coup (squelettes de tout le monde + éclats au plafond).
func _stress() -> void:
	for p: ClientPlayer in main.players.values():
		p.chr.die()
	var deb := Debris.current
	if deb == null or not (main._game is MortarClient):
		return
	var g: MortarClient = main._game
	var mat: Material = g.inst["wood"].material_override
	for i in g.n:
		var c := MortarShared.plot_center(i, g.n)
		for k in 2:
			var p := c + Vector3(randf_range(-3, 3), 0.5 + (k % 4), randf_range(-3, 3))
			deb.shatter(p, Basis(Vector3.UP, MortarShared.plot_yaw(i, g.n)), 0.98, mat, c + Vector3(0, -0.5, 0))
