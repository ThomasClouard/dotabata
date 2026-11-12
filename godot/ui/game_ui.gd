class_name GameUI
extends CanvasLayer
## Interface par-dessus le jeu : accueil (liste des serveurs, création), panneau du lobby (formulaire généré depuis les réglages
## déclarés par chaque jeu), bandeau de manche, toasts, scores, podium.

signal settings_changed(s: Dictionary)
signal bots_changed(n: int)
## Hôte : retirer ce bot du lobby.
signal bot_removed(id: String)
signal start_pressed
signal stop_pressed
signal to_lobby_pressed
## Accueil : rejoindre un serveur (mot de passe "" si aucun), en créer un ; quitter / fermer le serveur.
signal leave_pressed
## Hôte : réglages du serveur modifiés ({name, max, password}).
signal server_cfg_changed(cfg: Dictionary)
## Manette dans le panneau du lobby (true) ou sur le terrain (false).
signal pad_nav_changed(on: bool)

var splash: Control  # écran de chargement (libéré une fois effacé)
var menu := MainMenu.new()  # menu principal (écran titre, parties, personnage, options)
var root := Control.new()
var hud := Control.new()
var lobby := PanelContainer.new()
var overlay := ColorRect.new()
var wait: PanelContainer
var stop: Button
var leave: Button
var server_btn: Button
var corner: Label

var _lobby_box := VBoxContainer.new()
var _lobby_m: Dictionary = {}  # dernier état du lobby reçu
var _lobby_me := ""
var _tab := ""  # onglet ouvert de la fenêtre des réglages de la partie ("" : fermée)
var _overlay_card := PanelContainer.new()
var _banner := VBoxContainer.new()
var _b_title: Label
var _b_sub: Label
var _b_count: Label
var _toast: Label
var _toast_tween: Tween
var _waiting_focus := false
var pad_nav := false  # la manette navigue dans le panneau du lobby (au lieu de faire courir le personnage)
var _server_form: Dictionary = {}  # réglages du serveur connus de l'hôte (vide = on n'héberge pas)


func _ready() -> void:
	UI.init_theme()
	root.theme = UI.theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)

	# bandeau de début de manche
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_b_title = UI.outlined("", 54, Color.WHITE, 12)
	_b_title.add_theme_color_override("font_shadow_color", UI.ACCENT)
	_b_title.add_theme_constant_override("shadow_offset_x", 4)
	_b_title.add_theme_constant_override("shadow_offset_y", 4)
	_b_sub = UI.outlined("", 22, Color.WHITE, 8)
	_b_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_b_count = UI.outlined("", 120, UI.YELLOW, 20)
	for l: Label in [_b_title, _b_sub, _b_count]:
		_banner.add_child(l)
	_banner.visible = false
	root.add_child(_banner)

	_toast = UI.outlined("", 34, Color.WHITE, 10)
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 74
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	corner = UI.outlined("", 12, Color.WHITE, 4)
	corner.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	corner.offset_left = 12
	corner.offset_top = -28
	corner.offset_bottom = -10
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(corner)

	# panneau du lobby, en haut à gauche : sa hauteur suit le contenu (fixe pour un nombre de places donné)
	lobby.offset_left = 18
	lobby.offset_top = 18
	lobby.offset_right = 18 + 400
	_lobby_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_box.add_theme_constant_override("separation", 8)
	lobby.add_child(_lobby_box)
	lobby.visible = false
	root.add_child(lobby)

	wait = UI.card()
	wait.add_child(UI.label("Partie en cours… tu rejoins à la prochaine manche !", 18))
	wait.set_anchors_preset(Control.PRESET_CENTER)
	wait.grow_horizontal = Control.GROW_DIRECTION_BOTH
	wait.grow_vertical = Control.GROW_DIRECTION_BOTH
	wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wait.visible = false
	root.add_child(wait)

	# boutons en bas à droite pendant une partie : réglages du serveur et arrêt (hôte), quitter (tous)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	actions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	actions.grow_vertical = Control.GROW_DIRECTION_BEGIN
	actions.offset_right = -12
	actions.offset_bottom = -14
	server_btn = UI.button("Réglages du serveur", "small", func() -> void: show_server_settings())
	stop = UI.button("Arrêter la partie", "small", func() -> void: stop_pressed.emit())
	leave = UI.button("Quitter", "small", func() -> void: leave_pressed.emit())
	for b: Button in [server_btn, stop, leave]:
		b.visible = false
		actions.add_child(b)
	root.add_child(actions)

	root.add_child(menu)

	# voile sombre + carte centrale (scores, connexion)
	overlay.color = Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.35)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_card.custom_minimum_size = Vector2(440, 0)
	center.add_child(_overlay_card)
	overlay.add_child(center)
	overlay.visible = false
	root.add_child(overlay)

	# écran de chargement, par-dessus tout le reste
	splash = preload("res://ui/splash.gd").new()
	root.add_child(splash)


## Efface l'écran de chargement (dès qu'on a une réponse du serveur ou qu'il faut une saisie).
func dismiss_splash() -> void:
	if is_instance_valid(splash):
		splash.dismiss()


# ---------- HUD des mini-jeux ----------

func hud_clear() -> void:
	for c in hud.get_children():
		hud.remove_child(c)
		c.queue_free()


## Carte du HUD : "top" (centrée en haut), "side" (en haut à droite) ou "bottom" (centrée en bas).
func hud_card(where: String, interactive := false) -> PanelContainer:
	var c := UI.card()
	if not interactive:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s: StyleBoxFlat = UI.theme.get_stylebox("panel", "PanelContainer").duplicate()
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	c.add_theme_stylebox_override("panel", s)
	match where:
		"top":
			c.set_anchors_preset(Control.PRESET_CENTER_TOP)
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
			c.offset_top = 12
		"side":
			c.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			c.offset_top = 12
			c.offset_right = -12
			c.custom_minimum_size.x = 190
		_:
			c.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
			c.offset_bottom = -22
	hud.add_child(c)
	return c


# ---------- bandeau, toasts ----------

func show_banner(title: String, sub: String) -> void:
	_b_title.text = title
	_b_sub.text = sub
	_b_count.text = ""
	_banner.visible = true
	await get_tree().process_frame
	# le titre tombe en rebondissant, le sous-titre glisse en fondu
	_pop(_b_title, 1.8, 0.0, 0.5)
	_b_sub.modulate.a = 0.0
	_b_sub.create_tween().tween_property(_b_sub, "modulate:a", 1.0, 0.4).set_delay(0.25)


## Grossit (ou rétrécit) un texte depuis `from` jusqu'à sa taille, avec un rebond. Le pivot est le centre du texte.
func _pop(l: Control, from: float, delay := 0.0, dur := 0.35) -> void:
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2.ONE * from
	l.modulate.a = 0.0
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, dur).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, dur * 0.4).set_delay(delay)


func hide_banner() -> void:
	_banner.visible = false


func banner_visible() -> bool:
	return _banner.visible


const COUNT_COLORS := {"3": Color("#ff4d6d"), "2": Color("#ff9f1c"), "1": Color("#ffd60a")}


## Chiffre du compte à rebours : arrive en grand et rebondit, une couleur par chiffre ; « GO ! » éclate puis s'envole.
func set_count(text: String) -> void:
	_b_count.text = text
	if text == "":
		return
	await get_tree().process_frame  # taille du nouveau texte connue
	if text == "GO !":
		_b_count.rotation = 0.0
		_b_count.add_theme_color_override("font_color", Color("#70e000"))
		_pop(_b_count, 0.3, 0.0, 0.3)
		var tw := _b_count.create_tween()
		tw.tween_interval(0.35)
		tw.tween_property(_b_count, "scale", Vector2.ONE * 1.8, 0.4).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_b_count, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
	else:
		_b_count.add_theme_color_override("font_color", COUNT_COLORS.get(text, UI.YELLOW))
		_pop(_b_count, 2.4, 0.0, 0.4)
		# léger balancement pendant la seconde
		_b_count.rotation = 0.0
		_b_count.create_tween().tween_property(_b_count, "rotation", 0.06 * (1.0 if int(text) % 2 else -1.0), 0.5).set_trans(Tween.TRANS_SINE)


func toast(text: String, seconds := 1.8) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.25)


# ---------- voile central ----------

func _fill_overlay(children: Array, width := 440.0) -> void:
	_tab = ""  # la carte centrale ne montre plus les réglages de la partie
	_overlay_card.custom_minimum_size.x = width
	for c in _overlay_card.get_children():
		_overlay_card.remove_child(c)
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	for c: Control in children:
		v.add_child(c)
	_overlay_card.add_child(v)
	overlay.visible = true


func hide_overlay() -> void:
	_tab = ""
	overlay.visible = false


func show_message(title: String, text: String, button := "", action: Callable = Callable()) -> void:
	dismiss_splash()
	var t := UI.label(text, 15)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var kids: Array = [UI.h1(title), t]
	if button != "":
		kids.append(UI.button(button, "big", action))
	_fill_overlay(kids)


## Message avec deux choix (confirmation).
func show_confirm(title: String, text: String, yes: String, on_yes: Callable, no: String, on_no: Callable) -> void:
	dismiss_splash()
	var t := UI.label(text, 15)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UI.button(yes, "big", on_yes))
	row.add_child(UI.button(no, "", on_no))
	_fill_overlay([UI.h1(title), t, row])


# ---------- réglages du serveur (création depuis le menu, hôte en partie) ----------

## Champs des réglages du serveur ; on_change reçoit {name, max, password} à chaque validation.
static func server_fields(cfg: Dictionary, on_change: Callable) -> Array:
	var cur := [cfg.duplicate()]  # boîte : les fonctions anonymes capturent par valeur
	var name_edit := LineEdit.new()
	name_edit.text = cfg["name"]
	name_edit.max_length = 32
	name_edit.custom_minimum_size.x = 190
	var pw := LineEdit.new()
	pw.text = cfg["password"]
	pw.max_length = 32
	pw.secret = true
	pw.placeholder_text = "aucun"
	pw.custom_minimum_size.x = 150
	var commit := func() -> void:
		var next := {"name": name_edit.text.strip_edges(), "max": cur[0]["max"], "password": pw.text}
		if next != cur[0]:
			cur[0] = next
			on_change.call(next.duplicate())
	for e: LineEdit in [name_edit, pw]:
		e.text_submitted.connect(func(_t: String) -> void: e.release_focus())
		e.focus_exited.connect(commit)
	var mx := _num(cfg["max"], 2, Protocol.MAX_PLAYERS, 1, true, func(v: float) -> void:
		cur[0]["max"] = int(v)
		on_change.call(cur[0].duplicate()))
	var show_pw := CheckBox.new()
	show_pw.text = "voir"
	show_pw.focus_mode = Control.FOCUS_NONE
	show_pw.toggled.connect(func(on: bool) -> void: pw.secret = not on)
	return [UI.row("Nom du serveur", [name_edit]), UI.row("Joueurs max", [mx]), UI.row("Mot de passe", [pw, show_pw])]


## Réglages du serveur pendant une partie (hôte), dans le voile central.
func show_server_settings() -> void:
	if _server_form.is_empty():
		return
	var kids: Array = [UI.h1("Réglages du serveur")]
	kids.append_array(server_fields(_server_form, _on_server_form))
	var hint := UI.small("Ils s'appliquent tout de suite, sans interrompre la manche. Les réglages de la partie se changent au lobby.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kids.append(hint)
	kids.append(UI.button("Fermer", "big", func() -> void:
		var f := get_viewport().gui_get_focus_owner()
		if f:
			f.release_focus()
		hide_overlay.call_deferred()))
	_fill_overlay(kids)


func _on_server_form(next: Dictionary) -> void:
	_server_form = next
	server_cfg_changed.emit(next)


## Réglages du serveur connus de l'hôte (le mot de passe ne circule pas : il vient du PC de l'hôte). {} = pas hôte.
func set_server_form(cfg: Dictionary) -> void:
	_server_form = cfg.duplicate()


static func _rank_label(i: int) -> Label:
	var colors := [Color("#e0a800"), Color("#8d99ae"), Color("#c9763a")]
	var l := UI.label("%d." % (i + 1), 18, colors[i] if i < 3 else UI.INK)
	l.custom_minimum_size.x = 34
	return l


static func _table_row(cells: Array, me: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sbox(Color("#fff3b0") if me else Color(0, 0, 0, 0), 8, 8, 3))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	for c: Control in cells:
		h.add_child(c)
	p.add_child(h)
	return p


## Totaux triés par score décroissant ; à égalité, l'ordre du serveur est conservé.
static func sorted_totals(totals: Dictionary) -> Array:
	var rows := []
	var i := 0
	for id: String in totals:
		rows.append([id, float(totals[id]), i])
		i += 1
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1] if a[1] != b[1] else a[2] < b[2])
	return rows


func show_scores(m: Dictionary, players: Array, my_id: String, game_name: String) -> void:
	var by_id := {}
	for p: Dictionary in players:
		by_id[p["id"]] = p
	var round_res := {}
	for r: Dictionary in m["results"]:
		round_res[r["id"]] = r
	var kids: Array = [UI.h1("Manche %d/%d" % [int(m["index"]) + 1, int(m["total"])]), UI.h2(game_name)]
	var rows := sorted_totals(m["totals"])
	for i in rows.size():
		var id: String = rows[i][0]
		if not by_id.has(id):
			continue
		var p: Dictionary = by_id[id]
		var r: Variant = round_res.get(id)
		var name_l := UI.label(p["name"], 15)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		name_l.custom_minimum_size.x = 150
		var res_l := UI.label(r["label"] if r else "—", 14)
		res_l.custom_minimum_size.x = 150
		var pts := UI.label("+%d" % int(r["points"]) if r else "", 15, UI.ACCENT2)
		pts.custom_minimum_size.x = 40
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var tot := UI.label(str(int(rows[i][1])), 17)
		tot.custom_minimum_size.x = 40
		tot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kids.append(_table_row([_rank_label(i), UI.dot(Gfx.col(int(p["color"]))), name_l, res_l, pts, tot], id == my_id))
	kids.append(UI.small("Direction le podium…" if m["last"] else "Prochaine manche dans quelques secondes…"))
	_fill_overlay(kids)


## Classement final ; renvoie les identifiants dans l'ordre du podium.
func show_podium(totals: Dictionary, players: Array, my_id: String, host: bool) -> void:
	var by_id := {}
	for p: Dictionary in players:
		by_id[p["id"]] = p
	var rows := sorted_totals(totals).filter(func(r: Array) -> bool: return by_id.has(r[0]))
	hud_clear()
	var winner: String = by_id[rows[0][0]]["name"] if not rows.is_empty() else ""
	var top := hud_card("top")
	top.add_child(UI.label("%s remporte la partie !" % winner, 20))
	var side := hud_card("side", true)
	var v := VBoxContainer.new()
	v.add_child(UI.h2("Classement final"))
	for i in rows.size():
		var p: Dictionary = by_id[rows[i][0]]
		var name_l := UI.label(p["name"], 14)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.custom_minimum_size.x = 110
		v.add_child(_table_row([_rank_label(i), name_l, UI.label("%d pts" % int(rows[i][1]), 14)], rows[i][0] == my_id))
	if host:
		v.add_child(UI.button("Retour au lobby", "big", func() -> void: to_lobby_pressed.emit()))
	side.add_child(v)


# ---------- lobby ----------

func _focused_field() -> Control:
	var f := get_viewport().gui_get_focus_owner()
	if f is LineEdit and (lobby.is_ancestor_of(f) or overlay.is_ancestor_of(f)):
		return f
	return null


func render_lobby(m: Dictionary, my_id: String) -> void:
	_lobby_m = m
	_lobby_me = my_id
	# ne pas reconstruire pendant que l'utilisateur tape dans un champ (nom du serveur, mot de passe)
	var f := _focused_field()
	if f:
		if not _waiting_focus:
			_waiting_focus = true
			f.focus_exited.connect(_flush_pending, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
		return
	_build_lobby()
	if _tab != "":
		_build_settings()


func _flush_pending() -> void:
	_waiting_focus = false
	if not _lobby_m.is_empty():
		render_lobby(_lobby_m, _lobby_me)


static func _num(value: float, mn: float, mx: float, step: float, host: bool, on_set: Callable) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = mn
	sb.max_value = mx
	sb.step = step
	sb.value = value
	sb.editable = host
	sb.custom_minimum_size.x = 96
	sb.get_line_edit().text_submitted.connect(func(_t: String) -> void: sb.get_line_edit().release_focus())
	sb.value_changed.connect(on_set)
	return sb


func _check(text: String, on: bool, host: bool, on_toggle: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = on
	cb.disabled = not host
	cb.focus_mode = Control.FOCUS_NONE
	cb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cb.toggled.connect(on_toggle)
	return cb


## Valeur réglable « − valeur + » (les boutons disparaissent en lecture seule).
static func _stepper(value: float, mn: float, mx: float, step: float, unit: String, host: bool, on_set: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var cur := [value]
	var fmt := func(v: float) -> String:
		var t := str(int(round(v))) if is_equal_approx(step, round(step)) else "%.1f" % v
		return t + (" " + unit if unit != "" else "")
	var l := UI.label(fmt.call(value), 17)
	l.custom_minimum_size.x = 70
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var change := func(dir: float) -> void:
		var v := clampf(cur[0] + dir * step, mn, mx)
		if not is_equal_approx(v, cur[0]):
			cur[0] = v
			l.text = fmt.call(v)
			on_set.call(v)
	var minus := UI.button("−", "small", func() -> void: change.call(-1.0))
	var plus := UI.button("+", "small", func() -> void: change.call(1.0))
	for b: Button in [minus, plus]:
		b.custom_minimum_size.x = 34
		b.visible = host
	h.add_child(minus)
	h.add_child(l)
	h.add_child(plus)
	return h


## Interrupteur Oui / Non.
static func _toggle(on: bool, host: bool, on_set: Callable) -> Button:
	var b := UI.button("Oui" if on else "Non", "small", func() -> void: on_set.call(not on))
	b.custom_minimum_size.x = 74
	b.disabled = not host
	var bg := Color("#70e000") if on else Color("#e6e3ee")
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
		s.bg_color = bg.lightened(0.15) if st == "hover" else bg
		b.add_theme_stylebox_override(st, s)
	for c in ["font_color", "font_disabled_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, UI.INK if on else UI.MUTED)
	return b


## Petite étiquette arrondie (jeux du résumé, « privée »).
static func _pill(text: String, bg: Color, fg := UI.INK) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sbox(bg, 10, 10, 3))
	p.add_child(UI.label(text, 13, fg))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Case de la grille des joueurs (même taille pour un joueur, un bot ou une place libre).
static func _slot(bg: Color, border := Color(0, 0, 0, 0)) -> PanelContainer:
	var c := PanelContainer.new()
	var s := UI.sbox(bg, 12, 10, 6)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(2)
	c.add_theme_stylebox_override("panel", s)
	c.custom_minimum_size = Vector2(0, 42)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _player_card(p: Dictionary, host_id: String, my_id: String, host: bool) -> Control:
	var col := Gfx.col(int(p["color"]))
	var mine: bool = p["id"] == my_id
	var c := _slot(Color.WHITE.lerp(col, 0.22), UI.ACCENT2 if mine else Color(0, 0, 0, 0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 7)
	h.add_child(UI.dot(col, 16))
	var n := UI.label(str(p["name"]), 15)
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.custom_minimum_size.x = 40
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(n)
	var tag := "hôte" if p["id"] == host_id else ("bot" if p["isBot"] else ("toi" if mine else ""))
	if tag != "":
		var t := UI.label(tag, 12, UI.ACCENT if tag == "hôte" else UI.MUTED)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
	if host and p["isBot"]:
		var x := UI.button("×", "small", func() -> void: bot_removed.emit(p["id"]))
		x.tooltip_text = "Retirer ce bot"
		for st in ["normal", "hover", "pressed"]:
			var xs := UI.sbox(Color(1, 1, 1, 0.9 if st == "hover" else 0.55), 9, 7, 0)
			x.add_theme_stylebox_override(st, xs)
		x.add_theme_color_override("font_color", UI.MUTED)
		x.add_theme_color_override("font_hover_color", UI.ACCENT)
		x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(x)
	c.add_child(h)
	return c


func _build_lobby() -> void:
	var m := _lobby_m
	var my_id := _lobby_me
	var me: Variant = null
	for p: Dictionary in m["players"]:
		if p["id"] == my_id:
			me = p
	if me == null:
		return
	var host: bool = m["hostId"] == my_id
	var s: Dictionary = m["settings"]
	var srv: Dictionary = m.get("server", {})
	var keep_focus := _focus_path(_lobby_box)
	for c in _lobby_box.get_children():
		_lobby_box.remove_child(c)
		c.queue_free()
	var box := _lobby_box

	# en-tête : nom de la partie, places, adresse pour l'hôte
	var title := UI.h1(str(srv.get("name", "Dotabata!")))
	title.add_theme_font_size_override("font_size", 28)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)
	var players: Array = m["players"]
	var slots := maxi(int(srv.get("max", Protocol.MAX_PLAYERS)), players.size())
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var count := UI.h2("Joueurs  %d / %d" % [players.size(), slots])
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(count)
	if srv.get("locked", false):
		head.add_child(_pill("Privée", Color("#ffe3ea"), UI.ACCENT))
	box.add_child(head)

	# grille des places : une case par place, la hauteur ne change pas quand on ajoute des bots
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var bots := 0
	for p: Dictionary in players:
		if p["isBot"]:
			bots += 1
		grid.add_child(_player_card(p, m["hostId"], my_id, host))
	for i in range(players.size(), slots):
		if host and i == players.size():
			var add := UI.button("+  Ajouter un bot", "", func() -> void: bots_changed.emit(bots + 1))
			add.custom_minimum_size = Vector2(0, 42)
			add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			add.add_theme_font_size_override("font_size", 14)
			grid.add_child(add)
		else:
			var free := _slot(Color(1, 1, 1, 0.35), Color("#ddd6ee"))
			var l := UI.label("Place libre", 13, Color("#b3abc9"))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			free.add_child(l)
			grid.add_child(free)
	box.add_child(grid)

	# résumé de la partie
	box.add_child(_gap(4))
	box.add_child(UI.h2("La partie"))
	var rounds := int(s["rounds"])
	var order_txt: String = {"alternate": "jeux en alternance", "random": "jeux au hasard", "list": "ordre choisi"}.get(s["order"], "")
	box.add_child(UI.label("%d manche%s · %s" % [rounds, "s" if rounds > 1 else "", order_txt], 16))
	var names := {}
	for g: Dictionary in m["metas"]:
		# nom du jeu, suivi de ses réglages à choix (ex. : « Parcours délirant · Meilleur temps »)
		var label: String = g["name"]
		var vals: Dictionary = s["game"].get(g["id"], {})
		for key: String in g["settings"]:
			var def: Dictionary = g["settings"][key]
			if def["type"] == "choice":
				var k: int = maxi(0, def["options"].find(vals.get(key, def["default"])))
				label += " · " + str(def.get("labels", def["options"])[k])
		names[g["id"]] = label
	var pills := UI.flow()
	if s["order"] == "list":
		var list: Array = s["list"]
		for i in mini(rounds, list.size()):
			pills.add_child(_pill("%d. %s" % [i + 1, names.get(list[i], list[i])], Color("#e7ecff"), UI.ACCENT2))
	else:
		for id: String in s["games"]:
			pills.add_child(_pill(names.get(id, id), Color("#e7ecff"), UI.ACCENT2))
	box.add_child(pills)
	var see := UI.button("Réglages de la partie…" if host else "Voir les réglages", "", func() -> void: open_game_settings())
	see.set_meta("settings_btn", true)
	if not host:
		see.set_meta("pad_first", true)
	box.add_child(see)

	# lancement
	box.add_child(_gap(6))
	if host:
		var go := UI.button("Lancer la partie", "big", func() -> void: start_pressed.emit())
		go.set_meta("pad_first", true)
		box.add_child(go)
	else:
		var w := PanelContainer.new()
		w.add_theme_stylebox_override("panel", UI.sbox(Color("#fff6c2"), 12, 14, 10))
		var wl := UI.label("En attente du lancement par l'hôte…", 15)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		w.add_child(wl)
		box.add_child(w)
	var leave_b := UI.button("Fermer le serveur" if not _server_form.is_empty() else "Quitter la partie", "small", func() -> void: leave_pressed.emit())
	leave_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(leave_b)
	if pad_nav:
		_pad_focusables(_lobby_box, true)
		_restore_focus(_lobby_box, keep_focus)


static func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ---------- fenêtre des réglages de la partie ----------

## Ouvre la fenêtre des réglages (hôte : modifiables ; autres joueurs : lecture seule).
func open_game_settings(tab := "partie") -> void:
	if _lobby_m.is_empty():
		return
	_tab = tab
	_build_settings()


func close_game_settings() -> void:
	if _tab == "":
		return
	var f := get_viewport().gui_get_focus_owner()
	if f and overlay.is_ancestor_of(f):
		f.release_focus()
	hide_overlay()
	if pad_nav:
		var b := _find_meta(_lobby_box, "settings_btn")
		if b:
			b.grab_focus.call_deferred()


func _tabs() -> Array:
	var tabs: Array = [["partie", "Partie"]]
	for g: Dictionary in _lobby_m["metas"]:
		tabs.append([g["id"], g["name"]])
	if _lobby_m["hostId"] == _lobby_me and not _server_form.is_empty():
		tabs.append(["serveur", "Serveur"])
	return tabs


func _switch_tab(dir: int) -> void:
	var tabs := _tabs()
	var i := 0
	for k in tabs.size():
		if tabs[k][0] == _tab:
			i = k
	_tab = tabs[(i + dir + tabs.size()) % tabs.size()][0]
	_build_settings()
	if pad_nav:
		var b := _find_meta(_overlay_card, "tab_" + _tab)
		if b:
			b.grab_focus.call_deferred()


func _build_settings() -> void:
	var m := _lobby_m
	var host: bool = m["hostId"] == _lobby_me
	var s: Dictionary = m["settings"].duplicate(true)
	var push := func() -> void: settings_changed.emit(s)
	var keep_focus := _focus_path(_overlay_card)
	var tabs := _tabs()
	if not tabs.any(func(t: Array) -> bool: return t[0] == _tab):
		_tab = "partie"
	var tab := _tab

	var kids: Array = [UI.h1("Réglages de la partie" if host else "Réglages choisis par l'hôte")]
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	for t: Array in tabs:
		var id: String = t[0]
		var b := UI.button(t[1], "", func() -> void:
			_tab = id
			_build_settings())
		b.set_meta("tab_" + id, true)
		var on := id == tab
		for st in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
			sb.bg_color = UI.ACCENT2 if on else (Color("#e4ddfa") if st == "hover" else Color("#efeaff"))
			sb.shadow_size = 0
			sb.content_margin_left = 16
			sb.content_margin_right = 16
			sb.content_margin_top = 7
			sb.content_margin_bottom = 7
			b.add_theme_stylebox_override(st, sb)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, Color.WHITE if on else UI.INK)
		if on:
			b.set_meta("pad_first", true)
		bar.add_child(b)
	kids.append(bar)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.custom_minimum_size = Vector2(560, 300)
	var metas: Array = m["metas"]
	if tab == "partie":
		_tab_game_rules(body, s, metas, host, push)
	elif tab == "serveur":
		for c: Control in server_fields(_server_form, _on_server_form):
			body.add_child(c)
		var urls: Array = m["urls"]
		var hint := "Les joueurs du réseau local voient cette partie dans leur liste."
		if not urls.is_empty():
			hint += " Sinon, adresse à saisir : %s" % "  ou  ".join(PackedStringArray(urls))
		body.add_child(UI.small(hint))
	else:
		for g: Dictionary in metas:
			if g["id"] == tab:
				_tab_game(body, s, g, host, push)
	kids.append(body)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	var note := "Les changements s'appliquent tout de suite." if host else "Seul l'hôte peut les modifier."
	if pad_nav:
		note += " %s / %s : onglets." % [Pad.label(JOY_BUTTON_LEFT_SHOULDER), Pad.label(JOY_BUTTON_RIGHT_SHOULDER)]
	var nl := UI.small(note)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(nl)
	foot.add_child(UI.button("Terminé", "big", func() -> void: close_game_settings.call_deferred()))
	kids.append(foot)

	_fill_overlay(kids, 620)
	_tab = tab
	if pad_nav:
		_pad_focusables(_overlay_card, true)
		_restore_focus(_overlay_card, keep_focus)


## Ligne « libellé … contrôle » de la fenêtre des réglages.
static func _setting_row(text: String, control: Control) -> HBoxContainer:
	var h := UI.row(text, [control])
	h.get_child(0).add_theme_font_size_override("font_size", 16)
	h.get_child(0).custom_minimum_size.x = 260
	return h


func _tab_game_rules(body: VBoxContainer, s: Dictionary, metas: Array, host: bool, push: Callable) -> void:
	body.add_child(_setting_row("Nombre de manches", _stepper(s["rounds"], 1, 15, 1, "", host, func(v: float) -> void:
		s["rounds"] = int(v)
		push.call())))

	var order := HBoxContainer.new()
	order.add_theme_constant_override("separation", 6)
	for o: Array in [["alternate", "Alterné"], ["random", "Aléatoire"], ["list", "Choisi"]]:
		var key: String = o[0]
		var b := UI.button(o[1], "small", func() -> void:
			if host:
				s["order"] = key
				push.call())
		b.disabled = not host and s["order"] != key
		if s["order"] == key:
			UI.mark_selected(b)
		order.add_child(b)
	body.add_child(_setting_row("Ordre des jeux", order))

	if s["order"] == "list":
		# une case par manche : un clic passe au jeu suivant
		body.add_child(UI.label("Jeu de chaque manche", 16))
		var list: Array = s["list"]
		var chosen := UI.flow()
		for i in int(s["rounds"]):
			var cur := 0
			for k in metas.size():
				if i < list.size() and list[i] == metas[k]["id"]:
					cur = k
			var b := UI.button("%d. %s" % [i + 1, metas[cur]["name"]], "small", func() -> void:
				while list.size() <= i:
					list.append(metas[0]["id"])
				list[i] = metas[(cur + 1) % metas.size()]["id"]
				push.call())
			b.disabled = not host
			chosen.add_child(b)
		body.add_child(chosen)
		body.add_child(UI.small("Clique sur une manche pour changer de jeu."))
	else:
		body.add_child(UI.label("Jeux inclus", 16))
		var games: Array = s["games"]
		var inc := UI.flow()
		for g: Dictionary in metas:
			var cb := _check(g["name"], games.has(g["id"]), host, func(on: bool) -> void:
				var next := []
				for x: Dictionary in metas:
					if (on if x["id"] == g["id"] else games.has(x["id"])):
						next.append(x["id"])
				s["games"] = next
				push.call())
			cb.add_theme_font_size_override("font_size", 16)
			inc.add_child(cb)
		body.add_child(inc)


## Réglages propres à un jeu, générés depuis son schéma (server/metas.gd).
func _tab_game(body: VBoxContainer, s: Dictionary, g: Dictionary, host: bool, push: Callable) -> void:
	var desc := UI.small(str(g.get("description", "")))
	desc.add_theme_font_size_override("font_size", 13)
	body.add_child(desc)
	var included: bool = s["games"].has(g["id"]) or (s["order"] == "list" and s["list"].has(g["id"]))
	if not included:
		body.add_child(UI.label("Ce jeu n'est pas dans la partie (onglet Partie).", 14, UI.ACCENT))
	var game_vals: Dictionary = s["game"]
	if not game_vals.has(g["id"]):
		game_vals[g["id"]] = {}
	var vals: Dictionary = game_vals[g["id"]]
	var defs: Dictionary = g["settings"]
	for key: String in defs:
		var def: Dictionary = defs[key]
		var text: String = def["label"]
		if def["type"] == "number":
			body.add_child(_setting_row(text, _stepper(vals.get(key, def["default"]), def["min"], def["max"], def.get("step", 1), def.get("unit", ""), host, func(v: float) -> void:
				vals[key] = v
				push.call())))
		elif def["type"] == "choice":
			var seg := HBoxContainer.new()
			seg.add_theme_constant_override("separation", 6)
			var cur: String = vals.get(key, def["default"])
			var labels: Array = def.get("labels", def["options"])
			for k in def["options"].size():
				var opt: String = def["options"][k]
				var b := UI.button(labels[k], "small", func() -> void:
					if host:
						vals[key] = opt
						push.call())
				b.disabled = not host and opt != cur
				if opt == cur:
					UI.mark_selected(b)
				seg.add_child(b)
			body.add_child(_setting_row(text, seg))
		elif def["type"] == "bool":
			body.add_child(_setting_row(text, _toggle(bool(vals.get(key, def["default"])), host, func(on: bool) -> void:
				vals[key] = on
				push.call())))
		else:
			var options: Array = def["options"]
			var chosen: Array = vals.get(key, [])
			body.add_child(UI.label(text, 16))
			var chips := UI.flow()
			for opt: String in options:
				chips.add_child(_check(opt, chosen.is_empty() or chosen.has(opt), host, func(on: bool) -> void:
					var cur: Array = chosen if not chosen.is_empty() else options
					var next := []
					for o: String in options:
						if (on if o == opt else cur.has(o)):
							next.append(o)
					vals[key] = [] if next.size() == options.size() else next  # tout coché = pas de restriction
					push.call()))
			body.add_child(chips)


# ---------- lobby à la manette ----------

## La manette passe dans le panneau du lobby : tous les réglages deviennent sélectionnables à la croix ou au stick.
func enter_pad_nav() -> void:
	if pad_nav or not lobby.visible:
		return
	pad_nav = true
	pad_nav_changed.emit(true)  # Main reconstruit le panneau, qui devient alors navigable (fin de _build_lobby)


## Retour sur le terrain : plus aucun contrôle du panneau ne garde le focus (A, Espace… refont sauter).
func exit_pad_nav() -> void:
	if not pad_nav:
		return
	pad_nav = false
	close_game_settings()
	var f := get_viewport().gui_get_focus_owner()
	if f and lobby.is_ancestor_of(f):
		f.release_focus()
	_pad_focusables(_lobby_box, false)
	pad_nav_changed.emit(false)


## Rend les contrôles navigables (on) ou les remet comme pour la souris (off). Les champs de texte
## restent hors navigation (pas de clavier sur une manette) ; les nombres se règlent à gauche / droite.
func _pad_focusables(c: Node, on: bool) -> void:
	for k in c.get_children():
		if k is SpinBox:
			k.get_line_edit().focus_mode = Control.FOCUS_NONE if on else Control.FOCUS_ALL
			k.focus_mode = Control.FOCUS_ALL if on and k.editable else Control.FOCUS_NONE
			if on and not k.has_meta("pad_hooked"):
				k.set_meta("pad_hooked", true)
				var le: LineEdit = k.get_line_edit()
				k.focus_entered.connect(func() -> void: le.add_theme_stylebox_override("normal", UI.theme.get_stylebox("focus", "LineEdit")))
				k.focus_exited.connect(func() -> void: le.remove_theme_stylebox_override("normal"))
			continue
		if k is LineEdit:
			k.focus_mode = Control.FOCUS_NONE if on else Control.FOCUS_ALL
		elif k is BaseButton:
			k.focus_mode = Control.FOCUS_ALL if on and not k.disabled and k.visible else Control.FOCUS_NONE
		_pad_focusables(k, on)


## Chemin (indices des enfants) du contrôle qui a le focus sous root, pour le retrouver après reconstruction.
func _focus_path(root_node: Control) -> Array:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f == null or not root_node.is_ancestor_of(f):
		return []
	var path: Array = []
	while f != root_node:
		path.push_front(f.get_index())
		f = f.get_parent()
	return path


func _restore_focus(root_node: Control, path: Array) -> void:
	var n: Node = root_node
	for i: int in path:
		if i >= n.get_child_count():
			n = null
			break
		n = n.get_child(i)
	var target: Control = n if n is Control and n != root_node and n.focus_mode == Control.FOCUS_ALL else _find_pad_first(root_node)
	if target:
		(func() -> void:
			if is_instance_valid(target) and target.is_inside_tree():
				target.grab_focus()).call_deferred()


static func _find_pad_first(c: Node) -> Control:
	for k in c.get_children():
		if k is Control and k.has_meta("pad_first") and k.focus_mode == Control.FOCUS_ALL:
			return k
		var sub := _find_pad_first(k)
		if sub:
			return sub
	return null


static func _find_meta(c: Node, key: String) -> Control:
	for k in c.get_children():
		if k is Control and k.has_meta(key):
			return k
		var sub := _find_meta(k, key)
		if sub:
			return sub
	return null


func _input(ev: InputEvent) -> void:
	if _tab != "":
		# fenêtre des réglages ouverte : Échap / B / Start la ferment, LB / RB changent d'onglet
		var start_b: int = Pad.bindings.get("panneau", JOY_BUTTON_START)
		if ev.is_action_pressed("ui_cancel") or (ev is InputEventJoypadButton and ev.pressed and ev.button_index == start_b):
			get_viewport().set_input_as_handled()
			close_game_settings()
			return
		if ev is InputEventJoypadButton and ev.pressed and (ev.button_index == JOY_BUTTON_LEFT_SHOULDER or ev.button_index == JOY_BUTTON_RIGHT_SHOULDER):
			get_viewport().set_input_as_handled()
			_switch_tab(-1 if ev.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
			return
	if not pad_nav:
		return
	var f := get_viewport().gui_get_focus_owner()
	var area: Control = _overlay_card if _tab != "" else _lobby_box
	var start: int = Pad.bindings.get("panneau", JOY_BUTTON_START)
	if (ev is InputEventJoypadButton and ev.pressed and ev.button_index == start) or ev.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		exit_pad_nav()
		return
	if f is SpinBox and (ev.is_action_pressed("ui_left") or ev.is_action_pressed("ui_right")):
		get_viewport().set_input_as_handled()
		f.value += f.step * (1.0 if ev.is_action_pressed("ui_right") else -1.0)
		return
	if (f == null or not area.is_ancestor_of(f)) and (ev.is_action_pressed("ui_up") or ev.is_action_pressed("ui_down") or ev.is_action_pressed("ui_accept")):
		get_viewport().set_input_as_handled()
		_restore_focus(area, [])
