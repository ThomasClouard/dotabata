class_name ServerPlayer
extends RefCounted
## Joueur vu par le serveur (ServerPlayer + SPlayer du TS). Positions en Array de 3 flottants.

var id := ""
var name := ""
var is_bot := false
var p: Array = [0.0, 0.0, 0.0]  # pieds
var v: Array = [0.0, 0.0, 0.0]
var yaw := 0.0
var flags := 0
var body: Phys.Body = null  # seulement pour les bots, simulés par le serveur
# —— session ——
var color := 0
var hat := ""
var score := 0
var in_round := false
var peer: WebSocketPeer = null  # null pour les bots


func sync_from_body() -> void:
	p = [body.px, body.py, body.pz]
	v = [body.vx, body.vy, body.vz]
