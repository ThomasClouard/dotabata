class_name ClientGame
extends RefCounted
## Contrat client d'un mini-jeu. `ctx` est le nœud Main.

func on_enter(_ctx: Main, _init: Variant) -> void:
	pass


func on_message(_m: Dictionary) -> void:
	pass


func on_frame(_dt: float) -> void:
	pass


func on_exit() -> void:
	pass


## Collisions du joueur local à l'instant `t`.
func colliders(_t: float) -> Array:
	return []


func pre_step(_b: Phys.Body, _dt: float) -> void:
	pass


func post_step(_b: Phys.Body, _contacts: Array, _dt: float) -> void:
	pass


## Contact avec un autre joueur (position op, vitesse ov), après le pas de physique. Par défaut : simple poussée.
func jostle(b: Phys.Body, op: Vector3, _ov: Vector3) -> void:
	Phys.push_apart(b, op.x, op.y, op.z)


## Bits de pose propres au jeu, ajoutés aux drapeaux de l'état envoyé (Protocol.FLAG_ZIP…).
func pose_flags(_b: Phys.Body) -> int:
	return 0


## Vitesse de marche et vitesse verticale servant à animer un personnage (position p, vitesse v). Par défaut, le haut
## est l'axe Y ; un jeu à gravité différente (planètes) les calcule dans son propre repère.
func motion(_p: Vector3, v: Vector3) -> Vector2:
	return Vector2(sqrt(v.x * v.x + v.z * v.z), v.y)


## Cap transmis aux autres joueurs (par défaut : celui du personnage, autour de l'axe Y).
func net_yaw(yaw: float) -> float:
	return yaw


## Joueur « fantôme » (ex. : arrivé au parcours) : ni bousculé, ni bousculant.
func is_ghost(_id: String) -> bool:
	return false
