// Non-régression des bots : plateau tournant éloigné (écart calculé sur une boîte non tournée) et bot perché sur la
// barre basse d'un balayeur (pris pour un bord où attendre).
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import type { ServerCtx, ServerPlayer } from '../shared/src/game-api';
import { makeBody, type Vec3 } from '../shared/src/physics';
import { FLAG } from '../shared/src/protocol';
import { defaultGameSettings } from '../shared/src/scoring';
import { parkourMeta } from '../games/parkour/shared';
import { simulate } from './sim';

process.env.JEUX_LEVELS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures', 'parkour');
const { parkourServer } = await import('../games/parkour/server');

const settings = (level: string) => ({ ...defaultGameSettings(parkourMeta), duration: 60, hurry: 60, levels: [level] });

describe('bots : non-régression', () => {
  it('plateau tournant de 8 m à 3 m du départ : les bots sautent dessus au lieu d\'attendre au bord', () => {
    // avant correction : 0 arrivée sur 6 (écart estimé sur une seule boîte de l'octogone, sans sa rotation)
    for (let pass = 0; pass < 3; pass++) {
      const { log } = simulate(parkourServer, settings('bug-manege'), 6, 40);
      expect(log.filter((m) => m.t === 'finish').length).toBeGreaterThanOrEqual(5);
    }
  });

  it('bot posé sur la barre basse d\'un balayeur (dessus à 0.6 m du sol) : il en descend et repart', () => {
    let t = 0;
    const bot: ServerPlayer = { id: 'b0', name: 'B', isBot: true, p: [0, 0, 0], v: [0, 0, 0], yaw: 0, flags: FLAG.grounded };
    const players = new Map([[bot.id, bot]]);
    const ctx: ServerCtx = {
      players, settings: settings('bug-barre'), startAt: 0, now: () => t,
      broadcast: () => {}, send: () => {}, damage: () => {}, heal: () => {}, impulse: () => {}, teleport: () => {}, end: () => {},
    };
    const game = parkourServer.create(ctx);
    game.onStart();
    // sur l'axe de la barre basse (élément 2, centre [0, 0.45, 13], épaisseur 0.3), après la courte hésitation de départ
    t = 1;
    const p: Vec3 = [0, 0.62, 13];
    bot.body = makeBody(p);
    let onBar = 0, maxZ = 0;
    const dt = 1 / 30;
    for (let i = 0; i < 90; i++) {
      t += dt;
      game.botTick!(bot, dt);
      bot.p = [...bot.body.p];
      if (bot.body.grounded && bot.body.groundId === 2) onBar += dt;
      maxZ = Math.max(maxZ, bot.body.p[2]);
    }
    // avant correction : il restait sur la barre (« attente au bord » ~36 s avant de réapparaître)
    expect(onBar).toBeLessThan(1);
    expect(maxZ).toBeGreaterThan(17); // il a quitté la dalle du balayeur vers l'arrivée
  });
});
