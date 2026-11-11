// Vague 3 : bousculades, portes / trappes, dalles mémoire, objets, pièces — fonctions partagées (la logique serveur
// est testée côté Godot : godot/tests/run_server_tests.gd).
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  ElementSchema, LevelSchema, buildColliders, doorOpenness, elementCatalog, linkOpen, memoryKey, memoryTileAt, memoryTiles, memoryTilesUnder, newLevelState,
  type El, type LevelInput,
} from '../shared/src/level';
import { PHYS, jostle, jumpHeight, makeBody, stepBody, type Contact, type Vec3 } from '../shared/src/physics';
import { FLAG, poseFlags } from '../shared/src/protocol';
import { applyEffectMsg, applyLevelMsg, memoryLayout, parkourJostle, parkourMeta, parkourPostStep } from '../games/parkour/shared';

process.env.JEUX_LEVELS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures', 'parkour');
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

describe("vague 3 — niveau d'essai", () => {
  it('la fixture contient tous les types et est valide sans avertissement', () => {
    const l = readLevel('vague3');
    for (const ty of ['button', 'door', 'lever', 'trapdoor', 'memory', 'itembox', 'coin']) expect(l.elements.some((e) => e.type === ty), ty).toBe(true);
    const v = validateLevel(l);
    expect(v.errors).toEqual([]);
    expect(v.warnings).toEqual([]);
  });
});
