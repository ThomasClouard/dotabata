class_name Phys
extends RefCounted
## Physique maison, portée à l'identique de shared/src/physics.ts :
## une capsule verticale contre des boîtes orientées (lacet seul).
## Tout est calculé en float 64 bits (pas de Vector3) pour rester aligné sur les clients navigateur.

const GRAVITY := 24.0
const SPEED := 7.0
const JUMP_V := 9.0
const RADIUS := 0.4
const HEIGHT := 1.5
const ACCEL_GROUND := 60.0
const ACCEL_AIR := 20.0
const ACCEL_ICE := 5.0
const MAX_FALL := 45.0
const COYOTE := 0.12
# —— vague 2 ——
const JELLY_IMPACT := 5.0  # vitesse d'impact au-delà de laquelle la gélatine fait rebondir
const JELLY_MIN := 4.0  # rebond minimal sur la gélatine
const BOOST_TIME := 0.6  # secondes d'adhérence réduite après un speed pad
const SLIDE_MAX := 20.0  # vitesse au-delà de laquelle un toboggan n'accélère plus
const ZIP_HOP := 4.0  # vitesse verticale ajoutée en lâchant une tyrolienne par un saut
const ZIP_COOL := 0.5  # secondes avant de pouvoir se raccrocher / être re-téléporté
const ZIP_HANG := 1.9  # les pieds pendent à cette distance sous le câble
const ZIP_GRAB := 1.2
# —— vague 3 ——
const SUPER_JUMP := 1.4  # facteur de la vitesse de saut sous l'effet « super saut »
const JOSTLE_TRIP := 6.0  # vitesse à laquelle un autre joueur doit nous foncer dessus pour nous faire trébucher
const TRIP_TUMBLE := 0.7  # durée du petit roulé-boulé d'une bousculade  # rayon d'accrochage autour du départ du câble (depuis les mains = pieds + ZIP_HANG)


## Boîte orientée. Convention : monde = Ry(yaw) · local.
class Col extends RefCounted:
	var id := 0
	var tag := ""
	var cx := 0.0
	var cy := 0.0
	var cz := 0.0
	var hx := 0.0
	var hy := 0.0
	var hz := 0.0
	var yaw := 0.0
	var vx := 0.0  # vitesse de la surface
	var vy := 0.0
	var vz := 0.0
	var ang_vel := 0.0
	var ice := false
	var bounce := 0.0
	var has_conv := false
	var conv_x := 0.0
	var conv_z := 0.0
	# —— vague 2 (0 / false = absent : comportement d'origine) ——
	var slow := 0.0  # facteur de vitesse max debout dessus (boue)
	var jump := 0.0  # facteur de saut depuis cette surface (boue, gélatine)
	var jelly := 0.0  # restitution des atterrissages (gélatine)
	var slope := 0.0  # rampe : montée par m le long de z local (dalle cisaillée)
	var slide := false  # toboggan
	var has_boost := false  # speed pad : vitesse horizontale imposée
	var boost_x := 0.0
	var boost_z := 0.0
	var has_launch := false  # trampoline directionnel : vitesse imposée (monde)
	var launch_x := 0.0
	var launch_y := 0.0
	var launch_z := 0.0

	static func box(p_id: int, x: float, y: float, z: float, p_hx: float, p_hy: float, p_hz: float, p_yaw := 0.0, p_tag := "") -> Col:
		var c := Col.new()
		c.id = p_id
		c.cx = x
		c.cy = y
		c.cz = z
		c.hx = p_hx
		c.hy = p_hy
		c.hz = p_hz
		c.yaw = p_yaw
		c.tag = p_tag
		return c


class Body extends RefCounted:
	var px := 0.0  # position des pieds
	var py := 0.0
	var pz := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var grounded := false
	var ground_id := -1
	var gvx := 0.0
	var gvy := 0.0
	var gvz := 0.0
	var on_ice := false
	var coyote := 0.0
	var tumble := 0.0  # secondes de roulé-boulé restantes
	var jumped := false
	var landed := 0.0
	# —— vague 2 ——
	var slow := 1.0  # facteur de vitesse max du sol actuel
	var jump_k := 1.0  # facteur de saut du sol actuel
	var boost := 0.0  # secondes d'adhérence réduite (speed pad)
	var flight := 0.0  # secondes de vol balistique sans contrôle (canon, trampoline directionnel)
	var zip := -1  # index de la tyrolienne tenue, -1 sinon
	var zip_s := 0.0  # distance parcourue le long du câble
	var cool := 0.0  # secondes avant de pouvoir reprendre une tyrolienne / un téléporteur
	# —— vague 3 (non remis à zéro par clear_motion_state : les effets survivent à une chute) ——
	var super_jump := 0.0  # secondes de super saut restantes
	var shield := 0.0  # secondes de bouclier restantes

	func set_pos(x: float, y: float, z: float) -> void:
		px = x
		py = y
		pz = z

	func pos() -> Vector3:
		return Vector3(px, py, pz)


class Contact extends RefCounted:
	var id := 0
	var tag := ""
	var nx := 0.0
	var ny := 0.0
	var nz := 0.0
	var cvx := 0.0  # vitesse du collider au point de contact
	var cvy := 0.0
	var cvz := 0.0
	var ground := false
	var bounced := false


static func jump_height(v0 := JUMP_V, g := GRAVITY) -> float:
	return (v0 * v0) / (2.0 * g)


## Annule les états temporaires (tyrolienne, vol, élan, sol spécial) : à chaque réapparition.
static func clear_motion_state(b: Body) -> void:
	b.zip = -1
	b.zip_s = 0.0
	b.flight = 0.0
	b.boost = 0.0
	b.cool = 0.0
	b.slow = 1.0
	b.jump_k = 1.0


# normale monde du dernier contact résolu
static var _nx := 0.0
static var _ny := 0.0
static var _nz := 0.0


## Sort la capsule de la boîte ; vrai s'il y a contact (normale dans _nx, _ny, _nz).
static func _resolve(b: Body, c: Col) -> bool:
	var r := RADIUS
	var co := cos(c.yaw)
	var si := sin(c.yaw)
	var dx := b.px - c.cx
	var dz := b.pz - c.cz
	var reach := sqrt(c.hx * c.hx + c.hz * c.hz) + r
	if dx * dx + dz * dz > reach * reach:
		return false
	var lx := dx * co - dz * si
	var lz := dx * si + dz * co
	var a := b.py + r
	var top := b.py + HEIGHT - r
	var ymin := c.cy - c.hy
	var ymax := c.cy + c.hy
	var qx := maxf(-c.hx, minf(c.hx, lx))
	var qz := maxf(-c.hz, minf(c.hz, lz))
	if c.slope != 0.0:
		# rampe : dalle cisaillée, tranche verticale au point le plus proche (z local borné)
		var sh := c.slope * qz
		ymin += sh
		ymax += sh
	var dy := 0.0
	if top < ymin:
		dy = top - ymin
	elif a > ymax:
		dy = a - ymax
	var ex := lx - qx
	var ez := lz - qz
	var d2 := ex * ex + dy * dy + ez * ez
	if d2 >= r * r:
		return false
	var nx := 0.0
	var ny := 0.0
	var nz := 0.0
	var pen := 0.0
	if d2 > 1e-10:
		var d := sqrt(d2)
		nx = ex / d
		ny = dy / d
		nz = ez / d
		pen = r - d
	else:
		# axe de la capsule à l'intérieur de la boîte : sortie par la face la plus proche
		var ppx := c.hx - absf(lx) + r
		var ppz := c.hz - absf(lz) + r
		var pu := ymax - b.py
		var pd := b.py + HEIGHT - ymin
		pen = minf(minf(ppx, ppz), minf(pu, pd))
		if pen == pu:
			ny = 1.0
		elif pen == ppx:
			nx = 1.0 if lx >= 0.0 else -1.0
		elif pen == ppz:
			nz = 1.0 if lz >= 0.0 else -1.0
		else:
			ny = -1.0
	var wx := nx * co + nz * si
	var wz := -nx * si + nz * co
	b.px += wx * pen
	b.py += ny * pen
	b.pz += wz * pen
	_nx = wx
	_ny = ny
	_nz = wz
	return true


## Avance le personnage d'un pas `dt` et renvoie les contacts rencontrés.
static func step_body(b: Body, mx: float, mz: float, jump: bool, cols: Array, dt: float) -> Array:
	b.jumped = false
	b.landed = 0.0
	if b.zip >= 0:
		# suspendu à une tyrolienne : la pré-étape a placé le corps sur le câble ; sauter = lâcher
		if not jump:
			b.grounded = false
			b.on_ice = false
			b.coyote = 0.0
			b.ground_id = -1
			b.gvx = 0.0
			b.gvy = 0.0
			b.gvz = 0.0
			b.boost = 0.0
			b.flight = 0.0
			b.tumble = maxf(0.0, b.tumble - dt)
			if b.super_jump > 0.0:
				b.super_jump = maxf(0.0, b.super_jump - dt)
			if b.shield > 0.0:
				b.shield = maxf(0.0, b.shield - dt)
			return []
		b.zip = -1
		b.cool = ZIP_COOL
		b.vy = maxf(b.vy, 0.0) + ZIP_HOP
		b.jumped = true
	var ctrl := 0.15 if b.tumble > 0.0 else 1.0
	var base_acc := ACCEL_AIR
	if b.flight > 0.0:
		base_acc = 0.0  # vol de canon : aucun contrôle
	elif b.boost > 0.0:
		base_acc = ACCEL_ICE  # après un speed pad : adhérence de glace
	elif b.grounded:
		base_acc = ACCEL_ICE if b.on_ice else ACCEL_GROUND
	var acc := base_acc * ctrl * dt
	var dx := mx * SPEED * b.slow + b.gvx - b.vx
	var dz := mz * SPEED * b.slow + b.gvz - b.vz
	var d := sqrt(dx * dx + dz * dz)
	if d > acc:
		dx *= acc / d
		dz *= acc / d
	b.vx += dx
	b.vz += dz

	if jump and b.coyote > 0.0 and b.tumble <= 0.0:
		var jv := JUMP_V * b.jump_k
		if b.super_jump > 0.0:
			jv *= SUPER_JUMP
		b.vy = jv + maxf(0.0, b.gvy)
		b.coyote = 0.0
		b.grounded = false
		b.jumped = true
	b.vy = maxf(-MAX_FALL, b.vy - GRAVITY * dt)
	b.px += b.vx * dt
	b.py += b.vy * dt
	b.pz += b.vz * dt

	var was_grounded := b.grounded
	b.grounded = false
	b.on_ice = false
	b.slow = 1.0
	b.jump_k = 1.0
	var pad_now := false  # trampoline directionnel touché pendant ce pas
	var gx := 0.0
	var gy := 0.0
	var gz := 0.0
	var contacts: Array = []
	for c: Col in cols:
		if not _resolve(b, c):
			continue
		var nx := _nx
		var ny := _ny
		var nz := _nz
		var cvx := c.vx
		var cvy := c.vy
		var cvz := c.vz
		if c.ang_vel != 0.0:
			cvx += c.ang_vel * (b.pz - c.cz)
			cvz -= c.ang_vel * (b.px - c.cx)
		var ground := ny > 0.6
		var bounced := false
		if ground:
			if c.has_launch and b.vy < 2.0:
				# trampoline directionnel : vitesse imposée, vol sans contrôle jusqu'au prochain contact (au plus 2·vy/g)
				b.vx = c.launch_x
				b.vy = c.launch_y
				b.vz = c.launch_z
				b.coyote = 0.0
				b.flight = (2.0 * c.launch_y) / GRAVITY
				pad_now = true
				bounced = true
			elif c.bounce != 0.0 and b.vy < 2.0:
				b.vy = c.bounce
				b.coyote = 0.0
				bounced = true
			else:
				# rampe : le sol monte / descend à la vitesse que la pente impose à notre vitesse horizontale
				var sy := cvy
				if c.slope != 0.0:
					sy += c.slope * ((b.vx - cvx) * sin(c.yaw) + (b.vz - cvz) * cos(c.yaw))
				if b.vy <= sy + 0.01:
					if c.jelly != 0.0 and b.vy - sy < -JELLY_IMPACT:
						# gélatine : rebond amorti, jamais sous JELLY_MIN
						b.vy = sy + maxf(JELLY_MIN, (sy - b.vy) * c.jelly)
						b.coyote = 0.0
						bounced = true
					else:
						if not was_grounded and b.vy < -6.0:
							b.landed = -b.vy
						b.vy = sy
						b.grounded = true
						b.ground_id = c.id
						b.on_ice = c.ice or c.slide
						if c.has_conv:
							cvx += c.conv_x
							cvz += c.conv_z
						gx = cvx
						gy = cvy
						gz = cvz
						if c.slow != 0.0:
							b.slow = c.slow
						if c.jump != 0.0:
							b.jump_k = c.jump
						if c.has_boost:
							b.vx = c.boost_x
							b.vz = c.boost_z
							b.boost = BOOST_TIME
						if c.slide and c.slope != 0.0:
							# toboggan : accélération g·s/(1+s²) vers le bas de la pente, jusqu'à SLIDE_MAX
							var sn := sin(c.yaw)
							var cs := cos(c.yaw)
							if -(b.vx * sn + b.vz * cs) * signf(c.slope) < SLIDE_MAX:
								var k := ((GRAVITY * c.slope) / (1.0 + c.slope * c.slope)) * dt
								b.vx -= sn * k
								b.vz -= cs * k
		else:
			var vn := (b.vx - cvx) * nx + (b.vy - cvy) * ny + (b.vz - cvz) * nz
			if vn < 0.0:
				b.vx -= nx * vn
				b.vy -= ny * vn
				b.vz -= nz * vn
		var ct := Contact.new()
		ct.id = c.id
		ct.tag = c.tag
		ct.nx = nx
		ct.ny = ny
		ct.nz = nz
		ct.cvx = cvx
		ct.cvy = cvy
		ct.cvz = cvz
		ct.ground = ground
		ct.bounced = bounced
		contacts.append(ct)
	if b.grounded:
		b.coyote = COYOTE
		b.gvx = gx
		b.gvy = gy
		b.gvz = gz
	else:
		b.coyote -= dt
		if b.coyote <= 0.0:
			b.gvx = 0.0
			b.gvy = 0.0
			b.gvz = 0.0
			b.ground_id = -1
	b.tumble = maxf(0.0, b.tumble - dt)
	b.boost = maxf(0.0, b.boost - dt)
	b.cool = maxf(0.0, b.cool - dt)
	if b.super_jump > 0.0:
		b.super_jump = maxf(0.0, b.super_jump - dt)
	if b.shield > 0.0:
		b.shield = maxf(0.0, b.shield - dt)
	# le vol s'arrête au premier contact (sauf celui du trampoline directionnel qui vient de le lancer)
	if b.flight > 0.0 and not pad_now:
		b.flight = 0.0 if not contacts.is_empty() else maxf(0.0, b.flight - dt)
	return contacts


## Hauteur du sol sous un point (ombres « blob »). -INF s'il n'y a rien.
static func ground_below(x: float, y: float, z: float, cols: Array) -> float:
	var best := -INF
	for c: Col in cols:
		var co := cos(c.yaw)
		var si := sin(c.yaw)
		var dx := x - c.cx
		var dz := z - c.cz
		var lx := dx * co - dz * si
		var lz := dx * si + dz * co
		var top := c.cy + c.hy
		if c.slope != 0.0:
			top += c.slope * lz  # rampe : hauteur du plan incliné au point
		if top > y + 0.6 or top <= best:
			continue
		if absf(lx) <= c.hx and absf(lz) <= c.hz:
			best = top
	return best


## Bousculade entre deux personnages : repousse `b` hors de l'autre.
static func push_apart(b: Body, ox: float, oy: float, oz: float) -> void:
	var dx := b.px - ox
	var dz := b.pz - oz
	if absf(b.py - oy) > 1.3:
		return
	var d := sqrt(dx * dx + dz * dz)
	var mn := RADIUS * 2.0
	if d >= mn or d < 1e-4:
		return
	var k := (mn - d) / d
	b.px += dx * k * 0.5
	b.pz += dz * k * 0.5
	b.vx += (dx / d) * 1.5
	b.vz += (dz / d) * 1.5


## Bousculade complète (après step_body, pour chaque autre joueur, si le réglage est activé) : push_apart, puis
## trébuchement si l'autre (position op, vitesse ov) nous fonce dessus vite. Vrai si on vient de trébucher.
static func jostle(b: Body, ox: float, oy: float, oz: float, ovx: float, ovz: float) -> bool:
	var dx := b.px - ox
	var dz := b.pz - oz
	if absf(b.py - oy) > 1.3:
		return false
	var d := sqrt(dx * dx + dz * dz)
	if d >= RADIUS * 2.0 or d < 1e-4:
		return false
	var nx := dx / d
	var nz := dz / d
	var hit := ovx * nx + ovz * nz  # vitesse de l'autre vers nous
	var mine := -(b.vx * nx + b.vz * nz)  # notre vitesse vers lui (avant la poussée)
	push_apart(b, ox, oy, oz)
	if hit <= JOSTLE_TRIP or hit <= mine or b.tumble > 0.0 or b.shield > 0.0 or b.zip >= 0:
		return false
	b.vx += nx * hit * 0.8
	b.vz += nz * hit * 0.8
	b.vy = maxf(b.vy, 3.5)
	b.tumble = TRIP_TUMBLE
	b.grounded = false
	b.coyote = 0.0
	return true
