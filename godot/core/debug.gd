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
##   --travel         traveling : la caméra suit le chemin du niveau de parcours, du départ à l'arrivée, puis quitte
##     (avec --write-movie video.avi --fixed-fps 30 : vidéo du niveau)
##   --pano           panoramique : vue large et en hauteur de tout le niveau de parcours (départ à gauche, arrivée à
##     droite), sans interface ; à combiner avec --shot et --resolution (ex. 2400x800)
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
var _travel: PackedVector3Array  # chemin lissé du traveling
var _travel_cum: PackedFloat32Array  # longueur cumulée le long du chemin
var _travel_s := 0.0
var _travel_end := -1.0
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
	if Config.args.has("travel"):
		_travel_tick(dt)
	if Config.args.has("pano"):
		_pano_tick()
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


## Traveling : la caméra file le long du chemin (départ → arrivée), en regardant devant elle, sans interface.
func _travel_tick(dt: float) -> void:
	if main._phase != "round" or not main._game is ParkourClient:
		return
	if _travel.is_empty():
		_travel_build((main._game as ParkourClient).level)
		main.ui.visible = false
		main.cam_yaw = _travel_yaw_at(0.0)
		if _travel.is_empty():
			return
	var total := _travel_cum[_travel_cum.size() - 1]
	if _travel_end < 0.0:
		_travel_s = minf(total, _travel_s + 6.5 * dt)
		if _travel_s >= total:
			_travel_end = _t + 2.5
	elif _t >= _travel_end:
		get_tree().quit()
		return
	main.set_spectate(_travel_at(_travel_s), 11.0)
	main._cam_pitch = 0.5
	main.cam_yaw = Main._lerp_angle(main.cam_yaw, _travel_yaw_at(_travel_s), 1.0 - exp(-1.8 * dt))


## Panoramique : caméra fixe, de côté et en hauteur, à la distance qui fait tenir tout le chemin dans l'image.
func _pano_tick() -> void:
	if main._phase != "round" or not main._game is ParkourClient:
		return
	if _travel.is_empty():
		_travel_build((main._game as ParkourClient).level)
		main.ui.visible = false
		main.env._cam_attr.dof_blur_far_enabled = false
		if _travel.is_empty():
			return
	var a := _travel[0]
	var b := _travel[_travel.size() - 1]
	var d := Vector2(b.x - a.x, b.z - a.z)
	d = d.normalized() if d.length() > 1.0 else Vector2(0, 1)
	var side := Vector2(-d.y, d.x)
	# étendue du chemin : le long du sens départ → arrivée, en travers et en hauteur
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p: Vector3 in _travel:
		var q := Vector3(Vector2(p.x, p.z).dot(d), p.y, Vector2(p.x, p.z).dot(side))
		lo = lo.min(q)
		hi = hi.max(q)
	var mid := (lo + hi) / 2.0
	var target := Vector3(d.x * mid.x + side.x * mid.z, mid.y, d.y * mid.x + side.y * mid.z)
	var pitch := 0.6
	var vfov := deg_to_rad(58.0)
	var aspect := main.get_viewport().get_visible_rect().size.aspect()
	var hfov := 2.0 * atan(tan(vfov / 2.0) * aspect)
	var length := hi.x - lo.x + 16.0
	var height := (hi.y - lo.y) * cos(pitch) + (hi.z - lo.z) * sin(pitch) + 8.0
	var dist := maxf(length / 2.0 / tan(hfov / 2.0), height / 2.0 / tan(vfov / 2.0)) + (hi.z - lo.z) / 2.0
	main.set_spectate(target, dist)
	main._cam_pitch = pitch
	# la droite de l'image suit le sens départ → arrivée
	main.cam_yaw = atan2(d.y, -d.x)


func _travel_build(level: Dictionary) -> void:
	var els: Array = level["elements"]
	var ids: Array = LevelValidate.validate(level)["path"]
	var pts: Array = []
	for i: int in ids:
		var e: Dictionary = els[i]
		var p := Vector3(e["pos"][0], Level.top_of(e) + 0.6, e["pos"][2])
		if pts.is_empty() or (pts[-1] as Vector3).distance_to(p) > 0.5:
			pts.append(p)
	if pts.size() < 2:
		return
	# courbe de Catmull-Rom passant par les éléments du chemin : pas d'à-coups dans les virages
	_travel = PackedVector3Array()
	for i in pts.size() - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, pts.size() - 1)]
		for k in 12:
			var u := k / 12.0
			_travel.append(0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u * u * u))
	_travel.append(pts[-1])
	_travel_cum = PackedFloat32Array([0.0])
	for i in range(1, _travel.size()):
		_travel_cum.append(_travel_cum[i - 1] + _travel[i].distance_to(_travel[i - 1]))


func _travel_at(s: float) -> Vector3:
	var i := clampi(_travel_cum.bsearch(s) - 1, 0, _travel.size() - 2)
	var seg := maxf(1e-4, _travel_cum[i + 1] - _travel_cum[i])
	return _travel[i].lerp(_travel[i + 1], clampf((s - _travel_cum[i]) / seg, 0.0, 1.0))


## Cap regardé : vers le point du chemin 6 m plus loin.
func _travel_yaw_at(s: float) -> float:
	var total := _travel_cum[_travel_cum.size() - 1]
	var a := _travel_at(s)
	var b := _travel_at(minf(total, s + 6.0))
	if Vector2(b.x - a.x, b.z - a.z).length() < 0.3:
		a = _travel_at(maxf(0.0, s - 6.0))
	return atan2(b.x - a.x, b.z - a.z)


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
