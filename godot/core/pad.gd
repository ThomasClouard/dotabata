class_name Pad
extends RefCounted
## Manette : boutons réglables (écran Options → Manette), enregistrés dans jeux.cfg (section « manette »).
## Chaque action de jeu se traduit en « touche virtuelle » de GameInput (Space, KeyE, KeyF…), si bien que les
## mini-jeux n'ont rien de particulier à faire ; les actions des menus alimentent ui_accept / ui_cancel.
## Le stick gauche déplace, le stick droit tourne la caméra (non réassignables).
## Un code de bouton est un JOY_BUTTON_* (0 à 20), ou LT / RT pour les gâchettes (qui sont des axes).

const LT := 100
const RT := 101
const DEADZONE := 0.2

## group : "menu" ou "jeu" (un même bouton ne sert qu'à une action par groupe ; A valide les menus et fait sauter).
const ACTIONS := [
	{"id": "valider", "name": "Valider", "group": "menu", "default": JOY_BUTTON_A, "ui": "ui_accept"},
	{"id": "retour", "name": "Retour", "group": "menu", "default": JOY_BUTTON_B, "ui": "ui_cancel"},
	{"id": "sauter", "name": "Sauter", "group": "jeu", "default": JOY_BUTTON_A, "key": "Space"},
	{"id": "utiliser", "name": "Utiliser l'objet (parcours)", "group": "jeu", "default": JOY_BUTTON_X, "key": "KeyE"},
	{"id": "action", "name": "Poser un bloc / tirer (mortier)", "group": "jeu", "default": RT, "key": "KeyF"},
	{"id": "retirer", "name": "Retirer un bloc (mortier)", "group": "jeu", "default": LT, "key": "PadRemove"},
	{"id": "checkpoint", "name": "Revenir au checkpoint (parcours)", "group": "jeu", "default": JOY_BUTTON_LEFT_SHOULDER, "key": "PadCp"},
	{"id": "depart", "name": "Recommencer au départ (parcours)", "group": "jeu", "default": JOY_BUTTON_BACK, "key": "PadStart"},
	{"id": "materiau", "name": "Changer de matériau (mortier)", "group": "jeu", "default": JOY_BUTTON_Y, "key": "PadMat"},
	{"id": "panneau", "name": "Régler la partie (lobby)", "group": "jeu", "default": JOY_BUTTON_START, "key": "PadPanel"},
]

const NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Select", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "Croix ↑", JOY_BUTTON_DPAD_DOWN: "Croix ↓", JOY_BUTTON_DPAD_LEFT: "Croix ←", JOY_BUTTON_DPAD_RIGHT: "Croix →",
	JOY_BUTTON_MISC1: "Partage", JOY_BUTTON_TOUCHPAD: "Pavé tactile",
	LT: "LT", RT: "RT",
}

## id de l'action → code de bouton.
static var bindings := {}
## Caméra au stick droit : vitesse et axe vertical inversé.
static var look_sens := 1.0
static var invert_y := false


static func label(code: int) -> String:
	return NAMES.get(code, "Bouton %d" % code)


static func action(id: String) -> Dictionary:
	for a: Dictionary in ACTIONS:
		if a["id"] == id:
			return a
	return {}


static func load_cfg(cf: ConfigFile) -> void:
	for a: Dictionary in ACTIONS:
		bindings[a["id"]] = int(cf.get_value("manette", a["id"], a["default"]))
	look_sens = clampf(float(cf.get_value("manette", "camera", 1.0)), 0.25, 3.0)
	invert_y = bool(cf.get_value("manette", "inverser_y", false))
	apply_ui()


static func save_cfg(cf: ConfigFile) -> void:
	for a: Dictionary in ACTIONS:
		cf.set_value("manette", a["id"], bindings.get(a["id"], a["default"]))
	cf.set_value("manette", "camera", look_sens)
	cf.set_value("manette", "inverser_y", invert_y)


static func reset() -> void:
	for a: Dictionary in ACTIONS:
		bindings[a["id"]] = a["default"]
	look_sens = 1.0
	invert_y = false
	apply_ui()


## Assigne un bouton à une action ; l'action du même groupe qui l'avait prend l'ancien bouton (échange).
static func assign(id: String, code: int) -> void:
	var a := action(id)
	var old: int = bindings.get(id, a["default"])
	for b: Dictionary in ACTIONS:
		if b["id"] != id and b["group"] == a["group"] and bindings.get(b["id"]) == code:
			bindings[b["id"]] = old
	bindings[id] = code
	apply_ui()


## Met à jour ui_accept / ui_cancel (menus) avec les boutons choisis, à la place des boutons de manette précédents.
static func apply_ui() -> void:
	for a: Dictionary in ACTIONS:
		if not a.has("ui"):
			continue
		var ui: String = a["ui"]
		for e in InputMap.action_get_events(ui):
			if e is InputEventJoypadButton or (e is InputEventJoypadMotion and (e.axis == JOY_AXIS_TRIGGER_LEFT or e.axis == JOY_AXIS_TRIGGER_RIGHT)):
				InputMap.action_erase_event(ui, e)
		var code: int = bindings.get(a["id"], a["default"])
		if code == LT or code == RT:
			var m := InputEventJoypadMotion.new()
			m.axis = JOY_AXIS_TRIGGER_LEFT if code == LT else JOY_AXIS_TRIGGER_RIGHT
			m.axis_value = 1.0
			InputMap.action_add_event(ui, m)
		else:
			var b := InputEventJoypadButton.new()
			b.button_index = code
			InputMap.action_add_event(ui, b)


## Touches virtuelles des actions de jeu liées à ce bouton.
static func keys_for(code: int) -> Array:
	var out: Array = []
	for a: Dictionary in ACTIONS:
		if a["group"] == "jeu" and bindings.get(a["id"], a["default"]) == code:
			out.append(a["key"])
	return out


## Première manette branchée (-1 s'il n'y en a pas).
static func device() -> int:
	var pads := Input.get_connected_joypads()
	return pads[0] if not pads.is_empty() else -1


static func stick(dev: int, ax: JoyAxis, ay: JoyAxis) -> Vector2:
	if dev < 0:
		return Vector2.ZERO
	var v := Vector2(Input.get_joy_axis(dev, ax), Input.get_joy_axis(dev, ay))
	var l := v.length()
	if l < DEADZONE:
		return Vector2.ZERO
	return v / l * minf(1.0, (l - DEADZONE) / (1.0 - DEADZONE))
