class_name Debris
extends Node3D
## Effets physiques purement visuels, simulés par Jolt (le moteur 3D de Godot) : éclats des blocs détruits et
## squelettes qui se désarticulent. Rien n'est synchronisé : chaque client simule les siens, le jeu n'en dépend pas.
## Le décor solide (îles, blocs) est recopié depuis les collisions de la physique maison avec `set_ground`.

const LAYER_GROUND := 1
const LAYER_CHUNK := 2
const LAYER_BONE := 4
const MAX_CHUNKS := 160  # au-delà, les plus anciens éclats disparaissent
const CHUNK_LIFE := 3.5  # secondes avant de rétrécir puis disparaître
const KILL_Y := -30.0  # tombé dans le vide

static var current: Debris = null

var _ground: StaticBody3D
var _chunks: Array = []  # { body, life, size }
var _bodies: Array[RigidBody3D] = []  # tous les corps vivants (éclats et os), pour les réveiller
var _chunk_meshes := {}  # taille → Mesh
var _mat_chunk := PhysicsMaterial.new()
var _mat_bone := PhysicsMaterial.new()


static func enabled() -> bool:
	return Config.physics_fx and current != null and current.is_inside_tree()


func _ready() -> void:
	current = self
	_mat_chunk.friction = 0.9
	_mat_chunk.bounce = 0.15
	_mat_bone.friction = 0.8
	_mat_bone.bounce = 0.35


func _exit_tree() -> void:
	if current == self:
		current = null


## Remplace le décor solide par ces boîtes (Phys.Col : centre, demi-tailles, lacet).
func set_ground(cols: Array) -> void:
	if _ground:
		_ground.queue_free()
	_ground = StaticBody3D.new()
	_ground.collision_layer = LAYER_GROUND
	_ground.collision_mask = 0
	for c: Phys.Col in cols:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(c.hx, c.hy, c.hz) * 2.0
		cs.shape = box
		cs.transform = Transform3D(Basis(Vector3.UP, c.yaw), Vector3(c.cx, c.cy, c.cz))
		_ground.add_child(cs)
	add_child(_ground)
	# un bloc retiré sous un éclat endormi : on réveille tout le monde pour qu'il retombe
	for b in _bodies:
		if is_instance_valid(b):
			b.sleeping = false


## Retire tout (changement de scène).
func clear() -> void:
	for b in _bodies:
		if is_instance_valid(b):
			b.queue_free()
	_bodies.clear()
	_chunks.clear()
	if _ground:
		_ground.queue_free()
		_ground = null


## Un bloc cubique de côté `size` (centre `pos`, orientation `basis`) vole en 2×2×2 éclats, soufflés depuis `from`.
func shatter(pos: Vector3, basis: Basis, size: float, material: Material, from: Vector3, power := 7.0) -> void:
	var half := size * 0.25
	var piece := size * 0.5 * 0.92
	var mesh: Mesh = _chunk_meshes.get(piece)
	if mesh == null:
		mesh = Shapes.rbox(piece, piece, piece, piece * 0.12)
		_chunk_meshes[piece] = mesh
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * piece
	for i in 8:
		var off := basis * Vector3((i & 1) * 2 - 1, ((i >> 1) & 1) * 2 - 1, ((i >> 2) & 1) * 2 - 1) * half
		var b := _body(LAYER_CHUNK, LAYER_GROUND | LAYER_CHUNK, _mat_chunk, 0.4)
		b.transform = Transform3D(basis, pos + off)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		b.add_child(cs)
		Gfx.mesh(mesh, material, 0, 0, 0, b)
		add_child(b)
		var dir := (pos + off - from)
		var d := maxf(0.5, dir.length())
		b.linear_velocity = dir / d * power * clampf(3.0 / d, 0.35, 1.0) + Vector3(randf_range(-1, 1), randf_range(2.0, 4.0), randf_range(-1, 1))
		b.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		_chunks.append({"body": b, "life": CHUNK_LIFE + randf() * 1.0, "size": 1.0})
	while _chunks.size() > MAX_CHUNKS:
		var old: Dictionary = _chunks.pop_front()
		_forget(old["body"])


## Un os : `visual` (une copie hors de l'arbre, à placer en `visual_xf` dans le monde) devient un corps rigide de forme
## `shape`, centrée sur `shape_at` (monde). Renvoie le corps ; l'appelant le rend avec `forget` quand il veut.
func bone(visual: Node3D, visual_xf: Transform3D, shape: Shape3D, shape_at: Transform3D, vel: Vector3, mass := 0.3) -> RigidBody3D:
	var b := _body(LAYER_BONE, LAYER_GROUND, _mat_bone, mass)
	b.transform = shape_at.orthonormalized()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	b.add_child(visual)
	visual.transform = b.transform.affine_inverse() * visual_xf
	add_child(b)
	b.linear_velocity = vel
	b.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	return b


func forget(b: RigidBody3D) -> void:
	_forget(b)


func _forget(b: RigidBody3D) -> void:
	_bodies.erase(b)
	if is_instance_valid(b):
		b.queue_free()


func _body(layer: int, mask: int, mat: PhysicsMaterial, mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.collision_layer = layer
	b.collision_mask = mask
	b.physics_material_override = mat
	b.mass = mass
	b.can_sleep = true
	b.continuous_cd = false
	_bodies.append(b)
	return b


func _physics_process(dt: float) -> void:
	for i in range(_chunks.size() - 1, -1, -1):
		var c: Dictionary = _chunks[i]
		var b: RigidBody3D = c["body"]
		if not is_instance_valid(b):
			_chunks.remove_at(i)
			continue
		c["life"] -= dt
		if c["life"] < 0.5:  # rétrécit avant de disparaître
			var k := maxf(0.01, c["life"] / 0.5)
			for ch in b.get_children():
				if ch is MeshInstance3D:
					(ch as MeshInstance3D).scale = Vector3.ONE * k
		if c["life"] <= 0.0 or b.global_position.y < KILL_Y:
			_chunks.remove_at(i)
			_forget(b)
	for i in range(_bodies.size() - 1, -1, -1):
		var b := _bodies[i]
		if not is_instance_valid(b):
			_bodies.remove_at(i)
		elif b.global_position.y < KILL_Y:
			b.freeze = true
			b.visible = false
