class_name ParkourProps3
extends RefCounted
## Parcours délirant — vague 3 : boutons, portes, leviers, trappes, dalles mémoire, boîtes surprise, pièces, bananes,
## gant de boxe, bouclier et super saut (pour soi et pour les autres), HUD de l'objet tenu et des pièces.
## Tout l'état vient du serveur (Level.new_state tenu par ParkourShared.apply_level_msg) ; le rendu le lit au temps serveur.

const LINK_COLORS := [0xff4d6d, 0x4361ee, 0xffd60a, 0x70e000, 0xc77dff, 0xff9e00, 0x00b4d8]
const ITEM_COLORS := {"super": 0x70e000, "shield": 0x00b4d8, "banana": 0xffd60a, "glove": 0xff4d6d}

var ctx: Main
var level: Dictionary
var st: Dictionary  # état de niveau partagé avec ParkourClient
var recs: Array = []
var item: Variant = null  # objet tenu par le joueur local
var coins := 0
var _bananas := {}  # clé → nœud
var _banana_mesh: Node3D
var _shields := {}  # id → bulle
var _supers := {}  # id → fin du super saut (effet annoncé par le serveur)
var _gloves: Array = []  # { node, until }
var _hud_item: Label
var _hud_btn: Button
var _hud_card: PanelContainer
var _sparkle := 0.0
var _coin_total := 0


func _init(c: Main, l: Dictionary, state: Dictionary) -> void:
	ctx = c
	level = l
	st = state
	for e: Dictionary in l["elements"]:
		if e["type"] == "coin":
			_coin_total += 1


func _v(e: Dictionary) -> Vector3:
	return Vector3(e["pos"][0], e["pos"][1], e["pos"][2])


func _root(e: Dictionary) -> Node3D:
	var g := Node3D.new()
	g.position = _v(e)
	g.rotation.y = e.get("yaw", 0.0)
	ctx.world.add_child(g)
	return g


## Couleur commune à tous les éléments d'un même lien (bouton, levier, portes, trappes).
static func link_color(link: String) -> int:
	return LINK_COLORS[absi(link.hash()) % LINK_COLORS.size()]


# ---------- construction ----------

func build(e: Dictionary, i: int) -> Node3D:
	var sx: float = e["size"][0]
	var sy: float = e["size"][1]
	var sz: float = e["size"][2]
	var rec := {"e": e, "i": i, "type": e["type"]}
	var root: Node3D = null
	match e["type"]:
		"button":
			root = _root(e)
			var lc := link_color(e["link"])
			Gfx.mesh(Shapes.rbox(sx, sy, sz, minf(0.08, sy * 0.4)), Gfx.mat(0x3d4450, {"metal": 0.4, "rough": 0.4}), 0, 0, 0, root)
			var cap := Gfx.mesh(Shapes.cylinder(minf(sx, sz) * 0.36, minf(sx, sz) * 0.4, 0.22, 24), Gfx.mat(lc, {"glow": 0.4, "rough": 0.3}), 0, sy / 2.0 + 0.1, 0, root)
			rec["cap"] = cap
			rec["cap_y"] = cap.position.y
			rec["mat"] = cap.material_override
		"door":
			root = _root(e)
			var lc: int = Gfx.to_int(Color(e["color"])) if e.get("color") != null else link_color(e["link"])
			var panel := Node3D.new()
			root.add_child(panel)
			Gfx.mesh(Shapes.rbox(sx, sy, sz, minf(0.12, sz * 0.4)), Gfx.mat(Gfx.shade(lc, 0.85), {"rough": 0.4}), 0, 0, 0, panel)
			# planches et rivets : on reconnaît une porte ; la serrure prend la couleur du lien
			var stripe := Gfx.mat(Gfx.shade(lc, 0.65))
			for k in maxi(2, int(sx / 1.6)):
				var x := -sx / 2.0 + (k + 0.5) * sx / maxi(2, int(sx / 1.6))
				Gfx.mesh(Shapes.rbox(0.08, sy * 0.92, sz + 0.04, 0.03), stripe, x + sx / maxi(2, int(sx / 1.6)) / 2.0 - 0.04, 0, 0, panel)
			for s in [-1.0, 1.0]:
				Gfx.mesh(Shapes.sphere(0.28, 16, 10), Gfx.mat(lc, {"glow": 0.6}), 0, 0, s * (sz / 2.0 + 0.05), panel, false)
				Gfx.mesh(Shapes.rbox(0.12, 0.3, 0.06, 0.03), Gfx.mat(0x2b2140), 0, -0.05, s * (sz / 2.0 + 0.3), panel, false)
			# cadre fixe dans lequel la porte s'enfonce
			var frame := Gfx.mat(0x5c6470, {"metal": 0.4, "rough": 0.4})
			for s in [-1.0, 1.0]:
				Gfx.mesh(Shapes.rbox(0.3, sy + 0.3, sz + 0.3, 0.1), frame, s * (sx / 2.0 + 0.15), 0.15, 0, root)
			Gfx.mesh(Shapes.rbox(sx + 0.6, 0.3, sz + 0.3, 0.1), frame, 0, sy / 2.0 + 0.3, 0, root)
			rec["panel"] = panel
		"trapdoor":
			root = _root(e)
			var lc: int = Gfx.to_int(Color(e["color"])) if e.get("color") != null else link_color(e["link"])
			var leaves := []
			for s in [-1.0, 1.0]:
				var hinge := Node3D.new()
				hinge.position = Vector3(s * sx / 2.0, sy / 2.0, 0)
				root.add_child(hinge)
				var leaf := Gfx.mesh(Shapes.rbox(sx / 2.0 - 0.02, sy, sz, minf(0.1, sy * 0.3)), Gfx.mat(0xffffff, {"map": Tex.planks(), "uv": Vector2(1, maxf(1.0, sz / 1.5))}), -s * sx / 4.0, -sy / 2.0, 0, hinge)
				Gfx.mesh(Shapes.rbox(sx / 2.0 - 0.3, 0.06, 0.18, 0.03), Gfx.mat(lc, {"glow": 0.35}), 0, sy / 2.0 + 0.02, 0, leaf, false)
				leaves.append(hinge)
			rec["leaves"] = leaves
			# cadre
			var frame := Gfx.mat(0x5c6470, {"metal": 0.4})
			for s in [-1.0, 1.0]:
				Gfx.mesh(Shapes.rbox(sx + 0.3, sy * 0.9, 0.15, 0.05), frame, 0, 0, s * (sz / 2.0 + 0.08), root)
		"lever":
			root = _root(e)
			root.position.y -= sy / 2.0
			var lc := link_color(e["link"])
			Gfx.mesh(Shapes.rbox(sx * 0.8, 0.4, sz * 0.8, 0.12), Gfx.mat(0x3d4450, {"metal": 0.4, "rough": 0.4}), 0, 0.2, 0, root)
			var pivot := Node3D.new()
			pivot.position.y = 0.4
			root.add_child(pivot)
			var h := maxf(0.8, sy * 0.7)
			Gfx.mesh(Shapes.cylinder(0.07, 0.07, h, 8), Gfx.mat(0xbfc7d1, {"metal": 0.7, "rough": 0.3}), 0, h / 2.0, 0, pivot)
			var knob := Gfx.mesh(Shapes.sphere(0.2, 14, 10), Gfx.mat(lc, {"glow": 0.5}), 0, h, 0, pivot)
			rec["pivot"] = pivot
			rec["knob"] = knob.material_override
		"memory":
			root = Node3D.new()
			ctx.world.add_child(root)
			var tiles := Level.memory_tiles(e)
			var nodes := []
			for k in tiles.size():
				var c: Phys.Col = tiles[k]
				var tm := Gfx.mat(0xe9ecef, {"rough": 0.35})
				var n := Gfx.mesh(Shapes.rbox(c.hx * 2.0, c.hy * 2.0, c.hz * 2.0, minf(0.1, c.hy)), tm, c.cx, c.cy, c.cz, root)
				n.rotation.y = c.yaw
				nodes.append([n, tm, Vector3(c.cx, c.cy, c.cz)])
				# point d'interrogation discret sur chaque dalle
				var q := Gfx.label3d("?", minf(c.hx, c.hz) * 1.2, Color("#b8bfd0"), Color(0, 0, 0, 0))
				q.basis = Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -PI / 2.0)  # à plat, lisible depuis le début de la grille
				q.position = Vector3(0, c.hy + 0.01, 0)
				n.add_child(q)
			rec["tiles"] = nodes
		"itembox":
			root = _root(e)
			var box := Node3D.new()
			root.add_child(box)
			var bm := Gfx.mat(0xffffff, {"map": Tex.stripes("#c77dff", "#ffd60a"), "uv": Vector2(2, 2), "glow": 0.25, "rough": 0.3, "opacity": 0.92})
			Gfx.mesh(Shapes.rbox(sx, sy, sz, minf(0.15, sx * 0.2)), bm, 0, 0, 0, box)
			for f in 4:
				var l := Gfx.label3d("?", sy * 0.7, Color.WHITE, Color("#2b2140"))
				l.position = Vector3(sin(f * PI / 2.0) * (sx / 2.0 + 0.01), 0, cos(f * PI / 2.0) * (sz / 2.0 + 0.01))
				l.rotation.y = f * PI / 2.0
				box.add_child(l)
			rec["box"] = box
			rec["was"] = true
		"coin":
			root = _root(e)
			var coin := Node3D.new()
			root.add_child(coin)
			var r := minf(sx, sy) / 2.0
			var cm := Gfx.mat(0xffc300, {"metal": 0.85, "rough": 0.22, "glow": 0.2})
			var disc := Gfx.mesh(Shapes.cylinder(r, r, 0.12, 24), cm, 0, 0, 0, coin)
			disc.rotation.x = PI / 2.0
			# liseré en relief des deux côtés
			var rim := Gfx.mesh(Shapes.torus(r * 0.72, r * 0.08, 24, 6), Gfx.mat(0xfff3b0, {"metal": 0.6, "rough": 0.2}), 0, 0, 0, coin, false)
			rim.rotation.x = PI / 2.0
			rim.scale = Vector3(1, 1.6, 1)
			rec["coin"] = coin
	if root != null and rec.size() > 3:
		recs.append(rec)
	return root


# ---------- HUD ----------

## Carte en bas de l'écran : objet tenu (avec un bouton « Utiliser ») et pièces.
func build_hud() -> void:
	_hud_card = ctx.ui.hud_card("bottom", true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_hud_card.add_child(row)
	_hud_item = UI.label("", 16)
	row.add_child(_hud_item)
	_hud_btn = UI.button("Utiliser (E)", "", func() -> void: use_item())
	_hud_btn.focus_mode = Control.FOCUS_NONE
	row.add_child(_hud_btn)
	_refresh_hud()


func _refresh_hud() -> void:
	if _hud_item == null:
		return
	var txt := ""
	if item != null:
		txt = "Objet : %s" % ParkourShared.ITEM_NAMES.get(item, str(item))
	if _coin_total > 0:
		txt += ("   ·   " if txt != "" else "") + "Pièces : %d/%d" % [coins, _coin_total]
	_hud_item.text = txt
	_hud_btn.visible = item != null
	_hud_card.visible = txt != ""


func use_item() -> void:
	if item != null:
		ctx.send_game({"t": "use"})


# ---------- messages ----------

func on_message(m: Dictionary) -> void:
	var me := ctx.my_id
	match m["t"]:
		"item":
			if m["id"] == me:
				var had: Variant = item
				item = m["kind"]
				if item != null and had == null:
					ctx.sfx.pickup()
					ctx.toast("%s ! (E, clic droit ou bouton)" % ParkourShared.ITEM_NAMES.get(item, ""), 2.0)
				_refresh_hud()
		"box":
			var e: Dictionary = level["elements"][int(m["i"])]
			ctx.particles.burst(_v(e), 20, [0xc77dff, 0xffd60a, 0xffffff], 5.0, 0.13, 0.6)
		"effect":
			if m["kind"] == "super":
				_supers[m["id"]] = float(m["until"])
			if m["id"] == me:
				ctx.sfx.checkpoint()
		"coin":
			var e: Dictionary = level["elements"][int(m["i"])]
			if m["id"] == me:
				coins = int(m["n"])
				ctx.sfx.xylo()
				ctx.particles.burst(_v(e), 16, [0xffc300, 0xfff3b0], 4.0, 0.1, 0.5)
				_refresh_hud()
		"glove":
			var p: ClientPlayer = ctx.players.get(m["id"])
			if p:
				_punch(p)
			for id: String in m["hit"]:
				var h: ClientPlayer = ctx.players.get(id)
				if h:
					ctx.particles.burst(h.pos + Vector3(0, 1, 0), 14, [0xffffff, 0xff4d6d, 0xffd60a], 6.0, 0.14, 0.5)
			ctx.sfx.hit()
		"bananaGone":
			if m["by"] != "":
				var b: Node3D = _bananas.get(int(m["k"]))
				if b:
					ctx.particles.burst(b.position + Vector3(0, 0.3, 0), 10, [0xffd60a, 0xfff3b0], 4.0, 0.1, 0.5)
				ctx.sfx.boing()
		"tile":
			ctx.sfx.crumble()
		"open":
			ctx.sfx.place()
		"lever":
			ctx.sfx.tick()


## Gant de boxe qui jaillit devant le joueur.
func _punch(p: ClientPlayer) -> void:
	var g := Node3D.new()
	ctx.world.add_child(g)
	Gfx.mesh(Shapes.sphere(0.32, 14, 10), Gfx.mat(0xe5383b, {"rough": 0.3}), 0, 0, 0, g)
	Gfx.mesh(Shapes.cylinder(0.2, 0.22, 0.3, 12), Gfx.mat(0xffffff), 0, 0, -0.3, g).rotation.x = PI / 2.0
	_gloves.append({"node": g, "p": p, "t0": ctx.now()})


# ---------- animation ----------

func update(t: float, dt: float) -> void:
	for rec: Dictionary in recs:
		var e: Dictionary = rec["e"]
		var i: int = rec["i"]
		match rec["type"]:
			"button":
				var pressed := Level.link_open(st, e["link"], t)
				rec["cap"].position.y = rec["cap_y"] - (0.15 if pressed else 0.0)
				rec["mat"].emission_energy_multiplier = 1.6 if pressed else 0.4
			"door":
				var o := Level.door_openness(e, st, t)
				var panel: Node3D = rec["panel"]
				panel.position.y = -o * (e["size"][1] + 0.05)
				panel.visible = o < 0.999
			"trapdoor":
				var o := Level.door_openness(e, st, t)
				var leaves: Array = rec["leaves"]
				for k in 2:
					leaves[k].rotation.z = (-1.0 if k == 0 else 1.0) * o * PI * 0.5
			"lever":
				var down := Level.lever_down(e, i, st, t)
				var pv: Node3D = rec["pivot"]
				pv.rotation.x = move_toward(pv.rotation.x, 1.0 if down else -0.7, dt * 8.0)
				rec["knob"].emission_energy_multiplier = 0.3 if down else 0.6 + 0.4 * sin(t * 4.0)
			"memory":
				var tiles: Array = rec["tiles"]
				for k in tiles.size():
					var key := Level.memory_key(i, k)
					var n: MeshInstance3D = tiles[k][0]
					var at: Variant = st["tiles"].get(key)
					if at != null and t >= at:
						# dalle piégée : elle tombe (et reste tombée)
						var f: float = t - at
						n.visible = f < 2.5
						n.position = tiles[k][2] - Vector3(0, 12.0 * f * f, 0)
						n.rotation.x = f * 2.0
						tiles[k][1].albedo_color = Gfx.col(0xe5383b)
					elif st["safe"].has(key):
						var tm: StandardMaterial3D = tiles[k][1]
						tm.albedo_color = Gfx.col(0x70e000)
						tm.emission_enabled = true
						tm.emission = tm.albedo_color
						tm.emission_energy_multiplier = 0.4
			"itembox":
				var ready := Level.box_ready(i, st, t)
				var box: Node3D = rec["box"]
				box.visible = ready
				if ready and not rec["was"]:
					ctx.particles.burst(box.global_position, 12, [0xc77dff, 0xffffff], 3.0, 0.1, 0.4)
				rec["was"] = ready
				box.rotation = Vector3(0.25, t * 1.4 + i, 0.15)
				box.position.y = sin(t * 2.0 + i) * 0.15
			"coin":
				var coin: Node3D = rec["coin"]
				coin.visible = not st["coins"].has(i)  # déjà prise par moi : cachée (les autres la voient encore)
				coin.rotation.y = t * 3.0 + i
				coin.position.y = sin(t * 2.5 + i) * 0.12
	_update_bananas(t)
	_update_players(t, dt)
	# gants : sortent puis rentrent en 0.35 s
	var k := 0
	while k < _gloves.size():
		var gl: Dictionary = _gloves[k]
		var f: float = (t - gl["t0"]) / 0.35
		var p: ClientPlayer = gl["p"]
		if f > 1.0 or p == null:
			gl["node"].queue_free()
			_gloves.remove_at(k)
			continue
		var reach := sin(f * PI) * 1.6
		gl["node"].position = p.pos + Vector3(sin(p.yaw) * (0.4 + reach), 1.0, cos(p.yaw) * (0.4 + reach))
		gl["node"].rotation.y = p.yaw
		k += 1
	# poignée du bouton « utiliser » : E, clic droit, bouton X de la manette
	if item != null and (ctx.input.hit("KeyE") or ctx.input.hit("Mouse2") or ctx.input.hit("PadUse")):
		use_item()


func _update_bananas(t: float) -> void:
	var bs: Dictionary = st["bananas"]
	for key: int in _bananas.keys():
		if not bs.has(key):
			_bananas[key].queue_free()
			_bananas.erase(key)
	for key: int in bs.keys():
		if not _bananas.has(key):
			var p: Array = bs[key]
			var b := _make_banana()
			b.position = Vector3(p[0], p[1] + 0.12, p[2])
			b.rotation.y = key * 1.7
			ctx.world.add_child(b)
			_bananas[key] = b
		_bananas[key].scale = Vector3.ONE * (1.0 + 0.05 * sin(t * 5.0 + key))


func _make_banana() -> Node3D:
	var g := Node3D.new()
	var m := Gfx.mat(0xffd60a, {"rough": 0.35})
	var arc := Gfx.mesh(Shapes.torus_arc(0.28, 0.09, 8, 12, PI * 0.8), m, 0, 0.0, 0, g)
	arc.rotation = Vector3(PI / 2.0, 0, PI * 1.1)
	for s in [-1.0, 1.0]:
		Gfx.mesh(Shapes.sphere(0.05, 6, 4), Gfx.mat(0x6b4226), s * 0.27, 0.0, 0.08, g, false)
	return g


## Bouclier (bulle) et super saut (étincelles) des joueurs ; poses tirées des drapeaux (FLAG_SHIELD).
func _update_players(t: float, dt: float) -> void:
	var b := ctx.body
	for p: ClientPlayer in ctx.players.values():
		var is_me := p.id == ctx.my_id
		var shielded: bool = b.shield > 0.0 if is_me else p.flags & Protocol.FLAG_SHIELD != 0
		var bubble: Node3D = _shields.get(p.id)
		if shielded and p.chr.visible:
			if bubble == null:
				bubble = Gfx.mesh(Shapes.sphere(1.0, 20, 14), _shield_mat(), 0, 0, 0, ctx.world, false)
				_shields[p.id] = bubble
			bubble.visible = true
			bubble.position = p.pos + Vector3(0, 0.8, 0)
			var s := 1.05 + 0.04 * sin(t * 6.0)
			bubble.scale = Vector3(s, s * 1.05, s)
		elif bubble:
			bubble.visible = false
		var sup: bool = b.super_jump > 0.0 if is_me else t < _supers.get(p.id, -1.0)
		if sup and p.chr.visible:
			_sparkle -= dt
			if _sparkle < 0.0:
				_sparkle = 0.05
				ctx.particles.emit(p.pos.x + (randf() - 0.5) * 0.6, p.pos.y + randf() * 0.4, p.pos.z + (randf() - 0.5) * 0.6, 0, 1.5, 0, 0x70e000 if randf() < 0.6 else 0xfff3b0, 0.08, 0.5, -1.0)
		# autres joueurs : traînée pendant l'élan d'un speed pad ou le vol d'un canon (drapeaux de pose)
		if not is_me and p.chr.visible and p.flags & (Protocol.FLAG_BOOST | Protocol.FLAG_FLIGHT) != 0 and randf() < 0.4:
			ctx.particles.emit(p.pos.x + (randf() - 0.5) * 0.4, p.pos.y + 0.3 + randf() * 0.9, p.pos.z + (randf() - 0.5) * 0.4, 0, 0, 0, 0xffffff if p.flags & Protocol.FLAG_BOOST != 0 else 0xffd60a, 0.07, 0.35, 0.0)


static var _smat: StandardMaterial3D
static func _shield_mat() -> StandardMaterial3D:
	if _smat == null:
		_smat = Gfx.mat(0x90e0ef, {"opacity": 0.22, "rough": 0.05})
		_smat.rim_enabled = true
		_smat.rim = 1.0
		_smat.emission_enabled = true
		_smat.emission = Gfx.col(0x00b4d8)
		_smat.emission_energy_multiplier = 0.25
	return _smat


func clear() -> void:
	for n: Node3D in _shields.values():
		if is_instance_valid(n):
			n.queue_free()
	_shields.clear()
