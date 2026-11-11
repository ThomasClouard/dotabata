extends SceneTree
## Test de bout en bout du serveur hébergé : ServerHost sur un vrai port, clients WebSocket et découverte UDP.
##   godot --headless --path godot -s res://tests/run_host_test.gd

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _ok(cond: bool, what: String) -> bool:
	_checks += 1
	if not cond:
		_fails += 1
		print("ÉCHEC ", what)
	return cond


## Client WebSocket minimal : connexion, envoi, réception (messages gardés dans `log`).
class Client extends RefCounted:
	var ws := WebSocketPeer.new()
	var log: Array = []

	func _init(port: int) -> void:
		ws.inbound_buffer_size = 1 << 20
		ws.connect_to_url("ws://127.0.0.1:%d/ws" % port)

	func poll() -> void:
		ws.poll()
		while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			var m: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if m is Dictionary:
				log.append(m)

	func send(m: Dictionary) -> void:
		ws.send_text(JSON.stringify(m))

	func last(t: String) -> Variant:
		for i in range(log.size() - 1, -1, -1):
			if log[i]["t"] == t:
				return log[i]
		return null

	func count(t: String) -> int:
		return log.filter(func(m: Dictionary) -> bool: return m["t"] == t).size()


## Fait tourner le serveur et les clients jusqu'à ce que cond() soit vraie (ou délai dépassé).
func _until(clients: Array, cond: Callable, seconds := 5.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		for c: Client in clients:
			c.poll()
		if cond.call():
			return true
	return false


func _run() -> void:
	var host := ServerHost.new()
	root.add_child(host)
	var port := host.start({"name": "Salle de test", "max": 3, "password": "abc"})
	_ok(port >= Protocol.PORT, "serveur ouvert (port %d)" % port)

	# le créateur (clé d'hôte) entre sans mot de passe et devient l'hôte
	var a := Client.new(port)
	await _until([a], func() -> bool: return a.ws.get_ready_state() == WebSocketPeer.STATE_OPEN)
	a.send({"t": "hello", "name": "Alice", "color": Protocol.COLORS[0], "hat": "haricot", "key": host.session.host_key})
	_ok(await _until([a], func() -> bool: return a.last("lobby") != null), "lobby reçu par l'hôte")
	var lobby: Dictionary = a.last("lobby")
	var my_id: String = a.last("welcome")["id"]
	_ok(lobby["hostId"] == my_id, "le créateur est l'hôte")
	_ok(lobby.get("server", {}).get("name") == "Salle de test", "nom du serveur dans le lobby : %s" % [lobby.get("server")])
	_ok(lobby["server"]["locked"] == true and not JSON.stringify(lobby).contains("abc"), "mot de passe jamais envoyé")

	# mauvais mot de passe : refus 4001 ; bon mot de passe : accepté
	var b := Client.new(port)
	await _until([b], func() -> bool: return b.ws.get_ready_state() == WebSocketPeer.STATE_OPEN)
	b.send({"t": "hello", "name": "Bob", "pw": "nope"})
	await _until([a, b], func() -> bool: return b.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED)
	_ok(b.ws.get_close_code() == Session.CLOSE_PASSWORD, "mauvais mot de passe refusé (code %d)" % b.ws.get_close_code())
	b = Client.new(port)
	await _until([b], func() -> bool: return b.ws.get_ready_state() == WebSocketPeer.STATE_OPEN)
	b.send({"t": "hello", "name": "Bob", "pw": "abc"})
	_ok(await _until([a, b], func() -> bool: return b.last("lobby") != null), "bon mot de passe accepté")

	# découverte LAN
	var disc := Discovery.new()
	root.add_child(disc)
	disc.start()
	_ok(await _until([a, b], func() -> bool: return not disc.list().is_empty(), 4.0), "serveur trouvé par la découverte")
	if not disc.list().is_empty():
		var s: Dictionary = disc.list()[0]
		_ok(s["name"] == "Salle de test" and s["players"] == 2 and s["max"] == 3 and s["locked"], "résumé de découverte : %s" % [s])

	# réglages du serveur modifiés par l'hôte, avec un autre joueur connecté (et refusés venant de Bob)
	b.send({"t": "server", "name": "Pirate", "max": 10, "password": ""})
	a.send({"t": "server", "name": "Nouvelle salle", "max": 2, "password": ""})
	_ok(await _until([a, b], func() -> bool: return b.last("lobby") != null and b.last("lobby")["server"]["name"] == "Nouvelle salle"), "Bob voit le nouveau nom")
	_ok(b.last("lobby")["server"]["max"] == 2 and not b.last("lobby")["server"]["locked"], "max et mot de passe mis à jour")
	_ok(host.session.server_cfg["name"] != "Pirate", "seul l'hôte change les réglages du serveur")
	# serveur plein (max 2) : refus 4000
	var c := Client.new(port)
	await _until([c], func() -> bool: return c.ws.get_ready_state() == WebSocketPeer.STATE_OPEN)
	c.send({"t": "hello", "name": "Carole"})
	await _until([a, b, c], func() -> bool: return c.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED)
	_ok(c.ws.get_close_code() == Session.CLOSE_FULL, "serveur plein refusé (code %d)" % c.ws.get_close_code())
	_ok(await _until([a, b], func() -> bool: return disc.list().size() > 0 and disc.list()[0]["name"] == "Nouvelle salle", 4.0), "la découverte voit le nouveau nom")

	# une partie : bots, réglages, lancement, réglages du serveur en pleine manche
	a.send({"t": "server", "name": "Nouvelle salle", "max": 6, "password": ""})
	a.send({"t": "bots", "n": 3})
	var st: Dictionary = a.last("lobby")["settings"].duplicate(true)
	st["rounds"] = 1
	st["games"] = ["mortar"]
	st["game"]["mortar"]["buildTime"] = 5
	a.send({"t": "settings", "settings": st})
	_ok(await _until([a, b], func() -> bool: return a.last("lobby")["players"].size() == 5), "3 bots ajoutés")
	# retrait d'un bot précis (croix sur sa carte), puis on revient à 3
	var first_bot: String = a.last("lobby")["players"].filter(func(p: Dictionary) -> bool: return p["isBot"])[0]["id"]
	b.send({"t": "bots", "remove": first_bot})  # pas l'hôte : ignoré
	a.send({"t": "bots", "remove": a.last("lobby")["players"].filter(func(p: Dictionary) -> bool: return not p["isBot"])[0]["id"]})  # un humain : ignoré
	a.send({"t": "bots", "remove": first_bot})
	_ok(await _until([a, b], func() -> bool: return a.last("lobby")["players"].size() == 4 and not a.last("lobby")["players"].any(func(p: Dictionary) -> bool: return p["id"] == first_bot)), "bot précis retiré")
	a.send({"t": "bots", "n": 3})
	_ok(await _until([a, b], func() -> bool: return a.last("lobby")["players"].size() == 5), "bot remis")
	a.send({"t": "start"})
	_ok(await _until([a, b], func() -> bool: return b.last("round") != null), "manche lancée")
	_ok(b.last("round")["gameId"] == "mortar" and b.last("round")["spawns"].size() == 5, "manche de mortier pour 5")
	a.send({"t": "server", "name": "En plein jeu", "max": 6, "password": ""})
	_ok(await _until([a, b], func() -> bool: return b.last("lobby")["server"]["name"] == "En plein jeu" and b.last("lobby")["phase"] == "round"), "réglages du serveur changés pendant la manche")
	_ok(await _until([a, b], func() -> bool: return b.count("states") > 20), "états relayés")

	# l'hôte ferme : les autres reçoivent 4002
	host.shutdown()
	await _until([a, b], func() -> bool: return b.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED, 3.0)
	_ok(b.ws.get_close_code() == Session.CLOSE_SHUTDOWN, "fermeture annoncée (code %d)" % b.ws.get_close_code())
	disc.stop()
	print("%d vérifications, %d échec(s)" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
