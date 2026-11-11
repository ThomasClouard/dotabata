// Accessoires procéduraux du décor (parcours) : éléments de décor animés, panneaux à texte, arches gonflables, surfaces de lave/eau/acide.
// Même style que gfx.ts : formes arrondies, couleurs franches, aucun fichier à charger.
import * as THREE from 'three';
import { HIGH, balloon, canvasTex, mat, mesh, rbox, shade, sign, tex, tree } from './gfx';

/** Accessoire animé : `update(t, look)` reçoit l'horloge et le point que regardent les spectateurs (le joueur local). */
export interface Prop { obj: THREE.Group; update?: (t: number, look: THREE.Vector3) => void }

const VIVID = [0xff4d6d, 0xffd60a, 0x00b4d8, 0x70e000, 0x9d4edd, 0xff8c42, 0xf72585, 0x3a86ff];
const SKIN = [0xffd7b5, 0xf1c27d, 0xc68642, 0x8d5524, 0xffe0bd];
const rnd = (seed: number) => { const s = Math.sin(seed * 91.17 + 7.3) * 43758.5453; return s - Math.floor(s); };

/** Élément de décor `kind`, posé sur sa base (origine = centre du bas de la boîte sx × sy × sz). */
export function decoProp(kind: string, sx: number, sy: number, sz: number, color: number | undefined, seed: number): Prop {
  const g = new THREE.Group();
  switch (kind) {
    case 'rock': {
      const c = color ?? 0x9aa5b1;
      for (let k = 0; k < 2; k++) {
        const geo = new THREE.IcosahedronGeometry(1, 1);
        const p = geo.attributes.position;
        for (let i = 0; i < p.count; i++) {
          const n = 0.8 + rnd(seed * 13 + Math.round(p.getX(i) * 5) * 7 + Math.round(p.getY(i) * 5) * 3 + Math.round(p.getZ(i) * 5)) * 0.35;
          p.setXYZ(i, p.getX(i) * n, Math.max(-0.35, p.getY(i)) * n, p.getZ(i) * n);
        }
        geo.computeVertexNormals();
        const s = k ? 0.42 : 1;
        const m = mesh(geo, new THREE.MeshStandardMaterial({ color: k ? shade(c, 0.85) : c, roughness: 0.85, flatShading: true }), k ? sx * 0.42 : 0, sy * 0.35 * s, k ? sz * 0.3 : 0, g);
        m.scale.set((sx / 2) * s, (sy / 1.35) * s, (sz / 2) * s);
        m.rotation.y = seed + k * 2;
      }
      return { obj: g };
    }
    case 'balloon': {
      const bs: THREE.Group[] = [];
      const n = Math.max(1, Math.min(5, Math.round((sx * sz) / 1.5)));
      for (let k = 0; k < n; k++) {
        const b = balloon(color !== undefined && k === 0 ? color : VIVID[(seed + k * 3) % VIVID.length]);
        const a = (k / n) * Math.PI * 2;
        b.position.set(n > 1 ? Math.cos(a) * sx * 0.3 : 0, Math.max(1.2, sy - 0.7) - (k % 2) * 0.35, n > 1 ? Math.sin(a) * sz * 0.3 : 0);
        b.userData.y = b.position.y;
        g.add(b);
        bs.push(b);
      }
      mesh(rbox(0.4, 0.3, 0.4, 0.08), mat(0x5c6470), 0, 0.15, 0, g); // lest
      return { obj: g, update: (t) => bs.forEach((b, k) => { b.position.y = b.userData.y + Math.sin(t * 1.3 + k * 1.7 + seed) * 0.2; b.rotation.z = Math.sin(t * 0.9 + k) * 0.08; }) };
    }
    case 'arrow': {
      // flèche plate qui flotte et rebondit, pointe vers +z local
      const w = Math.max(0.6, sx), L = Math.max(0.8, sz);
      const shape = new THREE.Shape([
        new THREE.Vector2(-w * 0.22, -L / 2), new THREE.Vector2(w * 0.22, -L / 2), new THREE.Vector2(w * 0.22, L * 0.05),
        new THREE.Vector2(w / 2, L * 0.05), new THREE.Vector2(0, L / 2), new THREE.Vector2(-w / 2, L * 0.05), new THREE.Vector2(-w * 0.22, L * 0.05),
      ]);
      const geo = new THREE.ExtrudeGeometry(shape, { depth: 0.22, bevelEnabled: true, bevelSize: 0.06, bevelThickness: 0.06, bevelSegments: 2 }).rotateX(Math.PI / 2);
      const a = mesh(geo, mat(color ?? 0xffd60a, { glow: 0.5, rough: 0.3 }), 0, sy / 2, 0, g);
      return { obj: g, update: (t) => { a.position.y = sy / 2 + Math.abs(Math.sin(t * 3 + seed)) * 0.4; a.position.z = Math.sin(t * 3 + seed) * 0.1; } };
    }
    case 'flag': {
      const h = Math.max(1, sy), fw = Math.max(0.6, Math.min(2.5, sx * 0.8)), fh = Math.max(0.4, h * 0.3);
      mesh(new THREE.CylinderGeometry(0.06, 0.08, h, 8), mat(0xffffff, { rough: 0.3 }), 0, h / 2, 0, g);
      mesh(new THREE.SphereGeometry(0.12, 10, 8), mat(0xffd60a, { rough: 0.25 }), 0, h + 0.05, 0, g);
      const geo = new THREE.PlaneGeometry(fw, fh, 10, 1).translate(fw / 2 + 0.06, 0, 0);
      const cloth = mesh(geo, mat(color ?? 0xff4d6d, { side: THREE.DoubleSide, map: tex.stripes('#ffffff', '#f0f0f0', 1, 1) }), 0, h - fh / 2 - 0.08, 0, g);
      const p = geo.attributes.position, x0 = Float32Array.from({ length: p.count }, (_, i) => p.getX(i));
      return { obj: g, update: (t) => {
        for (let i = 0; i < p.count; i++) { const x = x0[i]; p.setZ(i, Math.sin(x * 3.2 - t * 6 + seed) * 0.13 * x); }
        p.needsUpdate = true;
        cloth.geometry.computeVertexNormals();
      } };
    }
    case 'cactus': {
      const k = Math.max(0.5, sy / 2.5), c = color ?? 0x3fae5a, m = mat(c, { rough: 0.55 });
      const r = 0.28 * k;
      mesh(new THREE.CapsuleGeometry(r, Math.max(0.1, sy - 2 * r), 6, 12), m, 0, sy / 2, 0, g);
      for (const s of [-1, 1]) {
        const ah = sy * (s < 0 ? 0.32 : 0.45), ay = sy * (s < 0 ? 0.42 : 0.55);
        mesh(new THREE.CapsuleGeometry(r * 0.7, r * 1.2, 4, 10), m, s * r * 2.2, ay + ah * 0.35, 0, g);
        mesh(new THREE.CapsuleGeometry(r * 0.7, r * 1.2, 4, 10), m, s * r * 1.2, ay, 0, g).rotation.z = Math.PI / 2;
      }
      mesh(new THREE.SphereGeometry(r * 0.55, 10, 8), mat(0xff70a6, { rough: 0.3 }), 0, sy + r * 0.1, 0, g);
      return { obj: g };
    }
    case 'mushroom': {
      const r = Math.max(0.3, Math.min(sx, sz) / 2), stem = sy * 0.6;
      mesh(new THREE.CylinderGeometry(r * 0.32, r * 0.42, stem, 14), mat(0xfff3e0, { rough: 0.6 }), 0, stem / 2, 0, g);
      const cap = mesh(new THREE.SphereGeometry(r, 22, 12, 0, Math.PI * 2, 0, Math.PI / 2), mat(color ?? 0xe63946, { rough: 0.3 }), 0, stem - 0.02, 0, g);
      cap.scale.y = Math.max(0.5, (sy - stem) / r + 0.1);
      const dot = new THREE.SphereGeometry(r * 0.13, 8, 6), white = mat(0xffffff, { rough: 0.4 });
      for (let k = 0; k < 7; k++) {
        const a = k * 2.4 + seed, e = k === 0 ? Math.PI / 2 : 0.45 + (k % 3) * 0.28;
        const d = mesh(dot, white, Math.cos(a) * Math.cos(e) * r, stem + Math.sin(e) * r * cap.scale.y, Math.sin(a) * Math.cos(e) * r, g);
        d.scale.y = 0.45;
      }
      return { obj: g };
    }
    case 'crystal': {
      const c = color ?? 0x9b5de5, m = mat(c, { glow: 0.45, rough: 0.12, metal: 0.2 });
      const cl = new THREE.Group();
      g.add(cl);
      for (let k = 0; k < 5; k++) {
        const h = sy * (k ? 0.45 + rnd(seed + k) * 0.35 : 1), r = Math.min(sx, sz) * (k ? 0.16 : 0.24);
        const o = mesh(new THREE.OctahedronGeometry(1, 0), m, k ? Math.cos(k * 1.6) * sx * 0.25 : 0, h / 2, k ? Math.sin(k * 1.6) * sz * 0.25 : 0, cl);
        o.scale.set(r, h / 2, r);
        o.rotation.set(k ? Math.cos(k * 1.6) * 0.35 : 0, k * 0.7, k ? -Math.sin(k * 1.6) * 0.35 : 0);
      }
      return { obj: g, update: (t) => { m.emissiveIntensity = 0.35 + 0.25 * Math.sin(t * 2 + seed); cl.rotation.y = Math.sin(t * 0.4 + seed) * 0.15; } };
    }
    case 'crowd': {
      // petits spectateurs qui sautillent, lèvent les bras et suivent le joueur des yeux
      const k = Math.max(0.6, Math.min(2, sy)), n = Math.max(3, Math.min(HIGH ? 24 : 12, Math.floor((sx * sz) / (1.1 * k * k))));
      const cols = Math.max(1, Math.round(Math.sqrt((n * sx) / sz))), rows = Math.ceil(n / cols);
      const bodyGeo = new THREE.CapsuleGeometry(0.22 * k, 0.32 * k, 4, HIGH ? 10 : 6), headGeo = new THREE.SphereGeometry(0.21 * k, HIGH ? 14 : 8, HIGH ? 10 : 6);
      const armGeo = new THREE.CapsuleGeometry(0.06 * k, 0.28 * k, 3, 6).translate(0, -0.2 * k, 0), eyeGeo = new THREE.SphereGeometry(0.035 * k, 6, 4), black = mat(0x2b2140);
      const fans: { o: THREE.Group; arms: THREE.Mesh[]; rate: number; ph: number }[] = [];
      // estrade sous leurs pieds
      mesh(rbox(sx, 0.3, sz, 0.1), mat(0xffffff, { map: tex.planks(), rough: 0.7 }), 0, -0.15, 0, g);
      for (let i = 0; i < n; i++) {
        const cx = i % cols, cz = Math.floor(i / cols);
        const o = new THREE.Group();
        o.position.set((cols > 1 ? cx / (cols - 1) - 0.5 : 0) * (sx - 0.6 * k) + (rnd(seed + i) - 0.5) * 0.2, 0, (rows > 1 ? cz / (rows - 1) - 0.5 : 0) * (sz - 0.6 * k) + (rnd(seed + i * 3) - 0.5) * 0.2);
        const shirt = color !== undefined ? (i % 3 ? color : shade(color, i % 2 ? 0.75 : 1.3)) : VIVID[(i * 5 + seed) % VIVID.length];
        mesh(bodyGeo, mat(shirt), 0, 0.38 * k, 0, o);
        mesh(headGeo, mat(SKIN[(i + seed) % SKIN.length], { rough: 0.6 }), 0, 0.86 * k, 0, o);
        for (const s of [-1, 1]) mesh(eyeGeo, black, s * 0.075 * k, 0.9 * k, 0.18 * k, o);
        const arms = [-1, 1].map((s) => mesh(armGeo, mat(shirt), s * 0.27 * k, 0.62 * k, 0, o));
        g.add(o);
        fans.push({ o, arms, rate: 5 + rnd(seed + i * 7) * 3, ph: rnd(seed + i * 11) * 6 });
      }
      const wp = new THREE.Vector3();
      return { obj: g, update: (t, look) => {
        g.getWorldPosition(wp);
        const toward = Math.atan2(look.x - wp.x, look.z - wp.z) - g.rotation.y;
        for (const f of fans) {
          const s = Math.sin(t * f.rate + f.ph);
          f.o.position.y = Math.max(0, s) * 0.35 * k;
          f.o.rotation.y = toward;
          // bras le long du corps au sol, levés au sommet du saut
          f.arms[0].rotation.z = -0.25 - Math.max(0, s) * 2.5;
          f.arms[1].rotation.z = 0.25 + Math.max(0, s) * 2.5;
        }
      } };
    }
    default: { // tree
      const t = tree(Math.max(1, sy), color ?? 0x52d681);
      const s = Math.max(0.5, Math.min(2, Math.max(sx, sz) / (0.6 * Math.max(1, sy))));
      t.scale.set(s, 1, s);
      g.add(t);
      return { obj: g, update: (time) => { t.rotation.z = Math.sin(time * 1.1 + seed) * 0.025; t.rotation.x = Math.sin(time * 0.8 + seed * 2) * 0.02; } };
    }
  }
}

/** Panneau en bois avec un texte sur plusieurs lignes (face avant vers +z), dos uni. */
export function textBoard(text: string, w: number, h: number): THREE.Mesh {
  const c = document.createElement('canvas');
  c.width = 1024; c.height = Math.max(64, Math.round((1024 * h) / w));
  const g = c.getContext('2d')!;
  g.fillStyle = '#fff6e0'; g.fillRect(0, 0, c.width, c.height);
  const pad = Math.min(c.width, c.height) * 0.08;
  g.strokeStyle = '#d99a55'; g.lineWidth = pad * 0.6; g.strokeRect(pad * 0.3, pad * 0.3, c.width - pad * 0.6, c.height - pad * 0.6);
  // plus grande police dont le texte (coupé aux espaces) tient dans le cadre
  const words = text.trim().split(/\s+/).filter(Boolean);
  let size = c.height, lines: string[] = [];
  for (; size > 12; size *= 0.92) {
    g.font = `900 ${Math.round(size)}px "Trebuchet MS", sans-serif`;
    lines = [];
    let cur = '';
    for (const wd of words) {
      const next = cur ? `${cur} ${wd}` : wd;
      if (g.measureText(next).width > c.width - pad * 2.4 && cur) { lines.push(cur); cur = wd; } else cur = next;
    }
    if (cur) lines.push(cur);
    if (lines.every((l) => g.measureText(l).width <= c.width - pad * 2.4) && lines.length * size * 1.1 <= c.height - pad * 2.4) break;
  }
  g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillStyle = '#2b2140';
  lines.forEach((l, i) => g.fillText(l, c.width / 2, c.height / 2 + (i - (lines.length - 1) / 2) * size * 1.1));
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  const wood = mat(0xc98846, { map: tex.planks() });
  return new THREE.Mesh(rbox(w, h, 0.14, 0.05), [wood, wood, wood, wood, mat(0xffffff, { map: t }), wood]);
}

/** Arche gonflable rayée (plan XY local, pieds à y = 0, en x = ±span/2) avec bannière et ballons. `update` la fait respirer. */
export function inflatableArch(span: number, label: string, a: string, b: string, bannerBg: string, bannerFg: string): Prop {
  const g = new THREE.Group(), R = Math.max(1.2, span / 2);
  const inner = new THREE.Group();
  g.add(inner);
  mesh(new THREE.TorusGeometry(R, 0.45, HIGH ? 16 : 10, HIGH ? 44 : 24, Math.PI), mat(0xffffff, { map: tex.stripes(a, b, 12, 1), rough: 0.28 }), 0, 0, 0, inner);
  for (const s of [-1, 1]) {
    mesh(new THREE.CylinderGeometry(0.62, 0.7, 0.45, 16), mat(0x2b2140, { rough: 0.5 }), s * R, 0.2, 0, g);
    const bl = balloon(s < 0 ? 0xff4d6d : 0x00b4d8);
    bl.position.set(s * (R + 0.35), R * 0.85 + 1.7, 0);
    inner.add(bl);
  }
  const board = sign(label, Math.min(4.5, R * 1.3), 1, bannerBg, bannerFg);
  board.position.set(0, R + 0.95, 0);
  inner.add(board);
  return { obj: g, update: (t) => { const s = 1 + Math.sin(t * 2.2) * 0.012; inner.scale.set(s, 1 + Math.sin(t * 2.2 + 1) * 0.015, s); } };
}

/** Surface animée de lave / eau / acide : texture qui défile (offset). */
export function hazardMaterial(style: string, w: number, d: number): { body: THREE.MeshStandardMaterial; top: THREE.MeshStandardMaterial; map: THREE.CanvasTexture } {
  const pal = style === 'water' ? ['#1f8fe0', '#7fd8ff', '#c9f2ff'] : style === 'acid' ? ['#4fd11f', '#a6ff4d', '#e9ff9e'] : ['#e8430c', '#ff9a1f', '#ffe14a'];
  const map = canvasTex(256, (g, s) => {
    g.fillStyle = pal[0]; g.fillRect(0, 0, s, s);
    for (let i = 0; i < 26; i++) {
      const x = rnd(i * 3.1) * s, y = rnd(i * 7.7) * s, r = 8 + rnd(i * 1.3) * (style === 'water' ? 10 : 26);
      g.fillStyle = i % 3 ? pal[1] : pal[2];
      g.globalAlpha = style === 'water' ? 0.55 : 0.85;
      for (const [ox, oy] of [[0, 0], [s, 0], [-s, 0], [0, s], [0, -s]]) {
        g.beginPath();
        if (style === 'water') { g.ellipse(x + ox, y + oy, r * 2.2, r * 0.35, 0, 0, 7); g.fill(); }
        else { g.arc(x + ox, y + oy, r, 0, 7); g.fill(); }
      }
    }
    g.globalAlpha = 1;
  }, w / 4, d / 4);
  const base = style === 'water' ? 0x1f8fe0 : style === 'acid' ? 0x4fd11f : 0xe8430c;
  const top = new THREE.MeshStandardMaterial({ color: 0xffffff, map, roughness: style === 'water' ? 0.08 : 0.35, metalness: 0, emissive: style === 'water' ? 0x000000 : base, emissiveIntensity: style === 'water' ? 0 : 0.55, emissiveMap: style === 'water' ? null : map, transparent: style === 'water', opacity: style === 'water' ? 0.88 : 1 });
  const body = mat(style === 'water' ? 0x1565a8 : style === 'acid' ? 0x2c6e1a : 0x6b2a12, { rough: 0.8, glow: style === 'lava' ? 0.25 : 0 });
  return { body, top, map };
}

/** Texture ronde et douce (bouffée de brouillard, fumée). */
export const puffTex = (() => {
  let t: THREE.CanvasTexture | null = null;
  return () => t ??= canvasTex(128, (g, s) => {
    const gr = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
    gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.5, 'rgba(255,255,255,0.45)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = gr; g.fillRect(0, 0, s, s);
  });
})();
