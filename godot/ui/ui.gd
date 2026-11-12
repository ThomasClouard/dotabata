class_name UI
extends RefCounted
## Thème et petites fabriques de contrôles : cartes blanches arrondies, boutons jaunes, encre violette.

const INK := Color("#2b2140")
const CARD := Color(1, 1, 1, 0.94)
const ACCENT := Color("#ff4d6d")
const ACCENT2 := Color("#4361ee")
const YELLOW := Color("#ffd60a")
const MUTED := Color("#6b6288")

static var theme: Theme
static var font: Font


static func sbox(bg: Color, radius := 12, pad_x := 14, pad_y := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.anti_aliasing = true
	return s


## Bouton « en relief » : un rebord plus foncé dessous, qui disparaît quand on appuie (le bouton s'enfonce).
static func relief(bg: Color, radius := 14, pad_x := 14, pad_y := 8, pressed := false) -> StyleBoxFlat:
	var s := sbox(bg, radius, pad_x, pad_y)
	s.border_color = bg.darkened(0.28)
	s.border_width_bottom = 1 if pressed else 5
	s.content_margin_top += 4 if pressed else 0
	s.shadow_color = Color(INK.r, INK.g, INK.b, 0.18 if not pressed else 0.1)
	s.shadow_size = 6 if not pressed else 2
	s.shadow_offset = Vector2(0, 4 if not pressed else 1)
	return s


static func _shadow(s: StyleBoxFlat, dy: float, alpha: float) -> StyleBoxFlat:
	s.shadow_color = Color(INK.r, INK.g, INK.b, alpha)
	s.shadow_size = int(dy * 2.0)
	s.shadow_offset = Vector2(0, dy)
	return s


static func init_theme() -> void:
	if theme:
		return
	# Fredoka (ronde et grasse, licence OFL : ui/fonts/OFL.txt), épaisseur 600 ; les caractères qu'elle n'a pas
	# (japonais du logo, symboles) viennent des polices du système
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Segoe UI", "Yu Gothic UI", "Meiryo", "Trebuchet MS", "sans-serif"])
	sys.font_weight = 700
	var ff: FontFile = load("res://ui/fonts/Fredoka.ttf")
	ff.fallbacks = [sys]
	var f := FontVariation.new()
	f.base_font = ff
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	font = f
	Gfx.font = f
	var t := Theme.new()
	t.default_font = f
	t.default_font_size = 15

	t.set_color("font_color", "Label", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_stylebox("panel", "PanelContainer", _shadow(sbox(CARD, 22, 18, 16), 7, 0.16))

	var normal := relief(YELLOW)
	var hover := relief(YELLOW.lightened(0.22))
	hover.border_color = YELLOW.darkened(0.28)
	var pressed := relief(YELLOW.darkened(0.04), 14, 14, 8, true)
	var disabled := sbox(Color("#e6e3ee"))
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus_ring())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("#8c86a0"))

	var field := sbox(Color.WHITE, 10, 8, 5)
	field.border_color = Color("#cfc7e6")
	field.set_border_width_all(2)
	var field_focus: StyleBoxFlat = field.duplicate()
	field_focus.border_color = ACCENT2
	var field_off: StyleBoxFlat = field.duplicate()
	field_off.bg_color = Color("#eeeeee")
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field_off)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_uneditable_color", "LineEdit", Color("#777777"))
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color("#a59fb8"))
	t.set_color("selection_color", "LineEdit", Color(ACCENT2.r, ACCENT2.g, ACCENT2.b, 0.3))
	for c in ["up_icon_modulate", "down_icon_modulate", "up_hover_icon_modulate", "down_hover_icon_modulate", "up_pressed_icon_modulate", "down_pressed_icon_modulate"]:
		t.set_color(c, "SpinBox", INK)
	for c in ["up_disabled_icon_modulate", "down_disabled_icon_modulate"]:
		t.set_color(c, "SpinBox", Color("#b5b0c4"))

	for st in ["normal", "hover", "pressed"]:
		t.set_stylebox(st, "OptionButton", field if st != "hover" else field_focus)
	t.set_stylebox("focus", "OptionButton", focus_ring(10))
	t.set_stylebox("disabled", "OptionButton", field_off)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "OptionButton", INK)
	t.set_color("font_disabled_color", "OptionButton", Color("#777777"))
	t.set_color("modulate_arrow", "OptionButton", INK)

	var chip := sbox(Color("#efeaff"), 10, 8, 3)
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		t.set_stylebox(st, "CheckBox", chip)
	t.set_stylebox("focus", "CheckBox", focus_ring(10))

	# curseurs (options du menu)
	var rail := sbox(Color("#e6e1f5"), 6, 0, 4)
	t.set_stylebox("slider", "HSlider", rail)
	var fill_rail := sbox(ACCENT2, 6, 0, 4)
	t.set_stylebox("grabber_area", "HSlider", fill_rail)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_rail)
	t.set_stylebox("focus", "HSlider", focus_ring(8))
	var knob := _knob_icon()
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "CheckBox", INK)
	t.set_color("font_disabled_color", "CheckBox", Color("#777777"))
	t.set_font_size("font_size", "CheckBox", 13)
	var box_off := _check_icon(false)
	var box_on := _check_icon(true)
	t.set_icon("unchecked", "CheckBox", box_off)
	t.set_icon("checked", "CheckBox", box_on)
	t.set_icon("unchecked_disabled", "CheckBox", box_off)
	t.set_icon("checked_disabled", "CheckBox", box_on)

	t.set_stylebox("background", "ProgressBar", sbox(Color(INK.r, INK.g, INK.b, 0.14), 8, 0, 0))
	t.set_stylebox("fill", "ProgressBar", sbox(Color("#70e000"), 8, 0, 0))
	theme = t


## Contour de focus (navigation au clavier ou à la manette) : liseré bleu autour du contrôle.
static func focus_ring(radius := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.set_corner_radius_all(radius + 3)
	s.border_color = ACCENT2
	s.set_border_width_all(4)
	s.set_expand_margin_all(4)
	s.anti_aliasing = true
	return s


static func _knob_icon() -> ImageTexture:
	var s := 22
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s / 2.0 - 0.5, s / 2.0 - 0.5)
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c)
			if d <= s / 2.0 - 1.0:
				img.set_pixel(x, y, YELLOW if d < s / 2.0 - 4.0 else INK)
	return ImageTexture.create_from_image(img)


static func _check_icon(on: bool) -> ImageTexture:
	var s := 18
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var edge := x < 2 or y < 2 or x >= s - 2 or y >= s - 2
			var c := Color.WHITE
			if edge:
				c = Color("#8f86b0")
			elif on and x >= 4 and y >= 4 and x < s - 4 and y < s - 4:
				c = ACCENT2
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func label(text: String, size := 15, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Texte secondaire qui passe à la ligne.
static func small(text: String) -> Label:
	var l := label(text, 12, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 100
	return l


static func h1(text: String) -> Label:
	var l := label(text, 30, ACCENT)
	l.add_theme_color_override("font_shadow_color", YELLOW)
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func h2(text: String) -> Label:
	return label(text.to_upper(), 15, ACCENT2)


## Texte blanc cerné d'encre, lisible par-dessus le décor.
static func outlined(text: String, size: int, color := Color.WHITE, outline := 8) -> Label:
	var l := label(text, size, color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Bouton. `kind` : "" (normal), "small" ou "big".
static func button(text: String, kind := "", on_press: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	squash_on_press(b)
	if kind == "small":
		for st in ["normal", "hover", "pressed", "disabled"]:
			var s: StyleBoxFlat = theme.get_stylebox(st, "Button").duplicate()
			s.content_margin_left = 10
			s.content_margin_right = 10
			s.content_margin_top = 3 if st != "pressed" else 7
			s.content_margin_bottom = 3
			b.add_theme_stylebox_override(st, s)
	elif kind == "big":
		for st in ["normal", "hover", "pressed"]:
			var s := relief(ACCENT.lightened(0.12) if st == "hover" else ACCENT, 16, 14, 12, st == "pressed")
			s.border_color = ACCENT.darkened(0.3)
			b.add_theme_stylebox_override(st, s)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, Color.WHITE)
		b.add_theme_font_size_override("font_size", 20)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## Gros bouton du menu principal : large, texte aligné à gauche, navigable au clavier et à la manette.
## `accent` : rose (action principale) au lieu de jaune.
static func menu_button(text: String, on_press: Callable = Callable(), accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320, 0)
	var base := ACCENT if accent else YELLOW
	for st in ["normal", "hover", "pressed", "focus"]:
		var s: StyleBoxFlat = theme.get_stylebox("normal" if st == "focus" else st, "Button").duplicate()
		if st == "focus":
			s = focus_ring(16)
		else:
			s = relief(base.lightened(0.18) if st == "hover" else base, 18, 26, 12, st == "pressed")
			s.border_color = base.darkened(0.3)
			s.border_width_bottom = 7 if st != "pressed" else 2
			s.content_margin_top = 12 if st != "pressed" else 17
		b.add_theme_stylebox_override(st, s)
	var fc := Color.WHITE if accent else INK
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, fc)
	b.add_theme_font_size_override("font_size", 26)
	# léger grossissement au survol ou au focus
	var grow := func(on: bool) -> void:
		b.pivot_offset = b.size / 2.0
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE * (1.05 if on else 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.mouse_entered.connect(func() -> void: grow.call(true))
	b.mouse_exited.connect(func() -> void: grow.call(b.has_focus()))
	b.focus_entered.connect(func() -> void: grow.call(true))
	b.focus_exited.connect(func() -> void: grow.call(false))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## Entoure un bouton d'un liseré pour marquer la sélection.
static func mark_selected(b: Button, color := ACCENT2) -> void:
	for st in ["normal", "hover", "pressed"]:
		var src: StyleBox = b.get_theme_stylebox(st) if b.has_theme_stylebox_override(st) else theme.get_stylebox(st, "Button")
		var s: StyleBoxFlat = src.duplicate()
		s.border_color = color
		s.set_border_width_all(3)
		b.add_theme_stylebox_override(st, s)


static func dot(color: Color, size := 14) -> Panel:
	var p := Panel.new()
	var s := sbox(color, size, 0, 0)
	s.border_color = Color(0, 0, 0, 0.25)
	s.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Ligne « libellé … contrôles ».
static func row(text: String, controls: Array = []) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	if text != "":
		var l := label(text, 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 110
		h.add_child(l)
	for c: Control in controls:
		h.add_child(c)
	return h


static func flow(controls: Array = []) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	for c: Control in controls:
		f.add_child(c)
	return f


static func card() -> PanelContainer:
	return PanelContainer.new()


static func bar(width: float, height: float, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	b.custom_minimum_size = Vector2(width, height)
	var fill := sbox(color, 8, 0, 0)
	fill.border_color = color.lightened(0.35)
	fill.border_width_top = int(maxf(1.0, height * 0.25))  # reflet clair en haut de la jauge
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func set_bar_color(b: ProgressBar, color: Color) -> void:
	var s: StyleBoxFlat = b.get_theme_stylebox("fill")
	s.bg_color = color


## Rend un conteneur et ses descendants transparents aux clics (ils atteignent alors le jeu).
static func passive(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hex(c: int) -> String:
	return "#%06x" % c


# ---------- animations ----------

## Apparition « pop » : le contrôle grossit depuis `from` avec un rebond, en fondu, après `delay` secondes.
## Le pivot est pris au centre au moment où l'animation démarre (la taille est alors connue).
static func pop_in(c: Control, delay := 0.0, from := 0.6, dur := 0.32) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2.ONE * from
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: c.pivot_offset = c.size / 2.0)
	tw.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(c, "modulate:a", 1.0, dur * 0.5)


## Fait apparaître les enfants d'un conteneur l'un après l'autre.
static func stagger(parent: Node, step := 0.06, delay := 0.1, from := 0.8) -> void:
	var i := 0
	for c in parent.get_children():
		if c is Control:
			pop_in(c, delay + i * step, from, 0.28)
			i += 1


## Nombre qui défile de `a` à `b` dans un Label (`fmt` : format avec un %d).
static func count_up(l: Label, a: int, b: int, delay := 0.0, dur := 0.6, fmt := "%d") -> void:
	l.text = fmt % a
	if a == b:
		return
	var tw := l.create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v: float) -> void: l.text = fmt % roundi(v), float(a), float(b), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Petit écrasement d'un bouton au clic.
static func squash_on_press(b: Button) -> void:
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size / 2.0
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.06, 0.92), 0.06)
		tw.tween_property(b, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))


## Jauge avec barre « retard » : quand la valeur baisse, une barre claire reste un instant derrière puis la
## rattrape (on voit ce qu'on vient de perdre). Appeler `tick_lag` à chaque image.
static func lag_bar(width: float, height: float, color: Color) -> ProgressBar:
	var b := bar(width, height, color)
	b.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	var lag := ProgressBar.new()
	lag.name = "retard"
	lag.show_percentage = false
	lag.max_value = 1.0
	lag.step = 0.0
	lag.value = 1.0
	lag.show_behind_parent = true
	lag.set_anchors_preset(Control.PRESET_FULL_RECT)
	lag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lag.add_theme_stylebox_override("fill", sbox(Color("#ffffff"), 8, 0, 0))
	b.add_child(lag)
	b.set_meta("hold", 0.0)
	return b


static func tick_lag(b: ProgressBar, dt: float) -> void:
	var lag: ProgressBar = b.get_node_or_null("retard")
	if lag == null:
		return
	if b.value >= lag.value:
		lag.value = b.value
		b.set_meta("hold", 0.45)
		return
	var hold: float = b.get_meta("hold", 0.0) - dt
	b.set_meta("hold", hold)
	if hold < 0.0:
		lag.value = maxf(b.value, lag.value - dt * 0.5)
