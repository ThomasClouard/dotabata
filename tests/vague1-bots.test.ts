// Les bots terminent un niveau d'essai (tests/fixtures/parkour) qui contient tous les éléments de la vague 1.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { defaultGameSettings } from '../shared/src/scoring';
import { parkourMeta } from '../games/parkour/shared';
import { simulate } from './sim';

// level-store lit JEUX_LEVELS_DIR à son chargement : on le fixe avant d'importer le serveur (fichier de test isolé)
process.env.JEUX_LEVELS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures', 'parkour');
const { parkourServer } = await import('../games/parkour/server');
const { readLevel } = await import('../shared/src/level-store');
const { validateLevel } = await import('../shared/src/level-validate');

describe('vague 1 : niveau d\'essai joué par des bots', () => {
  it('la fixture est valide sans avertissement', () => {
    const v = validateLevel(readLevel('vague1'));
    expect(v.errors).toEqual([]);
    expect(v.warnings).toEqual([]);
  });

  it('des bots terminent le niveau avec la vraie physique', () => {
    const settings = { ...defaultGameSettings(parkourMeta), duration: 280, hurry: 280, levels: ['vague1'] };
    const { results, log } = simulate(parkourServer, settings, 6, 300);
    const finished = log.filter((m) => m.t === 'finish');
    const cps = log.filter((m) => m.t === 'cp');
    expect(finished.length, `arrivées : ${JSON.stringify(results)} — checkpoints : ${JSON.stringify(cps.map((c) => c.id + ':' + c.k + '@' + c.t))}`).toBeGreaterThanOrEqual(1);
  });
});
