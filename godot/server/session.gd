class_name Session
extends RefCounted
## Cœur du serveur : lobby, enchaînement des manches, scores, relais des états, réglages du serveur.
## Ne connaît aucun jeu en particulier (voir GameMetas).
## Le transport (WebSocket) est géré par ServerHost, qui appelle on_hello / on_message / on_close et tick().

const BOT_NAMES := ["Nouille", "Patate", "Cornichon", "Biscotte", "Gnocchi", "Tartine", "Zigoto", "Pompon", "Bidule", "Saucisse"]
const DEFAULTS_FILE := "res://config/defaults.json"
const LAST_FILE := "user://last-settings.json"
const COUNTDOWN := 4.0
const SCORES_TIME := 9.0
const PODIUM_TIME := 60.0
## Codes de fermeture WebSocket envoyés aux clients refusés.
const CLOSE_FULL := 4000
const CLOSE_PASSWORD := 4001
const CLOSE_SHUTDOWN := 4002

## Appelé quand l'hôte modifie les réglages du serveur ({name, max, password}) : pour les mémoriser.
signal server_changed(cfg: Dictionary)

var players := {}  # id → ServerPlayer, dans l'ordre d'arrivée
var host_id := ""
var host_key := ""  # secret du créateur du serveur : son hello le désigne comme hôte
var settings := {}
var server_cfg := {"name": "Dotabata!", "max": Protocol.MAX_PLAYERS, "password": ""}
var phase := "lobby"  # lobby | round | scores | podium
var urls: Array = []
var game: ServerGame = null
var ctx: ServerCtx = null
var game_id := ""
var rounds: Array = []
var round_index := 0
var end_requested := false
var _timer_at := -1.0
var _timer_fn := Callable()
var _next_id := 1
var _t0 := Time.get_ticks_usec()
var _last_tick := 0.0
var _levels_fp := ""
var _levels_check := 0.0


func _init(p_urls: Array = [], cfg: Dictionary = {}) -> void:
	urls = p_urls
	host_key = "%x%x" % [randi(), randi()]
	for k: String in cfg:
		if server_cfg.has(k):
			server_cfg[k] = cfg[k]
	server_cfg = _clean_server_cfg(server_cfg, server_cfg)
	# réglages : valeurs par défaut du jeu, puis derniers réglages de l'hôte
	var last: Variant = _read_json(LAST_FILE)
	settings = Scoring.sanitize_settings(last if last != null else _read_json(DEFAULTS_FILE), GameMetas.all())
	LevelStore.ensure_user_dir()
	_levels_fp = LevelStore.fingerprint()


static func _read_json(f: String) -> Variant:
	if not FileAccess.file_exists(f):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(f))


static func clean_name(s: Variant, max_len := 16, fallback := "Anonyme") -> String:
	var out := str(s if s != null else "")
	for ch in ["<", ">", "\n", "\r"]:
		out = out.replace(ch, "")
	out = out.strip_edges().left(max_len)
	return out if out != "" else fallback


static func _clean_server_cfg(raw: Dictionary, prev: Dictionary) -> Dictionary:
	var mx: Variant = raw.get("max", prev["max"])
	var m: int = clampi(int(mx) if (mx is float or mx is int) else int(prev["max"]), 2, Protocol.MAX_PLAYERS)
	var pw: Variant = raw.get("password", prev["password"])
	return {
		"name": clean_name(raw.get("name", prev["name"]), 32, "Dotabata!"),
		"max": m,
		"password": str(pw).left(32) if pw is String else str(prev["password"]),
	}


## Horloge serveur, en secondes.
func now() -> float:
	return (Time.get_ticks_usec() - _t0) / 1e6


func humans() -> Array:
	return players.values().filter(func(p: ServerPlayer) -> bool: return not p.is_bot)


func bots() -> Array:
	return players.values().filter(func(p: ServerPlayer) -> bool: return p.is_bot)


## Résumé pour la découverte LAN.
func summary() -> Dictionary:
	return {"name": server_cfg["name"], "players": humans().size(), "bots": bots().size(), "max": server_cfg["max"], "phase": phase, "locked": server_cfg["password"] != ""}


# ---------- connexions ----------

## Premier message d'une connexion. Renvoie le joueur créé, ou [code, raison] si la connexion est refusée.
func on_hello(peer: WebSocketPeer, msg: Dictionary) -> Variant:
	var is_host_key: bool = msg.get("key") is String and msg["key"] == host_key
	if not is_host_key:
		if server_cfg["password"] != "" and str(msg.get("pw", "")) != server_cfg["password"]:
			return [CLOSE_PASSWORD, "Mot de passe incorrect"]
		if humans().size() >= int(server_cfg["max"]):
			return [CLOSE_FULL, "Partie complète"]
	if humans().size() >= Protocol.MAX_PLAYERS:
		return [CLOSE_FULL, "Partie complète"]
	if players.size() >= _capacity():
		_set_bots(bots().size() - 1)
	var me := _add_player(clean_name(msg.get("name")), msg.get("color"), msg.get("hat"), false)
	me.peer = peer
	if is_host_key or host_id == "":
		host_id = me.id
	_send(me, {"t": "welcome", "id": me.id, "time": now()})
	send_lobby()
	if phase != "lobby":
		_send(me, {"t": "wait"})
	return me


func on_close(me: ServerPlayer) -> void:
	if me != null:
		_remove_player(me.id)


## Nombre de places (humains + bots).
func _capacity() -> int:
	return maxi(int(server_cfg["max"]), humans().size())


func _add_player(pname: String, color: Variant, hat: Variant, is_bot: bool) -> ServerPlayer:
	var id := "p%d" % _next_id
	_next_id += 1
	var a := randf() * TAU
	var r := 3.0 + randf() * 4.0
	var p := ServerPlayer.new()
	p.id = id
	p.name = pname
	p.is_bot = is_bot
	var ci: int = int(color) if (color is float or color is int) else -1
	p.color = ci if Protocol.COLORS.has(ci) else Protocol.COLORS[players.size() % Protocol.COLORS.size()]
	p.hat = hat if hat is String and Protocol.HATS.has(hat) else Protocol.HATS[0]
	p.p = [sin(a) * r, 0.0, cos(a) * r]
	p.yaw = a + PI
	p.flags = Protocol.FLAG_GROUNDED
	if is_bot:
		p.body = Phys.make_body(p.p[0], p.p[1], p.p[2])
	players[id] = p
	return p


func _remove_player(id: String) -> void:
	var p: ServerPlayer = players.get(id)
	if p == null:
		return
	players.erase(id)
	if p.in_round and game != null:
		game.on_player_leave(id)
	var hs := humans()
	if hs.is_empty():
		# plus personne : retour au lobby, sans bots
		players.clear()
		host_id = ""
		to_lobby()
		return
	if host_id == id:
		host_id = hs[0].id
	send_lobby()


func _set_bots(n: int) -> void:
	var h := humans().size()
	n = maxi(0, mini(_capacity() - h, n))
	while bots().size() > n:
		var b: ServerPlayer = bots().back()
		players.erase(b.id)
		if b.in_round and game != null:
			game.on_player_leave(b.id)
	while bots().size() < n:
		var used := {}
		for p: ServerPlayer in players.values():
			used[p.name] = true
		var bname := "Bot %d" % _next_id
		for x: String in BOT_NAMES:
			if not used.has(x):
				bname = x
				break
		var taken := func(c: int) -> bool: return players.values().any(func(p: ServerPlayer) -> bool: return p.color == c)
		# de préférence un personnage dont la couleur d'origine est encore libre
		var free: Array = Protocol.HATS.filter(func(hh: String) -> bool: return not taken.call(Protocol.HAT_COLOR[hh]))
		var from: Array = free if not free.is_empty() else Protocol.HATS
		var hat: String = from[floori(randf() * from.size())]
		var color: Variant = Protocol.HAT_COLOR[hat]
		if taken.call(color):
			color = null
			for c: int in Protocol.COLORS:
				if not taken.call(c):
					color = c
					break
		_add_player(bname, color, hat, true)


# ---------- messages ----------

func on_message(me: ServerPlayer, msg: Dictionary) -> void:
	var host := me.id == host_id
	match msg.get("t"):
		"ping":
			_send(me, {"t": "pong", "c": msg.get("c", 0.0), "time": now()})
		"state":
			var s: Variant = msg.get("s")
			if not s is Array or s.size() < 8:
				return
			for x: Variant in s:
				if not (x is float or x is int) or not is_finite(x):
					return
			me.p = [float(s[0]), float(s[1]), float(s[2])]
			me.yaw = s[3]
			me.flags = int(s[4])
			me.v = [float(s[5]), float(s[6]), float(s[7])]
		"profile":
			me.name = clean_name(msg.get("name"))
			var c: Variant = msg.get("color")
			if (c is float or c is int) and Protocol.COLORS.has(int(c)):
				me.color = int(c)
			if msg.get("hat") is String and Protocol.HATS.has(msg["hat"]):
				me.hat = msg["hat"]
			send_lobby()
		"settings":
			if not host or phase != "lobby":
				return
			settings = Scoring.sanitize_settings(msg.get("settings"), GameMetas.all())
			var f := FileAccess.open(LAST_FILE, FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(settings, "  "))
			send_lobby()
		"server":
			# réglages du serveur : à tout moment, même en pleine partie
			if host:
				set_server_cfg(msg)
		"bots":
			if host and phase == "lobby":
				var n: Variant = msg.get("n")
				_set_bots(int(n) if (n is float or n is int) else 0)
				send_lobby()
		"start":
			if host and phase == "lobby":
				_start_session()
		"stop", "toLobby":
			if host and phase != "lobby":
				to_lobby()
		"game":
			if phase == "round" and me.in_round and game != null and msg.get("m") is Dictionary:
				game.on_player_message(me.id, msg["m"])


func set_server_cfg(raw: Dictionary) -> void:
	server_cfg = _clean_server_cfg(raw, server_cfg)
	if phase == "lobby" and players.size() > _capacity():
		_set_bots(_capacity() - humans().size())
	server_changed.emit(server_cfg.duplicate())
	send_lobby()


func _send(p: ServerPlayer, msg: Dictionary) -> void:
	if p.peer != null and p.peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		p.peer.send_text(JSON.stringify(msg, "", false))


func broadcast(msg: Dictionary, only_in_round := false) -> void:
	var data := JSON.stringify(msg, "", false)
	for p: ServerPlayer in players.values():
		if p.peer != null and p.peer.get_ready_state() == WebSocketPeer.STATE_OPEN and (not only_in_round or p.in_round):
			p.peer.send_text(data)


## Fermeture du serveur : prévient tout le monde.
func shutdown() -> void:
	for p: ServerPlayer in players.values():
		if p.peer != null:
			p.peer.close(CLOSE_SHUTDOWN, "L'hôte a fermé le serveur")


func metas() -> Array:
	# injecte les options dynamiques (ex. niveaux présents sur le disque)
	var dyn := GameMetas.dynamic_options()
	var out: Array = []
	for m: Dictionary in GameMetas.all():
		var mm: Dictionary = m.duplicate(true)
		for k: String in dyn.get(m["id"], {}):
			if mm["settings"].has(k) and mm["settings"][k]["type"] == "multi":
				mm["settings"][k]["options"] = dyn[m["id"]][k]
		out.append(mm)
	return out


func send_lobby() -> void:
	var list: Array = []
	for p: ServerPlayer in players.values():
		list.append({"id": p.id, "name": p.name, "color": p.color, "hat": p.hat, "isBot": p.is_bot, "score": p.score})
	var srv := {"name": server_cfg["name"], "max": server_cfg["max"], "locked": server_cfg["password"] != ""}
	broadcast({"t": "lobby", "phase": phase, "players": list, "hostId": host_id, "settings": settings, "metas": metas(), "urls": urls, "server": srv})


# ---------- déroulement ----------

func _set_timer(seconds: float, fn: Callable) -> void:
	_timer_at = now() + seconds
	_timer_fn = fn


func _clear_timer() -> void:
	_timer_at = -1.0
	_timer_fn = Callable()


func to_lobby() -> void:
	_clear_timer()
	phase = "lobby"
	game = null
	ctx = null
	var i := 0
	for p: ServerPlayer in players.values():
		p.score = 0
		p.in_round = false
		if p.is_bot:
			var a := (i / 9.0) * TAU
			i += 1
			p.p = [sin(a) * 6.0, 0.0, cos(a) * 6.0]
			p.v = [0.0, 0.0, 0.0]
			p.yaw = a + PI
			p.flags = Protocol.FLAG_GROUNDED
			p.body = Phys.make_body(p.p[0], p.p[1], p.p[2])
	send_lobby()


func _start_session() -> void:
	rounds = Scoring.build_round_list(settings)
	round_index = 0
	for p: ServerPlayer in players.values():
		p.score = 0
	_start_round()


func _make_ctx(start_at: float) -> ServerCtx:
	var c := ServerCtx.new()
	for p: ServerPlayer in players.values():
		p.in_round = true
		c.players[p.id] = p
	c.settings = settings["game"].get(game_id, {})
	c.start_at = start_at
	c._now = now
	c._broadcast = func(m: Dictionary) -> void: broadcast({"t": "game", "m": m}, true)
	c._send = func(id: String, m: Dictionary) -> void:
		var p: ServerPlayer = players.get(id)
		if p != null:
			_send(p, {"t": "game", "m": m})
	c._damage = func(id: String, hit: Dictionary) -> void: broadcast({"t": "damage", "id": id, "hit": hit})
	c._heal = func(id: String, n: int) -> void: broadcast({"t": "heal", "id": id, "n": n})
	c._impulse = func(id: String, v: Array, tumble: float) -> void:
		var p: ServerPlayer = players.get(id)
		if p == null:
			return
		if p.body != null:
			ServerCtx.impulse_body(p.body, v, tumble)
		else:
			_send(p, {"t": "impulse", "v": v, "tumble": tumble})
	c._teleport = func(id: String, pos: Array) -> void:
		var p: ServerPlayer = players.get(id)
		if p == null:
			return
		if p.body != null:
			p.body.set_pos(pos[0], pos[1], pos[2])
			p.body.vx = 0.0
			p.body.vy = 0.0
			p.body.vz = 0.0
		else:
			_send(p, {"t": "teleport", "p": pos})
	c._end = func() -> void: end_requested = true
	return c


func _start_round() -> void:
	_clear_timer()
	game_id = rounds[round_index]
	var start_at := now() + COUNTDOWN
	var c := _make_ctx(start_at)
	var g := GameMetas.create_game(game_id, c)
	var res: Dictionary = g.on_start() if g != null else {}
	if res.is_empty():
		push_error("Impossible de lancer la manche « %s »." % game_id)
		to_lobby()
		return
	var spawns: Dictionary = res["spawns"]
	for p: ServerPlayer in players.values():
		if not spawns.has(p.id):
			continue
		var s: Array = spawns[p.id]
		p.p = [s[0], s[1], s[2]]
		p.v = [0.0, 0.0, 0.0]
		if p.is_bot:
			p.body = Phys.make_body(s[0], s[1], s[2])
	game = g
	ctx = c
	phase = "round"
	end_requested = false
	send_lobby()
	broadcast({"t": "round", "index": round_index, "total": rounds.size(), "gameId": game_id, "init": res["init"], "spawns": spawns, "startAt": start_at})


func _end_round() -> void:
	if game == null:
		return
	var rows := Scoring.score_round(game.get_results())
	for r: Dictionary in rows:
		var p: ServerPlayer = players.get(r["id"])
		if p != null:
			p.score += r["points"]
	var totals := {}
	for p: ServerPlayer in players.values():
		totals[p.id] = p.score
	var last := round_index >= rounds.size() - 1
	phase = "scores"
	game = null
	broadcast({"t": "roundEnd", "gameId": game_id, "index": round_index, "total": rounds.size(), "results": rows, "totals": totals, "last": last})
	send_lobby()
	_set_timer(SCORES_TIME, func() -> void:
		if last:
			phase = "podium"
			broadcast({"t": "podium", "totals": totals})
			send_lobby()
			_set_timer(PODIUM_TIME, to_lobby)
		else:
			round_index += 1
			_start_round())


## Pas du serveur (30 Hz) : bots, règles de la manche, minuteries, relais des états.
func tick() -> void:
	var t := now()
	var dt := minf(0.1, t - _last_tick)
	_last_tick = t
	if _timer_at >= 0.0 and t >= _timer_at:
		var fn := _timer_fn
		_clear_timer()
		fn.call()
	if phase == "lobby" and t >= _levels_check:
		# un niveau ajouté (MCP, dossier user://) apparaît dans le lobby sans redémarrer
		_levels_check = t + 2.0
		var fp := LevelStore.fingerprint()
		if fp != _levels_fp:
			_levels_fp = fp
			send_lobby()
	if players.is_empty():
		return
	if phase == "round" and game != null and ctx != null:
		if game.has_bots() and t >= ctx.start_at:
			for p: ServerPlayer in players.values():
				if not p.is_bot or not p.in_round or p.body == null:
					continue
				game.bot_tick(p, dt)
				_sync_bot(p)
		game.on_tick(dt)
		if end_requested:
			_end_round()
	var s: Array = []
	for p: ServerPlayer in players.values():
		s.append([p.id, _r(p.p[0]), _r(p.p[1]), _r(p.p[2]), _r(p.yaw), p.flags, _r(p.v[0]), _r(p.v[1]), _r(p.v[2])])
	broadcast({"t": "states", "s": s})


static func _r(x: float) -> float:
	return roundf(x * 100.0) / 100.0


static func _sync_bot(p: ServerPlayer) -> void:
	var b := p.body
	p.sync_from_body()
	p.flags = (Protocol.FLAG_GROUNDED if b.grounded or b.coyote > 0.0 else 0) | (Protocol.FLAG_TUMBLE if b.tumble > 0.0 else 0) | Protocol.pose_flags(b)
