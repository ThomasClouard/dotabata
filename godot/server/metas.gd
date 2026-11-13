class_name GameMetas
extends RefCounted
## Fiches des mini-jeux (nom, description, réglages du lobby) et registre des jeux serveur.
## Portage de games/*/shared.ts (parkourMeta, mortarMeta) et de games/registry.ts.
## Ajouter un jeu : sa fiche ici, sa classe serveur dans server/games/, sa classe client dans core/registry.gd.

const PARKOUR := {
	"id": "parkour",
	"name": "Parcours délirant",
	"description": "Course d'obstacles : marteaux, barres tournantes, trampolines… Le premier à l'arrivée gagne, ou le meilleur temps : on refait le parcours autant qu'on veut.",
	"settings": {
		"mode": {"type": "choice", "label": "Mode", "default": "first", "options": ["first", "best"], "labels": ["Premier arrivé", "Meilleur temps"]},
		"duration": {"type": "number", "label": "Durée de la manche", "default": 150, "min": 45, "max": 300, "step": 15, "unit": "s"},
		"hurry": {"type": "number", "label": "Temps restant après le premier arrivé", "default": 40, "min": 10, "max": 120, "step": 5, "unit": "s"},
		"levels": {"type": "multi", "label": "Niveaux autorisés", "default": [], "options": []},
		"jostle": {"type": "bool", "label": "Bousculades entre joueurs", "default": true},
		"coins": {"type": "bool", "label": "Pièces : départager les ex æquo", "default": true},
	},
}

const MORTAR := {
	"id": "mortar",
	"name": "Abri & mortier",
	"description": "Construis ton abri, puis bombarde les îles voisines au mortier. Dernier survivant gagne.",
	"settings": {
		"buildTime": {"type": "number", "label": "Temps de construction", "default": 20, "min": 5, "max": 90, "step": 5, "unit": "s"},
		"battleTime": {"type": "number", "label": "Durée de la bataille", "default": 120, "min": 30, "max": 300, "step": 15, "unit": "s"},
		"budget": {"type": "number", "label": "Budget de blocs", "default": 14, "min": 0, "max": 40, "step": 1},
		"hp": {"type": "number", "label": "Points de vie", "default": 100, "min": 20, "max": 300, "step": 10},
		"crates": {"type": "bool", "label": "Caisses bonus", "default": true},
		"shrink": {"type": "number", "label": "Durée du rétrécissement final", "default": 35, "min": 0, "max": 120, "step": 5, "unit": "s"},
		"holes": {"type": "bool", "label": "Les obus trouent les îles", "default": false},
	},
}


const SPACE := {
	"id": "space",
	"name": "Saut cosmique",
	"description": "Vise une planète et décolle quand tu veux ! Plus elle est loin, plus elle rapporte ; à points égaux, le premier posé gagne.",
	"settings": {
		"aimTime": {"type": "number", "label": "Temps pour décoller", "default": 30, "min": 10, "max": 60, "step": 5, "unit": "s"},
		"flightTime": {"type": "number", "label": "Durée maximale du vol", "default": 30, "min": 15, "max": 60, "step": 5, "unit": "s"},
		"fuel": {"type": "number", "label": "Carburant des rétro-fusées", "default": 1.5, "min": 0, "max": 5, "step": 0.5, "unit": "s"},
		"planets": {"type": "number", "label": "Planètes d'arrivée", "default": 12, "min": 4, "max": 16, "step": 1},
		"gravity": {"type": "bool", "label": "Attraction des planètes", "default": true},
		"bump": {"type": "bool", "label": "Collisions entre joueurs", "default": true},
	},
}


static func all() -> Array:
	return [PARKOUR, MORTAR, SPACE]


## Crée la manche serveur du jeu `id` (ServerGame), ou null.
static func create_game(id: String, ctx: ServerCtx) -> ServerGame:
	match id:
		"parkour":
			return ParkourServer.new(ctx)
		"mortar":
			return MortarServer.new(ctx)
		"space":
			return SpaceServer.new(ctx)
	return null


## Options calculées à l'affichage du lobby (ex. niveaux présents sur le disque) : { jeu: { réglage: options } }.
static func dynamic_options() -> Dictionary:
	return {"parkour": {"levels": LevelStore.list_levels()}}
