// Parties complètes simulées sans réseau : des bots jouent chaque jeu avec la vraie physique et les vraies règles.
import { describe, expect, it } from 'vitest';
import { defaultGameSettings } from '../shared/src/scoring';
import { parkourServer } from '../games/parkour/server';
import { parkourMeta } from '../games/parkour/shared';
import { mortarServer } from '../games/mortar/server';
import { mortarMeta } from '../games/mortar/shared';
import { simulate } from './sim';

describe('parties simulées avec des bots', () => {
  // niveaux livrés : les 4 de la vague 4 doivent être terminés par au moins la moitié des bots
  for (const level of ['balade', 'usine', 'vertige', 'fete-foraine', 'volcan', 'labo', 'chateau']) {
    it(`des bots terminent le niveau « ${level} » avec la vraie physique`, () => {
      const settings = { ...defaultGameSettings(parkourMeta), duration: 240, hurry: 240, levels: [level] };
      const { results, log } = simulate(parkourServer, settings, 6, 260);
      const finished = log.filter((m) => m.t === 'finish');
      const need = ['balade', 'usine', 'vertige'].includes(level) ? 1 : 3;
      expect(finished.length, `arrivées sur ${level} : ${JSON.stringify(results)}`).toBeGreaterThanOrEqual(need);
      expect(results.length).toBe(6);
      expect(results[0].rank).toBe(0);
    });
  }

  it('une bataille de mortier entre bots va à son terme et fait des dégâts', () => {
    const settings = { ...defaultGameSettings(mortarMeta), buildTime: 5, battleTime: 90, shrink: 30 };
    const { results, log, ended } = simulate(mortarServer, settings, 5, 120);
    expect(ended).toBe(true);
    expect(log.some((m) => m.t === 'block')).toBe(true);
    expect(log.filter((m) => m.t === 'shell').length).toBeGreaterThan(10);
    expect(log.some((m) => m.t === 'boom')).toBe(true);
    expect(log.some((m) => m.t === 'hp')).toBe(true);
    expect(results.length).toBe(5);
    expect(new Set(results.map((r) => r.id)).size).toBe(5);
    expect(results.filter((r) => r.rank === 0).length).toBeGreaterThanOrEqual(1);
  });
});
