// Vague 2 : sols spéciaux et propulseurs — physique, fonctions pures et validation de chaque nouveau type.
import { describe, expect, it } from 'vitest';
import {
  ElementSchema, LevelSchema, ballisticPoint, boostVel, bubbleParts, buildColliders, elementBottom, elementCatalog, inZone, jumppadVel,
  launchVelocity, launcherArc, levelKillY, lowgravAt, rampCorners, rampTopAt, windAccel, windGust, zipCable, zipFeet, type El, type LevelInput,
} from '../shared/src/level';
import { validateLevel } from '../shared/src/level-validate';
import { PHYS, clearMotionState, groundBelow, jumpHeight, jumpReach, makeBody, stepBody, type Body } from '../shared/src/physics';
import { parkourPostStep, parkourPreStep, type PreEvents } from '../games/parkour/shared';

const DT = 1 / 60;
type V3 = [number, number, number];
const mk = (elements: LevelInput['elements']) => LevelSchema.parse({ name: 'test', elements });
const start = { type: 'start' as const, pos: [0, -0.5, -20] as V3, size: [8, 1, 8] as V3 };
const finish = { type: 'finish' as const, pos: [0, -0.5, 80] as V3, size: [6, 1, 6] as V3 };
const floor = (z = 0, w = 40) => ({ type: 'platform' as const, pos: [0, -0.5, z] as V3, size: [w, 1, w] as V3 });
const one = (...e: LevelInput['elements']) => mk([start, ...e, finish]);

/** Simule de t0 à t0 + secs (pré-étape avec l'horloge, pas de physique, post-étape) ; cumule les événements. */
function run(lvl: ReturnType<typeof mk>, b: Body, t0: number, secs: number, inp: { mx: number; mz: number; jump: boolean } | ((i: number) => { mx: number; mz: number; jump: boolean }) = { mx: 0, mz: 0, jump: false }, each?: (b: Body, i: number) => void) {
  const pre: PreEvents = { launched: -1, teleported: -1, grabbed: -1, released: -1 };
  let bounced = 0, boosted = false;
  const n = Math.round(secs / DT);
  for (let i = 0; i < n; i++) {
    const t = t0 + i * DT;
    const e = parkourPreStep(lvl, b, DT, t);
    for (const k of ['launched', 'teleported', 'grabbed', 'released'] as const) if (e[k] >= 0) pre[k] = e[k];
    const ev = parkourPostStep(b, stepBody(b, typeof inp === 'function' ? inp(i) : inp, buildColliders(lvl, t), DT));
    if (ev.bounced) bounced++;
    boosted ||= ev.boosted;
    each?.(b, i);
  }
  return { b, pre, bounced, boosted };
}
const still = { mx: 0, mz: 0, jump: false };

describe('vague 2 — schéma et catalogue', () => {
  it('chaque type est documenté, défauts appliqués, bornes refusées', () => {
    const types = ElementSchema.options.map((o) => o.shape.type.value);
    expect(elementCatalog().elements.map((e) => e.type).sort()).toEqual([...types].sort());
    const l = mk([start, { type: 'mud', pos: [0, 0, 0], size: [2, 1, 2] }, { type: 'jumppad', pos: [0, 0, 0], size: [2, 1, 2] }, { type: 'ramp', pos: [0, 0, 0], size: [2, 1, 4] }, { type: 'wind', pos: [0, 0, 0], size: [2, 1, 2] }, finish]);
    const [m, j, r, w] = l.elements.slice(1, 5) as [El<'mud'>, El<'jumppad'>, El<'ramp'>, El<'wind'>];
    expect([m.slow, m.jumpFactor]).toEqual([0.45, 0.6]);
    expect(j.launch).toEqual([0, 14, 8]);
    expect([r.rise, r.slide]).toEqual([2, false]);
    expect([w.force, w.period, w.phase]).toEqual([[24, 0, 0], 3, 0]);
    expect(ElementSchema.safeParse({ type: 'launcher', pos: [0, 0, 0], size: [1, 1, 1] }).success).toBe(false); // `to` requis
    expect(ElementSchema.safeParse({ type: 'jumppad', pos: [0, 0, 0], size: [1, 1, 1], launch: [0, 2, 0] }).success).toBe(false);
    expect(ElementSchema.safeParse({ type: 'lowgrav', pos: [0, 0, 0], size: [1, 1, 1], gravity: 0 }).success).toBe(false);
    expect(ElementSchema.safeParse({ type: 'bubble', pos: [0, 0, 0], size: [1, 1, 1], count: 0 }).success).toBe(false);
  });

  it('clearMotionState remet à zéro les états de la vague 2', () => {
    const b = makeBody([0, 0, 0]);
    Object.assign(b, { zip: 3, zipS: 2, flight: 1, boost: 0.4, cool: 0.2, slow: 0.4, jumpK: 0.6 });
    clearMotionState(b);
    expect([b.zip, b.zipS, b.flight, b.boost, b.cool, b.slow, b.jumpK]).toEqual([-1, 0, 0, 0, 0, 1, 1]);
  });
});

describe('vague 2 — sols spéciaux', () => {
  it('mud : vitesse max × slow, saut × jumpFactor', () => {
    const l = one({ type: 'mud', pos: [0, -0.5, 0], size: [40, 1, 40], slow: 0.5, jumpFactor: 0.6 });
    const { b } = run(l, makeBody([0, 0.02, -10]), 0, 1.5, { mx: 0, mz: 1, jump: false });
    expect(b.grounded).toBe(true);
    expect([b.slow, b.jumpK]).toEqual([0.5, 0.6]);
    expect(b.v[2]).toBeCloseTo(PHYS.speed * 0.5, 6);
    let apex = 0;
    run(l, b, 1.5, 1, (i) => ({ mx: 0, mz: 0, jump: i === 0 }), (q) => { apex = Math.max(apex, q.p[1]); });
    expect(apex).toBeGreaterThan(jumpHeight(PHYS.jumpV * 0.6) * 0.9);
    expect(apex).toBeLessThan(jumpHeight(PHYS.jumpV * 0.6) * 1.1);
  });

  it('jelly : les chutes rebondissent (au moins jellyMin), puis on se pose ; saut plus haut', () => {
    const l = one({ type: 'jelly', pos: [0, -0.5, 0], size: [10, 1, 10], bounciness: 0.6, jumpFactor: 1.2 });
    const b = makeBody([0, 3, 0]);
    let ups: number[] = [];
    const r = run(l, b, 0, 4, still, (q) => { if (q.v[1] > 0 && !q.grounded && (ups.length === 0 || ups[ups.length - 1] !== q.v[1])) ups.push(q.v[1]); });
    ups = [...new Set(ups.map((v) => +v.toFixed(3)))];
    expect(r.bounced).toBeGreaterThanOrEqual(1);
    const impact = Math.sqrt(2 * PHYS.gravity * 3);
    expect(ups[0]).toBeGreaterThan(impact * 0.6 - 0.5); // premier rebond ≈ 0.6 × impact (moins g·dt)
    expect(b.grounded).toBe(true);
    // petite chute (impact < jellyImpact) : pas de rebond
    const s = makeBody([0, 0.3, 0]);
    expect(run(l, s, 0, 1).bounced).toBe(0);
    let apex = 0;
    run(l, s, 1, 1.2, (i) => ({ mx: 0, mz: 0, jump: i === 0 }), (q) => { apex = Math.max(apex, q.p[1]); });
    expect(apex).toBeGreaterThan(jumpHeight() * 1.3);
    // rebond minimal
    const m = makeBody([0, 0.6, 0]);
    m.v[1] = -5.5;
    let up = 0;
    run(l, m, 0, 0.2, still, (q) => { up = Math.max(up, q.v[1]); });
    expect(up).toBeGreaterThan(PHYS.jellyMin - PHYS.gravity * DT - 1e-9); // 0.6 × ~6 < 4 : rebond minimal
  });

  it('ramp : géométrie, on tient debout sans glisser, on monte en suivant la pente, groundBelow suit le plan', () => {
    const l = one({ type: 'ramp', pos: [0, 1, 0], size: [4, 1, 8], rise: 3 }, floor(0));
    const e = l.elements[1] as El<'ramp'>;
    expect(rampTopAt(e, 0, -4)).toBeCloseTo(0, 9);
    expect(rampTopAt(e, 0, 4)).toBeCloseTo(3, 9);
    expect(rampTopAt(e, 0, 10)).toBeCloseTo(3, 9); // borné au bord
    const cs = rampCorners(e);
    expect(cs[4][1]).toBeCloseTo(0, 9); // dessus, −x −z
    expect(cs[7][1]).toBeCloseTo(3, 9); // dessus, +x +z
    expect(cs[3][1]).toBeCloseTo(2, 9); // dessous, +x +z
    const col = buildColliders(l, 0).find((c) => c.id === 1)!;
    expect(col.slope).toBeCloseTo(3 / 8, 9);
    expect(groundBelow(0, 5, 2, buildColliders(l, 0))).toBeCloseTo(rampTopAt(e, 0, 2), 9);
    // debout sur la pente : immobile
    const b = makeBody([0, rampTopAt(e, 0, 1) + 0.02, 1]);
    run(l, b, 0, 2);
    expect(b.grounded).toBe(true);
    expect(b.p[2]).toBeCloseTo(1, 3);
    expect(b.p[1]).toBeCloseTo(rampTopAt(e, 0, 1), 2);
    // on monte en marchant, collé à la pente
    const w = makeBody([0, 0.02, -6]);
    let off = 0;
    run(l, w, 0, 1.6, { mx: 0, mz: 1, jump: false }, (q) => { if (q.p[2] > -3.5 && q.p[2] < 3.5) off = Math.max(off, Math.abs(q.p[1] - rampTopAt(e, q.p[0], q.p[2]))); });
    expect(w.p[2]).toBeGreaterThan(3);
    expect(off).toBeLessThan(0.05);
    // et on redescend sans décoller
    let air = 0;
    run(l, w, 2, 1.2, { mx: 0, mz: -1, jump: false }, (q) => { if (q.p[2] > -3.5 && q.p[2] < 3.5 && !q.grounded) air++; });
    expect(air).toBe(0);
  });

  it('ramp slide : toboggan glissant qui accélère vers le bas', () => {
    const l = one({ type: 'ramp', pos: [0, 5, 0], size: [4, 1, 30], rise: -10, slide: true });
    const e = l.elements[1] as El<'ramp'>;
    const b = makeBody([0, rampTopAt(e, 0, -13) + 0.02, -13]);
    let maxV = 0;
    run(l, b, 0, 3.5, still, (q) => { if (q.grounded) maxV = Math.max(maxV, q.v[2]); });
    expect(b.onIce || !b.grounded).toBe(true);
    expect(maxV).toBeGreaterThan(PHYS.speed); // plus vite qu'en courant, sans rien toucher
    expect(b.p[2]).toBeGreaterThan(-13 + 5);
  });

  it('boost : vitesse portée à speed dans dir, adhérence réduite ensuite', () => {
    const l = one(floor(0), { type: 'boost', pos: [0, 0.01, 0], size: [3, 1, 3], yaw: 0.3, dir: [1, 1], speed: 18 });
    const e = l.elements[2] as El<'boost'>;
    const [vx, vz] = boostVel(e);
    expect(Math.hypot(vx, vz)).toBeCloseTo(18, 9);
    expect(vx).toBeCloseTo(vz, 9); // dir monde, indépendante du yaw
    const b = makeBody([0, 0.53, 0]);
    const r = run(l, b, 0, 0.05);
    expect(r.boosted).toBe(true);
    expect(Math.hypot(b.v[0], b.v[2])).toBeGreaterThan(17);
    run(l, b, 0.05, 0.3, { mx: 0, mz: 0, jump: false });
    expect(b.boost).toBeGreaterThan(0);
    expect(Math.hypot(b.v[0], b.v[2])).toBeGreaterThan(14); // l'élan dure
    run(l, b, 0.35, 1);
    expect(b.boost).toBe(0);
    expect(Math.hypot(b.v[0], b.v[2])).toBeLessThan(0.5); // adhérence normale revenue
  });

  it('bubble : bulles régulièrement décalées qui montent puis éclatent ; on monte avec puis on tombe', () => {
    const l = one({ type: 'bubble', pos: [0, 0, 0], size: [2, 0.4, 2], count: 4, rise: 8, period: 8 });
    const e = l.elements[1] as El<'bubble'>;
    const ps = bubbleParts(e, 1);
    expect(ps.map((p) => +p.c[1].toFixed(6))).toEqual([1, 3, 5, 7]);
    expect(ps[3].left).toBeCloseTo(1, 9);
    expect(ps[0].vel).toEqual([0, 1, 0]);
    expect(buildColliders(l, 1).filter((c) => c.id === 1).length).toBe(4);
    // sur la bulle 0 (y = 0 à t = 0) : on monte, puis elle éclate à t = 8
    const b = makeBody([0, 0.22, 0]);
    run(l, b, 0, 7.5);
    expect(b.grounded).toBe(true);
    expect(b.p[1]).toBeGreaterThan(7.3);
    run(l, b, 7.5, 0.8);
    expect(b.grounded).toBe(false);
  });
});

describe('vague 2 — propulseurs et zones', () => {
  it('launcher : tir en cloche qui atterrit exactement sur `to`, en roulé-boulé et sans contrôle', () => {
    const to: V3 = [3, 4, 14];
    const l = one(floor(0), { type: 'platform', pos: [3, 3.5, 14], size: [3, 1, 3] }, { type: 'launcher', pos: [0, 1, 0], size: [2, 2, 2], to, apex: 3 });
    const b = makeBody([0.3, 0.02, -0.2]);
    let flying = 0, maxY = 0, landedAt: V3 | null = null;
    const r = run(l, b, 0, 3, { mx: -1, mz: 0, jump: false }, (q) => {
      if (q.flight > 0) { flying++; expect(q.tumble).toBeGreaterThan(0); }
      maxY = Math.max(maxY, q.p[1]);
      if (!landedAt && q.grounded && q.p[1] > 3) landedAt = [...q.p];
    });
    expect(r.pre.launched).toBe(3);
    expect(flying).toBeGreaterThan(30);
    expect(maxY).toBeGreaterThan(6.8); // apogée ≈ max(0, 4) + 3
    expect(maxY).toBeLessThan(7.2);
    expect(landedAt).not.toBeNull();
    expect(Math.hypot(landedAt![0] - to[0], landedAt![2] - to[2])).toBeLessThan(0.15);
    // formule discrète exacte : T multiple de dt → arrivée pile sur `to`
    const { v, T } = launchVelocity([0, 0, 0], to, 3, DT);
    ballisticPoint([0, 0, 0], v, T, DT).forEach((x, k) => expect(x).toBeCloseTo(to[k], 9));
    expect(T).toBeCloseTo(Math.sqrt((2 * 7) / PHYS.gravity) + Math.sqrt((2 * 3) / PHYS.gravity), 9);
    const arc = launcherArc(l.elements[3] as El<'launcher'>, 10);
    expect(arc.length).toBe(11);
    expect(arc[10][0]).toBeCloseTo(3, 9);
    expect(arc[10][1]).toBeCloseTo(4, 9);
  });

  it('launchVelocity : l\'intégration du jeu (v.y −= g·dt ; p += v·dt) arrive sur `to` après T', () => {
    const from: V3 = [1, 2, 3], to: V3 = [-6, 0.5, 20];
    const { v, T } = launchVelocity(from, to, 2.5, DT);
    const n = Math.round(T / DT), p: V3 = [...from], vv: V3 = [...v];
    for (let i = 0; i < n; i++) { vv[1] -= PHYS.gravity * DT; p[0] += vv[0] * DT; p[1] += vv[1] * DT; p[2] += vv[2] * DT; }
    const tn = n * DT; // T n'est pas un multiple de dt : écart borné par une fraction de pas
    expect(Math.hypot(p[0] - ballisticPoint(from, v, tn, DT)[0], p[1] - ballisticPoint(from, v, tn, DT)[1])).toBeLessThan(1e-9);
    expect(Math.hypot(p[0] - to[0], p[1] - to[1], p[2] - to[2])).toBeLessThan(Math.hypot(...v) * DT);
  });

  it('jumppad : renvoie selon launch tourné par yaw, vol balistique jusqu\'au contact', () => {
    const l = one(floor(0), { type: 'jumppad', pos: [0, 0.01, 0], size: [2, 1, 2], yaw: Math.PI / 2, launch: [0, 12, 6] });
    const e = l.elements[2] as El<'jumppad'>;
    const w = jumppadVel(e);
    expect(w[0]).toBeCloseTo(6, 9); // z local → x monde
    expect(w[2]).toBeCloseTo(0, 9);
    const b = makeBody([0, 0.53, 0]);
    let vx = new Set<string>();
    const r = run(l, b, 0, 0.6, { mx: -1, mz: 0, jump: false }, (q) => { if (q.flight > 0) vx.add(q.v[0].toFixed(9)); });
    expect(r.bounced).toBeGreaterThanOrEqual(1);
    expect([...vx]).toEqual(['6.000000000']); // aucune commande pendant le vol
    run(l, b, 0.6, 1.5);
    expect(b.grounded).toBe(true);
    expect(b.p[0]).toBeGreaterThan(5.5);
  });

  it('zipline : accroche au départ, glisse à speed, lâche au bout avec l\'élan ; sauter lâche prise', () => {
    const l = one(floor(0, 6), { type: 'zipline', pos: [0, 2.1, 0], size: [0.4, 3, 0.4], to: [0, 0.6, 15], speed: 10 });
    const e = l.elements[2] as El<'zipline'>;
    const { len, dir } = zipCable(e);
    expect(len).toBeCloseTo(Math.hypot(1.5, 15), 9);
    expect(zipFeet(e, len)[1]).toBeCloseTo(0.6 - PHYS.zipHang, 9);
    // pieds à 2.1 sous le départ : mains à 0.2 du câble → accroche
    const b = makeBody([0, 0.02, 0.3]);
    let maxS = 0;
    const r = run(l, b, 0, 1, still, (q) => { if (q.zip >= 0) { maxS = q.zipS; expect(q.p[1]).toBeCloseTo(zipFeet(e, q.zipS)[1], 9); } });
    expect(r.pre.grabbed).toBe(2);
    expect(maxS).toBeCloseTo(10 * (1 - DT), 6);
    const r2 = run(l, b, 1, 1);
    expect(r2.pre.released).toBe(2);
    expect(b.zip).toBe(-1);
    expect(b.p[2]).toBeGreaterThan(15.5); // élan conservé après le bout
    // sauter = lâcher (et pas de raccrochage immédiat)
    const c = makeBody([0, 0.02, 0.3]);
    run(l, c, 0, 0.5);
    expect(c.zip).toBe(2);
    run(l, c, 0.5, DT, { mx: 0, mz: 0, jump: true });
    expect(c.zip).toBe(-1);
    expect(c.v[2]).toBeCloseTo(dir[2] * 10, 0);
    expect(c.v[1]).toBeGreaterThan(PHYS.zipHop - 1);
    run(l, c, 0.5 + DT, 0.3);
    expect(c.zip).toBe(-1); // pas de raccrochage pendant zipCool
  });

  it('teleport : pieds transportés en `to` avec exitVel, sans aller-retour', () => {
    const l = one(floor(0, 10), { type: 'platform', pos: [20, -0.5, 0], size: [6, 1, 6] }, { type: 'teleport', pos: [0, 1, 0], size: [2, 2, 2], to: [20, 0.5, 0], exitVel: [0, 3, 2] });
    const b = makeBody([0.2, 0.02, -0.2]);
    const r = run(l, b, 0, 0.02);
    expect(r.pre.teleported).toBe(3);
    expect(b.p[0]).toBeCloseTo(20, 9);
    expect(b.v[2]).toBeCloseTo(2 - PHYS.accelAir * DT, 9); // contrôle en l'air dès le pas du transport
    expect(b.cool).toBeGreaterThan(0);
    run(l, b, 0.02, 1.5);
    expect(b.grounded).toBe(true);
    expect(b.groundId).toBe(2);
    expect(inZone(l.elements[3], [0, 0, 0])).toBe(true);
  });

  it('lowgrav : gravité réduite dans la zone (saut bien plus haut), normale dehors', () => {
    const l = one(floor(0), { type: 'lowgrav', pos: [0, 5, 0], size: [10, 10, 10], gravity: 0.35 });
    expect(lowgravAt(l, [0, 0, 0])).toBe(0.35);
    expect(lowgravAt(l, [0, 0, 8])).toBe(1);
    const b = makeBody([0, 0.02, 0]);
    run(l, b, 0, 0.3);
    let apex = 0;
    run(l, b, 0.3, 3, (i) => ({ mx: 0, mz: 0, jump: i === 0 }), (q) => { apex = Math.max(apex, q.p[1]); });
    expect(apex).toBeGreaterThan(jumpHeight(PHYS.jumpV, PHYS.gravity * 0.35) * 0.9); // le pas du saut perd la compensation (v.y écrasé)
    expect(apex).toBeLessThan(jumpHeight(PHYS.jumpV, PHYS.gravity * 0.35) * 1.05);
    expect(jumpReach(0, PHYS.jumpV, PHYS.speed, PHYS.gravity * 0.35)).toBeCloseTo(jumpReach(0) / 0.35, 9);
  });

  it('wind : rafales qui pulsent, déportent un joueur en l\'air', () => {
    const l = one({ type: 'wind', pos: [0, 5, 0], size: [10, 10, 10], force: [30, 0, 0], period: 2, phase: 0.25 });
    const e = l.elements[1] as El<'wind'>;
    expect(windGust(e, 0)).toBeCloseTo(1, 9);
    expect(windGust(e, 1)).toBeCloseTo(0, 9);
    expect(windAccel(l, [0, 1, 0], 0)[0]).toBeCloseTo(30, 9);
    expect(windAccel(l, [0, 1, 0], 0.5)[0]).toBeCloseTo(15, 9);
    expect(windAccel(l, [0, 20, 0], 0)).toEqual([0, 0, 0]);
    const b = makeBody([0, 8, 0]);
    run(l, b, 0, 0.3); // en chute libre, sans commande
    expect(b.v[0]).toBeGreaterThan(1); // 30 m/s² de rafale contre 20 m/s² de contrôle en l'air
    // sans l'horloge (t par défaut), la pré-étape reste déterministe
    expect(windGust(e, 0)).toBe(windGust(e, 0));
  });
});

describe('vague 2 — validation et killY', () => {
  const S = { type: 'start' as const, pos: [0, -0.5, 0] as V3, size: [8, 1, 8] as V3 };
  it('launcher, teleport, zipline et jumppad sont des liens vers leur point d\'arrivée', () => {
    const F = { type: 'finish' as const, pos: [0, 4.5, 30] as V3, size: [6, 1, 6] as V3 };
    const base = [S, F];
    expect(validateLevel(mk(base)).ok).toBe(false);
    expect(validateLevel(mk([...base, { type: 'launcher', pos: [0, 1, 2], size: [2, 2, 2], to: [0, 5, 30] }])).path).toEqual([0, 2, 1]);
    expect(validateLevel(mk([...base, { type: 'teleport', pos: [0, 1, 2], size: [2, 2, 2], to: [0, 5.5, 30] }])).ok).toBe(true);
    expect(validateLevel(mk([...base, { type: 'teleport', pos: [0, 1, 2], size: [2, 2, 2], to: [0, 5.5, 50] }])).ok).toBe(false); // sortie dans le vide
    expect(validateLevel(mk([...base, { type: 'zipline', pos: [0, 1.95, 3], size: [0.4, 3, 0.4], to: [0, 7, 27], speed: 8 }])).ok).toBe(true);
    // trampoline directionnel : la parabole partie du centre retombe sur l'arrivée
    const pad = { type: 'jumppad' as const, pos: [0, -0.5, 5] as V3, size: [2, 1, 2] as V3 };
    const t = 18 / 24; // vy = 18 : montée 0.75 s
    const vz = 25 / (t + Math.sqrt((2 * (18 * 18 / 48 - 5)) / 24));
    expect(validateLevel(mk([...base, { ...pad, launch: [0, 18, vz] }])).ok).toBe(true);
    expect(validateLevel(mk([...base, { ...pad, launch: [0, 18, vz * 0.6] }])).ok).toBe(false);
  });

  it('boost, lowgrav, boue, toboggan : portées adaptées', () => {
    const P = (z: number, y = -0.5, sz = 4): LevelInput['elements'][number] => ({ type: 'platform', pos: [0, y, z], size: [4, 1, sz] });
    const F = (z: number, y = -0.5) => ({ type: 'finish' as const, pos: [0, y, z] as V3, size: [4, 1, 4] as V3 });
    // vide de 8 m : infranchissable sans élan, franchissable depuis un speed pad orienté vers l'arrivée
    expect(validateLevel(mk([S, F(14)])).ok).toBe(false);
    expect(validateLevel(mk([S, { type: 'boost', pos: [0, -0.5, 6], size: [4, 1, 4], dir: [0, 1] }, F(18)])).ok).toBe(true);
    expect(validateLevel(mk([S, { type: 'boost', pos: [0, -0.5, 6], size: [4, 1, 4], dir: [1, 0] }, F(18)])).ok).toBe(false);
    // 3 m de dénivelé : seulement en zone lunaire
    expect(validateLevel(mk([S, F(6, 2.5)])).ok).toBe(false);
    expect(validateLevel(mk([S, F(6, 2.5), { type: 'lowgrav', pos: [0, 3, 3], size: [10, 8, 14] }])).ok).toBe(true);
    // boue : on saute moins loin
    expect(validateLevel(mk([S, { type: 'mud', pos: [0, -0.5, 6], size: [4, 1, 4] }, F(11)])).ok).toBe(true);
    expect(validateLevel(mk([S, { type: 'mud', pos: [0, -0.5, 6], size: [4, 1, 4] }, F(13.5)])).ok).toBe(false);
    expect(validateLevel(mk([S, P(6), F(13.5)])).ok).toBe(true);
    // toboggan : on le descend, on ne repart pas de son sommet
    const slide = { type: 'ramp' as const, pos: [0, 2, 10] as V3, size: [4, 1, 12] as V3, rise: 4, slide: true };
    expect(validateLevel(mk([S, slide, F(19, 4)])).ok).toBe(false);
    expect(validateLevel(mk([S, { ...slide, slide: false }, F(19, 4)])).ok).toBe(true);
    expect(validateLevel(mk([S, { ...slide, slide: false, rise: 10 }, F(19, 4)])).warnings.some((w) => w.includes('raide'))).toBe(true);
  });

  it('killY tient compte des rampes et de la tyrolienne', () => {
    const l = mk([S, { type: 'ramp', pos: [0, -2, 10], size: [4, 1, 8], rise: 6 }, { type: 'zipline', pos: [0, 2, 0], size: [0.4, 3, 0.4], to: [0, -3, 20] }, F0()]);
    expect(elementBottom(l.elements[1])).toBeCloseTo(-5.5, 9);
    expect(elementBottom(l.elements[2])).toBeCloseTo(-3 - PHYS.zipHang, 9);
    expect(levelKillY(l)).toBeCloseTo(-5.5 - 12, 9);
  });
});

function F0() {
  return { type: 'finish' as const, pos: [0, -0.5, 40] as V3, size: [4, 1, 4] as V3 };
}
