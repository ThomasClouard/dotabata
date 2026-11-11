import type { ClientGameFactory } from '../client/src/api';
import { createParkourClient } from './parkour/client';
import { createMortarClient } from './mortar/client';

export const clientGames: Record<string, ClientGameFactory> = {
  parkour: createParkourClient,
  mortar: createMortarClient,
};
