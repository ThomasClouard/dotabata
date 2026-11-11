class_name PodiumScene
extends ClientGame
## Podium final : les trois premiers dansent sous les confettis et les projecteurs.

const STEPS := [[0.0, 2.0, 0xffd60a], [-2.3, 1.4, 0xd5dbe3], [2.3, 0.9, 0xe0915a]]

var ctx: Main
var ranking: Array
var cols: Array = [Phys.Col.box(0, 0, -0.75, 0, 14, 0.75, 14)]
var beams: Array = []
var confetti := 0.0


func _init(p_ranking: Array) -> void:
	ranking = p_ranking


func on_enter(c: Main, _init_data: Variant) -> void:
	ctx = c
	ctx.set_sky(0x6a4cff)
	ctx.set_sea(-9.0, 0xc34bff)
	var s := ctx.world
	var floor_g := Node3D.new()
	Gfx.mesh(Shapes.cylinder(14, 13, 1.5, 64), Gfx.mat(0xff8fab, {"rough": 0.25}), 0, 0, 0, floor_g)
	Gfx.mesh(Shapes.cylinder(9, 9, 0.04, 64), Gfx.mat(0xffb3c6, {"rough": 0.2}), 0, 0.76, 0, floor_g)
	Gfx.mesh(Shapes.torus(13.6, 0.22, 64, 10), Gfx.mat(0xffd60a, {"glow": 0.6}), 0, 0.7, 0, floor_g)
	LobbyScene.place(s, floor_g, cols[0])
	for i in 3:
		var x: float = STEPS[i][0]
		var h: float = STEPS[i][1]
		Gfx.mesh(Shapes.cylinder(1.05, 1.15, h, 32), Gfx.mat(STEPS[i][2], {"rough": 0.22, "metal": 0.35 if i == 0 else 0.2}), x, h / 2.0, 0, s)
		var n := Gfx.board(str(i + 1), 0.9, 0.9, "#2b2140", "#ffffff", 0.036)
		n.position = Vector3(x, h * 0.55, 1.16)
		s.add_child(n)
	# projecteurs
	var lights := [0xfff3b0, 0x9bf6ff, 0xffadad]
	for i in 3:
		var beam := Gfx.mesh(Shapes.cylinder(0.0, 2.4, 16, 24, false), Gfx.flat(lights[i], {"opacity": 0.06, "double": true, "add": true}), STEPS[i][0], 8.0 + STEPS[i][1], 0, s, false)
		beams.append(beam)
	for i in 10:
		var b := Gfx.balloon(LobbyScene.PARTY[i % LobbyScene.PARTY.size()])
		var a := (i / 10.0) * TAU
		b.position = Vector3(sin(a) * 12.0, 3.0 + (i % 3) * 1.5, cos(a) * 12.0)
		s.add_child(b)
	for i in ranking.size():
		var p: ClientPlayer = ctx.players.get(ranking[i])
		if p == null:
			continue
		p.chr.reset_damage()
		if i < 3:
			p.pin = {"p": Vector3(STEPS[i][0], STEPS[i][1], 0), "yaw": 0.0, "dance": true}
		else:
			var a := ((i - 3.0) / maxf(1.0, ranking.size() - 3.0) - 0.5) * 2.2
			p.pin = {"p": Vector3(sin(a) * 6.0, 0, 3.5 + cos(a) * 1.5), "yaw": PI + a, "dance": false}
	ctx.set_active(false)
	ctx.set_spectate(Vector3(0, 1.8, 0), 9.0)
	ctx.cam_yaw = PI
	ctx.sfx.win()


func on_frame(dt: float) -> void:
	var t := ctx.now()
	for i in beams.size():
		beams[i].rotation = Vector3(cos(t * 0.9 + i) * 0.08, 0, sin(t * 1.1 + i * 2.0) * 0.12)
	confetti -= dt
	if confetti < 0.0:
		confetti = 0.05
		for i in 3:
			ctx.particles.emit((randf() - 0.5) * 12.0, 8.0 + randf() * 2.0, (randf() - 0.5) * 8.0, (randf() - 0.5) * 2.0, -1.0, (randf() - 0.5) * 2.0, LobbyScene.PARTY.pick_random(), 0.16, 4.0, 2.5)


func on_exit() -> void:
	for p: ClientPlayer in ctx.players.values():
		p.pin = null
	ctx.set_active(true)
	ctx.set_spectate(null)


func colliders(_t: float) -> Array:
	return cols
