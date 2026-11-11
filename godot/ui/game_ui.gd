class_name GameUI
extends CanvasLayer
## Interface par-dessus le jeu : accueil (liste des serveurs, création), panneau du lobby (formulaire généré depuis les réglages
## déclarés par chaque jeu), bandeau de manche, toasts, scores, podium. Portage de client/src/ui.ts.

signal profile_changed(p: Dictionary)
signal settings_changed(s: Dictionary)
signal bots_changed(n: int)
signal start_pressed
signal stop_pressed
signal to_lobby_pressed
signal quality_toggled
## Accueil : rejoindre un serveur (mot de passe "" si aucun), en créer un ; quitter / fermer le serveur.
signal leave_pressed
## Hôte : réglages du serveur modifiés ({name, max, password}).
signal server_cfg_changed(cfg: Dictionary)

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
var _lobby_scroll := ScrollContainer.new()
var _overlay_card := PanelContainer.new()
var _banner := VBoxContainer.new()
var _b_title: Label
var _b_sub: Label
var _b_count: Label
var _toast: Label
var _toast_tween: Tween
var _pending: Variant = null
var _pending_id := ""
var _waiting_focus := false
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

	# panneau du lobby, à gauche
	lobby.anchor_bottom = 1.0
	lobby.offset_left = 14
	lobby.offset_top = 14
	lobby.offset_bottom = -22
	lobby.offset_right = 14 + 380
	_lobby_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lobby_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_box.add_theme_constant_override("separation", 6)
	_lobby_scroll.add_child(_lobby_box)
	lobby.add_child(_lobby_scroll)
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


func hide_banner() -> void:
	_banner.visible = false


func banner_visible() -> bool:
	return _banner.visible


func set_count(text: String) -> void:
	_b_count.text = text


func toast(text: String, seconds := 1.8) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.25)


# ---------- voile central ----------

func _fill_overlay(children: Array) -> void:
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
	if f is LineEdit and lobby.is_ancestor_of(f):
		return f
	return null


func render_lobby(m: Dictionary, my_id: String) -> void:
	# ne pas reconstruire le panneau pendant que l'utilisateur tape dans un champ
	var f := _focused_field()
	if f:
		_pending = m
		_pending_id = my_id
		if not _waiting_focus:
			_waiting_focus = true
			f.focus_exited.connect(_flush_pending, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
		return
	_build_lobby(m, my_id)


func _flush_pending() -> void:
	_waiting_focus = false
	if _pending != null:
		var m: Dictionary = _pending
		_pending = null
		render_lobby(m, _pending_id)


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


func _build_lobby(m: Dictionary, my_id: String) -> void:
	var me: Variant = null
	for p: Dictionary in m["players"]:
		if p["id"] == my_id:
			me = p
	if me == null:
		return
	var host: bool = m["hostId"] == my_id
	var s: Dictionary = m["settings"].duplicate(true)
	var push := func() -> void: settings_changed.emit(s)
	var scroll := _lobby_scroll.scroll_vertical
	for c in _lobby_box.get_children():
		_lobby_box.remove_child(c)
		c.queue_free()
	var box := _lobby_box
	var my_color := int(me["color"])
	var my_hat: String = me["hat"]
	var my_name: String = me["name"]

	var srv: Dictionary = m.get("server", {})
	box.add_child(UI.h1(str(srv.get("name", "Dotabata!"))))
	var name_edit := LineEdit.new()
	name_edit.text = my_name
	name_edit.max_length = 16
	name_edit.custom_minimum_size.x = 170
	name_edit.text_submitted.connect(func(_t: String) -> void: name_edit.release_focus())
	name_edit.focus_exited.connect(func() -> void:
		if name_edit.text != my_name:
			profile_changed.emit({"name": name_edit.text, "color": my_color, "hat": my_hat}))
	box.add_child(UI.row("Pseudo", [name_edit]))

	var swatches := UI.flow()
	for c: int in Protocol.COLORS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(28, 28)
		b.tooltip_text = "Couleur"
		for st in ["normal", "hover", "pressed"]:
			var sb := UI.sbox(Gfx.col(c), 14, 0, 0)
			sb.border_color = UI.INK if c == my_color else Color.WHITE
			sb.set_border_width_all(3)
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func() -> void: profile_changed.emit({"name": my_name, "color": c, "hat": my_hat}))
		swatches.add_child(b)
	box.add_child(swatches)

	var hats := UI.flow()
	for hat: String in Protocol.HATS:
		var b := UI.button(hat, "small", func() -> void: profile_changed.emit({"name": my_name, "color": Protocol.HAT_COLOR[hat], "hat": hat}))
		b.tooltip_text = "Personnage"
		if hat == my_hat:
			UI.mark_selected(b)
		hats.add_child(b)
	box.add_child(hats)

	var players: Array = m["players"]
	var humans := players.filter(func(p: Dictionary) -> bool: return not p["isBot"]).size()
	box.add_child(UI.h2("Joueurs (%d/%d)" % [humans, int(srv.get("max", Protocol.MAX_PLAYERS))]))
	var bots := 0
	for p: Dictionary in players:
		var tags := ""
		if p["id"] == m["hostId"]:
			tags += "  · hôte"
		if p["isBot"]:
			tags += "  · bot"
			bots += 1
		if p["id"] == my_id:
			tags += "  (toi)"
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.add_child(UI.dot(Gfx.col(int(p["color"]))))
		line.add_child(UI.label(str(p["name"]) + tags, 15))
		box.add_child(line)
	if host:
		box.add_child(UI.row("Bots pour compléter", [
			UI.button("−", "small", func() -> void: bots_changed.emit(bots - 1)),
			UI.label(str(bots), 15),
			UI.button("+", "small", func() -> void: bots_changed.emit(bots + 1))]))

	if host and not _server_form.is_empty():
		box.add_child(UI.h2("Serveur"))
		for c: Control in server_fields(_server_form, _on_server_form):
			box.add_child(c)
	elif srv.get("locked", false):
		box.add_child(UI.small("Serveur protégé par un mot de passe."))

	box.add_child(UI.h2("Réglages de la partie" if host else "Réglages (choisis par l'hôte)"))
	box.add_child(UI.row("Nombre de manches", [_num(s["rounds"], 1, 15, 1, host, func(v: float) -> void:
		s["rounds"] = int(v)
		push.call())]))
	var order := OptionButton.new()
	order.focus_mode = Control.FOCUS_NONE
	var order_keys := ["alternate", "random", "list"]
	for label: String in ["Alterné", "Aléatoire", "Liste choisie"]:
		order.add_item(label)
	order.selected = maxi(0, order_keys.find(s["order"]))
	order.disabled = not host
	order.item_selected.connect(func(i: int) -> void:
		s["order"] = order_keys[i]
		push.call())
	box.add_child(UI.row("Ordre des jeux", [order]))

	var metas: Array = m["metas"]
	var games: Array = s["games"]
	var inc := UI.flow()
	for g: Dictionary in metas:
		inc.add_child(_check(g["name"], games.has(g["id"]), host, func(on: bool) -> void:
			var next := []
			for x: Dictionary in metas:
				if (on if x["id"] == g["id"] else games.has(x["id"])):
					next.append(x["id"])
			s["games"] = next
			push.call()))
	box.add_child(UI.label("Jeux inclus", 14))
	box.add_child(inc)
	if s["order"] == "list":
		var list: Array = s["list"]
		var chosen := UI.flow()
		for i in int(s["rounds"]):
			var sel := OptionButton.new()
			sel.focus_mode = Control.FOCUS_NONE
			sel.disabled = not host
			var current := 0
			for k in metas.size():
				sel.add_item("%d. %s" % [i + 1, metas[k]["name"]])
				if i < list.size() and list[i] == metas[k]["id"]:
					current = k
			sel.selected = current
			sel.item_selected.connect(func(k: int) -> void:
				while list.size() <= i:
					list.append(metas[0]["id"])
				list[i] = metas[k]["id"]
				push.call())
			chosen.add_child(sel)
		box.add_child(chosen)

	# réglages propres à chaque jeu, générés automatiquement depuis leur schéma
	var game_vals: Dictionary = s["game"]
	for g: Dictionary in metas:
		if not games.has(g["id"]) and s["order"] != "list":
			continue
		box.add_child(UI.label(g["name"], 15, UI.ACCENT))
		if not game_vals.has(g["id"]):
			game_vals[g["id"]] = {}
		var vals: Dictionary = game_vals[g["id"]]
		var defs: Dictionary = g["settings"]
		for key: String in defs:
			var def: Dictionary = defs[key]
			var text: String = def["label"]
			if def["type"] == "number":
				if def.get("unit", "") != "":
					text += " (%s)" % def["unit"]
				box.add_child(UI.row(text, [_num(vals.get(key, def["default"]), def["min"], def["max"], def.get("step", 1), host, func(v: float) -> void:
					vals[key] = v
					push.call())]))
			elif def["type"] == "bool":
				box.add_child(UI.row(text, [_check("", bool(vals.get(key, def["default"])), host, func(on: bool) -> void:
					vals[key] = on
					push.call())]))
			else:
				var options: Array = def["options"]
				var chosen: Array = vals.get(key, [])
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
				box.add_child(UI.label(text, 14))
				box.add_child(chips)

	if host:
		box.add_child(UI.button("Lancer la partie", "big", func() -> void: start_pressed.emit()))
	else:
		box.add_child(UI.small("En attente du lancement par l'hôte… Entraîne-toi sur le terrain !"))
	box.add_child(UI.button("Fermer le serveur" if not _server_form.is_empty() else "Quitter le serveur", "small", func() -> void: leave_pressed.emit()))
	var urls: Array = m["urls"]
	if not _server_form.is_empty() and not urls.is_empty():
		var u := UI.small("Les joueurs du réseau local voient ce serveur dans leur liste. Sinon, adresse à saisir : %s" % "  ou  ".join(PackedStringArray(urls)))
		u.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(u)
	box.add_child(UI.small("Z Q S D : bouger · Espace : sauter · Souris : caméra (clic sur le jeu pour la capturer, Échap pour la libérer) · Flèches : caméra au clavier"))
	box.add_child(UI.row("Graphismes : %s" % Config.QUALITY_NAMES[Config.quality], [
		UI.button("Passer en %s" % Config.QUALITY_NAMES[(Config.quality + 1) % 3], "small", func() -> void: quality_toggled.emit())]))
	_lobby_scroll.set_deferred("scroll_vertical", scroll)
