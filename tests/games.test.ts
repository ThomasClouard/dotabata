import { describe, expect, it } from 'vitest';
import { buildRoundList, pointsForRank, ranksFromGroups, sanitizeSettings, scoreRound } from '../shared/src/scoring';
import { gameMetas } from '../games/registry';
import { M, launch, plotCenter, powerForDistance, ringRadius, shellAt, shellRange, toLocal, toWorld, zoneRadius } from '../games/mortar/shared';

describe('scores', () => {
  it('donne plus de points aux mieux classés, bonus au premier', () => {
    expect(pointsForRank(0, 10)).toBe(12);
    expect(pointsForRank(1, 10)).toBe(9);
    expect(pointsForRank(9, 10)).toBe(1);
    expect(pointsForRank(0, 2)).toBeGreaterThan(pointsForRank(1, 2));
  });

  it('gère les ex æquo', () => {
    const res = ranksFromGroups([[{ id: 'a', label: '' }, { id: 'b', label: '' }], [{ id: 'c', label: '' }]]);
    expect(res.map((r) => r.rank)).toEqual([0, 0, 2]);
    const rows = scoreRound(res);
    expect(rows[0].points).toBe(rows[1].points);
    expect(rows[2].points).toBe(1);
  });

  it('nettoie les réglages et construit la liste des manches', () => {
    const s = sanitizeSettings({ rounds: 99, games: ['mortar', 'inconnu'], game: { mortar: { hp: 9999, budget: 'x' } } }, gameMetas);
    expect(s.rounds).toBe(15);
    expect(s.games).toEqual(['mortar']);
    expect(s.game.mortar.hp).toBe(300);
    expect(s.game.mortar.budget).toBe(14);
    expect(s.game.parkour.duration).toBe(150);
    const alt = sanitizeSettings({ rounds: 4, games: ['parkour', 'mortar'] }, gameMetas);
    expect(buildRoundList(alt)).toEqual(['parkour', 'mortar', 'parkour', 'mortar']);
    expect(buildRoundList({ ...alt, order: 'list', list: ['mortar', 'mortar', 'parkour', 'parkour'] })).toEqual(['mortar', 'mortar', 'parkour', 'parkour']);
    expect(buildRoundList({ ...alt, order: 'random' }, () => 0).length).toBe(4);
  });
});

describe('balistique du mortier', () => {
  it('la trajectoire retombe à la portée calculée', () => {
    const l = launch([0, 0, 0], 0, 0.5);
    const range = shellRange(l.p, l.v);
    const t = (l.v[1] + Math.sqrt(l.v[1] ** 2 + 2 * M.g * l.p[1])) / M.g;
    const end = shellAt(l.p, l.v, t);
    expect(end[1]).toBeCloseTo(0, 5);
    expect(Math.hypot(end[0] - l.p[0], end[2] - l.p[2])).toBeCloseTo(range, 5);
  });

  it('la puissance calculée atteint la cible, et la pleine puissance couvre toute l\'arène', () => {
    for (const d of [8, 20, 45]) {
      const l = launch([0, 0, 0], 0, powerForDistance(d));
      expect(Math.abs(shellRange(l.p, l.v) + 0.6 - d)).toBeLessThan(0.2);
    }
    const full = launch([0, 0, 0], 0, 1);
    expect(shellRange(full.p, full.v)).toBeGreaterThan(ringRadius(10) * 2);
  });

  it('les îles ne se touchent pas et la zone rétrécit', () => {
    // aucun point du bord d'une île n'est à portée de saut (5,25 m) de sa voisine
    for (const n of [2, 3, 5, 10]) {
      let min = Infinity;
      for (let k = -6; k <= 6; k += 0.5) for (const [lx, lz] of [[k, 6], [k, -6], [6, k], [-6, k]]) {
        const [wx, wz] = toWorld(0, n, lx, lz);
        const [bx, bz] = toLocal(1, n, wx, wz);
        min = Math.min(min, Math.hypot(Math.max(0, Math.abs(bx) - 6), Math.max(0, Math.abs(bz) - 6)));
      }
      expect(min).toBeGreaterThan(5.4);
    }
    expect(plotCenter(0, 4)[2]).toBeCloseTo(ringRadius(4));
    expect(zoneRadius(0, 10, 20)).toBe(M.zoneR0);
    expect(zoneRadius(20, 10, 20)).toBeCloseTo(M.zoneR1);
    expect(zoneRadius(15, 10, 20)).toBeLessThan(M.zoneR0);
  });
});
