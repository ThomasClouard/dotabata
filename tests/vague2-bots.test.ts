// Les bots terminent un niveau d'essai (tests/fixtures/parkour) qui contient tous les éléments de la vague 2.
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

const V2 = ['mud', 'jelly', 'ramp', 'boost', 'launcher', 'jumppad', 'zipline', 'teleport', 'bubble', 'lowgrav', 'wind'];

describe('vague 2 : niveau d\'essai joué par des bots', () => {
  it('la fixture contient tous les types, est valide sans avertissement et son chemin les emprunte', () => {
    const l = readLevel('vague2');
    expect(V2.every((t) => l.elements.some((e) => e.type === t))).toBe(true);
    const v = validateLevel(l);
    expect(v.errors).toEqual([]);
    expect(v.warnings).toEqual([]);
    const onPath = new Set(v.path.map((i) => l.elements[i].type));
    for (const t of V2) if (t !== 'lowgrav' && t !== 'wind') expect(onPath.has(t as any), t).toBe(true);
  });

  it('des bots terminent le niveau avec la vraie physique', () => {
    const settings = { ...defaultGameSettings(parkourMeta), duration: 200, hurry: 200, levels: ['vague2'] };
    const { results, log } = simulate(parkourServer, settings, 6, 220);
    const finished = log.filter((m) => m.t === 'finish');
    const cps = log.filter((m) => m.t === 'cp');
    expect(finished.length, `arrivées : ${JSON.stringify(results)} — checkpoints : ${JSON.stringify(cps.map((c) => c.id + ':' + c.k))}`).toBeGreaterThanOrEqual(4);
  });
});
