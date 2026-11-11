class_name Net
extends Node
## Connexion WebSocket au serveur de jeu (hébergé par un joueur, voir ServerHost) + synchronisation de l'horloge
## serveur (les obstacles en dépendent).

signal message(m: Dictionary)
signal opened
signal closed(was_open: bool)

var id := ""
## Code et raison de la dernière fermeture par le serveur (Session.CLOSE_*), -1 / "" sinon.
var close_code := -1
var close_reason := ""
var _ws: WebSocketPeer
var _hello := {}
var _open := false
var _offset := 0.0  # horloge serveur - horloge locale
var _best_rtt := INF
var _pings := 0
var _ping_at := 0.0
var _deadline := 0.0


func local() -> float:
	return Time.get_ticks_usec() / 1e6


## Horloge serveur synchronisée, en secondes.
func now() -> float:
	return local() + _offset


func is_open() -> bool:
	return _open


func connect_to(address: String, hello: Dictionary) -> void:
	close()
	var url := address
	if not url.contains("://"):
		url = "ws://" + url
	# le serveur n'écoute qu'en IPv4 : « localhost » peut se résoudre en ::1 et ne jamais répondre
	url = url.replace("://localhost", "://127.0.0.1")
	if not url.ends_with("/ws"):
		url = url.trim_suffix("/") + "/ws"
	_hello = hello
	id = ""
	close_code = -1
	close_reason = ""
	_best_rtt = INF
	_pings = 0
	_ws = WebSocketPeer.new()
	_deadline = 0.0
	_ws.inbound_buffer_size = 1 << 20  # un niveau complet tient dans un seul message
	_ws.max_queued_packets = 4096
	if _ws.connect_to_url(url) != OK:
		_ws = null
		closed.emit.call_deferred(false)


func close() -> void:
	if _ws:
		_ws.close()
	_ws = null
	_open = false


func send(m: Dictionary) -> void:
	if _open:
		_ws.send_text(JSON.stringify(m))


func send_raw(text: String) -> void:
	if _open:
		_ws.send_text(text)


func _process(_dt: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	if _deadline == 0.0:
		_deadline = local() + 8.0  # compté à partir du premier sondage : le démarrage peut figer plusieurs secondes
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _open:
			_open = true
			send(_hello)  # doit être le tout premier message
			_ping_at = 0.0
			opened.emit()
		while _ws != null and _ws.get_available_packet_count() > 0:
			var m: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
			if typeof(m) == TYPE_DICTIONARY:
				_handle(m)
		if _ws != null and local() >= _ping_at:
			send({"t": "ping", "c": local()})
			_ping_at = local() + (0.25 if _pings < 8 else 3.0)
			_pings += 1
	elif st == WebSocketPeer.STATE_CLOSED or (st == WebSocketPeer.STATE_CONNECTING and local() > _deadline):
		var was := _open
		if st == WebSocketPeer.STATE_CLOSED:
			close_code = _ws.get_close_code()
			close_reason = _ws.get_close_reason()
		_ws = null
		_open = false
		closed.emit(was)


func _handle(m: Dictionary) -> void:
	var t: String = m.get("t", "")
	if t == "welcome":
		id = m["id"]
		_offset = m["time"] - local()
	elif t == "pong":
		var n := local()
		var rtt: float = n - m["c"]
		# on garde l'estimation issue de l'aller-retour le plus rapide
		if rtt <= _best_rtt + 0.002:
			_best_rtt = minf(_best_rtt, rtt)
			_offset = m["time"] + rtt / 2.0 - n
		return
	message.emit(m)
