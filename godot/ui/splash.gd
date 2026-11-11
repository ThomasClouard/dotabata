extends Control
## Écran de chargement : dégradé, logo « Dotabata! » + ドタバタ (ui/logo.gd), « Chargement… ».
## En partant, il se fond dans l'écran titre, qui reprend le même logo en haut à gauche.

const MIN_MS := 1600  # durée minimale d'affichage depuis le lancement

var _logo: Logo
var _load: Label
var _t := 0.0
var _leaving := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background())

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_logo = Logo.new()
	box.add_child(_logo)
	box.add_child(UI.outlined("« do-ta-ba-ta » : le joyeux chahut, en japonais", 18, Color.WHITE, 6))
	_load = UI.outlined("Chargement…", 14, Color.WHITE, 4)
	box.add_child(_load)


## Dégradé rose → violet → bleu de l'écran de chargement (repris par le menu).
static func background() -> TextureRect:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color("#ff8fab"), Color("#c77dff"), Color("#4361ee")])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.2, 0.0)
	tex.fill_to = Vector2(0.8, 1.0)
	var bg := TextureRect.new()
	bg.texture = tex
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg


func _process(dt: float) -> void:
	_t += dt
	_load.modulate.a = 0.6 + 0.35 * cos(_t * TAU / 1.2)


## Efface l'écran (après la durée minimale) : le logo rétrécit et file vers le haut à gauche pendant le fondu.
## Sans effet s'il est déjà parti.
func dismiss() -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.tween_interval(maxf(0.0, (MIN_MS - Time.get_ticks_msec()) / 1000.0))
	tw.tween_callback(func() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_logo.pivot_offset = Vector2.ZERO)
	tw.set_parallel(true)
	tw.tween_property(_logo, "scale", Vector2(0.55, 0.55), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_logo, "global_position", Vector2(48, 28), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "modulate:a", 0.0, 0.55).set_delay(0.1)
	tw.chain().tween_callback(queue_free)
