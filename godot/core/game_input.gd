class_name GameInput
extends Node
## Clavier + souris + manette. Les touches sont lues par position physique : ZQSD marche tel quel en AZERTY.
## Les boutons de la manette (réglables, voir Pad) enfoncent les mêmes touches virtuelles que le clavier ;
## les sticks donnent `move` (déplacement) et `look` (caméra).
## Les noms de touches reprennent ceux du client d'origine (« KeyW », « Space », « Mouse0 »…).

const KEYMAP := {
	KEY_W: "KeyW", KEY_A: "KeyA", KEY_S: "KeyS", KEY_D: "KeyD", KEY_F: "KeyF", KEY_R: "KeyR", KEY_E: "KeyE",
	KEY_SPACE: "Space", KEY_UP: "ArrowUp", KEY_DOWN: "ArrowDown", KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight",
	KEY_1: "Digit1", KEY_2: "Digit2", KEY_3: "Digit3", KEY_KP_1: "Numpad1", KEY_KP_2: "Numpad2", KEY_KP_3: "Numpad3",
}

var dx := 0.0
var dy := 0.0
var move := Vector2.ZERO  # stick gauche (x : droite, y : arrière)
var look := Vector2.ZERO  # stick droit
var locked := false
var _triggers := {Pad.LT: false, Pad.RT: false}
var _keys := {}
var _pressed := {}
var _released := {}
var _dragging := false


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey:
		if ev.echo:
			return
		if ev.physical_keycode == KEY_ESCAPE:
			if ev.pressed:
				release_mouse()
			return
		var code: Variant = KEYMAP.get(ev.physical_keycode)
		if code == null:
			return
		if ev.pressed:
			if not _keys.has(code):
				_pressed[code] = true
			_keys[code] = true
		elif _keys.erase(code):
			_released[code] = true
	elif ev is InputEventMouseButton:
		var code := "Mouse0"
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			code = "Mouse2"
		elif ev.button_index == MOUSE_BUTTON_MIDDLE:
			code = "Mouse1"
		elif ev.button_index != MOUSE_BUTTON_LEFT:
			return
		if ev.pressed:
			get_viewport().gui_release_focus()
			# le premier clic capture la souris ; il ne compte pas comme une action de jeu
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				_dragging = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				return
			_pressed[code] = true
			_keys[code] = true
		else:
			_dragging = false
			if _keys.erase(code):
				_released[code] = true
	elif ev is InputEventJoypadButton:
		_pad(ev.button_index, ev.pressed)
	elif ev is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or _dragging:
			dx += ev.screen_relative.x
			dy += ev.screen_relative.y


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_keys.clear()


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_dragging = false
	for k in ["Mouse0", "Mouse1", "Mouse2"]:
		if _keys.erase(k):
			_released[k] = true


## Bouton de manette (ou gâchette) enfoncé / relâché → touches virtuelles des actions qui lui sont liées.
func _pad(code: int, pressed: bool) -> void:
	for k: String in Pad.keys_for(code):
		if pressed:
			if not _keys.has(k):
				_pressed[k] = true
			_keys[k] = true
		elif _keys.erase(k):
			_released[k] = true


func begin_frame() -> void:
	locked = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	move = Vector2.ZERO
	look = Vector2.ZERO
	if not is_processing_unhandled_input():
		return  # menus : la manette y passe par les actions ui_*
	var dev := Pad.device()
	if dev < 0:
		return
	move = Pad.stick(dev, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	look = Pad.stick(dev, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	# gâchettes : ce sont des axes ; enfoncées au-delà de 0,55, relâchées sous 0,35
	for code: int in _triggers:
		var v := Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT if code == Pad.LT else JOY_AXIS_TRIGGER_RIGHT)
		var on: bool = v > 0.55 or (_triggers[code] and v > 0.35)
		if on != _triggers[code]:
			_triggers[code] = on
			_pad(code, on)


func down(a: String, b := "") -> bool:
	return _keys.has(a) or (b != "" and _keys.has(b))


## Vrai une seule fois, à l'image où la touche vient d'être enfoncée.
func hit(a: String, b := "") -> bool:
	return _pressed.has(a) or (b != "" and _pressed.has(b))


func up(a: String, b := "") -> bool:
	return _released.has(a) or (b != "" and _released.has(b))


func end_frame() -> void:
	_pressed.clear()
	_released.clear()
	dx = 0.0
	dy = 0.0
