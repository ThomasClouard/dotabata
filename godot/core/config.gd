class_name Config
extends RefCounted
## Profil, qualité graphique et adresse du serveur (fichier user://jeux.cfg),
## plus les options de lancement : `-- --server=hôte:port --bots=9 --autostart --shot=chemin.png --shot-at=8`
## sur bureau, `?server=…&bots=9` dans l'URL sur le web.

const PATH := "user://jeux.cfg"

static var profile := {"name": "", "color": 0, "hat": ""}
const QUALITY_KEYS := ["basse", "moyenne", "haute"]
const QUALITY_NAMES := ["légers", "moyens", "élevés"]

## Niveau de qualité graphique : 0 = légers, 1 = moyens, 2 = élevés.
static var quality := 2
static var server := ""
## Réglages du serveur qu'on héberge (nom, joueurs max, mot de passe), mémorisés pour la fois suivante.
static var server_cfg := {"name": "", "max": Protocol.MAX_PLAYERS, "password": ""}
static var args := {}


static func load_all() -> void:
	args = _parse_args()
	var cf := ConfigFile.new()
	cf.load(PATH)
	profile["name"] = str(cf.get_value("profil", "name", "Joueur %d" % randi_range(10, 99)))
	var c := int(cf.get_value("profil", "color", -1))
	profile["color"] = c if Protocol.COLORS.has(c) else Protocol.COLORS.pick_random()
	var h := str(cf.get_value("profil", "hat", ""))
	profile["hat"] = h if Protocol.HATS.has(h) else Protocol.HATS.pick_random()
	quality = QUALITY_KEYS.find(str(cf.get_value("jeu", "qualite", "")))
	if quality < 0:
		quality = _default_quality()
	server = str(cf.get_value("jeu", "serveur", ""))
	server_cfg = {
		"name": str(cf.get_value("serveur", "nom", "")),
		"max": clampi(int(cf.get_value("serveur", "max", Protocol.MAX_PLAYERS)), 2, Protocol.MAX_PLAYERS),
		"password": str(cf.get_value("serveur", "mot_de_passe", "")),
	}
	if args.has("name"):
		profile["name"] = str(args["name"]).left(16)
	if args.has("hat") and Protocol.HATS.has(args["hat"]):
		profile["hat"] = args["hat"]
		profile["color"] = Protocol.HAT_COLOR[args["hat"]]
	if args.has("quality"):
		quality = maxi(0, QUALITY_KEYS.find(str(args["quality"])))


static func save() -> void:
	if args.has("no-save"):
		return
	var cf := ConfigFile.new()
	cf.set_value("profil", "name", profile["name"])
	cf.set_value("profil", "color", profile["color"])
	cf.set_value("profil", "hat", profile["hat"])
	cf.set_value("jeu", "qualite", QUALITY_KEYS[quality])
	cf.set_value("jeu", "serveur", server)
	cf.set_value("serveur", "nom", server_cfg["name"])
	cf.set_value("serveur", "max", server_cfg["max"])
	cf.set_value("serveur", "mot_de_passe", server_cfg["password"])
	cf.save(PATH)


## Premier lancement : les puces graphiques intégrées et le web démarrent en « moyens ».
static func _default_quality() -> int:
	if OS.has_feature("web"):
		return 1
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	for k: String in ["intel", "uhd", "iris", "llvmpipe", "swiftshader", "basic render"]:
		if gpu.contains(k):
			return 1
	return 2


## Radeon GCN 1 à 3 (HD 7000/8000, R5/R7/R9 200-300, Fury), bloquées sur le pilote « legacy » : leur résolution
## du MSAA pour l'occlusion ambiante et les reflets écran donne des blocs noirs. `--msaa=on|off` force le choix.
static func msaa_breaks_screen_fx() -> bool:
	if args.has("msaa"):
		return str(args["msaa"]) == "off"
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	return RegEx.create_from_string("radeon (hd [78]\\d{3}|r[579] (2|3)\\d{2}|r9 fury|r9 nano)|amd fury").search(gpu) != null


## Adresse « hôte:port » du serveur de jeu à essayer en premier.
static func default_server() -> String:
	if args.has("server"):
		return str(args["server"])
	if OS.has_feature("web"):
		# sur le web, le serveur de jeu est a priori sur la machine qui sert la page
		var host: Variant = JavaScriptBridge.eval("location.hostname")
		if typeof(host) == TYPE_STRING and host != "":
			return "%s:3000" % host
	if server != "":
		return server
	return "localhost:3000"


static func arg_int(key: String, default := 0) -> int:
	return int(str(args[key])) if args.has(key) else default


static func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var eq := s.find("=")
		if eq < 0:
			out[s] = "1"
		else:
			out[s.left(eq)] = s.substr(eq + 1)
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("location.search")
		if typeof(q) == TYPE_STRING:
			for part in str(q).trim_prefix("?").split("&", false):
				var eq := part.find("=")
				if eq < 0:
					out[part] = "1"
				else:
					out[part.left(eq)] = part.substr(eq + 1).uri_decode()
	return out
