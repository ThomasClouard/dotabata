class_name MainMenu
extends Control
## Menu principal, façon jeu vidéo : écran titre (logo, gros boutons, ton personnage en vitrine dans le décor),
## puis les écrans Jouer (parties du réseau local), Créer une partie, Personnage et Options.
## Pile d'écrans avec transitions ; Échap ou B (manette) pour revenir ; tout se pilote au clavier, à la manette
## ou à la souris. Les décisions (rejoindre, créer, quitter…) remontent par signaux à Main.

signal join_requested(address: String, password: String)
signal create_requested(cfg: Dictionary)
signal profile_changed(p: Dictionary)
signal quality_changed(q: int)
signal shot_changed(name: String)
signal spin(amount: float)
signal quit_requested
signal sound(key: String)

const SCREENS := ["titre", "jouer", "creer", "personnage", "options"]
const HAT_NAMES := {
	"haricot": "Haricot", "casquette": "Casquette", "spaghetti": "Spaghetti", "hélice": "Hélice",
	"bouée": "Bouée", "crochet": "Crochet", "bandeau": "Bandeau", "arche": "Arche",
}

var can_host := true
var scanning := true
var last_address := ""
var _stack: Array[String] = []
var _screen: Control
var _servers: Array = []
var _list: VBoxContainer  # liste des parties (écran Jouer)
var _list_hint: Label
var _count: Label  # « N parties trouvées » (écran titre)
var _modal := ColorRect.new()
var _modal_card := PanelContainer.new()
var _t := 0.0
var _dots: Label  # indicateur de recherche animé


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.color = Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.45)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_card.custom_minimum_size = Vector2(420, 0)
	center.add_child(_modal_card)
	_modal.add_child(center)
	_modal.visible = false
	add_child(_modal)
	visible = false


# ---------- ouverture, navigation ----------

## Affiche le menu (sur l'écran où on l'avait laissé, l'écran titre la première fois), avec une erreur éventuelle.
func open(error := "") -> void:
	visible = true
	if _stack.is_empty():
		_stack.append("titre")
	_show(_stack[-1], 0)
	if error != "":
		show_error(error)


## La prochaine ouverture repart de l'écran titre.
func reset() -> void:
	_stack.clear()


func close() -> void:
	visible = false
	_modal.visible = false


func current() -> String:
	return "" if _stack.is_empty() else _stack[-1]


## Ouvre un écran par-dessus le courant.
func push(name: String) -> void:
	_stack.append(name)
	sound.emit("pickup")
	_show(name, 1)


## Revient à l'écran précédent (sans effet sur l'écran titre).
func back() -> void:
	if _stack.size() <= 1:
		return
	_stack.pop_back()
	sound.emit("remove")
	_show(_stack[-1], -1)


## Ouvre directement un écran (option de lancement --menu=…), l'écran titre restant dessous.
func jump_to(name: String) -> void:
	if name in SCREENS and name != "titre":
		_stack.assign(["titre", name])
		if visible:
			_show(name, 0)


## Remplace l'écran affiché. dir : 1 = on avance (arrive de la droite), -1 = on revient, 0 = sans glissement.
func _show(name: String, dir: int) -> void:
	_modal.visible = false
	var old := _screen
	_screen = _build(name)
	add_child(_screen)
	move_child(_screen, _modal.get_index())  # sous la fenêtre modale
	shot_changed.emit(name)
	if old:
		old.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_ignore(old)
		var tw := old.create_tween().set_parallel(true)
		tw.tween_property(old, "position:x", -70.0 * dir, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(old, "modulate:a", 0.0, 0.2)
		tw.chain().tween_callback(old.queue_free)
	if dir != 0:
		_screen.position.x = 70.0 * dir
		_screen.modulate.a = 0.0
		var tw := _screen.create_tween().set_parallel(true)
		tw.tween_property(_screen, "position:x", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.06)
		tw.tween_property(_screen, "modulate:a", 1.0, 0.24).set_delay(0.06)
	_focus_first.call_deferred()


static func _set_ignore(c: Control) -> void:
	for k in c.get_children():
		if k is Control:
			k.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if k is BaseButton:
				k.disabled = true
			_set_ignore(k)


func _build(name: String) -> Control:
	match name:
		"jouer":
			return _screen_play()
		"creer":
			return _screen_create()
		"personnage":
			return _screen_character()
		"options":
			return _screen_options()
	return _screen_title()


## Donne le focus au premier contrôle de l'écran (ou de la fenêtre modale), pour le clavier et la manette.
func _focus_first() -> void:
	var root: Control = _modal_card if _modal.visible else _screen
	if root == null:
		return
	var f := _first_focusable(root, true)
	if f == null:
		f = _first_focusable(root, false)
	if f:
		f.grab_focus()


## Premier contrôle focalisable (en profondeur) ; marked : seulement ceux marqués « first ».
static func _first_focusable(c: Node, marked: bool) -> Control:
	for k in c.get_children():
		if k is Control and k.visible and not k.is_queued_for_deletion():
			var ok: bool = k.focus_mode == Control.FOCUS_ALL and not (k is BaseButton and k.disabled)
			if ok and (k.has_meta("first") if marked else not k.has_meta("skip_focus")):
				return k
			var sub := _first_focusable(k, marked)
			if sub:
				return sub
	return null


func _unhandled_input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _modal.visible:
			_modal.visible = false
			_focus_first.call_deferred()
		else:
			back()
		return
	# plus rien n'a le focus (clic dans le décor) : la première flèche le redonne
	if get_viewport().gui_get_focus_owner() == null:
		for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_focus_next"]:
			if ev.is_action_pressed(a):
				get_viewport().set_input_as_handled()
				_focus_first()
				return


func _process(dt: float) -> void:
	_t += dt
	if is_instance_valid(_dots):
		_dots.text = "Recherche des parties sur le réseau" + ".".repeat(int(_t * 2.5) % 4)


# ---------- briques communes ----------

## Bouton secondaire « ‹ Retour ».
func _back_button() -> Button:
	var b := UI.button("‹  Retour", "", back)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 17)
	b.set_meta("skip_focus", true)
	_sounds(b)
	return b


## Petit son au focus d'un contrôle.
func _sounds(c: Control) -> Control:
	c.focus_entered.connect(func() -> void: sound.emit("tick"))
	c.mouse_entered.connect(func() -> void:
		if not c.has_focus():
			sound.emit("tick"))
	return c


## Panneau principal d'un sous-écran : grande carte à gauche, titre et bouton Retour.
func _side_panel(title: String, width := 560.0, full_height := false) -> Array:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0 if full_height else 0.0
	panel.offset_left = 40
	panel.offset_top = 32
	panel.offset_bottom = -32 if full_height else 32
	panel.offset_right = 40 + width
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(_back_button())
	var h := UI.h1(title)
	h.add_theme_font_size_override("font_size", 36)
	head.add_child(h)
	v.add_child(head)
	return [root, v]


static func _wrap(text: String, size := 15, color := UI.INK) -> Label:
	var l := UI.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


# ---------- écran titre ----------

func _screen_title() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := VBoxContainer.new()
	top.position = Vector2(48, 28)
	top.add_theme_constant_override("separation", 28)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(Logo.new(0.55, BoxContainer.ALIGNMENT_BEGIN))
	root.add_child(top)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_child(col)
	top.add_child(pad)
	var play := UI.menu_button("Jouer", func() -> void: push("jouer"), true)
	play.set_meta("first", true)
	col.add_child(_sounds(play))
	if can_host:
		col.add_child(_sounds(UI.menu_button("Créer une partie", func() -> void: push("creer"))))
	col.add_child(_sounds(UI.menu_button("Personnage", func() -> void: push("personnage"))))
	col.add_child(_sounds(UI.menu_button("Options", func() -> void: push("options"))))
	if not OS.has_feature("web"):
		col.add_child(_sounds(UI.menu_button("Quitter", func() -> void: quit_requested.emit())))

	# bas de l'écran : qui je suis, parties trouvées
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 22)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 56
	foot.offset_top = -56
	foot.offset_bottom = -24
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(UI.outlined("%s · %s" % [Config.profile["name"], HAT_NAMES.get(Config.profile["hat"], Config.profile["hat"])], 20, Color.WHITE, 7))
	_count = UI.outlined("", 18, UI.YELLOW, 7)
	foot.add_child(_count)
	root.add_child(foot)
	_update_count()
	return root


func _update_count() -> void:
	if not is_instance_valid(_count):
		return
	if not scanning:
		_count.text = ""
	elif _servers.is_empty():
		_count.text = "Aucune partie sur le réseau pour l'instant"
	else:
		_count.text = "%d partie%s sur le réseau" % [_servers.size(), "s" if _servers.size() > 1 else ""]


# ---------- Jouer : parties du réseau local ----------

func _screen_play() -> Control:
	var p := _side_panel("Rejoindre une partie", 600, true)
	var v: VBoxContainer = p[1]
	_dots = UI.label("", 14, UI.MUTED)
	v.add_child(_dots)
	if not scanning:
		_dots.queue_free()
		_dots = null
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	v.add_child(scroll)
	_list_hint = _wrap("", 15, UI.MUTED)
	v.add_child(_list_hint)

	# adresse manuelle (autre sous-réseau, VPN…), dépliée à la demande
	var addr_row := HBoxContainer.new()
	addr_row.add_theme_constant_override("separation", 8)
	var addr := LineEdit.new()
	addr.text = last_address
	addr.placeholder_text = "adresse:port, par exemple 192.168.1.20:%d" % Protocol.PORT
	addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var go := func() -> void:
		if addr.text.strip_edges() != "":
			join_requested.emit(addr.text.strip_edges(), "")
	addr.text_submitted.connect(func(_t: String) -> void: go.call())
	var go_b := UI.button("Rejoindre", "small", go)
	go_b.focus_mode = Control.FOCUS_ALL
	addr_row.add_child(addr)
	addr_row.add_child(go_b)
	addr_row.visible = not scanning
	var toggle := UI.button("Rejoindre par adresse…", "", func() -> void: pass)
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.visible = scanning
	toggle.set_meta("skip_focus", true)
	toggle.pressed.connect(func() -> void:
		addr_row.visible = true
		toggle.visible = false
		addr.grab_focus())
	_sounds(toggle)
	v.add_child(toggle)
	v.add_child(addr_row)
	_fill_list()
	return p[0]


## Met à jour la liste des parties (découverte LAN) sans perdre la sélection.
func update_servers(servers: Array) -> void:
	_servers = servers
	_update_count()
	if is_instance_valid(_list) and current() == "jouer":
		_fill_list()


func _fill_list() -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var inside := focused != null and _list.is_ancestor_of(focused)  # la sélection était dans la liste
	var keep := ""
	if inside:
		keep = focused.get_meta("address", "")
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if _servers.is_empty():
		_list_hint.text = ""
		_list.add_child(_empty_state())
	else:
		_list_hint.text = "Flèches pour choisir, Entrée pour rejoindre."
	var found := false
	for s: Dictionary in _servers:
		var row := _server_row(s)
		_list.add_child(row)
		if keep != "" and s["address"] == keep:
			row.grab_focus.call_deferred()
			found = true
	if not found and (inside or focused == null) and not _modal.visible:
		_focus_first.call_deferred()


## Liste vide : grand message, et raccourci vers la création d'une partie.
func _empty_state() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size.y = 320
	var big := UI.label("Personne ne joue encore…" if scanning else "Rejoindre par adresse", 26, UI.ACCENT2)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)
	var txt := _wrap("Les parties lancées sur le réseau local apparaîtront ici toutes seules." if scanning else "La recherche automatique n'est pas disponible ici : indique l'adresse de la partie ci-dessous.", 15, UI.MUTED)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(txt)
	if can_host:
		var b := UI.menu_button("Créer une partie", func() -> void:
			_stack.pop_back()
			push("creer"))
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.set_meta("first", true)
		v.add_child(_sounds(b))
	return v


func _server_row(s: Dictionary) -> Button:
	var full: bool = s["players"] >= s["max"]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 78)
	b.set_meta("address", s["address"])
	b.set_meta("first", true)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := UI.sbox(Color("#f4f1ff") if st == "normal" else (Color("#fff3b0") if st != "disabled" else Color("#ebe8f2")), 14)
		sb.border_color = Color("#ddd5f3")
		sb.set_border_width_all(2)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", UI.focus_ring(14))
	b.disabled = full
	b.pressed.connect(func() -> void:
		if s["locked"]:
			ask_password(s["address"], s["name"])
		else:
			join_requested.emit(s["address"], ""))
	_sounds(b)

	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 18)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 8)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := UI.label(s["name"], 21)
	title.clip_text = true
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(title)
	# places : joueurs, bots, libres
	var seats := HBoxContainer.new()
	seats.add_theme_constant_override("separation", 4)
	seats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var humans: int = s["players"]
	var bots: int = s["bots"]
	for i in maxi(s["max"], humans + bots):
		var c := UI.ACCENT2 if i < humans else (UI.YELLOW if i < humans + bots else Color("#d9d4e8"))
		seats.add_child(UI.dot(c, 12))
	var info := "  %d/%d" % [humans, s["max"]]
	if bots > 0:
		info += " + %d bot%s" % [bots, "s" if bots > 1 else ""]
	seats.add_child(UI.label(info, 13, UI.MUTED))
	for badge: Array in ([["en partie", UI.ACCENT]] if s["phase"] != "lobby" else []) + ([["mot de passe", UI.MUTED]] if s["locked"] else []) + ([["complet", UI.MUTED]] if full else []):
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", UI.sbox(badge[1], 8, 7, 1))
		tag.add_child(UI.label(badge[0], 12, Color.WHITE))
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seats.add_child(tag)
	left.add_child(seats)
	h.add_child(left)
	# ping en barres
	var ms := roundi(s["ping"] * 1000.0)
	var bars := 3 if ms < 40 else (2 if ms < 120 else 1)
	var ping := UI.label("▮".repeat(bars) + "▯".repeat(3 - bars) + "  %d ms" % ms, 14, Color("#38b000") if bars == 3 else (Color("#e09f00") if bars == 2 else UI.ACCENT))
	ping.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ping)
	var arrow := UI.label("›", 34, UI.ACCENT)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(arrow)
	for k in h.get_children() + seats.get_children():
		if k is Control:
			k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	b.add_child(m)
	return b


## Fenêtre de mot de passe, par-dessus l'écran courant.
func ask_password(address: String, server_name: String, error := "") -> void:
	visible = true
	var edit := LineEdit.new()
	edit.secret = true
	edit.placeholder_text = "mot de passe"
	edit.set_meta("first", true)
	var go := func() -> void: join_requested.emit(address, edit.text)
	edit.text_submitted.connect(func(_t: String) -> void: go.call())
	var kids: Array = [UI.h1(server_name), _wrap("Cette partie demande un mot de passe.")]
	if error != "":
		kids.append(UI.label(error, 15, UI.ACCENT))
	kids.append(edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var ok := UI.button("Rejoindre", "big", go)
	ok.focus_mode = Control.FOCUS_ALL
	var no := UI.button("Annuler", "", func() -> void: _close_modal())
	no.focus_mode = Control.FOCUS_ALL
	row.add_child(_sounds(ok))
	row.add_child(_sounds(no))
	kids.append(row)
	_open_modal(kids)


## Message d'erreur (connexion refusée, serveur fermé…), par-dessus l'écran courant.
func show_error(text: String) -> void:
	var ok := UI.button("OK", "big", func() -> void: _close_modal())
	ok.focus_mode = Control.FOCUS_ALL
	ok.custom_minimum_size.x = 140
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_open_modal([UI.h1("Oups !"), _wrap(text, 16), ok])


func _open_modal(kids: Array) -> void:
	for c in _modal_card.get_children():
		_modal_card.remove_child(c)
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	for c: Control in kids:
		v.add_child(c)
	_modal_card.add_child(v)
	_modal.visible = true
	_modal_card.pivot_offset = _modal_card.size / 2.0
	_modal_card.scale = Vector2(0.9, 0.9)
	_modal_card.create_tween().tween_property(_modal_card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_focus_first.call_deferred()


func _close_modal() -> void:
	_modal.visible = false
	_focus_first.call_deferred()


# ---------- Créer une partie ----------

func _screen_create() -> Control:
	var p := _side_panel("Créer une partie", 520)
	var v: VBoxContainer = p[1]
	var cfg: Dictionary = Config.server_cfg.duplicate()
	if str(cfg.get("name", "")) == "":
		cfg["name"] = "Partie de %s" % Config.profile["name"]
	var cur := [cfg]
	for c: Control in GameUI.server_fields(cfg, func(next: Dictionary) -> void: cur[0] = next):
		for k in c.get_children():
			if k is CheckBox:
				k.focus_mode = Control.FOCUS_ALL
		v.add_child(c)
	v.add_child(_wrap("Les joueurs du réseau local verront ta partie dans leur liste. Tu règles les manches et les jeux dans le lobby, et tout reste modifiable même quand des joueurs sont connectés.", 14, UI.MUTED))
	var go := UI.menu_button("Créer la partie", func() -> void:
		var f := get_viewport().gui_get_focus_owner()
		if f is LineEdit:
			f.release_focus()  # valide le champ en cours de saisie
		(func() -> void: create_requested.emit(cur[0])).call_deferred(), true)
	go.set_meta("first", true)
	v.add_child(_sounds(go))
	return p[0]


# ---------- Personnage ----------

func _screen_character() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# zone de glisser pour faire tourner le personnage
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.mouse_default_cursor_shape = Control.CURSOR_DRAG
	stage.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
			spin.emit(ev.relative.x * 0.012))
	root.add_child(stage)

	var back_b := _back_button()
	back_b.position = Vector2(40, 32)
	root.add_child(back_b)
	var h := UI.outlined("Personnage", 40, Color.WHITE, 10)
	h.position = Vector2(40, 84)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(h)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_bottom = -28
	card.custom_minimum_size.x = 460
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)

	# carrousel : ◀ nom ▶ (gauche / droite au clavier ou à la manette quand il a le focus)
	var cur: Dictionary = Config.profile.duplicate()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_l := Button.new()
	name_l.focus_mode = Control.FOCUS_ALL
	name_l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	name_l.custom_minimum_size = Vector2(260, 0)
	name_l.add_theme_font_size_override("font_size", 28)
	for st in ["normal", "hover", "pressed"]:
		name_l.add_theme_stylebox_override(st, UI.sbox(Color("#f4f1ff"), 14, 16, 8))
	name_l.add_theme_stylebox_override("focus", UI.focus_ring(14))
	name_l.set_meta("first", true)
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 6)
	var refresh := func() -> void:
		name_l.text = HAT_NAMES.get(cur["hat"], cur["hat"])
		name_l.add_theme_color_override("font_color", Gfx.col(int(cur["color"])).darkened(0.25))
		name_l.add_theme_color_override("font_focus_color", Gfx.col(int(cur["color"])).darkened(0.25))
		name_l.add_theme_color_override("font_hover_color", Gfx.col(int(cur["color"])).darkened(0.25))
		for c in dots.get_children():
			dots.remove_child(c)
			c.queue_free()
		for hat: String in Protocol.HATS:
			dots.add_child(UI.dot(Gfx.col(Protocol.HAT_COLOR[hat]) if hat == cur["hat"] else Color("#d9d4e8"), 12 if hat == cur["hat"] else 9))
	var step := func(d: int) -> void:
		var i := Protocol.HATS.find(cur["hat"])
		var hat: String = Protocol.HATS[posmod(i + d, Protocol.HATS.size())]
		cur["hat"] = hat
		cur["color"] = Protocol.HAT_COLOR[hat]
		refresh.call()
		profile_changed.emit(cur.duplicate())
	name_l.gui_input.connect(func(ev: InputEvent) -> void:
		if ev.is_action_pressed("ui_left"):
			step.call(-1)
			name_l.accept_event()
		elif ev.is_action_pressed("ui_right"):
			step.call(1)
			name_l.accept_event())
	var prev := UI.button("◀", "big", func() -> void: step.call(-1))
	var next := UI.button("▶", "big", func() -> void: step.call(1))
	row.add_child(prev)
	row.add_child(_sounds(name_l))
	row.add_child(next)
	v.add_child(row)
	v.add_child(dots)
	refresh.call()

	# pseudo
	var name_edit := LineEdit.new()
	name_edit.text = cur["name"]
	name_edit.max_length = 16
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var push_name := func() -> void:
		var n := name_edit.text.strip_edges()
		if n != "" and n != cur["name"]:
			cur["name"] = n
			profile_changed.emit(cur.duplicate())
	# Entrée (ou clic sur le nom, ou « Valider ») : on garde ce personnage et on revient à l'écran précédent
	var validate := func() -> void:
		push_name.call()
		_stack.pop_back()
		sound.emit("checkpoint")
		_show(_stack[-1], -1)
	name_l.pressed.connect(validate)
	name_edit.text_submitted.connect(func(_t: String) -> void: validate.call())
	name_edit.focus_exited.connect(push_name)
	v.add_child(UI.row("Pseudo", [name_edit]))
	var ok := UI.menu_button("Valider", validate, true)
	ok.alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_sounds(ok))
	v.add_child(UI.small("◀ ▶ pour changer de personnage · Entrée pour valider · glisse dans le décor pour le faire tourner"))
	name_l.focus_neighbor_bottom = name_l.get_path_to(name_edit)
	root.add_child(card)
	return root


# ---------- Options ----------

func _screen_options() -> Control:
	var p := _side_panel("Options", 520)
	var v: VBoxContainer = p[1]

	v.add_child(UI.h2("Graphismes"))
	var q_row := HBoxContainer.new()
	q_row.add_theme_constant_override("separation", 8)
	var q_buttons: Array[Button] = []
	for i in 3:
		var b := UI.button(Config.QUALITY_NAMES[i].capitalize(), "", Callable())
		b.focus_mode = Control.FOCUS_ALL
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == Config.quality:
			UI.mark_selected(b)
			b.set_meta("first", true)
		b.pressed.connect(func() -> void:
			quality_changed.emit(i)
			for j in 3:
				for st in ["normal", "hover", "pressed"]:
					q_buttons[j].remove_theme_stylebox_override(st)
			UI.mark_selected(q_buttons[i]))
		q_buttons.append(b)
		q_row.add_child(_sounds(b))
	v.add_child(q_row)
	v.add_child(_wrap("« Légers » et « moyens » soulagent les petites cartes graphiques.", 13, UI.MUTED))

	if not OS.has_feature("web"):
		v.add_child(UI.h2("Écran"))
		var fs := CheckBox.new()
		fs.text = "Plein écran"
		fs.add_theme_font_size_override("font_size", 16)
		fs.focus_mode = Control.FOCUS_ALL
		fs.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		fs.button_pressed = Config.fullscreen
		fs.toggled.connect(func(on: bool) -> void:
			Config.fullscreen = on
			Config.apply_options()
			Config.save())
		v.add_child(_sounds(fs))

	v.add_child(UI.h2("Son et contrôles"))
	v.add_child(_slider("Volume des effets", Config.sfx_volume, 0.0, 1.0, func(x: float) -> String: return "%d %%" % roundi(x * 100.0), func(x: float) -> void:
		Config.sfx_volume = x
		Config.apply_options()
		sound.emit("tick")))
	v.add_child(_slider("Sensibilité de la souris", Config.mouse_sens, 0.25, 3.0, func(x: float) -> String: return "× %.2f" % x, func(x: float) -> void:
		Config.mouse_sens = x))
	v.add_child(_wrap("Les réglages sont enregistrés tout de suite.", 13, UI.MUTED))
	return p[0]


## Ligne « libellé, curseur, valeur ». L'enregistrement se fait au relâchement.
func _slider(text: String, value: float, mn: float, mx: float, fmt: Callable, on_change: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := UI.label(text, 15)
	l.custom_minimum_size.x = 190
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = 0.05
	s.value = value
	s.focus_mode = Control.FOCUS_ALL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size.y = 26
	var val := UI.label(fmt.call(value), 15, UI.MUTED)
	val.custom_minimum_size.x = 64
	s.value_changed.connect(func(x: float) -> void:
		val.text = fmt.call(x)
		on_change.call(x))
	s.drag_ended.connect(func(_c: bool) -> void: Config.save())
	s.focus_exited.connect(Config.save)
	h.add_child(_sounds(s))
	h.add_child(val)
	return h
