class_name ClientPlayer
extends RefCounted
## Un joueur vu par le client : infos du lobby, personnage affiché, dernier état reçu du réseau.

var info: Dictionary
var chr: Character
var label: Label3D
var shadow: MeshInstance3D
var pos := Vector3.ZERO  # position affichée (interpolée pour les autres joueurs)
var yaw := 0.0
var flags := Protocol.FLAG_GROUNDED
## Fige le personnage à un endroit (podium) : { p: Vector3, yaw: float, dance: bool } ou null.
var pin: Variant = null
## Masque le personnage (ex. tombé dans le vide). Remis à faux à chaque changement de scène.
var hidden := false
var net_p := Vector3.ZERO
var net_v := Vector3.ZERO
var net_yaw := 0.0
var net_flags := Protocol.FLAG_GROUNDED

var id: String:
	get:
		return info["id"]
var name: String:
	get:
		return info["name"]
var color: int:
	get:
		return int(info["color"])
