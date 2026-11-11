import type { ServerGameModule } from '../shared/src/game-api';
import { parkourServer } from './parkour/server';
import { mortarServer } from './mortar/server';

export const serverGames: Record<string, ServerGameModule> = {
  parkour: parkourServer,
  mortar: mortarServer,
};
