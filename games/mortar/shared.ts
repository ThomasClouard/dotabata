// Abri & mortier — constantes, géométrie de l'arène et balistique, partagées client / serveur.
import type { GameMeta } from '../../shared/src/game-api';
import type { Collider, Vec3 } from '../../shared/src/physics';

export const mortarMeta: GameMeta = {
  id: 'mortar',
  name: 'Abri & mortier',
  description: 'Construis ton abri, puis bombarde les îles voisines au mortier. Dernier survivant gagne.',
  settings: {
    buildTime: { type: 'number', label: 'Temps de construction', default: 20, min: 5, max: 90, step: 5, unit: 's' },
    battleTime: { type: 'number', label: 'Durée de la bataille', default: 120, min: 30, max: 300, step: 15, unit: 's' },
    budget: { type: 'number', label: 'Budget de blocs', default: 14, min: 0, max: 40, step: 1 },
    hp: { type: 'number', label: 'Points de vie', default: 100, min: 20, max: 300, step: 10 },
    crates: { type: 'bool', label: 'Caisses bonus', default: true },
    shrink: { type: 'number', label: 'Durée du rétrécissement final', default: 35, min: 0, max: 120, step: 5, unit: 's' },
    holes: { type: 'bool', label: 'Les obus trouent les îles', default: false },
  },
};

export const M = {
  island: 12, // côté d'une île (m)
  thick: 1.5,
  grid: 8, // cases constructibles par côté
  maxH: 4,
  g: 18,
  elev: (60 * Math.PI) / 180,
  vMin: 8,
  vMax: 40,
  chargeTime: 1.3,
  reload: 1.3,
  zoneR0: 8.6,
  zoneR1: 2,
} as const;

export type Mat = 'wood' | 'stone' | 'tramp';
export const MATS: Record<Mat, { cost: number; hp: number; name: string; color: number }> = {
  wood: { cost: 1, hp: 1, name: 'Bois', color: 0xc98a4b },
  stone: { cost: 2, hp: 3, name: 'Pierre', color: 0x9aa3ad },
  tramp: { cost: 3, hp: 2, name: 'Trampoline', color: 0x39c5ff },
};
export const MAT_KEYS: Mat[] = ['wood', 'stone', 'tramp'];

export type ShellKind = 'normal' | 'mega' | 'cluster' | 'sub';
export const SHELLS: Record<ShellKind, { r: number; dmg: number; block: number }> = {
  normal: { r: 2.6, dmg: 38, block: 1 },
  mega: { r: 4.6, dmg: 70, block: 3 },
  cluster: { r: 1.6, dmg: 15, block: 1 },
  sub: { r: 1.9, dmg: 24, block: 1 },
};
export type CrateKind = 'mega' | 'cluster' | 'repair';

export interface Block { plot: number; x: number; y: number; z: number; mat: Mat; hp: number }
export const blockKey = (plot: number, x: number, y: number, z: number) => `${plot}:${x}:${y}:${z}`;

export interface MortarInit {
  n: number;
  plots: Record<string, number>;
  buildEnd: number;
  battleEnd: number;
  shrinkStart: number;
  budget: number;
  hp: number;
}

export function ringRadius(n: number): number {
  if (n < 2) return 13;
  // les coins intérieurs de deux îles voisines doivent rester à plus de 6 m (hors de portée de saut)
  const a = Math.PI / n, half = M.island / 2;
  return Math.max(13, half + (3 + half * Math.cos(a)) / Math.sin(a));
}

/** Chaque île est tournée face au centre de l'arène, pour que l'écart entre voisines soit infranchissable. */
export function plotYaw(i: number, n: number): number {
  return (i / n) * Math.PI * 2;
}

/** Monde → repère de l'île (x, z). */
export function toLocal(plot: number, n: number, x: number, z: number): [number, number] {
  const c = plotCenter(plot, n), a = plotYaw(plot, n), cos = Math.cos(a), sin = Math.sin(a);
  const dx = x - c[0], dz = z - c[2];
  return [dx * cos - dz * sin, dx * sin + dz * cos];
}

/** Repère de l'île → monde (x, z). */
export function toWorld(plot: number, n: number, lx: number, lz: number): [number, number] {
  const c = plotCenter(plot, n), a = plotYaw(plot, n), cos = Math.cos(a), sin = Math.sin(a);
  return [c[0] + lx * cos + lz * sin, c[2] - lx * sin + lz * cos];
}

export function plotCenter(i: number, n: number): Vec3 {
  const a = (i / n) * Math.PI * 2, R = ringRadius(n);
  return [Math.sin(a) * R, 0, Math.cos(a) * R];
}

export function blockCenter(b: { plot: number; x: number; y: number; z: number }, n: number): Vec3 {
  const [x, z] = toWorld(b.plot, n, b.x - (M.grid - 1) / 2, b.z - (M.grid - 1) / 2);
  return [x, b.y + 0.5, z];
}

/** Case de la grille sous un point monde, ou null hors grille. */
export function cellAt(plot: number, n: number, x: number, z: number): { x: number; z: number } | null {
  const [lx, lz] = toLocal(plot, n, x, z);
  const cx = Math.floor(lx + M.grid / 2), cz = Math.floor(lz + M.grid / 2);
  return cx >= 0 && cz >= 0 && cx < M.grid && cz < M.grid ? { x: cx, z: cz } : null;
}

export function columnHeight(blocks: Map<string, Block>, plot: number, x: number, z: number): number {
  let h = 0;
  while (h < M.maxH && blocks.has(blockKey(plot, x, h, z))) h++;
  return h;
}

/** Collisions : toutes les îles + les blocs de la parcelle indiquée (un joueur ne quitte jamais son île). */
export function mortarColliders(n: number, blocks: Iterable<Block>, plot: number): Collider[] {
  const out: Collider[] = [];
  for (let i = 0; i < n; i++) {
    const c = plotCenter(i, n);
    out.push({ id: i, tag: 'island', c: [c[0], -M.thick / 2, c[2]], h: [M.island / 2, M.thick / 2, M.island / 2], yaw: plotYaw(i, n) });
  }
  let id = 1000;
  for (const b of blocks) {
    if (b.plot !== plot) continue;
    out.push({ id: id++, tag: b.mat, c: blockCenter(b, n), h: [0.5, 0.5, 0.5], yaw: plotYaw(plot, n), bounce: b.mat === 'tramp' ? 13 : undefined });
  }
  return out;
}

// ---------- Balistique ----------

export function launchSpeed(power: number): number {
  return M.vMin + (M.vMax - M.vMin) * Math.min(1, Math.max(0, power));
}

/** Position et vitesse initiales d'un obus tiré par un joueur situé en `p`, tourné vers `yaw`. */
export function launch(p: Vec3, yaw: number, power: number): { p: Vec3; v: Vec3 } {
  const s = launchSpeed(power), ch = Math.cos(M.elev) * s;
  const fx = Math.sin(yaw), fz = Math.cos(yaw);
  return { p: [p[0] + fx * 0.6, p[1] + 1.4, p[2] + fz * 0.6], v: [fx * ch, Math.sin(M.elev) * s, fz * ch] };
}

export function shellAt(p0: Vec3, v0: Vec3, t: number): Vec3 {
  return [p0[0] + v0[0] * t, p0[1] + v0[1] * t - 0.5 * M.g * t * t, p0[2] + v0[2] * t];
}

/** Portée horizontale jusqu'à retomber à la hauteur `y` (par défaut le sol des îles). */
export function shellRange(p0: Vec3, v0: Vec3, y = 0): number {
  const t = (v0[1] + Math.sqrt(v0[1] * v0[1] + 2 * M.g * (p0[1] - y))) / M.g;
  return Math.hypot(v0[0], v0[2]) * t;
}

/** Puissance (0..1) pour toucher une cible à la distance horizontale `d`. Sert aux bots. */
export function powerForDistance(d: number): number {
  let lo = 0, hi = 1;
  for (let i = 0; i < 20; i++) {
    const mid = (lo + hi) / 2;
    const l = launch([0, 0, 0], 0, mid);
    if (shellRange(l.p, l.v) + 0.6 < d) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}

/** Rayon de la zone sûre de chaque île à l'instant `t`. */
export function zoneRadius(t: number, shrinkStart: number, battleEnd: number): number {
  if (t <= shrinkStart || battleEnd <= shrinkStart) return M.zoneR0;
  const k = Math.min(1, (t - shrinkStart) / (battleEnd - shrinkStart));
  return M.zoneR0 + (M.zoneR1 - M.zoneR0) * k;
}
