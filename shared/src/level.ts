// Format des niveaux de parcours (schéma partagé jeu ↔ MCP) et cinématique déterministe des obstacles.
import { z } from 'zod';
import { PHYS, jumpHeight, jumpReach, type Collider, type Vec3 } from './physics';

const TAU = Math.PI * 2;
const v3 = z.tuple([z.number(), z.number(), z.number()]);
const v2 = z.tuple([z.number(), z.number()]);
const size = z.tuple([z.number().min(0.2).max(80), z.number().min(0.2).max(80), z.number().min(0.2).max(80)]);
const common = { id: z.string().max(40).optional(), pos: v3, size, yaw: z.number().min(-7).max(7).default(0) };
/** Décor et liquides : peuvent couvrir tout le niveau (murs de la maison, parquet). */
const bigSize = z.tuple([z.number().min(0.2).max(200), z.number().min(0.2).max(200), z.number().min(0.2).max(200)]);
const phase = z.number().min(0).max(1).default(0);
const color = z.string().regex(/^#[0-9a-fA-F]{6}$/).optional();
const link = z.string().min(1).max(20);
/** Apparences (rendu seulement, la collision reste la boîte) : voir elementCatalog. */
export const SKINS = ['table', 'notebook', 'pencilcase', 'pencil', 'record', 'tv', 'pot', 'flowerpot', 'leaf', 'sunflower', 'mallet', 'wire', 'cloud', 'plane', 'kite', 'bird', 'wing', 'heli', 'rock', 'scree'] as const;
const skin = z.enum(SKINS).optional();

export const ElementSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('start'), ...common, skin }),
  z.object({ type: z.literal('finish'), ...common, skin }),
  z.object({ type: z.literal('checkpoint'), ...common, skin }),
  z.object({ type: z.literal('platform'), ...common, color, skin }),
  z.object({ type: z.literal('ice'), ...common }),
  z.object({ type: z.literal('moving'), ...common, delta: v3, period: z.number().min(1).max(30).default(4), phase, skin }),
  z.object({ type: z.literal('trampoline'), ...common, bounce: z.number().min(10).max(24).default(15) }),
  z.object({ type: z.literal('conveyor'), ...common, dir: v2, speed: z.number().min(0.5).max(10).default(4) }),
  z.object({ type: z.literal('crumble'), ...common, delay: z.number().min(0.2).max(3).default(0.5), respawn: z.number().min(1).max(20).default(4), skin }),
  z.object({ type: z.literal('spinner'), ...common, speed: z.number().min(-6).max(6).default(1.5), phase }),
  z.object({ type: z.literal('hammer'), ...common, length: z.number().min(1).max(12).default(5), axis: z.enum(['x', 'z']).default('x'), amplitude: z.number().min(0.2).max(1.5).default(1.1), period: z.number().min(1).max(12).default(3), phase, strike: z.number().int().min(-1).max(1).default(0), skin }),
  z.object({ type: z.literal('fan'), ...common, force: v3.default([0, 42, 0]) }),
  z.object({ type: z.literal('cannon'), ...common, dir: v2, stroke: z.number().min(0.5).max(10).default(3), period: z.number().min(1).max(12).default(3), phase }),
  // —— vague 1 : obstacles et sols horlogers, décor ——
  z.object({ type: z.literal('roller'), ...common, speed: z.number().min(-8).max(8).default(3) }),
  z.object({ type: z.literal('puncher'), ...common, count: z.number().int().min(1).max(12).default(4), stroke: z.number().min(0.5).max(8).default(2.5), period: z.number().min(1).max(12).default(3), stagger: z.number().min(0).max(1).default(0.15), phase }),
  z.object({ type: z.literal('gate'), ...common, drop: z.number().min(0.5).max(20).default(3), period: z.number().min(1.5).max(20).default(4), phase, skin }),
  z.object({ type: z.literal('turntable'), ...common, speed: z.number().min(-3).max(3).default(0.8), phase, skin }),
  z.object({ type: z.literal('sweeper'), ...common, speed: z.number().min(-3).max(3).default(1.3), highOffset: z.number().min(1.6).max(4).default(2.1), phase }),
  z.object({ type: z.literal('ferris'), ...common, count: z.number().int().min(1).max(12).default(4), radius: z.number().min(1.5).max(20).default(5), period: z.number().min(4).max(60).default(14), phase }),
  z.object({ type: z.literal('pistons'), ...common, count: z.number().int().min(1).max(16).default(4), height: z.number().min(0.3).max(8).default(2), period: z.number().min(1).max(20).default(3), stagger: z.number().min(0).max(1).default(0.25), phase }),
  z.object({ type: z.literal('wreckingball'), ...common, length: z.number().min(1).max(20).default(6), angle: z.number().min(0.1).max(1.3).default(0.7), period: z.number().min(2).max(20).default(4), phase }),
  z.object({ type: z.literal('crusher'), ...common, minGap: z.number().min(1.2).max(20).default(1.4), thickness: z.number().min(0.3).max(4).default(1), period: z.number().min(1.5).max(20).default(4), phase }),
  z.object({ type: z.literal('blink'), ...common, period: z.number().min(1.5).max(20).default(4), on: z.number().min(0.2).max(0.9).default(0.6), phase, skin }),
  z.object({ type: z.literal('hazard'), ...common, size: bigSize, style: z.enum(['lava', 'water', 'acid', 'floor']).default('lava') }),
  z.object({ type: z.literal('boulder'), ...common, delta: v3, interval: z.number().min(1).max(20).default(4), travel: z.number().min(1).max(20).default(5), phase }),
  z.object({ type: z.literal('fakewall'), ...common, color }),
  z.object({ type: z.literal('deco'), ...common, size: bigSize, kind: z.enum(['tree', 'rock', 'balloon', 'arrow', 'flag', 'cactus', 'mushroom', 'crystal', 'crowd', 'flowers', 'stem', 'cloud', 'rack', 'room']).default('tree'), color }),
  z.object({ type: z.literal('sign'), ...common, text: z.string().max(60).default('') }),
  z.object({ type: z.literal('fog'), ...common, density: z.number().min(0).max(1).default(0.6), color }),
  // —— vague 2 : sols spéciaux et propulseurs ——
  z.object({ type: z.literal('mud'), ...common, slow: z.number().min(0.15).max(0.9).default(0.45), jumpFactor: z.number().min(0.3).max(1).default(0.6) }),
  z.object({ type: z.literal('jelly'), ...common, bounciness: z.number().min(0.2).max(0.9).default(0.6), jumpFactor: z.number().min(1).max(1.6).default(1.2) }),
  z.object({ type: z.literal('ramp'), ...common, rise: z.number().min(-20).max(20).default(2), slide: z.boolean().default(false), color }),
  z.object({ type: z.literal('boost'), ...common, dir: v2.default([0, 1]), speed: z.number().min(8).max(30).default(18) }),
  z.object({ type: z.literal('launcher'), ...common, to: v3, apex: z.number().min(0.5).max(20).default(3) }),
  z.object({ type: z.literal('jumppad'), ...common, launch: z.tuple([z.number().min(-25).max(25), z.number().min(4).max(26), z.number().min(-25).max(25)]).default([0, 14, 8]) }),
  z.object({ type: z.literal('zipline'), ...common, to: v3, speed: z.number().min(3).max(25).default(10) }),
  z.object({ type: z.literal('teleport'), ...common, to: v3, exitVel: z.tuple([z.number().min(-30).max(30), z.number().min(-30).max(30), z.number().min(-30).max(30)]).default([0, 0, 0]) }),
  z.object({ type: z.literal('bubble'), ...common, count: z.number().int().min(1).max(12).default(3), rise: z.number().min(1).max(40).default(6), period: z.number().min(1.5).max(40).default(6), phase }),
  z.object({ type: z.literal('lowgrav'), ...common, gravity: z.number().min(0.05).max(1).default(0.35) }),
  // —— vague 3 : interactions (état de niveau tenu par le serveur) ——
  z.object({ type: z.literal('button'), ...common, link, duration: z.number().min(1).max(60).default(6) }),
  z.object({ type: z.literal('door'), ...common, link, color }),
  z.object({ type: z.literal('lever'), ...common, link, duration: z.number().min(1).max(60).default(4), cooldown: z.number().min(1).max(60).default(8) }),
  z.object({ type: z.literal('trapdoor'), ...common, link, color }),
  z.object({ type: z.literal('memory'), ...common, cols: z.number().int().min(2).max(8).default(3), rows: z.number().int().min(2).max(12).default(5), gap: z.number().min(0).max(1).default(0.25), traps: z.number().min(0.1).max(0.9).default(0.5) }),
  z.object({ type: z.literal('itembox'), ...common, respawn: z.number().min(2).max(60).default(6) }),
  z.object({ type: z.literal('coin'), ...common }),
  z.object({ type: z.literal('wind'), ...common, force: z.tuple([z.number().min(-40).max(40), z.number().min(-40).max(40), z.number().min(-40).max(40)]).default([24, 0, 0]), period: z.number().min(0.5).max(20).default(3), phase }),
  // —— vague 4 : parcours dessinés (castors, jets de lave, chutes de pierres) ——
  z.object({ type: z.literal('popper'), ...common, cols: z.number().int().min(1).max(8).default(3), rows: z.number().int().min(1).max(8).default(3), period: z.number().min(1).max(12).default(2.4), up: z.number().min(0.15).max(0.8).default(0.45), chance: z.number().min(0.1).max(1).default(0.45), phase }),
  z.object({ type: z.literal('geyser'), ...common, period: z.number().min(2).max(20).default(4), on: z.number().min(0.15).max(0.8).default(0.4), phase }),
  z.object({ type: z.literal('rockfall'), ...common, count: z.number().int().min(1).max(6).default(2), stone: z.number().min(0.4).max(2.5).default(1), interval: z.number().min(1.5).max(12).default(3), warn: z.number().min(0.6).max(4).default(1.4), phase }),
]);

export const LevelSchema = z.object({
  name: z.string().regex(/^[a-z0-9][a-z0-9_-]{0,40}$/, 'minuscules, chiffres, tirets uniquement'),
  title: z.string().max(60).default(''),
  author: z.string().max(40).default(''),
  difficulty: z.number().int().min(1).max(5).default(2),
  sky: z.string().regex(/^#[0-9a-fA-F]{6}$/).optional(),
  sea: z.string().regex(/^#[0-9a-fA-F]{6}$/).optional(), // mer sous le parcours (défaut : slime rose)
  killY: z.number().optional(),
  elements: z.array(ElementSchema).min(2).max(400),
});

export type LevelElement = z.infer<typeof ElementSchema>;
export type Level = z.infer<typeof LevelSchema>;
export type LevelInput = z.input<typeof LevelSchema>;
export type ElementType = LevelElement['type'];

/** Types sur lesquels on peut se tenir debout. */
export const STANDABLE: ReadonlySet<ElementType> = new Set(['start', 'finish', 'checkpoint', 'platform', 'ice', 'moving', 'trampoline', 'conveyor', 'crumble', 'roller', 'turntable', 'ferris', 'pistons', 'blink', 'mud', 'jelly', 'ramp', 'boost', 'jumppad', 'bubble', 'button', 'trapdoor', 'memory']);

/** Zones sans collision de la vague 2, testées sur la position des pieds (inZone). */
export const ZONES: ReadonlySet<ElementType> = new Set(['launcher', 'teleport', 'lowgrav', 'wind']);

/** Éléments touchés sans collision, détectés par le serveur sur la position des joueurs (vague 3). */
export const PICKUPS: ReadonlySet<ElementType> = new Set(['lever', 'itembox', 'coin']);

/** Types sans aucune collision ni effet physique (pur rendu). */
export const VISUAL_ONLY: ReadonlySet<ElementType> = new Set(['fakewall', 'deco', 'sign', 'fog']);

/** Types dont le contact « frappe » le joueur (roulé-boulé) : voir parkourPostStep. */
export const HITTERS: ReadonlySet<ElementType> = new Set(['hammer', 'spinner', 'cannon', 'puncher', 'gate', 'sweeper', 'wreckingball', 'boulder', 'popper', 'rockfall']);

export type El<T extends ElementType> = Extract<LevelElement, { type: T }>;

/** Morceau mobile d'un élément à l'instant t (bloc, nacelle, dalle, boule…) : boîte + vitesse de surface. */
export interface Part { c: Vec3; h: Vec3; yaw: number; vel: Vec3; angVel?: number }

/** Partie fractionnaire positive (GDScript : fposmod(x, 1.0)). */
export function frac(x: number): number {
  return x - Math.floor(x);
}

/** Point local (lx, ly, lz) d'un élément tourné de `yaw`, en coordonnées monde (monde = Ry(yaw) · local). */
function toWorld(e: LevelElement, lx: number, ly: number, lz: number): Vec3 {
  const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw);
  return [e.pos[0] + lx * cos + lz * sin, e.pos[1] + ly, e.pos[2] - lx * sin + lz * cos];
}

/** Extension du piston d'un canon pousseur (0..1) et sa dérivée par unité de phase. */
export function cannonPulse(u: number): [number, number] {
  if (u < 0.12) return [u / 0.12, 1 / 0.12];
  if (u < 0.35) return [1, 0];
  if (u < 0.75) return [1 - (u - 0.35) / 0.4, -1 / 0.4];
  return [0, 0];
}

/** Angle de rotation visuel du rouleau autour de son axe x local (le dessus avance vers +z local si speed > 0). */
export function rollerAngle(e: El<'roller'>, t: number): number {
  return (e.speed * t) / (e.size[1] / 2);
}

/** Blocs du mur poinçonneur : bloc k (de -x à +x local) jaillit de `stroke` vers +z local, décalé de k·stagger. */
export function puncherBlocks(e: El<'puncher'>, t: number): Part[] {
  const out: Part[] = [];
  const w = e.size[0] / e.count;
  const hw = Math.max(0.1, w / 2 - 0.05);
  const sin = Math.sin(e.yaw), cos = Math.cos(e.yaw);
  for (let k = 0; k < e.count; k++) {
    const [ext, dext] = cannonPulse(frac(t / e.period + e.phase + k * e.stagger));
    const sp = (dext * e.stroke) / e.period;
    out.push({ c: toWorld(e, -e.size[0] / 2 + (k + 0.5) * w, 0, ext * e.stroke), h: [hw, e.size[1] / 2, e.size[2] / 2], yaw: e.yaw, vel: [sin * sp, 0, cos * sp] });
  }
  return out;
}

/** Profil de la guillotine : part de descente g (0 = en haut, 1 = en bas) et dg/du. Chute 10 %, en bas 20 %, remontée 40 %, en haut 30 %. */
export function gateProfile(u: number): [number, number] {
  if (u < 0.1) return [(u / 0.1) * (u / 0.1), (2 * u) / 0.01];
  if (u < 0.3) return [1, 0];
  if (u < 0.7) {
    const s = (u - 0.3) / 0.4;
    return [1 - s * s * (3 - 2 * s), -(6 * s - 6 * s * s) / 0.4];
  }
  return [0, 0];
}

/** Lame de la guillotine (pos = position haute) et secondes avant la prochaine chute (0 si elle tombe). */
export function gatePart(e: El<'gate'>, t: number): Part & { untilFall: number } {
  const u = frac(t / e.period + e.phase);
  const [g, dg] = gateProfile(u);
  return { c: [e.pos[0], e.pos[1] - e.drop * g, e.pos[2]], h: [e.size[0] / 2, e.size[1] / 2, e.size[2] / 2], yaw: e.yaw, vel: [0, (-e.drop * dg) / e.period, 0], untilFall: u < 0.1 ? 0 : (1 - u) * e.period };
}

/** Angle (lacet) courant d'un élément tournant (turntable, sweeper). */
export function spinAngle(e: El<'turntable'> | El<'sweeper'>, t: number): number {
  return e.yaw + e.speed * t + e.phase * TAU;
}

/** Plateau tournant : octogone régulier = 4 boîtes [2r × 2r·tan(π/8)] tournées de 45°, r = 0.97 × rayon (même aire que le disque). */
export function turntableBoxes(e: El<'turntable'>, t: number): Part[] {
  const r = 0.97 * (e.size[0] / 2), a = spinAngle(e, t), out: Part[] = [];
  for (let k = 0; k < 4; k++) out.push({ c: [e.pos[0], e.pos[1], e.pos[2]], h: [r, e.size[1] / 2, r * Math.tan(Math.PI / 8)], yaw: a + (k * Math.PI) / 4, vel: [0, 0, 0], angVel: e.speed });
  return out;
}

/** Balayeur double : barre basse (centre pos) puis barre haute perpendiculaire (pos.y + highOffset). */
export function sweeperBars(e: El<'sweeper'>, t: number): Part[] {
  const a = spinAngle(e, t), h: Vec3 = [e.size[0] / 2, e.size[1] / 2, e.size[2] / 2];
  return [
    { c: [e.pos[0], e.pos[1], e.pos[2]], h, yaw: a, vel: [0, 0, 0], angVel: e.speed },
    { c: [e.pos[0], e.pos[1] + e.highOffset, e.pos[2]], h, yaw: a + Math.PI / 2, vel: [0, 0, 0], angVel: e.speed },
  ];
}

/** Nacelles de la grande roue (restent horizontales). Nacelle k à l'angle θ = 2π(t/period + phase + k/count) dans le plan (x local, y). */
export function ferrisCabins(e: El<'ferris'>, t: number): Part[] {
  const out: Part[] = [], w = TAU / e.period, R = e.radius;
  const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw);
  for (let k = 0; k < e.count; k++) {
    const th = TAU * (t / e.period + e.phase + k / e.count);
    const lx = R * Math.cos(th), ly = R * Math.sin(th), dlx = -R * Math.sin(th) * w, dly = R * Math.cos(th) * w;
    out.push({ c: [e.pos[0] + lx * cos, e.pos[1] + ly, e.pos[2] - lx * sin], h: [e.size[0] / 2, e.size[1] / 2, e.size[2] / 2], yaw: e.yaw, vel: [dlx * cos, dly, -dlx * sin] });
  }
  return out;
}

/** Dalles des pistons : dalle k (de -x à +x local) monte de 0 à `height` en sinusoïde, déphasée de k·stagger. */
export function pistonSlabs(e: El<'pistons'>, t: number): Part[] {
  const out: Part[] = [], w = e.size[0] / e.count;
  for (let k = 0; k < e.count; k++) {
    const ph = TAU * (t / e.period + e.phase + k * e.stagger);
    const lift = e.height * (0.5 - 0.5 * Math.cos(ph)), vy = (e.height * 0.5 * Math.sin(ph) * TAU) / e.period;
    out.push({ c: toWorld(e, -e.size[0] / 2 + (k + 0.5) * w, lift, 0), h: [w / 2, e.size[1] / 2, e.size[2] / 2], yaw: e.yaw, vel: [0, vy, 0] });
  }
  return out;
}

/** Boule de démolition (pendule conique) : pivot pos, la boule tourne à l'azimut φ = 2π(t/period + phase) (de +x vers +z). */
export function wreckingBall(e: El<'wreckingball'>, t: number): Part {
  const phi = TAU * (t / e.period + e.phase), w = TAU / e.period, rho = e.length * Math.sin(e.angle);
  return { c: [e.pos[0] + rho * Math.cos(phi), e.pos[1] - e.length * Math.cos(e.angle), e.pos[2] + rho * Math.sin(phi)], h: [e.size[0] / 2, e.size[1] / 2, e.size[2] / 2], yaw: e.yaw, vel: [-rho * w * Math.sin(phi), 0, rho * w * Math.cos(phi)] };
}

/** Étau : écart intérieur entre les murs (de size.x, grand ouvert, à minGap) et sa dérivée temporelle. */
export function crusherGap(e: El<'crusher'>, t: number): [number, number] {
  const ph = TAU * (t / e.period + e.phase), maxG = Math.max(e.size[0], e.minGap);
  return [e.minGap + (maxG - e.minGap) * (0.5 + 0.5 * Math.cos(ph)), (-(maxG - e.minGap) * 0.5 * Math.sin(ph) * TAU) / e.period];
}

/** Les deux murs de l'étau (−x local puis +x local), épaisseur `thickness`. */
export function crusherWalls(e: El<'crusher'>, t: number): Part[] {
  const [gap, dgap] = crusherGap(e, t), off = gap / 2 + e.thickness / 2;
  const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw), h: Vec3 = [e.thickness / 2, e.size[1] / 2, e.size[2] / 2];
  return [-1, 1].map((s) => ({ c: toWorld(e, s * off, 0, 0), h, yaw: e.yaw, vel: [(s * dgap * cos) / 2, 0, (-s * dgap * sin) / 2] as Vec3 }));
}

/** Dalle clignotante : solide pendant la fraction `on` du cycle. `left` = secondes avant le changement d'état. */
export function blinkState(e: El<'blink'>, t: number): { solid: boolean; u: number; left: number } {
  const u = frac(t / e.period + e.phase);
  return u < e.on ? { solid: true, u, left: (e.on - u) * e.period } : { solid: false, u, left: (1 - u) * e.period };
}

/** Boules en vol : une part de pos toutes les `interval` s et atteint pos + delta en `travel` s, puis disparaît. `roll` = angle de roulement (rad). */
export function boulderBalls(e: El<'boulder'>, t: number): (Part & { k: number; roll: number })[] {
  const out: (Part & { k: number; roll: number })[] = [];
  const s = t / e.interval + e.phase, f = s - Math.floor(s), r = e.size[0] / 2, hb = 0.8 * r;
  const yaw = Math.atan2(e.delta[0], e.delta[2]), len = Math.hypot(e.delta[0], e.delta[1], e.delta[2]);
  for (let j = 0; (f + j) * e.interval < e.travel; j++) {
    const k = ((f + j) * e.interval) / e.travel;
    out.push({ c: [e.pos[0] + e.delta[0] * k, e.pos[1] + e.delta[1] * k, e.pos[2] + e.delta[2] * k], h: [hb, hb, hb], yaw, vel: [e.delta[0] / e.travel, e.delta[1] / e.travel, e.delta[2] / e.travel], k, roll: (len * k) / r });
  }
  return out;
}

// ———————————————————— vague 4 : castors, jets de lave, chutes de pierres ————————————————————

/**
 * Hachage entier déterministe de (a, b) vers [0, 1) : mêmes tirages « au hasard » sur le serveur et tous les clients.
 * Calcul sur 32 bits non signés, porté à l'identique en GDScript (Level.hash01).
 */
export function hash01(a: number, b: number): number {
  let h = ((a * 73856093) ^ (b * 19349663)) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  h = Math.imul(h, 0x45d9f3b) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  h = Math.imul(h, 0x45d9f3b) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  return h / 4294967296;
}

/** Sortie d'un castor sur la fraction v (0..1) de sa sortie : jaillit vite (15 %), reste (60 %), redescend (25 %). Renvoie [ext, dext/dv]. */
export function popperProfile(v: number): [number, number] {
  if (v < 0 || v >= 1) return [0, 0];
  if (v < 0.15) return [v / 0.15, 1 / 0.15];
  if (v < 0.75) return [1, 0];
  return [(1 - v) / 0.25, -1 / 0.25];
}

/**
 * Castor du trou k (k = row·cols + col) à l'instant t : chaque trou a son cycle de `period` s (décalé au hasard) ;
 * à chaque cycle n, le castor sort avec la probabilité `chance` pendant la fraction `up`. `warn` : il va sortir dans < 0.6 s.
 * `seed` = index de l'élément (deux grilles du même niveau ne sont pas synchronisées).
 */
export function popperState(e: El<'popper'>, k: number, t: number, seed: number): { ext: number; dext: number; warn: boolean } {
  const s = t / e.period + e.phase + hash01(seed, k), n = Math.floor(s), u = s - n, key = seed * 64 + k;
  const active = hash01(key, n) < e.chance;
  const [ext, dv] = active ? popperProfile(u / e.up) : [0, 0];
  const warn = !active && hash01(key, n + 1) < e.chance && (1 - u) * e.period < 0.6;
  return { ext, dext: dv / (e.up * e.period), warn };
}

/**
 * Castors sortis : le bas de la boîte de l'élément est la surface du plateau ; un castor sorti remplit la boîte sur toute
 * sa hauteur, rentré il est sous la surface (aucune boîte émise). `k` = numéro du trou.
 */
export function popperParts(e: El<'popper'>, t: number, seed: number): (Part & { k: number })[] {
  const out: (Part & { k: number })[] = [], pw = e.size[0] / e.cols, pd = e.size[2] / e.rows, hy = e.size[1] / 2;
  const hw = 0.32 * Math.min(pw, pd);
  for (let row = 0; row < e.rows; row++) for (let col = 0; col < e.cols; col++) {
    const k = row * e.cols + col, st = popperState(e, k, t, seed);
    if (st.ext <= 0.02) continue;
    out.push({ c: toWorld(e, -e.size[0] / 2 + (col + 0.5) * pw, -2 * hy * (1 - st.ext), -e.size[2] / 2 + (row + 0.5) * pd), h: [hw, hy, hw], yaw: e.yaw, vel: [0, 2 * hy * st.dext, 0], k });
  }
  return out;
}

/** Jet de lave : en éruption pendant la fraction `on` du début de cycle. `left` = s avant le changement ; `warn` : éruption dans < 1 s. */
export function geyserState(e: El<'geyser'>, t: number): { active: boolean; u: number; left: number; warn: boolean } {
  const u = frac(t / e.period + e.phase);
  if (u < e.on) return { active: true, u, left: (e.on - u) * e.period, warn: false };
  const left = (1 - u) * e.period;
  return { active: false, u, left, warn: left < 1 };
}

/** Temps de pose d'une pierre tombée avant qu'elle s'émiette (s). */
export const ROCK_REST = 0.4;

/**
 * Pierres de la chute de pierres : la boîte de l'élément est la zone (bas = sol où elles s'écrasent, haut = d'où elles tombent).
 * Toutes les `interval` s, `count` pierres (diamètre `stone`, décalées de 0.35 s) tombent en `warn` s à des endroits tirés
 * au hasard, puis restent ROCK_REST s au sol (sans danger). `f` = avancement de la chute (≥ 1 : posée), `x`/`z` = point d'impact.
 */
export function rockfallStones(e: El<'rockfall'>, t: number, seed: number): (Part & { k: number; f: number; x: number; z: number })[] {
  const out: (Part & { k: number; f: number; x: number; z: number })[] = [];
  const s = t / e.interval + e.phase, n = Math.floor(s), tau = (s - n) * e.interval;
  const r = e.stone / 2, hb = 0.8 * r, H = e.size[1], ground = e.pos[1] - H / 2;
  for (let k = 0; k < e.count; k++) {
    const tk = tau - k * 0.35;
    if (tk < 0 || tk >= e.warn + ROCK_REST) continue;
    const key = seed * 16 + k;
    const lx = (hash01(key, 2 * n) - 0.5) * Math.max(0, e.size[0] - e.stone), lz = (hash01(key, 2 * n + 1) - 0.5) * Math.max(0, e.size[2] - e.stone);
    const p = toWorld(e, lx, 0, lz), f = tk / e.warn;
    const y = f < 1 ? ground + r + H * (1 - f * f) : ground + r, vy = f < 1 ? (-2 * H * f) / e.warn : 0;
    out.push({ c: [p[0], y, p[2]], h: [hb, hb, hb], yaw: 0, vel: [0, vy, 0], k, f, x: p[0], z: p[2] });
  }
  return out;
}

// ———————————————————— vague 2 : fonctions pures (physique, rendu, bots, portage Godot) ————————————————————

/** Les pieds `p` sont-ils dans la zone (boîte `size` centrée sur pos, tournée de yaw) ? */
export function inZone(e: LevelElement, p: Vec3): boolean {
  const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw), dx = p[0] - e.pos[0], dz = p[2] - e.pos[2];
  const lx = dx * cos - dz * sin, lz = dx * sin + dz * cos;
  return Math.abs(lx) <= e.size[0] / 2 && Math.abs(lz) <= e.size[2] / 2 && Math.abs(p[1] - e.pos[1]) <= e.size[1] / 2;
}

/** Pente de la rampe (m de montée par m le long de z local). */
export function rampSlope(e: El<'ramp'>): number {
  return e.rise / e.size[2];
}

/** Hauteur du dessus de la rampe à la verticale du point monde (x, z), z local borné aux bords de la rampe. */
export function rampTopAt(e: El<'ramp'>, x: number, z: number): number {
  const lz = (x - e.pos[0]) * Math.sin(e.yaw) + (z - e.pos[2]) * Math.cos(e.yaw);
  const q = Math.max(-e.size[2] / 2, Math.min(e.size[2] / 2, lz));
  return e.pos[1] + e.size[1] / 2 + rampSlope(e) * q;
}

/**
 * Les 8 sommets monde de la rampe (dalle cisaillée d'épaisseur size.y) : indice = ix + 2·iz + 4·iy,
 * ix/iz = 0 pour −x/−z local, 1 pour +x/+z ; iy = 0 dessous, 1 dessus.
 */
export function rampCorners(e: El<'ramp'>): Vec3[] {
  const out: Vec3[] = [], s = rampSlope(e), hx = e.size[0] / 2, hy = e.size[1] / 2, hz = e.size[2] / 2;
  for (let iy = 0; iy < 2; iy++) for (let iz = 0; iz < 2; iz++) for (let ix = 0; ix < 2; ix++) {
    const lx = ix ? hx : -hx, lz = iz ? hz : -hz;
    out.push(toWorld(e, lx, (iy ? hy : -hy) + s * lz, lz));
  }
  return out;
}

/** Vitesse horizontale imposée par un speed pad (dir monde normalisée × speed). */
export function boostVel(e: El<'boost'>): [number, number] {
  const n = Math.hypot(e.dir[0], e.dir[1]) || 1;
  return [(e.dir[0] / n) * e.speed, (e.dir[1] / n) * e.speed];
}

/** Vitesse monde d'un trampoline directionnel (launch est en repère local tourné par yaw). */
export function jumppadVel(e: El<'jumppad'>): Vec3 {
  const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw), l = e.launch;
  return [l[0] * cos + l[2] * sin, l[1], -l[0] * sin + l[2] * cos];
}

/**
 * Tir en cloche de `from` vers `to` (pieds), apogée `apex` m au-dessus du plus haut des deux points.
 * Durée T = √(2(H−from.y)/g) + √(2(H−to.y)/g) ; vitesse horizontale (to−from)/T ; vitesse verticale corrigée
 * pour l'intégration du jeu (v.y −= g·dt puis p += v·dt) : vy = (Δy + g·T²/2 + g·dt·T/2) / T → arrivée exacte
 * en `to` après T secondes quand T est un multiple de dt (dt = 0 : parabole continue, pour le rendu).
 */
export function launchVelocity(from: Vec3, to: Vec3, apex: number, dt: number): { v: Vec3; T: number } {
  const g = PHYS.gravity, H = Math.max(from[1], to[1]) + apex;
  const T = Math.sqrt((2 * (H - from[1])) / g) + Math.sqrt((2 * (H - to[1])) / g);
  const vy = (to[1] - from[1] + 0.5 * g * T * T + 0.5 * g * dt * T) / T;
  return { v: [(to[0] - from[0]) / T, vy, (to[2] - from[2]) / T], T };
}

/** Position à l'instant s d'un tir lancé de `from` à la vitesse v (mêmes conventions que launchVelocity). */
export function ballisticPoint(from: Vec3, v: Vec3, s: number, dt = 0): Vec3 {
  const g = PHYS.gravity;
  return [from[0] + v[0] * s, from[1] + v[1] * s - 0.5 * g * s * s - 0.5 * g * dt * s, from[2] + v[2] * s];
}

/** Trajectoire du canon pour le rendu : `n` + 1 points de la parabole partant du bas-centre de la zone vers `to`. */
export function launcherArc(e: El<'launcher'>, n = 24): Vec3[] {
  const from: Vec3 = [e.pos[0], e.pos[1] - e.size[1] / 2, e.pos[2]];
  const { v, T } = launchVelocity(from, e.to, e.apex, 0);
  const out: Vec3[] = [];
  for (let k = 0; k <= n; k++) out.push(ballisticPoint(from, v, (T * k) / n));
  return out;
}

/** Câble de la tyrolienne : de a = pos (départ) à b = to, longueur et direction unitaire. */
export function zipCable(e: El<'zipline'>): { a: Vec3; b: Vec3; len: number; dir: Vec3 } {
  const d: Vec3 = [e.to[0] - e.pos[0], e.to[1] - e.pos[1], e.to[2] - e.pos[2]];
  const len = Math.max(1e-6, Math.hypot(d[0], d[1], d[2]));
  return { a: [e.pos[0], e.pos[1], e.pos[2]], b: [e.to[0], e.to[1], e.to[2]], len, dir: [d[0] / len, d[1] / len, d[2] / len] };
}

/** Pieds d'un joueur suspendu à `s` m du départ du câble (s borné à [0, len]). */
export function zipFeet(e: El<'zipline'>, s: number): Vec3 {
  const { a, len, dir } = zipCable(e), q = Math.max(0, Math.min(len, s));
  return [a[0] + dir[0] * q, a[1] + dir[1] * q - PHYS.zipHang, a[2] + dir[2] * q];
}

/** Bulles : bulle k monte de pos à pos + [0, rise, 0] en `period` s, u = frac(t/period + phase + k/count) ; `left` = s avant d'éclater. */
export function bubbleParts(e: El<'bubble'>, t: number): (Part & { u: number; left: number })[] {
  const out: (Part & { u: number; left: number })[] = [];
  const h: Vec3 = [e.size[0] / 2, e.size[1] / 2, e.size[2] / 2], vy = e.rise / e.period;
  for (let k = 0; k < e.count; k++) {
    const u = frac(t / e.period + e.phase + k / e.count);
    out.push({ c: [e.pos[0], e.pos[1] + e.rise * u, e.pos[2]], h, yaw: e.yaw, vel: [0, vy, 0], u, left: (1 - u) * e.period });
  }
  return out;
}

/** Intensité d'une rafale (0..1) : 0.5 + 0.5·sin(2π(t/period + phase)). */
export function windGust(e: El<'wind'>, t: number): number {
  return 0.5 + 0.5 * Math.sin(TAU * (t / e.period + e.phase));
}

/** Accélération des rafales `wind` aux pieds p à l'instant t (somme, dans l'ordre des éléments, de force × windGust). */
export function windAccel(level: Level, p: Vec3, t: number): Vec3 {
  const a: Vec3 = [0, 0, 0];
  for (const e of level.elements) {
    if (e.type !== 'wind' || !inZone(e, p)) continue;
    const k = windGust(e, t);
    a[0] += e.force[0] * k; a[1] += e.force[1] * k; a[2] += e.force[2] * k;
  }
  return a;
}

/** Facteur de gravité aux pieds p : minimum des zones `lowgrav` qui les contiennent, 1 sinon. */
export function lowgravAt(level: Level, p: Vec3): number {
  let g = 1;
  for (const e of level.elements) if (e.type === 'lowgrav' && inZone(e, p)) g = Math.min(g, e.gravity);
  return g;
}

// ———————————————————— vague 3 : état de niveau tenu par le serveur (fonctions pures, portage Godot) ————————————————————

/** Ouverture d'un lien (portes / trappes de même `link`) : ouvert de `at` à `until` (horloge serveur). */
export interface LinkState { at: number; until: number }

/**
 * État dynamique du niveau, reconstruit par chaque client à partir des messages du serveur (applyLevelMsg dans
 * games/parkour/shared.ts). Seuls crumbled, links et tiles influencent les collisions.
 */
export interface LevelState {
  crumbled: Map<number, number>; // dalle friable → instant du déclenchement
  links: Map<string, LinkState>; // lien → ouverture en cours / dernière
  levers: Map<number, number>; // levier → instant du dernier actionnement
  tiles: Map<number, number>; // memoryKey(i, k) → instant où la dalle piégée tombe
  safe: Set<number>; // memoryKey des dalles mémoire reconnues sûres (rendu)
  boxes: Map<number, number>; // boîte surprise → instant de réapparition
  coins: Set<number>; // pièces déjà ramassées par le joueur local
  bananas: Map<number, Vec3>; // bananes posées (clé → pieds)
}

export function newLevelState(): LevelState {
  return { crumbled: new Map(), links: new Map(), levers: new Map(), tiles: new Map(), safe: new Set(), boxes: new Map(), coins: new Set(), bananas: new Map() };
}

/** Le lien est-il ouvert à l'instant t (at ≤ t < until) ? */
export function linkOpen(state: Partial<LevelState> | undefined, link: string, t: number): boolean {
  const s = state?.links?.get(link);
  return !!s && t >= s.at && t < s.until;
}

/** Ouverture visuelle d'une porte / trappe (0 fermée → 1 ouverte), transitions de DOOR_ANIM s. La collision, elle, disparaît d'un coup à `at`. */
export const DOOR_ANIM = 0.3;
export function doorOpenness(e: El<'door'> | El<'trapdoor'>, state: Partial<LevelState> | undefined, t: number): number {
  const s = state?.links?.get(e.link);
  if (!s || t < s.at) return 0;
  if (t < s.until) return Math.min(1, (t - s.at) / DOOR_ANIM);
  return Math.max(0, 1 - (t - s.until) / DOOR_ANIM);
}

/** Levier abaissé (en recharge) à l'instant t ? */
export function leverDown(e: El<'lever'>, i: number, state: Partial<LevelState> | undefined, t: number): boolean {
  const at = state?.levers?.get(i);
  return at !== undefined && t >= at && t < at + e.cooldown;
}

/** Boîte surprise présente à l'instant t ? */
export function boxReady(i: number, state: Partial<LevelState> | undefined, t: number): boolean {
  const until = state?.boxes?.get(i);
  return until === undefined || t >= until;
}

/** Clé d'une dalle mémoire (élément i, dalle k). */
export function memoryKey(i: number, k: number): number {
  return i * 1024 + k;
}

/** Dalles de la grille mémoire : k = row·cols + col, col le long de x local (de −x à +x), row le long de z local (de −z à +z). */
export function memoryTiles(e: El<'memory'>): Part[] {
  const out: Part[] = [], pw = e.size[0] / e.cols, pd = e.size[2] / e.rows;
  const h: Vec3 = [Math.max(0.05, pw / 2 - e.gap / 2), e.size[1] / 2, Math.max(0.05, pd / 2 - e.gap / 2)];
  for (let row = 0; row < e.rows; row++) for (let col = 0; col < e.cols; col++) {
    out.push({ c: toWorld(e, -e.size[0] / 2 + (col + 0.5) * pw, 0, -e.size[2] / 2 + (row + 0.5) * pd), h, yaw: e.yaw, vel: [0, 0, 0] });
  }
  return out;
}

/** Dalle mémoire sous les pieds p (à la verticale de sa surface, hors joints ; hauteur non testée), -1 sinon. */
export function memoryTileAt(e: El<'memory'>, p: Vec3): number {
  const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw), dx = p[0] - e.pos[0], dz = p[2] - e.pos[2];
  const lx = dx * cos - dz * sin + e.size[0] / 2, lz = dx * sin + dz * cos + e.size[2] / 2;
  const pw = e.size[0] / e.cols, pd = e.size[2] / e.rows;
  const col = Math.floor(lx / pw), row = Math.floor(lz / pd);
  if (col < 0 || col >= e.cols || row < 0 || row >= e.rows) return -1;
  const hx = Math.max(0.05, pw / 2 - e.gap / 2), hz = Math.max(0.05, pd / 2 - e.gap / 2);
  if (Math.abs(lx - (col + 0.5) * pw) > hx || Math.abs(lz - (row + 0.5) * pd) > hz) return -1;
  return row * e.cols + col;
}

/**
 * Dalles mémoire qui portent le joueur aux pieds p : la dalle sous les pieds s'il y en a une ; sinon (pieds dans un joint,
 * la capsule repose sur les bords voisins) toutes les dalles à moins de r (horizontalement) des pieds. Serveur seulement.
 */
export function memoryTilesUnder(e: El<'memory'>, p: Vec3, r = PHYS.radius * 0.9): number[] {
  const k = memoryTileAt(e, p);
  if (k >= 0) return [k];
  const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw), dx = p[0] - e.pos[0], dz = p[2] - e.pos[2];
  const lx = dx * cos - dz * sin + e.size[0] / 2, lz = dx * sin + dz * cos + e.size[2] / 2;
  const pw = e.size[0] / e.cols, pd = e.size[2] / e.rows;
  const hx = Math.max(0.05, pw / 2 - e.gap / 2), hz = Math.max(0.05, pd / 2 - e.gap / 2);
  const out: number[] = [];
  for (let row = 0; row < e.rows; row++) for (let col = 0; col < e.cols; col++) {
    const ex = Math.max(0, Math.abs(lx - (col + 0.5) * pw) - hx), ez = Math.max(0, Math.abs(lz - (row + 0.5) * pd) - hz);
    if (ex * ex + ez * ez <= r * r) out.push(row * e.cols + col);
  }
  return out;
}

/** Les pieds p sont-ils posés sur le dessus de l'élément (empreinte tournée, hauteur à ±0.35 m du dessus) ? Boutons, dalles mémoire. */
export function standsOn(e: LevelElement, p: Vec3): boolean {
  const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw), dx = p[0] - e.pos[0], dz = p[2] - e.pos[2];
  const lx = dx * cos - dz * sin, lz = dx * sin + dz * cos, top = e.pos[1] + e.size[1] / 2;
  return Math.abs(lx) <= e.size[0] / 2 && Math.abs(lz) <= e.size[2] / 2 && Math.abs(p[1] - top) <= 0.35;
}

/** Le corps (capsule debout aux pieds p) touche-t-il la boîte de l'élément (boîte surprise, pièce, levier) ? */
export function touches(e: LevelElement, p: Vec3): boolean {
  const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw), dx = p[0] - e.pos[0], dz = p[2] - e.pos[2];
  const lx = dx * cos - dz * sin, lz = dx * sin + dz * cos, r = PHYS.radius;
  return Math.abs(lx) <= e.size[0] / 2 + r && Math.abs(lz) <= e.size[2] / 2 + r && p[1] <= e.pos[1] + e.size[1] / 2 && p[1] + PHYS.height >= e.pos[1] - e.size[1] / 2;
}

/**
 * Boîtes de collision du niveau à l'instant `t` (horloge serveur). Fonction pure : tous les clients
 * obtiennent les mêmes obstacles sans rien synchroniser. `state` = état de niveau (LevelState), ou ancienne forme :
 * Map des dalles friables (index → instant du déclenchement).
 */
export function buildColliders(level: Level, t: number, state?: Map<number, number> | Partial<LevelState>): Collider[] {
  const st: Partial<LevelState> = state instanceof Map ? { crumbled: state } : state ?? {};
  const crumbled = st.crumbled;
  const out: Collider[] = [];
  // un élément peut produire plusieurs boîtes (même id), émises dans l'ordre de ses sous-parties
  const parts = (i: number, tag: string, ps: Part[]) => {
    for (const p of ps) {
      const col: Collider = { id: i, tag, c: p.c, h: p.h, yaw: p.yaw, vel: p.vel };
      if (p.angVel !== undefined) col.angVel = p.angVel;
      out.push(col);
    }
  };
  level.elements.forEach((e, i) => {
    const h: Vec3 = [e.size[0] / 2, e.size[1] / 2, e.size[2] / 2];
    const c: Vec3 = [e.pos[0], e.pos[1], e.pos[2]];
    const col: Collider = { id: i, tag: e.type, c, h, yaw: e.yaw };
    switch (e.type) {
      case 'fan':
      case 'fakewall':
      case 'deco':
      case 'sign':
      case 'fog':
      case 'launcher':
      case 'teleport':
      case 'zipline':
      case 'lowgrav':
      case 'wind':
      case 'lever':
      case 'itembox':
      case 'coin':
        return; // zones et décor : pas de collision
      case 'door':
      case 'trapdoor':
        if (linkOpen(st, e.link, t)) return; // ouverte : escamotée
        break;
      case 'memory': {
        // dalles de la grille, sauf les piégées déjà tombées
        const ts = memoryTiles(e);
        return parts(i, e.type, ts.filter((_, k) => { const at = st.tiles?.get(memoryKey(i, k)); return at === undefined || t < at; }));
      }
      case 'bubble': return parts(i, e.type, bubbleParts(e, t));
      case 'mud':
        col.slow = e.slow;
        col.jump = e.jumpFactor;
        break;
      case 'jelly':
        col.jelly = e.bounciness;
        col.jump = e.jumpFactor;
        break;
      case 'ramp':
        col.slope = rampSlope(e);
        if (e.slide) col.slide = true;
        break;
      case 'boost':
        col.boost = boostVel(e);
        break;
      case 'jumppad':
        col.launch = jumppadVel(e);
        break;
      case 'puncher': return parts(i, e.type, puncherBlocks(e, t));
      case 'turntable': return parts(i, e.type, turntableBoxes(e, t));
      case 'sweeper': return parts(i, e.type, sweeperBars(e, t));
      case 'ferris': return parts(i, e.type, ferrisCabins(e, t));
      case 'pistons': return parts(i, e.type, pistonSlabs(e, t));
      case 'crusher': return parts(i, e.type, crusherWalls(e, t));
      case 'boulder': return parts(i, e.type, boulderBalls(e, t));
      case 'wreckingball': return parts(i, e.type, [wreckingBall(e, t)]);
      case 'gate': return parts(i, e.type, [gatePart(e, t)]);
      case 'popper': return parts(i, e.type, popperParts(e, t, i));
      case 'rockfall': return parts(i, e.type, rockfallStones(e, t, i));
      case 'geyser':
        if (!geyserState(e, t).active) return;
        break;
      case 'blink':
        if (!blinkState(e, t).solid) return;
        break;
      case 'roller': {
        // tapis perpendiculaire à l'axe du rouleau : direction +z local
        col.conveyor = [Math.sin(e.yaw) * e.speed, Math.cos(e.yaw) * e.speed];
        break;
      }
      case 'moving': {
        const ph = (t / e.period + e.phase) * TAU;
        const k = 0.5 - 0.5 * Math.cos(ph), dk = (0.5 * Math.sin(ph) * TAU) / e.period;
        col.c = [c[0] + e.delta[0] * k, c[1] + e.delta[1] * k, c[2] + e.delta[2] * k];
        col.vel = [e.delta[0] * dk, e.delta[1] * dk, e.delta[2] * dk];
        break;
      }
      case 'spinner':
        col.yaw = e.yaw + e.speed * t + e.phase * TAU;
        col.angVel = e.speed;
        break;
      case 'hammer': {
        const ph = (t / e.period + e.phase) * TAU;
        let a = e.amplitude * Math.sin(ph), da = (e.amplitude * Math.cos(ph) * TAU) / e.period;
        if (e.strike !== 0) {
          // marteau qui tape : de la verticale (en haut) à l'horizontale (posé), au rythme d'une guillotine
          const [g, dg] = gateProfile(frac(t / e.period + e.phase));
          a = e.strike * (Math.PI - (Math.PI / 2) * g);
          da = (-e.strike * (Math.PI / 2) * dg) / e.period;
        }
        const ax = e.axis === 'x' ? 1 : 0, az = 1 - ax, L = e.length;
        col.c = [c[0] + ax * Math.sin(a) * L, c[1] - Math.cos(a) * L, c[2] + az * Math.sin(a) * L];
        col.vel = [ax * Math.cos(a) * L * da, Math.sin(a) * L * da, az * Math.cos(a) * L * da];
        break;
      }
      case 'cannon': {
        const u = (((t / e.period + e.phase) % 1) + 1) % 1;
        const [ext, dext] = cannonPulse(u);
        const n = Math.hypot(e.dir[0], e.dir[1]) || 1;
        const dx = e.dir[0] / n, dz = e.dir[1] / n, sp = (dext * e.stroke) / e.period;
        col.c = [c[0] + dx * ext * e.stroke, c[1], c[2] + dz * ext * e.stroke];
        col.vel = [dx * sp, 0, dz * sp];
        break;
      }
      case 'crumble': {
        const at = crumbled?.get(i);
        if (at !== undefined && t > at + e.delay && t < at + e.delay + e.respawn) return;
        break;
      }
      case 'trampoline':
        col.bounce = e.bounce;
        break;
      case 'ice':
        col.ice = true;
        break;
      case 'conveyor': {
        const n = Math.hypot(e.dir[0], e.dir[1]) || 1;
        col.conveyor = [(e.dir[0] / n) * e.speed, (e.dir[1] / n) * e.speed];
        break;
      }
    }
    out.push(col);
  });
  return out;
}

/** Accélération des ventilateurs à la position `p` (pieds du personnage). */
export function fanAccel(level: Level, p: Vec3): Vec3 {
  const a: Vec3 = [0, 0, 0];
  for (const e of level.elements) {
    if (e.type !== 'fan') continue;
    if (Math.abs(p[0] - e.pos[0]) <= e.size[0] / 2 && Math.abs(p[2] - e.pos[2]) <= e.size[2] / 2 && Math.abs(p[1] + 0.75 - e.pos[1]) <= e.size[1] / 2) {
      a[0] += e.force[0]; a[1] += e.force[1]; a[2] += e.force[2];
    }
  }
  return a;
}

/** Le joueur est-il sur (ou juste au-dessus de) cette dalle ? Sert aux checkpoints et à l'arrivée. */
export function onPad(e: LevelElement, p: Vec3): boolean {
  const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw);
  const dx = p[0] - e.pos[0], dz = p[2] - e.pos[2];
  const lx = dx * cos - dz * sin, lz = dx * sin + dz * cos;
  const top = e.pos[1] + e.size[1] / 2;
  return Math.abs(lx) <= e.size[0] / 2 + 0.3 && Math.abs(lz) <= e.size[2] / 2 + 0.3 && p[1] > top - 0.6 && p[1] < top + 3.5;
}

export function topOf(e: LevelElement): number {
  return e.pos[1] + e.size[1] / 2;
}

/** Point le plus bas atteint par un élément (pour killY). Le décor, les panneaux, le brouillard et les faux murs ne comptent pas. */
export function elementBottom(e: LevelElement): number {
  const b = e.pos[1] - e.size[1] / 2;
  switch (e.type) {
    case 'gate': return b - e.drop;
    case 'ferris': return b - e.radius;
    case 'wreckingball': return b - e.length * Math.cos(e.angle);
    case 'boulder': return Math.min(b, b + e.delta[1]);
    case 'ramp': return b - Math.abs(e.rise) / 2;
    case 'zipline': return Math.min(b, Math.min(e.pos[1], e.to[1]) - PHYS.zipHang);
    default: return b;
  }
}

export function levelKillY(level: Level): number {
  if (level.killY !== undefined) return level.killY;
  let min = Infinity;
  for (const e of level.elements) if (!VISUAL_ONLY.has(e.type)) min = Math.min(min, elementBottom(e));
  return min - 12;
}

/** Brouillard au point p (caméra ou joueur) : densité maximale des zones `fog` qui le contiennent, ou null. */
export function fogAt(level: Level, p: Vec3): { density: number; color?: string } | null {
  let best: { density: number; color?: string } | null = null;
  for (const e of level.elements) {
    if (e.type !== 'fog') continue;
    const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw), dx = p[0] - e.pos[0], dz = p[2] - e.pos[2];
    const lx = dx * cos - dz * sin, lz = dx * sin + dz * cos;
    if (Math.abs(lx) > e.size[0] / 2 || Math.abs(lz) > e.size[2] / 2 || Math.abs(p[1] - e.pos[1]) > e.size[1] / 2) continue;
    if (!best || e.density > best.density) best = { density: e.density, color: e.color };
  }
  return best;
}

/** Catalogue lisible par un humain ou par Claude : types d'éléments, paramètres et capacités du personnage. */
export function elementCatalog() {
  const r = (n: number) => Math.round(n * 100) / 100;
  return {
    conventions: {
      axes: 'x et z horizontaux, y vers le haut, unités en mètres. yaw en radians autour de y.',
      pos: 'Centre de la boîte (sauf hammer et wreckingball : point de pivot ; zipline : départ du câble). Le dessus d\'une dalle est à pos.y + size.y / 2 (rampe : au milieu de la pente). Les zones launcher, teleport, lowgrav et wind agissent quand les pieds du joueur sont dans la boîte (tournée par yaw).',
      size: '[largeur x, hauteur y, profondeur z].',
      ordre: 'Les checkpoints sont numérotés dans l\'ordre du tableau `elements`. Un seul `start`, au moins un `finish`.',
      phase: 'Décalage de cycle entre 0 et 1 pour désynchroniser des obstacles identiques.',
    },
    character: {
      radius: PHYS.radius,
      height: PHYS.height,
      runSpeed: PHYS.speed,
      jumpHeight: r(jumpHeight()),
      safeGapByHeightDiff: [-6, -3, -1, 0, 0.5, 1, 1.5].map((dh) => ({ heightDiff: dh, maxGap: r(jumpReach(dh) * SAFETY) })),
      note: `Écart horizontal maximal conseillé entre deux bords (marge de ${Math.round((1 - SAFETY) * 100)} % incluse). Au-delà de +${r(jumpHeight())} m de dénivelé, il faut un trampoline (simple ou directionnel), un ventilateur, une plateforme mobile verticale, des bulles, une rampe, de la gélatine, une zone lunaire, un canon à joueurs, une tyrolienne ou un téléporteur.`,
    },
    elements: [
      { type: 'start', description: 'Dalle de départ (solide). Prévoir au moins 8 × 8 m pour 10 joueurs.', params: { skin: SKIN_DOC } },
      { type: 'finish', description: 'Dalle d\'arrivée (solide). La toucher termine la course.', params: { skin: SKIN_DOC } },
      { type: 'checkpoint', description: 'Dalle solide ; point de réapparition après une chute.', params: { skin: SKIN_DOC } },
      { type: 'platform', description: 'Plateforme fixe.', params: { color: 'optionnel, "#rrggbb"', skin: SKIN_DOC } },
      { type: 'ice', description: 'Sol glissant : très peu d\'adhérence.', params: {} },
      { type: 'moving', description: 'Plateforme mobile qui va et vient entre pos et pos + delta.', params: { delta: '[x, y, z]', period: 'secondes pour un aller-retour (1–30, défaut 4)', phase: '0–1', skin: SKIN_DOC } },
      { type: 'trampoline', description: 'Fait rebondir.', params: { bounce: `vitesse verticale 10–24 (défaut 15 → rebond de ${r(jumpHeight(15))} m ; 20 → ${r(jumpHeight(20))} m)` } },
      { type: 'conveyor', description: 'Tapis roulant qui entraîne le joueur.', params: { dir: '[x, z] direction', speed: 'm/s 0.5–10 (défaut 4)' } },
      { type: 'crumble', description: 'Dalle qui s\'effondre après qu\'on a marché dessus, puis réapparaît.', params: { delay: 'secondes avant la chute (défaut 0.5)', respawn: 'secondes avant le retour (défaut 4)', skin: SKIN_DOC + ' ; "cloud" : le nuage se dissout au lieu de tomber' } },
      { type: 'spinner', description: 'Barre tournante (obstacle) : `size` est la taille de la barre, elle tourne autour de son centre. La placer 0.3–0.6 m au-dessus d\'une plateforme pour qu\'on doive sauter par-dessus.', params: { speed: 'rad/s, -6 à 6 (défaut 1.5)', phase: '0–1' } },
      { type: 'hammer', description: 'Marteau pendule : `pos` est le pivot, `size` la tête, qui passe au plus bas à pos.y - length.', params: { length: 'longueur du bras 1–12 (défaut 5)', axis: '"x" ou "z" : direction du balancement', amplitude: 'angle max en radians 0.2–1.5 (défaut 1.1)', period: 'secondes (défaut 3)', phase: '0–1', strike: '0 (pendule, défaut) ; 1 ou -1 : marteau qui tape — le bras part de la verticale au-dessus du pivot et s\'abat à l\'horizontale vers +axe (1) ou -axe (-1), au rythme d\'une guillotine (amplitude ignorée). Poser le pivot au bord de la table, à la hauteur du centre de la tête une fois posée.', skin: '"mallet" : gros maillet en bois' } },
      { type: 'fan', description: 'Ventilateur : `pos`/`size` décrivent la zone de souffle (pas de collision). Avec force.y > 24 (la gravité) il soulève le joueur jusqu\'en haut de la zone.', params: { force: '[x, y, z] accélération en m/s² (défaut [0, 42, 0])' } },
      { type: 'cannon', description: 'Canon pousseur : bloc qui jaillit périodiquement de `stroke` mètres dans la direction `dir` et éjecte les joueurs.', params: { dir: '[x, z]', stroke: 'course 0.5–10 (défaut 3)', period: 'secondes (défaut 3)', phase: '0–1' } },
      { type: 'roller', description: 'Rouleau broyeur : cylindre couché d\'axe x local, size = [longueur, diamètre, diamètre]. On peut marcher dessus ; le dessus entraîne le joueur perpendiculairement à l\'axe (vers +z local si speed > 0, comme un tapis). Pour traverser une rangée de rouleaux, orienter leur axe en travers du chemin.', params: { speed: 'vitesse de surface m/s, -8 à 8 (défaut 3) ; le signe donne le sens' } },
      { type: 'puncher', description: 'Mur poinçonneur : `count` blocs répartis le long de x local dans `size`, qui jaillissent chacun de `stroke` m vers +z local (orienter avec yaw), en vague (bloc k décalé de k × stagger cycle). Éjecte comme un canon.', params: { count: '1–12 (défaut 4)', stroke: 'course 0.5–8 (défaut 2.5)', period: 'secondes 1–12 (défaut 3)', stagger: 'décalage entre blocs, fraction de cycle 0–1 (défaut 0.15)', phase: '0–1' } },
      { type: 'gate', description: 'Porte guillotine : `pos` est la position HAUTE de la lame ; elle tombe vite de `drop` m (10 % du cycle), reste en bas (20 %), remonte lentement (40 %) puis reste en haut (30 %). Le joueur sous la lame qui tombe est éjecté. Donner une lame fine (size.z ≈ 0.5) qui barre le chemin ; en haut, son bas doit être ≥ 1.7 m au-dessus du sol pour passer dessous.', params: { drop: 'm 0.5–20 (défaut 3)', period: 'secondes 1.5–20 (défaut 4)', phase: '0–1', skin: '"mallet" : maillet en bois qui tape de haut en bas (tête = la boîte, manche vers le haut, sans portique) ; le poser pour que sa tête arrive au ras de la table' } },
      { type: 'turntable', description: 'Plateforme tournante : disque horizontal de diamètre size.x et d\'épaisseur size.y (size.z ignoré) qui tourne autour de son centre et entraîne le joueur.', params: { speed: 'rad/s -3 à 3 (défaut 0.8)', phase: '0–1', skin: '"record" (tourne-disque) ou "sunflower" (cœur de tournesol)' } },
      { type: 'sweeper', description: 'Balayeur double : deux barres de taille `size` (longueur x) qui tournent autour du même axe vertical. La basse (centrée sur pos, la placer 0.3–0.6 m au-dessus du sol) se saute ; la haute, perpendiculaire, passe à pos.y + highOffset et fauche ceux qui sautent : il faut rester au sol quand elle passe.', params: { speed: 'rad/s -3 à 3 (défaut 1.3)', highOffset: 'm 1.6–4 (défaut 2.1)', phase: '0–1' } },
      { type: 'ferris', description: 'Grande roue : `count` nacelles (taille `size`, restent horizontales) en orbite sur un cercle de rayon `radius` centré sur pos, dans le plan vertical (x local, y) orienté par yaw. On monte dessus pour gagner de la hauteur ; la vitesse de la nacelle est transmise. Le bas du cercle doit être accessible d\'un saut depuis une plateforme.', params: { count: '1–12 (défaut 4)', radius: 'm 1.5–20 (défaut 5)', period: 'secondes par tour 4–60 (défaut 14)', phase: '0–1' } },
      { type: 'pistons', description: 'Pistons de sol : `count` dalles alignées le long de x local dans `size` (position basse = pos) qui montent et descendent de `height` m en sinusoïde, la dalle k décalée de k × stagger cycle. On se tient dessus.', params: { count: '1–16 (défaut 4)', height: 'm 0.3–8 (défaut 2)', period: 'secondes 1–20 (défaut 3)', stagger: 'fraction de cycle 0–1 (défaut 0.25)', phase: '0–1' } },
      { type: 'wreckingball', description: 'Boule de démolition (pendule conique) : `pos` est le pivot, la boule (`size`) pend à `length` m et décrit un cercle horizontal de rayon length × sin(angle) à l\'altitude pos.y − length × cos(angle). Éjecte le joueur.', params: { length: 'bras 1–20 (défaut 6)', angle: 'inclinaison du bras en radians 0.1–1.3 (défaut 0.7)', period: 'secondes par tour 2–20 (défaut 4)', phase: '0–1' } },
      { type: 'crusher', description: 'Étau : deux murs (épaisseur `thickness`, hauteur size.y, profondeur size.z) face à face le long de x local, qui se rapprochent jusqu\'à `minGap` puis s\'écartent jusqu\'à size.x (écart intérieur). Jamais écrasant : ils poussent le joueur. On passe entre eux le long de z local.', params: { minGap: 'écart minimal m 1.2–20 (défaut 1.4)', thickness: 'm 0.3–4 (défaut 1)', period: 'secondes 1.5–20 (défaut 4)', phase: '0–1' } },
      { type: 'blink', description: 'Dalle clignotante : solide pendant la fraction `on` du cycle, absente le reste du temps (elle clignote juste avant de disparaître). On se tient dessus.', params: { period: 'secondes 1.5–20 (défaut 4)', on: 'fraction solide 0.2–0.9 (défaut 0.6)', phase: '0–1', skin: '"wing" (aile d\'oiseau qui se replie vers le haut, charnière côté −x local), "scree" (éboulis qui s\'écroule puis se reforme), "cloud"' } },
      { type: 'hazard', description: 'Lave / eau / acide : surface solide dont le moindre contact renvoie au dernier checkpoint. À poser sous ou entre les plateformes (jamais sur le chemin obligé).', params: { style: '"lava" (défaut), "water", "acid" ou "floor" (parquet de la maison)' } },
      { type: 'boulder', description: 'Boules qui dévalent : toutes les `interval` s une boule de diamètre size.x part de pos et file en ligne droite jusqu\'à pos + delta en `travel` s, puis disparaît (plusieurs boules en même temps si travel > interval). Éjecte le joueur. pos.y = sol + rayon.', params: { delta: '[x, y, z] trajet', interval: 'secondes entre deux boules 1–20 (défaut 4)', travel: 'durée du trajet 1–20 (défaut 5)', phase: '0–1' } },
      { type: 'fakewall', description: 'Faux mur / raccourci secret : ressemble à une plateforme mais n\'a aucune collision (on passe au travers, on tombe si on marche dessus).', params: { color: 'optionnel, "#rrggbb"' } },
      { type: 'deco', description: 'Décor sans collision, posé avec sa base en bas de la boîte (size donne l\'échelle).', params: { kind: '"tree" (défaut), "rock", "balloon", "arrow", "flag", "cactus", "mushroom", "crystal", "crowd" (petits spectateurs qui sautillent, répartis dans la boîte), "flowers" (bouquet dans un vase), "stem" (tige de tournesol, verticale), "cloud" (nuage), "rack" (montants d\'étendoir et linge pendu, le long de x local), "room" (murs de la maison autour de la boîte)', color: 'optionnel, "#rrggbb"' } },
      { type: 'sign', description: 'Panneau sans collision affichant un texte court ; face vers +z local.', params: { text: '≤ 60 caractères' } },
      { type: 'fog', description: 'Zone de brouillard / obscurité sans collision : quand la caméra ou le joueur y est, brouillard épais.', params: { density: '0–1 (défaut 0.6)', color: 'optionnel, "#rrggbb"' } },
      { type: 'mud', description: 'Boue / colle : dalle solide sur laquelle on avance lentement et on saute bas.', params: { slow: 'facteur de vitesse 0.15–0.9 (défaut 0.45)', jumpFactor: `facteur de saut 0.3–1 (défaut 0.6 → saut de ${r(jumpHeight(PHYS.jumpV * 0.6))} m)` } },
      { type: 'jelly', description: `Sol gélatine : chaque atterrissage un peu rude (chute > ${PHYS.jellyImpact} m/s) rebondit (au moins ${PHYS.jellyMin} m/s) ; le saut depuis la gélatine est plus haut.`, params: { bounciness: 'restitution 0.2–0.9 (défaut 0.6)', jumpFactor: `facteur de saut 1–1.6 (défaut 1.2 → saut de ${r(jumpHeight(PHYS.jumpV * 1.2))} m)` } },
      { type: 'ramp', description: 'Rampe / toboggan : dalle inclinée le long de z local, d\'épaisseur size.y. Le dessus passe de pos.y + size.y/2 − rise/2 (bord −z local) à pos.y + size.y/2 + rise/2 (bord +z local). On y marche si la pente |rise|/size.z ≤ 0.6 ; avec slide: true on glisse vers le bas en accélérant (toboggan, à prendre dans le sens de la descente). Enfoncer le bas dans le sol ou le raccorder à une dalle de même hauteur.', params: { rise: 'dénivelé m -20 à 20 (défaut 2) ; négatif = descend vers +z local', slide: 'booléen (défaut false)', color: 'optionnel, "#rrggbb"' } },
      { type: 'boost', description: `Speed pad : dalle solide ; au sol dessus, la vitesse horizontale est portée à \`speed\` dans la direction \`dir\`, avec ${PHYS.boostTime} s d'adhérence réduite pour garder l'élan (sauter juste après permet de franchir de grands vides).`, params: { dir: '[x, z] direction monde (défaut [0, 1])', speed: 'm/s 8–30 (défaut 18)' } },
      { type: 'launcher', description: 'Canon à joueurs : zone d\'entrée sans collision (pos/size ; pieds dedans). Le joueur qui y entre est tiré en cloche, en roulé-boulé et sans contrôle, et atterrit exactement au point `to` (pieds) ; apogée `apex` m au-dessus du plus haut des deux points. Poser la zone sur une dalle et `to` sur le dessus d\'une autre dalle (pas dans une zone). Garder dénivelé + apex < 35 m.', params: { to: '[x, y, z] point d\'atterrissage (pieds)', apex: 'm 0.5–20 (défaut 3)' } },
      { type: 'jumppad', description: 'Trampoline directionnel : dalle solide qui renvoie le joueur avec la vitesse `launch` (repère local tourné par yaw : x local, y, z local) ; adhérence réduite pendant le vol. Viser le centre de la dalle d\'arrivée depuis le centre du trampoline.', params: { launch: '[vx -25–25, vy 4–26, vz -25–25] m/s (défaut [0, 14, 8])' } },
      { type: 'zipline', description: `Tyrolienne : câble de pos (départ, en haut) à \`to\` (arrivée). Le joueur dont les mains (pieds + ${PHYS.zipHang} m) passent à moins de ${PHYS.zipGrab} m du départ s'accroche, glisse à \`speed\` m/s (pieds ${PHYS.zipHang} m sous le câble) et est lâché au bout avec son élan ; sauter = lâcher. Placer le départ ≈ ${PHYS.zipHang + 0.1} m au-dessus d'une dalle, et l'arrivée au-dessus d'une dalle. size = poteaux d'ancrage (rendu seulement), ex. [0.4, 3, 0.4].`, params: { to: '[x, y, z] bout du câble', speed: 'm/s 3–25 (défaut 10)' } },
      { type: 'teleport', description: 'Tuyau de téléportation : zone d\'entrée sans collision (pos/size ; pieds dedans) qui transporte instantanément les pieds en `to` avec la vitesse `exitVel`. `to` ne doit pas être dans une autre zone de téléportation.', params: { to: '[x, y, z] sortie (pieds)', exitVel: '[x, y, z] m/s, chaque composante -30 à 30 (défaut [0, 0, 0])' } },
      { type: 'bubble', description: 'Bulles flottantes : `count` bulles (plateformes de taille `size`) montent de pos à pos + [0, rise, 0] en `period` s, régulièrement décalées ; arrivée en haut, la bulle éclate (on tombe) et repart d\'en bas. On se tient dessus.', params: { count: '1–12 (défaut 3)', rise: 'm 1–40 (défaut 6)', period: 'secondes 1.5–40 (défaut 6)', phase: '0–1' } },
      { type: 'lowgrav', description: 'Zone lunaire sans collision (pieds dedans) : la gravité y est multipliée par `gravity`. Les sauts y sont bien plus hauts et longs.', params: { gravity: 'facteur 0.05–1 (défaut 0.35)' } },
      { type: 'wind', description: `Rafales : zone sans collision (pieds dedans) qui pousse comme un ventilateur, avec une force qui pulse : force × (0.5 + 0.5 sin(2π(t/period + phase))). Le contrôle du personnage compense jusqu'à ${PHYS.accelGround} m/s² au sol et ${PHYS.accelAir} m/s² en l'air : une rafale plus forte que ${PHYS.accelAir} déporte surtout les sauts.`, params: { force: '[x, y, z] m/s² monde, chaque composante -40 à 40 (défaut [24, 0, 0])', period: 'secondes 0.5–20 (défaut 3)', phase: '0–1' } },
      { type: 'button', description: 'Bouton au sol (dalle solide basse, ex. size [1.6, 0.2, 1.6] dépassant de 5 cm du sol) : un joueur posé dessus ouvre pendant `duration` s toutes les `door` et `trapdoor` de même `link` (rester dessus prolonge l\'ouverture). Le placer avant la porte, sur la même plateforme, accessible à pied.', params: { link: 'chaîne 1–20 caractères (requis)', duration: 'secondes 1–60 (défaut 6)' } },
      { type: 'door', description: 'Porte : mur solide qui s\'escamote (disparaît) tant que son `link` est ouvert par un bouton ou un levier. Prévoir un `button` de même link devant elle, sinon elle bloque le passage.', params: { link: 'chaîne (requis)', color: 'optionnel, "#rrggbb"' } },
      { type: 'lever', description: 'Levier : zone sans collision ; le joueur qui la touche ouvre pendant `duration` s les `door` / `trapdoor` de même `link`, puis le levier se recharge `cooldown` s. À poser à côté du chemin, typiquement pour piéger les autres sur des trappes.', params: { link: 'chaîne (requis)', duration: 'secondes 1–60 (défaut 4)', cooldown: 'secondes 1–60 (défaut 8)' } },
      { type: 'trapdoor', description: 'Trappe : dalle solide qui s\'ouvre (disparaît) tant que son `link` est ouvert → les joueurs dessus tombent. Les bots n\'y sautent pas quand elle est ouverte.', params: { link: 'chaîne (requis)', color: 'optionnel, "#rrggbb"' } },
      { type: 'memory', description: 'Dalles mémoire : grille cols × rows de dalles dans `size` (colonnes le long de x local, rangées le long de z local : on la traverse de −z vers +z local). Le serveur piège au hasard une partie des dalles en gardant toujours un chemin sûr (une dalle par rangée, colonnes voisines ou en diagonale). Une dalle piégée tombe dès qu\'on s\'y pose et reste tombée pour tous ; une dalle sûre s\'allume pour tous. La disposition n\'est jamais envoyée aux clients.', params: { cols: '2–8 (défaut 3)', rows: '2–12 (défaut 5)', gap: 'joint entre dalles m 0–1 (défaut 0.25)', traps: 'part des dalles hors chemin piégées 0.1–0.9 (défaut 0.5)' } },
      { type: 'itembox', description: 'Boîte surprise (sans collision, ex. size [1, 1, 1], à hauteur de corps au-dessus du chemin) : le premier joueur sans objet qui la touche reçoit un objet au hasard (super saut 8 s, bouclier 6 s, banane, gant de boxe) ; elle réapparaît après `respawn` s.', params: { respawn: 'secondes 2–60 (défaut 6)' } },
      { type: 'coin', description: 'Pièce (sans collision, ex. size [0.8, 0.8, 0.8]) : chaque joueur peut ramasser chaque pièce une fois ; elles départagent le classement selon le réglage de la manche.', params: {} },
      { type: 'popper', description: 'Castors (tape-taupe) : grille cols × rows de trous dans l\'empreinte de la boîte. Le bas de la boîte est la surface du plateau (poser la boîte sur une dalle) ; un castor sorti remplit la boîte sur toute sa hauteur (ex. 1.4 m). Chaque trou, à son rythme, fait jaillir un castor au hasard (le trou tremble juste avant) : il éjecte ceux qui sont dessus ou contre lui.', params: { cols: '1–8 (défaut 3)', rows: '1–8 (défaut 3)', period: 'secondes par cycle d\'un trou 1–12 (défaut 2.4)', up: 'fraction du cycle où le castor est sorti 0.15–0.8 (défaut 0.45)', chance: 'probabilité de sortie à chaque cycle 0.1–1 (défaut 0.45)', phase: '0–1' } },
      { type: 'geyser', description: 'Jet de lave : colonne (pos/size) qui jaillit pendant la fraction `on` du cycle puis s\'arrête (elle bouillonne 1 s avant de repartir). Pendant le jet, la toucher renvoie au checkpoint. Le poser entre deux dalles : on passe quand il est éteint.', params: { period: 'secondes 2–20 (défaut 4)', on: 'fraction du cycle en éruption 0.15–0.8 (défaut 0.4)', phase: '0–1' } },
      { type: 'rockfall', description: 'Chute de pierres : la boîte est la zone (bas = sol où elles s\'écrasent, haut = d\'où elles tombent). Toutes les `interval` s, `count` pierres tombent en `warn` s à des endroits tirés au hasard ; une ombre grandit au sol pour prévenir. Une pierre qui tombe éjecte. Prévoir interval ≥ warn + 0.4 + 0.35 × count.', params: { count: '1–6 (défaut 2)', stone: 'diamètre m 0.4–2.5 (défaut 1)', interval: 'secondes 1.5–12 (défaut 3)', warn: 'durée de la chute = préavis de l\'ombre, s 0.6–4 (défaut 1.4)', phase: '0–1' } },
    ],
  };
}

/** Apparences proposées pour les dalles (catalogue). */
const SKIN_DOC = 'apparence optionnelle (collision inchangée) : maison "table", "notebook", "pencilcase", "pencil" (crayon couché le long de z local), "tv", "pot", "flowerpot" (pot de fleurs), "leaf", "wire" (fil d\'étendoir : corde fine et pose d\'équilibriste, size.z ≈ 0.5) ; ciel "cloud", "plane", "kite", "bird", "heli" ; volcan "rock", "scree"';

/** Marge de sécurité appliquée aux sauts par la validation. */
export const SAFETY = 0.85;
