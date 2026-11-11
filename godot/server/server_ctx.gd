class_name ServerCtx
extends RefCounted
## Contexte donné à une manche serveur (ServerCtx de shared/src/game-api.ts).
## Les actions sont des Callables fournis par la session (ou par le banc d'essai des tests).

var players := {}  # id → ServerPlayer (joueurs de la manche, dans l'ordre d'arrivée)
var settings := {}
var start_at := 0.0  # fin du compte à rebours (horloge serveur, en secondes)

var _now: Callable
var _broadcast: Callable  # (m)
var _send: Callable  # (id, m)
var _damage: Callable  # (id, hit)
var _heal: Callable  # (id, n)
var _impulse: Callable  # (id, v, tumble)
var _teleport: Callable  # (id, p)
var _end: Callable


func now() -> float:
	return _now.call()


func broadcast(m: Dictionary) -> void:
	_broadcast.call(m)


func send(id: String, m: Dictionary) -> void:
	_send.call(id, m)


## Montre un impact sur la peau du joueur à tout le monde (les PV sont gérés par le jeu). hit = {pos, r}.
func damage(id: String, hit: Dictionary) -> void:
	_damage.call(id, hit)


func heal(id: String, n: int) -> void:
	_heal.call(id, n)


func impulse(id: String, v: Array, tumble: float) -> void:
	_impulse.call(id, v, tumble)


func teleport(id: String, p: Array) -> void:
	_teleport.call(id, p)


func end() -> void:
	_end.call()


## Applique une impulsion à un bot (corps simulé par le serveur).
static func impulse_body(b: Phys.Body, v: Array, tumble: float) -> void:
	b.vx = v[0]
	b.vy = v[1]
	b.vz = v[2]
	b.tumble = tumble
	b.grounded = false
	b.coyote = 0.0
