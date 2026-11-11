extends Control
## Écran de chargement : « Dotabata! » et ドタバタ dessiné en traits (aucune police japonaise requise,
## donc identique sur Windows et sur le web). Même tracé que le client navigateur (client/index.html).

const MIN_MS := 1600  # durée minimale d'affichage depuis le lancement
const UNIT := 110.0   # avance d'un kana dans sa boîte 100 × 100

var _kana := Control.new()
var _letters: Array[Label] = []
var _load: Label
var _glyphs: Array = []  # par kana : liste de traits (PackedVector2Array)
var _t := 0.0
var _leaving := false


static func _q(a: Vector2, c: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(11):
		var u := i / 10.0
		out.append(a.lerp(c, u).lerp(c.lerp(b, u), u))
	return out


static func _seg(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, b])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var to := [_seg(Vector2(40, 8), Vector2(40, 95)), _seg(Vector2(42, 44), Vector2(76, 64))]
	var ta := [_seg(Vector2(46, 6), Vector2(20, 44)), PackedVector2Array([Vector2(34, 26), Vector2(80, 26)]) + _q(Vector2(80, 26), Vector2(74, 66), Vector2(32, 96)), _seg(Vector2(34, 50), Vector2(66, 68))]
	var ha := [_seg(Vector2(36, 28), Vector2(10, 82)), _q(Vector2(60, 28), Vector2(78, 52), Vector2(92, 82))]
	var dk := [_seg(Vector2(74, 6), Vector2(82, 22)), _seg(Vector2(88, 2), Vector2(96, 18))]
	_glyphs = [to + dk, ta, ha + dk, ta]

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
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	# titre : une étiquette par lettre pour les faire sautiller
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	for c in "Dotabata!":
		var l := UI.outlined(c, 104, UI.YELLOW, 20)
		l.add_theme_color_override("font_shadow_color", UI.INK)
		l.add_theme_constant_override("shadow_offset_x", 5)
		l.add_theme_constant_override("shadow_offset_y", 5)
		var slot := Control.new()
		slot.add_child(l)
		row.add_child(slot)
		_letters.append(l)
	box.add_child(row)

	_kana.custom_minimum_size = Vector2(440, 130)
	_kana.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_kana.draw.connect(_draw_kana)
	box.add_child(_kana)

	box.add_child(UI.outlined("« do-ta-ba-ta » : le joyeux chahut, en japonais", 18, Color.WHITE, 6))
	_load = UI.outlined("Chargement…", 14, Color.WHITE, 4)
	box.add_child(_load)


func _process(dt: float) -> void:
	_t += dt
	for i in _letters.size():
		_letters[i].get_parent().custom_minimum_size = _letters[i].get_minimum_size()  # taille réelle une fois le thème appliqué
		_letters[i].position.y = _hop(_t - i * 0.07)
	_load.modulate.a = 0.6 + 0.35 * cos(_t * TAU / 1.2)
	_kana.queue_redraw()


## Saut d'une lettre : rebond vers le haut toutes les 0,9 s (comme l'animation CSS).
func _hop(t: float) -> float:
	var u := fposmod(t / 0.9, 1.0)
	return -14.0 * sin(u / 0.6 * PI) if u < 0.6 else 2.0 * sin((u - 0.6) / 0.4 * PI)


func _draw_kana() -> void:
	var s := _kana.size.x / 454.0
	var origin := Vector2((_kana.size.x - 430.0 * s) / 2.0, 12.0 * s)
	for layer in [[UI.INK, 24.0], [Color.WHITE, 12.0]]:
		var col: Color = layer[0]
		var w: float = layer[1] * s
		for i in _glyphs.size():
			var off := origin + Vector2(i * UNIT * s, _hop(_t - i * 0.12))
			for stroke: PackedVector2Array in _glyphs[i]:
				var pts := PackedVector2Array()
				for p in stroke:
					pts.append(off + p * s)
				_kana.draw_polyline(pts, col, w, true)
				for p in pts:  # bouts et coudes arrondis
					_kana.draw_circle(p, w / 2.0, col)


## Efface l'écran (après la durée minimale). Sans effet s'il est déjà parti.
func dismiss() -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.tween_interval(maxf(0.0, (MIN_MS - Time.get_ticks_msec()) / 1000.0))
	tw.tween_callback(func() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE)
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(queue_free)
