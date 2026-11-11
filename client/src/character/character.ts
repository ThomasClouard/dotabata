// Personnages façon pâte à modeler : corps « haricot » ou boule, gros yeux collés, membres en tube souple
// animés par ressorts (pas de vrai ragdoll), squelette cartoon à l'intérieur et peau qui s'efface autour
// des impacts (shader, aucune géométrie modifiée). Huit modèles, décrits par la table SPECS.
import * as THREE from 'three';

const UP = new THREE.Vector3(0, 1, 0);
const MAX_HITS = 12;
const CENTER = 0.85;

const std = (color: number, roughness = 0.6) => new THREE.MeshStandardMaterial({ color, roughness });
const boneMat = std(0xfffbea, 0.5);
const darkMat = new THREE.MeshBasicMaterial({ color: 0x15151c });
const whiteMat = std(0xffffff, 0.45);
const segGeo = new THREE.CylinderGeometry(1, 1, 1, 12);
const sphGeo = new THREE.SphereGeometry(1, 24, 16);
const boxGeo = new THREE.BoxGeometry(1, 1, 1);

// ---------- modèles ----------

interface Spec {
  y0: number; y1: number;          // bas et haut du corps
  radii: [number, number][];       // [t, rayon] le long du corps (t = 0 en bas, 1 en haut)
  cap: [number, number];           // hauteur des arrondis du bas et du haut
  lean?: (t: number) => number;    // décalage du corps vers l'avant
  eyeT: number; eyeR: number;
  arm: { t: number; r: number; rest: [number, number, number]; reach: number; lift?: number };
  leg: { x: number; r: number; foot: number; stride: number };
  armsWalk?: boolean;              // les mains marchent au sol (personnage en arche)
  acc?: 'casquette' | 'hélice' | 'bouée' | 'bandeau';
  accY?: number;
  accDead?: [number, number, number]; // x, y, roulis de l'accessoire sur le tas d'os
}

const ss = (x: number) => { x = Math.min(1, Math.max(0, x)); return x * x * (3 - 2 * x); };

const SPECS: Record<string, Spec> = {
  haricot: {
    y0: 0.5, y1: 1.62, radii: [[0, 0.21], [0.3, 0.27], [0.55, 0.22], [0.82, 0.25], [1, 0.2]], cap: [0.22, 0.22],
    lean: (t) => 0.1 * (t - 0.5) + 0.06 * Math.sin(Math.PI * t),
    eyeT: 0.8, eyeR: 0.105,
    arm: { t: 0.62, r: 0.07, rest: [0.5, 0.62, 0], reach: 0.8 }, leg: { x: 0.12, r: 0.07, foot: 0.13, stride: 1 },
  },
  casquette: {
    y0: 0.42, y1: 1.5, radii: [[0, 0.3], [1, 0.3]], cap: [0.3, 0.3],
    eyeT: 0.66, eyeR: 0.115,
    arm: { t: 0.5, r: 0.085, rest: [0.52, 0.55, 0], reach: 0.7 }, leg: { x: 0.14, r: 0.085, foot: 0.15, stride: 1 },
    acc: 'casquette', accY: 1.2, accDead: [0.5, 0.12, -1.2],
  },
  spaghetti: {
    y0: 0.56, y1: 1.72, radii: [[0, 0.19], [0.4, 0.21], [1, 0.24]], cap: [0.2, 0.24],
    lean: (t) => 0.05 * Math.sin(Math.PI * t),
    eyeT: 0.84, eyeR: 0.1,
    arm: { t: 0.55, r: 0.06, rest: [0.55, 0.6, 0], reach: 0.9 }, leg: { x: 0.1, r: 0.06, foot: 0.12, stride: 1.15 },
  },
  hélice: {
    y0: 0.3, y1: 1.14, radii: [[0, 0.42], [1, 0.42]], cap: [0.42, 0.42],
    eyeT: 0.68, eyeR: 0.11,
    arm: { t: 0.55, r: 0.1, rest: [0.6, 0.5, 0], reach: 0.5 }, leg: { x: 0.17, r: 0.09, foot: 0.14, stride: 0.8 },
    acc: 'hélice', accY: 0.72, accDead: [0.3, 0.1, -1.2],
  },
  bouée: {
    y0: 0.42, y1: 1.5, radii: [[0, 0.25], [1, 0.27]], cap: [0.25, 0.27],
    eyeT: 0.78, eyeR: 0.1,
    arm: { t: 0.6, r: 0.085, rest: [0.62, 0.98, 0.05], reach: 0.55 }, leg: { x: 0.13, r: 0.085, foot: 0.14, stride: 1 },
    acc: 'bouée', accY: 0.78, accDead: [0, 0.12, 0],
  },
  crochet: {
    y0: 0.5, y1: 1.72, radii: [[0, 0.18], [0.5, 0.17], [0.8, 0.2], [1, 0.2]], cap: [0.18, 0.2],
    lean: (t) => 0.32 * ss((t - 0.45) / 0.55) ** 2,
    eyeT: 0.86, eyeR: 0.1,
    arm: { t: 0.5, r: 0.065, rest: [0.5, 0.55, 0], reach: 0.95 }, leg: { x: 0.1, r: 0.065, foot: 0.12, stride: 1.2 },
  },
  bandeau: {
    y0: 0.3, y1: 1.14, radii: [[0, 0.42], [1, 0.42]], cap: [0.42, 0.42],
    eyeT: 0.62, eyeR: 0.105,
    arm: { t: 0.55, r: 0.1, rest: [0.6, 0.5, 0], reach: 0.5 }, leg: { x: 0.17, r: 0.09, foot: 0.14, stride: 0.8 },
    acc: 'bandeau', accY: 0.72, accDead: [0, -0.15, 0],
  },
  arche: {
    y0: 0.5, y1: 1.08, radii: [[0, 0.28], [1, 0.3]], cap: [0.28, 0.3],
    eyeT: 0.55, eyeR: 0.1,
    arm: { t: 0.75, r: 0.13, rest: [0.62, 0.09, 0.12], reach: 1.15, lift: 0.5 }, leg: { x: 0.13, r: 0.09, foot: 0.13, stride: 0.7 },
    armsWalk: true,
  },
};

function radiusAt(sp: Spec, y: number): number {
  const t = (y - sp.y0) / (sp.y1 - sp.y0);
  if (t <= 0 || t >= 1) return 0;
  let r = sp.radii[sp.radii.length - 1][1];
  for (let i = 1; i < sp.radii.length; i++) {
    const [t0, r0] = sp.radii[i - 1], [t1, r1] = sp.radii[i];
    if (t <= t1) { r = r0 + (r1 - r0) * ss((t - t0) / (t1 - t0)); break; }
  }
  const h = y - sp.y0, g = sp.y1 - y;
  if (h < sp.cap[0]) r *= Math.sqrt(1 - (1 - h / sp.cap[0]) ** 2);
  if (g < sp.cap[1]) r *= Math.sqrt(1 - (1 - g / sp.cap[1]) ** 2);
  return r;
}
const leanAt = (sp: Spec, y: number) => sp.lean?.((y - sp.y0) / (sp.y1 - sp.y0)) ?? 0;

function bodyGeometry(sp: Spec): THREE.BufferGeometry {
  const N = 36, M = 28, pos: number[] = [], idx: number[] = [];
  for (let i = 0; i <= N; i++) {
    const y = sp.y0 + (sp.y1 - sp.y0) * (1 - Math.cos((Math.PI * i) / N)) / 2;
    const r = radiusAt(sp, y), dz = leanAt(sp, y);
    for (let j = 0; j < M; j++) {
      const a = (j / M) * Math.PI * 2;
      pos.push(r * Math.cos(a), y, r * Math.sin(a) + dz);
    }
  }
  for (let i = 0; i < N; i++) for (let j = 0; j < M; j++) {
    const a = i * M + j, b = i * M + ((j + 1) % M), c = a + M, d = b + M;
    idx.push(a, d, b, a, c, d);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

// ---------- membre souple : tube le long d'une courbe, recalculé à chaque image ----------

const T_RINGS = 10, T_CAP = 4, T_SEG = 10;
const tubeIndex = (() => {
  const idx: number[] = [];
  for (let k = 0; k < T_RINGS + T_CAP - 1; k++) for (let j = 0; j < T_SEG; j++) {
    const a = k * T_SEG + j, b = k * T_SEG + ((j + 1) % T_SEG), c = a + T_SEG, d = b + T_SEG;
    idx.push(a, b, d, a, d, c);
  }
  return idx;
})();
const vT = new THREE.Vector3(), vN = new THREE.Vector3(), vB = new THREE.Vector3(), vC = new THREE.Vector3(), vP = new THREE.Vector3();

class Tube {
  readonly mesh: THREE.Mesh;
  private pos: THREE.BufferAttribute;
  private nor: THREE.BufferAttribute;

  constructor(mat: THREE.Material, private r0: number, private r1: number) {
    const n = (T_RINGS + T_CAP) * T_SEG;
    const g = new THREE.BufferGeometry();
    this.pos = new THREE.BufferAttribute(new Float32Array(n * 3), 3);
    this.nor = new THREE.BufferAttribute(new Float32Array(n * 3), 3);
    g.setAttribute('position', this.pos);
    g.setAttribute('normal', this.nor);
    g.setIndex(tubeIndex);
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false;
    this.mesh.castShadow = true;
  }

  /** Courbe de Bézier de `a` à `e` passant par `m` en son milieu, terminée par un bout arrondi. */
  update(a: THREE.Vector3, m: THREE.Vector3, e: THREE.Vector3): void {
    vC.copy(m).multiplyScalar(2).addScaledVector(a, -0.5).addScaledVector(e, -0.5); // point de contrôle
    let v = 0;
    for (let k = 0; k < T_RINGS + T_CAP; k++) {
      const t = Math.min(1, k / (T_RINGS - 1)), u = 1 - t;
      vP.set(0, 0, 0).addScaledVector(a, u * u).addScaledVector(vC, 2 * u * t).addScaledVector(e, t * t);
      vT.set(0, 0, 0).addScaledVector(a, -2 * u).addScaledVector(vC, 2 * u - 2 * t).addScaledVector(e, 2 * t);
      if (vT.lengthSq() < 1e-8) vT.subVectors(e, a);
      if (vT.lengthSq() < 1e-8) vT.set(0, -1, 0);
      vT.normalize();
      // repère transporté le long de la courbe : pas de vrillage
      if (k === 0) vN.set(0, 0, 1).cross(vT).lengthSq() < 0.01 ? vN.set(1, 0, 0).cross(vT) : 0;
      vN.addScaledVector(vT, -vN.dot(vT)).normalize();
      vB.crossVectors(vT, vN);
      let r = this.r0 + (this.r1 - this.r0) * t, tilt = 0;
      if (k >= T_RINGS) { // calotte du bout
        const phi = ((k - T_RINGS + 1) / T_CAP) * Math.PI / 2;
        vP.addScaledVector(vT, this.r1 * Math.sin(phi));
        r = this.r1 * Math.cos(phi);
        tilt = Math.sin(phi);
      }
      const flat = Math.sqrt(1 - tilt * tilt);
      for (let j = 0; j < T_SEG; j++, v++) {
        const ang = (j / T_SEG) * Math.PI * 2, c = Math.cos(ang), s = Math.sin(ang);
        const nx = vN.x * c + vB.x * s, ny = vN.y * c + vB.y * s, nz = vN.z * c + vB.z * s;
        this.pos.setXYZ(v, vP.x + nx * r, vP.y + ny * r, vP.z + nz * r);
        this.nor.setXYZ(v, nx * flat + vT.x * tilt, ny * flat + vT.y * tilt, nz * flat + vT.z * tilt);
      }
    }
    this.pos.needsUpdate = true;
    this.nor.needsUpdate = true;
  }
}

/** Matériau de peau : efface les fragments situés dans les sphères d'impact, avec un liseré foncé au bord. */
function makeSkin(color: number, hits: THREE.Vector4[]): THREE.MeshStandardMaterial {
  const m = new THREE.MeshStandardMaterial({ color, side: THREE.DoubleSide, roughness: 0.58 });
  m.onBeforeCompile = (sh) => {
    sh.uniforms.uHits = { value: hits };
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vWPos;')
      .replace('#include <project_vertex>', '#include <project_vertex>\nvWPos = (modelMatrix * vec4(transformed, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', `#include <common>\nuniform vec4 uHits[${MAX_HITS}];\nvarying vec3 vWPos;`)
      .replace('#include <color_fragment>', `#include <color_fragment>
        float holeEdge = 0.0;
        for (int i = 0; i < ${MAX_HITS}; i++) {
          vec4 h = uHits[i];
          if (h.w > 0.0) {
            vec3 d = vWPos - h.xyz;
            // bord irrégulier, façon trou de dessin animé
            float wob = sin(d.x * 31.0 + d.y * 17.0) * sin(d.y * 29.0 + d.z * 23.0) * sin(d.z * 19.0 + d.x * 13.0);
            float dist = length(d) + wob * 0.045;
            if (dist < h.w) discard;
            if (dist < h.w + 0.04) holeEdge = 1.0;
          }
        }
        if (holeEdge > 0.5) diffuseColor.rgb *= 0.2;
        if (!gl_FrontFacing) diffuseColor.rgb *= 0.3;`);
  };
  m.customProgramCacheKey = () => 'peau-trouee';
  return m;
}

interface Limb {
  leg: boolean;
  side: number;
  anchor: THREE.Vector3;
  anchor0: THREE.Vector3;
  pos: THREE.Vector3;
  vel: THREE.Vector3;
  tube: Tube;
  upper: THREE.Mesh;
  lower: THREE.Mesh;
  joint: THREE.Mesh;
  end: THREE.Mesh;
  foot: THREE.Mesh | null;
  pileAnchor: THREE.Vector3;
  pileEnd: THREE.Vector3;
}

export interface AnimState {
  speed: number; // vitesse horizontale
  vy: number;
  grounded: boolean;
  tumble: boolean;
  charging?: boolean;
  dance?: boolean;
  hang?: boolean; // suspendu (tyrolienne) : bras tendus au-dessus de la tête, jambes ballantes
  fly?: boolean; // propulsé sans contrôle : bras en l'air façon super-héros
}

export class Character {
  readonly root = new THREE.Group();
  private squash = new THREE.Group();
  private pivot = new THREE.Group();
  private content = new THREE.Group();
  private bones = new THREE.Group();
  private hatGroup = new THREE.Group();
  private eyes = new THREE.Group();
  private pupils: THREE.Mesh[] = [];
  private propeller: THREE.Object3D | null = null;
  private skin: THREE.MeshStandardMaterial;
  private skinMeshes: THREE.Object3D[] = [];
  private limbs: Limb[] = [];
  private owned: THREE.BufferGeometry[] = [];
  private hitsWorld: THREE.Vector4[] = [];
  private hits: { p: THREE.Vector3; r: number; cur: number }[] = [];
  private kind = '';
  private sp: Spec = SPECS.haricot;
  private eyeY = 1;
  private shoulderY = 1;
  private pileZ = -0.75;

  private phase = Math.random() * 6;
  private time = Math.random() * 10;
  private spin = 0;
  private sq = 1;
  private sqV = 0;
  private wasGrounded = true;
  private lastVy = 0;
  private lastPos = new THREE.Vector3();
  private lastVel = new THREE.Vector3();
  private first = true;
  private blink = 2 + Math.random() * 3;
  dead = false;
  private deadT = 0;
  private bonesPile = { y: 0, rx: 0, rz: 0 };
  private tmp = new THREE.Vector3();
  private tmp2 = new THREE.Vector3();
  private acc = new THREE.Vector3();

  constructor(color: number, kind: string) {
    for (let i = 0; i < MAX_HITS; i++) this.hitsWorld.push(new THREE.Vector4(0, 0, 0, 0));
    this.skin = makeSkin(color, this.hitsWorld);
    this.root.add(this.squash);
    this.squash.add(this.pivot);
    this.pivot.position.y = CENTER;
    this.pivot.add(this.content);
    this.content.position.y = -CENTER;
    this.setLook(color, kind);
  }

  /** Change la couleur et, si besoin, reconstruit le personnage avec un autre modèle. */
  setLook(color: number, kind: string): void {
    this.skin.color.set(color);
    if (!SPECS[kind]) kind = 'haricot';
    if (kind === this.kind) return;
    this.kind = kind;
    const sp = (this.sp = SPECS[kind]);
    for (const g of this.owned) g.dispose();
    this.owned = [];
    for (const g of [this.content, this.bones, this.eyes, this.hatGroup]) g.clear();
    this.skinMeshes = [];
    this.limbs = [];
    this.pupils = [];
    this.propeller = null;
    this.eyeY = sp.y0 + sp.eyeT * (sp.y1 - sp.y0);
    this.shoulderY = sp.y0 + sp.arm.t * (sp.y1 - sp.y0);

    const body = new THREE.Mesh(this.own(bodyGeometry(sp)), this.skin);
    body.castShadow = true;
    this.content.add(body);
    this.skinMeshes.push(body);
    this.buildSkeleton();
    this.buildEyes();
    this.content.add(this.hatGroup);
    this.hatGroup.position.set(0, sp.accY ?? 0, 0);
    this.hatGroup.rotation.set(0, 0, 0);
    this.buildAccessory();

    const footY = sp.leg.foot * 0.55;
    for (const side of [-1, 1]) {
      const sh = new THREE.Vector3(side * radiusAt(sp, this.shoulderY) * 0.8, this.shoulderY, leanAt(sp, this.shoulderY));
      this.limbs.push(this.makeLimb(false, side, sh, new THREE.Vector3(side * sp.arm.rest[0], sp.arm.rest[1], sp.arm.rest[2])));
      const hip = new THREE.Vector3(side * sp.leg.x, sp.y0 + 0.1, leanAt(sp, sp.y0 + 0.1));
      this.limbs.push(this.makeLimb(true, side, hip, new THREE.Vector3(side * (sp.leg.x + 0.03), footY, 0)));
    }
    if (this.dead) { this.dead = false; this.die(); }
  }

  private own<T extends THREE.BufferGeometry>(g: T): T { this.owned.push(g); return g; }

  private bone(geo: THREE.BufferGeometry, r: number): THREE.Mesh {
    const b = new THREE.Mesh(geo, boneMat);
    if (geo === segGeo) b.scale.set(r, 1, r); else b.scale.setScalar(r);
    this.content.add(b);
    return b;
  }

  private makeLimb(leg: boolean, side: number, anchor: THREE.Vector3, rest: THREE.Vector3): Limb {
    const sp = this.sp, r = leg ? sp.leg.r : sp.arm.r;
    const tube = new Tube(this.skin, r, leg ? r : r * 1.25);
    this.own(tube.mesh.geometry);
    this.content.add(tube.mesh);
    this.skinMeshes.push(tube.mesh);
    let foot: THREE.Mesh | null = null;
    if (leg) { // gros pied rond, un peu allongé vers l'avant
      const f = sp.leg.foot;
      foot = new THREE.Mesh(sphGeo, this.skin);
      foot.scale.set(f * 1.0, f * 0.7, f * 1.5);
      foot.castShadow = true;
      this.content.add(foot);
      this.skinMeshes.push(foot);
    }
    return {
      leg, side, anchor: anchor.clone(), anchor0: anchor.clone(), pos: rest.clone(), vel: new THREE.Vector3(), tube, foot,
      upper: this.bone(segGeo, 0.028), lower: this.bone(segGeo, 0.026), joint: this.bone(sphGeo, 0.042), end: this.bone(sphGeo, 0.055),
      pileAnchor: new THREE.Vector3(), pileEnd: new THREE.Vector3(),
    };
  }

  private buildSkeleton(): void {
    const sp = this.sp;
    const headY = this.eyeY, headZ = leanAt(sp, headY), k = Math.min(1, (radiusAt(sp, headY) * 0.72) / 0.21);
    const skull = new THREE.Group();
    skull.position.set(0, headY, headZ);
    skull.scale.setScalar(k);
    const add = (parent: THREE.Object3D, geo: THREE.BufferGeometry, mat: THREE.Material, x: number, y: number, z: number, sx = 1, sy = sx, sz = sx) => {
      const m = new THREE.Mesh(geo, mat);
      m.position.set(x, y, z);
      m.scale.set(sx, sy, sz);
      parent.add(m);
      return m;
    };
    add(skull, sphGeo, boneMat, 0, 0, 0, 0.21, 0.2, 0.2); // crâne
    add(skull, sphGeo, darkMat, -0.08, 0.03, 0.16, 0.055, 0.065, 0.04); // orbites
    add(skull, sphGeo, darkMat, 0.08, 0.03, 0.16, 0.055, 0.065, 0.04);
    add(skull, sphGeo, darkMat, 0, -0.05, 0.19, 0.02, 0.03, 0.02); // nez
    add(skull, boxGeo, boneMat, 0, -0.17, 0.1, 0.17, 0.07, 0.1); // mâchoire
    for (let i = -2; i <= 2; i++) add(skull, boxGeo, darkMat, i * 0.033, -0.16, 0.152, 0.006, 0.05, 0.004); // dents
    this.bones.add(skull);

    const pelvisY = sp.y0 + 0.1, neckY = headY - 0.2 * k;
    const a = new THREE.Vector3(0, pelvisY, leanAt(sp, pelvisY)), b = new THREE.Vector3(0, neckY, headZ);
    for (let i = 0; i < 5; i++) { // colonne, en tronçons qui suivent la courbure du corps
      const ya = pelvisY + ((neckY - pelvisY) * i) / 5, yb = pelvisY + ((neckY - pelvisY) * (i + 1)) / 5;
      this.seg(add(this.bones, segGeo, boneMat, 0, 0, 0, 0.03, 1, 0.03), a.set(0, ya, leanAt(sp, ya)), b.set(0, yb, leanAt(sp, yb)));
    }
    a.set(0, pelvisY, leanAt(sp, pelvisY));
    const len = neckY - pelvisY, n = len > 0.4 ? 3 : len > 0.15 ? 1 : 0;
    for (let i = 0; i < n; i++) { // côtes
      const y = neckY - 0.08 - (i * len * 0.5) / Math.max(1, n - 1 || 1);
      const r = Math.min(0.2, radiusAt(sp, y) * 0.66);
      const t = add(this.bones, this.own(new THREE.TorusGeometry(r, 0.022, 6, 14)), boneMat, 0, y, leanAt(sp, y));
      t.rotation.x = Math.PI / 2;
    }
    add(this.bones, boxGeo, boneMat, 0, pelvisY, a.z, Math.min(0.3, radiusAt(sp, pelvisY) * 1.2), 0.08, 0.13); // bassin
    this.pileZ = -(headY + pelvisY) / 2;
    this.content.add(this.bones);
  }

  private buildEyes(): void {
    const sp = this.sp, R = sp.eyeR * 1.12, x = R * 0.88;
    const surf = radiusAt(sp, this.eyeY);
    const z = leanAt(sp, this.eyeY) + Math.sqrt(Math.max(0, surf * surf - x * x)) - R * 0.3;
    for (const s of [-1, 1]) {
      const eye = new THREE.Mesh(sphGeo, whiteMat);
      eye.scale.setScalar(R);
      eye.position.set(s * x, this.eyeY, z);
      const pupil = new THREE.Mesh(sphGeo, darkMat);
      pupil.scale.setScalar(0.5);
      pupil.position.set(0, 0, 0.66);
      eye.add(pupil);
      this.pupils.push(pupil);
      this.eyes.add(eye);
    }
    this.content.add(this.eyes);
  }

  private buildAccessory(): void {
    const g = new THREE.Group();
    this.hatGroup.add(g);
    const add = (geo: THREE.BufferGeometry, mat: THREE.Material | number, x = 0, y = 0, z = 0, parent: THREE.Object3D = g) => {
      const m = new THREE.Mesh(this.own(geo), typeof mat === 'number' ? std(mat) : mat);
      m.position.set(x, y, z);
      m.castShadow = true;
      parent.add(m);
      return m;
    };
    const acc = this.sp.acc;
    if (acc === 'casquette') { // casquette jaune portée à l'envers
      const R = 0.315, yellow = std(0xf7b92b);
      g.rotation.x = -0.18;
      add(new THREE.SphereGeometry(R, 28, 12, 0, Math.PI * 2, 0, 1.05), yellow);
      const visor = add(new THREE.CylinderGeometry(0.27, 0.27, 0.04, 24, 1, false, Math.PI / 2, Math.PI), yellow, 0, R * Math.cos(1.05) + 0.015, -0.2);
      visor.scale.z = 1.35;
      visor.rotation.x = -0.12;
      // ouverture de réglage à l'avant : on voit la tête au travers
      const hole = add(new THREE.SphereGeometry(1, 16, 10), this.skin, 0, R * Math.cos(0.72), R * Math.sin(0.72));
      hole.scale.set(0.085, 0.06, 0.02);
      hole.rotation.x = -0.72;
      hole.castShadow = false;
      const strap = add(new THREE.TorusGeometry(0.085, 0.016, 6, 16, Math.PI), std(0xd99a12), 0, R * Math.cos(0.76), R * Math.sin(0.76) + 0.008);
      strap.rotation.x = -0.72;
    } else if (acc === 'hélice') { // bonnet à quartiers rouges et blancs, hélice jaune
      g.rotation.z = -0.32;
      const red = std(0xe8483f), white = std(0xfff6ea), yellow = std(0xffc93c), base = 0.35;
      const wedge = this.own(new THREE.SphereGeometry(0.2, 6, 8, 0, Math.PI / 3, 0, Math.PI / 2));
      for (let i = 0; i < 6; i++) {
        const w = new THREE.Mesh(wedge, i % 2 ? white : red);
        w.position.y = base;
        w.rotation.y = (i * Math.PI) / 3;
        w.castShadow = true;
        g.add(w);
      }
      add(new THREE.CylinderGeometry(0.016, 0.016, 0.1, 8), yellow, 0, base + 0.24);
      const prop = new THREE.Group();
      prop.position.y = base + 0.3;
      g.add(prop);
      add(new THREE.SphereGeometry(0.035, 10, 8), yellow, 0, 0, 0, prop);
      for (const s of [-1, 1]) add(new THREE.SphereGeometry(1, 14, 8), yellow, s * 0.13, 0, 0, prop).scale.set(0.13, 0.014, 0.055);
      this.propeller = prop;
    } else if (acc === 'bouée') { // bouée à rayures orange et blanches
      const arc = this.own(new THREE.TorusGeometry(0.37, 0.125, 14, 6, Math.PI / 4).rotateX(Math.PI / 2));
      const orange = std(0xf58a3c, 0.5), white = std(0xfff6ea, 0.5);
      for (let i = 0; i < 8; i++) {
        const m = new THREE.Mesh(arc, i % 2 ? white : orange);
        m.rotation.y = (i * Math.PI) / 4;
        m.castShadow = true;
        g.add(m);
      }
    } else if (acc === 'bandeau') { // bandeau blanc à liseré rouge
      g.rotation.x = -0.14;
      add(new THREE.SphereGeometry(0.432, 32, 6, 0, Math.PI * 2, 0.5, 0.48), std(0xfff6ea));
      add(new THREE.SphereGeometry(0.438, 32, 3, 0, Math.PI * 2, 0.67, 0.13), std(0xe8483f));
    }
  }

  // ---------- dégâts ----------

  /** Ajoute un trou dans la peau (position locale au personnage). */
  addHit(p: [number, number, number], r: number): void {
    if (this.hits.length >= MAX_HITS) {
      // plus de place : on agrandit un trou existant, les trous finissent par fusionner
      const h = this.hits[Math.floor(Math.random() * this.hits.length)];
      h.r = Math.min(0.6, h.r + r * 0.5);
      return;
    }
    this.hits.push({ p: new THREE.Vector3(p[0], p[1], p[2]), r, cur: 0.02 });
  }

  /** Fait repousser la peau sur les `n` derniers trous. */
  heal(n: number): void {
    for (let i = 0; i < n; i++) {
      const h = [...this.hits].reverse().find((x) => x.r > 0);
      if (h) h.r = 0;
    }
  }

  resetDamage(): void {
    this.hits.length = 0;
    for (const h of this.hitsWorld) h.w = 0;
    if (this.dead) this.revive();
  }

  /** PV à zéro : il ne reste que le squelette, qui s'écroule en tas d'os. */
  die(): void {
    if (this.dead) return;
    this.dead = true;
    this.deadT = 0;
    for (const m of this.skinMeshes) m.visible = false;
    this.eyes.visible = false;
    const rnd = (a: number) => (Math.random() * 2 - 1) * a;
    for (const l of this.limbs) {
      l.pileAnchor.set(rnd(0.3), 0.06 + Math.random() * 0.1, rnd(0.3));
      l.pileEnd.set(l.pileAnchor.x + rnd(0.35), 0.05, l.pileAnchor.z + rnd(0.35));
    }
    this.bonesPile = { y: 0.16, rx: 1.42 + rnd(0.1), rz: rnd(0.5) };
  }

  private revive(): void {
    this.dead = false;
    for (const m of this.skinMeshes) m.visible = true;
    this.eyes.visible = true;
    this.bones.position.set(0, 0, 0);
    this.bones.rotation.set(0, 0, 0);
    this.hatGroup.position.set(0, this.sp.accY ?? 0, 0);
    this.hatGroup.rotation.set(0, 0, 0);
    for (const l of this.limbs) l.anchor.copy(l.anchor0);
  }

  // ---------- animation ----------

  private seg(g: THREE.Object3D, a: THREE.Vector3, b: THREE.Vector3): void {
    const d = this.tmp.subVectors(b, a);
    const len = Math.max(0.001, d.length());
    g.position.addVectors(a, b).multiplyScalar(0.5);
    g.quaternion.setFromUnitVectors(UP, d.divideScalar(len));
    g.scale.y = len;
  }

  update(dt: number, st: AnimState): void {
    dt = Math.min(dt, 0.05);
    this.time += dt;
    const yaw = this.root.rotation.y, sp = this.sp;

    // accélération du corps dans son repère local → inertie des bras et des pupilles
    const wp = this.root.position;
    if (this.first) { this.lastPos.copy(wp); this.first = false; }
    const vel = this.tmp2.subVectors(wp, this.lastPos).divideScalar(Math.max(dt, 1e-3));
    if (vel.lengthSq() > 3600) vel.set(0, 0, 0); // téléportation
    this.acc.subVectors(vel, this.lastVel).divideScalar(Math.max(dt, 1e-3)).clampLength(0, 70);
    this.lastVel.copy(vel);
    this.lastPos.copy(wp);
    const cos = Math.cos(yaw), sin = Math.sin(yaw);
    const ax = this.acc.x * cos - this.acc.z * sin, az = this.acc.x * sin + this.acc.z * cos, ay = this.acc.y;

    const k = Math.min(1, st.speed / 5.5);
    if (st.grounded) this.phase += st.speed * dt * 1.9;
    else this.phase += dt * 9;
    const ph = this.phase;

    // étirement / écrasement
    if (st.grounded && !this.wasGrounded) this.sqV -= Math.min(5, 1.5 + Math.abs(this.lastVy) * 0.3);
    if (!st.grounded && this.wasGrounded && st.vy > 1) this.sqV += 3.5;
    this.wasGrounded = st.grounded;
    this.lastVy = st.vy;
    this.sqV += ((1 - this.sq) * 220 - this.sqV * 13) * dt;
    this.sq = THREE.MathUtils.clamp(this.sq + this.sqV * dt, 0.55, 1.5);
    const stretch = this.dead ? 1 : this.sq + (st.grounded ? 0 : THREE.MathUtils.clamp(Math.abs(st.vy) * 0.012, 0, 0.18));
    this.squash.scale.set(1 / Math.sqrt(stretch), stretch, 1 / Math.sqrt(stretch));

    // roulé-boulé
    if (st.tumble && !this.dead) this.spin += dt * 13;
    else {
      this.spin = Math.atan2(Math.sin(this.spin), Math.cos(this.spin));
      this.spin *= Math.exp(-10 * dt);
    }

    if (this.dead) {
      this.updateDead(dt);
    } else {
      const dance = st.dance ? 1 : 0;
      const bob = st.grounded ? Math.abs(Math.sin(ph)) * 0.07 * k : 0;
      this.pivot.position.y = CENTER + bob + dance * Math.abs(Math.sin(this.time * 7)) * 0.12;
      this.pivot.rotation.set(k * 0.2 + this.spin, 0, Math.sin(ph) * 0.14 * k + dance * Math.sin(this.time * 7) * 0.2);
      this.hatGroup.rotation.x = Math.sin(ph * 2) * 0.06 * k - THREE.MathUtils.clamp(az * 0.003, -0.2, 0.2);
      this.hatGroup.rotation.z = THREE.MathUtils.clamp(ax * 0.003, -0.2, 0.2);

      const lx = sp.leg.x + 0.03, fy = sp.leg.foot * 0.55, sd = sp.leg.stride, sy = this.shoulderY, [rx, ry, rz] = sp.arm.rest;
      for (const l of this.limbs) {
        const s = l.side, lp = ph + (s > 0 ? 0 : Math.PI);
        const target = this.tmp;
        if (l.leg) {
          if (st.tumble) target.set(s * 0.3, 0.3 + Math.sin(this.time * 15 + s) * 0.2, Math.cos(this.time * 13 + s) * 0.3);
          else if (st.hang) target.set(s * lx, fy - 0.02 + Math.sin(this.time * 6 + s) * 0.05, 0.12 + Math.sin(this.time * 5 + s * 1.3) * 0.12);
          else if (st.grounded) target.set(s * lx, fy + Math.max(0, Math.sin(lp)) * 0.32 * k * sd + dance * Math.max(0, Math.sin(this.time * 7 + s)) * 0.2, -Math.cos(lp) * 0.44 * k * sd);
          else target.set(s * (lx + 0.05), fy + 0.13 + Math.sin(this.time * 13 + s * 2) * 0.09, -0.1 + s * 0.14 * Math.sin(this.time * 9));
          l.pos.lerp(target, 1 - Math.exp(-28 * dt));
        } else {
          if (st.tumble) target.set(s * 0.7 * Math.cos(this.time * 17 + s), sy + 0.5 * Math.sin(this.time * 13), 0.5 * Math.sin(this.time * 11 + s));
          else if (st.hang) target.set(s * 0.16, sy + 2, 0); // borné à la portée du bras : main tendue vers le câble
          else if (st.fly) target.set(s * 0.3, sy + 0.9, 0.25);
          else if (dance) target.set(s * 0.55, sy + 0.5 + Math.sin(this.time * 7 + s * 1.5) * 0.25, 0.1);
          else if (st.charging) target.set(s * 0.2, sy - 0.05, 0.5);
          else if (!st.grounded && st.vy < -3) target.set(s * 0.62, sy + 0.5, 0); // bras en l'air en tombant
          else if (!st.grounded) target.set(s * 0.72, sy - 0.05, 0);
          else if (sp.armsWalk) target.set(s * rx, ry + Math.max(0, -Math.sin(lp)) * 0.25 * k, rz + Math.cos(lp) * 0.4 * k); // mains qui marchent
          else target.set(s * rx, ry, rz + Math.cos(lp) * 0.34 * k);
          // ressort sous-amorti : les bras traînent et rebondissent avec l'inertie
          const a = target.sub(l.pos).multiplyScalar(110);
          a.x -= l.vel.x * 8 + ax * 0.55; a.y -= l.vel.y * 8 + ay * 0.3; a.z -= l.vel.z * 8 + az * 0.55;
          l.vel.addScaledVector(a, dt);
          l.pos.addScaledVector(l.vel, dt);
          const d = this.tmp.subVectors(l.pos, l.anchor);
          if (d.length() > sp.arm.reach) l.pos.copy(l.anchor).addScaledVector(d.normalize(), sp.arm.reach);
        }
      }

      // yeux : clignement, pupilles qui ballottent, tournis pendant le roulé-boulé
      this.blink -= dt;
      if (this.blink < -0.12) this.blink = 1.5 + Math.random() * 4;
      this.eyes.scale.y = this.blink < 0 ? 0.15 : 1;
      this.eyes.position.y = this.blink < 0 ? this.eyeY * 0.85 : 0;
      this.pupils.forEach((p, i) => {
        if (st.tumble) p.position.set(Math.cos(this.time * 20 + i * 2) * 0.4, Math.sin(this.time * 20 + i * 2) * 0.4, 0.55);
        else p.position.set(THREE.MathUtils.clamp(-ax * 0.008, -0.35, 0.35) + 0.1 + Math.sin(this.time * 0.7) * 0.1, 0.08 + THREE.MathUtils.clamp(-ay * 0.006, -0.35, 0.35), 0.66);
      });
    }
    if (this.propeller) this.propeller.rotation.y += dt * (6 + st.speed * 4);

    // pose des membres : tube de peau courbe, et deux os + articulation à l'intérieur
    for (const l of this.limbs) {
      const mid = this.tmp2.addVectors(l.anchor, l.pos).multiplyScalar(0.5);
      if (!this.dead) {
        if (l.leg) mid.z += 0.12;
        else { mid.x += l.side * 0.13; mid.y += sp.arm.lift ?? 0.05; mid.z -= 0.04; }
        l.tube.update(l.anchor, mid, l.pos);
        if (l.foot) l.foot.position.set(l.pos.x, l.pos.y, l.pos.z + sp.leg.foot * 0.3);
      }
      l.joint.position.copy(mid);
      l.end.position.copy(l.pos);
      this.seg(l.upper, l.anchor, l.joint.position);
      this.seg(l.lower, l.joint.position, l.pos);
    }

    // sphères d'impact en coordonnées monde pour le shader
    if (this.hits.length) this.root.updateMatrixWorld(true);
    for (let i = 0; i < MAX_HITS; i++) {
      const h = this.hits[i], u = this.hitsWorld[i];
      if (!h) { u.w = 0; continue; }
      h.cur += (h.r - h.cur) * Math.min(1, dt * 9);
      const w = this.content.localToWorld(this.tmp.copy(h.p));
      u.set(w.x, w.y, w.z, h.cur < 0.015 ? 0 : h.cur);
    }
    if (this.hits.length) this.hits = this.hits.filter((h) => h.r > 0 || h.cur > 0.02);
  }

  private updateDead(dt: number): void {
    this.deadT += dt;
    const t = Math.min(1, this.deadT / 0.45);
    const e = 1 - Math.exp(-9 * dt);
    this.pivot.position.y = CENTER;
    this.pivot.rotation.set(this.spin, 0, 0);
    // le crâne et les côtes basculent à plat, recentrés sur le tas
    this.bones.position.y += (this.bonesPile.y - this.bones.position.y) * e;
    this.bones.position.z += (this.pileZ - this.bones.position.z) * e;
    this.bones.rotation.x += (this.bonesPile.rx - this.bones.rotation.x) * e;
    this.bones.rotation.z += (this.bonesPile.rz - this.bones.rotation.z) * e;
    const [hx, hy, hr] = this.sp.accDead ?? [0, 0, 0];
    this.hatGroup.position.y += (hy - this.hatGroup.position.y) * e;
    this.hatGroup.position.x += (hx - this.hatGroup.position.x) * e;
    this.hatGroup.rotation.x *= 1 - e;
    this.hatGroup.rotation.z += (hr - this.hatGroup.rotation.z) * e;
    for (const l of this.limbs) {
      l.anchor.lerp(l.pileAnchor, e);
      l.pos.lerp(l.pileEnd, e);
      // petit rebond des os en touchant le sol
      l.pos.y += Math.abs(Math.sin(t * Math.PI * 2)) * (1 - t) * 0.1;
    }
  }

  dispose(): void {
    this.root.removeFromParent();
    this.skin.dispose();
    for (const g of this.owned) g.dispose();
  }
}
