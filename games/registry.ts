// Fiches des mini-jeux (référence TypeScript des réglages). Le jeu vit dans godot/ : les fiches y sont recopiées dans
// godot/server/metas.gd, et les tests de parité vérifient qu'elles sont identiques.
import type { GameMeta } from '../shared/src/game-api';
import { parkourMeta } from './parkour/shared';
import { mortarMeta } from './mortar/shared';

export const gameMetas: GameMeta[] = [parkourMeta, mortarMeta];
