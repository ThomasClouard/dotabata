class_name Particles
extends MultiMeshInstance3D
## Particules légères : un seul MultiMesh de petites boules (confettis, débris, fumée, étincelles).

const CAP := 700

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _max := PackedFloat32Array()
var _size := PackedFloat32Array()
var _grav := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _next := 0
var _alive := 0
var _zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)


func _ready() -> void:
	_pos.resize(CAP)
	_vel.resize(CAP)
	_life.resize(CAP)
	_max.resize(CAP)
	_size.resize(CAP)
	_grav.resize(CAP)
	_spin.resize(CAP)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Shapes.icosphere(0.62, 1)
	mm.instance_count = CAP
	for i in CAP:
		mm.set_instance_transform(i, _zero)
		mm.set_instance_color(i, Color.WHITE)
	multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 1500, 4000))


func emit(x: float, y: float, z: float, vx: float, vy: float, vz: float, color: int, size := 0.12, life := 0.8, gravity := 12.0) -> void:
	var i := _next
	_next = (_next + 1) % CAP
	if _life[i] <= 0.0:
		_alive += 1
	_pos[i] = Vector3(x, y, z)
	_vel[i] = Vector3(vx, vy, vz)
	_life[i] = life
	_max[i] = life
	_size[i] = size
	_grav[i] = gravity
	_spin[i] = randf() * 10.0
	multimesh.set_instance_color(i, Gfx.col(color))


## Gerbe de particules dans toutes les directions.
func burst(p: Vector3, n: int, colors: Array, speed := 6.0, size := 0.14, life := 0.9, gravity := 14.0, up := 0.5) -> void:
	for i in n:
		var a := randf() * TAU
		var e := randf() * 2.0 - 1.0 + up
		var s := speed * (0.3 + randf() * 0.7)
		var h := sqrt(maxf(0.0, 1.0 - minf(1.0, e * e)))
		emit(p.x, p.y, p.z, cos(a) * h * s, e * s, sin(a) * h * s, colors[i % colors.size()], size * (0.6 + randf() * 0.8), life * (0.6 + randf() * 0.6), gravity)


func update(dt: float) -> void:
	if _alive <= 0:
		return
	var mm := multimesh
	for i in CAP:
		if _life[i] <= 0.0:
			continue
		_life[i] -= dt
		if _life[i] <= 0.0:
			_alive -= 1
			mm.set_instance_transform(i, _zero)
			continue
		var v := _vel[i]
		v.y -= _grav[i] * dt
		_vel[i] = v
		var p := _pos[i] + v * dt
		_pos[i] = p
		var sc := _size[i] * minf(1.0, (_life[i] / _max[i]) * 2.5)
		var b := Basis.from_euler(Vector3(_spin[i] + _life[i] * 6.0, _spin[i] * 2.0 + _life[i] * 4.0, 0.0)).scaled(Vector3(sc, sc, sc))
		mm.set_instance_transform(i, Transform3D(b, p))
