// Physique maison partagée client / serveur / MCP : une capsule verticale contre des boîtes orientées (lacet seul).
export type Vec3 = [number, number, number];

export const PHYS = {
  gravity: 24,
  speed: 7,
  jumpV: 9,
  radius: 0.4,
  height: 1.5,
  accelGround: 60,
  accelAir: 20,
  accelIce: 5,
  maxFall: 45,
  coyote: 0.12,
  // —— vague 2 ——
  jellyImpact: 5, // vitesse d'impact (m/s) au-delà de laquelle la gélatine fait rebondir
  jellyMin: 4, // rebond minimal sur la gélatine (m/s)
  boostTime: 0.6, // secondes d'adhérence réduite après un speed pad
  slideMax: 20, // vitesse (m/s) au-delà de laquelle un toboggan n'accélère plus
  zipHop: 4, // vitesse verticale ajoutée en lâchant une tyrolienne par un saut
  zipCool: 0.5, // secondes avant de pouvoir se raccrocher / être re-téléporté
  zipHang: 1.9, // les pieds pendent à cette distance sous le câble (mains au-dessus de la tête)
  zipGrab: 1.2, // rayon d'accrochage autour du départ du câble (mesuré depuis les mains = pieds + zipHang)
  // —— vague 3 ——
  superJump: 1.4, // facteur de la vitesse de saut sous l'effet « super saut »
  jostleTrip: 6, // vitesse (m/s) à laquelle un autre joueur doit nous foncer dessus pour nous faire trébucher
  tripTumble: 0.7, // durée du petit roulé-boulé d'une bousculade
} as const;

/** Boîte orientée. Convention : monde = Ry(yaw) · local (identique à three.js `rotation.y`). */
export interface Collider {
  id: number;
  c: Vec3; // centre
  h: Vec3; // demi-dimensions
  yaw: number;
  vel?: Vec3; // vitesse de la surface (plateformes mobiles, marteaux…)
  angVel?: number; // vitesse angulaire autour de Y (barres tournantes)
  ice?: boolean;
  bounce?: number; // vitesse verticale de rebond (trampoline)
  conveyor?: [number, number]; // vitesse d'entraînement (x, z)
  tag?: string;
  // —— vague 2 (absents = comportement d'origine) ——
  slow?: number; // facteur de vitesse max quand on se tient dessus (boue)
  jump?: number; // facteur de vitesse de saut depuis cette surface (boue < 1, gélatine > 1)
  jelly?: number; // restitution des atterrissages (gélatine)
  slope?: number; // rampe : le dessus monte de `slope` m par m le long de z local (dalle cisaillée d'épaisseur 2·h.y)
  slide?: boolean; // rampe toboggan : peu d'adhérence, on accélère vers le bas
  boost?: [number, number]; // speed pad : vitesse horizontale (x, z) imposée au sol
  launch?: Vec3; // trampoline directionnel : vitesse imposée (monde)
}

export interface Body {
  p: Vec3; // position des pieds
  v: Vec3;
  grounded: boolean;
  groundId: number;
  groundVel: Vec3;
  onIce: boolean;
  coyote: number;
  tumble: number; // secondes de roulé-boulé restantes (contrôle réduit)
  jumped: boolean; // vrai pendant le pas où le saut part
  landed: number; // vitesse d'impact à l'atterrissage pendant ce pas (0 sinon)
  // —— vague 2 ——
  slow: number; // facteur de vitesse max du sol actuel (1 = normal, boue < 1)
  jumpK: number; // facteur de saut du sol actuel (1 = normal)
  boost: number; // secondes d'adhérence réduite restantes (speed pad, trampoline directionnel)
  flight: number; // secondes de vol balistique sans contrôle restantes (canon à joueurs)
  zip: number; // index (dans level.elements) de la tyrolienne tenue, -1 sinon
  zipS: number; // distance parcourue le long du câble (m)
  cool: number; // secondes avant de pouvoir se raccrocher à une tyrolienne / reprendre un téléporteur
  // —— vague 3 (objets) ——
  superJump: number; // secondes de super saut restantes
  shield: number; // secondes de bouclier restantes (immunise contre les frappes, bousculades et glissades)
}

export interface MoveInput {
  mx: number; // direction voulue en espace monde, norme <= 1
  mz: number;
  jump: boolean;
}

export interface Contact {
  id: number;
  tag?: string;
  n: Vec3;
  cv: Vec3; // vitesse du collider au point de contact
  ground: boolean;
  bounced: boolean;
}

export function makeBody(p: Vec3): Body {
  return { p: [p[0], p[1], p[2]], v: [0, 0, 0], grounded: false, groundId: -1, groundVel: [0, 0, 0], onIce: false, coyote: 0, tumble: 0, jumped: false, landed: 0, slow: 1, jumpK: 1, boost: 0, flight: 0, zip: -1, zipS: 0, cool: 0, superJump: 0, shield: 0 };
}

/** Annule les états temporaires (tyrolienne, vol, élan, sol spécial) : à appeler à chaque réapparition. */
export function clearMotionState(b: Body): void {
  b.zip = -1; b.zipS = 0; b.flight = 0; b.boost = 0; b.cool = 0; b.slow = 1; b.jumpK = 1;
}

export function jumpHeight(v0: number = PHYS.jumpV, g: number = PHYS.gravity): number {
  return (v0 * v0) / (2 * g);
}

/** Distance horizontale atteignable en sautant vers une surface située `dh` plus haut (négatif = plus bas). -1 si trop haut. */
export function jumpReach(dh: number, v0: number = PHYS.jumpV, speed: number = PHYS.speed, g: number = PHYS.gravity): number {
  const disc = v0 * v0 - 2 * g * dh;
  if (disc < 0) return -1;
  return (speed * (v0 + Math.sqrt(disc))) / g;
}

function colliderVelAt(c: Collider, p: Vec3): Vec3 {
  const v: Vec3 = c.vel ? [c.vel[0], c.vel[1], c.vel[2]] : [0, 0, 0];
  if (c.angVel) {
    v[0] += c.angVel * (p[2] - c.c[2]);
    v[2] -= c.angVel * (p[0] - c.c[0]);
  }
  return v;
}

/** Sort la capsule de la boîte ; renvoie la normale monde du contact ou null. */
function resolve(b: Body, c: Collider): Vec3 | null {
  const r = PHYS.radius;
  const cos = Math.cos(c.yaw), sin = Math.sin(c.yaw);
  const dx = b.p[0] - c.c[0], dz = b.p[2] - c.c[2];
  const reach = Math.hypot(c.h[0], c.h[2]) + r;
  if (dx * dx + dz * dz > reach * reach) return null;
  const lx = dx * cos - dz * sin;
  const lz = dx * sin + dz * cos;
  const a = b.p[1] + r, top = b.p[1] + PHYS.height - r; // segment de la capsule
  let ymin = c.c[1] - c.h[1], ymax = c.c[1] + c.h[1];
  const qx = Math.max(-c.h[0], Math.min(c.h[0], lx));
  const qz = Math.max(-c.h[2], Math.min(c.h[2], lz));
  // rampe : dalle cisaillée, on prend sa tranche verticale au point le plus proche (z local borné)
  if (c.slope) { const sh = c.slope * qz; ymin += sh; ymax += sh; }
  let dy = 0;
  if (top < ymin) dy = top - ymin;
  else if (a > ymax) dy = a - ymax;
  const ex = lx - qx, ez = lz - qz;
  const d2 = ex * ex + dy * dy + ez * ez;
  if (d2 >= r * r) return null;
  let nx: number, ny: number, nz: number, pen: number;
  if (d2 > 1e-10) {
    const d = Math.sqrt(d2);
    nx = ex / d; ny = dy / d; nz = ez / d; pen = r - d;
  } else {
    // axe de la capsule à l'intérieur de la boîte : sortie par la face la plus proche
    const px = c.h[0] - Math.abs(lx) + r, pz = c.h[2] - Math.abs(lz) + r;
    const pu = ymax - b.p[1], pd = b.p[1] + PHYS.height - ymin;
    pen = Math.min(px, pz, pu, pd);
    nx = 0; ny = 0; nz = 0;
    if (pen === pu) ny = 1;
    else if (pen === px) nx = lx >= 0 ? 1 : -1;
    else if (pen === pz) nz = lz >= 0 ? 1 : -1;
    else ny = -1;
  }
  const wx = nx * cos + nz * sin;
  const wz = -nx * sin + nz * cos;
  b.p[0] += wx * pen; b.p[1] += ny * pen; b.p[2] += wz * pen;
  return [wx, ny, wz];
}

/** Avance le personnage d'un pas `dt` et renvoie les contacts rencontrés. */
export function stepBody(b: Body, inp: MoveInput, cols: Collider[], dt: number): Contact[] {
  b.jumped = false;
  b.landed = 0;
  if (b.zip >= 0) {
    // suspendu à une tyrolienne : parkourPreStep a déjà placé le corps sur le câble ; sauter = lâcher
    if (!inp.jump) {
      b.grounded = false; b.onIce = false; b.coyote = 0; b.groundId = -1; b.groundVel = [0, 0, 0];
      b.boost = 0; b.flight = 0;
      b.tumble = Math.max(0, b.tumble - dt);
      if (b.superJump > 0) b.superJump = Math.max(0, b.superJump - dt);
      if (b.shield > 0) b.shield = Math.max(0, b.shield - dt);
      return [];
    }
    b.zip = -1;
    b.cool = PHYS.zipCool;
    b.v[1] = Math.max(b.v[1], 0) + PHYS.zipHop;
    b.jumped = true;
  }
  const ctrl = b.tumble > 0 ? 0.15 : 1;
  // vol de canon : aucun contrôle ; après un speed pad : adhérence de glace
  const baseAcc = b.flight > 0 ? 0 : b.boost > 0 ? PHYS.accelIce : b.grounded ? (b.onIce ? PHYS.accelIce : PHYS.accelGround) : PHYS.accelAir;
  const acc = baseAcc * ctrl * dt;
  let dx = inp.mx * PHYS.speed * b.slow + b.groundVel[0] - b.v[0];
  let dz = inp.mz * PHYS.speed * b.slow + b.groundVel[2] - b.v[2];
  const d = Math.hypot(dx, dz);
  if (d > acc) { dx *= acc / d; dz *= acc / d; }
  b.v[0] += dx; b.v[2] += dz;

  if (inp.jump && b.coyote > 0 && b.tumble <= 0) {
    let jv = PHYS.jumpV * b.jumpK;
    if (b.superJump > 0) jv *= PHYS.superJump;
    b.v[1] = jv + Math.max(0, b.groundVel[1]);
    b.coyote = 0;
    b.grounded = false;
    b.jumped = true;
  }
  b.v[1] = Math.max(-PHYS.maxFall, b.v[1] - PHYS.gravity * dt);
  b.p[0] += b.v[0] * dt; b.p[1] += b.v[1] * dt; b.p[2] += b.v[2] * dt;

  const wasGrounded = b.grounded;
  b.grounded = false;
  b.onIce = false;
  b.slow = 1;
  b.jumpK = 1;
  let gv: Vec3 = [0, 0, 0];
  let padNow = false; // trampoline directionnel touché pendant ce pas
  const contacts: Contact[] = [];
  for (const c of cols) {
    const n = resolve(b, c);
    if (!n) continue;
    const cv = colliderVelAt(c, b.p);
    const ground = n[1] > 0.6;
    let bounced = false;
    if (ground) {
      if (c.launch && b.v[1] < 2) {
        // trampoline directionnel : vitesse imposée, vol balistique sans contrôle jusqu'au prochain contact
        // (au plus 2·vy/g, durée du retour à la hauteur de départ)
        b.v[0] = c.launch[0]; b.v[1] = c.launch[1]; b.v[2] = c.launch[2];
        b.coyote = 0;
        b.flight = (2 * c.launch[1]) / PHYS.gravity;
        padNow = true;
        bounced = true;
      } else if (c.bounce && b.v[1] < 2) {
        b.v[1] = c.bounce;
        b.coyote = 0;
        bounced = true;
      } else {
        // rampe : le sol monte / descend à la vitesse que la pente impose à notre vitesse horizontale
        let gy = cv[1];
        if (c.slope) gy += c.slope * ((b.v[0] - cv[0]) * Math.sin(c.yaw) + (b.v[2] - cv[2]) * Math.cos(c.yaw));
        if (b.v[1] <= gy + 0.01) {
          if (c.jelly && b.v[1] - gy < -PHYS.jellyImpact) {
            // gélatine : rebond amorti, jamais sous jellyMin
            b.v[1] = gy + Math.max(PHYS.jellyMin, (gy - b.v[1]) * c.jelly);
            b.coyote = 0;
            bounced = true;
          } else {
            if (!wasGrounded && b.v[1] < -6) b.landed = -b.v[1];
            b.v[1] = gy;
            b.grounded = true;
            b.groundId = c.id;
            b.onIce = !!c.ice || !!c.slide;
            gv = cv;
            if (c.conveyor) { gv[0] += c.conveyor[0]; gv[2] += c.conveyor[1]; }
            if (c.slow !== undefined) b.slow = c.slow;
            if (c.jump !== undefined) b.jumpK = c.jump;
            if (c.boost) { b.v[0] = c.boost[0]; b.v[2] = c.boost[1]; b.boost = PHYS.boostTime; }
            if (c.slide && c.slope) {
              // toboggan : accélération g·sinθ·cosθ = g·s/(1+s²) vers le bas de la pente, jusqu'à slideMax
              const sn = Math.sin(c.yaw), cs = Math.cos(c.yaw);
              if (-(b.v[0] * sn + b.v[2] * cs) * Math.sign(c.slope) < PHYS.slideMax) {
                const k = ((PHYS.gravity * c.slope) / (1 + c.slope * c.slope)) * dt;
                b.v[0] -= sn * k; b.v[2] -= cs * k;
              }
            }
          }
        }
      }
    } else {
      const vn = (b.v[0] - cv[0]) * n[0] + (b.v[1] - cv[1]) * n[1] + (b.v[2] - cv[2]) * n[2];
      if (vn < 0) { b.v[0] -= n[0] * vn; b.v[1] -= n[1] * vn; b.v[2] -= n[2] * vn; }
    }
    contacts.push({ id: c.id, tag: c.tag, n, cv, ground, bounced });
  }
  if (b.grounded) {
    b.coyote = PHYS.coyote;
    b.groundVel = gv;
  } else {
    b.coyote -= dt;
    if (b.coyote <= 0) { b.groundVel = [0, 0, 0]; b.groundId = -1; }
  }
  b.tumble = Math.max(0, b.tumble - dt);
  b.boost = Math.max(0, b.boost - dt);
  b.cool = Math.max(0, b.cool - dt);
  if (b.superJump > 0) b.superJump = Math.max(0, b.superJump - dt);
  if (b.shield > 0) b.shield = Math.max(0, b.shield - dt);
  // le vol s'arrête au premier contact (sauf celui du trampoline directionnel qui vient de le lancer)
  if (b.flight > 0 && !padNow) b.flight = contacts.length ? 0 : Math.max(0, b.flight - dt);
  return contacts;
}

/** Hauteur du sol sous un point (pour les ombres et les bots). -Infinity s'il n'y a rien. */
export function groundBelow(x: number, y: number, z: number, cols: Collider[]): number {
  let best = -Infinity;
  for (const c of cols) {
    const cos = Math.cos(c.yaw), sin = Math.sin(c.yaw);
    const dx = x - c.c[0], dz = z - c.c[2];
    const lx = dx * cos - dz * sin, lz = dx * sin + dz * cos;
    let top = c.c[1] + c.h[1];
    if (c.slope) top += c.slope * lz; // rampe : hauteur du plan incliné au point (hors de la rampe : rejeté plus bas)
    if (top > y + 0.6 || top <= best) continue;
    if (Math.abs(lx) <= c.h[0] && Math.abs(lz) <= c.h[2]) best = top;
  }
  return best;
}

/** Bousculade entre deux personnages : repousse `b` hors de l'autre. */
export function pushApart(b: Body, other: Vec3): void {
  const dx = b.p[0] - other[0], dz = b.p[2] - other[2];
  if (Math.abs(b.p[1] - other[1]) > 1.3) return;
  const d = Math.hypot(dx, dz), min = PHYS.radius * 2;
  if (d >= min || d < 1e-4) return;
  const k = (min - d) / d;
  b.p[0] += dx * k * 0.5; b.p[2] += dz * k * 0.5;
  b.v[0] += (dx / d) * 1.5; b.v[2] += (dz / d) * 1.5;
}

/**
 * Bousculade complète (à appeler après stepBody pour chaque autre joueur, si le réglage est activé) :
 * pushApart, puis trébuchement si l'autre nous fonce dessus vite. op/ov = position et vitesse de l'autre.
 * Renvoie true si on vient de trébucher.
 */
export function jostle(b: Body, op: Vec3, ov: Vec3): boolean {
  const dx = b.p[0] - op[0], dz = b.p[2] - op[2];
  if (Math.abs(b.p[1] - op[1]) > 1.3) return false;
  const d = Math.hypot(dx, dz);
  if (d >= PHYS.radius * 2 || d < 1e-4) return false;
  const nx = dx / d, nz = dz / d;
  const hit = ov[0] * nx + ov[2] * nz; // vitesse de l'autre vers nous
  const mine = -(b.v[0] * nx + b.v[2] * nz); // notre vitesse vers lui (avant la poussée)
  pushApart(b, op);
  if (hit <= PHYS.jostleTrip || hit <= mine || b.tumble > 0 || b.shield > 0 || b.zip >= 0) return false;
  b.v[0] += nx * hit * 0.8; b.v[2] += nz * hit * 0.8;
  b.v[1] = Math.max(b.v[1], 3.5);
  b.tumble = PHYS.tripTumble;
  b.grounded = false; b.coyote = 0;
  return true;
}
