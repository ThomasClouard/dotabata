class_name Config
extends RefCounted
## Profil, qualité graphique et adresse du serveur (fichier user://jeux.cfg),
## plus les options de lancement : `-- --server=hôte:port --bots=9 --autostart --shot=chemin.png --shot-at=8`.

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
## Options du menu : plein écran, volume des effets (0 à 1), sensibilité de la souris (facteur).
static var fullscreen := false
static var sfx_volume := 0.8
static var mouse_sens := 1.0


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
	fullscreen = bool(cf.get_value("options", "plein_ecran", false))
	sfx_volume = clampf(float(cf.get_value("options", "volume", 0.8)), 0.0, 1.0)
	mouse_sens = clampf(float(cf.get_value("options", "souris", 1.0)), 0.25, 3.0)
	Pad.load_cfg(cf)
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
	cf.set_value("options", "plein_ecran", fullscreen)
	cf.set_value("options", "volume", sfx_volume)
	cf.set_value("options", "souris", mouse_sens)
	Pad.save_cfg(cf)
	cf.save(PATH)


## Applique le plein écran et le volume (la sensibilité est lue à chaque image par la caméra).
static func apply_options() -> void:
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		var mode := DisplayServer.window_get_mode()
		var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if is_full != fullscreen:
			DisplayServer.window_set_mode(want)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(sfx_volume, 0.0001)))
	AudioServer.set_bus_mute(0, sfx_volume <= 0.001)


## Premier lancement : les puces graphiques intégrées démarrent en « moyens ».
static func _default_quality() -> int:
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
	return out
