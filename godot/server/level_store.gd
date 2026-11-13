class_name LevelStore
extends RefCounted
## Niveaux de parcours sur le disque : res://levels/parkour (livrés avec le jeu ; le vrai dossier quand on lance
## depuis les sources, celui où écrit le MCP) puis user://levels/parkour (niveaux perso, prioritaires à nom égal).
## Les valeurs par défaut du schéma (shared/src/level.ts, zod) sont appliquées à la lecture.

const DIRS := ["res://levels/parkour", "user://levels/parkour"]
const NAME_RE := "^[a-z0-9][a-z0-9_-]{0,40}$"

## Valeurs par défaut par type d'élément (yaw = 0 pour tous).
const DEFAULTS := {
	"moving": {"period": 4, "phase": 0},
	"trampoline": {"bounce": 15},
	"conveyor": {"speed": 4},
	"crumble": {"delay": 0.5, "respawn": 4},
	"spinner": {"speed": 1.5, "phase": 0},
	"hammer": {"length": 5, "axis": "x", "amplitude": 1.1, "period": 3, "phase": 0},
	"fan": {"force": [0, 42, 0]},
	"cannon": {"stroke": 3, "period": 3, "phase": 0},
	"roller": {"speed": 3},
	"puncher": {"count": 4, "stroke": 2.5, "period": 3, "stagger": 0.15, "phase": 0},
	"gate": {"drop": 3, "period": 4, "phase": 0},
	"turntable": {"speed": 0.8, "phase": 0},
	"sweeper": {"speed": 1.3, "highOffset": 2.1, "phase": 0},
	"ferris": {"count": 4, "radius": 5, "period": 14, "phase": 0},
	"pistons": {"count": 4, "height": 2, "period": 3, "stagger": 0.25, "phase": 0},
	"wreckingball": {"length": 6, "angle": 0.7, "period": 4, "phase": 0},
	"crusher": {"minGap": 1.4, "thickness": 1, "period": 4, "phase": 0},
	"blink": {"period": 4, "on": 0.6, "phase": 0},
	"hazard": {"style": "lava"},
	"boulder": {"interval": 4, "travel": 5, "phase": 0},
	"deco": {"kind": "tree"},
	"sign": {"text": ""},
	"fog": {"density": 0.6},
	"mud": {"slow": 0.45, "jumpFactor": 0.6},
	"jelly": {"bounciness": 0.6, "jumpFactor": 1.2},
	"ramp": {"rise": 2, "slide": false},
	"boost": {"dir": [0, 1], "speed": 18},
	"launcher": {"apex": 3},
	"jumppad": {"launch": [0, 14, 8]},
	"zipline": {"speed": 10},
	"teleport": {"exitVel": [0, 0, 0]},
	"bubble": {"count": 3, "rise": 6, "period": 6, "phase": 0},
	"lowgrav": {"gravity": 0.35},
	"button": {"duration": 6},
	"door": {},
	"lever": {"duration": 4, "cooldown": 8},
	"trapdoor": {},
	"memory": {"cols": 3, "rows": 5, "gap": 0.25, "traps": 0.5},
	"itembox": {"respawn": 6},
	"coin": {},
	"wind": {"force": [24, 0, 0], "period": 3, "phase": 0},
	"popper": {"cols": 3, "rows": 3, "period": 2.4, "up": 0.45, "chance": 0.45, "phase": 0},
	"geyser": {"period": 4, "on": 0.4, "phase": 0},
	"rockfall": {"count": 2, "stone": 1, "interval": 3, "warn": 1.4, "phase": 0},
	"start": {}, "finish": {}, "checkpoint": {}, "platform": {}, "ice": {}, "fakewall": {},
}
## Champs obligatoires en plus de pos et size.
const REQUIRED := {
	"moving": ["delta"], "conveyor": ["dir"], "cannon": ["dir"], "boulder": ["delta"], "launcher": ["to"], "zipline": ["to"],
	"teleport": ["to"], "button": ["link"], "door": ["link"], "lever": ["link"], "trapdoor": ["link"],
}
## Champs entiers (le JSON les lit en flottants).
const INTS := ["count", "cols", "rows"]

static var _re: RegEx


## Crée le dossier des niveaux perso (user://levels/parkour) pour qu'on puisse y déposer des fichiers.
static func ensure_user_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIRS[-1])


static func valid_name(n: String) -> bool:
	if _re == null:
		_re = RegEx.create_from_string(NAME_RE)
	return _re.search(n) != null


## Noms des niveaux disponibles, triés.
static func list_levels() -> Array:
	var names := {}
	for d: String in DIRS:
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".json") and valid_name(f.get_basename()):
				names[f.get_basename()] = true
	var out := names.keys()
	out.sort()
	return out


## Empreinte du dossier des niveaux (noms + dates) : change quand un niveau est ajouté, modifié ou supprimé.
static func fingerprint() -> String:
	var parts: Array = []
	for d: String in DIRS:
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".json"):
				parts.append("%s/%s@%d" % [d, f, FileAccess.get_modified_time(d.path_join(f))])
	return ",".join(parts)


## Fichier du niveau (perso prioritaire), "" s'il n'existe pas.
static func file_of(n: String) -> String:
	if not valid_name(n):
		return ""
	for i in range(DIRS.size() - 1, -1, -1):
		var f: String = DIRS[i].path_join(n + ".json")
		if FileAccess.file_exists(f):
			return f
	return ""


## Lit un niveau et applique les valeurs par défaut. Renvoie {} (avec un message dans `err[0]`) s'il est invalide.
static func read_level(n: String, err: Array = []) -> Dictionary:
	var f := file_of(n)
	if f == "":
		err.append("Niveau introuvable : « %s »." % n)
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
	if not raw is Dictionary:
		err.append("%s : JSON invalide." % f)
		return {}
	var level := normalize(raw, err)
	if level.is_empty():
		return {}
	level["name"] = n
	return level


## Applique le schéma (défauts, champs obligatoires) à un niveau brut. {} si invalide.
static func normalize(raw: Dictionary, err: Array = []) -> Dictionary:
	var level := {
		"name": str(raw.get("name", "")), "title": str(raw.get("title", "")), "author": str(raw.get("author", "")),
		"difficulty": int(raw.get("difficulty", 2)), "elements": [],
	}
	if raw.get("sky") is String:
		level["sky"] = raw["sky"]
	if raw.get("sea") is String:
		level["sea"] = raw["sea"]
	if raw.get("killY") is float or raw.get("killY") is int:
		level["killY"] = float(raw["killY"])
	var els: Variant = raw.get("elements")
	if not els is Array or els.size() < 2:
		err.append("Il faut au moins 2 éléments.")
		return {}
	for k in els.size():
		var e: Variant = els[k]
		if not e is Dictionary or not DEFAULTS.has(e.get("type")):
			err.append("Élément #%d : type inconnu." % k)
			return {}
		var out: Dictionary = e.duplicate(true)
		if not _vec(out.get("pos"), 3) or not _vec(out.get("size"), 3):
			err.append("Élément #%d : pos et size doivent être des triplets de nombres." % k)
			return {}
		for req: String in REQUIRED.get(out["type"], []):
			if not out.has(req):
				err.append("Élément #%d (%s) : champ « %s » manquant." % [k, out["type"], req])
				return {}
		if not out.has("yaw"):
			out["yaw"] = 0.0
		var defs: Dictionary = DEFAULTS[out["type"]]
		for key: String in defs:
			if not out.has(key):
				var d: Variant = defs[key]
				out[key] = d.duplicate() if d is Array else d
		for key: String in out:
			if key in INTS:
				out[key] = int(out[key])
			elif out[key] is int:
				out[key] = float(out[key])
			elif out[key] is Array:
				out[key] = out[key].map(func(x: Variant) -> Variant: return float(x) if x is int else x)
		level["elements"].append(out)
	return level


static func _vec(v: Variant, n: int) -> bool:
	if not v is Array or v.size() != n:
		return false
	for x: Variant in v:
		if not (x is float or x is int):
			return false
	return true
