// Simulation d'une partie complète sans réseau : des bots jouent avec la vraie physique et les vraies règles.
import type { ServerCtx, ServerGameModule, ServerPlayer } from '../shared/src/game-api';
import { makeBody } from '../shared/src/physics';
import { FLAG } from '../shared/src/protocol';

export function simulate(mod: ServerGameModule, settings: Record<string, any>, nBots: number, maxSeconds: number) {
  let t = 0, ended = false;
  const players = new Map<string, ServerPlayer>();
  for (let i = 0; i < nBots; i++) players.set(`b${i}`, { id: `b${i}`, name: `Bot ${i}`, isBot: true, p: [0, 0, 0], v: [0, 0, 0], yaw: 0, flags: FLAG.grounded });
  const log: any[] = [];
  const ctx: ServerCtx = {
    players, settings, startAt: 1,
    now: () => t,
    broadcast: (m) => log.push(m),
    send: () => {},
    damage: (id, hit) => log.push({ t: 'damage', id, hit }),
    heal: () => {},
    impulse: (id, v, tumble) => { const b = players.get(id)!.body!; b.v = [...v]; b.tumble = tumble; b.grounded = false; b.coyote = 0; },
    teleport: (id, p) => { players.get(id)!.body!.p = [...p]; },
    end: () => { ended = true; },
  };
  const game = mod.create(ctx);
  const { spawns } = game.onStart();
  for (const p of players.values()) { p.p = [...spawns[p.id]]; p.body = makeBody(p.p); }
  const dt = 1 / 30;
  while (!ended && t < maxSeconds) {
    t += dt;
    if (t >= ctx.startAt) for (const p of players.values()) {
      game.botTick!(p, dt);
      p.p = [...p.body!.p]; p.v = [...p.body!.v];
    }
    game.onTick(dt);
  }
  return { results: game.getResults(), log, t, ended, players };
}
