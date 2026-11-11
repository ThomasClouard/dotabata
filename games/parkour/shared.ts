// Parcours délirant — règles partagées entre le client (joueur local) et le serveur (bots).
import type { GameMeta } from '../../shared/src/game-api';
import { PHYS, jostle, type Body, type Contact, type Vec3 } from '../../shared/src/physics';
import { fanAccel, inZone, launchVelocity, lowgravAt, windAccel, zipCable, zipFeet, memoryKey, type Level, type LevelState } from '../../shared/src/level';

export const parkourMeta: GameMeta = {
  id: 'parkour',
  name: 'Parcours délirant',
  description: 'Course d\'obstacles : marteaux, barres tournantes, trampolines… Le premier à l\'arrivée gagne, ou le meilleur temps : on refait le parcours autant qu\'on veut.',
  settings: {
    mode: { type: 'choice', label: 'Mode', default: 'first', options: ['first', 'best'], labels: ['Premier arrivé', 'Meilleur temps'] },
    duration: { type: 'number', label: 'Durée de la manche', default: 150, min: 45, max: 300, step: 15, unit: 's' },
    hurry: { type: 'number', label: 'Temps restant après le premier arrivé', default: 40, min: 10, max: 120, step: 5, unit: 's' },
    levels: { type: 'multi', label: 'Niveaux autorisés', default: [], options: [] },
    jostle: { type: 'bool', label: 'Bousculades entre joueurs', default: true },
    coins: { type: 'bool', label: 'Pièces : départager les ex æquo', default: true },
  },
};

export interface ParkourInit {
  level: Level;
  endAt: number;
  cps: number[]; // index des checkpoints dans level.elements
  jostle: boolean; // bousculades entre joueurs (réglage de la manche) : false = on se traverse
  coins: boolean; // les pièces départagent le classement
  mode: 'first' | 'best'; // premier arrivé, ou meilleur temps (on recommence autant qu'on veut)
}

export interface ContactEvents {
  knocked: boolean; // percuté par un obstacle : roulé-boulé + marque sur la peau
  crumble: number[]; // dalles friables sur lesquelles on vient de marcher
  bounced: boolean;
  killed: boolean; // a touché un `hazard` (lave, eau, acide) : à traiter comme une chute (retour au checkpoint)
  hazard: number; // index de l'élément `hazard` touché (-1 sinon), pour le style de l'effet (lave / eau / acide)
  boosted: boolean; // au sol sur un speed pad (`boost`) pendant ce pas
}

/** Coefficient d'éjection (vitesse de l'obstacle × k) et condition de frappe par type d'obstacle. */
function hitFactor(c: Contact): number {
  const speed = Math.hypot(c.cv[0], c.cv[2]);
  const side = !c.ground;
  switch (c.tag) {
    case 'hammer': return speed > 1.5 ? 1.25 : 0;
    case 'spinner': case 'sweeper': return side && speed > 1 ? 1.4 : 0;
    case 'cannon': case 'puncher': return side && speed > 2 ? 1.1 : 0;
    case 'wreckingball': return speed > 1.5 ? 1.3 : 0;
    case 'boulder': return side && speed > 1.5 ? 1.2 : 0;
    case 'gate': return side && c.cv[1] < -2 ? 1 : 0; // lame qui tombe
    default: return 0;
  }
}

/** Événements de la pré-étape (index d'élément, -1 sinon) : pour les sons / effets des clients et la progression des bots. */
export interface PreEvents {
  launched: number; // canon à joueurs qui vient de tirer
  teleported: number; // téléporteur emprunté
  grabbed: number; // tyrolienne attrapée
  released: number; // tyrolienne lâchée au bout du câble
}

/**
 * Avant le pas de physique : souffle des ventilateurs et des rafales, gravité réduite, tyroliennes, téléporteurs
 * et canons à joueurs. `t` = horloge serveur (rafales). Ordre fixe, porté tel quel côté Godot.
 */
export function parkourPreStep(level: Level, b: Body, dt: number, t = 0): PreEvents {
  const ev: PreEvents = { launched: -1, teleported: -1, grabbed: -1, released: -1 };
  const a = fanAccel(level, b.p);
  b.v[0] += a[0] * dt; b.v[1] += a[1] * dt; b.v[2] += a[2] * dt;
  const w = windAccel(level, b.p, t);
  b.v[0] += w[0] * dt; b.v[1] += w[1] * dt; b.v[2] += w[2] * dt;
  const g = lowgravAt(level, b.p);
  if (g < 1) b.v[1] += PHYS.gravity * (1 - g) * dt; // stepBody retire g·dt : il reste g·gravity·dt
  if (b.zip >= 0) {
    // suspendu : on avance le long du câble ; au bout, on lâche avec l'élan du câble
    const e = level.elements[b.zip];
    if (e?.type !== 'zipline') { b.zip = -1; return ev; }
    const { len, dir } = zipCable(e);
    b.zipS += e.speed * dt;
    if (b.zipS >= len) { b.zipS = len; ev.released = b.zip; b.zip = -1; b.cool = PHYS.zipCool; }
    b.p = zipFeet(e, b.zipS);
    b.v = [dir[0] * e.speed, dir[1] * e.speed, dir[2] * e.speed];
    return ev;
  }
  for (let i = 0; i < level.elements.length; i++) {
    const e = level.elements[i];
    if (e.type === 'zipline' && b.cool <= 0) {
      const dx = b.p[0] - e.pos[0], dy = b.p[1] + PHYS.zipHang - e.pos[1], dz = b.p[2] - e.pos[2];
      if (dx * dx + dy * dy + dz * dz > PHYS.zipGrab * PHYS.zipGrab) continue;
      const { dir } = zipCable(e);
      b.zip = i; b.zipS = 0;
      b.p = zipFeet(e, 0);
      b.v = [dir[0] * e.speed, dir[1] * e.speed, dir[2] * e.speed];
      b.flight = 0; b.boost = 0; b.tumble = 0;
      ev.grabbed = i;
      return ev;
    }
    if (e.type === 'teleport' && b.cool <= 0 && inZone(e, b.p)) {
      b.p = [e.to[0], e.to[1], e.to[2]];
      b.v = [e.exitVel[0], e.exitVel[1], e.exitVel[2]];
      b.cool = PHYS.zipCool; b.flight = 0;
      b.grounded = false; b.coyote = 0; b.groundVel = [0, 0, 0]; b.groundId = -1;
      ev.teleported = i;
      return ev;
    }
    if (e.type === 'launcher' && b.flight <= 0 && inZone(e, b.p)) {
      const l = launchVelocity(b.p, e.to, e.apex, dt);
      b.v = l.v;
      b.flight = l.T;
      b.tumble = Math.max(b.tumble, l.T);
      b.grounded = false; b.coyote = 0; b.groundVel = [0, 0, 0]; b.groundId = -1;
      ev.launched = i;
      return ev;
    }
  }
  return ev;
}

/**
 * Réactions aux obstacles touchés pendant le pas : éjection (marteaux, barres, canons, poinçonneurs, guillotines,
 * balayeurs, boules), dalles friables, et mort au contact d'un `hazard` (ev.killed : l'appelant renvoie au checkpoint).
 */
export function parkourPostStep(b: Body, contacts: Contact[]): ContactEvents {
  const ev: ContactEvents = { knocked: false, crumble: [], bounced: false, killed: false, hazard: -1, boosted: false };
  for (const c of contacts) {
    if (c.tag === 'hazard') { ev.killed = true; ev.hazard = c.id; }
    if (c.bounced) ev.bounced = true;
    if (c.tag === 'boost' && c.ground) ev.boosted = true;
    if (c.tag === 'crumble' && c.ground) ev.crumble.push(c.id);
    if (b.tumble > 0.4) continue; // déjà en train de valser
    if (b.shield > 0) continue; // bouclier : aucune frappe
    const k = hitFactor(c);
    if (k <= 0) continue;
    if (c.tag === 'gate') {
      // la lame tombe : on écarte le joueur à l'horizontale (selon la normale, sinon à rebours de sa course, sinon vers +z)
      let dx = c.n[0], dz = c.n[2], d = Math.hypot(dx, dz);
      if (d < 0.3) { dx = -b.v[0]; dz = -b.v[2]; d = Math.hypot(dx, dz); }
      if (d < 0.1) { dx = 0; dz = 1; d = 1; }
      b.v[0] = (dx / d) * 7; b.v[2] = (dz / d) * 7;
      b.v[1] = Math.min(b.v[1], 0);
    } else {
      b.v[0] = c.cv[0] * k; b.v[2] = c.cv[2] * k;
      b.v[1] = Math.max(b.v[1], 5.5);
    }
    b.tumble = 1.1;
    b.grounded = false; b.coyote = 0;
    ev.knocked = true;
  }
  return ev;
}

export function formatTime(s: number): string {
  const m = Math.floor(s / 60), r = s - m * 60;
  return `${m}:${r < 10 ? '0' : ''}${r.toFixed(1)}`;
}

// ———————————————————— vague 3 : interactions, objets, pièces ————————————————————

export type ItemKind = 'super' | 'shield' | 'banana' | 'glove';
export const ITEMS: readonly ItemKind[] = ['super', 'shield', 'banana', 'glove'];
export const ITEM_NAMES: Record<ItemKind, string> = { super: 'Super saut', shield: 'Bouclier', banana: 'Banane', glove: 'Gant de boxe' };

/** Réglages des objets et des interactions (serveur ; durées en secondes, distances en mètres). */
export const ITEM = {
  superTime: 8,
  shieldTime: 6,
  bananaBack: 1.2, // la banane est posée derrière le joueur, à cette distance
  bananaArm: 0.6, // délai avant qu'elle puisse faire glisser (même son poseur)
  bananaR: 0.7, // rayon de glissade autour de la banane (horizontal, |dy| ≤ 0.6)
  bananaLife: 60, // durée de vie d'une banane posée
  slipSpeed: 9, // vitesse de la glissade (dans le sens de la marche, sinon du regard)
  slipUp: 4,
  slipTumble: 1.3,
  gloveRange: 3.5, // portée du gant
  gloveDot: 0.4, // cosinus minimal entre le regard et la cible
  gloveV: 13, // vitesse horizontale donnée aux joueurs frappés
  gloveUp: 6,
  gloveTumble: 1.1,
} as const;

/** Messages serveur → clients de la vague 3 (dans { t: 'game', m }). Les anciens (cp, finish, hurry, crumble) sont inchangés. */
export type ParkourServerMsg =
  | { t: 'open'; link: string; at: number; until: number; by: number } // bouton / levier `by` a ouvert `link`
  | { t: 'lever'; i: number; at: number } // levier actionné (recharge jusqu'à at + cooldown)
  | { t: 'tile'; i: number; k: number; at: number } // dalle mémoire piégée qui tombe (pour toujours)
  | { t: 'safe'; i: number; k: number } // dalle mémoire reconnue sûre
  | { t: 'box'; i: number; until: number; id: string } // boîte surprise prise par id, revient à until
  | { t: 'item'; id: string; kind: ItemKind | null } // objet tenu par id (null = plus rien)
  | { t: 'effect'; id: string; kind: 'super' | 'shield'; until: number } // effet actif sur id jusqu'à until
  | { t: 'banana'; k: number; p: Vec3 } // banane posée
  | { t: 'bananaGone'; k: number; by: string } // banane écrasée par `by` ('' = expirée)
  | { t: 'glove'; id: string; hit: string[] } // coup de gant de id
  | { t: 'coin'; id: string; i: number; n: number } // id a ramassé la pièce i (n pièces au total)
  | { t: 'killed'; id: string; i: number; p: Vec3 }; // id est mort dans le hazard i (effet chez tous)

/** Messages clients → serveur ajoutés (dans { t: 'game', m }). Les anciens : { t: 'crumble', i }, { t: 'hit' }. */
export type ParkourClientMsg = { t: 'use' } | { t: 'killed'; i: number };

/**
 * Met à jour l'état de niveau d'un client avec un message du serveur (portes, leviers, dalles mémoire, boîtes,
 * pièces du joueur local, bananes, dalles friables). Renvoie true si le message concernait l'état de niveau.
 */
export function applyLevelMsg(state: LevelState, m: any, myId: string): boolean {
  switch (m?.t) {
    case 'crumble': {
      const at = state.crumbled.get(m.i);
      if (at === undefined || Math.abs(at - m.at) > 1) state.crumbled.set(m.i, m.at);
      return true;
    }
    case 'open': state.links.set(m.link, { at: m.at, until: m.until }); return true;
    case 'lever': state.levers.set(m.i, m.at); return true;
    case 'tile': state.tiles.set(memoryKey(m.i, m.k), m.at); return true;
    case 'safe': state.safe.add(memoryKey(m.i, m.k)); return true;
    case 'box': state.boxes.set(m.i, m.until); return true;
    case 'coin': if (m.id === myId) state.coins.add(m.i); return true;
    case 'banana': state.bananas.set(m.k, [m.p[0], m.p[1], m.p[2]]); return true;
    case 'bananaGone': state.bananas.delete(m.k); return true;
    default: return false;
  }
}

/** Applique au corps local un effet d'objet annoncé par le serveur (super saut, bouclier). Renvoie true si appliqué. */
export function applyEffectMsg(b: Body, m: any, myId: string, now: number): boolean {
  if (m?.t !== 'effect' || m.id !== myId) return false;
  const left = Math.max(0, m.until - now);
  if (m.kind === 'super') b.superJump = left;
  else if (m.kind === 'shield') b.shield = left;
  else return false;
  return true;
}

/** Bousculade entre joueurs selon le réglage de la manche : sans effet si désactivée. Voir `jostle` (physics.ts). */
export function parkourJostle(init: Pick<ParkourInit, 'jostle'>, b: Body, op: Vec3, ov: Vec3): boolean {
  return init.jostle !== false && jostle(b, op, ov);
}

/**
 * Disposition d'une grille mémoire (serveur seulement, jamais envoyée) : true = dalle piégée. Un chemin sûr est garanti :
 * une dalle par rangée, la colonne variant d'au plus 1 d'une rangée à la suivante ; les autres dalles sont piégées avec la
 * probabilité `traps`.
 */
export function memoryLayout(cols: number, rows: number, traps: number, rnd: () => number = Math.random): boolean[] {
  const trap = Array.from({ length: cols * rows }, () => rnd() < traps);
  let col = Math.floor(rnd() * cols);
  for (let row = 0; row < rows; row++) {
    trap[row * cols + col] = false;
    col = Math.max(0, Math.min(cols - 1, col + Math.floor(rnd() * 3) - 1));
  }
  return trap;
}
