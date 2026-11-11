// Registre des mini-jeux (partie commune). Ajouter un jeu = un dossier games/<id>/ + une ligne ici,
// une dans registry.server.ts et une dans registry.client.ts.
import type { GameMeta } from '../shared/src/game-api';
import { parkourMeta } from './parkour/shared';
import { mortarMeta } from './mortar/shared';

export const gameMetas: GameMeta[] = [parkourMeta, mortarMeta];
