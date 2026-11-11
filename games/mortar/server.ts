// Abri & mortier — autorité serveur : construction, obus, explosions, dégâts, caisses, zone, bots.
import type { RoundResult, ServerCtx, ServerGame, ServerGameModule, ServerPlayer } from '../../shared/src/game-api';
import { stepBody, type Vec3 } from '../../shared/src/physics';
import { ranksFromGroups } from '../../shared/src/scoring';
import {
  M, MATS, MAT_KEYS, SHELLS, blockCenter, blockKey, cellAt, columnHeight, launch, mortarColliders, plotCenter, powerForDistance, toLocal, zoneRadius,
  type Block, type CrateKind, type Mat, type MortarInit, type ShellKind,
} from './shared';

interface MP { plot: number; hp: number; alive: boolean; deadAt: number; lastFire: number; ammo: ShellKind; budget: number }
interface Shell { id: number; p: Vec3; v: Vec3; kind: ShellKind; owner: string; born: number }
interface Crate { id: number; p: Vec3; kind: CrateKind; landAt: number }
interface Bot { nextAct: number; target: Vec3; nextMove: number }

const rnd = (a: number, b: number) => a + Math.random() * (b - a);

function create(ctx: ServerCtx): ServerGame {
  let n = 0;
  let buildEnd = 0, battleEnd = 0, shrinkStart = 0;
  const mps = new Map<string, MP>();
  const blocks = new Map<string, Block>();
  const shells = new Map<number, Shell>();
  const crates = new Map<number, Crate>();
  const bots = new Map<string, Bot>();
  let nextId = 1;
  let nextCrate = 0;
  let nextZone = 0;
  let endingAt = 0;
  let deathOrder = 0;

  const alive = () => [...mps.entries()].filter(([, m]) => m.alive);

  function kill(id: string, cause: 'hp' | 'fall') {
    const m = mps.get(id);
    if (!m || !m.alive) return;
    m.alive = false;
    m.hp = 0;
    m.deadAt = ++deathOrder;
    ctx.broadcast({ t: 'dead', id, cause });
  }

  function hurt(id: string, dmg: number, from: Vec3 | null) {
    const m = mps.get(id), p = ctx.players.get(id);
    if (!m || !p || !m.alive || dmg <= 0) return;
    m.hp = Math.max(0, m.hp - Math.round(dmg));
    // l'impact est placé du côté d'où vient le coup, en coordonnées locales du personnage
    let a = Math.random() * Math.PI * 2;
    if (from) a = Math.atan2(from[0] - p.p[0], from[2] - p.p[2]) - p.yaw + rnd(-0.5, 0.5);
    ctx.damage(id, { pos: [Math.sin(a) * 0.32, rnd(0.4, 1.3), Math.cos(a) * 0.32], r: Math.min(0.42, 0.16 + dmg / 180) });
    ctx.broadcast({ t: 'hp', id, hp: m.hp });
    if (m.hp <= 0) kill(id, 'hp');
  }

  /** Un bloc de la parcelle se trouve-t-il entre l'explosion et le joueur ? (test segment / boîte) */
  function covered(plot: number, wa: Vec3, wb: Vec3): boolean {
    // on travaille dans le repère de l'île, où les blocs sont alignés sur les axes
    const la = toLocal(plot, n, wa[0], wa[2]), lb = toLocal(plot, n, wb[0], wb[2]);
    const a: Vec3 = [la[0], wa[1], la[1]], b: Vec3 = [lb[0], wb[1], lb[1]];
    const off = (M.grid - 1) / 2;
    for (const blk of blocks.values()) {
      if (blk.plot !== plot) continue;
      const c: Vec3 = [blk.x - off, blk.y + 0.5, blk.z - off];
      let t0 = 0, t1 = 1, hit = true;
      for (let k = 0; k < 3 && hit; k++) {
        const d = b[k] - a[k], lo = c[k] - 0.5, hi = c[k] + 0.5;
        if (Math.abs(d) < 1e-6) { if (a[k] < lo || a[k] > hi) hit = false; continue; }
        let u0 = (lo - a[k]) / d, u1 = (hi - a[k]) / d;
        if (u0 > u1) [u0, u1] = [u1, u0];
        t0 = Math.max(t0, u0); t1 = Math.min(t1, u1);
        if (t0 > t1) hit = false;
      }
      if (hit) return true;
    }
    return false;
  }

  function explode(s: Shell, pos: Vec3) {
    shells.delete(s.id);
    const spec = SHELLS[s.kind];
    const victims: { id: string; dmg: number; imp: Vec3 }[] = [];
    for (const [id, m] of alive()) {
      const p = ctx.players.get(id)!;
      const center: Vec3 = [p.p[0], p.p[1] + 0.8, p.p[2]];
      const dx = center[0] - pos[0], dy = center[1] - pos[1], dz = center[2] - pos[2];
      const d = Math.hypot(dx, dy, dz), R = spec.r + 0.5;
      if (d >= R) continue;
      const cover = covered(m.plot, pos, center) ? 0.35 : 1;
      const k = 1 - d / R, hl = Math.hypot(dx, dz) || 1;
      const f = (5 + 13 * k) * cover;
      victims.push({ id, dmg: (spec.dmg * k + 5) * cover, imp: [(dx / hl) * f, 5 + 5 * k * cover, (dz / hl) * f] });
    }
    const removed: string[] = [];
    for (const [key, blk] of blocks) {
      const c = blockCenter(blk, n);
      if (Math.hypot(c[0] - pos[0], c[1] - pos[1], c[2] - pos[2]) > spec.r + 0.4) continue;
      blk.hp -= spec.block;
      if (blk.hp <= 0) { blocks.delete(key); removed.push(key); }
    }
    ctx.broadcast({ t: 'boom', id: s.id, p: pos, r: spec.r, kind: s.kind, removed });
    for (const v of victims) {
      ctx.impulse(v.id, v.imp, 1.0);
      hurt(v.id, v.dmg, pos);
    }
    if (s.kind === 'cluster') {
      for (let i = 0; i < 5; i++) {
        const a = (i / 5) * Math.PI * 2 + Math.random();
        spawnShell([pos[0], pos[1] + 0.5, pos[2]], [Math.sin(a) * rnd(3, 7), rnd(7, 10), Math.cos(a) * rnd(3, 7)], 'sub', s.owner);
      }
    }
  }

  function spawnShell(p: Vec3, v: Vec3, kind: ShellKind, owner: string) {
    const s: Shell = { id: nextId++, p, v, kind, owner, born: ctx.now() };
    shells.set(s.id, s);
    ctx.broadcast({ t: 'shell', id: s.id, p, v, at: s.born, kind, owner });
  }

  function stepShell(s: Shell, dt: number) {
    s.v[1] -= M.g * dt;
    s.p[0] += s.v[0] * dt; s.p[1] += s.v[1] * dt; s.p[2] += s.v[2] * dt;
    if (s.p[1] < -25) { shells.delete(s.id); ctx.broadcast({ t: 'gone', id: s.id }); return; }
    const young = ctx.now() - s.born < 0.35;
    for (const [id] of alive()) {
      if (young && id === s.owner) continue;
      const p = ctx.players.get(id)!;
      if (Math.hypot(s.p[0] - p.p[0], s.p[2] - p.p[2]) < 0.6 && s.p[1] > p.p[1] - 0.1 && s.p[1] < p.p[1] + 1.6) return explode(s, [...s.p]);
    }
    for (let i = 0; i < n; i++) {
      const [lx, lz] = toLocal(i, n, s.p[0], s.p[2]);
      if (Math.abs(lx) > M.island / 2 || Math.abs(lz) > M.island / 2) continue;
      const cell = cellAt(i, n, s.p[0], s.p[2]);
      const y = Math.floor(s.p[1]);
      if (cell && y >= 0 && y < M.maxH) {
        const key = blockKey(i, cell.x, y, cell.z), blk = blocks.get(key);
        if (blk) {
          if (blk.mat === 'tramp' && s.v[1] < 0) {
            // le trampoline renvoie l'obus et s'use
            s.p[1] = y + 1.05;
            s.v = [s.v[0] * 0.9 + rnd(-1, 1), -s.v[1] * 0.85, s.v[2] * 0.9 + rnd(-1, 1)];
            s.owner = '';
            ctx.broadcast({ t: 'bounce', id: s.id, p: s.p, v: s.v, at: ctx.now() });
            if (--blk.hp <= 0) { blocks.delete(key); ctx.broadcast({ t: 'unblock', keys: [key] }); }
            return;
          }
          return explode(s, [...s.p]);
        }
      }
      if (s.p[1] <= 0 && s.p[1] > -M.thick) return explode(s, [s.p[0], 0.05, s.p[2]]);
    }
  }

  function place(id: string, x: number, z: number, mat: Mat) {
    const m = mps.get(id);
    if (!m || !m.alive || ctx.now() >= buildEnd || !MATS[mat]) return;
    if (!Number.isInteger(x) || !Number.isInteger(z) || x < 0 || z < 0 || x >= M.grid || z >= M.grid) return;
    const y = columnHeight(blocks, m.plot, x, z);
    if (y >= M.maxH || m.budget < MATS[mat].cost) return;
    m.budget -= MATS[mat].cost;
    const blk: Block = { plot: m.plot, x, y, z, mat, hp: MATS[mat].hp };
    blocks.set(blockKey(m.plot, x, y, z), blk);
    ctx.broadcast({ t: 'block', b: blk, by: id, budget: m.budget });
  }

  function unplace(id: string, x: number, z: number) {
    const m = mps.get(id);
    if (!m || !m.alive || ctx.now() >= buildEnd || !Number.isInteger(x) || !Number.isInteger(z)) return;
    const y = columnHeight(blocks, m.plot, x, z) - 1;
    const key = blockKey(m.plot, x, y, z), blk = blocks.get(key);
    if (!blk) return;
    blocks.delete(key);
    m.budget += MATS[blk.mat].cost;
    ctx.broadcast({ t: 'unblock', keys: [key], by: id, budget: m.budget });
  }

  function fire(id: string, yaw: number, power: number) {
    const m = mps.get(id), p = ctx.players.get(id), t = ctx.now();
    if (!m || !p || !m.alive || t < buildEnd || t - m.lastFire < M.reload - 0.1) return;
    if (!Number.isFinite(yaw) || !Number.isFinite(power)) return;
    m.lastFire = t;
    const l = launch(p.p, yaw, power);
    spawnShell(l.p, l.v, m.ammo, id);
    if (m.ammo !== 'normal') { m.ammo = 'normal'; ctx.send(id, { t: 'ammo', kind: 'normal' }); }
  }

  return {
    onStart() {
      n = ctx.players.size;
      const s = ctx.settings;
      buildEnd = ctx.startAt + s.buildTime;
      battleEnd = buildEnd + s.battleTime;
      shrinkStart = battleEnd - Math.min(s.shrink, s.battleTime);
      nextCrate = buildEnd + rnd(6, 10);
      const plots: Record<string, number> = {}, spawns: Record<string, Vec3> = {};
      let i = 0;
      for (const p of ctx.players.values()) {
        plots[p.id] = i;
        const c = plotCenter(i, n);
        spawns[p.id] = [c[0], 0.1, c[2]];
        mps.set(p.id, { plot: i, hp: s.hp, alive: true, deadAt: 0, lastFire: 0, ammo: 'normal', budget: s.budget });
        if (p.isBot) bots.set(p.id, { nextAct: ctx.startAt + rnd(0.5, 2), target: [c[0], 0, c[2]], nextMove: 0 });
        i++;
      }
      const init: MortarInit = { n, plots, buildEnd, battleEnd, shrinkStart, budget: s.budget, hp: s.hp };
      return { init, spawns };
    },

    onTick(dt) {
      const t = ctx.now();
      if (t < ctx.startAt) return;
      for (const [id] of alive()) if (ctx.players.get(id)!.p[1] < -10) kill(id, 'fall');
      if (t >= buildEnd) {
        const sub = 4;
        for (const s of [...shells.values()]) for (let k = 0; k < sub && shells.has(s.id); k++) stepShell(s, dt / sub);

        if (ctx.settings.crates && t >= nextCrate && t < battleEnd - 5) {
          nextCrate = t + rnd(9, 14);
          const live = alive();
          if (live.length) {
            const [, m] = live[Math.floor(Math.random() * live.length)];
            const cx = Math.floor(rnd(0, M.grid)), cz = Math.floor(rnd(0, M.grid));
            const c = blockCenter({ plot: m.plot, x: cx, y: columnHeight(blocks, m.plot, cx, cz), z: cz }, n);
            const kind: CrateKind = (['mega', 'cluster', 'repair'] as const)[Math.floor(Math.random() * 3)];
            const crate: Crate = { id: nextId++, p: [c[0], c[1] - 0.1, c[2]], kind, landAt: t + 3.5 };
            crates.set(crate.id, crate);
            ctx.broadcast({ t: 'crate', id: crate.id, p: crate.p, kind, landAt: crate.landAt });
          }
        }
        for (const c of crates.values()) {
          if (t < c.landAt) continue;
          for (const [id, m] of alive()) {
            const p = ctx.players.get(id)!;
            if (Math.hypot(p.p[0] - c.p[0], p.p[2] - c.p[2]) > 1.2 || Math.abs(p.p[1] + 0.4 - c.p[1]) > 1.5) continue;
            crates.delete(c.id);
            if (c.kind === 'repair') {
              m.hp = Math.min(ctx.settings.hp, m.hp + 35);
              ctx.heal(id, 4);
              ctx.broadcast({ t: 'hp', id, hp: m.hp });
            } else {
              m.ammo = c.kind;
              ctx.send(id, { t: 'ammo', kind: c.kind });
            }
            ctx.broadcast({ t: 'crateTaken', id: c.id, by: id, kind: c.kind });
            break;
          }
        }

        if (t > shrinkStart && t >= nextZone) {
          nextZone = t + 0.5;
          const r = zoneRadius(t, shrinkStart, battleEnd);
          for (const [id, m] of alive()) {
            const p = ctx.players.get(id)!, c = plotCenter(m.plot, n);
            if (Math.hypot(p.p[0] - c[0], p.p[2] - c[2]) > r) hurt(id, 6, null);
          }
        }
      }
      // fin : un seul survivant (on laisse 2,5 s pour savourer l'explosion) ou temps écoulé
      const left = alive().length;
      if (!endingAt && (left <= (n > 1 ? 1 : 0) || t >= battleEnd)) endingAt = t + (t >= battleEnd ? 0 : 2.5);
      if (endingAt && t >= endingAt) ctx.end();
    },

    onPlayerMessage(id, msg) {
      if (msg?.t === 'place') place(id, msg.x, msg.z, msg.mat);
      else if (msg?.t === 'remove') unplace(id, msg.x, msg.z);
      else if (msg?.t === 'fire') fire(id, msg.yaw, msg.power);
    },

    onPlayerLeave(id) {
      kill(id, 'fall');
      bots.delete(id);
    },

    getResults(): RoundResult[] {
      const rows = [...mps.entries()].filter(([id]) => ctx.players.has(id));
      const survivors = rows.filter(([, m]) => m.alive).sort((a, b) => b[1].hp - a[1].hp);
      const dead = rows.filter(([, m]) => !m.alive).sort((a, b) => b[1].deadAt - a[1].deadAt);
      const groups: { id: string; label: string }[][] = [];
      for (const [id, m] of survivors) {
        const lbl = { id, label: `Survivant · ${m.hp} PV` };
        const last = groups[groups.length - 1];
        // même nombre de PV à la fin du temps : ex æquo
        if (last && mps.get(last[0].id)!.hp === m.hp) last.push(lbl); else groups.push([lbl]);
      }
      for (const [id] of dead) groups.push([{ id, label: 'Éliminé' }]);
      return ranksFromGroups(groups);
    },

    botTick(pl: ServerPlayer, dt: number) {
      const b = pl.body, bot = bots.get(pl.id), m = mps.get(pl.id);
      if (!b || !bot || !m) return;
      const t = ctx.now(), c = plotCenter(m.plot, n);
      let mx = 0, mz = 0;
      if (m.alive && t >= ctx.startAt) {
        if (t >= bot.nextAct) {
          if (t < buildEnd) {
            bot.nextAct = Math.min(t + rnd(0.4, 1.1), buildEnd) + (t + 1.1 >= buildEnd ? rnd(1, 4) : 0);
            const mat = MAT_KEYS[Math.floor(Math.random() * 3)];
            // construit un muret autour du centre de l'île
            const a = Math.random() * Math.PI * 2, r = rnd(1.5, 3);
            place(pl.id, Math.floor(M.grid / 2 + Math.sin(a) * r), Math.floor(M.grid / 2 + Math.cos(a) * r), mat);
          } else {
            bot.nextAct = t + rnd(1.8, 4);
            const foes = alive().filter(([id]) => id !== pl.id);
            if (foes.length) {
              const target = ctx.players.get(foes[Math.floor(Math.random() * foes.length)][0])!;
              const dx = target.p[0] - b.p[0], dz = target.p[2] - b.p[2];
              // visée volontairement approximative : un bot ne doit pas être un tireur d'élite
              pl.yaw = Math.atan2(dx, dz) + rnd(-0.11, 0.11);
              fire(pl.id, pl.yaw, powerForDistance(Math.hypot(dx, dz)) + rnd(-0.08, 0.08));
            }
          }
        }
        if (t >= bot.nextMove) {
          bot.nextMove = t + rnd(1.5, 4);
          const r = Math.min(3.5, zoneRadius(t, shrinkStart, battleEnd) - 1);
          bot.target = [c[0] + rnd(-r, r), 0, c[2] + rnd(-r, r)];
        }
        const dx = bot.target[0] - b.p[0], dz = bot.target[2] - b.p[2], d = Math.hypot(dx, dz);
        if (d > 0.5) { mx = (dx / d) * 0.6; mz = (dz / d) * 0.6; }
      }
      stepBody(b, { mx, mz, jump: contactsBlocked(b, mx, mz) }, mortarColliders(n, blocks.values(), m.plot), dt);
    },
  };

  /** Le bot saute s'il pousse contre un bloc (vitesse presque nulle alors qu'il veut avancer). */
  function contactsBlocked(b: { v: Vec3; grounded: boolean }, mx: number, mz: number): boolean {
    return b.grounded && (mx !== 0 || mz !== 0) && Math.hypot(b.v[0], b.v[2]) < 1;
  }
}

export const mortarServer: ServerGameModule = { create };
