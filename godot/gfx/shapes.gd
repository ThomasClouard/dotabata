class_name Shapes
extends RefCounted
## Générateurs de maillages procéduraux absents des primitives de Godot :
## boîte arrondie, icosphère, portions de sphère, de tore et de cylindre.

static var _cache := {}


## Assemble un ArrayMesh. L'ordre des sommets de chaque triangle est corrigé d'après les normales :
## les générateurs n'ont pas à se soucier du sens (Godot attend des faces avant horaires).
static func build(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array, xf := Transform3D.IDENTITY, with_uv2 := false) -> ArrayMesh:
	var out := PackedInt32Array()
	out.resize(idx.size())
	for i in range(0, idx.size(), 3):
		var a := idx[i]
		var b := idx[i + 1]
		var c := idx[i + 2]
		var g := (v[b] - v[a]).cross(v[c] - v[a])
		if g.dot(n[a] + n[b] + n[c]) > 0.0:
			out[i] = a
			out[i + 1] = c
			out[i + 2] = b
		else:
			out[i] = a
			out[i + 1] = b
			out[i + 2] = c
	if xf != Transform3D.IDENTITY:
		for i in v.size():
			v[i] = xf * v[i]
			n[i] = (xf.basis * n[i]).normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	if uv.size() == v.size():
		arrays[Mesh.ARRAY_TEX_UV] = uv
	if with_uv2:
		var uv2 := PackedVector2Array()
		uv2.resize(v.size())
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = out
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _samples(hh: float, r: float) -> Array:
	var e := hh - r
	var k := r * 0.41421356
	return [-hh, -e - k, -e, e, e + k, hh]


## Boîte aux arêtes arrondies (w × h × d), UV de 0 à 1 sur chaque face.
static func rbox(w: float, h: float, d: float, r := 0.18) -> ArrayMesh:
	r = maxf(0.01, minf(minf(r, w / 2.0 - 0.005), minf(h / 2.0 - 0.005, d / 2.0 - 0.005)))
	var key := "rb|%.3f|%.3f|%.3f|%.3f" % [w, h, d, r]
	if _cache.has(key):
		return _cache[key]
	var half := Vector3(w, h, d) / 2.0
	var inner := half - Vector3(r, r, r)
	var sm := [_samples(half.x, r), _samples(half.y, r), _samples(half.z, r)]
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for axis in 3:
		var ua := (axis + 1) % 3
		var va := (axis + 2) % 3
		var su: Array = sm[ua]
		var sv: Array = sm[va]
		for sgn in [-1.0, 1.0]:
			var base := v.size()
			for i in su.size():
				for j in sv.size():
					var p := Vector3.ZERO
					p[axis] = sgn * half[axis]
					p[ua] = su[i]
					p[va] = sv[j]
					var q := p.clamp(-inner, inner)
					var nn := (p - q).normalized()
					v.append(q + nn * r)
					n.append(nn)
					var fx := (p.x + half.x) / w
					var fy := 1.0 - (p.y + half.y) / h
					var fz := (p.z + half.z) / d
					if axis == 0:
						uv.append(Vector2(fz, fy))
					elif axis == 1:
						uv.append(Vector2(fx, fz))
					else:
						uv.append(Vector2(fx, fy))
			var cols := sv.size()
			for i in su.size() - 1:
				for j in cols - 1:
					var a := base + i * cols + j
					idx.append_array([a, a + 1, a + cols + 1, a, a + cols + 1, a + cols])
	var m := build(v, n, uv, idx)
	_cache[key] = m
	return m


## Sphère lisse à facettes régulières (subdivision d'un icosaèdre).
static func icosphere(radius: float, level: int) -> ArrayMesh:
	var key := "ico|%.3f|%d" % [radius, level]
	if _cache.has(key):
		return _cache[key]
	var data := icosphere_data(level)
	var v: PackedVector3Array = data[0]
	var n := v.duplicate()
	for i in v.size():
		v[i] *= radius
	var m := build(v, n, PackedVector2Array(), data[1])
	_cache[key] = m
	return m


## Sommets unitaires (soudés) et index d'une icosphère.
static func icosphere_data(level: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in v.size():
		v[i] = v[i].normalized()
	var idx := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for _l in level:
		var mid := {}
		var next := PackedInt32Array()
		for i in range(0, idx.size(), 3):
			var a := idx[i]
			var b := idx[i + 1]
			var c := idx[i + 2]
			var ab := _midpoint(v, mid, a, b)
			var bc := _midpoint(v, mid, b, c)
			var ca := _midpoint(v, mid, c, a)
			next.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		idx = next
	return [v, idx]


static func _midpoint(v: PackedVector3Array, mid: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if mid.has(key):
		return mid[key]
	v.append(((v[a] + v[b]) * 0.5).normalized())
	mid[key] = v.size() - 1
	return v.size() - 1


## Portion de sphère (mêmes paramètres que THREE.SphereGeometry).
static func sphere_part(radius: float, wseg: int, hseg: int, phi0 := 0.0, phi_len := TAU, theta0 := 0.0, theta_len := PI, with_uv2 := false) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for iy in hseg + 1:
		var tv := float(iy) / hseg
		var theta := theta0 + tv * theta_len
		for ix in wseg + 1:
			var tu := float(ix) / wseg
			var phi := phi0 + tu * phi_len
			var d := Vector3(-cos(phi) * sin(theta), cos(theta), sin(phi) * sin(theta))
			v.append(d * radius)
			n.append(d)
			uv.append(Vector2(tu, tv))
	var row := wseg + 1
	for iy in hseg:
		for ix in wseg:
			var a := iy * row + ix + 1
			var b := iy * row + ix
			var c := (iy + 1) * row + ix
			var d2 := (iy + 1) * row + ix + 1
			idx.append_array([a, b, d2, b, c, d2])
	return build(v, n, uv, idx, Transform3D.IDENTITY, with_uv2)


## Arc de tore dans le plan XY (mêmes paramètres que THREE.TorusGeometry).
static func torus_arc(radius: float, tube: float, radial_seg: int, tubular_seg: int, arc := TAU, xf := Transform3D.IDENTITY) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in radial_seg + 1:
		for i in tubular_seg + 1:
			var u := float(i) / tubular_seg * arc
			var w := float(j) / radial_seg * TAU
			var center := Vector3(radius * cos(u), radius * sin(u), 0.0)
			var p := Vector3((radius + tube * cos(w)) * cos(u), (radius + tube * cos(w)) * sin(u), tube * sin(w))
			v.append(p)
			n.append((p - center).normalized())
			uv.append(Vector2(float(i) / tubular_seg, float(j) / radial_seg))
	var row := tubular_seg + 1
	for j in range(1, radial_seg + 1):
		for i in range(1, tubular_seg + 1):
			var a := row * j + i - 1
			var b := row * (j - 1) + i - 1
			var c := row * (j - 1) + i
			var d := row * j + i
			idx.append_array([a, b, d, b, c, d])
	return build(v, n, uv, idx, xf)


## Portion de cylindre fermée par deux disques (mêmes paramètres que THREE.CylinderGeometry).
static func cyl_part(r_top: float, r_bottom: float, height: float, seg: int, theta0 := 0.0, theta_len := TAU) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var slope := (r_bottom - r_top) / height
	for iy in 2:
		var y := height / 2.0 if iy == 0 else -height / 2.0
		var r := r_top if iy == 0 else r_bottom
		for ix in seg + 1:
			var th := theta0 + float(ix) / seg * theta_len
			v.append(Vector3(r * sin(th), y, r * cos(th)))
			n.append(Vector3(sin(th), slope, cos(th)).normalized())
			uv.append(Vector2(float(ix) / seg, float(iy)))
	for ix in seg:
		idx.append_array([ix, seg + 1 + ix, ix + 1, seg + 1 + ix, seg + 2 + ix, ix + 1])
	for cap in 2:
		var y := height / 2.0 if cap == 0 else -height / 2.0
		var r := r_top if cap == 0 else r_bottom
		var nn := Vector3.UP if cap == 0 else Vector3.DOWN
		var center := v.size()
		v.append(Vector3(0, y, 0))
		n.append(nn)
		uv.append(Vector2(0.5, 0.5))
		for ix in seg + 1:
			var th := theta0 + float(ix) / seg * theta_len
			v.append(Vector3(r * sin(th), y, r * cos(th)))
			n.append(nn)
			uv.append(Vector2(0.5 + 0.5 * cos(th), 0.5 + 0.5 * sin(th)))
		for ix in seg:
			idx.append_array([center, center + 1 + ix, center + 2 + ix])
	return build(v, n, uv, idx)


## Anneau plat horizontal (THREE.RingGeometry couché), visible des deux côtés via le matériau.
static func ring(r_in: float, r_out: float, seg: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in seg + 1:
		var a := float(i) / seg * TAU
		v.append(Vector3(cos(a) * r_in, 0, sin(a) * r_in))
		v.append(Vector3(cos(a) * r_out, 0, sin(a) * r_out))
		n.append(Vector3.UP)
		n.append(Vector3.UP)
	for i in seg:
		var a := i * 2
		idx.append_array([a, a + 1, a + 3, a, a + 3, a + 2])
	return build(v, n, PackedVector2Array(), idx)


static func sphere(radius: float, radial := 24, rings := 14) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = radial
	m.rings = rings
	return m


static func cylinder(r_top: float, r_bottom: float, height: float, seg := 16, caps := true) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = height
	m.radial_segments = seg
	m.rings = 1
	m.cap_top = caps
	m.cap_bottom = caps
	return m


## Capsule dont `length` est la longueur de la partie droite (convention three.js).
static func capsule(radius: float, length: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = length + radius * 2.0
	m.radial_segments = 16
	m.rings = 6
	return m


## Tore complet à plat (plan XZ).
static func torus(radius: float, tube: float, rings := 40, ring_seg := 12) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = radius - tube
	m.outer_radius = radius + tube
	m.rings = rings
	m.ring_segments = ring_seg
	return m


static func box(w := 1.0, h := 1.0, d := 1.0) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(w, h, d)
	return m
