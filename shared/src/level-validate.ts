// Vérifie qu'un niveau est terminable : graphe des surfaces atteignables d'un saut, avec la physique du jeu.
import { PHYS, jumpHeight, jumpReach, type Vec3 } from './physics';
import { SAFETY, STANDABLE, boostVel, jumppadVel, levelKillY, lowgravAt, rampSlope, inZone, zipCable, zipFeet, type Level, type LevelElement } from './level';

interface Node {
  i: number; // index dans level.elements
  minX: number; maxX: number; minZ: number; maxZ: number;
  topMin: number; topMax: number; // hauteur du dessus (varie pour les plateformes mobiles)
  bottom: number; // bas de la zone (ventilateurs)
  v0: number; // vitesse verticale au départ de cette surface
  speed: number; // vitesse horizontale au départ (boue : réduite)
  g: number; // facteur de gravité au départ (zone lunaire)
  fan: boolean; // zone dans laquelle on entre (ventilateur, canon, téléporteur, accroche de tyrolienne)
  parts?: Node[]; // surfaces disjointes ou positions échantillonnées (pistons, nacelles) : un saut vers/depuis l'une suffit
  arriveOnly?: boolean; // partie sur laquelle on peut arriver mais d'où l'on ne part pas (haut d'un toboggan)
  boost?: { dir: [number, number]; speed: number }; // speed pad : départ à `speed` dans la direction dir
  ballistic?: { p: Vec3; v: Vec3 }; // propulseur : on repart forcément de p avec la vitesse v (vol libre)
  exits?: number[]; // liens forcés (propulseurs) : remplacent les sauts au départ de ce nœud
}

/** Boîte englobante (alignée sur les axes) d'une boîte tournée de `yaw`. */
function boxNode(i: number, c: number[], hx: number, hz: number, yaw: number, top: number): Node {
  const cos = Math.abs(Math.cos(yaw)), sin = Math.abs(Math.sin(yaw));
  const ex = cos * hx + sin * hz, ez = sin * hx + cos * hz;
  return { i, minX: c[0] - ex, maxX: c[0] + ex, minZ: c[2] - ez, maxZ: c[2] + ez, topMin: top, topMax: top, bottom: top, v0: PHYS.jumpV, speed: PHYS.speed, g: 1, fan: false };
}

/** Zone d'entrée d'un propulseur (même logique d'accès qu'un ventilateur), qui renvoie de p à la vitesse v. */
function zoneNode(i: number, c: number[], hx: number, hz: number, yaw: number, bottom: number, top: number, p: Vec3, v: Vec3): Node {
  const n = boxNode(i, c, hx, hz, yaw, top);
  n.fan = true; n.bottom = bottom; n.ballistic = { p, v };
  return n;
}

function makeNode(e: LevelElement, i: number): Node | null {
  const top = e.pos[1] + e.size[1] / 2;
  const n = boxNode(i, e.pos, e.size[0] / 2, e.size[2] / 2, e.yaw, top);
  switch (e.type) {
    case 'launcher': return zoneNode(i, e.pos, e.size[0] / 2, e.size[2] / 2, e.yaw, e.pos[1] - e.size[1] / 2, top, [e.to[0], e.to[1], e.to[2]], [0, 0, 0]);
    case 'teleport': return zoneNode(i, e.pos, e.size[0] / 2, e.size[2] / 2, e.yaw, e.pos[1] - e.size[1] / 2, top, [e.to[0], e.to[1], e.to[2]], [e.exitVel[0], e.exitVel[1], e.exitVel[2]]);
    case 'zipline': {
      // accroche : les pieds doivent passer près de pos − zipHang ; lâcher au bout avec l'élan du câble
      const { len, dir } = zipCable(e), f = zipFeet(e, 0), r = PHYS.zipGrab * 0.7;
      return zoneNode(i, f, r, r, 0, f[1] - r, f[1] + r, zipFeet(e, len), [dir[0] * e.speed, dir[1] * e.speed, dir[2] * e.speed]);
    }
    case 'jumppad': n.ballistic = { p: [e.pos[0], top, e.pos[2]], v: jumppadVel(e) }; return n;
    case 'mud': n.v0 = PHYS.jumpV * e.jumpFactor; n.speed = PHYS.speed * e.slow; return n;
    case 'jelly': n.v0 = PHYS.jumpV * e.jumpFactor; return n;
    case 'boost': { const [vx, vz] = boostVel(e); n.boost = { dir: [vx / e.speed, vz / e.speed], speed: e.speed }; return n; }
    case 'bubble': n.topMax = top + e.rise * 0.85; return n; // on saute avant que la bulle éclate
    case 'ramp': {
      // tranches de ≤ 2 m le long de la pente ; toboggan : on ne repart que de la tranche la plus basse
      const s = rampSlope(e), k = Math.max(1, Math.ceil(e.size[2] / 2)), dz = e.size[2] / k;
      n.parts = [];
      for (let j = 0; j < k; j++) {
        const lz = -e.size[2] / 2 + (j + 0.5) * dz;
        const c = [e.pos[0] + lz * Math.sin(e.yaw), e.pos[1], e.pos[2] + lz * Math.cos(e.yaw)];
        const p = boxNode(i, c, e.size[0] / 2, dz / 2, e.yaw, top + s * lz);
        p.topMin = top + s * lz - Math.abs(s * dz) / 2; p.topMax = top + s * lz + Math.abs(s * dz) / 2;
        if (e.slide && j !== (s > 0 ? 0 : k - 1)) p.arriveOnly = true;
        n.parts.push(p);
      }
      break;
    }
  }
  if (e.type === 'turntable') {
    // disque : on ne compte que le carré central (0.75 × rayon), sûr quelle que soit la rotation
    const r = 0.75 * (e.size[0] / 2);
    return { ...boxNode(i, e.pos, r, r, 0, top) };
  }
  if (e.type === 'ferris') {
    // 12 positions échantillonnées d'une nacelle sur son orbite (le bot attend la bonne)
    n.parts = [];
    for (let k = 0; k < 12; k++) {
      const th = (k / 12) * Math.PI * 2, lx = e.radius * Math.cos(th);
      const c = [e.pos[0] + lx * Math.cos(e.yaw), e.pos[1] + e.radius * Math.sin(th), e.pos[2] - lx * Math.sin(e.yaw)];
      n.parts.push(boxNode(i, c, e.size[0] / 2, e.size[2] / 2, e.yaw, c[1] + e.size[1] / 2));
    }
  }
  if (e.type === 'pistons') {
    n.parts = [];
    const w = e.size[0] / e.count;
    for (let k = 0; k < e.count; k++) {
      const lx = -e.size[0] / 2 + (k + 0.5) * w;
      const c = [e.pos[0] + lx * Math.cos(e.yaw), e.pos[1], e.pos[2] - lx * Math.sin(e.yaw)];
      const p = boxNode(i, c, w / 2, e.size[2] / 2, e.yaw, top);
      p.topMax = top + e.height;
      n.parts.push(p);
    }
  }
  if (n.parts) {
    // enveloppe globale (pour l'affichage des distances) ; les sauts se calculent sur les parties
    n.minX = Math.min(...n.parts.map((p) => p.minX)); n.maxX = Math.max(...n.parts.map((p) => p.maxX));
    n.minZ = Math.min(...n.parts.map((p) => p.minZ)); n.maxZ = Math.max(...n.parts.map((p) => p.maxZ));
    n.topMin = Math.min(...n.parts.map((p) => p.topMin)); n.topMax = Math.max(...n.parts.map((p) => p.topMax));
    return n;
  }
  if (e.type === 'fan') {
    if (e.force[1] <= PHYS.gravity + 4) return null; // ventilateur latéral ou trop faible : simple perturbation
    n.fan = true;
    n.bottom = e.pos[1] - e.size[1] / 2;
    n.v0 = 5; // élan résiduel en sortant par le haut
    return n;
  }
  if (!STANDABLE.has(e.type)) return null;
  if (e.type === 'moving') {
    n.minX = Math.min(n.minX, n.minX + e.delta[0]); n.maxX = Math.max(n.maxX, n.maxX + e.delta[0]);
    n.minZ = Math.min(n.minZ, n.minZ + e.delta[2]); n.maxZ = Math.max(n.maxZ, n.maxZ + e.delta[2]);
    n.topMin = Math.min(top, top + e.delta[1]); n.topMax = Math.max(top, top + e.delta[1]);
  }
  if (e.type === 'trampoline') n.v0 = e.bounce;
  return n;
}

function gap(a: Node, b: Node): number {
  return Math.hypot(Math.max(0, b.minX - a.maxX, a.minX - b.maxX), Math.max(0, b.minZ - a.maxZ, a.minZ - b.maxZ));
}

/** Coût du saut de a vers b, ou -1 s'il est infaisable. Les longs sauts coûtent plus cher : le chemin retenu est le plus sûr. */
function jumpCost(a: Node, b: Node): number {
  if (a.parts || b.parts) {
    let best = -1;
    for (const pa of a.parts ?? [a]) for (const pb of b.parts ?? [b]) {
      if (pa.arriveOnly) continue;
      const c = jumpCost(pa, pb);
      if (c >= 0 && (best < 0 || c < best)) best = c;
    }
    return best;
  }
  const g = gap(a, b);
  const G = PHYS.gravity * a.g;
  let speed = a.speed;
  if (a.boost) {
    // speed pad : élan complet seulement si la cible est dans la direction du pad
    const dx = (b.minX + b.maxX - a.minX - a.maxX) / 2, dz = (b.minZ + b.maxZ - a.minZ - a.maxZ) / 2;
    if (dx * a.boost.dir[0] + dz * a.boost.dir[1] >= 0.7 * Math.hypot(dx, dz)) speed = a.boost.speed;
  }
  let reach: number;
  if (b.fan) {
    // il faut entrer dans la colonne d'air : par le côté ou en sautant dedans
    if (a.topMin > b.topMax + 0.5) reach = jumpReach(b.topMax - a.topMin, a.v0, speed, G);
    else {
      const up = Math.max(0, b.bottom - a.topMax);
      if (up > jumpHeight(a.v0, G) * SAFETY) return -1;
      reach = jumpReach(up, a.v0, speed, G);
    }
  } else reach = jumpReach(b.topMin - a.topMax, a.v0, speed, G);
  reach *= SAFETY;
  if (reach < 0 || g > reach) return -1;
  return 0.5 + g * (1 + (2 * g) / Math.max(reach, 0.1));
}

/** Surface sur laquelle retombe un vol libre parti de p à la vitesse v (première traversée d'un dessus en descendant), -1 sinon. */
function landing(nodes: Node[], from: Node, p: Vec3, v: Vec3, level: Level): number {
  const G = PHYS.gravity * lowgravAt(level, p), tol = 0.3;
  let best = -1, bestT = Infinity;
  for (const n of nodes) {
    if (n === from || n.fan) continue;
    for (const q of n.parts ?? [n]) {
      const disc = v[1] * v[1] + 2 * G * (p[1] + 0.3 - q.topMax); // 0.3 : un point posé sur la dalle compte
      if (disc < 0) continue;
      const t = (v[1] + Math.sqrt(disc)) / G;
      const x = p[0] + v[0] * t, z = p[2] + v[2] * t;
      if (x < q.minX - tol || x > q.maxX + tol || z < q.minZ - tol || z > q.maxZ + tol || t >= bestT) continue;
      bestT = t; best = n.i;
    }
  }
  return best;
}

function buildGraph(level: Level) {
  const nodes: Node[] = [];
  level.elements.forEach((e, i) => { const n = makeNode(e, i); if (n) nodes.push(n); });
  // zones lunaires : gravité réduite au départ des surfaces qui y sont
  for (const n of nodes) for (const q of n.parts ?? [n]) {
    q.g = lowgravAt(level, [(q.minX + q.maxX) / 2, q.topMax + 0.05, (q.minZ + q.maxZ) / 2]);
  }
  for (const n of nodes) if (n.ballistic) { const to = landing(nodes, n, n.ballistic.p, n.ballistic.v, level); n.exits = to >= 0 ? [to] : []; }
  const adj = new Map<number, [number, number][]>();
  for (const a of nodes) {
    const edges: [number, number][] = [];
    if (a.exits) for (const to of a.exits) edges.push([to, 0.5]);
    else for (const b of nodes) {
      const c = b === a ? -1 : jumpCost(a, b);
      if (c >= 0) edges.push([b.i, c]);
    }
    adj.set(a.i, edges);
  }
  return { nodes, adj };
}

/** Plus courts chemins (Dijkstra) depuis `from` : renvoie le prédécesseur de chaque surface atteignable. */
function bfs(adj: Map<number, [number, number][]>, from: number): Map<number, number> {
  const prev = new Map<number, number>([[from, -1]]);
  const dist = new Map<number, number>([[from, 0]]);
  const done = new Set<number>();
  for (;;) {
    let cur = -1, best = Infinity;
    for (const [i, d] of dist) if (!done.has(i) && d < best) { best = d; cur = i; }
    if (cur < 0) break;
    done.add(cur);
    for (const [nx, c] of adj.get(cur) ?? []) {
      if (best + c < (dist.get(nx) ?? Infinity)) { dist.set(nx, best + c); prev.set(nx, cur); }
    }
  }
  return prev;
}

function pathTo(prev: Map<number, number>, to: number): number[] | null {
  if (!prev.has(to)) return null;
  const out: number[] = [];
  for (let c = to; c !== -1; c = prev.get(c)!) out.unshift(c);
  return out;
}

export interface Validation {
  ok: boolean;
  errors: string[];
  warnings: string[];
  path: number[]; // index des éléments du départ à l'arrivée, en passant par les checkpoints
  stats: { elements: number; checkpoints: number; pathLength: number; estimatedSeconds: number };
}

const label = (level: Level, i: number) => `#${i} (${level.elements[i].type}${level.elements[i].id ? ` « ${level.elements[i].id} »` : ''})`;

export function validateLevel(level: Level): Validation {
  const errors: string[] = [], warnings: string[] = [];
  const idx = (t: string) => level.elements.map((e, i) => (e.type === t ? i : -1)).filter((i) => i >= 0);
  const starts = idx('start'), finishes = idx('finish'), cps = idx('checkpoint');
  if (starts.length !== 1) errors.push(`Il faut exactement un élément "start" (trouvé : ${starts.length}).`);
  if (!finishes.length) errors.push('Il faut au moins un élément "finish".');
  const { nodes, adj } = buildGraph(level);
  const path: number[] = [];
  let pathLength = 0;
  if (!errors.length) {
    const fromStart = bfs(adj, starts[0]);
    // le parcours doit s'enchaîner : départ → checkpoint 1 → … → arrivée
    let cur = starts[0];
    path.push(cur);
    for (const target of [...cps, -1]) {
      const prev = bfs(adj, cur);
      const goal = target === -1 ? finishes.find((f) => prev.has(f)) ?? finishes[0] : target;
      const seg = pathTo(prev, goal);
      if (!seg) {
        const blocked = [...prev.keys()].map((i) => label(level, i)).slice(-4).join(', ');
        errors.push(`${label(level, goal)} est inatteignable depuis ${label(level, cur)}. Dernières surfaces atteintes : ${blocked}. Rapprocher les plateformes, réduire le dénivelé (saut max ${jumpHeight().toFixed(2)} m) ou ajouter un trampoline / ventilateur.`);
        break;
      }
      path.push(...seg.slice(1));
      cur = goal;
    }
    for (const n of nodes) if (!fromStart.has(n.i)) warnings.push(`${label(level, n.i)} n'est atteignable par aucun saut depuis le départ.`);
    for (let k = 1; k < path.length; k++) {
      const a = level.elements[path[k - 1]].pos, b = level.elements[path[k]].pos;
      pathLength += Math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]);
    }
    const s = level.elements[starts[0]];
    if (s.size[0] * s.size[2] < 36) warnings.push('La dalle de départ est petite : prévoir au moins 6 × 6 m (idéalement 8 × 8) pour 10 joueurs.');
    if (pathLength > 0 && pathLength < 40) warnings.push('Parcours très court (moins de 40 m).');
    if (pathLength > 450) warnings.push('Parcours très long : il risque de ne pas tenir dans une manche de 2–3 minutes.');
    if (cps.length === 0 && pathLength > 80) warnings.push('Aucun checkpoint : une chute renvoie au départ.');
    const killY = levelKillY(level);
    for (const n of nodes) if (n.topMin <= killY) warnings.push(`${label(level, n.i)} est sous killY (${killY}) : on y meurt.`);
    for (const n of nodes) if (n.exits && !n.exits.length) warnings.push(`${label(level, n.i)} : le vol qui en part ne retombe sur aucune surface (vérifier to / launch / exitVel).`);
    vague2Warnings(level, warnings);
  }
  const ids = level.elements.map((e) => e.id).filter(Boolean);
  if (new Set(ids).size !== ids.length) warnings.push('Certains éléments partagent le même id.');
  return {
    ok: errors.length === 0, errors, warnings, path,
    stats: { elements: level.elements.length, checkpoints: cps.length, pathLength: Math.round(pathLength), estimatedSeconds: Math.round((pathLength / PHYS.speed) * 1.8) },
  };
}

/** Avertissements propres aux éléments de la vague 2 (pentes, canons, tyroliennes, téléporteurs). */
function vague2Warnings(level: Level, warnings: string[]) {
  level.elements.forEach((e, i) => {
    const l = label(level, i);
    if (e.type === 'ramp' && !e.slide && Math.abs(rampSlope(e)) > 0.6) warnings.push(`${l} : pente de ${Math.abs(rampSlope(e)).toFixed(2)} trop raide pour marcher (≤ 0.6), ou mettre slide: true.`);
    if (e.type === 'launcher' && Math.max(e.pos[1], e.to[1]) + e.apex - Math.min(e.pos[1], e.to[1]) > 35) warnings.push(`${l} : dénivelé + apex > 35 m, la chute atteint la vitesse maximale (trajectoire faussée).`);
    if (e.type === 'zipline' && zipCable(e).len < 2) warnings.push(`${l} : câble trop court (< 2 m).`);
    if (e.type === 'teleport' && level.elements.some((o) => o.type === 'teleport' && inZone(o, [e.to[0], e.to[1], e.to[2]]))) warnings.push(`${l} : la sortie est dans une zone de téléportation (aller-retour sans fin).`);
    // vague 3 : liens orphelins
    if (e.type === 'door' || e.type === 'trapdoor') {
      if (!level.elements.some((o) => (o.type === 'button' || o.type === 'lever') && o.link === e.link)) warnings.push(`${l} : aucun bouton ni levier de lien « ${e.link} »${e.type === 'door' ? ' : la porte restera fermée' : ''}.`);
    }
    if ((e.type === 'button' || e.type === 'lever') && !level.elements.some((o) => (o.type === 'door' || o.type === 'trapdoor') && o.link === e.link)) warnings.push(`${l} : aucune porte ni trappe de lien « ${e.link} ».`);
  });
}

const GLYPH: Record<string, string> = {
  start: 'S', finish: 'F', checkpoint: 'C', platform: '#', ice: 'i', moving: '~', trampoline: 'T', conveyor: '>', crumble: 'x', spinner: '+', hammer: 'H', fan: '^', cannon: 'P',
  roller: '=', puncher: 'K', gate: 'G', turntable: 'O', sweeper: 'Y', ferris: 'E', pistons: 'I', wreckingball: 'B', crusher: 'V', blink: 'b', hazard: 'L', boulder: 'o', fakewall: 'f',
  mud: 'm', jelly: 'j', ramp: '/', boost: '»', launcher: 'Q', jumppad: 'J', zipline: 'z', teleport: '@', bubble: 'u',
  button: 'n', door: 'D', lever: 'l', trapdoor: 't', memory: 'M', itembox: '?', coin: '*',
};

/** Vue de dessus en ASCII (x vers la droite, z vers le bas). */
export function asciiPreview(level: Level, maxWidth = 72): string {
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  const boxes = level.elements.filter((e) => e.type !== 'deco' && e.type !== 'sign' && e.type !== 'fog' && e.type !== 'lowgrav' && e.type !== 'wind').map((e) => {
    const cos = Math.abs(Math.cos(e.yaw)), sin = Math.abs(Math.sin(e.yaw));
    const ex = cos * e.size[0] / 2 + sin * e.size[2] / 2, ez = sin * e.size[0] / 2 + cos * e.size[2] / 2;
    const b = { x0: e.pos[0] - ex, x1: e.pos[0] + ex, z0: e.pos[2] - ez, z1: e.pos[2] + ez, y: e.pos[1], g: GLYPH[e.type] ?? '?' };
    minX = Math.min(minX, b.x0); maxX = Math.max(maxX, b.x1); minZ = Math.min(minZ, b.z0); maxZ = Math.max(maxZ, b.z1);
    return b;
  });
  const cell = Math.max(1, (maxX - minX) / maxWidth, (maxZ - minZ) / 160);
  const w = Math.max(1, Math.ceil((maxX - minX) / cell)), h = Math.max(1, Math.ceil((maxZ - minZ) / cell));
  const grid = Array.from({ length: h }, () => Array<string>(w).fill(' '));
  const order = (g: string) => ('SFC'.includes(g) ? 3 : '+HP^KGYBVoQz@Dl?*'.includes(g) ? 2 : g === 'L' ? 0 : 1); // la lave reste sous les plateformes
  const prio = Array.from({ length: h }, () => Array<number>(w).fill(0));
  for (const b of boxes) {
    const c0 = Math.floor((b.x0 - minX) / cell), c1 = Math.max(c0, Math.ceil((b.x1 - minX) / cell) - 1);
    const r0 = Math.floor((b.z0 - minZ) / cell), r1 = Math.max(r0, Math.ceil((b.z1 - minZ) / cell) - 1);
    for (let r = r0; r <= Math.min(h - 1, r1); r++) for (let c = c0; c <= Math.min(w - 1, c1); c++) {
      if (order(b.g) >= prio[r][c]) { grid[r][c] = b.g; prio[r][c] = order(b.g); }
    }
  }
  const legend = Object.entries(GLYPH).map(([k, g]) => `${g}=${k}`).join('  ');
  return [
    `${level.title || level.name} — x de ${minX.toFixed(1)} à ${maxX.toFixed(1)} (→), z de ${minZ.toFixed(1)} à ${maxZ.toFixed(1)} (↓), 1 caractère = ${cell.toFixed(2)} m`,
    ...grid.map((row) => row.join('').replace(/\s+$/, '')),
    legend,
  ].join('\n');
}
