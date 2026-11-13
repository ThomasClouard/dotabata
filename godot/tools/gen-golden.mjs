// Génère les vecteurs de référence des tests de parité à partir des sources TypeScript d'origine
// (importées en lecture seule). À lancer depuis la racine du dépôt :
//   node --import tsx godot/tools/gen-golden.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeBody, stepBody, pushApart, groundBelow, clearMotionState, jumpHeight, jostle, PHYS } from '../../shared/src/physics.ts';
import { poseFlags } from '../../shared/src/protocol.ts';
import {
  buildColliders, fanAccel, levelKillY, topOf, onPad, LevelSchema, frac, cannonPulse, rollerAngle, gatePart, gateProfile,
  spinAngle, crusherGap, blinkState, boulderBalls, elementBottom, fogAt, HITTERS,
  inZone, rampSlope, rampTopAt, rampCorners, boostVel, jumppadVel, launchVelocity, ballisticPoint, launcherArc, zipCable, zipFeet,
  bubbleParts, windGust, windAccel, lowgravAt,
  hash01, popperState, geyserState, rockfallStones,
  newLevelState, linkOpen, doorOpenness, leverDown, boxReady, memoryKey, memoryTiles, memoryTileAt, standsOn, touches,
} from '../../shared/src/level.ts';
import { readLevel, listLevels, LEVELS_DIR } from '../../shared/src/level-store.ts';
import { parkourPreStep, parkourPostStep, formatTime, applyLevelMsg, applyEffectMsg, parkourJostle, memoryLayout } from '../../games/parkour/shared.ts';
import * as mortar from '../../games/mortar/shared.ts';
import { validateLevel } from '../../shared/src/level-validate.ts';
import { sanitizeSettings, buildRoundList, scoreRound, ranksFromGroups } from '../../shared/src/scoring.ts';
import { gameMetas } from '../../games/registry.ts';

const OUT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'tests', 'golden');
fs.mkdirSync(OUT, { recursive: true });
const H = 1 / 60;

// générateur pseudo-aléatoire déterministe (les entrées sont de toute façon enregistrées dans le fichier)
let seed = 12345;
const rnd = () => { seed = (seed * 48271) % 2147483647; return seed / 2147483647; };

const colOut = (c) => ({ id: c.id, tag: c.tag ?? '', c: c.c, h: c.h, yaw: c.yaw, vel: c.vel ?? [0, 0, 0], angVel: c.angVel ?? 0, ice: !!c.ice, bounce: c.bounce ?? 0, conveyor: c.conveyor ?? null,
  slow: c.slow ?? 0, jump: c.jump ?? 0, jelly: c.jelly ?? 0, slope: c.slope ?? 0, slide: !!c.slide, boost: c.boost ?? null, launch: c.launch ?? null });
const bodyOut = (b) => ({ p: [...b.p], v: [...b.v], grounded: b.grounded, groundId: b.groundId, groundVel: [...b.groundVel], onIce: b.onIce, coyote: b.coyote, tumble: b.tumble,
  slow: b.slow, jumpK: b.jumpK, boost: b.boost, flight: b.flight, zip: b.zip, zipS: b.zipS, cool: b.cool, superJump: b.superJump, shield: b.shield });

function inputs(steps) {
  const out = [];
  let mx = 0, mz = 0, jump = false;
  for (let i = 0; i < steps; i++) {
    if (i % 17 === 0) { const a = rnd() * Math.PI * 2, k = rnd() < 0.15 ? 0 : 1; mx = Math.sin(a) * k; mz = Math.cos(a) * k; }
    if (i % 11 === 0) jump = rnd() < 0.45;
    out.push([mx, mz, jump]);
  }
  return out;
}

// ---------- physique seule : terrain du lobby (trampoline, marches tournées, barre tournante) ----------
{
  const cols = [
    { id: 0, c: [0, -0.75, 0], h: [16, 0.75, 16], yaw: 0 },
    { id: 1, c: [6, 0.25, 6], h: [1.5, 0.25, 1.5], yaw: 0, bounce: 15 },
    { id: 2, c: [-6, 0.5, 5], h: [1.5, 0.5, 1.5], yaw: 0.4 },
    { id: 3, c: [-8.5, 1, 7.5], h: [1.5, 1, 1.5], yaw: 0.4 },
    { id: 4, c: [-11, 1.5, 10], h: [1.5, 1.5, 1.5], yaw: 0.4 },
    { id: 5, c: [3, 0.45, -3], h: [3, 0.3, 0.3], yaw: 0, angVel: 1.4 },
    { id: 6, c: [-3, 0.2, -2], h: [2, 0.2, 2], yaw: 0.2, ice: true },
    { id: 7, c: [2, 0.2, 3], h: [1.5, 0.2, 1.5], yaw: -0.3, conveyor: [2, -1] },
  ];
  const steps = 1500, inp = inputs(steps), states = [];
  const b = makeBody([1, 2, 1]);
  const other = [2.2, 0, 1.4];
  for (let i = 0; i < steps; i++) {
    cols[5].yaw = i * H * 1.4;
    stepBody(b, { mx: inp[i][0], mz: inp[i][1], jump: inp[i][2] }, cols, H);
    pushApart(b, other);
    if (b.p[1] < -9) { b.p = [0, 3, 0]; b.v = [0, 0, 0]; }
    if (i % 10 === 9) states.push({ ...bodyOut(b), ground: groundBelow(b.p[0], b.p[1] + 0.3, b.p[2], cols) });
  }
  fs.writeFileSync(path.join(OUT, 'physics.json'), JSON.stringify({ cols: cols.map(colOut), other, inputs: inp, states }));
}

// ---------- niveaux : boîtes de collision à plusieurs instants, puis une course simulée ----------
{
  const levels = [];
  for (const name of listLevels()) {
    const level = readLevel(name);
    const crumbleIdx = level.elements.findIndex((e) => e.type === 'crumble');
    const crumbled = new Map();
    if (crumbleIdx >= 0) crumbled.set(crumbleIdx, 1.0);
    const times = [0, 0.37, 1.2, 1.9, 3.3, 7.25, 33.3, 1234.567];
    const snapshots = times.map((t) => ({ t, cols: buildColliders(level, t, crumbled).map(colOut) }));
    const fans = [];
    for (const e of level.elements) if (e.type === 'fan') fans.push({ p: [e.pos[0] + 0.1, e.pos[1] - 0.3, e.pos[2] - 0.1], a: fanAccel(level, [e.pos[0] + 0.1, e.pos[1] - 0.3, e.pos[2] - 0.1]) });

    // course : entrées enregistrées, réapparition au départ après une chute
    const start = level.elements.find((e) => e.type === 'start');
    const spawn = [start.pos[0], topOf(start) + 0.2, start.pos[2]];
    const killY = levelKillY(level);
    const steps = 1800, inp = inputs(steps), states = [];
    const b = makeBody(spawn);
    const run = new Map();
    let knocks = 0, bounces = 0;
    for (let i = 0; i < steps; i++) {
      const t = 3 + i * H;
      const cols = buildColliders(level, t, run);
      parkourPreStep(level, b, H);
      const contacts = stepBody(b, { mx: inp[i][0], mz: inp[i][1], jump: inp[i][2] }, cols, H);
      const ev = parkourPostStep(b, contacts);
      if (ev.knocked) knocks++;
      if (ev.bounced) bounces++;
      for (const k of ev.crumble) {
        const e = level.elements[k], at = run.get(k);
        if (at === undefined || t >= at + e.delay + e.respawn) run.set(k, t);
      }
      if (ev.killed || b.p[1] < killY) { b.p = [...spawn]; b.v = [0, 0, 0]; b.tumble = 0; }
      if (i % 10 === 9) states.push(bodyOut(b));
    }
    // lâcher du personnage sur (ou contre) chaque élément : couvre trampolines, tapis, glace, marteaux, canons…
    const drops = [];
    level.elements.forEach((e, k) => {
      const t0 = 5 + k * 0.37;
      const col = buildColliders(level, t0).find((c) => c.id === k);
      const at = col ? [col.c[0] - (k % 2 ? 0.9 : 0), col.c[1] + col.h[1] + (k % 3 === 0 ? 0.05 : 1.2), col.c[2]] : [e.pos[0], e.pos[1] - e.size[1] / 2 + 0.2, e.pos[2]];
      const d = makeBody(at), seen = new Map(), st = [];
      let kn = 0, bo = 0;
      for (let i = 0; i < 150; i++) {
        const t = t0 + i * H;
        parkourPreStep(level, d, H);
        const contacts = stepBody(d, { mx: 0.6, mz: k % 2 ? 0.3 : -0.3, jump: i % 40 === 20 }, buildColliders(level, t, seen), H);
        const ev = parkourPostStep(d, contacts);
        if (ev.knocked) kn++;
        if (ev.bounced) bo++;
        for (const c of ev.crumble) if (!seen.has(c)) seen.set(c, t);
        if (i % 10 === 9) st.push(bodyOut(d));
      }
      drops.push({ k, t0, at, states: st, knocks: kn, bounces: bo });
    });
    levels.push({ level, crumbleIdx, snapshots, fans, killY, spawn, inputs: inp, states, knocks, bounces, drops });
  }
  fs.writeFileSync(path.join(OUT, 'levels.json'), JSON.stringify({ levels, times: [0, 9.96, 59.94, 61.5, 125.25].map((s) => ({ s, text: formatTime(s) })) }));
}

// ---------- vague 1 (et 4) : niveau d'essai avec tous les nouveaux types (tests/fixtures/parkour/<name>.json) ----------
waveLevel('vague1');
function waveLevel(name) {
  const file = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'tests', 'fixtures', 'parkour', name + '.json');
  const raw = { ...JSON.parse(fs.readFileSync(file, 'utf8')), name };
  const level = LevelSchema.parse(raw);
  // boîtes à de nombreux instants (toutes les phases des cycles : chute de guillotine, dalles absentes, plusieurs boules…)
  const times = [];
  // (+0.0007 : évite de tomber pile sur une frontière de cycle, que la relecture JSON de Godot peut décaler d'un ulp)
  for (let i = 0; i < 48; i++) times.push(i * 0.29 + (i % 5) * 0.013 + 0.0007);
  times.push(77.77, 1234.567, 9999.25);
  const snapshots = times.map((t) => ({ t, cols: buildColliders(level, t).map(colOut) }));
  // fonctions pures du rendu, à quelques instants
  const pure = [];
  for (const t of [0, 0.41, 1.7, 2.95, 5.5, 13.13, 600.3]) {
    const r = { t, els: [] };
    level.elements.forEach((e, i) => {
      const o = { i };
      if (e.type === 'roller') o.roll = rollerAngle(e, t);
      if (e.type === 'gate') { const g = gatePart(e, t); o.untilFall = g.untilFall; o.profile = gateProfile(frac(t / e.period + e.phase)); }
      if (e.type === 'turntable' || e.type === 'sweeper') o.spin = spinAngle(e, t);
      if (e.type === 'crusher') o.gap = crusherGap(e, t);
      if (e.type === 'blink') o.blink = blinkState(e, t);
      if (e.type === 'boulder') o.balls = boulderBalls(e, t).map((b) => ({ c: b.c, k: b.k, roll: b.roll }));
      if (e.type === 'puncher') o.pulse = cannonPulse(frac(t / e.period + e.phase));
      if (e.type === 'popper') o.pop = Array.from({ length: e.cols * e.rows }, (_, k) => popperState(e, k, t, i));
      if (e.type === 'geyser') o.geyser = geyserState(e, t);
      if (e.type === 'rockfall') o.stones = rockfallStones(e, t, i).map((s) => ({ c: s.c, k: s.k, f: s.f, x: s.x, z: s.z }));
      r.els.push(o);
    });
    pure.push(r);
  }
  const bottoms = level.elements.map((e) => elementBottom(e));
  const fogPts = [[0, 3, 63.5], [4.9, 6.9, 58], [5.1, 3, 63.5], [0, -1.2, 63.5], [0, 7.2, 69.4], [0, 1, 20], [-3, 0, 60]];
  const fog = fogPts.map((p) => ({ p, f: fogAt(level, p) ?? null }));

  // course « pilotée » vers l'avant (+z) : réapparition au dernier checkpoint après une chute ou la lave
  const start = level.elements.find((e) => e.type === 'start');
  const cpIdx = level.elements.map((e, i) => (e.type === 'checkpoint' ? i : -1)).filter((i) => i >= 0);
  const killY = levelKillY(level);
  const steps = 4800, inp = [];
  for (let i = 0; i < steps; i++) {
    if (i % 23 === 0) seed = (seed * 48271) % 2147483647;
    const wob = Math.sin(i * 0.05) * 0.35 + ((seed % 7) - 3) * 0.04;
    inp.push([wob, 1, i % 37 < 12 || rnd() < 0.08]);
  }
  const spawnOf = (cp) => { const e = cp < 0 ? start : level.elements[cpIdx[cp]]; return [e.pos[0], topOf(e) + 0.2, e.pos[2]]; };
  let cp = -1, spawn = spawnOf(-1);
  const b = makeBody(spawn), states = [];
  let knocks = 0, bounces = 0, kills = 0, falls = 0;
  for (let i = 0; i < steps; i++) {
    const t = 3 + i * H;
    const cols = buildColliders(level, t);
    parkourPreStep(level, b, H);
    const contacts = stepBody(b, { mx: inp[i][0], mz: inp[i][1], jump: inp[i][2] }, cols, H);
    const ev = parkourPostStep(b, contacts);
    if (ev.knocked) knocks++;
    if (ev.bounced) bounces++;
    if (cp + 1 < cpIdx.length && onPad(level.elements[cpIdx[cp + 1]], b.p)) { cp++; spawn = spawnOf(cp); }
    if (ev.killed || b.p[1] < killY) {
      if (ev.killed) kills++; else falls++;
      b.p = [...spawn]; b.v = [0, 0, 0]; b.tumble = 0;
    }
    if (i % 10 === 9) states.push({ ...bodyOut(b), cp, killed: ev.killed, hazard: ev.hazard });
  }
  // lâchers sur chaque élément à trois instants, et approche latérale contre chaque obstacle
  const drops = [];
  const runDrop = (k, n, t0, at, mx, mz, jumps) => {
    const d = makeBody(at), st = [];
    let kn = 0, bo = 0, ki = 0;
    for (let i = 0; i < 150; i++) {
      const t = t0 + i * H;
      parkourPreStep(level, d, H);
      const contacts = stepBody(d, { mx, mz, jump: jumps && i % 40 === 20 }, buildColliders(level, t), H);
      const ev = parkourPostStep(d, contacts);
      if (ev.knocked) kn++;
      if (ev.bounced) bo++;
      if (ev.killed) ki++;
      if (i % 10 === 9) st.push(bodyOut(d));
    }
    drops.push({ k, n, t0, at, mx, mz, jumps, states: st, knocks: kn, bounces: bo, kills: ki });
  };
  level.elements.forEach((e, k) => {
    for (let n = 0; n < 4; n++) {
      const t0 = 5 + k * 0.37 + n * 1.13;
      const cs = buildColliders(level, t0).filter((c) => c.id === k);
      const col = cs[n % Math.max(1, cs.length)];
      let at, mx = 0.6, mz = k % 2 ? 0.3 : -0.3;
      if (!col) at = [e.pos[0], e.pos[1] - e.size[1] / 2 + 0.2, e.pos[2]];
      else if (n < 3) at = [col.c[0] - (k % 2 ? 0.9 : 0), col.c[1] + col.h[1] + (n === 0 ? 0.05 : 1.2), col.c[2]];
      else { at = [col.c[0] - Math.cos(col.yaw) * (col.h[0] + 1.2), col.c[1] - 0.7, col.c[2] + Math.sin(col.yaw) * (col.h[0] + 1.2)]; mx = Math.cos(col.yaw); mz = -Math.sin(col.yaw); }
      runDrop(k, n, t0, at, mx, mz, true);
    }
    // embuscades : joueur immobile là où une partie de l'obstacle sera 0.5 s plus tard (frappes de tous les HITTERS)
    if (HITTERS.has(e.type)) {
      for (let n = 0; n < 10; n++) {
        const t0 = 3 + n * 0.55;
        const cs = buildColliders(level, t0 + 0.5).filter((c) => c.id === k);
        if (!cs.length) continue;
        const col = cs[n % cs.length];
        runDrop(k, 4 + n, t0, [col.c[0] + 0.1, col.c[1] - 0.7, col.c[2] - 0.1], 0, 0, false);
      }
    }
  });
  const hashes = [[0, 0], [1, 2], [7, -3], [-5, 11], [1234, 98765], [64 * 40 + 3, 4321], [-1, -1]].map(([a, b]) => [a, b, hash01(a, b)]);
  fs.writeFileSync(path.join(OUT, name + '.json'), JSON.stringify({ level, raw, snapshots, pure, bottoms, fog, killY, cpIdx, inputs: inp, states, knocks, bounces, kills, falls, drops, hashes }));
  console.log(`${name} : course ${knocks} éjections, ${kills} morts (lave), ${falls} chutes, checkpoint final ${cp}`);
}

// ---------- mortier : géométrie de l'arène et balistique ----------
{
  const rings = [];
  for (let n = 1; n <= 10; n++) {
    const plots = [];
    for (let i = 0; i < n; i++) {
      const wx = 3.3 * Math.sin(i * 1.7) + mortar.plotCenter(i, n)[0], wz = 2.1 * Math.cos(i * 0.9) + mortar.plotCenter(i, n)[2];
      plots.push({
        center: mortar.plotCenter(i, n), yaw: mortar.plotYaw(i, n), w: [wx, wz],
        local: mortar.toLocal(i, n, wx, wz), world: mortar.toWorld(i, n, 1.25, -2.5),
        block: mortar.blockCenter({ plot: i, x: 2, y: 1, z: 5 }, n), cell: mortar.cellAt(i, n, wx, wz),
      });
    }
    rings.push({ n, radius: mortar.ringRadius(n), plots });
  }
  const shots = [];
  for (const [yaw, power] of [[0, 0], [0.7, 0.25], [2.1, 0.5], [-1.3, 0.8], [3.9, 1], [1, 1.4]]) {
    const l = mortar.launch([1.5, 0.2, -2.5], yaw, power);
    shots.push({ yaw, power, p: l.p, v: l.v, range: mortar.shellRange(l.p, l.v), range2: mortar.shellRange(l.p, l.v, 2), at: [0, 0.4, 1.7].map((t) => mortar.shellAt(l.p, l.v, t)) });
  }
  const zone = [[0, 10, 45], [10, 10, 45], [20, 10, 45], [45, 10, 45], [60, 10, 45], [5, 30, 30]].map(([t, s, e]) => ({ t, s, e, r: mortar.zoneRadius(t, s, e) }));
  const blocks = [
    { plot: 1, x: 0, y: 0, z: 0, mat: 'wood', hp: 1 }, { plot: 1, x: 0, y: 1, z: 0, mat: 'tramp', hp: 2 },
    { plot: 2, x: 3, y: 0, z: 4, mat: 'stone', hp: 3 }, { plot: 1, x: 7, y: 0, z: 7, mat: 'stone', hp: 3 },
  ];
  const map = new Map(blocks.map((b) => [mortar.blockKey(b.plot, b.x, b.y, b.z), b]));
  fs.writeFileSync(path.join(OUT, 'mortar.json'), JSON.stringify({
    rings, shots, zone, blocks, cols: mortar.mortarColliders(5, blocks, 1).map(colOut),
    heights: [[1, 0, 0], [1, 7, 7], [2, 3, 4], [1, 3, 3]].map(([p, x, z]) => ({ p, x, z, h: mortar.columnHeight(map, p, x, z) })),
  }));
}

// ---------- vague 2 : sols spéciaux et propulseurs (tests/fixtures/parkour/vague2.json) ----------
{
  // physique seule : terrain avec rampes (dont un toboggan), boue, gélatine, speed pad, trampoline directionnel
  const cols = [
    { id: 0, c: [0, -0.75, 0], h: [18, 0.75, 18], yaw: 0 },
    { id: 1, c: [6, 0.5, 4], h: [2, 0.5, 4], yaw: 0.35, slope: 0.4 },
    { id: 2, c: [-6, 1.5, 6], h: [1.6, 0.4, 5], yaw: -0.2, slope: -0.45, slide: true },
    { id: 3, c: [3, 0.1, -5], h: [2.5, 0.1, 2], yaw: 0.1, slow: 0.45, jump: 0.6 },
    { id: 4, c: [-4, 0.15, -4], h: [2, 0.15, 2], yaw: 0, jelly: 0.6, jump: 1.2 },
    { id: 5, c: [0, 0.1, 8], h: [1.5, 0.1, 1.5], yaw: 0.6, boost: [12, -9] },
    { id: 6, c: [-9, 0.15, -9], h: [1, 0.15, 1], yaw: 0, launch: [5, 13, 3] },
    { id: 7, c: [-4, 3, -4], h: [1, 0.2, 1], yaw: 0.3 },
  ];
  const steps = 2400, inp = inputs(steps), states = [];
  const b = makeBody([1, 2, 1]);
  for (let i = 0; i < steps; i++) {
    stepBody(b, { mx: inp[i][0], mz: inp[i][1], jump: inp[i][2] }, cols, H);
    if (b.p[1] < -9 || Math.abs(b.p[0]) > 17 || Math.abs(b.p[2]) > 17) { b.p = [((i * 7) % 11) - 5, 3, ((i * 5) % 9) - 4]; b.v = [0, 0, 0]; clearMotionState(b); }
    if (i % 10 === 9) states.push({ ...bodyOut(b), ground: groundBelow(b.p[0], b.p[1] + 0.3, b.p[2], cols) });
  }
  const probes = [];
  for (let k = 0; k < 40; k++) { const x = -10 + ((k * 7.3) % 20), z = -10 + ((k * 4.1) % 20), y = 0.5 + (k % 5) * 0.8; probes.push({ p: [x, y, z], g: groundBelow(x, y, z, cols) }); }

  const file = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'tests', 'fixtures', 'parkour', 'vague2.json');
  const raw = { ...JSON.parse(fs.readFileSync(file, 'utf8')), name: 'vague2' };
  const level = LevelSchema.parse(raw);
  const times = [];
  for (let i = 0; i < 40; i++) times.push(i * 0.37 + (i % 3) * 0.011 + 0.0007);
  times.push(88.8, 1234.567);
  const snapshots = times.map((t) => ({ t, cols: buildColliders(level, t).map(colOut) }));
  // fonctions pures
  const els = level.elements.map((e, i) => {
    const o = { i, bottom: elementBottom(e) };
    if (e.type === 'ramp') { o.slope = rampSlope(e); o.corners = rampCorners(e); o.tops = [[0, 35], [1.5, 38], [-2, 41.7], [0, 100], [0.3, 183]].map(([x, z]) => rampTopAt(e, x, z)); }
    if (e.type === 'boost') o.boost = boostVel(e);
    if (e.type === 'jumppad') o.launch = jumppadVel(e);
    if (e.type === 'launcher') { o.arc = launcherArc(e); o.arc7 = launcherArc(e, 7); }
    if (e.type === 'zipline') { const c = zipCable(e); o.cable = c; o.feet = [-1, 0, 3.3, 9.9, 50].map((q) => zipFeet(e, q)); }
    if (e.type === 'bubble') o.bubbles = [0, 0.9, 3.4, 6.99, 77.7].map((t) => ({ t, parts: bubbleParts(e, t).map((p) => ({ c: p.c, u: p.u, left: p.left })) }));
    if (e.type === 'wind') o.gust = [0, 0.4, 1.1, 2.9, 333.3].map((t) => windGust(e, t));
    return o;
  });
  const pts = [];
  for (let k = 0; k < 60; k++) pts.push([((k * 3.7) % 9) - 4.5, 2 + ((k * 1.3) % 12), 145 + ((k * 2.9) % 40)]);
  pts.push([0, 3, 118], [0.9, 1.01, 118.7], [0, 9, 152], [3.9, 10, 171]);
  const zones = pts.map((p, k) => ({ p, t: k * 0.23, wind: windAccel(level, p, k * 0.23), g: lowgravAt(level, p), inz: level.elements.map((e) => inZone(e, p)) }));
  const launches = [[[0, 3, 66], [0, 3, 81], 3, H], [[0.4, 3.2, 65.5], [0, 3, 81], 3, H], [[1, 0, 0], [-4, 9, 12], 0.5, 0], [[0, 10, 0], [5, 1, -7], 6, 1 / 30]].map(([from, to, apex, dt]) => {
    const l = launchVelocity(from, to, apex, dt);
    return { from, to, apex, dt, v: l.v, T: l.T, pts: [0, 0.3, l.T / 2, l.T].map((q) => ballisticPoint(from, l.v, q, dt)) };
  });
  const misc = { jh: jumpHeight(9, 24 * 0.35), jh2: jumpHeight(10.8) };

  // course pilotée vers +z, réapparition au dernier checkpoint (avec clearMotionState)
  const start = level.elements.find((e) => e.type === 'start');
  const cpIdx = level.elements.map((e, i) => (e.type === 'checkpoint' ? i : -1)).filter((i) => i >= 0);
  const killY = levelKillY(level);
  const spawnOf = (cp) => { const e = cp < 0 ? start : level.elements[cpIdx[cp]]; return [e.pos[0], topOf(e) + 0.2, e.pos[2]]; };
  const runRace = (steps, mkInput, cp0 = -1) => {
    let cp = cp0, spawn = spawnOf(cp0);
    const b = makeBody(spawn), states = [], inp = [];
    const n = { knocks: 0, bounces: 0, falls: 0, boosted: 0, launched: 0, teleported: 0, grabbed: 0, released: 0 };
    for (let i = 0; i < steps; i++) {
      const t = 3 + i * H;
      const ip = mkInput(i, b); inp.push(ip);
      const pre = parkourPreStep(level, b, H, t);
      if (pre.launched >= 0) n.launched++;
      if (pre.teleported >= 0) n.teleported++;
      if (pre.grabbed >= 0) n.grabbed++;
      if (pre.released >= 0) n.released++;
      const contacts = stepBody(b, { mx: ip[0], mz: ip[1], jump: ip[2] }, buildColliders(level, t), H);
      const ev = parkourPostStep(b, contacts);
      if (ev.knocked) n.knocks++;
      if (ev.bounced) n.bounces++;
      if (ev.boosted) n.boosted++;
      if (cp + 1 < cpIdx.length && onPad(level.elements[cpIdx[cp + 1]], b.p)) { cp++; spawn = spawnOf(cp); }
      if (ev.killed || b.p[1] < killY) { n.falls++; b.p = [...spawn]; b.v = [0, 0, 0]; b.tumble = 0; clearMotionState(b); }
      if (i % 10 === 9) states.push({ ...bodyOut(b), cp, pre, boosted: ev.boosted, bounced: ev.bounced });
    }
    return { cp0, inputs: inp, states, ...n, cp };
  };
  // pilote « bot naïf » : avance vers +z en visant x = 0, saute régulièrement (entrées enregistrées)
  const races = [
    runRace(5400, (i, b) => [Math.max(-1, Math.min(1, -b.p[0] * 0.5)) * 0.6, 1, i % 45 < 10]),
    runRace(3000, (i) => [Math.sin(i * 0.031) * 0.5, i % 300 < 40 ? -0.4 : 1, i % 29 < 6 || rnd() < 0.05]),
    ...[0, 1, 2, 3].map((c) => runRace(1500, (i, b) => [Math.max(-1, Math.min(1, -b.p[0] * 0.5)) * 0.6, 1, i % 45 < 10], c)),
  ];
  // lâchers sur / dans chaque élément à plusieurs instants (zones : pieds au bas de la zone ; tyrolienne : sous le départ)
  const drops = [];
  level.elements.forEach((e, k) => {
    for (let n = 0; n < 4; n++) {
      const t0 = 4 + k * 0.41 + n * 1.37;
      const cs = buildColliders(level, t0).filter((c) => c.id === k);
      const col = cs[n % Math.max(1, cs.length)];
      let at;
      if (!col) at = [e.pos[0] + (n - 1.5) * 0.3, e.pos[1] - e.size[1] / 2 + 0.2 + (n === 3 ? 0.5 : 0), e.pos[2] + (n % 2 ? 0.3 : -0.3)];
      else if (n < 3) at = [col.c[0] - (k % 2 ? 0.9 : 0), col.c[1] + col.h[1] + (n === 0 ? 0.05 : n === 1 ? 1.2 : 3.5), col.c[2]];
      else at = [col.c[0] - Math.cos(col.yaw) * (col.h[0] + 1.2), col.c[1] - 0.7, col.c[2] + Math.sin(col.yaw) * (col.h[0] + 1.2)];
      const mx = n === 3 ? 0.8 : 0.4 * (k % 2 ? 1 : -1), mz = n === 2 ? -0.7 : 0.5;
      const d = makeBody(at), st = [];
      const c = { kn: 0, bo: 0, bs: 0, pre: 0 };
      for (let i = 0; i < 240; i++) {
        const t = t0 + i * H;
        const pre = parkourPreStep(level, d, H, t);
        if (pre.launched >= 0 || pre.teleported >= 0 || pre.grabbed >= 0 || pre.released >= 0) c.pre++;
        const contacts = stepBody(d, { mx, mz, jump: i % 50 === 25 }, buildColliders(level, t), H);
        const ev = parkourPostStep(d, contacts);
        if (ev.knocked) c.kn++;
        if (ev.bounced) c.bo++;
        if (ev.boosted) c.bs++;
        if (i % 10 === 9) st.push(bodyOut(d));
      }
      drops.push({ k, n, t0, at, mx, mz, states: st, knocks: c.kn, bounces: c.bo, boosts: c.bs, pres: c.pre });
    }
  });
  fs.writeFileSync(path.join(OUT, 'vague2.json'), JSON.stringify({
    physics: { cols: cols.map(colOut), inputs: inp, states, probes },
    level, raw, snapshots, els, zones, launches, misc, killY, cpIdx, races, drops,
  }));
  for (const r of races) console.log(`vague2 : course depuis cp ${r.cp0} → checkpoint ${r.cp}, ${r.launched} tirs, ${r.teleported} téléports, ${r.grabbed} tyroliennes, ${r.boosted} pas sur le speed pad, ${r.bounces} rebonds, ${r.falls} chutes ; lâchers : ${drops.reduce((a, d) => a + d.pres, 0)} événements`);
}

// ---------- vague 3 : état de niveau, interactions, bousculades, objets (tests/fixtures/parkour/vague3.json) ----------
{
  const file = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'tests', 'fixtures', 'parkour', 'vague3.json');
  const raw = { ...JSON.parse(fs.readFileSync(file, 'utf8')), name: 'vague3' };
  const level = LevelSchema.parse(raw);
  const stOut = (st) => ({
    crumbled: [...st.crumbled].map(([k, v]) => [k, v]), links: [...st.links].map(([k, v]) => [k, v.at, v.until]),
    levers: [...st.levers], tiles: [...st.tiles], safe: [...st.safe].sort((a, b) => a - b), boxes: [...st.boxes],
    coins: [...st.coins].sort((a, b) => a - b), bananas: [...st.bananas].map(([k, p]) => [k, ...p]),
  });
  const me = 'moi';
  // séquence de messages du serveur appliquée à l'état, avec les boîtes et les fonctions pures après chaque message
  const msgs = [
    { t: 'open', link: 'porte1', at: 2, until: 10, by: 3 },
    { t: 'tile', i: 8, k: 4, at: 3.5 },
    { t: 'safe', i: 8, k: 1 },
    { t: 'tile', i: 8, k: 9, at: 5 },
    { t: 'lever', i: 12, at: 6 },
    { t: 'open', link: 'trappe', at: 6, until: 9, by: 12 },
    { t: 'box', i: 6, until: 8, id: 'b1' },
    { t: 'coin', id: me, i: 1, n: 1 },
    { t: 'coin', id: 'autre', i: 15, n: 1 },
    { t: 'banana', k: 3, p: [1, 0, 20] },
    { t: 'banana', k: 4, p: [-1, 0.5, 30] },
    { t: 'bananaGone', k: 3, by: 'b2' },
    { t: 'crumble', i: 2, at: 4 },
    { t: 'crumble', i: 2, at: 4.5 },
    { t: 'open', link: 'porte1', at: 9.5, until: 17.5, by: 3 },
    { t: 'item', id: me, kind: 'banana' },
    { t: 'cp', id: me, k: 0 },
  ];
  const st = newLevelState();
  const times = [0, 1.99, 2, 2.1, 2.35, 3.49, 3.5, 5.5, 6.1, 8.5, 9.05, 9.2, 9.7, 12, 17.6, 17.95, 30];
  const seq = msgs.map((m) => {
    const used = applyLevelMsg(st, m, me);
    return {
      m, used, st: stOut(st),
      snaps: times.map((t) => ({ t, cols: buildColliders(level, t, st).map(colOut) })),
      pure: times.map((t) => ({
        open: ['porte1', 'trappe', 'rien'].map((l) => linkOpen(st, l, t)),
        door: [4, 10].map((i) => doorOpenness(level.elements[i], st, t)),
        lever: leverDown(level.elements[12], 12, st, t), box: [6, 17].map((i) => boxReady(i, st, t)),
      })),
    };
  });
  // effets d'objets sur le corps local
  const effects = [
    { m: { t: 'effect', id: me, kind: 'super', until: 12 }, now: 4 }, { m: { t: 'effect', id: me, kind: 'shield', until: 9 }, now: 4.5 },
    { m: { t: 'effect', id: 'autre', kind: 'shield', until: 9 }, now: 4.5 }, { m: { t: 'effect', id: me, kind: 'shield', until: 3 }, now: 4.5 },
    { m: { t: 'open', link: 'x', at: 1, until: 2 }, now: 1 },
  ].map(({ m, now }) => { const b = makeBody([0, 0, 0]); const ok = applyEffectMsg(b, m, me, now); return { m, now, ok, superJump: b.superJump, shield: b.shield }; });
  // grille mémoire : dalles, dalle sous des points, dessus, contacts
  const mem = level.elements[8];
  const tiles = memoryTiles(mem).map((p) => ({ c: p.c, h: p.h, yaw: p.yaw }));
  const probes = [];
  for (let k = 0; k < 80; k++) probes.push([((k * 1.37) % 8) - 4, -0.5 + ((k * 0.61) % 3) - 1, 33 + ((k * 2.3) % 16)]);
  const hits = probes.map((p) => ({ p, tile: memoryTileAt(mem, p), on: level.elements.map((e) => standsOn(e, p)), touch: level.elements.map((e) => touches(e, p)) }));
  const keys = [[0, 0], [8, 11], [12, 1023]].map(([i, k]) => memoryKey(i, k));
  // disposition de grille (graine enregistrée)
  const layouts = [[3, 4, 0.6], [8, 12, 0.5], [2, 2, 0.9], [5, 7, 0.1]].map(([c, r, tr]) => {
    const seq = []; let sd = 777 + c * 31 + r;
    const rnd = () => { sd = (sd * 48271) % 2147483647; const v = sd / 2147483647; seq.push(v); return v; };
    const trap = memoryLayout(c, r, tr, rnd);
    return { cols: c, rows: r, traps: tr, rnd: seq, trap };
  });
  // bousculades : cas variés (position et vitesse de l'autre, état du corps), réglage activé / désactivé
  const jostles = [];
  for (let k = 0; k < 160; k++) {
    const b = makeBody([((k * 0.37) % 1) - 0.5, (k % 7 === 0) ? 1.4 : 0, ((k * 0.53) % 1) - 0.5]);
    b.v = [((k * 3.1) % 10) - 5, (k % 3) - 1, ((k * 1.7) % 10) - 5];
    if (k % 11 === 3) b.tumble = 0.5;
    if (k % 13 === 5) b.shield = 2;
    if (k % 17 === 7) b.zip = 2;
    const a = (k * 2.399) % (2 * Math.PI), d = 0.05 + ((k * 0.173) % 0.9);
    const op = [Math.sin(a) * d, (k % 5) * 0.1, Math.cos(a) * d];
    const sp = (k * 1.9) % 16;
    const ov = [-Math.sin(a) * sp + ((k % 4) - 1.5), 0, -Math.cos(a) * sp];
    const init = { jostle: k % 9 === 4 ? false : k % 9 === 5 ? undefined : true };
    const before = bodyOut(b);
    const b2 = makeBody([0, 0, 0]); Object.assign(b2, JSON.parse(JSON.stringify(b)));
    const r1 = jostle(b, op, ov);
    const r2 = parkourJostle(init, b2, op, ov);
    jostles.push({ before, tumble0: before.tumble, shield0: before.shield, zip0: before.zip, op, ov, jostle: init.jostle ?? null, r1, after: bodyOut(b), r2, after2: bodyOut(b2) });
  }
  // super saut, bouclier et pose : terrain plat, barre tournante, entrées enregistrées
  const cols = [
    { id: 0, tag: 'platform', c: [0, -0.5, 0], h: [20, 0.5, 20], yaw: 0 },
    { id: 1, tag: 'spinner', c: [0, 0.45, 4], h: [4, 0.3, 0.3], yaw: 0, angVel: 2.5 },
    { id: 2, tag: 'hammer', c: [-5, 0.9, -3], h: [1, 0.8, 1], yaw: 0, vel: [0, 0, 6] },
    { id: 3, tag: 'boost', c: [5, 0.05, -5], h: [1.5, 0.05, 1.5], yaw: 0, boost: [0, 14] },
  ];
  const fx = [];
  for (const [sj, sh, seedk] of [[0, 0, 1], [8, 0, 2], [0, 6, 3], [3, 2.5, 4]]) {
    seed = 999 + seedk;
    const steps = 900, inp = inputs(steps), states = [];
    const b = makeBody([0, 0.01, 0]); b.superJump = sj; b.shield = sh;
    let kn = 0, maxY = 0;
    for (let i = 0; i < steps; i++) {
      const t = i * H;
      cols[1].yaw = t * 2.5;
      const contacts = stepBody(b, { mx: inp[i][0], mz: inp[i][1], jump: inp[i][2] }, cols, H);
      const ev = parkourPostStep(b, contacts);
      if (ev.knocked) kn++;
      maxY = Math.max(maxY, b.p[1]);
      if (Math.abs(b.p[0]) > 19 || Math.abs(b.p[2]) > 19 || b.p[1] < -5) { b.p = [0, 0.01, 0]; b.v = [0, 0, 0]; clearMotionState(b); }
      if (i % 10 === 9) states.push({ ...bodyOut(b), flags: poseFlags(b) });
    }
    fx.push({ superJump: sj, shield: sh, inputs: inp, states, knocks: kn, maxY });
  }
  // course pilotée avec un état de niveau qui évolue (portes, dalles, trappe) et un « autre joueur » enregistré qui fonce dans le nôtre
  const timeline = [
    [4.0, { t: 'open', link: 'porte1', at: 4.0, until: 12, by: 3 }], [9.0, { t: 'tile', i: 8, k: 1, at: 9.0 }],
    [10.0, { t: 'tile', i: 8, k: 6, at: 10.0 }], [12.0, { t: 'lever', i: 12, at: 12.0 }], [12.0, { t: 'open', link: 'trappe', at: 12.0, until: 15, by: 12 }],
    [14.0, { t: 'effect', id: me, kind: 'super', until: 22 }], [16.0, { t: 'effect', id: me, kind: 'shield', until: 20 }],
  ];
  const races = [];
  for (const jo of [true, false]) {
    const rs = newLevelState(), steps = 2400, inp = [], states = [], others = [];
    const start = level.elements[0];
    const b = makeBody([start.pos[0], topOf(start) + 0.2, start.pos[2]]);
    let ti = 0, trips = 0, falls = 0, knocks = 0;
    const killY = levelKillY(level);
    for (let i = 0; i < steps; i++) {
      const t = 3 + i * H;
      while (ti < timeline.length && timeline[ti][0] <= t) { applyLevelMsg(rs, timeline[ti][1], me); applyEffectMsg(b, timeline[ti][1], me, t); ti++; }
      const ip = [Math.max(-1, Math.min(1, -b.p[0] * 0.4)) * 0.5 + Math.sin(i * 0.02) * 0.3, i % 400 < 330 ? 1 : -0.3, i % 50 < 9];
      inp.push(ip);
      parkourPreStep(level, b, H, t);
      const contacts = stepBody(b, { mx: ip[0], mz: ip[1], jump: ip[2] }, buildColliders(level, t, rs), H);
      // l'autre joueur fonce périodiquement sur nous depuis le côté
      const ph = (i % 120) / 120, side = (i % 240) < 120 ? 1 : -1;
      // (passages brefs, toutes les 2 s : des contacts permanents rendraient la trajectoire chaotique, sensible au dernier bit)
      const near = (i % 120) < 24;
      const op = [b.p[0] + side * (near ? 1.0 - ph * 2.5 : 6), b.p[1] + (i % 7 === 0 ? 1.5 : 0), b.p[2] + 0.1];
      const ov = [-side * (4 + (i % 9)), 0, 0.5];
      others.push([...op, ...ov]);
      if (parkourJostle({ jostle: jo }, b, op, ov)) trips++;
      const ev = parkourPostStep(b, contacts);
      if (ev.knocked) knocks++;
      if (ev.killed || b.p[1] < killY) { falls++; b.p = [start.pos[0], topOf(start) + 0.2, start.pos[2]]; b.v = [0, 0, 0]; b.tumble = 0; clearMotionState(b); }
      if (i % 10 === 9) states.push({ ...bodyOut(b), flags: poseFlags(b) });
    }
    races.push({ jostle: jo, inputs: inp, others, states, trips, falls, knocks });
  }
  fs.writeFileSync(path.join(OUT, 'vague3.json'), JSON.stringify({ level, raw, killY: levelKillY(level), seq, times, effects, tiles, hits, keys, layouts, jostles, cols: cols.map(colOut), fx, timeline, races }));
  console.log(`vague3 : ${jostles.filter((j) => j.r1).length}/${jostles.length} trébuchements, frappes sans/avec bouclier ${fx.map((x) => x.knocks).join('/')}, hauteurs max ${fx.map((x) => x.maxY.toFixed(2)).join('/')}, courses : ${races.map((r) => r.trips + ' trébuchements, ' + r.falls + ' chutes').join(' | ')}`);
}

// ---------- serveur : schéma des niveaux, validation (chemin des bots), réglages et scores ----------
{
  const fx = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'tests', 'fixtures', 'parkour');
  const raws = [
    ...listLevels().map((n) => ({ ...JSON.parse(fs.readFileSync(path.join(LEVELS_DIR, n + '.json'), 'utf8')), name: n })),
    ...fs.readdirSync(fx).filter((f) => f.endsWith('.json')).map((f) => ({ ...JSON.parse(fs.readFileSync(path.join(fx, f), 'utf8')), name: f.slice(0, -5) })),
  ];
  const levels = raws.map((raw) => {
    const level = LevelSchema.parse(raw);
    const v = validateLevel(level);
    return { raw, level, ok: v.ok, path: v.path, pathLength: v.stats.pathLength };
  });
  const rawSettings = [
    {},
    null,
    { rounds: 3, order: 'list', list: ['mortar', 'nope', 'parkour'], games: ['mortar'], game: { parkour: { mode: 'best', duration: 9999, jostle: 0, levels: ['a', 3, 'b'] }, mortar: { hp: '50', crates: '' } } },
    { rounds: '7', order: 'random', games: ['parkour', 'parkour', 'x'], game: { mortar: { buildTime: -4, shrink: 'abc' } } },
    { rounds: 40, order: 'weird', list: ['parkour'], game: { parkour: { mode: 'nope' } } },
  ];
  const settings = rawSettings.map((raw) => ({ raw, out: sanitizeSettings(raw, gameMetas) }));
  let k = 0;
  const seq = Array.from({ length: 200 }, () => rnd());
  const rounds = [settings[2].out, settings[3].out, { ...settings[3].out, games: ['parkour', 'mortar'], rounds: 12 }, settings[4].out].map((st) => {
    const start = k;
    const list = buildRoundList(st, () => seq[k++ % seq.length]);
    return { settings: st, start, list };
  });
  const results = [
    ranksFromGroups([[{ id: 'a', label: '1' }], [{ id: 'b', label: '2' }, { id: 'c', label: '2' }], [{ id: 'd', label: '4' }]]),
    ranksFromGroups([[{ id: 'x', label: 'x' }, { id: 'y', label: 'y' }]]),
  ].map((r) => ({ results: r, rows: scoreRound(r) }));
  const metas = gameMetas;
  fs.writeFileSync(path.join(OUT, 'server.json'), JSON.stringify({ levels, settings, seq, rounds, results, metas }));
  console.log(`serveur : ${levels.length} niveaux validés (${levels.filter((l) => l.ok).length} terminables)`);
}

console.log('Vecteurs de référence écrits dans', OUT);

// ---------- vague 4 : castors, jets de lave, chutes de pierres, apparences (tests/fixtures/parkour/vague4.json) ----------
waveLevel('vague4');
