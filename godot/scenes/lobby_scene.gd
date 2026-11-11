class_name LobbyScene
extends ClientGame
## Lobby : un terrain de jeu où l'on court et saute en attendant que l'hôte lance la partie.

const PARTY := [0xff4d6d, 0xffd60a, 0x70e000, 0x00b4d8, 0x9d4edd, 0xff9f1c]

var ctx: Main
var cols: Array = []
var bar: Node3D
var balloons: Array = []
var balloon_y: Array = []


func _init() -> void:
	cols = [
		Phys.Col.box(0, 0, -0.75, 0, 16, 0.75, 16),
		Phys.Col.box(1, 6, 0.25, 6, 1.5, 0.25, 1.5),
		Phys.Col.box(2, -6, 0.5, 5, 1.5, 0.5, 1.5, 0.4),
		Phys.Col.box(3, -8.5, 1, 7.5, 1.5, 1, 1.5, 0.4),
		Phys.Col.box(4, -11, 1.5, 10, 1.5, 1.5, 1.5, 0.4),
		Phys.Col.box(5, 7, 0.45, -7, 3, 0.3, 0.3),
	]
	cols[1].bounce = 15.0
	cols[5].ang_vel = 1.4
	# troncs des arbres aux quatre coins
	var trunks := [[-13.0, -13.0], [13.0, -13.0], [-13.5, 13.5], [13.0, 12.0]]
	for i in 4:
		cols.append(Phys.Col.box(10 + i, trunks[i][0], 1, trunks[i][1], 0.3, 1, 0.3))


## Pose un décor à l'emplacement exact d'une boîte de collision.
static func place(scene: Node3D, o: Node3D, c: Phys.Col) -> Node3D:
	o.position = Vector3(c.cx, c.cy, c.cz)
	o.rotation.y = c.yaw
	scene.add_child(o)
	return o


func on_enter(c: Main, _init_data: Variant) -> void:
	ctx = c
	ctx.set_sky(0x7cc8ff)
	ctx.set_sea(-9.0, 0x1fb6e0)
	var s := ctx.world
	place(s, Gfx.slab(32, 1.5, 32, 0x7ddc6a, {"top": 0xffffff, "top_map": Tex.soft("#8fe07a", "#a8ec8c"), "top_uv": Vector2(4, 4)}), cols[0])

	# trampoline : socle + toile cible
	var tr := place(s, Node3D.new(), cols[1])
	Gfx.mesh(Shapes.rbox(3, 0.5, 3, 0.2), Gfx.mat(0x4361ee), 0, 0, 0, tr)
	Gfx.mesh(Shapes.cylinder(1.25, 1.25, 0.06, 32), Gfx.mat(0xffffff, {"map": Tex.target("#ffd60a", "#ff4d6d")}), 0, 0.27, 0, tr)

	# marches de couleurs
	var steps := [0xffc971, 0xff8fab, 0xcdb4db]
	for i in 3:
		var col: Phys.Col = cols[2 + i]
		place(s, Gfx.slab(col.hx * 2.0, col.hy * 2.0, col.hz * 2.0, steps[i], {"under": false}), col)

	# barre tournante rembourrée sur son axe
	bar = place(s, Node3D.new(), cols[5])
	var pad := Gfx.mesh(Shapes.capsule(0.3, 5.4), Gfx.mat(0xffffff, {"map": Tex.stripes("#ff4d6d", "#ffffff"), "uv": Vector2(1, 6)}), 0, 0, 0, bar)
	pad.rotation.z = PI / 2.0
	Gfx.mesh(Shapes.cylinder(0.28, 0.4, 0.5, 16), Gfx.mat(0x495057, {"metal": 0.6, "rough": 0.3}), 7, 0.2, -7, s)

	# arbres, pancarte et ballons
	for i in 4:
		var t := Gfx.tree(3.2 + (i % 2) * 0.8, 0x52d681 if i % 2 else 0x3bc47a)
		t.position = Vector3(cols[6 + i].cx, 0, cols[6 + i].cz)
		s.add_child(t)
	var board := Gfx.board("JEUX", 7, 2.2, "#ff4d6d", "#ffd60a")
	board.position = Vector3(0, 4, -14.5)
	s.add_child(board)
	for x in [-3.0, 3.0]:
		Gfx.mesh(Shapes.cylinder(0.14, 0.14, 4, 10), Gfx.mat(0xffffff), x, 2, -14.6, s)
	for i in 12:
		var b := Gfx.balloon(PARTY[i % PARTY.size()])
		var a := (i / 12.0) * TAU
		var r := 19.0 + (i % 3) * 3.0
		b.position = Vector3(sin(a) * r, 4.0 + (i % 4) * 2.2, cos(a) * r)
		s.add_child(b)
		balloons.append(b)
		balloon_y.append(b.position.y)
	for x in [-2.6, 2.6]:
		var b := Gfx.balloon(0xffd60a if x < 0.0 else 0x00b4d8)
		b.position = Vector3(x * 1.45, 6.6, -14.5)
		s.add_child(b)
		balloons.append(b)
		balloon_y.append(6.6)


func on_frame(_dt: float) -> void:
	var t := ctx.now()
	cols[5].yaw = t * 1.4
	bar.rotation.y = cols[5].yaw
	for i in balloons.size():
		balloons[i].position.y = balloon_y[i] + sin(t * 0.8 + i) * 0.4
		balloons[i].rotation.z = sin(t * 0.6 + i * 2.0) * 0.12
	if ctx.body.py < -9.0:
		ctx.body.set_pos(0, 3, 0)
		ctx.body.vx = 0.0
		ctx.body.vy = 0.0
		ctx.body.vz = 0.0


func colliders(_t: float) -> Array:
	return cols
