class_name Tex
extends RefCounted
## Textures procédurales (équivalent des textures « canvas » d'origine), générées une fois puis mises en cache.

static var _cache := {}


static func _finish(key: String, img: Image) -> ImageTexture:
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


static func _new(s: int, c: Color) -> Image:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


static func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 1.0:
		img.set_pixel(x, y, c)
	else:
		var o := img.get_pixel(x, y)
		img.set_pixel(x, y, Color(lerpf(o.r, c.r, c.a), lerpf(o.g, c.g, c.a), lerpf(o.b, c.b, c.a), 1.0))


static func _rect(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	for py in range(int(y), int(y + h)):
		for px in range(int(x), int(x + w)):
			_blend(img, px, py, c)


static func _disc(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for py in range(int(cy - r), int(cy + r) + 1):
		for px in range(int(cx - r), int(cx + r) + 1):
			if (px + 0.5 - cx) ** 2 + (py + 0.5 - cy) ** 2 <= r * r:
				_blend(img, px, py, c)


static func checker(a: String, b: String) -> ImageTexture:
	var key := "checker" + a + b
	if _cache.has(key):
		return _cache[key]
	var s := 128
	var img := _new(s, Color(b))
	var ca := Color(a)
	for y in s:
		for x in s:
			if (x / (s / 2) + y / (s / 2)) % 2 == 1:
				img.set_pixel(x, y, ca)
	return _finish(key, img)


## Bandes diagonales (rembourrage, signalisation).
static func stripes(a: String, b: String) -> ImageTexture:
	var key := "stripes" + a + b
	if _cache.has(key):
		return _cache[key]
	var s := 128
	var img := _new(s, Color(a))
	var cb := Color(b)
	for y in s:
		for x in s:
			if posmod(x - y, s / 2) < s / 4:
				img.set_pixel(x, y, cb)
	return _finish(key, img)


## Sol à gros motif doux (damier arrondi).
static func soft(a: String, b: String) -> ImageTexture:
	var key := "soft" + a + b
	if _cache.has(key):
		return _cache[key]
	var s := 128
	var img := _new(s, Color(a))
	var cb := Color(b)
	var half := s / 2.0
	var w := half - 12.0
	var rad := 14.0
	for y in s:
		for x in s:
			var lx := fposmod(x + 0.5, half) - 6.0
			var ly := fposmod(y + 0.5, half) - 6.0
			if (int(x / half) + int(y / half)) % 2 == 1:
				continue
			# rectangle arrondi : distance au rectangle intérieur
			var dx := maxf(maxf(rad - lx, lx - (w - rad)), 0.0)
			var dy := maxf(maxf(rad - ly, ly - (w - rad)), 0.0)
			if lx >= 0.0 and ly >= 0.0 and lx <= w and ly <= w and dx * dx + dy * dy <= rad * rad:
				img.set_pixel(x, y, cb)
	return _finish(key, img)


static func target(a: String, b: String) -> ImageTexture:
	var key := "target" + a + b
	if _cache.has(key):
		return _cache[key]
	var s := 128
	var img := _new(s, Color(a))
	var ca := Color(a)
	var cb := Color(b)
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5 - s / 2.0, y + 0.5 - s / 2.0).length()
			if d <= s / 7.0:
				img.set_pixel(x, y, cb)
			elif d <= 2.0 * s / 7.0:
				img.set_pixel(x, y, ca)
			elif d <= 3.0 * s / 7.0:
				img.set_pixel(x, y, cb)
	return _finish(key, img)


## Dalle fissurée.
static func cracks(base: String) -> ImageTexture:
	var key := "cracks" + base
	if _cache.has(key):
		return _cache[key]
	var s := 256
	var img := _new(s, Color(base))
	var ink := Color(70 / 255.0, 35 / 255.0, 10 / 255.0, 1.0).lerp(Color(base), 0.25)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 5:
		var x := s / 2.0 + (rng.randf() - 0.5) * 60.0
		var y := s / 2.0 + (rng.randf() - 0.5) * 60.0
		var a0 := (k / 5.0) * TAU
		for i in 6:
			var a := a0 + (rng.randf() - 0.5) * 1.2
			var nx := x + cos(a) * 28.0
			var ny := y + sin(a) * 28.0
			for st in 15:
				var f := st / 14.0
				_disc(img, lerpf(x, nx, f), lerpf(y, ny, f), 2.5, ink)
			x = nx
			y = ny
	return _finish(key, img)


static func planks() -> ImageTexture:
	var key := "planks"
	if _cache.has(key):
		return _cache[key]
	var s := 128
	var img := _new(s, Color.WHITE)
	var tones := ["#d99a55", "#c98846", "#e0a660", "#cf9150"]
	var line := Color(90 / 255.0, 50 / 255.0, 15 / 255.0, 0.55)
	for i in 4:
		_rect(img, 0, i * s / 4.0, s, s / 4.0, Color(tones[i]))
		_rect(img, 0, i * s / 4.0, s, 3, line)
		_rect(img, ((i * 53) % 90) + 10, i * s / 4.0, 3, s / 4.0, line)
	var nail := Color(60 / 255.0, 35 / 255.0, 10 / 255.0, 0.6)
	for p in [Vector2(10, 10), Vector2(s - 16, 10), Vector2(10, s - 16), Vector2(s - 16, s - 16)]:
		_disc(img, p.x + 3, p.y + 3, 4, nail)
	return _finish(key, img)


static func stone() -> ImageTexture:
	var key := "stone"
	if _cache.has(key):
		return _cache[key]
	var s := 128
	var img := _new(s, Color("#a9b3bd"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 60:
		var light := rng.randf() < 0.5
		var c := Color(1, 1, 1) if light else Color(50 / 255.0, 60 / 255.0, 70 / 255.0)
		c.a = 0.08 + rng.randf() * 0.15
		_disc(img, rng.randf() * s, rng.randf() * s, 2.0 + rng.randf() * 7.0, c)
	var edge := Color(60 / 255.0, 70 / 255.0, 80 / 255.0, 0.5)
	_rect(img, 0, 0, s, 4, edge)
	_rect(img, 0, s - 4, s, 4, edge)
	_rect(img, 0, 4, 4, s - 8, edge)
	_rect(img, s - 4, 4, 4, s - 8, edge)
	return _finish(key, img)
