// Vague 1 : cinématique, collisions et règles de chaque nouveau type d'élément.
import { describe, expect, it } from 'vitest';
import {
  ElementSchema, LevelSchema, blinkState, boulderBalls, buildColliders, crusherGap, elementCatalog, ferrisCabins, fogAt,
  gatePart, levelKillY, pistonSlabs, puncherBlocks, rollerAngle, sweeperBars, turntableBoxes, wreckingBall, type El, type LevelInput,
} from '../shared/src/level';
import { validateLevel } from '../shared/src/level-validate';
import { makeBody, stepBody, type Body, type Collider } from '../shared/src/physics';
import { parkourPostStep, parkourPreStep } from '../games/parkour/shared';

const DT = 1 / 60;
const mk = (elements: LevelInput['elements']) => LevelSchema.parse({ name: 'test', elements });
const start = { type: 'start' as const, pos: [0, -0.5, -20] as [number, number, number], size: [8, 1, 8] as [number, number, number] };
const finish = { type: 'finish' as const, pos: [0, -0.5, 60] as [number, number, number], size: [6, 1, 6] as [number, number, number] };
/** Élément seul (avec départ et arrivée loin pour que le niveau soit bien formé), valeurs par défaut appliquées. */
const one = <T extends LevelInput['elements'][number]>(e: T) => mk([start, e, finish]);

/** Simule un joueur immobile (ou poussé par `inp`) de t0 à t0 + secs ; renvoie le corps et les événements cumulés. */
function run(lvl: ReturnType<typeof mk>, b: Body, t0: number, secs: number, inp = { mx: 0, mz: 0, jump: false }) {
  let knocked = false, killed = false, hazard = -1;
  const n = Math.round(secs / DT);
  for (let i = 0; i < n; i++) {
    const t = t0 + i * DT;
    parkourPreStep(lvl, b, DT);
    const ev = parkourPostStep(b, stepBody(b, inp, buildColliders(lvl, t), DT));
    knocked ||= ev.knocked;
    if (ev.killed) { killed = true; hazard = ev.hazard; }
  }
  return { b, knocked, killed, hazard };
}

const ofId = (cs: Collider[], id: number) => cs.filter((c) => c.id === id);

describe('vague 1 — schéma et catalogue', () => {
  it('chaque type du schéma est documenté dans le catalogue', () => {
    const types = ElementSchema.options.map((o) => o.shape.type.value);
    const cat = elementCatalog().elements.map((e) => e.type);
    expect(cat.sort()).toEqual([...types].sort());
  });

  it('applique les valeurs par défaut et refuse les paramètres hors bornes', () => {
    const l = mk([start, { type: 'ferris', pos: [0, 5, 0], size: [2, 0.4, 2] }, { type: 'sign', pos: [0, 1, 0], size: [2, 1, 0.2] }, finish]);
    const f = l.elements[1] as El<'ferris'>;
    expect([f.count, f.radius, f.period, f.phase]).toEqual([4, 5, 14, 0]);
    expect((l.elements[2] as El<'sign'>).text).toBe('');
    expect(ElementSchema.safeParse({ type: 'crusher', pos: [0, 0, 0], size: [4, 2, 2], minGap: 0.8 }).success).toBe(false);
    expect(ElementSchema.safeParse({ type: 'sign', pos: [0, 0, 0], size: [1, 1, 1], text: 'x'.repeat(61) }).success).toBe(false);
    expect(ElementSchema.safeParse({ type: 'hazard', pos: [0, 0, 0], size: [1, 1, 1], style: 'goudron' }).success).toBe(false);
    expect(ElementSchema.safeParse({ type: 'deco', pos: [0, 0, 0], size: [1, 1, 1], kind: 'crowd', color: '#12ab34' }).success).toBe(true);
  });

  it('les vitesses de surface sont la dérivée exacte des positions', () => {
    const l = mk([
      start,
      { type: 'puncher', pos: [0, 1, 0], size: [6, 1, 1], yaw: 0.7, count: 3, stagger: 0.2 },
      { type: 'gate', pos: [10, 3, 0], size: [4, 1, 0.5], yaw: 0.3 },
      { type: 'ferris', pos: [20, 6, 0], size: [2, 0.4, 2], yaw: 1.1, radius: 5 },
      { type: 'pistons', pos: [30, 0, 0], size: [8, 1, 2], yaw: -0.4, count: 4 },
      { type: 'wreckingball', pos: [40, 8, 0], size: [1.4, 1.4, 1.4] },
      { type: 'crusher', pos: [50, 1, 0], size: [5, 2, 3], yaw: 0.9 },
      { type: 'boulder', pos: [60, 1, 0], size: [1.2, 1.2, 1.2], delta: [10, -2, 4], interval: 3, travel: 5 },
      finish,
    ]);
    const eps = 1e-5;
    for (const t of [0.13, 1.37, 2.71, 5.05, 9.9]) {
      const a = buildColliders(l, t - eps), b = buildColliders(l, t + eps), m = buildColliders(l, t);
      expect(a.length).toBe(m.length);
      m.forEach((c, k) => {
        if (c.id === 0 || c.id === 8) return;
        for (let j = 0; j < 3; j++) expect(c.vel![j], `${c.tag} t=${t} axe ${j}`).toBeCloseTo((b[k].c[j] - a[k].c[j]) / (2 * eps), 3);
      });
    }
  });
});

describe('vague 1 — sols horlogers', () => {
  it('roller : le dessus entraîne le joueur perpendiculairement à l\'axe, le visuel tourne', () => {
    const l = one({ type: 'roller', pos: [0, -0.6, 0], size: [6, 1.2, 1.2], yaw: Math.PI / 2, speed: 3 });
    const e = l.elements[1] as El<'roller'>;
    const c = ofId(buildColliders(l, 0), 1)[0];
    expect(c.conveyor![0]).toBeCloseTo(3, 6); // +z local, tourné de 90° → +x monde
    expect(c.conveyor![1]).toBeCloseTo(0, 6);
    const { b } = run(l, makeBody([-0.5, 0.05, 0]), 0, 0.15);
    expect(b.grounded).toBe(true);
    expect(b.groundVel[0]).toBeCloseTo(3, 3);
    expect(b.v[0]).toBeGreaterThan(1.5); // déjà entraîné
    expect(rollerAngle(e, 2)).toBeCloseTo((3 * 2) / 0.6, 6);
  });

  it('turntable : octogone de 4 boîtes, le joueur tourne avec le plateau', () => {
    const l = one({ type: 'turntable', pos: [0, -0.5, 0], size: [8, 1, 8], speed: 1 });
    const boxes = turntableBoxes(l.elements[1] as El<'turntable'>, 0.5);
    expect(boxes.length).toBe(4);
    expect(boxes[1].yaw - boxes[0].yaw).toBeCloseTo(Math.PI / 4, 6);
    const b = makeBody([2.5, 0.05, 0]);
    run(l, b, 0, 0.1);
    const a0 = Math.atan2(-b.p[2], b.p[0]); // angle dans le sens du lacet (+yaw : x vers -z)
    run(l, b, 0.1, 1);
    const a1 = Math.atan2(-b.p[2], b.p[0]);
    expect(b.grounded).toBe(true);
    expect(a1 - a0).toBeGreaterThan(0.8); // ≈ 1 rad en 1 s (accélération au sol finie)
    expect(a1 - a0).toBeLessThan(1.1);
    expect(Math.hypot(b.p[0], b.p[2])).toBeLessThan(3.6); // ne s'envole pas du disque
  });

  it('ferris : les nacelles restent horizontales sur le cercle, le joueur monte avec sa nacelle', () => {
    const l = one({ type: 'ferris', pos: [0, 5, 0], size: [3, 0.4, 3], yaw: 0.6, radius: 5, period: 12, count: 3 });
    const e = l.elements[1] as El<'ferris'>;
    for (const t of [0, 1.7, 6.2]) {
      const cabs = ferrisCabins(e, t);
      expect(cabs.length).toBe(3);
      for (const c of cabs) {
        expect(Math.hypot(c.c[0], c.c[1] - 5, c.c[2])).toBeCloseTo(5, 6);
        expect(c.yaw).toBe(0.6);
        // dans le plan vertical de x local : composante z locale nulle
        expect(c.c[0] * Math.sin(0.6) + c.c[2] * Math.cos(0.6)).toBeCloseTo(0, 6);
      }
    }
    // nacelle 0 au plus bas à t = 9 s (θ = 3π/2) ; on y pose le joueur puis on attend un quart de tour
    const low = ferrisCabins(e, 9)[0];
    expect(low.c[1]).toBeCloseTo(0, 6);
    const b = makeBody([low.c[0], low.c[1] + 0.2 + 0.02, low.c[2]]);
    run(l, b, 9, 3);
    const now = ferrisCabins(e, 12)[0];
    expect(b.grounded).toBe(true);
    expect(b.groundId).toBe(1);
    expect(b.p[1]).toBeCloseTo(now.c[1] + 0.2, 1);
    expect(Math.hypot(b.p[0] - now.c[0], b.p[2] - now.c[2])).toBeLessThan(1.5);
  });

  it('pistons : dalles entre pos.y et pos.y + height, déphasées, qui soulèvent le joueur', () => {
    const l = one({ type: 'pistons', pos: [0, -0.5, 0], size: [8, 1, 3], count: 4, height: 2, period: 4, stagger: 0.25 });
    const e = l.elements[1] as El<'pistons'>;
    const s = pistonSlabs(e, 0);
    expect(s.map((p) => +p.c[1].toFixed(6))).toEqual([-0.5, 0.5, 1.5, 0.5]);
    expect(s.map((p) => p.c[0])).toEqual([-3, -1, 1, 3]);
    // dalle 0 : au plus bas à t = 0, au plus haut à t = 2
    const b = makeBody([-3, 0.02, 0]);
    run(l, b, 0, 2);
    expect(b.grounded).toBe(true);
    expect(b.p[1]).toBeGreaterThan(1.9);
  });

  it('blink : présente pendant la fraction `on`, le joueur tombe quand elle disparaît', () => {
    const l = one({ type: 'blink', pos: [0, -0.5, 0], size: [3, 1, 3], period: 4, on: 0.5 });
    const e = l.elements[1] as El<'blink'>;
    expect(ofId(buildColliders(l, 1), 1).length).toBe(1);
    expect(ofId(buildColliders(l, 3), 1).length).toBe(0);
    expect(blinkState(e, 1.5)).toEqual({ solid: true, u: 0.375, left: 0.5 });
    expect(blinkState(e, 3).solid).toBe(false);
    const b = makeBody([0, 0.02, 0]);
    run(l, b, 0, 1.9);
    expect(b.grounded).toBe(true);
    run(l, b, 1.9, 0.6);
    expect(b.grounded).toBe(false);
    expect(b.p[1]).toBeLessThan(-0.5);
  });
});

describe('vague 1 — obstacles', () => {
  it('puncher : blocs en vague le long de x local, qui frappent vers +z local', () => {
    const l = one({ type: 'puncher', pos: [0, 0.6, 0], size: [6, 1.2, 1], count: 3, stroke: 2, period: 3, stagger: 0.5 });
    const e = l.elements[1] as El<'puncher'>;
    const bl = puncherBlocks(e, 0.6); // u = 0.2 (sorti) ; bloc 1 : u = 0.7 (rentre) ; bloc 2 : u = 0.2
    expect(bl.map((p) => p.c[0])).toEqual([-2, 0, 2]);
    expect(bl[0].c[2]).toBeCloseTo(2, 6);
    expect(bl[1].c[2]).toBeGreaterThan(0);
    expect(bl[1].c[2]).toBeLessThan(2);
    expect(bl[2].c[2]).toBeCloseTo(2, 6);
    // joueur devant le bloc 0 au repos : il jaillit et l'éjecte vers +z
    const floor = { type: 'platform' as const, pos: [0, -0.5, 2] as [number, number, number], size: [10, 1, 10] as [number, number, number] };
    const l2 = mk([start, { ...e }, floor, finish]);
    const { b, knocked } = run(l2, makeBody([-2, 0.02, 1.3]), 2.95, 0.4);
    expect(knocked).toBe(true);
    expect(b.v[2]).toBeGreaterThan(3);
  });

  it('gate : chute rapide, remontée lente ; la lame qui tombe écarte le joueur', () => {
    const l = one({ type: 'gate', pos: [0, 2.6, 0], size: [6, 1.2, 0.5], drop: 2, period: 4 });
    const e = l.elements[1] as El<'gate'>;
    expect(gatePart(e, 3.2).c[1]).toBeCloseTo(2.6, 6); // en haut
    expect(gatePart(e, 0.8).c[1]).toBeCloseTo(0.6, 6); // en bas
    expect(gatePart(e, 0.3).vel[1]).toBeLessThan(-7); // tombe vite
    expect(gatePart(e, 2).vel[1]).toBeGreaterThan(0); // remonte
    expect(gatePart(e, 2).vel[1]).toBeLessThan(5);
    expect(gatePart(e, 3).untilFall).toBeCloseTo(1, 6);
    const floor = { type: 'platform' as const, pos: [0, -0.5, 0] as [number, number, number], size: [10, 1, 10] as [number, number, number] };
    const l2 = mk([start, { ...e }, floor, finish]);
    const { b, knocked } = run(l2, makeBody([0, 0.02, 0.1]), 3.9, 0.5);
    expect(knocked).toBe(true);
    expect(Math.abs(b.p[2])).toBeGreaterThan(0.6); // sorti de sous la lame
  });

  it('sweeper : barre basse et barre haute perpendiculaire ; la haute fauche celui qui saute', () => {
    const l = one({ type: 'sweeper', pos: [0, 0.45, 0], size: [6, 0.3, 0.3], speed: 1.5, highOffset: 2.1 });
    const e = l.elements[1] as El<'sweeper'>;
    const [lo, hi] = sweeperBars(e, 0.7);
    expect(hi.c[1] - lo.c[1]).toBeCloseTo(2.1, 6);
    expect(hi.yaw - lo.yaw).toBeCloseTo(Math.PI / 2, 6);
    expect(ofId(buildColliders(l, 0), 1).every((c) => c.angVel === 1.5)).toBe(true);
    // un joueur en l'air à hauteur de la barre haute, sur sa trajectoire
    const hit = makeBody([0, 0, 0]);
    const ev = parkourPostStep(hit, [{ id: 1, tag: 'sweeper', n: [0, -1, 0], cv: [0, 0, -3], ground: false, bounced: false }]);
    expect(ev.knocked).toBe(true);
    expect(hit.v[2]).toBeLessThan(-3);
  });

  it('wreckingball : la boule tourne sur un cercle horizontal et éjecte', () => {
    const l = one({ type: 'wreckingball', pos: [0, 8, 0], size: [1.4, 1.4, 1.4], length: 6, angle: 0.6, period: 4 });
    const e = l.elements[1] as El<'wreckingball'>;
    for (const t of [0, 1.1, 2.9]) {
      const w = wreckingBall(e, t);
      expect(Math.hypot(w.c[0], w.c[1] - 8, w.c[2])).toBeCloseTo(6, 6);
      expect(w.c[1]).toBeCloseTo(8 - 6 * Math.cos(0.6), 6);
      expect(Math.hypot(w.vel[0], w.vel[2])).toBeCloseTo((6 * Math.sin(0.6) * 2 * Math.PI) / 4, 6);
    }
    // joueur posé sur le cercle de la boule, un peu avant son passage (φ = π/2 à t = 1 s)
    const floor = { type: 'platform' as const, pos: [0, 8 - 6 * Math.cos(0.6) - 1.2, 0] as [number, number, number], size: [12, 1, 12] as [number, number, number] };
    const l2 = mk([start, { ...e }, floor, finish]);
    const r = 6 * Math.sin(0.6);
    const { knocked } = run(l2, makeBody([0, floor.pos[1] + 0.52, r]), 0.7, 0.6);
    expect(knocked).toBe(true);
  });

  it('crusher : l\'écart reste entre minGap et size.x, le joueur coincé est poussé sans être écrasé', () => {
    const l = one({ type: 'crusher', pos: [0, 1, 0], size: [5, 2, 3], minGap: 1.4, thickness: 1, period: 4 });
    const e = l.elements[1] as El<'crusher'>;
    expect(crusherGap(e, 0)[0]).toBeCloseTo(5, 6);
    expect(crusherGap(e, 2)[0]).toBeCloseTo(1.4, 6);
    const floor = { type: 'platform' as const, pos: [0, -0.5, 0] as [number, number, number], size: [10, 1, 10] as [number, number, number] };
    const l2 = mk([start, { ...e }, floor, finish]);
    const b = makeBody([1.6, 0.02, 0]); // près du mur droit
    for (let i = 0; i < 4 / DT; i++) {
      const t = i * DT;
      parkourPostStep(b, stepBody(b, { mx: 0, mz: 0, jump: false }, buildColliders(l2, t), DT));
      const gap = crusherGap(e, t)[0];
      expect(Math.abs(b.p[0])).toBeLessThanOrEqual(gap / 2 - 0.4 + 0.25); // jamais dans un mur (tolérance d'un pas)
    }
    expect(b.tumble).toBe(0);
    expect(b.p[1]).toBeGreaterThan(-0.1);
  });

  it('boulder : boules périodiques en ligne droite, qui disparaissent au bout et éjectent', () => {
    const l = one({ type: 'boulder', pos: [-6, 0.6, 0], size: [1.2, 1.2, 1.2], delta: [12, 0, 0], interval: 2, travel: 3 });
    const e = l.elements[1] as El<'boulder'>;
    expect(boulderBalls(e, 0.5).length).toBe(2); // une à 0.5 s, une à 2.5 s de vol
    expect(boulderBalls(e, 1.5).length).toBe(1);
    const [ball] = boulderBalls(e, 1.5);
    expect(ball.c[0]).toBeCloseTo(-6 + 12 * 0.5, 6);
    expect(ball.vel[0]).toBeCloseTo(4, 6);
    expect(ball.roll).toBeCloseTo(6 / 0.6, 6);
    const floor = { type: 'platform' as const, pos: [0, -0.5, 0] as [number, number, number], size: [16, 1, 6] as [number, number, number] };
    const l2 = mk([start, { ...e }, floor, finish]);
    const { b, knocked } = run(l2, makeBody([0, 0.02, 0]), 0, 2);
    expect(knocked).toBe(true);
    expect(b.tumble).toBeGreaterThan(0);
  });

  it('hazard : le moindre contact renvoie un événement de mort', () => {
    const l = one({ type: 'hazard', style: 'water', pos: [0, -1, 0], size: [6, 1, 6] });
    const { killed, hazard } = run(l, makeBody([0, 2, 0]), 0, 1);
    expect(killed).toBe(true);
    expect(hazard).toBe(1);
    const dry = parkourPostStep(makeBody([0, 0, 0]), [{ id: 3, tag: 'platform', n: [0, 1, 0], cv: [0, 0, 0], ground: true, bounced: false }]);
    expect(dry.killed).toBe(false);
    expect(dry.hazard).toBe(-1);
  });
});

describe('vague 1 — décor et validation', () => {
  it('fakewall, deco, sign, fog : aucune collision ; fogAt ; killY les ignore', () => {
    const l = mk([
      start,
      { type: 'fakewall', pos: [0, -0.5, 0], size: [4, 1, 4] },
      { type: 'deco', kind: 'tree', pos: [5, -50, 0], size: [2, 4, 2] },
      { type: 'sign', pos: [0, 1, 3], size: [2, 1, 0.2], text: 'Par ici !' },
      { type: 'fog', pos: [0, 2, 10], size: [6, 4, 6], density: 0.8, color: '#223344' },
      finish,
    ]);
    expect(buildColliders(l, 3).map((c) => c.id)).toEqual([0, 5]);
    const b = run(l, makeBody([0, 0.5, 0]), 0, 1).b;
    expect(b.p[1]).toBeLessThan(-3); // on traverse le faux mur
    expect(fogAt(l, [1, 2, 11])).toEqual({ density: 0.8, color: '#223344' });
    expect(fogAt(l, [1, 5, 11])).toBeNull();
    expect(levelKillY(l)).toBe(-1 - 12);
  });

  it('un faux mur ou de la lave ne servent jamais d\'appui au chemin', () => {
    const fake = validateLevel(mk([
      { type: 'start', pos: [0, -0.5, 0], size: [8, 1, 8] },
      { type: 'fakewall', pos: [0, -0.5, 7], size: [4, 1, 4] },
      { type: 'finish', pos: [0, -0.5, 14], size: [6, 1, 6] },
    ]));
    expect(fake.ok).toBe(false);
    const lava = validateLevel(mk([
      { type: 'start', pos: [0, -0.5, 0], size: [8, 1, 8] },
      { type: 'hazard', pos: [0, -0.5, 7], size: [4, 1, 4] },
      { type: 'finish', pos: [0, -0.5, 14], size: [6, 1, 6] },
    ]));
    expect(lava.ok).toBe(false);
  });

  it('les sols horlogers sont des nœuds du chemin : grande roue pour monter, pistons, dalles, plateau, rouleau', () => {
    const v = validateLevel(mk([
      { type: 'start', pos: [0, -0.5, 0], size: [8, 1, 8] },
      { type: 'roller', pos: [0, -0.6, 5], size: [6, 1.2, 1.2] },
      { type: 'turntable', pos: [0, -0.5, 10], size: [7, 1, 7] },
      { type: 'pistons', pos: [0, -0.5, 17.5], size: [8, 1, 4], yaw: Math.PI / 2, height: 1.5 },
      { type: 'blink', pos: [0, -0.5, 24], size: [3, 1, 3] },
      { type: 'ferris', pos: [0, 4.5, 32], size: [2.5, 0.4, 2.5], yaw: Math.PI / 2, radius: 4.5 },
      { type: 'finish', pos: [0, 6.5, 42], size: [6, 1, 6] },
    ]));
    expect(v.errors).toEqual([]);
    expect(v.path).toEqual([0, 1, 2, 3, 4, 5, 6]);
    // sans la grande roue, l'arrivée (7 m plus haut) est inatteignable
    const no = validateLevel(mk([
      { type: 'start', pos: [0, -0.5, 0], size: [8, 1, 8] },
      { type: 'finish', pos: [0, 6.5, 10], size: [6, 1, 6] },
    ]));
    expect(no.ok).toBe(false);
  });
});
