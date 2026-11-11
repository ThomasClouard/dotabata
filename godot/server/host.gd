class_name ServerHost
extends Node
## Serveur de jeu hébergé dans le client : WebSocket (TCPServer + WebSocketPeer), pas de 30 Hz, et répondeur de
## découverte LAN en UDP. Le créateur s'y connecte lui-même en boucle locale, comme n'importe quel joueur.

const TICK := 1.0 / 30.0
const BUFFER := 1 << 20  # un niveau complet tient dans un seul message

var session: Session
var port := 0
var _tcp := TCPServer.new()
var _udp := PacketPeerUDP.new()
var _conns: Array = []  # [{ws, player}]
var _acc := 0.0
var _closing := -1.0  # instant de fermeture définitive après shutdown()


class Conn extends RefCounted:
	var ws: WebSocketPeer
	var player: ServerPlayer = null
	var refused := false


## Ouvre le serveur sur le premier port libre (PORT … PORT + PORT_SPAN - 1). Renvoie le port, ou -1.
func start(cfg: Dictionary) -> int:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for p in range(Protocol.PORT, Protocol.PORT + Protocol.PORT_SPAN):
		if _tcp.listen(p, "0.0.0.0") == OK:  # IPv4 : un « * » double pile cohabiterait avec un autre serveur du port
			port = p
			break
	if port == 0:
		return -1
	# découverte : même numéro en UDP (si le port est pris, le serveur marche quand même, sans apparaître dans les listes)
	if _udp.bind(port, "0.0.0.0") != OK:
		push_warning("Découverte LAN indisponible sur le port UDP %d." % port)
		_udp = null
	session = Session.new(lan_addresses().map(func(ip: String) -> String: return "%s:%d" % [ip, port]), cfg)
	return port


## Adresses IPv4 de ce PC sur le réseau local.
static func lan_addresses() -> Array:
	var out: Array = []
	for ip: String in IP.get_local_addresses():
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		out.append(ip)
	return out


## Prévient les joueurs et ferme le serveur (les messages de fermeture partent pendant une fraction de seconde).
func shutdown() -> void:
	if session == null or _closing >= 0.0:
		return
	session.shutdown()
	_closing = Time.get_ticks_msec() / 1000.0 + 0.4
	_tcp.stop()
	if _udp:
		_udp.close()
		_udp = null


func _process(delta: float) -> void:
	if session == null:
		return
	if _closing >= 0.0:
		for c: Conn in _conns:
			c.ws.poll()
		if Time.get_ticks_msec() / 1000.0 >= _closing:
			queue_free()
		return
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = BUFFER
		ws.outbound_buffer_size = BUFFER
		ws.max_queued_packets = 4096
		if ws.accept_stream(_tcp.take_connection()) == OK:
			var c := Conn.new()
			c.ws = ws
			_conns.append(c)
	for c: Conn in _conns.duplicate():
		c.ws.poll()
		var st := c.ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			while c.ws.get_available_packet_count() > 0:
				_on_packet(c, c.ws.get_packet().get_string_from_utf8())
		elif st == WebSocketPeer.STATE_CLOSED:
			_conns.erase(c)
			if c.player != null:
				session.on_close(c.player)
	_discovery()
	_acc += delta
	var n := 0
	while _acc >= TICK and n < 4:
		_acc -= TICK
		session.tick()
		n += 1
	if _acc > TICK:
		_acc = 0.0  # gros à-coup (chargement) : on ne rattrape pas indéfiniment


func _on_packet(c: Conn, text: String) -> void:
	if c.refused:
		return
	var msg: Variant = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	if c.player == null:
		if msg.get("t") != "hello":
			return
		var res: Variant = session.on_hello(c.ws, msg)
		if res is Array:
			c.refused = true
			c.ws.close(res[0], res[1])
		else:
			c.player = res
		return
	session.on_message(c.player, msg)


## Répond aux requêtes « dotabata? » des clients qui cherchent des serveurs.
func _discovery() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var from_port := _udp.get_packet_port()
		var q: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if not q is Dictionary or q.get("t") != "dotabata?":
			continue
		var reply := session.summary()
		reply.merge({"t": "dotabata", "v": Protocol.DISCOVERY_VERSION, "port": port, "c": q.get("c", 0)})
		_udp.set_dest_address(ip, from_port)
		_udp.put_packet(JSON.stringify(reply, "", false).to_utf8_buffer())
