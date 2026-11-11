// Parcours délirant — côté client : décor du niveau, obstacles animés, réactions du joueur local, HUD.
import * as THREE from 'three';
import { esc, type ClientCtx, type ClientGame } from '../../client/src/api';
import { HIGH, balloon, canvasTex, mat, mesh, rbox, shade, slab, tex } from '../../client/src/gfx';
import { decoProp, hazardMaterial, inflatableArch, puffTex, textBoard } from '../../client/src/props';
import { PHYS, clearMotionState, type Body, type Collider, type Contact, type Vec3 } from '../../shared/src/physics';
import {
  STANDABLE, VISUAL_ONLY, ZONES, blinkState, boxReady, doorOpenness, leverDown, linkOpen, memoryKey, memoryTiles, newLevelState, boostVel, bubbleParts, frac, inZone, jumppadVel, launcherArc, rampCorners, windGust, zipCable, zipFeet, boulderBalls, buildColliders, crusherGap, crusherWalls, ferrisCabins, fogAt, gatePart, levelKillY, pistonSlabs,
  puncherBlocks, rollerAngle, spinAngle, sweeperBars, topOf, wreckingBall, type Level, type LevelElement, type Part,
} from '../../shared/src/level';
import { ITEM_NAMES, applyEffectMsg, applyLevelMsg, formatTime, parkourJostle, parkourPostStep, parkourPreStep, type ItemKind, type ParkourInit } from './shared';
import { FLAG, poseFlags } from '../../shared/src/protocol';

const PASTELS = [0xff8fab, 0xffc971, 0x7fd8f0, 0xa5e07a, 0xc9a8e8, 0xfde68a, 0x8fb8ff];
const CONFETTI = [0xff4d6d, 0xffd60a, 0x70e000, 0x00b4d8, 0x9d4edd, 0xff8c42];
const UP = new THREE.Vector3(0, 1, 0);
const TAU = Math.PI * 2;
const hex = (c: string | undefined, d: number) => (c ? new THREE.Color(c).getHex() : d);

/** Place un objet sur une sous-partie calculée par les fonctions pures du niveau (même horloge que les collisions). */
function place(o: THREE.Object3D, p: Part): void {
  o.position.set(p.c[0], p.c[1], p.c[2]);
  o.rotation.y = p.yaw;
}

/** Cylindre (rayon r) étiré entre deux points : chaînes, tiges, pieds. */
function beam(a: THREE.Vector3, b: THREE.Vector3, r: number, m: THREE.Material, parent?: THREE.Object3D): THREE.Mesh {
  const d = new THREE.Vector3().subVectors(b, a), len = d.length();
  const o = mesh(new THREE.CylinderGeometry(r, r, 1, 8), m, (a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2, parent);
  if (len > 1e-4) o.quaternion.setFromUnitVectors(UP, d.divideScalar(len));
  o.scale.y = Math.max(1e-3, len);
  return o;
}

const ITEM_EMOJI: Record<ItemKind, string> = { super: '🦘', shield: '🛡️', banana: '🍌', glove: '🥊' };
const LINK_COLORS = [0xff4d6d, 0x3a86ff, 0xffd60a, 0x70e000, 0x9d4edd, 0xff8c42, 0x00b4d8];
/** Couleur d'un lien (bouton, levier, porte, trappe de même link ont la même couleur). */
const linkColor = (link: string) => { let h = 0; for (const c of link) h = (h * 31 + c.charCodeAt(0)) >>> 0; return LINK_COLORS[h % LINK_COLORS.length]; };

/** Point d'interrogation (boîte surprise, dalles mémoire). */
const qTex = (bg: string, fg: string) => canvasTex(128, (g, s) => {
  g.fillStyle = bg; g.fillRect(0, 0, s, s);
  g.font = `900 ${s * 0.75}px "Trebuchet MS", sans-serif`; g.textAlign = 'center'; g.textBaseline = 'middle';
  g.lineWidth = s * 0.08; g.strokeStyle = 'rgba(0,0,0,0.35)'; g.strokeText('?', s / 2, s * 0.55);
  g.fillStyle = fg; g.fillText('?', s / 2, s * 0.55);
});

/** Étoile dorée sur une pièce. */
const coinTex = (() => {
  let t: THREE.CanvasTexture | null = null;
  return () => t ??= canvasTex(128, (g, s) => {
    g.fillStyle = '#ffd60a'; g.fillRect(0, 0, s, s);
    g.fillStyle = '#ffb703'; g.beginPath(); g.arc(s / 2, s / 2, s * 0.42, 0, 7); g.fill();
    g.fillStyle = '#fff3b0'; g.beginPath();
    for (let k = 0; k < 10; k++) { const r = k % 2 ? s * 0.14 : s * 0.32, a = -Math.PI / 2 + (k * Math.PI) / 5; g.lineTo(s / 2 + Math.cos(a) * r, s / 2 + Math.sin(a) * r); }
    g.fill();
  });
})();

const css6 = (c: number) => `#${c.toString(16).padStart(6, '0')}`;

/** Boue : brun avec cloques et flaques plus sombres. */
const mudTex = (rx: number, ry: number) => canvasTex(256, (g, s) => {
  g.fillStyle = '#7a4a2a'; g.fillRect(0, 0, s, s);
  for (let k = 0; k < 40; k++) {
    const x = ((k * 97) % 256), y = ((k * 57 + k * k * 3) % 256), r = 6 + ((k * 13) % 22);
    g.fillStyle = k % 3 ? 'rgba(60,32,15,0.55)' : 'rgba(160,110,70,0.5)';
    g.beginPath(); g.ellipse(x, y, r, r * 0.7, k, 0, 7); g.fill();
  }
}, rx, ry);

/** Tourbillon violet des téléporteurs. */
const swirlTex = (() => {
  let t: THREE.CanvasTexture | null = null;
  return () => t ??= canvasTex(256, (g, s) => {
    const gr = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
    gr.addColorStop(0, '#ffffff'); gr.addColorStop(0.35, '#c77dff'); gr.addColorStop(1, '#3c096c');
    g.fillStyle = gr; g.fillRect(0, 0, s, s);
    g.strokeStyle = 'rgba(255,255,255,0.7)'; g.lineWidth = 6;
    for (let a = 0; a < 4; a++) {
      g.beginPath();
      for (let k = 0; k < 60; k++) { const r = (k / 60) * s * 0.5, th = a * (Math.PI / 2) + k * 0.12; g.lineTo(s / 2 + Math.cos(th) * r, s / 2 + Math.sin(th) * r); }
      g.stroke();
    }
  });
})();

/** Petite étoile à 4 branches (zone lunaire). */
const starTex = (() => {
  let t: THREE.CanvasTexture | null = null;
  return () => t ??= canvasTex(64, (g, s) => {
    const gr = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
    gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.25, 'rgba(255,255,255,0.5)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = gr; g.fillRect(0, 0, s, s);
    g.fillStyle = '#ffffff';
    g.beginPath(); g.moveTo(s / 2, 0); g.lineTo(s * 0.56, s * 0.44); g.lineTo(s, s / 2); g.lineTo(s * 0.56, s * 0.56); g.lineTo(s / 2, s); g.lineTo(s * 0.44, s * 0.56); g.lineTo(0, s / 2); g.lineTo(s * 0.44, s * 0.44); g.fill();
  });
})();

/** Disque à quartiers colorés (dessus du plateau tournant) : on voit qu'il tourne. */
const wedges = (a: string, b: string) => canvasTex(256, (g, s) => {
  for (let k = 0; k < 8; k++) { g.fillStyle = k % 2 ? a : b; g.beginPath(); g.moveTo(s / 2, s / 2); g.arc(s / 2, s / 2, s, (k * Math.PI) / 4, ((k + 1) * Math.PI) / 4); g.fill(); }
  g.fillStyle = '#ffffff'; g.beginPath(); g.arc(s / 2, s / 2, s * 0.09, 0, 7); g.fill();
});

export function createParkourClient(): ClientGame {
  let ctx: ClientCtx;
  let level: Level;
  let cps: number[] = [];
  let endAt = 0;
  let killY = -20;
  let cp = -1;
  let finished = false;
  let respawn: Vec3 = [0, 1, 0];
  let lastHit = 0;
  let fanTimer = 0;
  let hudTimer = 0;
  // état dynamique du niveau (portes, dalles mémoire, boîtes, pièces, bananes…), tenu à jour par les messages du serveur
  const st = newLevelState();
  const crumbled = st.crumbled;
  // boîtes de collision de l'image : calculées une fois (colliders) et réutilisées par onFrame ; invalidées quand l'état change
  let frameCols: Collider[] = [], frameT = NaN;
  const frameColliders = (t: number) => {
    if (!(Math.abs(t - frameT) < 0.02)) { frameCols = buildColliders(level, t, st); frameT = t; }
    return frameCols;
  };
  const byId: (Collider | undefined)[] = [];
  let jostleOn = true;
  let held: ItemKind | null = null; // objet tenu par le joueur local
  let myCoins = 0;
  let itemEl: HTMLElement;
  const superUntil = new Map<string, number>(); // super saut actif (tous les joueurs, pour l'effet)
  const bananaMeshes = new Map<number, THREE.Object3D>();
  const shields = new Map<string, THREE.Mesh>(); // bulle de bouclier par joueur (d'après FLAG.shield)
  const fxs: { until: number; update(t: number): void; done(): void }[] = []; // effets passagers (gant)
  const hasCoins = () => level.elements.some((e) => e.type === 'coin');
  const objs: (THREE.Object3D | null)[] = [];
  const arms = new Map<number, THREE.Mesh>();
  const blades: THREE.Object3D[] = [];
  const flags = new Map<number, THREE.MeshStandardMaterial>();
  const arrows: { el: LevelElement; speed: number; meshes: THREE.Mesh[]; len: number; dir: [number, number] }[] = [];
  const finishers: { id: string; time: number }[] = [];
  let marker: THREE.Mesh;
  const deco: THREE.Object3D[] = [];
  let top: HTMLElement, side: HTMLElement;
  const va = new THREE.Vector3(), vb = new THREE.Vector3(), vd = new THREE.Vector3();
  // éléments de la vague 1 : chacun s'anime à partir des fonctions pures du niveau à l'instant t (horloge serveur)
  const anims: ((t: number) => void)[] = [];
  const emitters: { e: Extract<LevelElement, { type: 'hazard' }>; n: number }[] = [];
  const look = new THREE.Vector3(); // ce que regardent les spectateurs : le joueur local
  let emitTimer = 0;
  // vague 2
  const muds: LevelElement[] = [];
  const zips: Extract<LevelElement, { type: 'zipline' }>[] = [];
  const jiggle = new Map<number, number>(); // gélatine / trampoline directionnel : amplitude du tremblement (décroît)
  const launchers = new Map<number, THREE.Vector3>(); // bouche des canons à joueurs (fumée au tir)
  let whooshAt = 0;
  // confettis de l'arrivée : canons aux pieds de l'arche
  const confettiFrom: THREE.Vector3[] = [];
  let confettiUntil = 0;
  // brouillard : on resserre le brouillard de la scène quand la caméra ou le joueur est dans une zone `fog`
  let fog: THREE.Fog | null = null;
  let fogBase: { near: number; far: number; color: THREE.Color } | null = null;
  let fogK = 0;
  let veil: THREE.Mesh | null = null;
  const fogCol = new THREE.Color(), fogTarget = new THREE.Color();

  /** Sol statique le plus haut sous (x, z) et sous l'altitude y (pieds de panneaux), ou null. */
  function groundUnder(x: number, y: number, z: number): number | null {
    let best: number | null = null;
    for (const e of level.elements) {
      if (!STANDABLE.has(e.type) || e.type === 'moving' || e.type === 'ferris' || e.type === 'pistons') continue;
      const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw), dx = x - e.pos[0], dz = z - e.pos[2];
      if (Math.abs(dx * cos - dz * sin) > e.size[0] / 2 || Math.abs(dx * sin + dz * cos) > e.size[2] / 2) continue;
      const tp = topOf(e);
      if (tp <= y + 0.05 && (best === null || tp > best)) best = tp;
    }
    return best;
  }

  /** Longueur d'une dalle le long d'une direction monde (dir unitaire), compte tenu de son lacet. */
  function lengthAlong(e: LevelElement, dir: [number, number]): number {
    const lx = dir[0] * Math.cos(e.yaw) - dir[1] * Math.sin(e.yaw), lz = dir[0] * Math.sin(e.yaw) + dir[1] * Math.cos(e.yaw);
    return Math.min(Math.abs(lx) > 1e-3 ? e.size[0] / Math.abs(lx) : Infinity, Math.abs(lz) > 1e-3 ? e.size[2] / Math.abs(lz) : Infinity);
  }

  /** Flèches qui défilent sur le dessus d'une dalle (tapis roulant, speed pad), à `speed` m/s le long de dir (monde). */
  function movingArrows(e: LevelElement, dir: [number, number], len: number, color: number, scale: number, step: number, speed: number): void {
    const shape = new THREE.Shape([new THREE.Vector2(-0.45, -0.3), new THREE.Vector2(0, 0.05), new THREE.Vector2(0.45, -0.3), new THREE.Vector2(0.45, -0.05), new THREE.Vector2(0, 0.35), new THREE.Vector2(-0.45, -0.05)].map((v) => v.multiplyScalar(scale)));
    const ag = new THREE.ShapeGeometry(e.type === 'conveyor' ? new THREE.Shape([new THREE.Vector2(-0.45, -0.3), new THREE.Vector2(0.45, -0.3), new THREE.Vector2(0, 0.35)]) : shape).rotateX(Math.PI / 2);
    const am = new THREE.MeshBasicMaterial({ color, side: THREE.DoubleSide });
    const meshes: THREE.Mesh[] = [];
    for (let k = 0; k < Math.max(1, Math.floor(len / step)); k++) {
      const a = new THREE.Mesh(ag, am);
      a.rotation.y = Math.atan2(dir[0], dir[1]);
      ctx.scene.add(a);
      meshes.push(a);
    }
    arrows.push({ el: e, speed, meshes, len, dir });
  }

  /** Arche gonflable posée sur le bord de la dalle `e` tourné vers le point (tx, tz). Renvoie les pieds (repère monde). */
  function archOn(e: LevelElement, g: THREE.Group, tx: number, tz: number, label: string, a: string, b: string, bg: string, fg: string): THREE.Vector3[] {
    const [sx, sy, sz] = e.size;
    const dx = tx - e.pos[0], dz = tz - e.pos[2];
    const lx = dx * Math.cos(e.yaw) - dz * Math.sin(e.yaw), lz = dx * Math.sin(e.yaw) + dz * Math.cos(e.yaw);
    const onX = Math.abs(lx) / sx > Math.abs(lz) / sz; // arche sur une face ±x locale (elle enjambe alors z)
    const span = Math.max(2.4, (onX ? sz : sx) - 1);
    const arch = inflatableArch(span, label, a, b, bg, fg);
    if (onX) { arch.obj.rotation.y = Math.PI / 2; arch.obj.position.set(Math.sign(lx || 1) * (sx / 2 - 0.8), sy / 2, 0); }
    else arch.obj.position.set(0, sy / 2, Math.sign(lz || 1) * (sz / 2 - 0.8));
    g.add(arch.obj);
    anims.push((t) => arch.update!(t, look));
    g.updateMatrixWorld(true);
    return [-1, 1].map((s) => arch.obj.localToWorld(new THREE.Vector3(s * span / 2, 0.5, 0)));
  }

  function build(e: LevelElement, i: number): THREE.Object3D | null {
    const [sx, sy, sz] = e.size;
    const put = <T extends THREE.Object3D>(o: T): T => {
      o.position.set(e.pos[0], e.pos[1], e.pos[2]);
      o.rotation.y = e.yaw;
      ctx.scene.add(o);
      return o;
    };
    switch (e.type) {
      case 'platform':
        return put(slab(sx, sy, sz, e.color ? new THREE.Color(e.color).getHex() : PASTELS[i % PASTELS.length], { seed: i }));
      case 'start': {
        const g = put(slab(sx, sy, sz, 0x8ecbff, { top: 0xffffff, topMap: tex.soft('#ffffff', '#cfe8ff', sx / 4, sz / 4), seed: i }));
        // arche gonflable « DÉPART » sur le bord tourné vers le premier objectif (la caméra est derrière les joueurs)
        const first = level.elements[cps.length ? cps[0] : level.elements.findIndex((x) => x.type === 'finish')] ?? e;
        const feet = archOn(e, g, first.pos[0], first.pos[2], 'DÉPART', '#00b4d8', '#ffffff', '#ffffff', '#2b2140');
        // fanions aux coins, sauf ceux qu'occupe l'arche
        for (const [cx, cz] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
          const x = cx * (sx / 2 - 0.35), z = cz * (sz / 2 - 0.35);
          g.updateMatrixWorld(true);
          const w = g.localToWorld(new THREE.Vector3(x, sy / 2, z));
          if (feet.some((f) => Math.hypot(f.x - w.x, f.z - w.z) < 1.6)) continue;
          mesh(new THREE.CylinderGeometry(0.06, 0.06, 2.4, 8), mat(0xffffff), x, sy / 2 + 1.2, z, g);
          mesh(rbox(0.8, 0.5, 0.05, 0.02), mat(cx * cz > 0 ? 0xff4d6d : 0xffd60a), x - cx * 0.42, sy / 2 + 2.1, z, g);
        }
        return g;
      }
      case 'finish': {
        const g = put(slab(sx, sy, sz, 0xffd60a, { top: 0xffffff, topMap: tex.checker('#ffffff', '#2b2140', sx / 2, sz / 2), seed: i }));
        // arche gonflable rayée + bannière, du côté d'où l'on arrive (dernier checkpoint, sinon départ) ; canons à confettis à ses pieds
        const prev = level.elements[cps.length ? cps[cps.length - 1] : level.elements.findIndex((x) => x.type === 'start')] ?? e;
        confettiFrom.push(...archOn(e, g, prev.pos[0], prev.pos[2], 'ARRIVÉE', '#ff4d6d', '#ffffff', '#2b2140', '#ffd60a'));
        return g;
      }
      case 'checkpoint': {
        const g = put(slab(sx, sy, sz, 0x52d681, { top: 0xffffff, topMap: tex.soft('#7be495', '#a2f0b5', sx / 3, sz / 3), seed: i }));
        // portique en anneau qui s'allume à la couleur du joueur quand il est validé
        const ringMat = mat(0xdde3ea, { rough: 0.3 });
        const ring = mesh(new THREE.TorusGeometry(Math.min(sx, 5) / 2 - 0.3, 0.2, 12, 36, Math.PI), ringMat, 0, sy / 2, 0, g);
        ring.name = 'portique';
        flags.set(i, ringMat);
        return g;
      }
      case 'ice': {
        const m = put(mesh(rbox(sx, sy, sz, 0.2), new THREE.MeshStandardMaterial({ color: 0xc9f2ff, roughness: 0.04, metalness: 0.1, transparent: true, opacity: 0.86, envMapIntensity: 2.2 })));
        mesh(rbox(sx * 0.9, sy * 0.5, sz * 0.9, 0.15), mat(0xffffff, { rough: 0.1, opacity: 0.55 }), 0, 0, 0, m);
        return m;
      }
      case 'moving': {
        const g = put(slab(sx, sy, sz, 0x9d4edd, { under: false }));
        // dessous lumineux : on voit de loin que la plateforme bouge
        mesh(rbox(sx * 0.7, 0.14, sz * 0.7, 0.07), mat(0x5ef2ff, { glow: 2.2 }), 0, -sy / 2 - 0.05, 0, g);
        for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) mesh(new THREE.SphereGeometry(0.16, 10, 8), mat(0xffd60a, { glow: 1.5 }), x * (sx / 2 - 0.3), sy / 2 - 0.02, z * (sz / 2 - 0.3), g);
        return g;
      }
      case 'trampoline': {
        const g = put(new THREE.Group());
        const r = Math.min(sx, sz) / 2;
        mesh(rbox(sx, sy, sz, 0.25), mat(0x3a56e0), 0, 0, 0, g);
        mesh(new THREE.CylinderGeometry(r * 0.82, r * 0.82, 0.06, 32), mat(0xffffff, { map: tex.target('#ffd60a', '#ff4d6d') }), 0, sy / 2 + 0.02, 0, g);
        mesh(new THREE.TorusGeometry(r * 0.86, 0.13, 10, 32), mat(0xffffff, { rough: 0.25 }), 0, sy / 2 + 0.04, 0, g).rotation.x = Math.PI / 2;
        return g;
      }
      case 'conveyor': {
        const g = put(new THREE.Group());
        mesh(rbox(sx, sy, sz, 0.2), mat(0x3d4450, { rough: 0.6 }), 0, 0, 0, g);
        mesh(rbox(sx - 0.5, 0.08, sz - 0.5, 0.04), mat(0x23272e, { rough: 0.85 }), 0, sy / 2 - 0.02, 0, g);
        const n = Math.hypot(e.dir[0], e.dir[1]) || 1, dir: [number, number] = [e.dir[0] / n, e.dir[1] / n];
        // longueur du tapis le long de la direction d'entraînement (en tenant compte de son orientation)
        const lx = dir[0] * Math.cos(e.yaw) - dir[1] * Math.sin(e.yaw), lz = dir[0] * Math.sin(e.yaw) + dir[1] * Math.cos(e.yaw);
        const len = Math.min(Math.abs(lx) > 1e-3 ? sx / Math.abs(lx) : Infinity, Math.abs(lz) > 1e-3 ? sz / Math.abs(lz) : Infinity);
        // bordures de signalisation le long du tapis
        const alongX = Math.abs(lx) > Math.abs(lz);
        for (const s of [-1, 1]) {
          const rail = mesh(rbox(alongX ? sx : 0.22, 0.16, alongX ? 0.22 : sz, 0.07), mat(0xffffff, { map: tex.stripes('#ffd60a', '#2b2140', alongX ? sx : 1, alongX ? 1 : sz) }), alongX ? 0 : s * (sx / 2 - 0.13), sy / 2 + 0.05, alongX ? s * (sz / 2 - 0.13) : 0, g);
          rail.name = 'bordure';
        }
        movingArrows(e, dir, len, 0xffe14a, 1, 1.5, e.speed);
        return g;
      }
      case 'crumble':
        return put(slab(sx, sy, sz, 0xe09f3e, { top: 0xffffff, topMap: tex.cracks('#f0b458'), under: false }));
      case 'spinner': {
        const g = put(new THREE.Group());
        // barre rembourrée : le long de x (taille de la barre), section = hauteur / profondeur
        const r = Math.min(sy, sz) / 2;
        const bar = mesh(new THREE.CapsuleGeometry(r, Math.max(0.1, sx - 2 * r), 6, 16), mat(0xffffff, { map: tex.stripes('#ff4d6d', '#ffffff', 1, Math.max(2, Math.round(sx))) }), 0, 0, 0, g);
        bar.rotation.z = Math.PI / 2;
        mesh(new THREE.SphereGeometry(r * 1.5, 16, 12), mat(0xffd60a, { metal: 0.3, rough: 0.25 }), 0, 0, 0, g);
        const pole = mesh(new THREE.CylinderGeometry(0.16, 0.26, 1.4, 12), mat(0x5c6470, { metal: 0.6, rough: 0.3 }), e.pos[0], e.pos[1] - 0.7, e.pos[2]);
        ctx.scene.add(pole);
        return g;
      }
      case 'hammer': {
        const g = put(new THREE.Group());
        // maillet : cylindre couché dans l'axe du balancement, avec deux faces de frappe
        const r = Math.min(sx, sy, sz) / 2;
        const head = mesh(new THREE.CylinderGeometry(r, r, e.axis === 'x' ? sx : sz, 24), mat(0xe5383b, { rough: 0.3 }), 0, 0, 0, g);
        head.rotation.set(e.axis === 'x' ? 0 : Math.PI / 2, 0, e.axis === 'x' ? Math.PI / 2 : 0);
        for (const s of [-1, 1]) {
          const cap = mesh(new THREE.CylinderGeometry(r * 1.08, r * 1.08, 0.22, 24), mat(0xffd60a, { rough: 0.3 }), e.axis === 'x' ? s * (sx / 2 - 0.1) : 0, 0, e.axis === 'x' ? 0 : s * (sz / 2 - 0.1), g);
          cap.rotation.copy(head.rotation);
        }
        const arm = mesh(new THREE.CylinderGeometry(0.13, 0.13, 1, 10), mat(0x5c6470, { metal: 0.6, rough: 0.3 }));
        ctx.scene.add(arm);
        arms.set(i, arm);
        // potence : une poutre au-dessus du pivot
        const beam = mesh(rbox(e.axis === 'x' ? 0.5 : 3.4, 0.4, e.axis === 'x' ? 3.4 : 0.5, 0.15), mat(0x3d4450, { metal: 0.4, rough: 0.4 }), e.pos[0], e.pos[1] + 0.1, e.pos[2]);
        ctx.scene.add(beam, mesh(new THREE.SphereGeometry(0.34, 14, 10), mat(0xffd60a, { metal: 0.3, rough: 0.25 }), e.pos[0], e.pos[1], e.pos[2]));
        return g;
      }
      case 'cannon': {
        const g = put(new THREE.Group());
        mesh(rbox(sx, sy, sz, 0.25), mat(0xf72585, { rough: 0.3 }), 0, 0, 0, g);
        const n = Math.hypot(e.dir[0], e.dir[1]) || 1;
        // plaque de frappe du côté où le piston pousse
        const lx = (e.dir[0] / n) * Math.cos(e.yaw) - (e.dir[1] / n) * Math.sin(e.yaw), lz = (e.dir[0] / n) * Math.sin(e.yaw) + (e.dir[1] / n) * Math.cos(e.yaw);
        const alongX = Math.abs(lx) > Math.abs(lz), sgn = Math.sign(alongX ? lx : lz) || 1;
        mesh(rbox(alongX ? 0.2 : sx * 1.04, sy * 1.04, alongX ? sz * 1.04 : 0.2, 0.09), mat(0xffffff, { map: tex.stripes('#ffd60a', '#2b2140', 2, 2) }), alongX ? (sgn * sx) / 2 : 0, 0, alongX ? 0 : (sgn * sz) / 2, g);
        // tige du piston, étirée entre la position de repos et la tête
        const rod = mesh(new THREE.CylinderGeometry(0.2, 0.2, 1, 12), mat(0xbfc7d1, { metal: 0.8, rough: 0.2 }));
        rod.visible = false;
        ctx.scene.add(rod);
        arms.set(i, rod);
        return g;
      }
      case 'fan': {
        const g = put(new THREE.Group());
        const r = Math.min(sx, sz) / 2, by = -sy / 2;
        const col = mesh(new THREE.CylinderGeometry(r, r, sy, 24, 1, true), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.07, depthWrite: false, side: THREE.DoubleSide }), 0, 0, 0, g);
        col.userData.noShadow = true;
        mesh(new THREE.CylinderGeometry(r, r * 1.12, 0.35, 28), mat(0x3d4450, { metal: 0.5, rough: 0.35 }), 0, by + 0.17, 0, g);
        mesh(new THREE.TorusGeometry(r * 0.95, 0.09, 10, 36), mat(0x5ef2ff, { glow: 2 }), 0, by + 0.38, 0, g).rotation.x = Math.PI / 2;
        const hub = new THREE.Group();
        hub.position.y = by + 0.5;
        g.add(hub);
        mesh(new THREE.SphereGeometry(0.28, 14, 10), mat(0xffd60a), 0, 0, 0, hub);
        for (let k = 0; k < 4; k++) {
          const blade = mesh(rbox(r * 0.8, 0.05, 0.5, 0.02), mat(0xffd60a, { rough: 0.3 }), 0, 0, 0, hub);
          blade.position.set(Math.cos((k * Math.PI) / 2) * r * 0.45, 0, Math.sin((k * Math.PI) / 2) * r * 0.45);
          blade.rotation.set(0.35, -(k * Math.PI) / 2, 0);
        }
        blades.push(hub);
        return g;
      }
      // —— vague 1 ——
      case 'roller': {
        // rouleau rayé couché le long de x local ; le dessus avance vers +z local si speed > 0
        const g = put(new THREE.Group()), r = sy / 2;
        const drum = new THREE.Group();
        g.add(drum);
        mesh(new THREE.CylinderGeometry(r, r, sx - 0.24, HIGH ? 28 : 16), mat(0xffffff, { map: tex.stripes(e.speed >= 0 ? '#ff8c42' : '#3a86ff', '#fff3e0', 3, Math.max(1, Math.round(sx / 2))), rough: 0.35 }), 0, 0, 0, drum).rotation.z = Math.PI / 2;
        for (const s of [-1, 1]) {
          const cap = mesh(new THREE.CylinderGeometry(r * 1.06, r * 1.06, 0.12, HIGH ? 28 : 16), mat(0xffd60a, { rough: 0.3 }), s * (sx / 2 - 0.06), 0, 0, drum);
          cap.rotation.z = Math.PI / 2;
          // rayon peint sur le flasque : on voit le sens de rotation
          mesh(rbox(0.04, r * 1.6, 0.18, 0.02), mat(0x2b2140), s * (sx / 2 + 0.01), 0, 0, drum);
        }
        anims.push((t) => { drum.rotation.x = rollerAngle(e, t); });
        return g;
      }
      case 'puncher': {
        // rangée de blocs qui jaillissent vers +z local ; une plaque fixe derrière, une tige par bloc
        const g = put(new THREE.Group());
        mesh(rbox(sx + 0.2, sy + 0.3, 0.3, 0.1), mat(0x3d4450, { metal: 0.4, rough: 0.4 }), 0, 0, -sz / 2 - 0.2, g);
        const w = sx / e.count, hw = Math.max(0.1, w / 2 - 0.05);
        const face = tex.stripes('#ffd60a', '#2b2140', 1, 1);
        const blocks = Array.from({ length: e.count }, (_, k) => {
          const b = new THREE.Group();
          mesh(rbox(hw * 2, sy, sz, 0.18), mat(k % 2 ? 0xf72585 : 0xff4d6d, { rough: 0.3 }), 0, 0, 0, b);
          mesh(rbox(hw * 2 * 0.86, sy * 0.86, 0.12, 0.05), mat(0xffffff, { map: face }), 0, 0, sz / 2 + 0.02, b);
          const rod = mesh(new THREE.CylinderGeometry(0.11, 0.11, e.stroke + 0.3, 10), mat(0xbfc7d1, { metal: 0.8, rough: 0.2 }), 0, 0, -sz / 2 - (e.stroke + 0.3) / 2, b);
          rod.rotation.x = Math.PI / 2;
          ctx.scene.add(b);
          return b;
        });
        anims.push((t) => puncherBlocks(e, t).forEach((p, k) => place(blocks[k], p)));
        return g;
      }
      case 'gate': {
        // guillotine : lame rayée entre deux montants, voyant rouge quand elle va tomber
        const g = put(new THREE.Group());
        const bottom = -e.drop - sy / 2, topY = sy / 2 + 0.5, frame = mat(0x5c6470, { metal: 0.5, rough: 0.35 });
        for (const s of [-1, 1]) mesh(rbox(0.32, topY - bottom, Math.max(0.4, sz + 0.2), 0.1), frame, s * (sx / 2 + 0.2), (topY + bottom) / 2, 0, g);
        mesh(rbox(sx + 0.8, 0.36, Math.max(0.5, sz + 0.3), 0.12), frame, 0, topY + 0.1, 0, g);
        const lamp = mat(0x70e000, { glow: 1.5 });
        mesh(new THREE.SphereGeometry(0.2, 12, 8), lamp, 0, topY + 0.42, 0, g);
        const blade = new THREE.Group();
        mesh(rbox(sx, sy, sz, 0.12), mat(0xffffff, { map: tex.stripes('#e5383b', '#ffffff', Math.max(1, Math.round(sx / 1.5)), 1), rough: 0.3 }), 0, 0, 0, blade);
        mesh(rbox(sx * 1.01, Math.min(0.22, sy * 0.25), sz * 1.08, 0.05), mat(0xd9dee5, { metal: 0.9, rough: 0.15 }), 0, -sy / 2 + Math.min(0.11, sy * 0.125), 0, blade);
        ctx.scene.add(blade);
        anims.push((t) => {
          const p = gatePart(e, t);
          place(blade, p);
          const warn = p.untilFall < 1.2;
          lamp.color.set(warn ? 0xff3030 : 0x70e000);
          lamp.emissive.copy(lamp.color);
          lamp.emissiveIntensity = warn ? (Math.sin(t * 25) > 0 ? 2.5 : 0.3) : 1.2;
        });
        return g;
      }
      case 'turntable': {
        // disque à quartiers sur un pied ; tourne avec spinAngle (le collider est un octogone de même aire)
        const g = put(new THREE.Group()), R = sx / 2;
        mesh(new THREE.CylinderGeometry(R, R * 0.96, sy, HIGH ? 48 : 24), mat(0x3a56e0, { rough: 0.4 }), 0, 0, 0, g);
        mesh(new THREE.CircleGeometry(R * 0.97, HIGH ? 48 : 24).rotateX(-Math.PI / 2), mat(0xffffff, { map: wedges('#ffd60a', '#ff8fab') }), 0, sy / 2 + 0.01, 0, g);
        mesh(new THREE.TorusGeometry(R * 0.985, 0.1, 8, HIGH ? 48 : 24), mat(0xffffff, { rough: 0.25 }), 0, sy / 2, 0, g).rotation.x = Math.PI / 2;
        ctx.scene.add(mesh(new THREE.CylinderGeometry(0.35, 0.6, 2.4, 14), mat(0x5c6470, { metal: 0.6, rough: 0.3 }), e.pos[0], e.pos[1] - sy / 2 - 1.2, e.pos[2]));
        anims.push((t) => { g.rotation.y = spinAngle(e, t); });
        return g;
      }
      case 'sweeper': {
        // deux barres rembourrées sur un même mât : basse (à sauter) et haute perpendiculaire (à éviter en restant au sol)
        const r = Math.min(sy, sz) / 2;
        const bars = [0, 1].map((k) => {
          const b = new THREE.Group();
          const bar = mesh(new THREE.CapsuleGeometry(r, Math.max(0.1, sx - 2 * r), 6, 16), mat(0xffffff, { map: tex.stripes(k ? '#3a86ff' : '#ff4d6d', '#ffffff', 1, Math.max(2, Math.round(sx))) }), 0, 0, 0, b);
          bar.rotation.z = Math.PI / 2;
          mesh(new THREE.SphereGeometry(Math.max(0.2, r * 1.5), 16, 12), mat(0xffd60a, { metal: 0.3, rough: 0.25 }), 0, 0, 0, b);
          ctx.scene.add(b);
          return b;
        });
        const g = put(new THREE.Group());
        const h = e.highOffset + 0.4;
        mesh(new THREE.CylinderGeometry(0.12, 0.2, h + 1, 12), mat(0x5c6470, { metal: 0.6, rough: 0.3 }), 0, (h - 1) / 2, 0, g);
        mesh(new THREE.SphereGeometry(0.22, 12, 8), mat(0xffd60a, { glow: 0.8 }), 0, h, 0, g);
        anims.push((t) => sweeperBars(e, t).forEach((p, k) => place(bars[k], p)));
        return g;
      }
      case 'ferris': {
        // grande roue dans le plan (x local, y) : deux jantes, rayons, pieds ; les nacelles restent horizontales
        const g = put(new THREE.Group()), R = e.radius, zr = sz / 2 + 0.3;
        const frame = mat(0xffffff, { rough: 0.3 }), steel = mat(0x5c6470, { metal: 0.6, rough: 0.3 });
        const wheel = new THREE.Group();
        g.add(wheel);
        const spoke = new THREE.CylinderGeometry(0.06, 0.06, R, 6);
        for (const s of [-1, 1]) {
          mesh(new THREE.TorusGeometry(R, 0.12, 8, HIGH ? 64 : 32), frame, 0, 0, s * zr, wheel);
          for (let k = 0; k < e.count * 2; k++) {
            const a = (k / (e.count * 2)) * TAU;
            mesh(spoke, frame, (Math.cos(a) * R) / 2, (Math.sin(a) * R) / 2, s * zr, wheel).rotation.z = a - Math.PI / 2;
          }
          if (HIGH) for (let k = 0; k < 16; k++) mesh(new THREE.SphereGeometry(0.11, 8, 6), mat(CONFETTI[k % CONFETTI.length], { glow: 1.6 }), Math.cos((k / 16) * TAU) * R, Math.sin((k / 16) * TAU) * R, s * (zr + 0.1), wheel);
          // pieds en A
          for (const f of [-1, 1]) beam(new THREE.Vector3(0, 0, s * (zr + 0.35)), new THREE.Vector3(f * R * 0.55, -R - 1.5, s * (zr + 0.9)), 0.16, steel, g);
        }
        mesh(new THREE.CylinderGeometry(0.4, 0.4, zr * 2 + 1, 16), mat(0xff4d6d, { rough: 0.3 }), 0, 0, 0, g).rotation.x = Math.PI / 2;
        const cabins = Array.from({ length: e.count }, (_, k) => {
          const c = slab(sx, sy, sz, PASTELS[(i + k) % PASTELS.length], { under: false });
          mesh(new THREE.CylinderGeometry(0.08, 0.08, zr * 2 + 0.1, 8), steel, 0, 0, 0, c).rotation.x = Math.PI / 2;
          ctx.scene.add(c);
          return c;
        });
        anims.push((t) => {
          wheel.rotation.z = TAU * (t / e.period + e.phase);
          ferrisCabins(e, t).forEach((p, k) => place(cabins[k], p));
        });
        return g;
      }
      case 'pistons': {
        // dalles jointives qui montent et descendent sur leur vérin ; socle fixe dessous
        const g = put(new THREE.Group()), w = sx / e.count;
        mesh(rbox(sx + 0.2, 0.3, sz + 0.2, 0.1), mat(0x3d4450, { metal: 0.4, rough: 0.4 }), 0, -sy / 2 - 0.2, 0, g);
        const rodGeo = new THREE.CylinderGeometry(Math.min(w, sz) * 0.14, Math.min(w, sz) * 0.14, 1, 12).translate(0, -0.5, 0);
        const slabs = Array.from({ length: e.count }, (_, k) => {
          const s = new THREE.Group();
          mesh(rbox(w - 0.06, sy, sz, 0.15), mat(shade(k % 2 ? 0xffc971 : 0xff8c42, 0.8)), 0, 0, 0, s);
          mesh(rbox(w + 0.02, Math.min(0.24, sy * 0.4), sz + 0.08, 0.1), mat(0xffffff, { map: tex.soft(k % 2 ? '#ffd166' : '#ff9f5a', '#fff3e0', 1, 1) }), 0, sy / 2 - Math.min(0.12, sy * 0.2), 0, s);
          const rod = mesh(rodGeo, mat(0xbfc7d1, { metal: 0.8, rough: 0.2 }), 0, -sy / 2, 0, s);
          ctx.scene.add(s);
          return { s, rod };
        });
        anims.push((t) => pistonSlabs(e, t).forEach((p, k) => {
          place(slabs[k].s, p);
          slabs[k].rod.scale.y = Math.max(0.01, p.c[1] - e.pos[1] + 0.1);
        }));
        return g;
      }
      case 'wreckingball': {
        // boule de démolition en pendule conique : chaîne du pivot à la boule
        const g = put(new THREE.Group());
        mesh(new THREE.CylinderGeometry(0.7, 0.7, 0.35, 20), mat(0x3d4450, { metal: 0.5, rough: 0.35 }), 0, 0.25, 0, g);
        mesh(new THREE.SphereGeometry(0.3, 14, 10), mat(0xffd60a, { metal: 0.3, rough: 0.25 }), 0, 0, 0, g);
        const ball = new THREE.Group();
        const r = sx / 2;
        mesh(new THREE.SphereGeometry(r, HIGH ? 28 : 16, HIGH ? 20 : 12), mat(0x2b2f38, { metal: 0.7, rough: 0.28 }), 0, 0, 0, ball);
        mesh(new THREE.TorusGeometry(r * 1.0, r * 0.12, 8, 28), mat(0xff4d6d, { rough: 0.3 }), 0, 0, 0, ball).rotation.x = Math.PI / 2;
        mesh(new THREE.CylinderGeometry(r * 0.25, r * 0.3, r * 0.4, 12), mat(0x5c6470, { metal: 0.6 }), 0, -r * 0.95, 0, ball); // attache côté chaîne (-y une fois orientée)
        const chain = mesh(new THREE.CylinderGeometry(0.07, 0.07, 1, 8), mat(0xbfc7d1, { metal: 0.8, rough: 0.25 }));
        ctx.scene.add(ball, chain);
        anims.push((t) => {
          const p = wreckingBall(e, t);
          ball.position.set(p.c[0], p.c[1], p.c[2]);
          const a = va.set(e.pos[0], e.pos[1], e.pos[2]), d = vd.set(p.c[0], p.c[1], p.c[2]).sub(a), len = d.length();
          chain.position.copy(a).addScaledVector(d, 0.5);
          chain.quaternion.setFromUnitVectors(UP, d.divideScalar(len));
          chain.scale.set(1, len, 1);
          ball.quaternion.copy(chain.quaternion); // la boule pend au bout de sa chaîne
        });
        return g;
      }
      case 'crusher': {
        // étau : deux murs capitonnés qui se rapprochent ; tiges vers des butées fixes à l'extérieur
        const g = put(new THREE.Group()), th = e.thickness, back = Math.max(sx, e.minGap) / 2 + th + 0.5;
        const pad = tex.stripes('#ff4d6d', '#ffffff', 1, Math.max(1, Math.round(sy)));
        const rods: THREE.Mesh[] = [];
        for (const s of [-1, 1]) {
          mesh(rbox(0.4, sy * 0.8, Math.min(sz, 2) * 0.8, 0.1), mat(0x3d4450, { metal: 0.4, rough: 0.4 }), s * (back + 0.2), 0, 0, g);
          const rod = mesh(new THREE.CylinderGeometry(0.16, 0.16, 1, 12), mat(0xbfc7d1, { metal: 0.8, rough: 0.2 }), 0, 0, 0, g);
          rod.rotation.z = Math.PI / 2;
          rods.push(rod);
        }
        const walls = [-1, 1].map((s) => {
          const w = new THREE.Group();
          mesh(rbox(th, sy, sz, 0.15), mat(0x3a86ff, { rough: 0.35 }), 0, 0, 0, w);
          mesh(rbox(0.22, sy * 0.88, sz * 0.88, 0.1), mat(0xffffff, { map: pad, rough: 0.5 }), -s * (th / 2 + 0.06), 0, 0, w);
          ctx.scene.add(w);
          return w;
        });
        anims.push((t) => {
          crusherWalls(e, t).forEach((p, k) => place(walls[k], p));
          const outer = crusherGap(e, t)[0] / 2 + th, len = Math.max(0.01, back - outer);
          rods.forEach((rod, k) => { rod.position.x = (k ? 1 : -1) * (outer + len / 2); rod.scale.y = len; });
        });
        return g;
      }
      case 'blink': {
        // dalle lumineuse : clignote de plus en plus vite avant de disparaître ; silhouette fantôme quand elle est absente
        const g = put(slab(sx, sy, sz, 0x48cae4, { top: 0xffffff, topMap: tex.soft('#90e0ef', '#caf0f8', sx / 3, sz / 3), under: false, glow: 0.15 }));
        const cap = (g.getObjectByName('dessus') as THREE.Mesh).material as THREE.MeshStandardMaterial;
        cap.emissive.set(0x48cae4);
        const ghost = put(mesh(rbox(sx, sy, sz, 0.15), new THREE.MeshBasicMaterial({ color: 0xcaf0f8, transparent: true, opacity: 0.1, depthWrite: false })));
        ghost.userData.noShadow = true;
        anims.push((t) => {
          const s = blinkState(e, t);
          ghost.visible = !s.solid;
          if (!s.solid) {
            g.visible = false;
            (ghost.material as THREE.MeshBasicMaterial).opacity = 0.08 + (s.left < 0.7 ? ((0.7 - s.left) / 0.7) * 0.3 : 0);
            return;
          }
          const warn = s.left < 1.2;
          // alerte : clignotement qui accélère et vire au rouge
          g.visible = !warn || Math.floor(s.left * (s.left < 0.5 ? 14 : 7)) % 2 === 0;
          cap.emissive.set(warn ? 0xff3030 : 0x48cae4);
          cap.emissiveIntensity = warn ? 0.9 : 0.15 + 0.08 * Math.sin(t * 3);
        });
        return g;
      }
      case 'hazard': {
        const g = put(new THREE.Group());
        const m = hazardMaterial(e.style, sx, sz);
        mesh(rbox(sx, sy, sz, 0.12), m.body, 0, 0, 0, g);
        const surf = mesh(new THREE.PlaneGeometry(sx - 0.1, sz - 0.1).rotateX(-Math.PI / 2), m.top, 0, sy / 2 + 0.02, 0, g);
        surf.userData.noShadow = e.style === 'water';
        const sp = e.style === 'water' ? 0.08 : e.style === 'acid' ? 0.05 : 0.025;
        anims.push((t) => {
          m.map.offset.set(t * sp, t * sp * 0.6 + Math.sin(t * 0.5) * 0.02);
          surf.position.y = sy / 2 + 0.05 + Math.sin(t * 1.7) * 0.025; // toujours au-dessus du bac
        });
        emitters.push({ e, n: Math.max(1, Math.min(6, Math.round((sx * sz) / 25))) });
        return g;
      }
      case 'boulder': {
        // boules de pierre qui roulent de pos à pos + delta ; bouche de tunnel au départ, poussière à l'arrivée
        const r = sx / 2, yaw = Math.atan2(e.delta[0], e.delta[2]);
        const g = put(new THREE.Group());
        g.rotation.y = yaw;
        // tuyau d'où sortent les boules (derrière le point de départ, ouvert vers delta)
        const pipe = mesh(new THREE.CylinderGeometry(r * 1.25, r * 1.25, r * 2.2, 20, 1, true), mat(0x5c6470, { metal: 0.5, rough: 0.35, side: THREE.DoubleSide }), 0, 0, -r * 1.1, g);
        pipe.rotation.x = Math.PI / 2;
        mesh(new THREE.TorusGeometry(r * 1.25, Math.max(0.12, r * 0.18), 10, 24), mat(0xffd60a, { rough: 0.3 }), 0, 0, 0, g);
        mesh(new THREE.CircleGeometry(r * 1.25, 20), new THREE.MeshBasicMaterial({ color: 0x1a1020 }), 0, 0, -r * 2.1, g);
        const rock = mat(0xb08968, { map: tex.stone(), rough: 0.85 });
        const n = Math.ceil(e.travel / e.interval) + 1;
        const balls = Array.from({ length: n }, () => {
          const b = new THREE.Group(), inner = mesh(new THREE.IcosahedronGeometry(r, HIGH ? 3 : 2), rock, 0, 0, 0, b);
          ctx.scene.add(b);
          return { b, inner };
        });
        let lastK = 0;
        const end: Vec3 = [e.pos[0] + e.delta[0], e.pos[1] + e.delta[1], e.pos[2] + e.delta[2]];
        anims.push((t) => {
          const bs = boulderBalls(e, t);
          balls.forEach((m, j) => {
            const p = bs[j];
            m.b.visible = !!p;
            if (!p) return;
            place(m.b, p);
            m.inner.rotation.x = p.roll;
          });
          // la plus ancienne vient de disparaître : petit nuage de poussière au bout de la course
          const oldest = bs.length ? bs[bs.length - 1].k : 0;
          if (lastK > 0.85 && oldest < lastK - 0.2) ctx.particles.burst([end[0], end[1], end[2]], HIGH ? 14 : 6, [0xd8c3a5, 0xb08968, 0xffffff], 3, r * 0.35, 0.8, 2);
          lastK = oldest;
        });
        return g;
      }
      case 'fakewall': {
        // identique à une plateforme… sauf qu'elle ne projette pas d'ombre et que son dessus scintille à peine
        const g = put(slab(sx, sy, sz, e.color ? new THREE.Color(e.color).getHex() : PASTELS[i % PASTELS.length], { seed: i }));
        g.traverse((o) => { o.userData.noShadow = true; });
        const cap = (g.getObjectByName('dessus') as THREE.Mesh).material as THREE.MeshStandardMaterial;
        cap.emissive.set(0xffffff);
        anims.push((t) => { cap.emissiveIntensity = 0.025 + 0.025 * Math.sin(t * 2.3 + i); });
        return g;
      }
      case 'deco': {
        const p = decoProp(e.kind, sx, sy, sz, e.color ? new THREE.Color(e.color).getHex() : undefined, i);
        p.obj.position.set(e.pos[0], e.pos[1] - sy / 2, e.pos[2]);
        p.obj.rotation.y = e.yaw;
        ctx.scene.add(p.obj);
        if (p.update) anims.push((t) => p.update!(t, look));
        return p.obj;
      }
      case 'sign': {
        // panneau en bois face à +z local, sur deux pieds plantés dans le sol le plus proche dessous
        const g = put(new THREE.Group());
        g.add(textBoard(e.text, sx, sy));
        const gy = groundUnder(e.pos[0], e.pos[1] - sy / 2, e.pos[2]);
        const foot = gy !== null && e.pos[1] - sy / 2 - gy < 10 ? gy - e.pos[1] : -sy / 2 - 1.2;
        const wood = mat(0x9c6644, { rough: 0.8 });
        for (const s of [-1, 1]) {
          const x = s * Math.max(0.1, sx / 2 - 0.25), y0 = foot, y1 = sy / 2 - 0.1;
          mesh(new THREE.CylinderGeometry(0.07, 0.08, y1 - y0, 8), wood, x, (y0 + y1) / 2, -0.12, g);
        }
        return g;
      }
      case 'fog': {
        // nappe de brume : grosses bouffées douces qui dérivent lentement (le brouillard de la scène s'épaissit quand on y entre)
        const g = put(new THREE.Group());
        const col = hex(e.color, 0xd8dce6);
        const n = Math.max(3, Math.min(HIGH ? 18 : 7, Math.round((sx * sz) / 14)));
        const puffs = Array.from({ length: n }, (_, k) => {
          const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: puffTex(), color: col, transparent: true, opacity: 0.18 + 0.4 * e.density, depthWrite: false }));
          const sc = Math.max(sx, sz) * (0.45 + ((k * 37) % 10) / 25);
          s.scale.set(sc, sc * 0.6, 1);
          s.position.set((((k * 53) % 100) / 100 - 0.5) * sx * 0.8, (((k * 29) % 100) / 100 - 0.5) * sy * 0.7, (((k * 71) % 100) / 100 - 0.5) * sz * 0.8);
          s.userData = { x: s.position.x, z: s.position.z, noShadow: true };
          g.add(s);
          return s;
        });
        anims.push((t) => puffs.forEach((s, k) => { s.position.x = s.userData.x + Math.sin(t * 0.21 + k) * sx * 0.08; s.position.z = s.userData.z + Math.cos(t * 0.17 + k * 2) * sz * 0.08; }));
        return g;
      }
      // —— vague 2 ——
      case 'mud': {
        // boue brune pleine de cloques ; quelques bulles éclatent en surface (émetteurs de onFrame)
        const g = put(slab(sx, sy, sz, 0x7a4a2a, { top: 0xffffff, topMap: mudTex(sx / 3, sz / 3), seed: i }));
        muds.push(e);
        return g;
      }
      case 'jelly': {
        // gélatine translucide avec un cœur plus clair ; tremblote (fort à chaque atterrissage, voir postStep)
        const g = put(new THREE.Group());
        const body = new THREE.Group();
        g.add(body);
        const col = 0x52e0a0;
        const outer = mesh(rbox(sx, sy, sz, Math.min(0.4, sy * 0.45)), new THREE.MeshStandardMaterial({ color: col, roughness: 0.08, transparent: true, opacity: 0.72, emissive: col, emissiveIntensity: 0.15, envMapIntensity: 2 }), 0, 0, 0, body);
        outer.userData.noShadow = true;
        mesh(rbox(sx * 0.7, sy * 0.55, sz * 0.7, 0.2), mat(0xb8ffd8, { glow: 0.3, opacity: 0.6 }), 0, 0, 0, body).userData.noShadow = true;
        if (HIGH) for (let k = 0; k < 6; k++) mesh(new THREE.SphereGeometry(0.08 + (k % 3) * 0.04, 8, 6), mat(0xffffff, { opacity: 0.5 }), (((k * 37) % 10) / 10 - 0.5) * sx * 0.7, (((k * 13) % 10) / 10 - 0.5) * sy * 0.6, (((k * 71) % 10) / 10 - 0.5) * sz * 0.7, body);
        anims.push((t) => {
          const j = jiggle.get(i) ?? 0, w = Math.sin(t * 28) * (0.13 * j) + Math.sin(t * 2.3 + i) * 0.012;
          body.scale.set(1 - w * 0.5, 1 + w, 1 - w * 0.5);
          body.position.y = (sy * w) / 2; // le dessous reste en place
        });
        return g;
      }
      case 'ramp': {
        // dalle cisaillée exacte (rampCorners) ; toboggan = rayures bleues glissantes et rambardes
        const c = rampCorners(e).map((v) => new THREE.Vector3(v[0], v[1], v[2]));
        const color = e.slide ? 0x3a86ff : hex(e.color, PASTELS[i % PASTELS.length]);
        const quads = [[4, 5, 7, 6], [0, 1, 3, 2], [0, 2, 6, 4], [1, 3, 7, 5], [0, 1, 5, 4], [2, 3, 7, 6]];
        const center = c.reduce((a, v) => a.add(v), new THREE.Vector3()).multiplyScalar(1 / 8);
        const pos: number[] = [], uv: number[] = [];
        for (const q of quads) {
          let [a, b, cc, d] = q.map((k) => c[k]);
          const n = new THREE.Vector3().subVectors(b, a).cross(new THREE.Vector3().subVectors(cc, a));
          const fc = new THREE.Vector3().add(a).add(b).add(cc).add(d).multiplyScalar(0.25).sub(center);
          if (n.dot(fc) < 0) [b, d] = [d, b]; // sommets dans l'ordre direct vu de l'extérieur
          const ks = [a, b, cc, a, cc, d];
          for (const v of ks) {
            pos.push(v.x, v.y, v.z);
            const k = c.indexOf(v), ix = k & 1, iz = (k >> 1) & 1, iy = k >> 2;
            uv.push(q === quads[0] || q === quads[1] ? ix * (sx / 2) : (ix + iz) * 0.5, q === quads[0] || q === quads[1] ? iz * (sz / 2) : iy);
          }
        }
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
        geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
        geo.computeVertexNormals();
        geo.addGroup(0, 6, 0);
        geo.addGroup(6, 30, 1);
        const top = e.slide ? mat(0xffffff, { map: tex.stripes('#3a86ff', '#ffffff', 1, 1), rough: 0.12 }) : mat(color, { map: tex.soft(css6(shade(color, 1.15)), css6(color), 1, 1) });
        if (top.map) top.map.repeat.set(e.slide ? 1 : 0.5, e.slide ? 0.5 : 0.5);
        const m = new THREE.Mesh(geo, [top, mat(shade(color, 0.7))]);
        ctx.scene.add(m);
        if (e.slide) {
          const rail = mat(0xffd60a, { rough: 0.3 }), up = new THREE.Vector3(0, 0.3, 0);
          for (const [a, b] of [[4, 6], [5, 7]]) beam(c[a].clone().add(up), c[b].clone().add(up), 0.1, rail, m);
        }
        return m;
      }
      case 'boost': {
        // speed pad : socle sombre bordé de cyan lumineux, chevrons qui filent dans le sens de la poussée
        const g = put(new THREE.Group());
        mesh(rbox(sx, sy, sz, 0.18), mat(0x23272e, { rough: 0.5 }), 0, 0, 0, g);
        mesh(rbox(sx + 0.08, 0.1, sz + 0.08, 0.04), mat(0x5ef2ff, { glow: 1.6 }), 0, sy / 2 - 0.08, 0, g);
        mesh(rbox(sx - 0.3, 0.06, sz - 0.3, 0.03), mat(0x14161b, { rough: 0.8 }), 0, sy / 2 - 0.02, 0, g); // sous les chevrons (topOf + 0.03)
        const bv = boostVel(e), n = Math.hypot(bv[0], bv[1]) || 1, dir: [number, number] = [bv[0] / n, bv[1] / n];
        movingArrows(e, dir, lengthAlong(e, dir) * 0.85, 0x5ef2ff, Math.min(1.6, Math.min(sx, sz) / 2.2), 1.1, e.speed * 0.3);
        return g;
      }
      case 'launcher': {
        // canon à joueurs : fût incliné selon le départ de la trajectoire, cible au point d'arrivée, arc pointillé discret
        const g = new THREE.Group();
        ctx.scene.add(g);
        const arc = launcherArc(e, 32), from = new THREE.Vector3(...arc[0]);
        const tan = new THREE.Vector3(...arc[1]).sub(from).normalize();
        const R = Math.min(sx, sz) / 2;
        const barrel = new THREE.Group();
        barrel.position.copy(from);
        barrel.quaternion.setFromUnitVectors(UP, tan);
        g.add(barrel);
        const L = Math.min(2.2, Math.max(1.2, sy * 0.8));
        mesh(new THREE.CylinderGeometry(R * 0.95, R * 1.05, L, HIGH ? 28 : 16, 1, true), mat(0xe5383b, { rough: 0.3, side: THREE.DoubleSide, map: tex.stripes('#e5383b', '#ff6b6b', 4, 1) }), 0, L / 2, 0, barrel);
        mesh(new THREE.TorusGeometry(R * 0.97, 0.12, 8, HIGH ? 28 : 16), mat(0xffd60a, { metal: 0.4, rough: 0.25 }), 0, L, 0, barrel).rotation.x = Math.PI / 2;
        mesh(new THREE.TorusGeometry(R * 1.08, 0.16, 8, HIGH ? 28 : 16), mat(0x2b2140, { rough: 0.5 }), 0, 0.1, 0, barrel).rotation.x = Math.PI / 2;
        mesh(new THREE.CircleGeometry(R * 0.95, 24).rotateX(-Math.PI / 2), mat(0xffffff, { map: tex.target('#2b2140', '#ffd60a') }), from.x, from.y + 0.04, from.z, g);
        // arc pointillé (une perle lumineuse le parcourt) et cible pulsante à l'arrivée
        const dot = new THREE.SphereGeometry(0.07, 6, 4), dm = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.45 });
        for (let k = 3; k < arc.length - 1; k += HIGH ? 1 : 2) mesh(dot, dm, arc[k][0], arc[k][1], arc[k][2], g).userData.noShadow = true;
        const pearl = mesh(new THREE.SphereGeometry(0.16, 10, 8), mat(0xffd60a, { glow: 2 }), 0, 0, 0, g);
        const target = mesh(new THREE.TorusGeometry(1, 0.12, 8, 32), mat(0xff4d6d, { glow: 1.2 }), e.to[0], e.to[1] + 0.06, e.to[2], g);
        target.rotation.x = Math.PI / 2;
        anims.push((t) => {
          const u = frac(t / 2.2), k = u * (arc.length - 1), a = Math.floor(k), f = k - a, p0 = arc[a], p1 = arc[Math.min(arc.length - 1, a + 1)];
          pearl.position.set(p0[0] + (p1[0] - p0[0]) * f, p0[1] + (p1[1] - p0[1]) * f, p0[2] + (p1[2] - p0[2]) * f);
          target.scale.setScalar(0.8 + 0.25 * Math.sin(t * 4));
        });
        launchers.set(i, from);
        return g;
      }
      case 'jumppad': {
        // trampoline directionnel : socle orange, toile, grosse flèche inclinée dans le sens du tir
        const g = put(new THREE.Group());
        const pad = new THREE.Group();
        g.add(pad);
        const r = Math.min(sx, sz) / 2;
        mesh(rbox(sx, sy, sz, 0.22), mat(0xff8c42), 0, 0, 0, g);
        mesh(new THREE.CylinderGeometry(r * 0.85, r * 0.85, 0.06, 28), mat(0xffffff, { map: tex.target('#ffffff', '#ff8c42') }), 0, sy / 2 + 0.02, 0, pad);
        mesh(new THREE.TorusGeometry(r * 0.88, 0.1, 8, 28), mat(0x2b2140), 0, sy / 2 + 0.04, 0, pad).rotation.x = Math.PI / 2;
        const v = jumppadVel(e), hv = Math.hypot(v[0], v[2]);
        const arrow = new THREE.Group();
        arrow.rotation.order = 'YXZ';
        arrow.rotation.y = Math.atan2(v[0], v[2]) - e.yaw;
        arrow.rotation.x = -Math.min(1.2, Math.atan2(v[1], Math.max(0.01, hv))) * 0.6;
        arrow.position.y = sy / 2 + 0.35;
        pad.add(arrow);
        const al = Math.max(0.8, r * 1.4), aw = Math.max(0.6, r);
        const shape = new THREE.Shape([new THREE.Vector2(-aw * 0.2, -al / 2), new THREE.Vector2(aw * 0.2, -al / 2), new THREE.Vector2(aw * 0.2, 0), new THREE.Vector2(aw / 2, 0), new THREE.Vector2(0, al / 2), new THREE.Vector2(-aw / 2, 0), new THREE.Vector2(-aw * 0.2, 0)]);
        mesh(new THREE.ExtrudeGeometry(shape, { depth: 0.12, bevelEnabled: false }).rotateX(Math.PI / 2), mat(0xffd60a, { glow: 0.6 }), 0, 0, 0, arrow);
        anims.push((t) => {
          const j = jiggle.get(i) ?? 0;
          pad.scale.y = 1 - 0.5 * j * Math.max(0, Math.sin(t * 30));
          arrow.position.y = sy / 2 + 0.35 + Math.abs(Math.sin(t * 3)) * 0.12;
        });
        return g;
      }
      case 'zipline': {
        // poteaux (taille size) sous les deux ancrages, câble, chariot à poulie garé au départ (ou qui suit le joueur local)
        const g = new THREE.Group();
        ctx.scene.add(g);
        const cab = zipCable(e), wood = mat(0x9c6644, { rough: 0.8 }), steel = mat(0x5c6470, { metal: 0.6, rough: 0.3 });
        for (const p of [cab.a, cab.b]) {
          mesh(rbox(Math.max(0.2, sx), sy + 0.4, Math.max(0.2, sz), 0.06), wood, p[0], p[1] - sy / 2 + 0.2, p[2], g);
          mesh(new THREE.SphereGeometry(0.16, 10, 8), mat(0xffd60a, { metal: 0.3, rough: 0.25 }), p[0], p[1] + 0.45, p[2], g);
        }
        beam(new THREE.Vector3(...cab.a), new THREE.Vector3(...cab.b), 0.035, mat(0x2b2140, { metal: 0.5, rough: 0.4 }), g).userData.noShadow = true;
        const trolley = new THREE.Group();
        trolley.rotation.order = 'YXZ';
        trolley.rotation.y = Math.atan2(cab.dir[0], cab.dir[2]);
        trolley.rotation.x = -Math.asin(Math.max(-1, Math.min(1, cab.dir[1])));
        mesh(new THREE.CylinderGeometry(0.16, 0.16, 0.1, 16), mat(0xff4d6d, { rough: 0.3 }), 0, 0.12, 0, trolley).rotation.z = Math.PI / 2;
        mesh(rbox(0.12, 0.34, 0.3, 0.04), steel, 0, -0.06, 0, trolley);
        mesh(new THREE.CylinderGeometry(0.04, 0.04, 0.7, 8), mat(0xffd60a, { rough: 0.3 }), 0, -0.24, 0, trolley).rotation.z = Math.PI / 2;
        g.add(trolley);
        // zone d'accroche : anneau au sol sous le départ du câble
        const ring = mesh(new THREE.TorusGeometry(PHYS.zipGrab * 0.7, 0.06, 8, 28), mat(0x5ef2ff, { glow: 1.4 }), cab.a[0], cab.a[1] - PHYS.zipHang + 0.08, cab.a[2], g);
        ring.rotation.x = Math.PI / 2;
        anims.push((t) => {
          const b = ctx.body, mine = b.zip === i;
          const p = mine ? zipFeet(e, b.zipS) : cab.a;
          trolley.position.set(p[0], p[1] + (mine ? PHYS.zipHang : 0) - 0.02, p[2]);
          ring.scale.setScalar(1 + 0.08 * Math.sin(t * 4));
        });
        zips.push(e);
        return g;
      }
      case 'teleport': {
        // tuyau d'entrée (traversé le long de z local) avec tourbillon, tuyau de sortie en `to` orienté selon exitVel
        const g = put(new THREE.Group());
        const r = Math.max(0.6, Math.min(sx, sy) / 2), swirl = swirlTex();
        const pipe = (parent: THREE.Object3D, len: number) => {
          mesh(new THREE.CylinderGeometry(r, r, len, HIGH ? 28 : 16, 1, true), mat(0x2db84d, { rough: 0.3, side: THREE.DoubleSide }), 0, 0, 0, parent).rotation.x = Math.PI / 2;
          for (const s of [-1, 1]) mesh(new THREE.TorusGeometry(r, 0.16, 10, HIGH ? 28 : 16), mat(0x52d681, { rough: 0.25 }), 0, 0, (s * len) / 2, parent);
          const d = mesh(new THREE.CircleGeometry(r * 0.95, 28), new THREE.MeshBasicMaterial({ map: swirl, transparent: true, opacity: 0.85, side: THREE.DoubleSide, depthWrite: false }), 0, 0, 0, parent);
          d.userData.noShadow = true;
          return d;
        };
        const d1 = pipe(g, Math.max(0.6, sz));
        g.children.forEach((o) => { o.position.y += r - sy / 2; }); // bas du tuyau au niveau des pieds
        const out = new THREE.Group();
        const ev = e.exitVel, hv = Math.hypot(ev[0], ev[2]);
        const len = 1.4;
        if (hv >= Math.abs(ev[1]) * 0.5 || hv + Math.abs(ev[1]) < 0.1) {
          // sortie horizontale : le tuyau est derrière le point d'arrivée, bouche vers exitVel (ou vers le lacet de l'entrée)
          const yaw = hv > 0.1 ? Math.atan2(ev[0], ev[2]) : e.yaw;
          out.rotation.y = yaw;
          out.position.set(e.to[0] - Math.sin(yaw) * (len / 2 + 0.3), e.to[1] + r * 0.98, e.to[2] - Math.cos(yaw) * (len / 2 + 0.3));
        } else {
          // sortie verticale : tuyau dressé sous (ou au-dessus de) l'arrivée
          out.rotation.x = Math.PI / 2;
          out.position.set(e.to[0], e.to[1] + (ev[1] > 0 ? -len / 2 : len / 2 + 2), e.to[2]);
        }
        const d2 = pipe(out, len);
        ctx.scene.add(out);
        anims.push((t) => { d1.rotation.z = t * 3; d2.rotation.z = -t * 3; });
        return g;
      }
      case 'bubble': {
        // bulles de savon qui montent, tremblent avant d'éclater (left) et éclatent en haut ; machine à bulles en bas
        const g = put(new THREE.Group());
        mesh(new THREE.CylinderGeometry(sx * 0.5, sx * 0.6, 0.4, 20), mat(0x9d4edd, { rough: 0.35 }), 0, -sy / 2 - 0.3, 0, g);
        mesh(new THREE.TorusGeometry(sx * 0.5, 0.08, 8, 24), mat(0xffd60a, { rough: 0.3 }), 0, -sy / 2 - 0.1, 0, g).rotation.x = Math.PI / 2;
        const hy = Math.max(sy / 2, Math.min(sx, sz) * 0.22);
        const bm = new THREE.MeshStandardMaterial({ color: 0xc9f2ff, roughness: 0.05, metalness: 0.2, transparent: true, opacity: 0.45, emissive: 0x9d4edd, emissiveIntensity: 0.12, envMapIntensity: 3, depthWrite: false });
        const bubbles = Array.from({ length: e.count }, () => {
          const b = new THREE.Group();
          const s = mesh(new THREE.SphereGeometry(1, HIGH ? 24 : 14, HIGH ? 16 : 10), bm, 0, 0, 0, b);
          s.scale.set(sx / 2, hy, sz / 2);
          s.userData.noShadow = true;
          mesh(new THREE.SphereGeometry(0.12, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffffff }), -sx * 0.2, hy * 0.55, -sz * 0.15, b);
          ctx.scene.add(b);
          return b;
        });
        const prevU: number[] = [];
        anims.push((t) => bubbleParts(e, t).forEach((p, k) => {
          const b = bubbles[k];
          // le dessus de la bulle visible = le dessus de la boîte de collision
          b.position.set(p.c[0], p.c[1] + sy / 2 - hy, p.c[2]);
          const grow = Math.min(1, p.u / 0.06), shake = p.left < 0.6 ? Math.sin(t * 60 + k) * 0.06 * (1 - p.left / 0.6) : 0;
          b.scale.set(grow * (1 + shake), grow * (1 - shake), grow * (1 + shake));
          if (prevU[k] !== undefined && p.u < prevU[k] - 0.5) {
            const top: Vec3 = [p.c[0], e.pos[1] + e.rise + sy / 2, p.c[2]];
            ctx.particles.burst(top, HIGH ? 16 : 7, [0xffffff, 0xc9f2ff, 0xff8fab], 4, 0.09, 0.5, 6);
            const me = ctx.body.p;
            if (Math.hypot(me[0] - top[0], me[1] - top[1], me[2] - top[2]) < 20) ctx.sfx.pop();
          }
          prevU[k] = p.u;
        }));
        return g;
      }
      case 'lowgrav': {
        // zone lunaire : volume violet à peine teinté, étoiles qui flottent lentement vers le haut
        const g = put(new THREE.Group());
        const box = mesh(new THREE.BoxGeometry(sx, sy, sz), new THREE.MeshBasicMaterial({ color: 0x9d4edd, transparent: true, opacity: 0.06, depthWrite: false }), 0, 0, 0, g);
        box.userData.noShadow = true;
        const n = Math.round(Math.min(HIGH ? 140 : 50, Math.max(20, (sx * sy * sz) / 12)));
        const base = new Float32Array(n * 3), arr = new Float32Array(n * 3);
        for (let k = 0; k < n; k++) base.set([(Math.random() - 0.5) * sx, Math.random(), (Math.random() - 0.5) * sz], k * 3);
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.BufferAttribute(arr, 3));
        const pts = new THREE.Points(geo, new THREE.PointsMaterial({ map: starTex(), color: 0xe9d5ff, size: 0.45, transparent: true, depthWrite: false, opacity: 0.9 }));
        pts.frustumCulled = false;
        g.add(pts);
        anims.push((t) => {
          for (let k = 0; k < n; k++) {
            arr[k * 3] = base[k * 3] + Math.sin(t * 0.5 + k) * 0.2;
            arr[k * 3 + 1] = (frac(base[k * 3 + 1] + t * 0.04 + (k % 5) * 0.003) - 0.5) * sy;
            arr[k * 3 + 2] = base[k * 3 + 2] + Math.cos(t * 0.4 + k * 1.7) * 0.2;
          }
          geo.attributes.position.needsUpdate = true;
        });
        return g;
      }
      case 'wind': {
        // rafales : traits d'air qui filent dans le sens de `force`, plus nombreux et rapides au plus fort de windGust
        const g = new THREE.Group();
        ctx.scene.add(g);
        const f = new THREE.Vector3(...e.force), fl = f.length() || 1, dir = f.clone().divideScalar(fl);
        const span = Math.abs(dir.x) * sx + Math.abs(dir.y) * sy + Math.abs(dir.z) * sz || sx; // longueur de la zone le long du vent (approchée)
        const n = HIGH ? 18 : 8;
        const sm = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.5, depthWrite: false });
        const leafM = mat(0x70e000, { rough: 0.6, side: THREE.DoubleSide });
        const streaks = Array.from({ length: n }, (_, k) => {
          const leaf = k % 4 === 3;
          const m = leaf ? mesh(new THREE.CircleGeometry(0.12, 5), leafM) : mesh(new THREE.BoxGeometry(0.035, 0.035, 1.4), sm);
          m.userData.noShadow = true;
          m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), dir);
          g.add(m);
          // position latérale fixe (repère local de la zone), phase propre
          return { m, leaf, lx: (((k * 37) % 100) / 100 - 0.5) * sx * 0.9, ly: (((k * 61) % 100) / 100 - 0.5) * sy * 0.8, lz: (((k * 23) % 100) / 100 - 0.5) * sz * 0.9, ph: ((k * 53) % 100) / 100 };
        });
        const cos = Math.cos(e.yaw), sin = Math.sin(e.yaw);
        anims.push((t) => {
          const k = windGust(e, t);
          sm.opacity = 0.12 + 0.5 * k;
          for (const s of streaks) {
            // avance le long du vent depuis un point de la zone (boucle), en restant dans la zone
            const u = frac(s.ph + t * (0.25 + 0.5 * k)) - 0.5;
            const wx = e.pos[0] + s.lx * cos + s.lz * sin, wz = e.pos[2] - s.lx * sin + s.lz * cos;
            s.m.position.set(wx + dir.x * u * span, e.pos[1] + s.ly + dir.y * u * span, wz + dir.z * u * span);
            const o = inZone(e, [s.m.position.x, s.m.position.y, s.m.position.z]);
            s.m.visible = o && (s.leaf || k > 0.08);
            if (s.leaf) s.m.rotation.z = t * 8 + s.ph * 10;
            else s.m.scale.z = 0.4 + 1.2 * k;
          }
        });
        return g;
      }
      // —— vague 3 ——
      case 'button': {
        // gros bouton à la couleur de son lien ; s'enfonce et s'allume tant que le lien est ouvert
        const g = put(new THREE.Group()), col = linkColor(e.link), r = Math.min(sx, sz) / 2;
        mesh(new THREE.CylinderGeometry(r * 1.05, r * 1.15, sy * 0.6, 24), mat(0x3d4450, { metal: 0.4, rough: 0.4 }), 0, -sy * 0.2, 0, g);
        const capM = mat(col, { rough: 0.25 });
        const cap = mesh(new THREE.CylinderGeometry(r * 0.78, r * 0.82, sy, 24), capM, 0, 0.02, 0, g);
        capM.emissive.set(col);
        anims.push((t) => {
          const on = linkOpen(st, e.link, t);
          cap.position.y += ((on ? -sy * 0.55 : 0.02) - cap.position.y) * 0.3;
          capM.emissiveIntensity = on ? 1.2 : 0.1 + 0.1 * Math.sin(t * 4);
        });
        return g;
      }
      case 'door': {
        // porte rayée à la couleur du lien, avec un cadenas ; s'escamote dans le sol (doorOpenness)
        const g = put(new THREE.Group()), col = linkColor(e.link);
        const wall = new THREE.Group();
        g.add(wall);
        mesh(rbox(sx, sy, sz, 0.12), mat(0xffffff, { map: tex.stripes(css6(hex(e.color, col)), '#ffffff', Math.max(1, Math.round(sx / 2)), Math.max(1, Math.round(sy / 2))), rough: 0.35 }), 0, 0, 0, wall);
        for (const s of [-1, 1]) {
          const lock = mesh(new THREE.CylinderGeometry(0.35, 0.35, 0.08, 20), mat(col, { metal: 0.4, rough: 0.25, glow: 0.3 }), 0, 0, s * (sz / 2 + 0.03), wall);
          lock.rotation.x = Math.PI / 2;
          mesh(new THREE.TorusGeometry(0.18, 0.06, 8, 16, Math.PI), mat(0xd9dee5, { metal: 0.8, rough: 0.2 }), 0, 0.3, s * (sz / 2 + 0.03), wall);
        }
        // cadre fixe : deux montants et un linteau
        const frame = mat(0x5c6470, { metal: 0.5, rough: 0.35 });
        for (const s of [-1, 1]) mesh(rbox(0.3, sy + 0.3, sz + 0.2, 0.08), frame, s * (sx / 2 + 0.15), 0.15, 0, g);
        mesh(rbox(sx + 0.6, 0.3, sz + 0.2, 0.08), frame, 0, sy / 2 + 0.15, 0, g);
        anims.push((t) => {
          const o = doorOpenness(e, st, t);
          wall.visible = o < 0.999;
          wall.scale.y = Math.max(0.001, 1 - o);
          wall.position.y = (-sy * o) / 2; // rentre dans le sol
        });
        return g;
      }
      case 'lever': {
        // levier sur un socle : bascule quand il est actionné (leverDown), poignée à la couleur du lien
        const g = put(new THREE.Group()), col = linkColor(e.link);
        mesh(rbox(sx * 0.7, 0.3, sz * 0.5, 0.08), mat(0x3d4450, { metal: 0.4, rough: 0.4 }), 0, -sy / 2 + 0.15, 0, g);
        const arm = new THREE.Group();
        arm.position.y = -sy / 2 + 0.3;
        g.add(arm);
        const L = Math.max(0.6, sy * 0.6);
        mesh(new THREE.CylinderGeometry(0.06, 0.06, L, 8), mat(0xbfc7d1, { metal: 0.8, rough: 0.2 }), 0, L / 2, 0, arm);
        const knob = mat(col, { rough: 0.25 });
        knob.emissive.set(col);
        mesh(new THREE.SphereGeometry(0.17, 14, 10), knob, 0, L, 0, arm);
        let a = -0.7;
        anims.push((t) => {
          const down = leverDown(e, i, st, t);
          a += ((down ? 0.7 : -0.7) - a) * 0.2;
          arm.rotation.x = a;
          knob.emissiveIntensity = down ? 1 : 0.15 + 0.15 * Math.sin(t * 5);
        });
        return g;
      }
      case 'trapdoor': {
        // trappe : deux battants à charnières sur les bords ±x, qui basculent vers le bas (doorOpenness)
        const g = put(new THREE.Group()), col = hex(e.color, linkColor(e.link));
        const frame = mat(0x5c6470, { metal: 0.5, rough: 0.35 });
        for (const s of [-1, 1]) {
          mesh(rbox(0.2, sy, sz + 0.2, 0.06), frame, s * (sx / 2 + 0.1), 0, 0, g);
          mesh(rbox(sx + 0.4, sy, 0.2, 0.06), frame, 0, 0, s * (sz / 2 + 0.1), g);
        }
        const flaps = [-1, 1].map((s) => {
          const pivot = new THREE.Group();
          pivot.position.set(s * (sx / 2), sy / 2, 0);
          g.add(pivot);
          mesh(rbox(sx / 2 - 0.02, sy, sz, 0.08), mat(0xffffff, { map: tex.planks() }), -s * (sx / 4), -sy / 2, 0, pivot);
          mesh(rbox(0.25, 0.04, sz * 0.8, 0.02), mat(col, { glow: 0.3 }), -s * (sx / 2 - 0.3), 0.01, 0, pivot);
          return { pivot, s };
        });
        anims.push((t) => {
          const o = doorOpenness(e, st, t);
          for (const f of flaps) f.pivot.rotation.z = f.s * o * 1.5; // le bord libre descend
        });
        return g;
      }
      case 'memory': {
        // grille mémoire : dalles « ? » ; les sûres s'allument en vert, les piégées tombent (pour tous) à leur instant
        const g = new THREE.Group();
        ctx.scene.add(g);
        const tiles = memoryTiles(e), q = qTex('#c9a8e8', '#ffffff');
        q.center.set(0.5, 0.5);
        q.rotation = Math.PI; // « ? » à l'endroit vu depuis le départ (-z local)
        const meshes = tiles.map((p) => {
          const side = mat(0x9d7bc4);
          const m = new THREE.Mesh(rbox(p.h[0] * 2, p.h[1] * 2, p.h[2] * 2, 0.1), [side, side, mat(0xffffff, { map: q }), mat(0x6b4f8a), side, side]);
          m.position.set(p.c[0], p.c[1], p.c[2]);
          m.rotation.y = p.yaw;
          g.add(m);
          return m;
        });
        anims.push((t) => tiles.forEach((p, k) => {
          const m = meshes[k], key = memoryKey(i, k), fell = st.tiles.get(key);
          const top = (m.material as THREE.MeshStandardMaterial[])[2];
          if (fell !== undefined && t >= fell) {
            const d = t - fell;
            m.visible = d < 2.5;
            m.position.y = p.c[1] - 0.5 * PHYS.gravity * d * d;
            m.rotation.set(d * 2, p.yaw, d * 1.3);
            top.color.set(0xff4d6d);
          } else if (st.safe.has(key)) {
            top.color.set(0x7be495); top.emissive.set(0x52d681); top.emissiveIntensity = 0.5 + 0.2 * Math.sin(t * 4 + k);
          }
        }));
        return g;
      }
      case 'itembox': {
        // boîte surprise « ? » arc-en-ciel qui tourne et flotte ; absente pendant sa recharge, réapparaît en grossissant
        const g = put(new THREE.Group());
        const box = new THREE.Group();
        g.add(box);
        const m = mat(0xffffff, { map: qTex('#ff8c42', '#ffffff'), glow: 0.25, opacity: 0.92 });
        mesh(rbox(sx, sy, sz, Math.min(sx, sy, sz) * 0.18), m, 0, 0, 0, box);
        const c = new THREE.Color();
        anims.push((t) => {
          const ready = boxReady(i, st, t), until = st.boxes.get(i);
          box.visible = ready;
          const grow = until !== undefined ? Math.min(1, Math.max(0, (t - until) / 0.3)) : 1;
          box.scale.setScalar(Math.max(0.001, grow));
          box.rotation.set(0.35, t * 1.5, 0.2);
          box.position.y = Math.sin(t * 2.5 + i) * 0.15;
          m.color.copy(c.setHSL(frac(t * 0.15 + i * 0.1), 0.9, 0.65));
          m.emissive.copy(m.color);
        });
        return g;
      }
      case 'coin': {
        // pièce dorée à l'étoile qui tourne ; disparaît pour soi une fois ramassée (les autres la voient encore)
        const g = put(new THREE.Group());
        const r = Math.min(sx, sy) / 2;
        const face = mat(0xffffff, { map: coinTex(), metal: 0.4, rough: 0.25, glow: 0.2 });
        const coin = new THREE.Mesh(new THREE.CylinderGeometry(r, r, Math.max(0.08, sz * 0.15), 28), [mat(0xffb703, { metal: 0.6, rough: 0.25 }), face, face]);
        coin.rotation.x = Math.PI / 2;
        g.add(coin);
        anims.push((t) => {
          g.visible = !st.coins.has(i);
          g.rotation.y = t * 2.5 + i;
          g.position.y = e.pos[1] + Math.sin(t * 2 + i) * 0.12;
        });
        return g;
      }
    }
  }

  /** Petits effets quand l'état du niveau change (message serveur déjà appliqué à st). */
  function levelFx(m: any): void {
    const at = (i: number): Vec3 => { const e = level.elements[i]; return e ? [e.pos[0], e.pos[1], e.pos[2]] : ctx.body.p; };
    switch (m.t) {
      case 'open': if (near(at(m.by), 30)) ctx.sfx.door(); break;
      case 'lever': if (near(at(m.i))) ctx.sfx.place(); break;
      case 'tile': {
        const e = level.elements[m.i];
        if (e?.type !== 'memory') break;
        const c = memoryTiles(e)[m.k]?.c;
        if (c) { ctx.particles.burst([c[0], c[1] + 0.5, c[2]], HIGH ? 14 : 6, [0xff4d6d, 0xffffff], 4, 0.12, 0.6); if (near(c)) ctx.sfx.crumble(); }
        break;
      }
      case 'safe': if (near(at(m.i))) ctx.sfx.ding(); break;
      case 'box': ctx.particles.burst(at(m.i), HIGH ? 24 : 10, CONFETTI, 5, 0.12, 0.7, 6); break;
      case 'coin': {
        const p = at(m.i);
        if (m.id === ctx.myId) { myCoins = m.n; ctx.sfx.coin(); ctx.particles.burst(p, HIGH ? 18 : 8, [0xffd60a, 0xfff3b0, 0xffffff], 4, 0.1, 0.6, 4); }
        break;
      }
      case 'banana': if (near(m.p)) ctx.sfx.place(); break;
      case 'bananaGone': {
        const o = bananaMeshes.get(m.k);
        if (o && m.by) { ctx.particles.burst([o.position.x, o.position.y + 0.3, o.position.z], 10, [0xffe14a, 0xffffff], 4, 0.1, 0.5); if (near([o.position.x, o.position.y, o.position.z])) ctx.sfx.slip(); }
        break;
      }
    }
  }

  /** Coup de gant de boxe : un gant jaillit devant le joueur id ; étoiles sur les joueurs touchés. */
  function gloveFx(id: string, hit: string[]): void {
    const p = ctx.players.get(id);
    if (!p) return;
    const g = new THREE.Group();
    mesh(new THREE.SphereGeometry(0.45, 16, 12), mat(0xe5383b, { rough: 0.3 }), 0, 0, 0, g).scale.set(1, 0.85, 1.15);
    mesh(new THREE.SphereGeometry(0.2, 10, 8), mat(0xe5383b, { rough: 0.3 }), 0.38, 0.05, 0.05, g);
    mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.3, 14), mat(0xffffff), 0, 0, -0.5, g).rotation.x = Math.PI / 2;
    ctx.scene.add(g);
    const t0 = ctx.now(), yaw = p.yaw, base = p.pos.clone();
    fxs.push({
      until: t0 + 0.45,
      update: (t) => {
        const u = (t - t0) / 0.45, d = 0.6 + Math.sin(Math.min(1, u) * Math.PI) * 2.4;
        g.position.set(base.x + Math.sin(yaw) * d, base.y + 1.1, base.z + Math.cos(yaw) * d);
        g.rotation.y = yaw;
      },
      done: () => g.removeFromParent(),
    });
    for (const h of hit) {
      const q = ctx.players.get(h)?.pos;
      if (q) ctx.particles.burst([q.x, q.y + 1.2, q.z], 14, [0xffd60a, 0xffffff, 0xff4d6d], 6, 0.14, 0.6);
    }
    if (near([base.x, base.y, base.z])) ctx.sfx.hit();
  }

  /** Effet de mort dans le hazard i (lave : flammes et fumée, eau : éclaboussure, acide : bulles) au point p. */
  function hazardFx(i: number, p: Vec3, mine: boolean): void {
    const hz = level.elements[i];
    const style = hz?.type === 'hazard' ? hz.style : 'lava';
    const n = (HIGH ? 1 : 0.5) * (mine ? 1 : 0.6);
    if (style === 'water') {
      ctx.particles.burst(p, 30 * n, [0x7fd8ff, 0xffffff, 0x1f8fe0], 7, 0.16, 0.9, 16, 1.4);
      if (mine || near(p)) ctx.sfx.splash();
    } else if (style === 'acid') {
      for (let k = 0; k < 24 * n; k++) ctx.particles.emit(p[0] + (Math.random() - 0.5) * 1.2, p[1] + Math.random() * 0.6, p[2] + (Math.random() - 0.5) * 1.2, (Math.random() - 0.5) * 0.8, 1 + Math.random() * 2, (Math.random() - 0.5) * 0.8, k % 3 ? 0x8cff3a : 0xe9ff9e, 0.1 + Math.random() * 0.14, 1 + Math.random() * 0.6, -2);
      if (mine || near(p)) ctx.sfx.bubbles();
    } else {
      // gerbe de flammes puis colonne de fumée qui monte
      ctx.particles.burst(p, 26 * n, [0xff9a1f, 0xffe14a, 0xe8430c], 5, 0.22, 0.8, -3, 1.4);
      for (let k = 0; k < 16 * n; k++) ctx.particles.emit(p[0] + (Math.random() - 0.5) * 0.8, p[1] + 0.4 + Math.random() * 0.8, p[2] + (Math.random() - 0.5) * 0.8, (Math.random() - 0.5) * 0.6, 1.5 + Math.random() * 1.5, (Math.random() - 0.5) * 0.6, k % 2 ? 0x4a4a52 : 0x6e6e78, 0.3 + Math.random() * 0.25, 1.6, -1.5);
      if (mine || near(p)) ctx.sfx.sizzle();
    }
    if (mine) ctx.shake(0.35);
  }

  /** Le joueur local est-il assez près pour entendre ? */
  const near = (p: Vec3, r = 25) => Math.hypot(p[0] - ctx.body.p[0], p[1] - ctx.body.p[1], p[2] - ctx.body.p[2]) < r;

  function setRespawn() {
    const e = level.elements[cp < 0 ? level.elements.findIndex((x) => x.type === 'start') : cps[cp]];
    respawn = [e.pos[0] + (Math.random() - 0.5) * 1.2, topOf(e) + 0.2, e.pos[2] + (Math.random() - 0.5) * 1.2];
  }

  function nextTarget(): LevelElement | null {
    if (finished) return null;
    const i = cp + 1 < cps.length ? cps[cp + 1] : level.elements.findIndex((x) => x.type === 'finish');
    return level.elements[i] ?? null;
  }

  return {
    onEnter(c, init: ParkourInit) {
      ctx = c;
      level = init.level;
      cps = init.cps;
      endAt = init.endAt;
      jostleOn = init.jostle !== false;
      killY = levelKillY(level);
      ctx.setSky(level.sky ? new THREE.Color(level.sky).getHex() : 0x8fd3ff);
      level.elements.forEach((e, i) => objs.push(build(e, i)));
      marker = new THREE.Mesh(new THREE.ConeGeometry(0.55, 1.1, 20), mat(0xffd60a, { glow: 1.2 }));
      marker.rotation.x = Math.PI;
      marker.userData.noShadow = true;
      // mer de « slime » sous le parcours, juste au-dessus de l'altitude où l'on réapparaît
      ctx.setSea(killY + 3, 0xff5fb0);
      // ballons décoratifs le long du parcours
      level.elements.forEach((e, i) => {
        if (i % 3 !== 1 || e.type === 'fan' || e.type === 'hammer' || VISUAL_ONLY.has(e.type) || e.type === 'hazard' || e.type === 'ferris' || e.type === 'wreckingball' || e.type === 'boulder' || ZONES.has(e.type) || e.type === 'zipline' || e.type === 'bubble') return;
        const b = balloon(PASTELS[(i * 5) % PASTELS.length]);
        b.position.set(e.pos[0] + (i % 2 ? 1 : -1) * (e.size[0] / 2 + 3 + (i % 4)), e.pos[1] + 2 + (i % 5), e.pos[2] + ((i * 7) % 5) - 2);
        b.userData.y = b.position.y;
        ctx.scene.add(b);
        deco.push(b);
      });
      ctx.scene.add(marker);
      // brouillard : on reprend celui de la scène (rendu à l'identique en sortie) ; voile autour de la caméra pour masquer le ciel
      const sc = ctx.scene.parent as THREE.Scene | null;
      if (level.elements.some((e) => e.type === 'fog') && sc?.fog instanceof THREE.Fog) {
        fog = sc.fog;
        fogBase = { near: fog.near, far: fog.far, color: fog.color };
        fog.color = new THREE.Color().copy(fogBase.color);
        veil = new THREE.Mesh(new THREE.SphereGeometry(1, 24, 12), new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.BackSide, transparent: true, opacity: 0, depthWrite: false, fog: false }));
        veil.userData.noShadow = true;
        veil.visible = false;
        ctx.scene.add(veil);
      }
      setRespawn();
      // caméra tournée vers le premier objectif
      const t = nextTarget(), s = ctx.body.p;
      if (t) ctx.setCamYaw(Math.atan2(t.pos[0] - s[0], t.pos[2] - s[2]));
      top = document.createElement('div');
      top.className = 'top card';
      side = document.createElement('div');
      side.className = 'side card';
      itemEl = document.createElement('div');
      itemEl.className = 'card';
      itemEl.style.cssText = 'position:fixed;left:50%;bottom:58px;transform:translateX(-50%);text-align:center;display:none;';
      ctx.hud.append(top, side, itemEl);
      ctx.toast(level.title || level.name, 2.5);
    },

    colliders: (t) => { frameT = NaN; return frameColliders(t); },

    jostle: (b, op, ov) => parkourJostle({ jostle: jostleOn }, b, op, ov),

    preStep(b: Body, dt: number) {
      // heure serveur : les rafales sont les mêmes pour tous
      const ev = parkourPreStep(level, b, dt, ctx.now());
      if (ev.launched >= 0) {
        const m = launchers.get(ev.launched);
        ctx.sfx.launch();
        ctx.shake(0.7);
        if (m) {
          ctx.particles.burst([m.x, m.y + 0.6, m.z], HIGH ? 24 : 10, [0xffffff, 0xd8dce6, 0x9aa5b1], 4, 0.3, 0.9, -2, 1.2);
          ctx.particles.burst([m.x, m.y + 0.6, m.z], HIGH ? 14 : 6, [0xffd60a, 0xff8c42], 7, 0.14, 0.5, 6, 1.2);
        }
      }
      if (ev.teleported >= 0) {
        const e = level.elements[ev.teleported];
        ctx.sfx.warp();
        for (const p of [e.pos, b.p]) ctx.particles.burst([p[0], p[1] + 0.8, p[2]], HIGH ? 22 : 10, [0xc77dff, 0xffffff, 0x5ef2ff], 5, 0.13, 0.7, 2);
      }
      if (ev.grabbed >= 0) ctx.sfx.zip();
      if (ev.released >= 0) ctx.sfx.unzip();
    },

    pose(_id, _pos, _local, flags) {
      // bits de pose de l'état réseau (poseFlags) : les mêmes pour le joueur local et les autres
      if (flags & FLAG.zip) return { hang: true, grounded: false };
      if (flags & FLAG.flight && !(flags & FLAG.tumble)) return { fly: true };
      return null;
    },

    postStep(b: Body, contacts: Contact[]) {
      const ev = parkourPostStep(b, contacts);
      const now = ctx.now();
      if (ev.knocked) {
        ctx.sfx.hit();
        ctx.shake(0.5);
        ctx.particles.burst([b.p[0], b.p[1] + 0.8, b.p[2]], 12, [0xffffff, 0xffd60a], 6, 0.14, 0.5);
        if (now - lastHit > 0.8) { lastHit = now; ctx.send({ t: 'hit' }); }
      }
      if (ev.bounced) ctx.sfx.boing();
      // gélatine et trampolines directionnels tremblent quand on atterrit dessus
      for (const c of contacts) {
        if (!c.ground) continue;
        const e = level.elements[c.id];
        if (e?.type === 'jelly' && (ev.bounced || b.landed > 3)) jiggle.set(c.id, Math.max(jiggle.get(c.id) ?? 0, ev.bounced ? 1 : 0.5));
        if (e?.type === 'jumppad' && ev.bounced) jiggle.set(c.id, 1);
      }
      if (ev.boosted && now - whooshAt > 0.5) {
        whooshAt = now;
        ctx.sfx.whoosh();
        ctx.particles.burst([b.p[0], b.p[1] + 0.3, b.p[2]], HIGH ? 12 : 5, [0x5ef2ff, 0xffffff], 4, 0.1, 0.4, 4);
      }
      for (const i of ev.crumble) {
        const e = level.elements[i], at = crumbled.get(i);
        if (e.type !== 'crumble' || (at !== undefined && now < at + e.delay + e.respawn)) continue;
        crumbled.set(i, now); // effet immédiat chez soi ; le serveur prévient les autres
        frameT = NaN;
        ctx.send({ t: 'crumble', i });
        ctx.sfx.crumble();
      }
      // lave / eau / acide : comme une chute, avec un effet selon le style ; le serveur le relaie aux autres
      if (ev.killed) {
        hazardFx(ev.hazard, [b.p[0], b.p[1] + 0.3, b.p[2]], true);
        ctx.send({ t: 'killed', i: ev.hazard });
      }
      if (ev.killed || b.p[1] < killY) {
        b.p = [respawn[0], respawn[1], respawn[2]];
        b.v = [0, 0, 0];
        b.tumble = 0;
        clearMotionState(b); // tyrolienne, vol, speed pad…
        ctx.sfx.hurt();
      }
    },

    onMessage(m) {
      if (applyLevelMsg(st, m, ctx.myId)) { frameT = NaN; levelFx(m); }
      else if (m.t === 'effect') {
        applyEffectMsg(ctx.body, m, ctx.myId, ctx.now());
        if (m.kind === 'super') superUntil.set(m.id, m.until);
        const p = ctx.players.get(m.id)?.pos;
        if (p) ctx.particles.burst([p.x, p.y + 1, p.z], HIGH ? 20 : 8, m.kind === 'super' ? [0xffd60a, 0xffffff, 0xff8c42] : [0x5ef2ff, 0xffffff], 4, 0.12, 0.6, 2);
        if (m.id === ctx.myId) ctx.sfx.pickup();
      } else if (m.t === 'item') {
        if (m.id === ctx.myId) {
          held = m.kind;
          if (held) { ctx.sfx.pickup(); ctx.toast(`${ITEM_EMOJI[held]} ${ITEM_NAMES[held]} ! (E ou clic droit)`, 2); }
        }
      } else if (m.t === 'glove') gloveFx(m.id, m.hit);
      else if (m.t === 'killed') {
        if (m.id !== ctx.myId) hazardFx(m.i, [m.p[0], m.p[1] + 0.3, m.p[2]], false);
      } else if (m.t === 'cp') {
        const who = ctx.players.get(m.id);
        if (m.id === ctx.myId && m.k > cp) {
          cp = m.k;
          setRespawn();
          ctx.sfx.checkpoint();
          ctx.toast(`Checkpoint ${m.k + 1}/${cps.length} !`);
          const gate = flags.get(cps[m.k]);
          if (gate) { gate.color.set(who?.info.color ?? 0xffd60a); gate.emissive.copy(gate.color); gate.emissiveIntensity = 1.4; }
        }
      } else if (m.t === 'finish') {
        finishers.push({ id: m.id, time: m.time });
        confettiUntil = ctx.now() + (m.id === ctx.myId ? 3 : 1.5); // les canons de l'arche tirent à chaque arrivée
        if (m.id === ctx.myId) {
          finished = true;
          ctx.sfx.win();
          ctx.toast(m.place === 1 ? '🏁 Premier !' : `🏁 Arrivé ${m.place}e !`, 3);
          ctx.particles.burst([ctx.body.p[0], ctx.body.p[1] + 1, ctx.body.p[2]], 60, [0xff4d6d, 0xffd60a, 0x70e000, 0x00b4d8], 9, 0.18, 1.6, 8);
        }
      } else if (m.t === 'hurry') {
        endAt = m.endAt;
        if (!finished) ctx.toast('Dépêche-toi !', 2);
      }
    },

    onFrame(dt) {
      const t = ctx.now();
      const cs = frameColliders(t);
      byId.length = level.elements.length;
      byId.fill(undefined);
      for (const c of cs) byId[c.id] = c; // plusieurs boîtes : la dernière, comme avant
      level.elements.forEach((e, i) => {
        const o = objs[i];
        if (!o) return;
        const c = byId[i];
        if (e.type === 'crumble') {
          // tremble avant de tomber, puis disparaît jusqu'à sa réapparition
          const at = crumbled.get(i);
          o.visible = !!c;
          const shaking = c && at !== undefined && t > at && t < at + e.delay;
          o.position.set(e.pos[0] + (shaking ? (Math.random() - 0.5) * 0.12 : 0), e.pos[1] - (shaking ? 0.05 : 0), e.pos[2] + (shaking ? (Math.random() - 0.5) * 0.12 : 0));
          return;
        }
        if (!c || !(e.type === 'moving' || e.type === 'spinner' || e.type === 'hammer' || e.type === 'cannon')) return;
        o.position.set(c.c[0], c.c[1], c.c[2]);
        o.rotation.y = c.yaw;
        const arm = arms.get(i);
        if (arm) {
          const a = va.set(e.pos[0], e.pos[1], e.pos[2]), b = vb.set(c.c[0], c.c[1], c.c[2]);
          const d = vd.subVectors(b, a), len = d.length();
          arm.visible = len > 0.05;
          if (arm.visible) {
            arm.position.copy(a).addScaledVector(d, 0.5);
            arm.quaternion.setFromUnitVectors(UP, d.divideScalar(len));
            arm.scale.set(1, len, 1);
            if (e.type === 'hammer') o.quaternion.copy(arm.quaternion); // la tête suit l'inclinaison du bras
          }
        }
      });
      for (const a of arrows) {
        const e = a.el, y = topOf(e) + 0.03, n = a.meshes.length, spacing = a.len / n;
        a.meshes.forEach((m, k) => {
          const u = ((((k + (t * a.speed) / spacing) % n) + n) % n) * spacing - a.len / 2 + spacing / 2;
          m.position.set(e.pos[0] + a.dir[0] * u, y, e.pos[2] + a.dir[1] * u);
        });
      }
      for (const b of blades) b.rotation.y += dt * 14;
      look.set(ctx.body.p[0], ctx.body.p[1] + 1, ctx.body.p[2]);
      for (const [k, j] of jiggle) jiggle.set(k, j * Math.exp(-3.5 * dt));
      // utiliser l'objet tenu : E ou clic droit (le clic qui capture la souris ne compte pas, cf. Input)
      if (held && ctx.input.hit('KeyE', 'Mouse2')) ctx.send({ t: 'use' });
      // bananes posées (st.bananas) : une peau par banane
      for (const [k, p] of st.bananas) {
        if (bananaMeshes.has(k)) continue;
        const b = new THREE.Group();
        mesh(new THREE.TorusGeometry(0.28, 0.08, 8, 16, Math.PI * 0.9), mat(0xffe14a, { rough: 0.4 }), 0, 0, 0, b).rotation.x = -Math.PI / 2;
        for (const a of [-0.6, 0.6, 2.2]) mesh(new THREE.ConeGeometry(0.07, 0.3, 6), mat(0xf5c400, { rough: 0.5 }), Math.cos(a) * 0.3, 0.02, Math.sin(a) * 0.3, b).rotation.set(Math.PI / 2, 0, -a);
        b.position.set(p[0], p[1] + 0.08, p[2]);
        b.rotation.y = k * 1.7;
        ctx.scene.add(b);
        bananaMeshes.set(k, b);
      }
      for (const [k, b] of bananaMeshes) if (!st.bananas.has(k)) { b.removeFromParent(); bananaMeshes.delete(k); }
      // bouclier (bulle), traînée de speed pad et étincelles de super saut, pour tous les joueurs d'après leurs drapeaux
      for (const [id, pl] of ctx.players) {
        const mine = id === ctx.myId, fl = mine ? poseFlags(ctx.body) : pl.flags;
        let sh = shields.get(id);
        if (fl & FLAG.shield && !pl.hidden) {
          if (!sh) {
            sh = mesh(new THREE.SphereGeometry(1.05, HIGH ? 24 : 14, HIGH ? 16 : 10), new THREE.MeshStandardMaterial({ color: 0x5ef2ff, emissive: 0x5ef2ff, emissiveIntensity: 0.5, transparent: true, opacity: 0.28, roughness: 0.1, depthWrite: false }));
            sh.userData.noShadow = true;
            ctx.scene.add(sh);
            shields.set(id, sh);
          }
          sh.visible = true;
          sh.position.set(pl.pos.x, pl.pos.y + 0.9, pl.pos.z);
          sh.scale.setScalar(1 + Math.sin(t * 6) * 0.04);
          // clignote pendant la dernière seconde (connue seulement pour soi)
          (sh.material as THREE.MeshStandardMaterial).opacity = mine && ctx.body.shield < 1 && Math.sin(t * 30) > 0 ? 0.1 : 0.28;
        } else if (sh) sh.visible = false;
        if (!mine && fl & FLAG.boost && Math.random() < (HIGH ? 0.7 : 0.3)) ctx.particles.emit(pl.pos.x, pl.pos.y + 0.3 + Math.random() * 0.9, pl.pos.z, 0, 0.3, 0, Math.random() < 0.5 ? 0x5ef2ff : 0xffffff, 0.09, 0.35, 0);
        if ((superUntil.get(id) ?? 0) > t && Math.random() < (HIGH ? 0.5 : 0.2)) ctx.particles.emit(pl.pos.x + (Math.random() - 0.5) * 0.6, pl.pos.y + 0.1, pl.pos.z + (Math.random() - 0.5) * 0.6, 0, 1.5 + Math.random(), 0, Math.random() < 0.5 ? 0xffd60a : 0xffffff, 0.08, 0.6, 0);
      }
      for (let k = fxs.length - 1; k >= 0; k--) {
        if (t > fxs[k].until) { fxs[k].done(); fxs.splice(k, 1); } else fxs[k].update(t);
      }
      // traînée derrière le joueur lancé par un speed pad
      const me = ctx.body;
      if (me.boost > 0 && Math.random() < (HIGH ? 0.9 : 0.4)) ctx.particles.emit(me.p[0] + (Math.random() - 0.5) * 0.4, me.p[1] + 0.3 + Math.random() * 0.9, me.p[2] + (Math.random() - 0.5) * 0.4, -me.v[0] * 0.15, 0.3, -me.v[2] * 0.15, Math.random() < 0.5 ? 0x5ef2ff : 0xffffff, 0.09, 0.35, 0);
      for (const a of anims) a(t);
      // bulles de lave / d'acide, reflets sur l'eau
      emitTimer -= dt;
      if (emitTimer < 0) {
        emitTimer = HIGH ? 0.12 : 0.3;
        for (const e of muds) {
          if (Math.random() > 0.5) continue;
          const lx = (Math.random() - 0.5) * e.size[0] * 0.85, lz = (Math.random() - 0.5) * e.size[2] * 0.85;
          ctx.particles.emit(e.pos[0] + lx * Math.cos(e.yaw) + lz * Math.sin(e.yaw), topOf(e) + 0.05, e.pos[2] - lx * Math.sin(e.yaw) + lz * Math.cos(e.yaw), 0, 0.6, 0, 0x5a3418, 0.1 + Math.random() * 0.08, 0.45, 2);
        }
        for (const { e, n } of emitters) {
          for (let k = 0; k < n; k++) {
            const lx = (Math.random() - 0.5) * e.size[0] * 0.9, lz = (Math.random() - 0.5) * e.size[2] * 0.9;
            const x = e.pos[0] + lx * Math.cos(e.yaw) + lz * Math.sin(e.yaw), z = e.pos[2] - lx * Math.sin(e.yaw) + lz * Math.cos(e.yaw), y = topOf(e) + 0.05;
            if (e.style === 'lava') ctx.particles.emit(x, y, z, (Math.random() - 0.5) * 0.6, 2 + Math.random() * 2, (Math.random() - 0.5) * 0.6, Math.random() < 0.5 ? 0xffb703 : 0xff5a1f, 0.07 + Math.random() * 0.06, 0.9, 3);
            else if (e.style === 'acid') ctx.particles.emit(x, y, z, 0, 0.5 + Math.random() * 0.6, 0, 0xa6ff4d, 0.08 + Math.random() * 0.1, 0.7, 0);
            else if (Math.random() < 0.4) ctx.particles.emit(x, y, z, 0, 0.3, 0, 0xffffff, 0.06, 0.5, 0);
          }
        }
      }
      // canons à confettis de l'arche d'arrivée
      if (t < confettiUntil) {
        for (const f of confettiFrom) {
          for (let k = 0; k < (HIGH ? 3 : 1); k++) {
            ctx.particles.emit(f.x, f.y, f.z, (Math.random() - 0.5) * 4, 9 + Math.random() * 5, (Math.random() - 0.5) * 4, CONFETTI[Math.floor(Math.random() * CONFETTI.length)], 0.1 + Math.random() * 0.06, 2.6, 5);
          }
        }
      }
      // brouillard : s'épaissit quand la caméra ou le joueur est dans une zone `fog`
      if (fog && fogBase && veil) {
        const cp3 = ctx.camera.position;
        const a = fogAt(level, [cp3.x, cp3.y, cp3.z]), b = fogAt(level, ctx.body.p);
        const f = a && (!b || a.density >= b.density) ? a : b;
        fogK += ((f ? f.density : 0) - fogK) * (1 - Math.exp(-2.5 * dt));
        if (f) fogTarget.set(f.color ?? '#d8dce6');
        fogCol.lerp(fogTarget, 1 - Math.exp(-4 * dt));
        // w : part du brouillard de zone (plein dès density 0.35) ; far : ~66 m à density 0, 21 m à 0.5, 6 m à 1
        const w = Math.min(1, fogK * 3);
        fog.near = fogBase.near * (1 - w);
        fog.far = fogBase.far + (6 + 60 * (1 - fogK) ** 2 - fogBase.far) * w;
        fog.color.copy(fogBase.color).lerp(fogCol, w);
        veil.visible = w > 0.01;
        if (veil.visible) {
          veil.position.copy(cp3);
          veil.scale.setScalar(Math.min(300, fog.far * 0.9));
          const vm = veil.material as THREE.MeshBasicMaterial;
          vm.color.copy(fog.color);
          vm.opacity = w * 0.92;
        }
      }
      deco.forEach((b, i) => { b.position.y = b.userData.y + Math.sin(t * 0.8 + i) * 0.35; });
      fanTimer -= dt;
      if (fanTimer < 0) {
        fanTimer = 0.06;
        for (const e of level.elements) {
          if (e.type !== 'fan') continue;
          ctx.particles.emit(e.pos[0] + (Math.random() - 0.5) * e.size[0] * 0.8, e.pos[1] - e.size[1] / 2 + 0.4, e.pos[2] + (Math.random() - 0.5) * e.size[2] * 0.8,
            e.force[0] * 0.15, e.force[1] * 0.2, e.force[2] * 0.15, 0xffffff, 0.09, 0.9, 0);
        }
      }
      const tgt = nextTarget();
      marker.visible = !!tgt;
      if (tgt) {
        marker.position.set(tgt.pos[0], topOf(tgt) + 3.2 + Math.sin(t * 4) * 0.3, tgt.pos[2]);
        marker.rotation.y = t * 2;
      }
      hudTimer -= dt;
      if (hudTimer < 0) {
        hudTimer = 0.1;
        const left = Math.max(0, endAt - Math.max(t, ctx.startAt));
        top.textContent = `⏱ ${formatTime(left)}  ·  ${finished ? '🏁 Arrivé !' : cps.length ? `Checkpoint ${cp + 1}/${cps.length}` : 'Fonce vers l\'arrivée !'}${hasCoins() ? `  ·  🪙 ${myCoins}` : ''}`;
        // objet tenu, avec sa touche
        itemEl.style.display = held ? 'block' : 'none';
        if (held) itemEl.innerHTML = `<span style="font-size:30px">${ITEM_EMOJI[held]}</span> <b>${ITEM_NAMES[held]}</b><br><span style="font-weight:normal">E ou clic droit</span>`;
        side.innerHTML = `<b>Arrivées</b><br>${finishers.map((f, i) => `${i + 1}. ${esc(ctx.players.get(f.id)?.info.name ?? '?')} — ${formatTime(f.time)}`).join('<br>') || '<span style="font-weight:normal">personne pour l\'instant</span>'}`;
      }
    },

    onExit() {
      // le brouillard appartient à la scène commune : on le rend tel qu'on l'a trouvé
      if (fog && fogBase) { fog.near = fogBase.near; fog.far = fogBase.far; fog.color = fogBase.color; }
      fog = null;
    },
  };
}
