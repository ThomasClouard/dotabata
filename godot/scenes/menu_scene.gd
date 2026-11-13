class_name MenuScene
extends LobbyScene
## Décor du menu principal : le terrain du lobby, avec ton personnage en vitrine. Chaque écran du menu a son
## cadrage (`set_shot`) ; la caméra « respire » légèrement. Changer de personnage le fait bondir dans des confettis.

const SPOT := Vector3(0, 0, 6)  # emplacement de la vitrine (devant la pancarte « JEUX »)
## Cadrages : [position de la caméra, point visé], relatifs à la vitrine.
const SHOTS := {
	"titre": [Vector3(-0.2, 1.45, 3.7), Vector3(-1.25, 0.95, 0)],
	"jouer": [Vector3(1.2, 3.4, 10.5), Vector3(-3.6, 1.2, 0)],
	"creer": [Vector3(-2.6, 2.6, 8.0), Vector3(-3.2, 1.0, 0)],
	"personnage": [Vector3(0, 1.35, 3.5), Vector3(0, 0.92, 0)],
	"options": [Vector3(3.2, 2.2, 7.5), Vector3(-2.4, 1.2, 0)],
}

var showcase: Character
var shot := "titre"
var _yaw := 0.0
var _spin := 0.0  # rotation ajoutée à la main (glisser, stick) sur l'écran Personnage
var _y := 0.0
var _vy := 0.0
var _t := 0.0
var _extras: Array = []  # figurants : { chr, mode, phase }, mode = tour | trampoline | danse


func on_enter(c: Main, init_data: Variant) -> void:
	super.on_enter(c, init_data)
	showcase = Character.new(Config.profile["color"], Config.profile["hat"])
	showcase.position = SPOT
	ctx.world.add_child(showcase)
	_yaw = _face_camera()
	# figurants derrière le logo : deux qui font le tour, un sur le trampoline, un qui danse
	var hats: Array = Protocol.HATS.filter(func(h: String) -> bool: return h != Config.profile["hat"])
	hats.shuffle()
	for i in 4:
		var h: String = hats[i]
		var fig := Character.new(Protocol.HAT_COLOR[h], h)
		ctx.world.add_child(fig)
		_extras.append({"chr": fig, "mode": ["tour", "tour", "trampoline", "danse"][i], "phase": i * 2.1})


## Change le personnage de la vitrine : petit bond et confettis.
func show_look(color: int, hat: String) -> void:
	showcase.set_look(color, hat)
	_vy = 5.5
	ctx.particles.burst(SPOT + Vector3(0, 1.2, 0), 26, [color, 0xffd60a, 0xff4d6d, 0x4361ee, 0xffffff], 5.0, 0.11, 1.0, 9.0, 0.9)
	ctx.sfx.boing()


func set_shot(name: String) -> void:
	if SHOTS.has(name):
		shot = name
	if shot != "personnage":
		_spin = 0.0


## Rotation à la main de la vitrine (radians).
func spin(amount: float) -> void:
	_spin += amount


## Position et point visé de la caméra pour le cadrage courant, avec un léger balancement.
func camera_shot() -> Array:
	var s: Array = SHOTS[shot]
	var sway := Vector3(sin(_t * 0.31) * 0.22, sin(_t * 0.47) * 0.1, cos(_t * 0.23) * 0.15)
	if shot == "titre":  # lent travelling latéral sur l'écran titre
		sway.x += sin(_t * 0.12) * 0.9
	return [SPOT + s[0] + sway, SPOT + s[1]]


func _face_camera() -> float:
	var s: Array = SHOTS[shot]
	var p: Vector3 = s[0]
	return atan2(p.x, p.z)


func on_frame(dt: float) -> void:
	super.on_frame(dt)
	_t += dt
	_update_extras(dt)
	# saut de la vitrine (changement de personnage)
	if _y > 0.0 or _vy > 0.0:
		_vy -= 22.0 * dt
		_y = maxf(0.0, _y + _vy * dt)
		if _y == 0.0:
			_vy = 0.0
	var grounded := _y <= 0.0 and _vy <= 0.0
	# orientation : face à la caméra, ou tour lent sur l'écran Personnage (plus la rotation à la main)
	var stick := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	if absf(stick) > 0.2:
		_spin += stick * 3.0 * dt
	var target := _face_camera()
	if shot == "personnage":
		target += sin(_t * 0.6) * 0.5 + _spin
	# aperçu des animations (tests) : --vitrine=marche|course|saut, --vitrine-angle=1.57 (vue de profil)
	var mode := str(Config.args.get("vitrine", ""))
	if mode != "":
		target = _face_camera() + float(Config.args.get("vitrine-angle", "0"))
		if mode == "saut" and grounded and fmod(_t, 1.4) < dt:
			_vy = 8.0
	_yaw = _yaw + atan2(sin(target - _yaw), cos(target - _yaw)) * (1.0 - exp(-6.0 * dt))
	showcase.position = SPOT + Vector3(0, _y, 0)
	showcase.rotation.y = _yaw
	var speed: float = {"marche": 3.0, "course": 7.0}.get(mode, 0.0)
	showcase.update(dt, speed, _vy, grounded, false, false, mode == "" and shot != "personnage" and grounded)


## Les figurants du décor : ils donnent de la vie au menu (aucune physique, trajectoires calculées).
func _update_extras(dt: float) -> void:
	for e: Dictionary in _extras:
		var c: Character = e["chr"]
		var ph: float = _t + e["phase"]
		match e["mode"]:
			"tour":  # petit tour en courant autour d'un point derrière la vitrine
				var dir := 1.0 if e["phase"] < 1.0 else -1.0
				var a := ph * 0.9 * dir
				var center := SPOT + Vector3(-3.5, 0, -5.0) if dir > 0.0 else SPOT + Vector3(3.0, 0, -6.5)
				c.position = center + Vector3(cos(a), 0, sin(a)) * 2.6
				c.rotation.y = atan2(-sin(a) * dir, cos(a) * dir)
				c.update(dt, 5.5, 0.0, true, false)
			"trampoline":  # rebondit sur le trampoline du lobby (en 6, 6)
				var u := fmod(ph, 1.3) / 1.3
				var h := 4.0 * u * (1.0 - u) * 3.2
				c.position = Vector3(6, 0.5 + h, 6)
				c.rotation.y = ph * 0.8
				c.update(dt, 0.0, (1.0 - 2.0 * u) * 9.0, h < 0.05, false)
			"danse":
				c.position = SPOT + Vector3(2.4, 0, -2.5)
				c.rotation.y = -0.4
				c.update(dt, 0.0, 0.0, true, false, false, true)
