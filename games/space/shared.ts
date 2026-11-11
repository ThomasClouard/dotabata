// Saut cosmique — fiche du jeu (référence TypeScript des réglages). Le jeu lui-même vit dans godot/ :
// godot/sim/space_shared.gd (vol, gravité, planètes), godot/server/games/space_server.gd, godot/games/space/.
import type { GameMeta } from '../../shared/src/game-api';

export const spaceMeta: GameMeta = {
  id: 'space',
  name: 'Saut cosmique',
  description: 'Vise une planète et décolle quand tu veux ! Plus elle est loin, plus elle rapporte ; à points égaux, le premier posé gagne.',
  settings: {
    aimTime: { type: 'number', label: 'Temps pour décoller', default: 30, min: 10, max: 60, step: 5, unit: 's' },
    flightTime: { type: 'number', label: 'Durée maximale du vol', default: 30, min: 15, max: 60, step: 5, unit: 's' },
    fuel: { type: 'number', label: 'Carburant des rétro-fusées', default: 1.5, min: 0, max: 5, step: 0.5, unit: 's' },
    planets: { type: 'number', label: 'Planètes d\'arrivée', default: 12, min: 4, max: 16, step: 1 },
    gravity: { type: 'bool', label: 'Attraction des planètes', default: true },
    bump: { type: 'bool', label: 'Collisions entre joueurs', default: true },
  },
};

export interface SpacePlanet {
  c: [number, number, number];
  r: number;
  pts: number; // 0 pour la planète de départ
  name: string;
  color: number;
  ring: boolean;
}

export interface SpaceInit {
  planets: SpacePlanet[]; // [0] = planète de départ
  aimEnd: number; // fin de la visée = décollage (horloge serveur)
  flightEnd: number;
  fuel: number; // secondes de poussée
  gravity: boolean;
  bump: boolean;
}
