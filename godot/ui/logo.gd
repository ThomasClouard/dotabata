class_name Logo
extends VBoxContainer
## Logo « Dotabata! » (lettres qui sautillent) et ドタバタ dessiné en traits, sans police japonaise : identique
## partout. Sert à l'écran de chargement et à l'écran titre (taille réglable par `scale_factor`).

const UNIT := 110.0  # avance d'un kana dans sa boîte 100 × 100

var scale_factor := 1.0
var align := BoxContainer.ALIGNMENT_CENTER
var _kana := Control.new()
var _letters: Array[Label] = []
var _glyphs: Array = []  # par kana : liste de traits (PackedVector2Array)
var _t := 0.0


static func _q(a: Vector2, c: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(11):
		var u := i / 10.0
		out.append(a.lerp(c, u).lerp(c.lerp(b, u), u))
	return out


static func _seg(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, b])


func _init(scale := 1.0, alignment_ := BoxContainer.ALIGNMENT_CENTER) -> void:
	scale_factor = scale
	align = alignment_


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", int(10 * scale_factor))
	var to := [_seg(Vector2(40, 8), Vector2(40, 95)), _seg(Vector2(42, 44), Vector2(76, 64))]
	var ta := [_seg(Vector2(46, 6), Vector2(20, 44)), PackedVector2Array([Vector2(34, 26), Vector2(80, 26)]) + _q(Vector2(80, 26), Vector2(74, 66), Vector2(32, 96)), _seg(Vector2(34, 50), Vector2(66, 68))]
	var ha := [_seg(Vector2(36, 28), Vector2(10, 82)), _q(Vector2(60, 28), Vector2(78, 52), Vector2(92, 82))]
	var dk := [_seg(Vector2(74, 6), Vector2(82, 22)), _seg(Vector2(88, 2), Vector2(96, 18))]
	_glyphs = [to + dk, ta, ha + dk, ta]

	# titre : une étiquette par lettre pour les faire sautiller
	var row := HBoxContainer.new()
	row.alignment = align
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in "Dotabata!":
		var l := UI.outlined(c, int(104 * scale_factor), UI.YELLOW, int(20 * scale_factor))
		l.add_theme_color_override("font_shadow_color", UI.INK)
		l.add_theme_constant_override("shadow_offset_x", int(5 * scale_factor))
		l.add_theme_constant_override("shadow_offset_y", int(5 * scale_factor))
		var slot := Control.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(l)
		row.add_child(slot)
		_letters.append(l)
	add_child(row)

	_kana.custom_minimum_size = Vector2(440, 130) * scale_factor
	_kana.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match align:
		BoxContainer.ALIGNMENT_BEGIN:
			_kana.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		BoxContainer.ALIGNMENT_END:
			_kana.size_flags_horizontal = Control.SIZE_SHRINK_END
		_:
			_kana.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_kana.draw.connect(_draw_kana)
	add_child(_kana)


func _process(dt: float) -> void:
	_t += dt
	for i in _letters.size():
		_letters[i].get_parent().custom_minimum_size = _letters[i].get_minimum_size()  # taille réelle une fois le thème appliqué
		_letters[i].position.y = hop(_t - i * 0.07) * scale_factor
	_kana.queue_redraw()


## Saut d'une lettre : rebond vers le haut toutes les 0,9 s.
static func hop(t: float) -> float:
	var u := fposmod(t / 0.9, 1.0)
	return -14.0 * sin(u / 0.6 * PI) if u < 0.6 else 2.0 * sin((u - 0.6) / 0.4 * PI)


func _draw_kana() -> void:
	var s := _kana.size.x / 454.0
	var x0 := (_kana.size.x - 430.0 * s) / 2.0
	var origin := Vector2(x0, 12.0 * s)
	for layer in [[UI.INK, 24.0], [Color.WHITE, 12.0]]:
		var col: Color = layer[0]
		var w: float = layer[1] * s
		for i in _glyphs.size():
			var off := origin + Vector2(i * UNIT * s, hop(_t - i * 0.12) * scale_factor)
			for stroke: PackedVector2Array in _glyphs[i]:
				var pts := PackedVector2Array()
				for p in stroke:
					pts.append(off + p * s)
				_kana.draw_polyline(pts, col, w, true)
				for p in pts:  # bouts et coudes arrondis
					_kana.draw_circle(p, w / 2.0, col)
