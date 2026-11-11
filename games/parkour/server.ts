// Parcours délirant — autorité serveur : checkpoints, arrivées, chrono, classement, bots.
import type { RoundResult, ServerCtx, ServerGame, ServerGameModule, ServerPlayer } from '../../shared/src/game-api';
import { PHYS, clearMotionState, groundBelow, jostle, jumpHeight, jumpReach, stepBody, type Body, type Collider, type Vec3 } from '../../shared/src/physics';
import { FLAG, poseFlags } from '../../shared/src/protocol';
import {
  blinkState, boxReady, bubbleParts, buildColliders, gatePart, leverDown, levelKillY, linkOpen, lowgravAt, memoryKey, memoryTilesUnder, memoryTiles, newLevelState, onPad,
  rampTopAt, standsOn, topOf, touches, type El, type ElementType, type Level,
} from '../../shared/src/level';
import { validateLevel } from '../../shared/src/level-validate';
import { listLevels, readLevel } from '../../shared/src/level-store';
import { ranksFromGroups } from '../../shared/src/scoring';
import { ITEM, ITEMS, formatTime, memoryLayout, parkourPostStep, parkourPreStep, type ItemKind, type ParkourInit } from './shared';

interface Progress {
  cp: number; finishedAt: number; lastHit: number;
  coins: Set<number>; // pièces ramassées
  item: ItemKind | null; // objet tenu
  shieldUntil: number; // bouclier actif jusqu'à (horloge serveur)
  lastKilled: number; // dernier relais de mort (anti-spam)
}
interface Bot {
  pathIdx: number; stuck: number; pace: number; waitUntil: number;
  detour: number; detourUntil: number; // élément visité hors chemin (bouton, levier, boîte, pièce), -1 sinon
  memTile: number; // dalle mémoire visée (memoryKey), -1 sinon
  useAt: number; // instant prévu pour utiliser l'objet tenu
  tempted: Set<number>; // leviers / pièces / boîtes déjà envisagés
}
interface Banana { p: Vec3; armAt: number; until: number }

let lastLevel = '';

/** Cibles sans surface : on y entre (ventilateur) ou elles nous emportent (canon, téléporteur, tyrolienne). */
const ZONE_TARGETS: ReadonlySet<ElementType> = new Set(['fan', 'launcher', 'teleport', 'zipline', 'lever', 'itembox', 'coin']);

function create(ctx: ServerCtx): ServerGame {
  let level: Level;
  let cps: number[] = [];
  let finishes: number[] = [];
  let startIdx = 0;
  let endAt = 0;
  let killY = -20;
  let path: number[] = [];
  const prog = new Map<string, Progress>();
  const bots = new Map<string, Bot>();
  const st = newLevelState(); // portes, leviers, dalles mémoire, boîtes, bananes, dalles friables
  const crumbled = st.crumbled;
  const traps = new Map<number, boolean[]>(); // grilles mémoire : dalles piégées (secret serveur)
  const bananas = new Map<number, Banana>();
  let nextBanana = 1;
  const byType = (ty: ElementType) => level.elements.map((e, i) => (e.type === ty ? i : -1)).filter((i) => i >= 0);
  let buttons: number[] = [], levers: number[] = [], memories: number[] = [], boxes: number[] = [], coinEls: number[] = [];
  let finishedCount = 0;
  let cols: Collider[] = [];
  let colsAt = -1;

  let solid: Collider[] = []; // sans les `hazard` : les bots ne prennent pas la lave pour un sol
  const colliders = () => {
    const t = ctx.now();
    if (t !== colsAt) { cols = buildColliders(level, t, st); solid = cols.filter((c) => c.tag !== 'hazard'); colsAt = t; }
    return cols;
  };

  /** Boîte visée par un bot sur l'élément i (plusieurs boîtes : nacelles, dalles… → la plus proche, position anticipée). */
  function targetBox(i: number, b: Body, cs: Collider[]): Collider | undefined {
    const e = level.elements[i];
    let best: Collider | undefined, bestD = Infinity;
    // bulles : on ignore celles qui vont éclater ou qui seront trop hautes à l'atterrissage
    const cands: Collider[] = e.type === 'bubble'
      ? bubbleParts(e, ctx.now() + 0.45).filter((p) => p.left > 1.3 && p.c[1] + p.h[1] <= b.p[1] + jumpHeight() * 0.8).map((p) => ({ id: i, c: p.c, h: p.h, yaw: p.yaw }))
      : cs;
    for (const c of cands) {
      if (c.id !== i) continue;
      let cc = c;
      if (e.type === 'ferris') {
        // nacelle : on vise où elle sera à l'atterrissage
        const v = c.vel ?? [0, 0, 0], lead = 0.45;
        cc = { ...c, c: [c.c[0] + v[0] * lead, c.c[1] + v[1] * lead, c.c[2] + v[2] * lead] };
        if (cc.c[1] + cc.h[1] > b.p[1] + jumpHeight() * 0.8) continue;
      }
      if (e.type !== 'ferris' && e.type !== 'pistons' && e.type !== 'bubble') return cc;
      const d = Math.hypot(Math.max(0, Math.abs(cc.c[0] - b.p[0]) - cc.h[0]), Math.max(0, Math.abs(cc.c[2] - b.p[2]) - cc.h[2])) + Math.max(0, cc.c[1] + cc.h[1] - b.p[1]) * 0.5;
      if (d < bestD) { bestD = d; best = cc; }
    }
    return best;
  }

  /** La cible est-elle « prête » à recevoir un saut maintenant (dalle clignotante présente à l'atterrissage) ? */
  function targetReady(i: number): boolean {
    const e = level.elements[i], t = ctx.now();
    if (e.type === 'blink') return blinkState(e, t + 0.3).solid && blinkState(e, t + 1.1).solid;
    if (e.type === 'trapdoor') return !linkOpen(st, e.link, t);
    return true;
  }

  /**
   * Écart horizontal entre les pieds p et la surface visée : boîte dans son repère tourné (yaw), plateau tournant
   * traité comme son disque (apothème de l'octogone) quelle que soit la rotation de ses boîtes.
   */
  function targetGap(el: Level['elements'][number], col: Collider | undefined, p: Vec3): number {
    if (el.type === 'turntable') return Math.max(0, Math.hypot(p[0] - el.pos[0], p[2] - el.pos[2]) - 0.97 * (el.size[0] / 2));
    const c = col ? col.c : el.pos, yaw = col ? col.yaw : el.yaw;
    const hx = col ? col.h[0] : el.size[0] / 2, hz = col ? col.h[2] : el.size[2] / 2;
    const cos = Math.cos(yaw), sin = Math.sin(yaw), dx = p[0] - c[0], dz = p[2] - c[2];
    const lx = dx * cos - dz * sin, lz = dx * sin + dz * cos;
    return Math.hypot(Math.max(0, Math.abs(lx) - hx), Math.max(0, Math.abs(lz) - hz));
  }

  /** Le segment horizontal a → b traverse-t-il la boîte c élargie de m ? */
  function segHits(a: Vec3, b: Vec3, c: Collider, m: number): boolean {
    const cos = Math.cos(c.yaw), sin = Math.sin(c.yaw);
    const loc = (p: Vec3) => { const dx = p[0] - c.c[0], dz = p[2] - c.c[2]; return [dx * cos - dz * sin, dx * sin + dz * cos]; };
    const [ax, az] = loc(a), [bx, bz] = loc(b);
    let t0 = 0, t1 = 1;
    for (const [p0, d, h] of [[ax, bx - ax, c.h[0] + m], [az, bz - az, c.h[2] + m]]) {
      if (Math.abs(d) < 1e-9) { if (Math.abs(p0) > h) return false; continue; }
      let ta = (-h - p0) / d, tb = (h - p0) / d;
      if (ta > tb) [ta, tb] = [tb, ta];
      t0 = Math.max(t0, ta); t1 = Math.min(t1, tb);
      if (t0 > t1) return false;
    }
    return true;
  }

  /** Détours des bots : bouton / levier d'une porte fermée sur le trajet, puis boîtes, pièces et leviers proches accessibles à pied. */
  function updateDetour(b: Body, bot: Bot, pr: Progress, target: Vec3, cs: Collider[], t: number) {
    if (bot.detour >= 0) {
      const e = level.elements[bot.detour];
      const done = t > bot.detourUntil
        || (e.type === 'button' && linkOpen(st, e.link, t))
        || (e.type === 'lever' && leverDown(e, bot.detour, st, t))
        || (e.type === 'itembox' && (!!pr.item || !boxReady(bot.detour, st, t)))
        || (e.type === 'coin' && pr.coins.has(bot.detour));
      if (!done) return;
      bot.detour = -1;
    }
    if (!b.grounded) return;
    const near = (e: { pos: number[] }) => Math.hypot(e.pos[0] - b.p[0], e.pos[2] - b.p[2]);
    for (const c of cs) {
      if (c.tag !== 'door') continue;
      const e = level.elements[c.id] as El<'door'>;
      if (c.c[1] - c.h[1] > b.p[1] + 1.5 || c.c[1] + c.h[1] < b.p[1] + 0.2 || near({ pos: c.c }) > 8 + Math.max(c.h[0], c.h[2]) || !segHits(b.p, target, c, 0.5)) continue;
      let best = -1, bd = 30;
      for (const i of [...buttons, ...levers]) {
        const o = level.elements[i] as El<'button'> | El<'lever'>;
        if (o.link === e.link && near(o) < bd) { bd = near(o); best = i; }
      }
      if (best >= 0) { bot.detour = best; bot.detourUntil = t + 10; return; }
    }
    for (const i of [...boxes, ...coinEls, ...levers]) {
      const e = level.elements[i];
      if (bot.tempted.has(i) || near(e) > 6) continue;
      bot.tempted.add(i); // envisagé une seule fois
      const floor = groundBelow(e.pos[0], b.p[1] + 1, e.pos[2], solid);
      if (Math.abs(floor - b.p[1]) > 0.4 || e.pos[1] - e.size[1] / 2 > b.p[1] + 1.4) continue; // pas accessible à pied
      const want = e.type === 'itembox' ? !pr.item && boxReady(i, st, t) && Math.random() < 0.8
        : e.type === 'coin' ? !pr.coins.has(i) && Math.random() < 0.9
        : e.type === 'lever' && !leverDown(e, i, st, t) && Math.random() < 0.35;
      if (want) { bot.detour = i; bot.detourUntil = t + 6; return; }
    }
  }

  /** Grille mémoire : dalle visée dans la rangée suivante (sûres connues d'abord, sinon au hasard ; jamais une tombée). */
  function memoryTarget(b: Body, bot: Bot, pathI: number): Collider | undefined {
    const g = b.grounded ? level.elements[b.groundId] : undefined;
    const i = g?.type === 'memory' ? b.groundId : level.elements[pathI].type === 'memory' ? pathI : -1;
    if (i < 0) { bot.memTile = -1; return undefined; }
    const e = level.elements[i] as El<'memory'>;
    const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw), dx = b.p[0] - e.pos[0], dz = b.p[2] - e.pos[2];
    const pw = e.size[0] / e.cols, pd = e.size[2] / e.rows;
    const clampI = (x: number, n: number) => Math.max(0, Math.min(n - 1, x));
    const col = clampI(Math.floor((dx * cos - dz * sin + e.size[0] / 2) / pw), e.cols);
    const row = g?.type === 'memory' ? clampI(Math.floor((dx * sin + dz * cos + e.size[2] / 2) / pd), e.rows) : -1;
    if (row >= e.rows - 1) { bot.memTile = -1; return undefined; } // dernière rangée : on poursuit le chemin
    const fallen = (k: number) => st.tiles.has(memoryKey(i, k));
    const cur = row * e.cols + col;
    const kOld = bot.memTile - i * 1024;
    const keep = bot.memTile >= 0 && Math.floor(bot.memTile / 1024) === i && kOld !== cur && !fallen(kOld) && Math.floor(kOld / e.cols) >= row;
    if (!keep) {
      const pick = (r: number, ok: (c: number) => boolean) => {
        const all: number[] = [];
        for (let c = 0; c < e.cols; c++) if (ok(c) && !fallen(r * e.cols + c)) all.push(r * e.cols + c);
        const safe = all.filter((k) => st.safe.has(memoryKey(i, k)));
        const from = safe.length ? safe : all;
        return from.length ? from[Math.floor(Math.random() * from.length)] : -1;
      };
      let k = pick(row + 1, (c) => row < 0 || Math.abs(c - col) <= 1);
      if (k < 0 && row >= 0) k = pick(row, (c) => Math.abs(c - col) === 1); // pas de côté
      if (k < 0) { bot.memTile = -1; return undefined; }
      bot.memTile = memoryKey(i, k);
    }
    const p = memoryTiles(e)[bot.memTile - i * 1024];
    return { id: i, c: p.c, h: p.h, yaw: p.yaw };
  }

  /** Secondes avant que la barre tournante `c` passe sur le point p (barre symétrique : demi-tour). */
  function barEta(c: Collider, p: Vec3): number {
    const sx = p[0] - c.c[0], sz = p[2] - c.c[2], PI = Math.PI;
    const delta = (((Math.atan2(-sz, sx) - c.yaw) % PI) + PI) % PI; // angle entre la barre et le point
    return (c.angVel! > 0 ? delta : PI - delta) / Math.abs(c.angVel!);
  }

  function spawnAt(elIdx: number, k: number, n: number): Vec3 {
    const e = level.elements[elIdx];
    const perRow = Math.max(1, Math.ceil(Math.sqrt(n)));
    const sx = Math.min(1.4, (e.size[0] - 1.5) / perRow), sz = Math.min(1.4, (e.size[2] - 1.5) / perRow);
    const col = k % perRow, row = Math.floor(k / perRow);
    return [e.pos[0] + (col - (perRow - 1) / 2) * sx, topOf(e) + 0.05, e.pos[2] + (row - (perRow - 1) / 2) * sz];
  }

  function respawnPoint(cp: number): Vec3 {
    const e = level.elements[cp < 0 ? startIdx : cps[cp]];
    return [e.pos[0] + (Math.random() - 0.5) * 1.5, topOf(e) + 0.1, e.pos[2] + (Math.random() - 0.5) * 1.5];
  }

  function respawnBot(b: Body, bot: Bot, pr: Progress) {
    b.p = respawnPoint(pr.cp); b.v = [0, 0, 0]; b.tumble = 0;
    clearMotionState(b);
    bot.pathIdx = Math.max(0, path.indexOf(pr.cp < 0 ? startIdx : cps[pr.cp]));
    bot.stuck = 0;
    // hésitation aléatoire : évite de retomber indéfiniment dans le même obstacle au même moment du cycle
    bot.waitUntil = ctx.now() + Math.random() * 1.5;
    bot.pace = 0.7 + Math.random() * 0.3;
  }

  function crumble(i: number) {
    const e = level.elements[i];
    if (!e || e.type !== 'crumble') return;
    const at = crumbled.get(i), t = ctx.now();
    if (at !== undefined && t < at + e.delay + e.respawn) return;
    crumbled.set(i, t);
    ctx.broadcast({ t: 'crumble', i, at: t });
  }

  function cosmeticHit(id: string) {
    const pr = prog.get(id);
    if (!pr || ctx.now() - pr.lastHit < 0.8) return;
    pr.lastHit = ctx.now();
    const a = Math.random() * Math.PI * 2;
    ctx.damage(id, { pos: [Math.sin(a) * 0.3, 0.55 + Math.random() * 0.7, Math.cos(a) * 0.3], r: 0.14 + Math.random() * 0.08 });
  }

  /** Mort dans un hazard : relayée à tous pour l'effet lave / eau / acide (au plus 2 par seconde et par joueur). */
  function relayKilled(id: string, i: number) {
    const pr = prog.get(id), pl = ctx.players.get(id), t = ctx.now();
    if (!pr || !pl || t - pr.lastKilled < 0.5) return;
    pr.lastKilled = t;
    ctx.broadcast({ t: 'killed', id, i, p: [pl.p[0], pl.p[1], pl.p[2]] });
  }

  // ———— vague 3 : interactions détectées sur les positions des joueurs (état 30 Hz), objets, pièces ————

  /** Ouvre `link` pendant `duration` s (prolonge une ouverture en cours) ; by = bouton / levier. */
  function openLink(link: string, duration: number, by: number) {
    const t = ctx.now(), s = st.links.get(link);
    const live = !!s && t < s.until;
    if (live && s!.until - t > duration - 0.5) return; // déjà ouvert pour (presque) toute la durée : pas de spam
    const at = live ? s!.at : t, until = Math.max(live ? s!.until : 0, t + duration);
    st.links.set(link, { at, until });
    ctx.broadcast({ t: 'open', link, at, until, by });
  }

  function pullLever(i: number) {
    const e = level.elements[i] as El<'lever'>, t = ctx.now();
    if (leverDown(e, i, st, t)) return;
    st.levers.set(i, t);
    ctx.broadcast({ t: 'lever', i, at: t });
    openLink(e.link, e.duration, i);
  }

  /** Un joueur se pose sur la dalle k de la grille i : piégée → elle tombe pour tous ; sûre → révélée. */
  function stepTile(i: number, k: number) {
    const key = memoryKey(i, k), t = ctx.now();
    if (st.tiles.has(key)) return;
    if (traps.get(i)?.[k]) { st.tiles.set(key, t); ctx.broadcast({ t: 'tile', i, k, at: t }); }
    else if (!st.safe.has(key)) { st.safe.add(key); ctx.broadcast({ t: 'safe', i, k }); }
  }

  const shielded = (id: string) => (prog.get(id)?.shieldUntil ?? 0) > ctx.now();

  function giveItem(id: string, pr: Progress, kind: ItemKind | null) {
    pr.item = kind;
    ctx.broadcast({ t: 'item', id, kind });
    const bot = bots.get(id);
    if (bot && kind) bot.useAt = ctx.now() + 1 + Math.random() * 4;
  }

  /** Utilisation de l'objet tenu (message { t: 'use' } ou bot). */
  function useItem(id: string) {
    const pr = prog.get(id), pl = ctx.players.get(id), t = ctx.now();
    if (!pr || !pl || !pr.item || pr.finishedAt >= 0) return;
    const kind = pr.item;
    const fx = Math.sin(pl.yaw), fz = Math.cos(pl.yaw);
    // banane : posée au sol derrière soi ; pas de sol (vide, lave) à moins de 6 m sous les pieds → on la garde
    let bananaAt: Vec3 | null = null;
    if (kind === 'banana') {
      const bx = pl.p[0] - fx * ITEM.bananaBack, bz = pl.p[2] - fz * ITEM.bananaBack;
      colliders();
      const gy = groundBelow(bx, pl.p[1] + 0.5, bz, solid);
      if (gy < pl.p[1] - 6) return;
      bananaAt = [bx, gy, bz];
    }
    giveItem(id, pr, null);
    if (kind === 'super' || kind === 'shield') {
      const dur = kind === 'super' ? ITEM.superTime : ITEM.shieldTime, until = t + dur;
      if (kind === 'shield') pr.shieldUntil = until;
      if (pl.body) { if (kind === 'super') pl.body.superJump = dur; else pl.body.shield = dur; }
      ctx.broadcast({ t: 'effect', id, kind, until });
    } else if (kind === 'banana') {
      const k = nextBanana++, p = bananaAt!;
      bananas.set(k, { p, armAt: t + ITEM.bananaArm, until: t + ITEM.bananaLife });
      st.bananas.set(k, p);
      ctx.broadcast({ t: 'banana', k, p });
    } else {
      // gant de boxe : repousse les joueurs proches devant soi
      const hit: string[] = [];
      for (const q of ctx.players.values()) {
        if (q.id === id || !prog.has(q.id)) continue; // joueurs partis : ignorés
        const dx = q.p[0] - pl.p[0], dz = q.p[2] - pl.p[2], d = Math.hypot(dx, dz);
        if (d > ITEM.gloveRange || d < 0.01 || Math.abs(q.p[1] - pl.p[1]) > 1.6 || (dx * fx + dz * fz) / d < ITEM.gloveDot || shielded(q.id)) continue;
        ctx.impulse(q.id, [(dx / d) * ITEM.gloveV, ITEM.gloveUp, (dz / d) * ITEM.gloveV], ITEM.gloveTumble);
        hit.push(q.id);
      }
      ctx.broadcast({ t: 'glove', id, hit });
    }
  }

  /** Bananes : le premier qui passe dessus (une fois armée) glisse en roulé-boulé ; le bouclier protège mais l'écrase. */
  function bananaTick(t: number) {
    for (const [k, bn] of bananas) {
      let by = '';
      if (t >= bn.until) by = '-';
      else if (t >= bn.armAt) {
        for (const q of ctx.players.values()) {
          if (!prog.has(q.id)) continue;
          if (Math.hypot(q.p[0] - bn.p[0], q.p[2] - bn.p[2]) > ITEM.bananaR || Math.abs(q.p[1] - bn.p[1]) > 0.6) continue;
          by = q.id;
          if (!shielded(q.id)) {
            const sp = Math.hypot(q.v[0], q.v[2]);
            const dx = sp > 1 ? q.v[0] / sp : Math.sin(q.yaw), dz = sp > 1 ? q.v[2] / sp : Math.cos(q.yaw);
            ctx.impulse(q.id, [dx * ITEM.slipSpeed, ITEM.slipUp, dz * ITEM.slipSpeed], ITEM.slipTumble);
          }
          break;
        }
      }
      if (!by) continue;
      bananas.delete(k);
      st.bananas.delete(k);
      ctx.broadcast({ t: 'bananaGone', k, by: by === '-' ? '' : by });
    }
  }

  /** Boutons, leviers, dalles mémoire, boîtes surprise et pièces touchés par le joueur p (positions de l'état réseau). */
  function interactions(p: ServerPlayer, pr: Progress, t: number) {
    const grounded = (p.flags & FLAG.grounded) !== 0;
    for (const i of buttons) {
      const e = level.elements[i] as El<'button'>;
      if (grounded && standsOn(e, p.p)) openLink(e.link, e.duration, i);
    }
    for (const i of levers) if (touches(level.elements[i], p.p)) pullLever(i);
    for (const i of memories) {
      const e = level.elements[i] as El<'memory'>;
      if (!grounded || !standsOn(e, p.p)) continue;
      // joint compris : les dalles qui portent la capsule (piégée → tombe, sûre → révélée)
      for (const k of memoryTilesUnder(e, p.p)) stepTile(i, k);
    }
    for (const i of boxes) {
      const e = level.elements[i] as El<'itembox'>;
      if (pr.item || !boxReady(i, st, t) || !touches(e, p.p)) continue;
      st.boxes.set(i, t + e.respawn);
      ctx.broadcast({ t: 'box', i, until: t + e.respawn, id: p.id });
      giveItem(p.id, pr, ITEMS[Math.floor(Math.random() * ITEMS.length)]);
    }
    for (const i of coinEls) {
      if (pr.coins.has(i) || !touches(level.elements[i], p.p)) continue;
      pr.coins.add(i);
      ctx.broadcast({ t: 'coin', id: p.id, i, n: pr.coins.size });
    }
  }

  return {
    onStart() {
      const available = listLevels();
      const allowed = (ctx.settings.levels as string[]).filter((n) => available.includes(n));
      let pool = allowed.length ? allowed : available;
      // seuls les niveaux terminables sont proposés
      pool = pool.filter((n) => { try { return validateLevel(readLevel(n)).ok; } catch { return false; } });
      if (!pool.length) throw new Error('Aucun niveau de parcours valide dans levels/parkour.');
      const fresh = pool.filter((n) => n !== lastLevel);
      const name = (fresh.length ? fresh : pool)[Math.floor(Math.random() * (fresh.length || pool.length))];
      lastLevel = name;
      level = readLevel(name);
      path = validateLevel(level).path;
      level.elements.forEach((e, i) => {
        if (e.type === 'checkpoint') cps.push(i);
        if (e.type === 'finish') finishes.push(i);
        if (e.type === 'start') startIdx = i;
      });
      killY = levelKillY(level);
      endAt = ctx.startAt + ctx.settings.duration;
      buttons = byType('button'); levers = byType('lever'); memories = byType('memory'); boxes = byType('itembox'); coinEls = byType('coin');
      for (const i of memories) { const e = level.elements[i] as El<'memory'>; traps.set(i, memoryLayout(e.cols, e.rows, e.traps)); }
      const spawns: Record<string, Vec3> = {};
      let k = 0;
      for (const p of ctx.players.values()) {
        spawns[p.id] = spawnAt(startIdx, k++, ctx.players.size);
        prog.set(p.id, { cp: -1, finishedAt: -1, lastHit: 0, coins: new Set(), item: null, shieldUntil: 0, lastKilled: 0 });
        if (p.isBot) bots.set(p.id, { pathIdx: 0, stuck: 0, pace: 0.7 + Math.random() * 0.3, waitUntil: ctx.startAt + Math.random() * 0.8, detour: -1, detourUntil: 0, memTile: -1, useAt: 0, tempted: new Set() });
      }
      const init: ParkourInit = { level, endAt, cps, jostle: ctx.settings.jostle !== false, coins: ctx.settings.coins !== false };
      return { init, spawns };
    },

    onTick() {
      const t = ctx.now();
      if (t < ctx.startAt) return;
      bananaTick(t);
      for (const p of ctx.players.values()) {
        const pr = prog.get(p.id);
        if (!pr || pr.finishedAt >= 0) continue;
        interactions(p, pr, t);
        for (let k = cps.length - 1; k > pr.cp; k--) {
          if (onPad(level.elements[cps[k]], p.p)) {
            pr.cp = k;
            ctx.broadcast({ t: 'cp', id: p.id, k });
            break;
          }
        }
        if (finishes.some((f) => onPad(level.elements[f], p.p))) {
          pr.finishedAt = t - ctx.startAt;
          finishedCount++;
          ctx.broadcast({ t: 'finish', id: p.id, time: pr.finishedAt, place: finishedCount });
          if (finishedCount === 1 && endAt - t > ctx.settings.hurry) {
            endAt = t + ctx.settings.hurry;
            ctx.broadcast({ t: 'hurry', endAt });
          }
        }
      }
      if (t >= endAt || (prog.size > 0 && finishedCount >= prog.size)) ctx.end();
    },

    onPlayerMessage(id, msg) {
      if (msg?.t === 'crumble' && Number.isInteger(msg.i)) crumble(msg.i);
      else if (msg?.t === 'hit') cosmeticHit(id);
      else if (msg?.t === 'use') useItem(id);
      else if (msg?.t === 'killed' && Number.isInteger(msg.i) && level.elements[msg.i]?.type === 'hazard') relayKilled(id, msg.i);
    },

    onPlayerLeave(id) {
      const pr = prog.get(id);
      if (pr && pr.finishedAt >= 0) finishedCount--;
      prog.delete(id);
      bots.delete(id);
    },

    getResults(): RoundResult[] {
      const targets = [...cps, finishes[0]];
      const rows = [...prog.entries()].map(([id, pr]) => {
        const p = ctx.players.get(id);
        const tgt = level.elements[targets[Math.min(pr.cp + 1, targets.length - 1)]];
        const dist = p ? Math.hypot(p.p[0] - tgt.pos[0], p.p[1] - tgt.pos[1], p.p[2] - tgt.pos[2]) : 1e9;
        return { id, pr, dist };
      });
      // pièces : départagent les temps égaux (au dixième affiché) et les checkpoints égaux, si le réglage le veut
      const coinRank = ctx.settings.coins !== false ? (a: typeof rows[0], b: typeof rows[0]) => b.pr.coins.size - a.pr.coins.size : () => 0;
      const tenth = (s: number) => Math.round(s * 10);
      const done = rows.filter((r) => r.pr.finishedAt >= 0).sort((a, b) => tenth(a.pr.finishedAt) - tenth(b.pr.finishedAt) || coinRank(a, b) || a.pr.finishedAt - b.pr.finishedAt);
      const rest = rows.filter((r) => r.pr.finishedAt < 0).sort((a, b) => b.pr.cp - a.pr.cp || coinRank(a, b) || a.dist - b.dist);
      const withCoins = (label: string, n: number) => (n ? `${label} · ${n} pièce${n > 1 ? 's' : ''}` : label);
      return ranksFromGroups([
        ...done.map((r) => [{ id: r.id, label: withCoins(formatTime(r.pr.finishedAt), r.pr.coins.size) }]),
        ...rest.map((r) => [{ id: r.id, label: withCoins(r.pr.cp >= 0 ? `Checkpoint ${r.pr.cp + 1}/${cps.length}` : 'Pas arrivé', r.pr.coins.size) }]),
      ]);
    },

    // Bot : suit le chemin calculé par la validation, saute au bord des plateformes, attend les plateformes mobiles.
    botTick(pl: ServerPlayer, dt: number) {
      const b = pl.body, bot = bots.get(pl.id), pr = prog.get(pl.id);
      if (!b || !bot || !pr) return;
      const cs = colliders(), t = ctx.now();
      let mx = 0, mz = 0, jump = false;
      if (b.zip >= 0) {
        // suspendu à une tyrolienne : on se laisse porter jusqu'au bout (sauter ferait lâcher)
        const at = path.indexOf(b.zip, bot.pathIdx);
        if (at > bot.pathIdx) bot.pathIdx = at;
        bot.stuck = 0;
      } else if (pr.finishedAt < 0 && t > bot.waitUntil) {
        // recale la progression si on se tient sur un élément plus loin sur le chemin
        if (b.grounded) {
          const at = path.indexOf(b.groundId, bot.pathIdx);
          if (at > bot.pathIdx) { bot.pathIdx = at; bot.stuck = 0; }
        }
        const pathI = path[Math.min(bot.pathIdx + 1, path.length - 1)];
        // détour (bouton d'une porte fermée, boîte, pièce, levier), sinon dalle mémoire, sinon la suite du chemin
        updateDetour(b, bot, pr, level.elements[pathI].pos as Vec3, cs, t);
        const memCol = bot.detour < 0 ? memoryTarget(b, bot, pathI) : undefined;
        const nextI = bot.detour >= 0 ? bot.detour : memCol ? memCol.id : pathI;
        const el = level.elements[nextI];
        const col = memCol ?? targetBox(nextI, b, cs);
        const onMem = !!memCol;
        const multi = el.type === 'ferris' || el.type === 'pistons' || el.type === 'bubble';
        const zone = ZONE_TARGETS.has(el.type);
        const tc = col ? col.c : el.pos;
        let top = zone ? b.p[1] : (col ? col.c[1] + col.h[1] : topOf(el));
        if (el.type === 'ramp') top = rampTopAt(el, b.p[0], b.p[2]); // hauteur du bord de rampe le plus proche
        if (el.type === 'fan' && Math.abs(b.p[0] - el.pos[0]) < el.size[0] / 2 && Math.abs(b.p[2] - el.pos[2]) < el.size[2] / 2 && b.p[1] > el.pos[1] + el.size[1] / 2 - 2) bot.pathIdx++;
        const dx = tc[0] - b.p[0], dz = tc[2] - b.p[2];
        const d = Math.hypot(dx, dz) || 1;
        const ux = dx / d, uz = dz / d;
        const gapToTarget = targetGap(el, col, b.p);
        // arrivé au-dessus de la cible sans s'y être posé (ex. debout sur une barre tournante) : on passe à la suite
        if (!zone && !onMem && bot.detour < 0 && b.grounded && gapToTarget === 0 && b.p[1] >= top - 0.1 && bot.pathIdx + 1 < path.length - 1) { bot.pathIdx++; bot.stuck = 0; }
        // la lave n'est pas un sol : on saute par-dessus comme au-dessus du vide
        const edge = groundBelow(b.p[0] + ux * 0.8, b.p[1], b.p[2] + uz * 0.8, solid) < b.p[1] - 0.5;
        // portée du saut selon le sol (boue, gélatine), l'élan d'un speed pad et la gravité locale (zone lunaire)
        const runSpeed = b.boost > 0 ? Math.max(PHYS.speed * b.slow, Math.hypot(b.v[0], b.v[2])) : PHYS.speed * b.slow;
        let v0 = PHYS.jumpV * b.jumpK;
        if (b.superJump > 0) v0 *= PHYS.superJump;
        const reach = jumpReach(top - b.p[1], v0, runSpeed, PHYS.gravity * lowgravAt(level, b.p));
        const ready = targetReady(nextI) && (!multi || col !== undefined);
        // sur une bulle on attend d'être presque à hauteur de la cible : le saut part sans élan
        const riding = b.grounded && level.elements[b.groundId]?.type === 'bubble' && top - b.p[1] > 0.3;
        const feasible = zone || (ready && !riding && reach >= 0 && gapToTarget <= reach * 0.82);
        let waiting = false;
        if (d > 0.4) { mx = ux * bot.pace; mz = uz * bot.pace; }
        // perché sur une barre tournante (spinner, barre basse d'un balayeur) : ce n'est pas un bord où attendre, on en descend
        const groundEl = b.grounded ? level.elements[b.groundId] : undefined;
        const onBar = groundEl?.type === 'spinner' || groundEl?.type === 'sweeper';
        if (b.grounded && edge && !(onBar && !feasible)) {
          if (feasible) jump = true;
          else { mx = 0; mz = 0; waiting = true; } // cible mobile trop loin / dalle absente : on attend au bord
        } else if (b.grounded && top > b.p[1] + 0.25 && gapToTarget < 1.5 && ready) jump = true;
        // grille mémoire : on marche de dalle en dalle (un saut pourrait atterrir deux rangées plus loin)
        if (onMem && gapToTarget < 0.6) { jump = false; if (d > 0.4) { mx = ux * bot.pace; mz = uz * bot.pace; } waiting = false; }
        // tyrolienne trop haute pour l'attraper en marchant dessous : on saute
        if (el.type === 'zipline' && b.grounded && d < 1.2 && el.pos[1] - PHYS.zipHang - b.p[1] > 0.6) jump = true;
        const ground = b.grounded ? level.elements[b.groundId] : undefined;
        // pistons : on grimpe sur la dalle voisine si elle est plus haute
        if (b.grounded && !jump && (ground?.type === 'pistons' || el.type === 'pistons')) {
          if (groundBelow(b.p[0] + ux * 0.7, b.p[1] + 1.1, b.p[2] + uz * 0.7, solid) > b.p[1] + 0.3) jump = true;
        }
        // guillotine devant nous : on attend qu'elle soit levée et qu'il reste le temps de passer dessous
        for (const c of cs) {
          if (c.tag !== 'gate') continue;
          const g = level.elements[c.id];
          if (g.type !== 'gate' || g.pos[1] - g.drop - g.size[1] / 2 > b.p[1] + 1.7 || g.pos[1] + g.size[1] / 2 < b.p[1]) continue;
          const cos = Math.cos(c.yaw), sin = Math.sin(c.yaw), gx = b.p[0] - c.c[0], gz = b.p[2] - c.c[2];
          const lx = gx * cos - gz * sin, lz = gx * sin + gz * cos;
          if (Math.abs(lx) > c.h[0] + 0.5 || Math.abs(lz) > c.h[2] + 1.6 || Math.abs(lz) < c.h[2] + 0.45) continue; // loin, ou déjà dessous : on fonce
          const clear = c.c[1] - c.h[1] > b.p[1] + 1.7 && gatePart(g, t).untilFall > 0.9;
          if (!clear && ux * -gx + uz * -gz > 0) { mx = 0; mz = 0; jump = false; waiting = true; }
        }
        // barres tournantes (spinner, barre basse du balayeur) sur le point de nous faucher : on saute par-dessus ;
        // barre haute du balayeur qui arrive : surtout pas de saut
        let barJump = false, noJump = false;
        for (const c of cs) {
          if ((c.tag !== 'spinner' && c.tag !== 'sweeper') || !c.angVel || !b.grounded || b.groundId === c.id) continue;
          if (Math.hypot(b.p[0] - c.c[0], b.p[2] - c.c[2]) > c.h[0] + 0.6) continue;
          const lo = c.c[1] - c.h[1], hi = c.c[1] + c.h[1];
          if (hi >= b.p[1] && lo <= b.p[1] + 1.2) { if (barEta(c, b.p) < 0.3) barJump = true; }
          else if (c.tag === 'sweeper' && lo > b.p[1] + 1.2 && lo < b.p[1] + jumpHeight() + PHYS.height + 0.3 && barEta(c, b.p) < 0.9) noJump = true;
        }
        if (barJump) jump = true;
        else if (noJump && jump) { jump = false; if (edge) { mx = 0; mz = 0; waiting = true; } }
        // rouleau : on compense son entraînement pour garder le cap
        if (ground?.type === 'roller' && (mx || mz)) {
          let ix = mx * PHYS.speed - Math.sin(ground.yaw) * ground.speed, iz = mz * PHYS.speed - Math.cos(ground.yaw) * ground.speed;
          const n = Math.hypot(ix, iz) / PHYS.speed;
          if (n > 1) { ix /= n; iz /= n; }
          mx = ix / PHYS.speed; mz = iz / PHYS.speed;
        }
        bot.stuck += waiting ? dt * 0.25 : dt; // attendre une nacelle / une dalle n'est pas être coincé
        if (bot.stuck > 9) respawnBot(b, bot, pr);
      }
      const pre = parkourPreStep(level, b, dt, t);
      // canon, téléporteur, tyrolienne : on est emporté vers la suite du chemin
      for (const i of [pre.launched, pre.teleported, pre.grabbed]) {
        if (i < 0) continue;
        const at = path.indexOf(i, bot.pathIdx);
        if (at > bot.pathIdx) { bot.pathIdx = at; bot.stuck = 0; }
      }
      if (b.zip >= 0) { mx = 0; mz = 0; jump = false; }
      const contacts = stepBody(b, { mx, mz, jump }, cs, dt);
      // un trampoline ne « pose » jamais le bot : on avance sur le chemin dès le rebond
      for (const c of contacts) {
        if (!c.bounced) continue;
        const at = path.indexOf(c.id, bot.pathIdx);
        if (at > bot.pathIdx) { bot.pathIdx = at; bot.stuck = 0; }
      }
      const ev = parkourPostStep(b, contacts);
      if (ev.knocked) cosmeticHit(pl.id);
      for (const i of ev.crumble) crumble(i);
      if (ev.killed) relayKilled(pl.id, ev.hazard);
      if (ev.killed || b.p[1] < killY) respawnBot(b, bot, pr);
      // bousculades avec les autres joueurs (réglage de la manche)
      if (ctx.settings.jostle !== false) for (const q of ctx.players.values()) if (q.id !== pl.id && prog.has(q.id)) jostle(b, q.p, q.v);
      if (mx || mz) pl.yaw = Math.atan2(mx, mz);
      pl.flags = (b.grounded || b.coyote > 0 ? FLAG.grounded : 0) | (b.tumble > 0 ? FLAG.tumble : 0) | poseFlags(b);
      // objet tenu : utilisé au hasard (le gant attend une cible devant, 5 s au plus)
      if (pr.item && pr.finishedAt < 0 && t >= bot.useAt) {
        const fx = Math.sin(pl.yaw), fz = Math.cos(pl.yaw);
        const target = [...ctx.players.values()].some((q) => { const dx = q.p[0] - b.p[0], dz = q.p[2] - b.p[2], dd = Math.hypot(dx, dz); return q.id !== pl.id && prog.has(q.id) && dd < ITEM.gloveRange && dd > 0.01 && (dx * fx + dz * fz) / dd >= ITEM.gloveDot; });
        if (pr.item !== 'glove' || target || t > bot.useAt + 5) useItem(pl.id);
      }
    },
  };
}

export const parkourServer: ServerGameModule = {
  create,
  dynamicOptions: () => ({ levels: listLevels() }),
};
