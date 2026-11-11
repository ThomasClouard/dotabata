class_name Discovery
extends Node
## Recherche des serveurs Dotabata! du réseau local : envoie « dotabata? » en UDP (broadcast et boucle locale)
## sur les ports Protocol.PORT … PORT + PORT_SPAN - 1 toutes les 2 s, et tient la liste des serveurs qui répondent.

signal changed

const PERIOD := 2.0
const FORGET := 6.0  # un serveur muet depuis plus longtemps disparaît de la liste

var servers := {}  # "ip:port" → {address, name, players, bots, max, phase, locked, ping, seen}
var _udp: PacketPeerUDP
var _next := 0.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func start() -> void:
	if _udp != null:
		return
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	if _udp.bind(0, "*") != OK:
		_udp = null
		return
	_next = 0.0


func stop() -> void:
	if _udp:
		_udp.close()
	_udp = null
	servers.clear()


func is_running() -> bool:
	return _udp != null


## Liste triée (nom, puis adresse).
func list() -> Array:
	var out: Array = servers.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["name"].naturalnocasecmp_to(b["name"]) < 0 if a["name"] != b["name"] else a["address"] < b["address"])
	return out


## Adresses de diffusion : générale, /24 de chaque interface, et ce PC.
static func _targets() -> Array:
	var out := ["255.255.255.255", "127.0.0.1"]
	for ip: String in IP.get_local_addresses():
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		var parts := ip.split(".")
		var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not out.has(b):
			out.append(b)
	return out


func _process(_dt: float) -> void:
	if _udp == null:
		return
	var t := _now()
	if t >= _next:
		_next = t + PERIOD
		var q := JSON.stringify({"t": "dotabata?", "v": Protocol.DISCOVERY_VERSION, "c": t}).to_utf8_buffer()
		for ip: String in _targets():
			for p in range(Protocol.PORT, Protocol.PORT + Protocol.PORT_SPAN):
				_udp.set_dest_address(ip, p)
				_udp.put_packet(q)
	var dirty := false
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var r: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if not r is Dictionary or r.get("t") != "dotabata" or int(r.get("v", 0)) != Protocol.DISCOVERY_VERSION:
			continue
		var addr := "%s:%d" % [ip, int(r.get("port", Protocol.PORT))]
		# un serveur de ce PC répond aussi via le réseau local : on garde une seule entrée (la boucle locale)
		var key := "%s:%d" % ["local" if ip == "127.0.0.1" or ServerHost.lan_addresses().has(ip) else ip, int(r.get("port", 0))]
		var prev: Dictionary = servers.get(key, {})
		var ping := maxf(0.0, t - float(r.get("c", t)))
		servers[key] = {
			"address": addr if not prev.has("address") or ip == "127.0.0.1" else prev["address"],
			"name": Session.clean_name(r.get("name"), 32, "Dotabata!"),
			"players": int(r.get("players", 0)), "bots": int(r.get("bots", 0)), "max": int(r.get("max", Protocol.MAX_PLAYERS)),
			"phase": str(r.get("phase", "lobby")), "locked": bool(r.get("locked", false)),
			"ping": minf(ping, prev.get("ping", INF)) if prev.has("ping") and t - prev.get("seen", 0.0) < PERIOD * 2.0 else ping,
			"seen": t,
		}
		dirty = true
	for k: String in servers.keys():
		if t - servers[k]["seen"] > FORGET:
			servers.erase(k)
			dirty = true
	if dirty:
		changed.emit()
