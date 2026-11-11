class_name Registry
extends RefCounted
## Registre client des mini-jeux (équivalent de games/registry.client.ts).


static func create(game_id: String) -> ClientGame:
	match game_id:
		"parkour":
			return ParkourClient.new()
		"mortar":
			return MortarClient.new()
	return null
