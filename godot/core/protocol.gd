class_name Protocol
extends RefCounted
## Constantes du protocole WebSocket, reprises de shared/src/protocol.ts.

const FLAG_GROUNDED := 1
const FLAG_TUMBLE := 2
const FLAG_CHARGING := 4
const FLAG_HIDDEN := 8
# —— vague 3 : bits de pose (parcours) ——
const FLAG_ZIP := 16
const FLAG_FLIGHT := 32
const FLAG_BOOST := 64
const FLAG_SHIELD := 128


## Bits de pose du corps local (tyrolienne, vol, élan, bouclier), à OR-er dans les drapeaux de l'état envoyé.
static func pose_flags(b: Phys.Body) -> int:
	return (FLAG_ZIP if b.zip >= 0 else 0) | (FLAG_FLIGHT if b.flight > 0.0 else 0) | (FLAG_BOOST if b.boost > 0.0 else 0) | (FLAG_SHIELD if b.shield > 0.0 else 0)

## Personnages (le champ `hat` du profil désigne le personnage choisi) et leur couleur d'origine.
const HAT_COLOR := {
	"haricot": 0xf0629a, "casquette": 0x4a8fe8, "spaghetti": 0xffc636, "hélice": 0x9a6be0,
	"bouée": 0x7dc95a, "crochet": 0xf78a3c, "bandeau": 0x7ccdf2, "arche": 0xb08cf0,
}
const HATS := ["haricot", "casquette", "spaghetti", "hélice", "bouée", "crochet", "bandeau", "arche"]
const COLORS := [0xf0629a, 0x4a8fe8, 0xffc636, 0x9a6be0, 0x7dc95a, 0xf78a3c, 0x7ccdf2, 0xb08cf0, 0xff4d6d, 0xf8f9fa]
const MAX_PLAYERS := 10
