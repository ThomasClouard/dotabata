// Vague 3 : bousculades, portes / trappes, dalles mémoire, objets, pièces, relais d'effets — logique serveur et fonctions partagées.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it, vi } from 'vitest';
import type { ServerCtx, ServerPlayer } from '../shared/src/game-api';
import {
  ElementSchema, LevelSchema, buildColliders, doorOpenness, elementCatalog, linkOpen, memoryKey, memoryTileAt, memoryTiles, memoryTilesUnder, newLevelState,
  type El, type LevelInput,
} from '../shared/src/level';
import { PHYS, jostle, jumpHeight, makeBody, stepBody, type Contact, type Vec3 } from '../shared/src/physics';
import { FLAG, poseFlags } from '../shared/src/protocol';
import { defaultGameSettings } from '../shared/src/scoring';
import { applyEffectMsg, applyLevelMsg, memoryLayout, parkourJostle, parkourMeta, parkourPostStep } from '../games/parkour/shared';
import { simulate } from './sim';

process.env.JEUX_LEVELS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures', 'parkour');
const { parkourServer } = await import('../games/parkour/server');
const { readLevel } = await import('../shared/src/level-store');
const { validateLevel } = await import('../shared/src/level-validate');

type V3 = [number, number, number];
const DT = 1 / 60;
const mk = (elements: LevelInput['elements']) => LevelSchema.parse({ name: 'test', elements });
const S = { type: 'start' as const, pos: [0, -0.5, -20] as V3, size: [8, 1, 8] as V3 };
const F = { type: 'finish' as const, pos: [0, -0.5, 40] as V3, size: [6, 1, 6] as V3 };

describe('vague 3 — schéma, catalogue, état de niveau', () => {
  it('chaque type est documenté ; défauts et bornes', () => {
    const types = ElementSchema.options.map((o) => o.shape.type.value);
    expect(elementCatalog().elements.map((e) => e.type).sort()).toEqual([...types].sort());
    const l = mk([S, { type: 'memory', pos: [0, 0, 0], size: [6, 1, 9] }, { type: 'lever', pos: [0, 0, 0], size: [1, 2, 1], link: 'a' }, F]);
    const m = l.elements[1] as El<'memory'>, lv = l.elements[2] as El<'lever'>;
    expect([m.cols, m.rows, m.gap, m.traps]).toEqual([3, 5, 0.25, 0.5]);
    expect([lv.duration, lv.cooldown]).toEqual([4, 8]);
    expect(ElementSchema.safeParse({ type: 'door', pos: [0, 0, 0], size: [1, 1, 1] }).success).toBe(false); // link requis
    expect(ElementSchema.safeParse({ type: 'memory', pos: [0, 0, 0], size: [1, 1, 1], cols: 9 }).success).toBe(false);
    expect(parkourMeta.settings.jostle).toEqual({ type: 'bool', label: 'Bousculades entre joueurs', default: true });
    expect(parkourMeta.settings.coins.type).toBe('bool');
  });

  it('portes et trappes s\'escamotent tant que leur lien est ouvert ; ancienne signature (Map des dalles friables) conservée', () => {
    const l = mk([S, { type: 'door', pos: [0, 1, 0], size: [4, 2, 0.5], link: 'a' }, { type: 'trapdoor', pos: [0, -0.5, 5], size: [3, 1, 3], link: 'b' }, { type: 'crumble', pos: [0, -0.5, 10], size: [3, 1, 3] }, F]);
    const st = newLevelState();
    const ids = (t: number) => buildColliders(l, t, st).map((c) => c.id);
    expect(ids(1)).toEqual([0, 1, 2, 3, 4]);
    st.links.set('a', { at: 2, until: 5 });
    expect(ids(1.9)).toContain(1);
    expect(ids(2)).not.toContain(1);
    expect(ids(4.9)).toEqual([0, 2, 3, 4]);
    expect(ids(5)).toContain(1);
    expect(linkOpen(st, 'a', 3)).toBe(true);
    expect(linkOpen(st, 'b', 3)).toBe(false);
    const door = l.elements[1] as El<'door'>;
    expect(doorOpenness(door, st, 2.15)).toBeCloseTo(0.5, 9);
    expect(doorOpenness(door, st, 4)).toBe(1);
    expect(doorOpenness(door, st, 5.15)).toBeCloseTo(0.5, 9);
    expect(doorOpenness(door, st, 9)).toBe(0);
    st.crumbled.set(3, 0);
    expect(ids(1)).not.toContain(3);
    expect(buildColliders(l, 1, new Map([[3, 0]])).map((c) => c.id)).not.toContain(3);
  });

  it('dalles mémoire : géométrie, dalle sous les pieds, dalles tombées retirées des collisions', () => {
    const l = mk([S, { type: 'memory', pos: [0, -0.5, 0], size: [6, 1, 8], yaw: 0, cols: 3, rows: 4, gap: 0.2 }, F]);
    const e = l.elements[1] as El<'memory'>;
    const ts = memoryTiles(e);
    expect(ts.length).toBe(12);
    expect(ts[0].c).toEqual([-2, -0.5, -3]);
    expect(ts[5].c).toEqual([2, -0.5, -1]);
    expect(ts[0].h[0]).toBeCloseTo(0.9, 9);
    expect(memoryTileAt(e, [2, 0, -1])).toBe(5);
    expect(memoryTileAt(e, [1, 0, -1])).toBe(-1); // dans le joint
    expect(memoryTileAt(e, [0, 0, 5])).toBe(-1);
    const st = newLevelState();
    st.tiles.set(memoryKey(1, 5), 3);
    expect(buildColliders(l, 2, st).filter((c) => c.id === 1).length).toBe(12);
    expect(buildColliders(l, 3, st).filter((c) => c.id === 1).length).toBe(11);
    // un chemin sûr existe toujours (une dalle par rangée, colonnes voisines)
    let seed = 7;
    const rnd = () => { seed = (seed * 48271) % 2147483647; return seed / 2147483647; };
    for (let n = 0; n < 300; n++) {
      const cols = 2 + (n % 7), rows = 2 + (n % 11), trap = memoryLayout(cols, rows, 0.9, rnd);
      let reach = new Set<number>([...Array(cols).keys()].filter((c) => !trap[c]));
      for (let r = 1; r < rows; r++) {
        const next = new Set<number>();
        for (const c of reach) for (const d of [-1, 0, 1]) if (c + d >= 0 && c + d < cols && !trap[r * cols + c + d]) next.add(c + d);
        reach = next;
      }
      expect(reach.size, `grille ${cols}×${rows}`).toBeGreaterThan(0);
    }
  });

  it('applyLevelMsg / applyEffectMsg reconstruisent l\'état d\'un client', () => {
    const st = newLevelState(), b = makeBody([0, 0, 0]);
    expect(applyLevelMsg(st, { t: 'open', link: 'a', at: 1, until: 4, by: 3 }, 'p1')).toBe(true);
    applyLevelMsg(st, { t: 'tile', i: 2, k: 4, at: 5 }, 'p1');
    applyLevelMsg(st, { t: 'safe', i: 2, k: 1 }, 'p1');
    applyLevelMsg(st, { t: 'coin', id: 'p2', i: 7, n: 1 }, 'p1');
    applyLevelMsg(st, { t: 'coin', id: 'p1', i: 8, n: 1 }, 'p1');
    applyLevelMsg(st, { t: 'banana', k: 1, p: [1, 2, 3] }, 'p1');
    applyLevelMsg(st, { t: 'box', i: 9, until: 12, id: 'p2' }, 'p1');
    applyLevelMsg(st, { t: 'crumble', i: 6, at: 2 }, 'p1');
    expect(st.links.get('a')).toEqual({ at: 1, until: 4 });
    expect(st.tiles.get(memoryKey(2, 4))).toBe(5);
    expect(st.safe.has(memoryKey(2, 1))).toBe(true);
    expect([...st.coins]).toEqual([8]);
    expect(st.bananas.get(1)).toEqual([1, 2, 3]);
    expect(st.boxes.get(9)).toBe(12);
    expect(st.crumbled.get(6)).toBe(2);
    applyLevelMsg(st, { t: 'bananaGone', k: 1, by: 'p2' }, 'p1');
    expect(st.bananas.size).toBe(0);
    expect(applyLevelMsg(st, { t: 'cp', id: 'p1', k: 0 }, 'p1')).toBe(false);
    expect(applyEffectMsg(b, { t: 'effect', id: 'p2', kind: 'super', until: 10 }, 'p1', 2)).toBe(false);
    expect(applyEffectMsg(b, { t: 'effect', id: 'p1', kind: 'super', until: 10 }, 'p1', 2)).toBe(true);
    applyEffectMsg(b, { t: 'effect', id: 'p1', kind: 'shield', until: 8 }, 'p1', 2);
    expect([b.superJump, b.shield]).toEqual([8, 6]);
  });
});

describe('vague 3 — physique : bousculade, super saut, bouclier, pose', () => {
  it('jostle : poussée, trébuchement seulement si l\'autre nous fonce dessus vite', () => {
    const fast = makeBody([0, 0, 0]);
    expect(jostle(fast, [0, 0, -0.5], [0, 0, 8])).toBe(true); // l'autre arrive à 8 m/s par −z
    expect(fast.tumble).toBe(PHYS.tripTumble);
    expect(fast.v[2]).toBeGreaterThan(5);
    const slow = makeBody([0, 0, 0]);
    expect(jostle(slow, [0, 0, -0.5], [0, 0, 4])).toBe(false);
    expect(slow.p[2]).toBeGreaterThan(0); // poussé quand même
    const both = makeBody([0, 0, 0]);
    both.v = [0, 0, -8];
    expect(jostle(both, [0, 0, -0.5], [0, 0, 8])).toBe(false); // choc frontal à vitesses égales : personne ne tombe
    const sh = makeBody([0, 0, 0]);
    sh.shield = 3;
    expect(jostle(sh, [0, 0, -0.5], [0, 0, 9])).toBe(false);
    const far = makeBody([0, 0, 0]);
    expect(jostle(far, [0, 0, -2], [0, 0, 9])).toBe(false);
    expect(far.p).toEqual([0, 0, 0]);
    // réglage désactivé : aucun effet
    const off = makeBody([0, 0, 0]);
    expect(parkourJostle({ jostle: false }, off, [0, 0, -0.5], [0, 0, 9])).toBe(false);
    expect(off.p).toEqual([0, 0, 0]);
    expect(parkourJostle({ jostle: true }, off, [0, 0, -0.5], [0, 0, 9])).toBe(true);
  });

  it('super saut plus haut, bouclier contre les frappes, drapeaux de pose', () => {
    const floor = { id: 0, c: [0, -0.5, 0] as Vec3, h: [20, 0.5, 20] as Vec3, yaw: 0 };
    const b = makeBody([0, 0, 0]);
    for (let i = 0; i < 10; i++) stepBody(b, { mx: 0, mz: 0, jump: false }, [floor], DT);
    b.superJump = 8;
    let apex = 0;
    stepBody(b, { mx: 0, mz: 0, jump: true }, [floor], DT);
    for (let i = 0; i < 90; i++) { stepBody(b, { mx: 0, mz: 0, jump: false }, [floor], DT); apex = Math.max(apex, b.p[1]); }
    expect(apex).toBeGreaterThan(jumpHeight(PHYS.jumpV * PHYS.superJump) * 0.93);
    expect(b.superJump).toBeCloseTo(8 - 91 * DT, 6);
    const hammer: Contact = { id: 3, tag: 'hammer', n: [1, 0, 0], cv: [6, 0, 0], ground: false, bounced: false };
    const h = makeBody([0, 0, 0]);
    expect(parkourPostStep(h, [hammer]).knocked).toBe(true);
    const s = makeBody([0, 0, 0]);
    s.shield = 2;
    expect(parkourPostStep(s, [hammer]).knocked).toBe(false);
    expect(parkourPostStep(s, [{ ...hammer, tag: 'hazard' }]).killed).toBe(true); // la lave tue quand même
    const p = makeBody([0, 0, 0]);
    expect(poseFlags(p)).toBe(0);
    p.zip = 2; p.flight = 1; p.boost = 0.3; p.shield = 1;
    expect(poseFlags(p)).toBe(FLAG.zip | FLAG.flight | FLAG.boost | FLAG.shield);
  });
});

// ———— logique serveur avec de faux joueurs (positions et drapeaux posés à la main, comme l'état réseau 30 Hz) ————
function server(settings: Record<string, any> = {}, n = 2) {
  let t = 0;
  const players = new Map<string, ServerPlayer>();
  for (let i = 0; i < n; i++) players.set(`p${i}`, { id: `p${i}`, name: `J${i}`, isBot: false, p: [0, 0, 0], v: [0, 0, 0], yaw: 0, flags: FLAG.grounded });
  const log: any[] = [], impulses: { id: string; v: Vec3; tumble: number }[] = [];
  const ctx: ServerCtx = {
    players, startAt: 1, now: () => t,
    settings: { ...defaultGameSettings(parkourMeta), duration: 200, hurry: 200, levels: ['vague3'], ...settings },
    broadcast: (m) => log.push({ ...m, at: t }), send: () => {}, damage: () => {}, heal: () => {},
    impulse: (id, v, tumble) => impulses.push({ id, v, tumble }), teleport: () => {}, end: () => {},
  };
  const game = parkourServer.create(ctx);
  const { init } = game.onStart();
  const level = init.level as ReturnType<typeof readLevel>;
  const idx = (id: string) => level.elements.findIndex((e) => e.id === id);
  const put = (id: string, p: Vec3, extra: Partial<ServerPlayer> = {}) => Object.assign(players.get(id)!, { p, flags: FLAG.grounded, v: [0, 0, 0] }, extra);
  const tick = (to: number) => { while (t < to - 1e-9) { t = Math.round((t + 1 / 30) * 1e6) / 1e6; game.onTick(1 / 30); } };
  return { game, init, level, idx, put, tick, log, impulses, players, now: () => t, of: (ty: string) => log.filter((m) => m.t === ty) };
}

describe('vague 3 — serveur autoritaire', () => {
  it('bouton → ouverture diffusée (prolongée, sans spam) ; levier avec recharge', () => {
    const s = server();
    expect(s.init.jostle).toBe(true);
    s.tick(2);
    const btn = s.level.elements[s.idx('bouton')];
    s.put('p0', [btn.pos[0], btn.pos[1] + btn.size[1] / 2, btn.pos[2]]);
    s.tick(2.5);
    const opens = s.of('open');
    expect(opens.length).toBe(1);
    expect(opens[0]).toMatchObject({ link: 'porte1', by: s.idx('bouton') });
    expect(opens[0].until - opens[0].at).toBeCloseTo(8, 6);
    s.tick(4.5); // toujours dessus : prolongation seulement quand il reste < 7.5 s
    expect(s.of('open').length).toBeGreaterThan(1);
    expect(s.of('open').length).toBeLessThan(10);
    s.put('p0', [0, 0, 0]);
    const lv = s.level.elements[s.idx('levier')];
    s.put('p1', [lv.pos[0], lv.pos[1] - 1, lv.pos[2]]);
    s.tick(5);
    s.tick(9);
    expect(s.of('lever').length).toBe(1); // recharge de 8 s
    expect(s.of('open').filter((m) => m.link === 'trappe').length).toBe(1);
    s.tick(13.2);
    expect(s.of('lever').length).toBe(2);
  });

  it('dalles mémoire : piégée → tombe pour tous et reste tombée ; sûre → révélée ; disposition jamais envoyée', () => {
    const s = server();
    expect(Object.keys(s.init).sort()).toEqual(['coins', 'cps', 'endAt', 'jostle', 'level']); // aucune disposition
    s.tick(2);
    const i = s.idx('memoire'), e = s.level.elements[i] as El<'memory'>;
    const tiles = memoryTiles(e);
    tiles.forEach((tile, k) => { s.put('p0', [tile.c[0], tile.c[1] + tile.h[1], tile.c[2]]); s.tick(2 + (k + 1) * 0.1); });
    const fell = s.of('tile').map((m) => m.k), safe = s.of('safe').map((m) => m.k);
    expect(fell.length + safe.length).toBe(12);
    expect(new Set([...fell, ...safe]).size).toBe(12);
    expect(safe.length).toBeGreaterThanOrEqual(e.rows);
    // la même dalle n'est jamais rediffusée
    s.put('p1', [tiles[fell[0]].c[0], tiles[fell[0]].c[1] + tiles[fell[0]].h[1], tiles[fell[0]].c[2]]);
    s.tick(5);
    expect(s.of('tile').length).toBe(fell.length);
    // en l'air (pas grounded) : rien
  });

  it('boîte surprise, objets (super saut, bouclier, gant, banane) et pièces', () => {
    const s = server({}, 3);
    s.tick(2);
    const bi = s.idx('boite1'), box = s.level.elements[bi];
    const r = { super: 0.05, shield: 0.3, banana: 0.55, glove: 0.8 } as const;
    /** id prend la boîte (tirage forcé) dès qu'elle est revenue. */
    const grab = (id: string, kind: keyof typeof r) => {
      const n = s.of('box').length;
      const spy = vi.spyOn(Math, 'random').mockReturnValue(r[kind]);
      s.put(id, [box.pos[0], box.pos[1] - 0.9, box.pos[2]]);
      for (let k = 0; k < 200 && s.of('box').length === n; k++) s.tick(s.now() + 1 / 30);
      spy.mockRestore();
      expect(s.of('item').pop()).toEqual(expect.objectContaining({ id, kind }));
      s.put(id, [5, 0, 30]);
    };
    grab('p0', 'super');
    // la boîte est absente pendant `respawn` s, et on ne prend rien en tenant déjà un objet
    s.put('p1', [box.pos[0], box.pos[1] - 0.9, box.pos[2]]);
    s.tick(s.now() + 1);
    expect(s.of('item').length).toBe(1);
    s.put('p1', [5, 0, 31]);
    s.game.onPlayerMessage('p0', { t: 'use' });
    expect(s.of('item').pop()).toEqual(expect.objectContaining({ id: 'p0', kind: null }));
    expect(s.of('effect').pop()).toEqual(expect.objectContaining({ id: 'p0', kind: 'super' }));
    expect(s.of('effect')[0].until - s.now()).toBeCloseTo(8, 6);
    grab('p1', 'shield');
    s.game.onPlayerMessage('p1', { t: 'use' });
    // gant : p1 (bouclier) et p2 devant p0 ; seul p2 est frappé
    grab('p0', 'glove');
    s.put('p0', [0, 0, 24], { yaw: 0 });
    s.put('p1', [0, 0, 26]);
    s.put('p2', [0.5, 0, 25.5]);
    s.game.onPlayerMessage('p0', { t: 'use' });
    expect(s.of('glove').pop().hit).toEqual(['p2']);
    expect(s.impulses.map((x) => x.id)).toEqual(['p2']);
    expect(s.impulses[0].v[2]).toBeGreaterThan(9);
    // banane : derrière p0, armée après 0.6 s, fait glisser le premier qui passe puis disparaît
    s.put('p1', [9, 0, 30]); s.put('p2', [9, 0, 31]);
    grab('p0', 'banana');
    s.put('p0', [0, 0, 24], { yaw: 0 });
    s.game.onPlayerMessage('p0', { t: 'use' });
    const ban = s.of('banana').pop();
    expect(ban.p).toEqual([0, 0, 24 - 1.2]);
    s.put('p0', [5, 0, 30]);
    s.put('p2', [0, 0, 22.9], { v: [0, 0, 5] });
    s.tick(s.now() + 0.3);
    expect(s.of('bananaGone').length).toBe(0);
    s.tick(s.now() + 0.5);
    expect(s.of('bananaGone').pop()).toEqual(expect.objectContaining({ k: ban.k, by: 'p2' }));
    const slip = s.impulses.pop()!;
    expect(slip.id).toBe('p2');
    expect(slip.v[2]).toBeCloseTo(9, 6);
    // pièce : une fois par joueur, compteur
    const coin = s.level.elements[1];
    for (const id of ['p0', 'p0', 'p1']) { s.put(id, [coin.pos[0], 0, coin.pos[2]]); s.tick(s.now() + 0.2); s.put(id, [9, 0, 9]); }
    expect(s.of('coin').filter((m) => m.i === 1).map((m) => `${m.id}:${m.n}`)).toEqual(['p0:1', 'p1:1']);
  });

  it('grille mémoire : marcher dans un joint déclenche les dalles qui portent la capsule (relecture n° 1)', () => {
    const s = server();
    s.tick(2);
    const i = s.idx('memoire'), e = s.level.elements[i] as El<'memory'>;
    const tiles = memoryTiles(e), top = e.pos[1] + e.size[1] / 2;
    // joint entre les colonnes 0 et 1 (x = −1 pour une grille de 6 m sur 3 colonnes), au milieu de la rangée 1
    const zRow1 = tiles[e.cols].c[2];
    expect(memoryTileAt(e, [-1, top, zRow1])).toBe(-1);
    expect(memoryTilesUnder(e, [-1, top, zRow1]).sort()).toEqual([e.cols, e.cols + 1]);
    // sur une dalle (même près du bord) : seulement elle
    expect(memoryTilesUnder(e, [-1.2, top, zRow1])).toEqual([e.cols]);
    // à la croisée de 4 dalles : les 4
    const zJoint = (tiles[0].c[2] + tiles[e.cols].c[2]) / 2;
    expect(memoryTilesUnder(e, [-1, top, zJoint]).length).toBe(4);
    // traversée complète en suivant le joint : chaque rangée réagit (piège qui tombe ou dalle révélée)
    for (let z = e.pos[2] - e.size[2] / 2 + 0.2; z < e.pos[2] + e.size[2] / 2; z += 0.25) { s.put('p0', [-1, top, z]); s.tick(s.now() + 1 / 30); }
    const touched = new Set([...s.of('tile'), ...s.of('safe')].map((m) => m.k));
    for (let row = 0; row < e.rows; row++) expect(touched.has(row * e.cols) && touched.has(row * e.cols + 1), `rangée ${row}`).toBe(true);
  });

  it('banane au sol, gardée au-dessus du vide ; joueurs partis ignorés (relecture n° 2 et 3)', () => {
    const s = server({}, 3);
    s.tick(2);
    const box = s.level.elements[s.idx('boite1')];
    const spy = vi.spyOn(Math, 'random').mockReturnValue(0.55); // banane
    s.put('p0', [box.pos[0], box.pos[1] - 0.9, box.pos[2]]);
    s.tick(s.now() + 0.1);
    spy.mockRestore();
    expect(s.of('item').pop()).toEqual(expect.objectContaining({ id: 'p0', kind: 'banana' }));
    // au-dessus du vide (entre deux plateformes, rien dessous) : rien n'est posé, on garde l'objet
    s.put('p0', [0, 0, 29.5], { yaw: 0 });
    s.game.onPlayerMessage('p0', { t: 'use' });
    expect(s.of('banana').length).toBe(0);
    expect(s.of('item').pop().kind).toBe('banana');
    // en plein saut au-dessus d'une plateforme : posée sur le sol, pas en l'air
    s.put('p0', [0, 1.5, 25], { yaw: 0 });
    s.game.onPlayerMessage('p0', { t: 'use' });
    const ban = s.of('banana').pop();
    expect(ban.p[1]).toBeCloseTo(0, 6);
    // un joueur parti (encore dans ctx.players) n'écrase pas la banane
    s.put('p0', [5, 0, 30]);
    s.put('p2', [ban.p[0], ban.p[1], ban.p[2]]);
    s.game.onPlayerLeave('p2');
    s.tick(s.now() + 1.5);
    expect(s.of('bananaGone').length).toBe(0);
  });

  it('mort dans un hazard relayée à tous ; classement départagé par les pièces selon le réglage', () => {
    const s = server();
    s.tick(2);
    const lava = s.level.elements.findIndex((e) => e.type === 'hazard');
    s.game.onPlayerMessage('p0', { t: 'killed', i: lava });
    s.game.onPlayerMessage('p0', { t: 'killed', i: lava }); // anti-spam
    s.game.onPlayerMessage('p1', { t: 'killed', i: 0 }); // pas un hazard
    expect(s.of('killed').map((m) => m.id)).toEqual(['p0']);
    // même checkpoint, p1 a une pièce : devant même s'il est plus loin
    const coin = s.level.elements[1];
    s.put('p1', [coin.pos[0], 0, coin.pos[2]]);
    s.tick(2.2);
    s.put('p0', [0, 0, 4]); s.put('p1', [0, 0, -4]);
    expect(s.game.getResults().map((r) => r.id)).toEqual(['p1', 'p0']);
    expect(s.game.getResults()[0].label).toMatch(/1 pièce$/);
    const s2 = server({ coins: false, jostle: false });
    expect(s2.init.jostle).toBe(false);
    s2.tick(2);
    s2.put('p1', [coin.pos[0], 0, coin.pos[2]]);
    s2.tick(2.2);
    s2.put('p0', [0, 0, 4]); s2.put('p1', [0, 0, -4]);
    expect(s2.game.getResults().map((r) => r.id)).toEqual(['p0', 'p1']);
  });
});

describe('vague 3 — niveau d\'essai joué par des bots', () => {
  it('la fixture contient tous les types et est valide sans avertissement', () => {
    const l = readLevel('vague3');
    for (const ty of ['button', 'door', 'lever', 'trapdoor', 'memory', 'itembox', 'coin']) expect(l.elements.some((e) => e.type === ty), ty).toBe(true);
    const v = validateLevel(l);
    expect(v.errors).toEqual([]);
    expect(v.warnings).toEqual([]);
  });

  for (const jostleOn of [true, false]) {
    it(`des bots terminent (bousculades ${jostleOn ? 'activées' : 'désactivées'}) en ouvrant la porte et en traversant la grille`, () => {
      const settings = { ...defaultGameSettings(parkourMeta), duration: 150, hurry: 150, levels: ['vague3'], jostle: jostleOn };
      const { log } = simulate(parkourServer, settings, 6, 170);
      const finished = log.filter((m) => m.t === 'finish');
      expect(finished.length, JSON.stringify(log.filter((m) => m.t === 'cp').map((c) => c.id + ':' + c.k))).toBeGreaterThanOrEqual(4);
      expect(log.some((m) => m.t === 'open' && m.link === 'porte1')).toBe(true);
      expect(log.some((m) => m.t === 'safe')).toBe(true);
      expect(log.some((m) => m.t === 'coin')).toBe(true);
    });
  }
});
