class_name Cursors
extends RefCounted
## Curseurs de souris aux couleurs du jeu, dessinés au démarrage (comme le reste : aucune image à charger) :
## flèche jaune cernée d'encre, flèche rose à étincelle sur ce qui se clique, poignée pour faire tourner le
## personnage, barre de texte. Formes pleines, contour d'encre, liseré blanc (lisible sur fond sombre) et petite
## ombre portée, lissées par suréchantillonnage.

const SIZE := 32
const OUTLINE := 1.15  # demi-épaisseur du contour d'encre (pixels)
const RIM := 1.0  # liseré blanc autour du contour
const SS := 3  # suréchantillonnage par côté


## Remplace les curseurs du système (sans effet si la plateforme ne le permet pas, ou sans écran).
## Le dessin (une demi-seconde) se fait sur un fil de travail pour ne pas retarder le démarrage.
static func install() -> void:
	if DisplayServer.get_name() == "headless" or not DisplayServer.has_feature(DisplayServer.FEATURE_CUSTOM_CURSOR_SHAPE):
		return
	WorkerThreadPool.add_task(func() -> void: _apply.call_deferred(_build()))


## [image, forme, point actif] pour chaque curseur.
static func _build() -> Array:
	var arrow := _arrow(Vector2.ZERO)
	var grab := _render(_grab())
	return [
		[_render([[arrow, UI.YELLOW]]), Input.CURSOR_ARROW, Vector2(2, 1)],
		[_render([[arrow, UI.ACCENT], [_star(Vector2(24.5, 24.5), 6.8, 3.2), UI.YELLOW]]), Input.CURSOR_POINTING_HAND, Vector2(2, 1)],
		[grab, Input.CURSOR_DRAG, Vector2(16, 16)],
		[grab, Input.CURSOR_MOVE, Vector2(16, 16)],
		[_render(_ibeam()), Input.CURSOR_IBEAM, Vector2(16, 16)],
	]


static func _apply(cursors: Array) -> void:
	for c: Array in cursors:
		Input.set_custom_mouse_cursor(c[0], c[1], c[2])


# ---------- formes (coordonnées en pixels dans un carré de 32) ----------

static func _arrow(o: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(2, 1), Vector2(2, 25), Vector2(7.8, 20), Vector2(11.8, 29), Vector2(17, 26.8), Vector2(13.2, 18.4), Vector2(21, 18.4)])
	for i in pts.size():
		pts[i] += o
	return pts


static func _star(c: Vector2, r_out: float, r_in: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	return pts


static func _circle(c: Vector2, r: float, n := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := i * TAU / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Poignée : rond jaune et deux flèches blanches (gauche, droite).
static func _grab() -> Array:
	var c := Vector2(16, 16)
	var left := PackedVector2Array([Vector2(2, 16), Vector2(10, 8), Vector2(10, 24)])
	var right := PackedVector2Array([Vector2(30, 16), Vector2(22, 8), Vector2(22, 24)])
	return [[left, UI.ACCENT], [right, UI.ACCENT], [_circle(c, 7), UI.YELLOW]]


## Barre de texte : I épais blanc cerné d'encre.
static func _ibeam() -> Array:
	var pts := PackedVector2Array([
		Vector2(9, 3), Vector2(23, 3), Vector2(23, 8), Vector2(18.5, 8), Vector2(18.5, 24), Vector2(23, 24),
		Vector2(23, 29), Vector2(9, 29), Vector2(9, 24), Vector2(13.5, 24), Vector2(13.5, 8), Vector2(9, 8),
	])
	return [[pts, UI.YELLOW]]


# ---------- rendu ----------

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _edge_dist(p: Vector2, poly: PackedVector2Array) -> float:
	var d := INF
	for i in poly.size():
		d = minf(d, _seg_dist(p, poly[i], poly[(i + 1) % poly.size()]))
	return d


## Couleur d'un point : ombre, liseré blanc, puis les formes dans l'ordre (la dernière dessus), remplies et cernées.
static func _sample(p: Vector2, shapes: Array) -> Color:
	var out := Color(0, 0, 0, 0)
	var sp := p - Vector2(1.2, 1.8)  # ombre portée, vers le bas à droite
	for s: Array in shapes:
		var poly: PackedVector2Array = s[0]
		if Geometry2D.is_point_in_polygon(sp, poly) or _edge_dist(sp, poly) <= OUTLINE + RIM:
			out = Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.35)
			break
	var dists: Array[float] = []
	var insides: Array[bool] = []
	for s: Array in shapes:
		var poly: PackedVector2Array = s[0]
		insides.append(Geometry2D.is_point_in_polygon(p, poly))
		dists.append(_edge_dist(p, poly))
	for i in shapes.size():
		if dists[i] <= OUTLINE + RIM:
			out = Color.WHITE
			break
	for i in shapes.size():
		if dists[i] <= OUTLINE:
			out = UI.INK
		elif insides[i]:
			out = shapes[i][1]
	return out


static func _render(shapes: Array) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var n := float(SS * SS)
	for y in SIZE:
		for x in SIZE:
			var acc := Vector4.ZERO  # couleur prémultipliée + alpha
			for sy in SS:
				for sx in SS:
					var c := _sample(Vector2(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS), shapes)
					acc += Vector4(c.r * c.a, c.g * c.a, c.b * c.a, c.a)
			if acc.w > 0.0:
				img.set_pixel(x, y, Color(acc.x / acc.w, acc.y / acc.w, acc.z / acc.w, acc.w / n))
	return img
