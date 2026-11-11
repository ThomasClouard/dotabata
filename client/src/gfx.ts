// Boîte à outils graphique commune : matériaux « plastique brillant », formes arrondies, ciel, mer, ombres et bloom.
// Tout est procédural : aucune texture ni modèle à charger.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { mergeVertices } from 'three/examples/jsm/utils/BufferGeometryUtils.js';

/** Graphismes élevés (ombres, bloom, antialiasing) ou légers pour les petites machines. */
export const HIGH = (() => { try { return localStorage.getItem('jeux-qualite') !== 'basse'; } catch { return true; } })();
export function toggleQuality(): void {
  try { localStorage.setItem('jeux-qualite', HIGH ? 'basse' : 'haute'); } catch { /* stockage indisponible */ }
  location.reload();
}

export const SUN_DIR = new THREE.Vector3(0.45, 0.8, 0.35).normalize();

// ---------- matériaux et formes ----------

export interface MatOpts { rough?: number; metal?: number; glow?: number; map?: THREE.Texture | null; opacity?: number; side?: THREE.Side }

/** Matériau façon jouet en plastique : couleurs franches, reflets doux. `glow` le rend lumineux (capté par le bloom). */
export function mat(color: number, o: MatOpts = {}): THREE.MeshStandardMaterial {
  const m = new THREE.MeshStandardMaterial({ color, roughness: o.rough ?? 0.42, metalness: o.metal ?? 0, map: o.map ?? null, side: o.side ?? THREE.FrontSide });
  if (o.glow) { m.emissive.set(color); m.emissiveIntensity = o.glow; }
  if (o.opacity !== undefined && o.opacity < 1) { m.transparent = true; m.opacity = o.opacity; }
  return m;
}

const tmpColor = new THREE.Color();
/** Éclaircit (k > 1) ou assombrit (k < 1) une couleur. */
export function shade(color: number, k: number): number {
  tmpColor.set(color);
  if (k <= 1) tmpColor.multiplyScalar(k);
  else tmpColor.lerp(new THREE.Color(0xffffff), Math.min(1, k - 1));
  return tmpColor.getHex();
}

/** Boîte aux arêtes arrondies. */
export function rbox(w: number, h: number, d: number, r = 0.18): THREE.BufferGeometry {
  return new RoundedBoxGeometry(w, h, d, 4, Math.max(0.01, Math.min(r, w / 2 - 0.005, h / 2 - 0.005, d / 2 - 0.005)));
}

export function mesh(geo: THREE.BufferGeometry, material: THREE.Material, x = 0, y = 0, z = 0, parent?: THREE.Object3D): THREE.Mesh {
  const m = new THREE.Mesh(geo, material);
  m.position.set(x, y, z);
  parent?.add(m);
  return m;
}

/** Active les ombres portées et reçues sur un objet et ses enfants (sauf les matériaux translucides ou non éclairés). */
export function shadowify(o: THREE.Object3D): void {
  o.traverse((c) => {
    const m = c as THREE.Mesh;
    if (!m.isMesh || m.userData.noShadow) return;
    const material = m.material as THREE.Material;
    const lit = !(material as THREE.MeshBasicMaterial).isMeshBasicMaterial && !(material as THREE.ShaderMaterial).isShaderMaterial;
    m.castShadow = lit && !material.transparent;
    m.receiveShadow = lit;
  });
}

const hash = (x: number, y: number, z: number) => {
  const s = Math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453;
  return s - Math.floor(s);
};

/** Rocher lisse et irrégulier, plat sur le dessus : sert de dessous aux plateformes et îles flottantes. */
export function rockUnder(w: number, h: number, d: number, color: number, seed = 0): THREE.Mesh {
  let g: THREE.BufferGeometry = new THREE.IcosahedronGeometry(1, 3);
  g.deleteAttribute('uv');
  g.deleteAttribute('normal');
  g = mergeVertices(g);
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) {
    let x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    const n = 0.82 + hash(Math.round(x * 3) + seed, Math.round(y * 3), Math.round(z * 3)) * 0.3;
    // silhouette plus carrée vue de dessus, pointe vers le bas
    const sq = 1 / Math.max(Math.abs(x), Math.abs(z), 0.55);
    const k = y < 0 ? 1 - Math.pow(-y, 1.6) * 0.55 : 1;
    x *= Math.min(sq, 1.35) * k * n; z *= Math.min(sq, 1.35) * k * n;
    y = y > 0 ? 0 : y * n;
    p.setXYZ(i, x * w * 0.5, y * h, z * d * 0.5);
  }
  g.computeVertexNormals();
  return new THREE.Mesh(g, mat(color, { rough: 0.9 }));
}

export interface SlabOpts { top?: number; topMap?: THREE.Texture; under?: boolean; seed?: number; glow?: number }

/**
 * Plateforme prête à poser : corps arrondi, dessus plus clair avec un léger débord, rocher flottant dessous.
 * L'origine du groupe est le centre de la boîte de collision (w × h × d).
 */
export function slab(w: number, h: number, d: number, color: number, o: SlabOpts = {}): THREE.Group {
  const g = new THREE.Group();
  const capH = Math.min(0.24, h * 0.42);
  const body = mesh(rbox(w, h - capH * 0.6, d, Math.min(0.22, h * 0.4)), mat(shade(color, 0.7)), 0, -capH * 0.3, 0, g);
  body.name = 'corps';
  const cap = mesh(rbox(w + 0.1, capH, d + 0.1, capH * 0.48), mat(o.top ?? color, { map: o.topMap, glow: o.glow }), 0, h / 2 - capH / 2, 0, g);
  cap.name = 'dessus';
  if (o.under !== false && Math.min(w, d) >= 2) {
    const rock = rockUnder(w * 0.92, Math.min(4.5, Math.max(1, Math.min(w, d) * 0.5)), d * 0.92, shade(color, 0.45), o.seed ?? 0);
    rock.position.y = -h / 2 + 0.05;
    g.add(rock);
  }
  return g;
}

// ---------- textures procédurales ----------

export function canvasTex(size: number, draw: (g: CanvasRenderingContext2D, s: number) => void, repeatX = 1, repeatY = 1): THREE.CanvasTexture {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  draw(c.getContext('2d')!, size);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeatX, repeatY);
  t.anisotropy = 4;
  return t;
}

export const tex = {
  checker: (a: string, b: string, rx = 1, ry = 1) => canvasTex(128, (g, s) => {
    for (let x = 0; x < 2; x++) for (let y = 0; y < 2; y++) { g.fillStyle = (x + y) % 2 ? a : b; g.fillRect((x * s) / 2, (y * s) / 2, s / 2, s / 2); }
  }, rx, ry),
  /** Bandes diagonales (rembourrage, signalisation). */
  stripes: (a: string, b: string, rx = 1, ry = 1) => canvasTex(128, (g, s) => {
    g.fillStyle = a; g.fillRect(0, 0, s, s);
    g.fillStyle = b;
    for (let i = -1; i < 3; i++) { g.beginPath(); g.moveTo(i * s / 2, 0); g.lineTo(i * s / 2 + s / 4, 0); g.lineTo(i * s / 2 + s / 4 + s, s); g.lineTo(i * s / 2 + s, s); g.fill(); }
  }, rx, ry),
  /** Dalle fissurée. */
  cracks: (base: string) => canvasTex(256, (g, s) => {
    g.fillStyle = base; g.fillRect(0, 0, s, s);
    g.strokeStyle = 'rgba(70,35,10,0.75)'; g.lineWidth = 5; g.lineCap = 'round'; g.lineJoin = 'round';
    for (let k = 0; k < 5; k++) {
      let x = s / 2 + (Math.random() - 0.5) * 60, y = s / 2 + (Math.random() - 0.5) * 60;
      const a0 = (k / 5) * Math.PI * 2;
      g.beginPath(); g.moveTo(x, y);
      for (let i = 0; i < 6; i++) { const a = a0 + (Math.random() - 0.5) * 1.2; x += Math.cos(a) * 28; y += Math.sin(a) * 28; g.lineTo(x, y); }
      g.stroke();
    }
  }),
  planks: () => canvasTex(128, (g, s) => {
    for (let i = 0; i < 4; i++) {
      g.fillStyle = ['#d99a55', '#c98846', '#e0a660', '#cf9150'][i]; g.fillRect(0, (i * s) / 4, s, s / 4);
      g.fillStyle = 'rgba(90,50,15,0.55)'; g.fillRect(0, (i * s) / 4, s, 3);
      g.fillRect(((i * 53) % 90) + 10, (i * s) / 4, 3, s / 4);
    }
    g.fillStyle = 'rgba(60,35,10,0.6)';
    for (const [x, y] of [[10, 10], [s - 16, 10], [10, s - 16], [s - 16, s - 16]]) { g.beginPath(); g.arc(x + 3, y + 3, 4, 0, 7); g.fill(); }
  }),
  stone: () => canvasTex(128, (g, s) => {
    g.fillStyle = '#a9b3bd'; g.fillRect(0, 0, s, s);
    for (let i = 0; i < 60; i++) { g.fillStyle = `rgba(${Math.random() < 0.5 ? '255,255,255' : '50,60,70'},${0.08 + Math.random() * 0.15})`; g.beginPath(); g.arc(Math.random() * s, Math.random() * s, 2 + Math.random() * 7, 0, 7); g.fill(); }
    g.strokeStyle = 'rgba(60,70,80,0.5)'; g.lineWidth = 4; g.strokeRect(2, 2, s - 4, s - 4);
  }),
  target: (a: string, b: string) => canvasTex(128, (g, s) => {
    g.fillStyle = a; g.fillRect(0, 0, s, s);
    for (let i = 3; i > 0; i--) { g.fillStyle = i % 2 ? b : a; g.beginPath(); g.arc(s / 2, s / 2, (i * s) / 7, 0, 7); g.fill(); }
  }),
  /** Sol à gros motif doux (damier arrondi). */
  soft: (a: string, b: string, rx = 1, ry = 1) => canvasTex(128, (g, s) => {
    g.fillStyle = a; g.fillRect(0, 0, s, s);
    g.fillStyle = b;
    for (const [x, y] of [[0, 0], [s / 2, s / 2]]) { g.beginPath(); g.roundRect(x + 6, y + 6, s / 2 - 12, s / 2 - 12, 14); g.fill(); }
  }, rx, ry),
};

/** Panneau avec du texte (pancarte, bannière). */
export function sign(text: string, w: number, h: number, bg: string, fg: string): THREE.Mesh {
  const c = document.createElement('canvas');
  c.width = 512; c.height = Math.round((512 * h) / w);
  const g = c.getContext('2d')!;
  g.fillStyle = bg; g.fillRect(0, 0, c.width, c.height);
  g.font = `900 ${Math.round(c.height * 0.62)}px "Trebuchet MS", sans-serif`;
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.lineWidth = c.height * 0.09; g.strokeStyle = 'rgba(0,0,0,0.35)'; g.lineJoin = 'round';
  g.strokeText(text, c.width / 2, c.height * 0.54);
  g.fillStyle = fg; g.fillText(text, c.width / 2, c.height * 0.54);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  const m = new THREE.Mesh(rbox(w, h, 0.18, 0.08), [mat(0xffffff), mat(0xffffff), mat(0xffffff), mat(0xffffff), mat(0xffffff, { map: t }), mat(0xffffff, { map: t })]);
  return m;
}

/** Ballon décoratif avec sa ficelle. */
export function balloon(color: number): THREE.Group {
  const g = new THREE.Group();
  const b = mesh(new THREE.SphereGeometry(0.55, 16, 12), mat(color, { rough: 0.2 }), 0, 0, 0, g);
  b.scale.y = 1.2;
  mesh(new THREE.ConeGeometry(0.1, 0.16, 8), mat(color), 0, -0.7, 0, g);
  const s = mesh(new THREE.CylinderGeometry(0.012, 0.012, 1.6, 4), new THREE.MeshBasicMaterial({ color: 0xffffff }), 0, -1.55, 0, g);
  s.userData.noShadow = true;
  return g;
}

/** Petit arbre rond stylisé. */
export function tree(h = 3, leaf = 0x52d681): THREE.Group {
  const g = new THREE.Group();
  mesh(new THREE.CylinderGeometry(0.16, 0.24, h * 0.55, 8), mat(0x9c6644, { rough: 0.8 }), 0, h * 0.275, 0, g);
  const s = new THREE.SphereGeometry(1, 14, 10);
  for (const [x, y, z, r] of [[0, h * 0.72, 0, 0.9], [0.5, h * 0.6, 0.2, 0.6], [-0.45, h * 0.62, -0.25, 0.65], [0.1, h * 0.95, -0.1, 0.6]]) {
    mesh(s, mat(leaf, { rough: 0.7 }), x, y, z, g).scale.setScalar(r * h * 0.3);
  }
  return g;
}

// ---------- ciel et mer ----------

const SHADER_END = '\n#include <tonemapping_fragment>\n#include <colorspace_fragment>\n';

export class Sky {
  readonly mesh: THREE.Mesh;
  readonly horizon = new THREE.Color();
  private u = { uTop: { value: new THREE.Color() }, uHorizon: { value: this.horizon }, uSun: { value: SUN_DIR } };

  constructor() {
    this.mesh = new THREE.Mesh(new THREE.SphereGeometry(480, 32, 16), new THREE.ShaderMaterial({
      uniforms: this.u, side: THREE.BackSide, depthWrite: false, fog: false,
      vertexShader: 'varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
      fragmentShader: `uniform vec3 uTop; uniform vec3 uHorizon; uniform vec3 uSun; varying vec3 vDir;
        void main(){
          vec3 d = normalize(vDir);
          float h = clamp(d.y, -1.0, 1.0);
          vec3 c = mix(uHorizon, uTop, pow(smoothstep(0.0, 0.85, h), 0.7));
          c = mix(c, uHorizon * 0.96, smoothstep(0.0, -0.35, h));
          float s = max(dot(d, uSun), 0.0);
          c += vec3(1.0, 0.93, 0.75) * (pow(s, 900.0) * 6.0 + pow(s, 28.0) * 0.35 + pow(s, 4.0) * 0.12);
          gl_FragColor = vec4(c, 1.0);${SHADER_END}
        }`,
    }));
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = -10;
    this.set(0x8fd3ff);
  }

  set(color: number): void {
    const c = new THREE.Color(color);
    this.u.uTop.value.copy(c).offsetHSL(-0.02, 0.12, -0.2);
    this.horizon.copy(c).lerp(new THREE.Color(0xffffff), 0.42);
  }
}

export class Sea {
  readonly mesh: THREE.Mesh;
  private u = { uTime: { value: 0 }, uDeep: { value: new THREE.Color() }, uLight: { value: new THREE.Color() }, uFog: { value: new THREE.Color() }, uSun: { value: SUN_DIR } };

  constructor(fog: THREE.Color) {
    this.u.uFog.value = fog;
    this.mesh = new THREE.Mesh(new THREE.PlaneGeometry(900, 900, HIGH ? 180 : 60, HIGH ? 180 : 60).rotateX(-Math.PI / 2), new THREE.ShaderMaterial({
      uniforms: this.u, fog: false,
      vertexShader: `uniform float uTime; varying float vH; varying vec3 vW; varying vec3 vN;
        float wave(vec2 p){ return sin(p.x * 0.11 + uTime * 0.7) * 0.7 + sin(p.y * 0.16 - uTime * 0.55) * 0.55 + sin((p.x + p.y) * 0.29 + uTime * 1.2) * 0.28 + sin((p.x - p.y) * 0.47 - uTime * 1.6) * 0.14; }
        void main(){
          vec4 w = modelMatrix * vec4(position, 1.0);
          float h = wave(w.xz);
          vN = normalize(vec3(wave(w.xz - vec2(0.6, 0.0)) - wave(w.xz + vec2(0.6, 0.0)), 1.2, wave(w.xz - vec2(0.0, 0.6)) - wave(w.xz + vec2(0.0, 0.6))));
          w.y += h; vH = h; vW = w.xyz;
          gl_Position = projectionMatrix * viewMatrix * w;
        }`,
      fragmentShader: `uniform vec3 uDeep; uniform vec3 uLight; uniform vec3 uFog; uniform vec3 uSun; varying float vH; varying vec3 vW; varying vec3 vN;
        void main(){
          vec3 n = normalize(vN), v = normalize(cameraPosition - vW);
          vec3 c = mix(uDeep, uLight, smoothstep(-1.2, 1.5, vH));
          c *= 0.75 + 0.35 * max(dot(n, uSun), 0.0);
          c += vec3(1.0) * pow(max(dot(reflect(-uSun, n), v), 0.0), 60.0) * 0.9;        // reflets du soleil
          c = mix(c, uFog, pow(1.0 - max(dot(n, v), 0.0), 3.0) * 0.22);                    // le ciel se reflète à l'horizon
          c = mix(c, vec3(1.0), smoothstep(1.25, 1.6, vH) * 0.7);                           // écume sur les crêtes
          c = mix(c, uFog, smoothstep(110.0, 420.0, length(vW - cameraPosition)));
          gl_FragColor = vec4(c, 1.0);${SHADER_END}
        }`,
    }));
    this.mesh.frustumCulled = false;
    this.mesh.visible = false;
  }

  /** Place la mer à l'altitude `y` (null = pas de mer). */
  set(y: number | null, color = 0x1fb6e0): void {
    this.mesh.visible = y !== null;
    if (y === null) return;
    this.mesh.position.y = y;
    this.u.uDeep.value.set(color).multiplyScalar(0.62);
    this.u.uLight.value.set(color).lerp(new THREE.Color(0xffffff), 0.3);
  }

  update(time: number, cx: number, cz: number): void {
    this.u.uTime.value = time;
    this.mesh.position.x = Math.round(cx / 20) * 20;
    this.mesh.position.z = Math.round(cz / 20) * 20;
  }
}

/** Nuages moelleux : toutes les boules dans un seul InstancedMesh. */
export function makeClouds(): THREE.InstancedMesh {
  const blobs: THREE.Matrix4[] = [];
  const m = new THREE.Matrix4(), q = new THREE.Quaternion();
  for (let i = 0; i < 22; i++) {
    const a = (i / 22) * Math.PI * 2 + Math.random() * 0.3, r = 110 + Math.random() * 140;
    const cx = Math.sin(a) * r, cy = 10 + Math.random() * 90, cz = Math.cos(a) * r, sc = 5 + Math.random() * 8;
    for (let k = 0; k < 7; k++) {
      const s = sc * (0.55 + Math.random() * 0.6) * (k === 0 ? 1.3 : 1);
      m.compose(new THREE.Vector3(cx + (k - 3) * sc * 0.75 + Math.random() * sc * 0.4, cy + (k % 2) * sc * 0.25 + Math.random() * sc * 0.3 - Math.abs(k - 3) * sc * 0.08, cz + (Math.random() - 0.5) * sc), q, new THREE.Vector3(s, s * 0.72, s));
      blobs.push(m.clone());
    }
  }
  const material = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 1, emissive: 0xffffff, emissiveIntensity: 0.32, fog: false });
  const inst = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(1, 3), material, blobs.length);
  blobs.forEach((b, i) => inst.setMatrixAt(i, b));
  inst.frustumCulled = false;
  inst.userData.noShadow = true;
  return inst;
}

// ---------- rendu ----------

export interface Graphics {
  sky: Sky;
  sea: Sea;
  sun: THREE.DirectionalLight;
  render(): void;
  resize(w: number, h: number): void;
  /** Recentre la zone d'ombres sur le point regardé par la caméra. */
  follow(target: THREE.Vector3): void;
}

export function setupGraphics(renderer: THREE.WebGLRenderer, scene: THREE.Scene, camera: THREE.PerspectiveCamera): Graphics {
  renderer.setPixelRatio(HIGH ? Math.min(devicePixelRatio, 2) : 1);
  renderer.toneMapping = THREE.NeutralToneMapping;
  renderer.toneMappingExposure = 1.0;
  renderer.shadowMap.enabled = HIGH;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  // reflets doux sur tous les matériaux
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.4;
  pmrem.dispose();

  const sky = new Sky();
  scene.fog = new THREE.Fog(0xffffff, 90, 360);
  scene.fog.color = sky.horizon;
  scene.background = null;
  const sea = new Sea(sky.horizon);
  scene.add(sky.mesh, sea.mesh);

  scene.add(new THREE.HemisphereLight(0xdff3ff, 0xb59ad6, 0.55));
  const sun = new THREE.DirectionalLight(0xfff4dc, 1.7);
  sun.castShadow = HIGH;
  sun.shadow.mapSize.set(2048, 2048);
  const sc = sun.shadow.camera;
  sc.left = -34; sc.right = 34; sc.top = 34; sc.bottom = -34; sc.near = 1; sc.far = 160;
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.04;
  sun.shadow.radius = 3;
  scene.add(sun, sun.target);

  let composer: EffectComposer | null = null;
  if (HIGH) {
    const size = renderer.getDrawingBufferSize(new THREE.Vector2());
    const target = new THREE.WebGLRenderTarget(size.x, size.y, { type: THREE.HalfFloatType, samples: 4 });
    composer = new EffectComposer(renderer, target);
    composer.addPass(new RenderPass(scene, camera));
    composer.addPass(new UnrealBloomPass(new THREE.Vector2(size.x / 2, size.y / 2), 0.22, 0.6, 1.0));
    composer.addPass(new OutputPass());
  }

  return {
    sky, sea, sun,
    render: () => (composer ? composer.render() : renderer.render(scene, camera)),
    resize: (w, h) => {
      renderer.setSize(w, h, false);
      composer?.setSize(w, h);
    },
    follow: (t) => {
      // position arrondie : évite le scintillement des ombres quand la caméra bouge
      const x = Math.round(t.x / 2) * 2, y = Math.round(t.y / 2) * 2, z = Math.round(t.z / 2) * 2;
      sun.target.position.set(x, y, z);
      sun.position.set(x + SUN_DIR.x * 70, y + SUN_DIR.y * 70, z + SUN_DIR.z * 70);
    },
  };
}
