class_name ServerGame
extends RefCounted
## Manche d'un mini-jeu côté serveur (ServerGame de shared/src/game-api.ts). Les jeux héritent de cette classe.

var ctx: ServerCtx


func _init(p_ctx: ServerCtx) -> void:
	ctx = p_ctx


## { init: Dictionary, spawns: { id: [x, y, z] } }. Peut lever une erreur via push_error + retour {} (manche annulée).
func on_start() -> Dictionary:
	return {}


func on_tick(_dt: float) -> void:
	pass


func on_player_message(_id: String, _msg: Dictionary) -> void:
	pass


func on_player_leave(_id: String) -> void:
	pass


## RoundResult[] : [{id, rank, label}].
func get_results() -> Array:
	return []


func has_bots() -> bool:
	return false


func bot_tick(_pl: ServerPlayer, _dt: float) -> void:
	pass
