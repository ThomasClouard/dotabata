class_name Registry
extends RefCounted
## Registre client des mini-jeux (leur fiche et leur partie serveur sont dans server/metas.gd).


static func create(game_id: String) -> ClientGame:
	match game_id:
		"parkour":
			return ParkourClient.new()
		"mortar":
			return MortarClient.new()
	return null
