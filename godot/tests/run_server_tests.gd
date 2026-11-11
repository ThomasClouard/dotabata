extends SceneTree
## Tests du serveur GDScript : parties complètes jouées par des bots (vraie physique, vraies règles), interactions du
## parcours avec de faux joueurs, bataille de mortier. Portage des anciens tests vitest du serveur Node.
##   godot --headless --path godot -s res://tests/run_server_tests.gd
## Option : `-- --only=balade,mortier` pour ne lancer que certains cas.

var _fails := 0
var _checks := 0
var _only: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.trim_prefix("--only=").split(",")
	var t0 := Time.get_ticks_msec()
	_test_session_rules()
	_test_vague3_rules()
	if _wants("modes"):
		_test_modes()
	if _wants("balade-meilleur-temps"):
		# les bots repartent du départ après chaque arrivée : plusieurs arrivées par bot
		var log := _test_bots("balade (meilleur temps)", LevelStore.read_level("balade"), 4, 200.0, 6, {"mode": "best"})
		_ok(log.any(func(m: Dictionary) -> bool: return m["t"] == "finish" and m["runs"] >= 2), "meilleur temps : un bot arrivé au moins deux fois")
	for lv: String in ["balade", "usine", "vertige", "fete-foraine", "volcan", "labo", "chateau"]:
		if _wants(lv):
			var need := 1 if lv in ["balade", "usine", "vertige"] else 3
			_test_bots(lv, LevelStore.read_level(lv), 6, 260.0, need)
	if _wants("vague1"):
		_test_bots("vague1", _fixture("vague1"), 6, 300.0, 1)
	if _wants("vague2"):
		_test_bots("vague2", _fixture("vague2"), 6, 220.0, 4)
	for jostle: bool in [true, false]:
		if _wants("vague3"):
			var log := _test_bots("vague3 (bousculades %s)" % ("oui" if jostle else "non"), _fixture("vague3"), 6, 170.0, 4, {"jostle": jostle})
			_ok(log.any(func(m: Dictionary) -> bool: return m["t"] == "open" and m["link"] == "porte1"), "vague3 : porte ouverte par un bot")
			_ok(log.any(func(m: Dictionary) -> bool: return m["t"] == "safe"), "vague3 : dalle mémoire révélée")
			_ok(log.any(func(m: Dictionary) -> bool: return m["t"] == "coin"), "vague3 : pièce ramassée")
	if _wants("bug-manege"):
		for pass_i in 3:
			_test_bots("bug-manege #%d" % pass_i, _fixture("bug-manege"), 6, 40.0, 5)
	if _wants("bug-barre"):
		_test_bug_barre()
	if _wants("mortier"):
		_test_mortar()
	if _wants("espace"):
		_test_space()
	print("%d vérifications, %d échec(s) en %.1f s" % [_checks, _fails, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if _fails > 0 else 0)


func _wants(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _ok(cond: bool, what: String) -> bool:
	_checks += 1
	if not cond:
		_fails += 1
		print("ÉCHEC ", what)
	return cond


func _eq(a: Variant, b: Variant, what: String) -> bool:
	return _ok(a == b, "%s : obtenu %s, attendu %s" % [what, a, b])


func _fixture(name: String) -> Dictionary:
	var f := ProjectSettings.globalize_path("res://").path_join("../tests/fixtures/parkour/%s.json" % name)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(f))
	var lv := LevelStore.normalize(raw)
	lv["name"] = name
	return lv


## Banc d'essai sans réseau (portage de tests/sim.ts) : horloge, journal des messages diffusés, impulsions.
class Harness extends RefCounted:
	var t := 0.0
	var ended := false
	var log: Array = []
	var impulses: Array = []
	var ctx := ServerCtx.new()
	var game: ServerGame
	var init := {}

	func _init(settings: Dictionary, n: int, bots: bool, start_at := 1.0) -> void:
		for i in n:
			var p := ServerPlayer.new()
			p.id = ("b%d" if bots else "p%d") % i
			p.name = "Joueur %d" % i
			p.is_bot = bots
			p.flags = Protocol.FLAG_GROUNDED
			ctx.players[p.id] = p
		ctx.settings = settings
		ctx.start_at = start_at
		ctx._now = func() -> float: return t
		ctx._broadcast = func(m: Dictionary) -> void:
			var c := m.duplicate()
			c["at_"] = t
			log.append(c)
		ctx._send = func(_id: String, _m: Dictionary) -> void: pass
		ctx._damage = func(id: String, hit: Dictionary) -> void: log.append({"t": "damage", "id": id, "hit": hit})
		ctx._heal = func(_id: String, _n: int) -> void: pass
		ctx._impulse = func(id: String, v: Array, tumble: float) -> void:
			impulses.append({"id": id, "v": v, "tumble": tumble})
			var p: ServerPlayer = ctx.players[id]
			if p.body != null:
				ServerCtx.impulse_body(p.body, v, tumble)
		ctx._teleport = func(id: String, pos: Array) -> void:
			var p: ServerPlayer = ctx.players[id]
			if p.body != null:
				p.body.set_pos(pos[0], pos[1], pos[2])
		ctx._end = func() -> void: ended = true

	func of(ty: String) -> Array:
		return log.filter(func(m: Dictionary) -> bool: return m["t"] == ty)

	func player(id: String) -> ServerPlayer:
		return ctx.players[id]

	## Pose un faux joueur (position de l'état réseau, au sol, immobile).
	func put(id: String, p: Array, extra := {}) -> void:
		var pl: ServerPlayer = ctx.players[id]
		pl.p = [float(p[0]), float(p[1]), float(p[2])]
		pl.v = [0.0, 0.0, 0.0]
		pl.flags = Protocol.FLAG_GROUNDED
		for k: String in extra:
			pl.set(k, extra[k])

	## Avance l'horloge jusqu'à `to` par pas de 1/30 s (sans bots).
	func tick(to: float) -> void:
		while t < to - 1e-9:
			t = roundf((t + 1.0 / 30.0) * 1e6) / 1e6
			game.on_tick(1.0 / 30.0)

	## Partie complète jouée par les bots.
	func simulate(max_seconds: float) -> void:
		for p: ServerPlayer in ctx.players.values():
			p.body = Phys.make_body(p.p[0], p.p[1], p.p[2])
		var dt := 1.0 / 30.0
		while not ended and t < max_seconds:
			t += dt
			if t >= ctx.start_at:
				for p: ServerPlayer in ctx.players.values():
					game.bot_tick(p, dt)
					p.sync_from_body()
			game.on_tick(dt)


static func parkour_settings(extra := {}) -> Dictionary:
	var s := Scoring.default_game_settings(GameMetas.PARKOUR)
	s.merge(extra, true)
	return s


func _parkour(level: Dictionary, settings: Dictionary, n: int, bots: bool) -> Harness:
	var h := Harness.new(settings, n, bots)
	var g := ParkourServer.new(h.ctx)
	h.game = g
	var res := g.start_with(level)
	h.init = res["init"]
	for id: String in res["spawns"]:
		var s: Array = res["spawns"][id]
		h.player(id).p = [s[0], s[1], s[2]]
	return h


func _test_bots(what: String, level: Dictionary, n: int, max_s: float, need: int, extra := {}) -> Array:
	var t0 := Time.get_ticks_msec()
	_ok(not level.is_empty() and LevelValidate.validate(level)["ok"], what + " : niveau terminable")
	var h := _parkour(level, parkour_settings({"duration": max_s - 20.0, "hurry": max_s - 20.0}.merged(extra, true)), n, true)
	h.simulate(max_s)
	var finished := h.of("finish").size()
	var results := h.game.get_results()
	_ok(finished >= need, "%s : %d arrivée(s), au moins %d attendue(s) — %s" % [what, finished, need, JSON.stringify(results)])
	_eq(results.size(), n, what + " : lignes du classement")
	_eq(results[0]["rank"], 0, what + " : premier rang")
	print("%s : %d/%d arrivés en %.1f s de jeu (%.1f s)" % [what, finished, n, h.t, (Time.get_ticks_msec() - t0) / 1000.0])
	return h.log


## Non-régression : bot posé sur la barre basse d'un balayeur, il en descend et repart.
func _test_bug_barre() -> void:
	var h := _parkour(_fixture("bug-barre"), parkour_settings({"duration": 60, "hurry": 60}), 1, true)
	h.ctx.start_at = 0.0
	h.t = 1.0
	var bot := h.player("b0")
	bot.body = Phys.make_body(0.0, 0.62, 13.0)
	var on_bar := 0.0
	var max_z := 0.0
	var dt := 1.0 / 30.0
	for i in 90:
		h.t += dt
		h.game.bot_tick(bot, dt)
		bot.sync_from_body()
		if bot.body.grounded and bot.body.ground_id == 2:
			on_bar += dt
		max_z = maxf(max_z, bot.body.pz)
	_ok(on_bar < 1.0, "bug-barre : resté %.2f s sur la barre" % on_bar)
	_ok(max_z > 17.0, "bug-barre : parti vers l'arrivée (z max %.2f)" % max_z)
	print("bug-barre : OK")


func _test_mortar() -> void:
	var s := Scoring.default_game_settings(GameMetas.MORTAR)
	s.merge({"buildTime": 5, "battleTime": 90, "shrink": 30}, true)
	var h := Harness.new(s, 5, true)
	var g := MortarServer.new(h.ctx)
	h.game = g
	var res := g.on_start()
	for id: String in res["spawns"]:
		var sp: Array = res["spawns"][id]
		h.player(id).p = [sp[0], sp[1], sp[2]]
	h.simulate(120.0)
	_ok(h.ended, "mortier : la bataille se termine")
	_ok(not h.of("block").is_empty(), "mortier : des blocs construits")
	_ok(h.of("shell").size() > 10, "mortier : plus de 10 obus (%d)" % h.of("shell").size())
	_ok(not h.of("boom").is_empty(), "mortier : des explosions")
	_ok(not h.of("hp").is_empty(), "mortier : des dégâts")
	var results := g.get_results()
	_eq(results.size(), 5, "mortier : lignes du classement")
	var ids := {}
	for r: Dictionary in results:
		ids[r["id"]] = true
	_eq(ids.size(), 5, "mortier : joueurs distincts")
	_ok(results.any(func(r: Dictionary) -> bool: return r["rank"] == 0), "mortier : un vainqueur")
	print("mortier : %d obus, %d explosions, fin à %.1f s" % [h.of("shell").size(), h.of("boom").size(), h.t])


func _space(n: int, bots: bool, extra := {}) -> Harness:
	var s := Scoring.default_game_settings(GameMetas.SPACE)
	s.merge(extra, true)
	var h := Harness.new(s, n, bots)
	var g := SpaceServer.new(h.ctx)
	h.game = g
	var res := g.start_with(1234)
	h.init = res["init"]
	for id: String in res["spawns"]:
		var sp: Array = res["spawns"][id]
		h.player(id).p = [sp[0], sp[1], sp[2]]
	return h


static func _surface(pl: Dictionary) -> Array:
	var c := SpaceShared.v3(pl["c"])
	var p := c + Vector3.UP * float(pl["r"])
	return [p.x, p.y, p.z]


func _test_space() -> void:
	# planètes : déterministes, séparées, plus loin = plus de points
	var a := SpaceShared.layout(7, 10)
	_eq(JSON.stringify(a), JSON.stringify(SpaceShared.layout(7, 10)), "espace : placement déterministe")
	_eq(a.size(), 11, "espace : départ + 10 planètes")
	var gap := INF
	for i in a.size():
		for j in range(i + 1, a.size()):
			gap = minf(gap, SpaceShared.v3(a[i]["c"]).distance_to(SpaceShared.v3(a[j]["c"])) - a[i]["r"] - a[j]["r"])
	_ok(gap > 8.0, "espace : planètes bien séparées (écart min %.1f m)" % gap)
	var mono := true
	for i in range(2, a.size()):
		if a[i]["pts"] < a[i - 1]["pts"] or SpaceShared.v3(a[i]["c"]).length() < SpaceShared.v3(a[i - 1]["c"]).length() - 13.0:
			mono = false
	_ok(mono, "espace : points croissants avec la distance")
	_eq([a[1]["pts"], a[10]["pts"]], [1, 5], "espace : de 1 à 5 points")
	# 16 planètes en couloirs : séparées, et chaque lointaine a une proche dans une direction voisine
	var b := SpaceShared.layout(3, 16)
	var gap16 := INF
	var lanes_ok := true
	for i in range(1, b.size()):
		var ci := SpaceShared.v3(b[i]["c"])
		for j in range(i + 1, b.size()):
			gap16 = minf(gap16, ci.distance_to(SpaceShared.v3(b[j]["c"])) - b[i]["r"] - b[j]["r"])
		if i > 8:
			var near_ok := false
			for j in range(1, 9):
				if ci.angle_to(SpaceShared.v3(b[j]["c"])) < deg_to_rad(15.0):
					near_ok = true
			lanes_ok = lanes_ok and near_ok
	_ok(gap16 > 8.0, "espace : 16 planètes bien séparées (écart min %.1f m)" % gap16)
	_ok(lanes_ok, "espace : derrière chaque planète proche, une lointaine dans la même direction")
	# sans attraction : ligne droite ; avec : un tir rasant retombe
	var pr := SpaceShared.predict(Vector3(0, 13, 0), Vector3(0, 0, 30), a.slice(0, 1), false, 2.0)
	var last: Vector3 = pr["pts"][pr["pts"].size() - 1]
	_ok(absf(last.y - 13.0) < 1e-3 and absf(last.z - SpaceShared.SPEED * 2.0) < 0.6, "espace : vol droit à vitesse fixe sans attraction (%s)" % last)
	pr = SpaceShared.predict(Vector3(0, 13, 0), Vector3(0, 0, 30), a.slice(0, 1), true, 2.0)
	last = pr["pts"][pr["pts"].size() - 1]
	_ok(last.y < 12.0, "espace : avec attraction, la trajectoire se courbe vers la planète (%s)" % last)
	var s := SpaceShared.step(Vector3(0, 13, 0), Vector3(0, 0, 15), 0.5, a.slice(0, 1), false, Vector3.UP)
	_ok(absf(s[1].length() - SpaceShared.SPEED) < 1e-3, "espace : vitesse constante, même avec les rétro-fusées")
	_ok(s[1].angle_to(Vector3(0, 0, 1)) < deg_to_rad(4.0) and s[1].y > 0.0, "espace : les rétro-fusées font tourner la trajectoire")

	# vrais joueurs : atterrissage vérifié, classement points puis heure, fin quand tout le monde est posé
	var h := _space(3, false, {"aimTime": 10, "flightTime": 20})
	var g: SpaceServer = h.game
	g.on_player_message("p0", {"t": "launch"})
	_eq(h.of("launch").size(), 0, "espace : pas de décollage pendant le compte à rebours")
	h.tick(3.0)
	g.on_player_message("p0", {"t": "launch"})
	g.on_player_message("p0", {"t": "launch"})
	_eq(h.of("launch").size(), 1, "espace : décollage à la demande, une seule fois")
	h.tick(11.5)
	_eq(h.of("launch").size(), 3, "espace : décollage automatique des retardataires à la fin du temps")
	var last_i := g.planets.size() - 1
	h.put("p0", [0, 100, 0])
	g.on_player_message("p0", {"t": "landed", "planet": last_i})
	_eq(h.of("landed").size(), 0, "espace : atterrissage loin de la planète refusé")
	h.put("p0", _surface(g.planets[last_i]))
	g.on_player_message("p0", {"t": "landed", "planet": last_i})
	h.tick(12.0)
	h.put("p1", _surface(g.planets[1]))
	g.on_player_message("p1", {"t": "landed", "planet": 1})
	h.tick(13.0)
	h.put("p2", _surface(g.planets[1]))
	g.on_player_message("p2", {"t": "landed", "planet": 1})
	_eq(h.of("landed").size(), 3, "espace : trois atterrissages")
	_ok(not h.ended, "espace : petite pause avant la fin")
	h.tick(16.0)
	_ok(h.ended, "espace : fin quand tout le monde est posé")
	var res := g.get_results()
	_eq(res.map(func(r: Dictionary) -> String: return r["id"]), ["p0", "p1", "p2"], "espace : classement points puis heure")
	_ok(res[1]["label"].ends_with("11,0 s"), "espace : l'heure d'atterrissage est affichée (%s)" % res[1]["label"])
	_eq(res.map(func(r: Dictionary) -> int: return r["rank"]), [0, 1, 2], "espace : rangs")

	# personne ne se pose : perdu à la fin du vol
	h = _space(2, false, {"aimTime": 10, "flightTime": 15})
	g = h.game
	h.put("p0", [0, 60, 0])
	h.put("p1", [0, 500, 0])
	h.tick(11.6)
	_eq(h.of("lost").size(), 1, "espace : perdu hors de la zone")
	h.tick(25.0)
	_ok(not h.ended, "espace : le vol continue")
	h.tick(26.2)
	_ok(h.ended and h.of("lost").size() == 2, "espace : perdu à la fin du vol")
	_eq(g.get_results().map(func(r: Dictionary) -> int: return r["rank"]), [0, 0], "espace : perdus ex æquo")

	# parties de bots, avec et sans attraction
	for grav: bool in [true, false]:
		var t0 := Time.get_ticks_msec()
		h = _space(6, true, {"aimTime": 10, "gravity": grav})
		h.simulate(80.0)
		var landed := h.of("landed").filter(func(m: Dictionary) -> bool: return m["planet"] > 0)
		_ok(h.ended, "espace (attraction %s) : la manche se termine" % grav)
		_ok(landed.size() >= 3, "espace (attraction %s) : au moins 3 bots posés sur une planète d'arrivée (%d)" % [grav, landed.size()])
		_eq(h.game.get_results().size(), 6, "espace : lignes du classement")
		print("espace (attraction %s) : %d/6 posés, %d retombés, %d perdus, fin à %.1f s (%.1f s) — %s" % [grav, landed.size(), h.of("landed").size() - landed.size(), h.of("lost").size(), h.t, (Time.get_ticks_msec() - t0) / 1000.0, JSON.stringify(h.game.get_results().map(func(r: Dictionary) -> String: return r["label"]))])


# ---------- règles de session ----------

func _test_session_rules() -> void:
	_eq(Scoring.points_for_rank(0, 4), 6, "points du premier")
	_eq(Scoring.points_for_rank(3, 4), 1, "points du dernier")
	var lv := LevelStore.list_levels()
	_ok(lv.size() >= 7 and lv.has("balade"), "niveaux livrés trouvés : %s" % [lv])
	_ok(not ParkourServer.playable_levels(["balade", "inconnu"]).has("inconnu"), "niveaux autorisés filtrés")
	_eq(ParkourServer.playable_levels(["inconnu"]), lv, "aucun niveau autorisé présent : tous")
	var cfg := Session._clean_server_cfg({"name": "  <Salle>\n ", "max": 99, "password": 3}, {"name": "x", "max": 6, "password": "pw"})
	_eq(cfg, {"name": "Salle", "max": Protocol.MAX_PLAYERS, "password": "pw"}, "réglages du serveur nettoyés")
	print("règles de session : OK")


# ---------- parcours : modes, recommencer, arrivée ----------

func _on(h: Harness, id: String, ty: String, k := 0) -> void:
	var els: Array = h.init["level"]["elements"]
	var found := 0
	for e: Dictionary in els:
		if e["type"] == ty:
			if found == k:
				h.put(id, [e["pos"][0], Level.top_of(e), e["pos"][2]])
				return
			found += 1


func _msgs(h: Harness, ty: String, id: String) -> Array:
	return h.of(ty).filter(func(m: Dictionary) -> bool: return m["id"] == id)


func _test_modes() -> void:
	var lv := LevelStore.read_level("balade")
	# premier arrivé : une fois arrivé, on ne recommence plus et on réapparaît sur l'arrivée
	var h := _parkour(lv, parkour_settings({"duration": 200, "hurry": 200}), 2, false)
	_eq(h.init["mode"], "first", "mode par défaut")
	h.tick(2.0)
	_on(h, "p0", "finish")
	h.tick(2.2)
	_eq(_msgs(h, "finish", "p0").size(), 1, "premier arrivé : arrivée")
	h.game.on_player_message("p0", {"t": "restart", "to": "start"})
	_eq(_msgs(h, "restart", "p0").size(), 0, "premier arrivé : pas de recommencer une fois arrivé")
	var g: ParkourServer = h.game
	var rp: Array = g._respawn_point(g.prog["p0"])
	var fin: Dictionary = g.els[g.finishes[0]]
	_ok(absf(rp[0] - fin["pos"][0]) < 1.0 and absf(rp[2] - fin["pos"][2]) < 1.0, "premier arrivé : réapparition sur l'arrivée")
	_on(h, "p1", "checkpoint")
	h.tick(2.5)
	_eq(_msgs(h, "cp", "p1").size(), 1, "checkpoint validé")
	h.game.on_player_message("p1", {"t": "restart", "to": "cp"})
	_eq(_msgs(h, "restart", "p1").back()["cp"], 0, "recommencer au checkpoint")
	h.tick(2.6)
	_eq(_msgs(h, "cp", "p1").size(), 1, "pas de checkpoint revalidé juste après")
	h.game.on_player_message("p1", {"t": "restart", "to": "start"})
	_eq(_msgs(h, "restart", "p1").back()["cp"], -1, "recommencer au départ")

	# meilleur temps : chrono par essai, retour automatique au départ, record conservé, fin à la durée seulement
	h = _parkour(lv, parkour_settings({"mode": "best", "duration": 30, "hurry": 10}), 2, false)
	_eq(h.init["mode"], "best", "mode meilleur temps")
	h.tick(3.0)
	_on(h, "p0", "finish")
	h.tick(3.1)
	var f1: Dictionary = _msgs(h, "finish", "p0")[0]
	_ok(absf(f1["time"] - 2.0) < 0.1 and f1["record"], "meilleur temps : premier essai %.2f s" % f1["time"])
	_eq(h.of("hurry").size(), 0, "meilleur temps : pas d'accélération")
	h.tick(6.2)
	var r: Array = _msgs(h, "restart", "p0")
	_eq(r.size(), 1, "meilleur temps : retour automatique au départ")
	h.tick(7.0)
	_eq(_msgs(h, "finish", "p0").size(), 1, "meilleur temps : pas d'arrivée tant qu'on n'a pas quitté l'arrivée")
	_on(h, "p0", "start")
	h.tick(9.0)
	_on(h, "p0", "finish")
	h.tick(10.0)
	var f2: Dictionary = _msgs(h, "finish", "p0")[1]
	_ok(not f2["record"] and absf(f2["best"] - f1["time"]) < 1e-6, "meilleur temps : le record reste le premier essai")
	_ok(not h.ended, "meilleur temps : la manche continue")
	_on(h, "p1", "checkpoint")
	h.tick(31.5)
	_ok(h.ended, "meilleur temps : fin à la durée")
	var res: Array = h.game.get_results()
	_eq(res[0]["id"], "p0", "meilleur temps : p0 premier")
	_ok(str(res[0]["label"]).contains("2 arrivées"), "meilleur temps : libellé %s" % res[0]["label"])
	_eq(res[1]["label"], "Checkpoint 1/%d" % g.cps.size(), "meilleur temps : p1 au checkpoint")
	print("modes du parcours : OK")


# ---------- parcours : logique serveur avec de faux joueurs ----------

func _v3(extra := {}, n := 2) -> Harness:
	return _parkour(_fixture("vague3"), parkour_settings({"duration": 200, "hurry": 200}.merged(extra, true)), n, false)


func _idx(h: Harness, id: String) -> int:
	var els: Array = h.init["level"]["elements"]
	for i in els.size():
		if els[i].get("id", "") == id:
			return i
	return -1


func _el(h: Harness, i: int) -> Dictionary:
	return h.init["level"]["elements"][i]


func _test_vague3_rules() -> void:
	if not _wants("vague3-regles"):
		return
	# bouton → ouverture diffusée (prolongée, sans spam) ; levier avec recharge
	var s := _v3()
	_eq(s.init["jostle"], true, "bousculades par défaut")
	s.tick(2.0)
	var btn := _el(s, _idx(s, "bouton"))
	s.put("p0", [btn["pos"][0], btn["pos"][1] + btn["size"][1] / 2.0, btn["pos"][2]])
	s.tick(2.5)
	var opens := s.of("open")
	_eq(opens.size(), 1, "bouton : une ouverture")
	_eq(opens[0]["link"], "porte1", "bouton : lien")
	_eq(opens[0]["by"], _idx(s, "bouton"), "bouton : par")
	_ok(absf(opens[0]["until"] - opens[0]["at"] - 8.0) < 1e-6, "bouton : 8 s")
	s.tick(4.5)
	_ok(s.of("open").size() > 1 and s.of("open").size() < 10, "bouton : prolongé sans spam")
	s.put("p0", [0, 0, 0])
	var lv := _el(s, _idx(s, "levier"))
	s.put("p1", [lv["pos"][0], lv["pos"][1] - 1, lv["pos"][2]])
	s.tick(5.0)
	s.tick(9.0)
	_eq(s.of("lever").size(), 1, "levier : recharge")
	_eq(s.of("open").filter(func(m: Dictionary) -> bool: return m["link"] == "trappe").size(), 1, "levier : trappe ouverte")
	s.tick(13.2)
	_eq(s.of("lever").size(), 2, "levier : réarmé")

	# dalles mémoire : piégée → tombe pour tous et reste tombée ; sûre → révélée ; disposition jamais envoyée
	s = _v3()
	var keys: Array = s.init.keys()
	keys.sort()
	_eq(keys, ["coins", "cps", "endAt", "jostle", "level", "mode"], "init sans disposition")
	s.tick(2.0)
	var mi := _idx(s, "memoire")
	var me := _el(s, mi)
	var tiles := Level.memory_tiles(me)
	for k in tiles.size():
		var tile: Phys.Col = tiles[k]
		s.put("p0", [tile.cx, tile.cy + tile.hy, tile.cz])
		s.tick(2.0 + (k + 1) * 0.1)
	var fell: Array = s.of("tile").map(func(m: Dictionary) -> int: return m["k"])
	var safe: Array = s.of("safe").map(func(m: Dictionary) -> int: return m["k"])
	_eq(fell.size() + safe.size(), 12, "mémoire : 12 dalles")
	_ok(safe.size() >= me["rows"], "mémoire : un chemin sûr")
	var tf: Phys.Col = tiles[fell[0]]
	s.put("p1", [tf.cx, tf.cy + tf.hy, tf.cz])
	s.tick(5.0)
	_eq(s.of("tile").size(), fell.size(), "mémoire : pas de rediffusion")

	# boîte surprise, objets et pièces
	s = _v3({}, 3)
	s.tick(2.0)
	var box := _el(s, _idx(s, "boite1"))
	var rolls := {"super": 0.05, "shield": 0.3, "banana": 0.55, "glove": 0.8}
	var grab := func(id: String, kind: String) -> void:
		var n := s.of("box").size()
		(s.game as ParkourServer).item_roll = func() -> float: return rolls[kind]
		s.put(id, [box["pos"][0], box["pos"][1] - 0.9, box["pos"][2]])
		var k := 0
		while k < 200 and s.of("box").size() == n:
			s.tick(s.t + 1.0 / 30.0)
			k += 1
		(s.game as ParkourServer).item_roll = randf
		var it: Dictionary = s.of("item").back()
		_ok(it["id"] == id and it["kind"] == kind, "boîte : %s prend %s" % [id, kind])
		s.put(id, [5, 0, 30])
	grab.call("p0", "super")
	s.put("p1", [box["pos"][0], box["pos"][1] - 0.9, box["pos"][2]])
	s.tick(s.t + 1.0)
	_eq(s.of("item").size(), 1, "boîte absente pendant sa recharge")
	s.put("p1", [5, 0, 31])
	s.game.on_player_message("p0", {"t": "use"})
	_eq(s.of("item").back()["kind"], null, "objet utilisé")
	_eq(s.of("effect").back()["kind"], "super", "effet super saut")
	_ok(absf(s.of("effect")[0]["until"] - s.t - 8.0) < 1e-6, "super saut : 8 s")
	grab.call("p1", "shield")
	s.game.on_player_message("p1", {"t": "use"})
	grab.call("p0", "glove")
	s.put("p0", [0, 0, 24], {"yaw": 0.0})
	s.put("p1", [0, 0, 26])
	s.put("p2", [0.5, 0, 25.5])
	s.game.on_player_message("p0", {"t": "use"})
	_eq(s.of("glove").back()["hit"], ["p2"], "gant : seul p2 (sans bouclier) frappé")
	_eq(s.impulses.map(func(x: Dictionary) -> String: return x["id"]), ["p2"], "gant : impulsion")
	_ok(s.impulses[0]["v"][2] > 9.0, "gant : vers l'avant")
	s.put("p1", [9, 0, 30])
	s.put("p2", [9, 0, 31])
	grab.call("p0", "banana")
	s.put("p0", [0, 0, 24], {"yaw": 0.0})
	s.game.on_player_message("p0", {"t": "use"})
	var ban: Dictionary = s.of("banana").back()
	_ok(absf(ban["p"][0]) < 1e-9 and absf(ban["p"][1]) < 1e-9 and absf(ban["p"][2] - 22.8) < 1e-9, "banane derrière le joueur : %s" % [ban["p"]])
	s.put("p0", [5, 0, 30])
	s.put("p2", [0, 0, 22.9], {"v": [0.0, 0.0, 5.0]})
	s.tick(s.t + 0.3)
	_eq(s.of("bananaGone").size(), 0, "banane pas encore armée")
	s.tick(s.t + 0.5)
	_eq(s.of("bananaGone").back()["by"], "p2", "banane écrasée par p2")
	var slip: Dictionary = s.impulses.back()
	_ok(slip["id"] == "p2" and absf(slip["v"][2] - 9.0) < 1e-6, "glissade")
	var coin := _el(s, 1)
	for id: String in ["p0", "p0", "p1"]:
		s.put(id, [coin["pos"][0], 0, coin["pos"][2]])
		s.tick(s.t + 0.2)
		s.put(id, [9, 0, 9])
	_eq(s.of("coin").filter(func(m: Dictionary) -> bool: return m["i"] == 1).map(func(m: Dictionary) -> String: return "%s:%d" % [m["id"], m["n"]]), ["p0:1", "p1:1"], "pièces")

	# joint de la grille mémoire : les dalles qui portent la capsule réagissent
	s = _v3()
	s.tick(2.0)
	me = _el(s, mi)
	var top: float = me["pos"][1] + me["size"][1] / 2.0
	var z: float = me["pos"][2] - me["size"][2] / 2.0 + 0.2
	while z < me["pos"][2] + me["size"][2] / 2.0:
		s.put("p0", [-1, top, z])
		s.tick(s.t + 1.0 / 30.0)
		z += 0.25
	var touched := {}
	for m: Dictionary in s.of("tile") + s.of("safe"):
		touched[m["k"]] = true
	var all_rows := true
	for row in int(me["rows"]):
		all_rows = all_rows and touched.has(row * me["cols"]) and touched.has(row * me["cols"] + 1)
	_ok(all_rows, "joint : chaque rangée réagit")

	# banane gardée au-dessus du vide ; joueurs partis ignorés
	s = _v3({}, 3)
	s.tick(2.0)
	box = _el(s, _idx(s, "boite1"))
	(s.game as ParkourServer).item_roll = func() -> float: return 0.55
	s.put("p0", [box["pos"][0], box["pos"][1] - 0.9, box["pos"][2]])
	s.tick(s.t + 0.1)
	_eq(s.of("item").back()["kind"], "banana", "banane prise")
	s.put("p0", [0, 0, 29.5], {"yaw": 0.0})
	s.game.on_player_message("p0", {"t": "use"})
	_eq(s.of("banana").size(), 0, "banane gardée au-dessus du vide")
	s.put("p0", [0, 1.5, 25], {"yaw": 0.0})
	s.game.on_player_message("p0", {"t": "use"})
	ban = s.of("banana").back()
	_ok(absf(ban["p"][1]) < 1e-6, "banane posée au sol")
	s.put("p0", [5, 0, 30])
	s.put("p2", ban["p"])
	s.game.on_player_leave("p2")
	s.tick(s.t + 1.5)
	_eq(s.of("bananaGone").size(), 0, "joueur parti ignoré")

	# mort dans un hazard relayée ; pièces départagent selon le réglage
	s = _v3()
	s.tick(2.0)
	var lava := -1
	var els: Array = s.init["level"]["elements"]
	for i in els.size():
		if els[i]["type"] == "hazard":
			lava = i
			break
	s.game.on_player_message("p0", {"t": "killed", "i": lava})
	s.game.on_player_message("p0", {"t": "killed", "i": lava})
	s.game.on_player_message("p1", {"t": "killed", "i": 0})
	_eq(s.of("killed").map(func(m: Dictionary) -> String: return m["id"]), ["p0"], "mort relayée une fois")
	coin = _el(s, 1)
	s.put("p1", [coin["pos"][0], 0, coin["pos"][2]])
	s.tick(2.2)
	s.put("p0", [0, 0, 4])
	s.put("p1", [0, 0, -4])
	var res := s.game.get_results()
	_eq(res.map(func(r: Dictionary) -> String: return r["id"]), ["p1", "p0"], "pièces départagent")
	_ok(str(res[0]["label"]).ends_with("1 pièce"), "libellé avec pièce : %s" % res[0]["label"])
	var s2 := _v3({"coins": false, "jostle": false})
	_eq(s2.init["jostle"], false, "bousculades désactivées")
	s2.tick(2.0)
	s2.put("p1", [coin["pos"][0], 0, coin["pos"][2]])
	s2.tick(2.2)
	s2.put("p0", [0, 0, 4])
	s2.put("p1", [0, 0, -4])
	_eq(s2.game.get_results().map(func(r: Dictionary) -> String: return r["id"]), ["p0", "p1"], "sans pièces : distance")
	print("vague 3, règles du serveur : OK")
