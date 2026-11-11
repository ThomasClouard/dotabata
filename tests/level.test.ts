import { describe, expect, it } from 'vitest';
import { LevelSchema, buildColliders, type LevelInput } from '../shared/src/level';
import { asciiPreview, validateLevel } from '../shared/src/level-validate';
import { listLevels, readLevel } from '../shared/src/level-store';
import { makeBody, stepBody } from '../shared/src/physics';
import { parkourPostStep, parkourPreStep } from '../games/parkour/shared';

const mk = (elements: LevelInput['elements']) => LevelSchema.parse({ name: 'test', elements });

describe('niveaux de parcours', () => {
  it('les niveaux livrés sont valides et terminables', () => {
    const names = listLevels();
    expect(names.length).toBeGreaterThanOrEqual(7);
    for (const n of names) {
      const v = validateLevel(readLevel(n));
      expect(v.errors, `${n} : ${v.errors.join(' | ')}`).toEqual([]);
      expect(v.warnings, `${n} : ${v.warnings.join(' | ')}`).toEqual([]);
    }
  });

  it('refuse un saut trop long ou trop haut', () => {
    const far = validateLevel(mk([
      { type: 'start', pos: [0, 0, 0], size: [8, 1, 8] },
      { type: 'finish', pos: [0, 0, 20], size: [6, 1, 6] },
    ]));
    expect(far.ok).toBe(false);
    const high = validateLevel(mk([
      { type: 'start', pos: [0, 0, 0], size: [8, 1, 8] },
      { type: 'finish', pos: [0, 4, 8], size: [6, 1, 6] },
    ]));
    expect(high.ok).toBe(false);
  });

  it('accepte le même dénivelé avec un trampoline, et exige start / finish', () => {
    const ok = validateLevel(mk([
      { type: 'start', pos: [0, 0, 0], size: [8, 1, 8] },
      { type: 'trampoline', pos: [0, 0, 7], size: [3, 1, 3], bounce: 17 },
      { type: 'finish', pos: [0, 4, 13], size: [6, 1, 6] },
    ]));
    expect(ok.errors).toEqual([]);
    expect(ok.path).toEqual([0, 1, 2]);
    expect(validateLevel(mk([{ type: 'platform', pos: [0, 0, 0], size: [8, 1, 8] }, { type: 'finish', pos: [0, 0, 8], size: [6, 1, 6] }])).ok).toBe(false);
  });

  it('rejette un élément mal formé', () => {
    expect(LevelSchema.safeParse({ name: 'x', elements: [{ type: 'laser', pos: [0, 0, 0], size: [1, 1, 1] }, { type: 'start', pos: [0, 0, 0], size: [1, 1, 1] }] }).success).toBe(false);
    expect(LevelSchema.safeParse({ name: 'Nom Invalide', elements: [] }).success).toBe(false);
  });

  it('les obstacles sont déterministes et les dalles friables tombent', () => {
    const lvl = mk([
      { type: 'start', pos: [0, 0, 0], size: [8, 1, 8] },
      { type: 'moving', pos: [0, 0, 8], size: [3, 1, 3], delta: [6, 0, 0], period: 4 },
      { type: 'crumble', pos: [0, 0, 14], size: [3, 1, 3] },
      { type: 'finish', pos: [0, 0, 20], size: [6, 1, 6] },
    ]);
    expect(buildColliders(lvl, 12.34)).toEqual(buildColliders(lvl, 12.34));
    expect(buildColliders(lvl, 2)[1].c[0]).toBeCloseTo(6, 5); // demi-période : bout de course
    const crumbled = new Map([[2, 10]]);
    expect(buildColliders(lvl, 10.2, crumbled).length).toBe(4);
    expect(buildColliders(lvl, 11, crumbled).length).toBe(3);
    expect(buildColliders(lvl, 15, crumbled).length).toBe(4);
  });

  it('un ventilateur soulève le joueur et un marteau l\'éjecte', () => {
    const lvl = mk([
      { type: 'start', pos: [0, -0.5, 0], size: [8, 1, 8] },
      { type: 'fan', pos: [0, 5, 0], size: [4, 10, 4] },
      { type: 'finish', pos: [0, 9, 6], size: [6, 1, 6] },
    ]);
    const b = makeBody([0, 0.5, 0]);
    for (let i = 0; i < 90; i++) { parkourPreStep(lvl, b, 1 / 60); stepBody(b, { mx: 0, mz: 0, jump: false }, buildColliders(lvl, i / 60), 1 / 60); }
    expect(b.p[1]).toBeGreaterThan(5);
    const hit = makeBody([0, 0, 0]);
    const ev = parkourPostStep(hit, [{ id: 3, tag: 'hammer', n: [1, 0, 0], cv: [8, 0, 0], ground: false, bounced: false }]);
    expect(ev.knocked).toBe(true);
    expect(hit.v[0]).toBeGreaterThan(8);
    expect(hit.tumble).toBeGreaterThan(0);
  });

  it('dessine un aperçu ASCII', () => {
    const txt = asciiPreview(readLevel('balade'));
    expect(txt).toContain('S');
    expect(txt).toContain('F');
  });
});
