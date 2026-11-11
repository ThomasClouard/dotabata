// Cœur du client : rendu, caméra troisième personne, personnage local, réseau, enchaînement lobby → manches → podium.
import * as THREE from 'three';
import { clientGames } from '../../games/registry.client';
import { clearMotionState, groundBelow, makeBody, pushApart, stepBody, type Collider, type Vec3 } from '../../shared/src/physics';
import { COLORS, FLAG, HATS, poseFlags, type PlayerInfo, type ServerMsg } from '../../shared/src/protocol';
import type { ClientCtx, ClientGame, ClientPlayer } from './api';
import { Sfx } from './audio';
import { Character } from './character/character';
import { Input } from './input';
import { Net } from './net';
import { Particles } from './particles';
import { createLobbyScene, createPodiumScene } from './scenes';
import { css, renderLobby, renderPodium, renderScores } from './ui';
import { HIGH, makeClouds, setupGraphics, shadowify, toggleQuality } from './gfx';

type LobbyMsg = Extract<ServerMsg, { t: 'lobby' }>;
interface CP extends ClientPlayer {
  label: THREE.Sprite;
  shadow: THREE.Mesh;
  net: { p: Vec3; v: Vec3; yaw: number; flags: number };
}

const $ = (id: string) => document.getElementById(id)!;
const canvas = $('c') as HTMLCanvasElement;
const hud = $('hud'), lobbyEl = $('lobby'), overlay = $('overlay'), banner = $('banner'), toastEl = $('toast'), waitEl = $('wait'), stopBtn = $('stop');

// ---------- rendu ----------
const renderer = new THREE.WebGLRenderer({ canvas, antialias: !HIGH, powerPreference: 'high-performance' });
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(58, 1, 0.1, 900);
const gfx = setupGraphics(renderer, scene, camera);
const world = new THREE.Group();
const charLayer = new THREE.Group();
const particles = new Particles();
const clouds = makeClouds();
scene.add(world, charLayer, particles.mesh, clouds);

function resize() {
  gfx.resize(innerWidth, innerHeight);
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
}
addEventListener('resize', resize);
resize();

// ---------- état ----------
const net = new Net();
const input = new Input(canvas);
const sfx = new Sfx();
const players = new Map<string, CP>();
const body = makeBody([0, 2, 0]);
let lobby: LobbyMsg | null = null;
let phase: 'boot' | 'lobby' | 'round' | 'scores' | 'podium' = 'boot';
let waiting = false;
let game: ClientGame | null = null;
let cols: Collider[] = [];
let camYaw = Math.PI, camPitch = 0.38, shake = 0;
let spectate: { target: Vec3; dist: number } | null = null;
let active = true, aimMode = false, charging = false;
let myYaw = 0;
let acc = 0;
let sendAcc = 0;
let lastCount = -1;
let toastTimer = 0;
let botsApplied = false;
const camTarget = new THREE.Vector3(0, 1.5, 0);
const H = 1 / 60;

const saved = (() => { try { return JSON.parse(localStorage.getItem('jeux-profil') ?? 'null'); } catch { return null; } })();
const profile = {
  name: saved?.name ?? `Joueur ${Math.floor(Math.random() * 90 + 10)}`,
  color: COLORS.includes(saved?.color) ? saved.color : COLORS[Math.floor(Math.random() * COLORS.length)],
  hat: HATS.includes(saved?.hat) ? saved.hat : HATS[Math.floor(Math.random() * HATS.length)],
};

const ctx: ClientCtx = {
  scene: world, camera, myId: '', players, body, startAt: 0, hud, sfx, particles, input,
  now: () => net.now(),
  send: (m) => net.send({ t: 'game', m }),
  camYaw: () => camYaw,
  setCamYaw: (y) => { camYaw = y; },
  shake: (a) => { shake = Math.min(1.2, Math.max(shake, a)); },
  setSky: (c) => gfx.sky.set(c),
  setSea: (y, color) => gfx.sea.set(y, color),
  setActive: (a) => { active = a; },
  setSpectate: (t, dist = 12) => { spectate = t ? { target: t, dist } : null; },
  setAimMode: (on) => { aimMode = on; },
  setCharging: (on) => { charging = on; },
  toast,
};

function toast(text: string, seconds = 1.8) {
  toastEl.textContent = text;
  toastEl.style.opacity = '1';
  clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => (toastEl.style.opacity = '0'), seconds * 1000);
}

// ---------- joueurs ----------
function makeLabel(name: string, color: number): THREE.Sprite {
  const c = document.createElement('canvas');
  c.width = 256; c.height = 64;
  const g = c.getContext('2d')!;
  g.font = '900 34px "Trebuchet MS", sans-serif';
  g.textAlign = 'center'; g.textBaseline = 'middle';
  g.lineWidth = 8; g.strokeStyle = '#2b2140'; g.lineJoin = 'round';
  g.strokeText(name, 128, 32);
  g.fillStyle = css(color);
  g.fillText(name, 128, 32);
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(c), depthTest: false, transparent: true, fog: false }));
  s.scale.set(2.2, 0.55, 1);
  s.position.y = 2.25;
  s.renderOrder = 10;
  return s;
}

const shadowGeo = new THREE.CircleGeometry(0.5, 16).rotateX(-Math.PI / 2);
const shadowMat = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.28, depthWrite: false });

function syncPlayers(list: PlayerInfo[]) {
  const seen = new Set<string>();
  for (const info of list) {
    seen.add(info.id);
    let p = players.get(info.id);
    if (!p) {
      const char = new Character(info.color, info.hat);
      const label = makeLabel(info.name, info.color);
      char.root.add(label);
      const shadow = new THREE.Mesh(shadowGeo, shadowMat);
      charLayer.add(char.root, shadow);
      p = { info, char, label, shadow, pos: new THREE.Vector3(0, 0, 0), yaw: 0, flags: FLAG.grounded, pin: null, hidden: false, net: { p: [0, 0, 0], v: [0, 0, 0], yaw: 0, flags: FLAG.grounded } };
      players.set(info.id, p);
    } else {
      if (p.info.color !== info.color || p.info.hat !== info.hat) p.char.setLook(info.color, info.hat);
      if (p.info.name !== info.name || p.info.color !== info.color) {
        p.label.removeFromParent();
        p.label = makeLabel(info.name, info.color);
        p.char.root.add(p.label);
      }
      p.info = info;
    }
  }
  for (const [id, p] of players) {
    if (seen.has(id)) continue;
    p.char.dispose();
    p.shadow.removeFromParent();
    players.delete(id);
  }
}

// ---------- scènes ----------
function setGame(g: ClientGame, init: any) {
  if (game) { try { game.onExit(); } catch (e) { console.error(e); } }
  world.traverse((o) => {
    const m = o as THREE.Mesh;
    m.geometry?.dispose?.();
    for (const mat of Array.isArray(m.material) ? m.material : m.material ? [m.material] : []) mat.dispose();
  });
  world.clear();
  hud.replaceChildren();
  active = true; spectate = null; aimMode = false; charging = false;
  for (const p of players.values()) { p.pin = null; p.hidden = false; }
  gfx.sea.set(null);
  game = g;
  g.onEnter(ctx, init);
  shadowify(world);
}

function teleport(p: Vec3) {
  body.p = [p[0], p[1], p[2]];
  body.v = [0, 0, 0];
  body.tumble = 0;
  clearMotionState(body); // tyrolienne, vol, speed pad… oubliés
}

function enterLobby() {
  phase = 'lobby';
  ctx.startAt = 0;
  setGame(createLobbyScene(), null);
  for (const p of players.values()) p.char.resetDamage();
  const a = Math.random() * Math.PI * 2;
  teleport([Math.sin(a) * 3, 1, Math.cos(a) * 3 - 4]);
  camYaw = Math.PI;
  overlay.style.display = 'none';
  banner.style.display = 'none';
}

function updateChrome() {
  lobbyEl.style.display = phase === 'lobby' && !waiting ? 'block' : 'none';
  waitEl.style.display = waiting ? 'flex' : 'none';
  stopBtn.style.display = lobby && lobby.hostId === net.id && phase !== 'lobby' && phase !== 'boot' ? 'block' : 'none';
  $('corner').textContent = phase === 'lobby' ? '' : 'Z Q S D : bouger · Espace : sauter · Souris : caméra · Échap : libérer la souris';
}
stopBtn.onclick = () => net.send({ t: 'stop' });

// ---------- écran de chargement ----------
// Reste au moins 1,6 s après l'ouverture de la page, puis s'efface dès qu'on a le lobby (ou une erreur).
function hideSplash() {
  const sp = document.getElementById('splash');
  if (!sp || sp.dataset.out) return;
  sp.dataset.out = '1';
  setTimeout(() => { sp.classList.add('out'); setTimeout(() => sp.remove(), 600); }, Math.max(0, 1600 - performance.now()));
}

// ---------- réseau ----------
net.onClose = () => {
  hideSplash();
  overlay.style.display = 'flex';
  overlay.firstElementChild!.innerHTML = '<h1>Connexion perdue</h1><p>Le serveur ne répond plus. Recharge la page pour te reconnecter.</p>';
};

net.onMessage = (m) => {
  switch (m.t) {
    case 'welcome':
      ctx.myId = m.id;
      break;
    case 'lobby': {
      hideSplash();
      lobby = m;
      syncPlayers(m.players);
      if (m.phase === 'lobby') {
        waiting = false;
        if (phase !== 'lobby') enterLobby();
        renderLobby(lobbyEl, m, net.id, {
          profile: (p) => {
            Object.assign(profile, p);
            localStorage.setItem('jeux-profil', JSON.stringify(profile));
            net.send({ t: 'profile', ...p });
          },
          settings: (s) => net.send({ t: 'settings', settings: s }),
          bots: (n) => net.send({ t: 'bots', n }),
          start: () => net.send({ t: 'start' }),
          quality: { high: HIGH, toggle: toggleQuality },
        });
        // ?bots=N : remplit le lobby de bots pour tester seul
        const want = Number(new URLSearchParams(location.search).get('bots'));
        if (!botsApplied && want > 0 && m.hostId === net.id) { botsApplied = true; net.send({ t: 'bots', n: want }); }
      } else if (phase === 'boot') enterLobby();
      updateChrome();
      break;
    }
    case 'wait':
      waiting = true;
      updateChrome();
      break;
    case 'round': {
      const factory = clientGames[m.gameId];
      if (!factory) break;
      waiting = false;
      phase = 'round';
      overlay.style.display = 'none';
      for (const p of players.values()) p.char.resetDamage();
      ctx.startAt = m.startAt;
      const s = m.spawns[net.id];
      if (s) teleport(s);
      body.superJump = 0; body.shield = 0; // les objets de la manche précédente ne survivent pas
      setGame(factory(), m.init);
      const meta = lobby?.metas.find((g) => g.id === m.gameId);
      banner.style.display = 'flex';
      banner.querySelector('.title')!.textContent = meta?.name ?? m.gameId;
      banner.querySelector('.sub')!.textContent = `Manche ${m.index + 1}/${m.total} — ${meta?.description ?? ''}`;
      lastCount = -1;
      updateChrome();
      break;
    }
    case 'roundEnd': {
      phase = 'scores';
      document.exitPointerLock?.();
      renderScores(overlay.firstElementChild as HTMLElement, m, lobby?.players ?? [], net.id, lobby?.metas.find((g) => g.id === m.gameId)?.name ?? m.gameId);
      overlay.style.display = 'flex';
      banner.style.display = 'none';
      break;
    }
    case 'podium': {
      phase = 'podium';
      overlay.style.display = 'none';
      const order = Object.entries(m.totals).sort((a, b) => b[1] - a[1]).map(([id]) => id).filter((id) => players.has(id));
      setGame(createPodiumScene(order), null);
      renderPodium(hud, m.totals, lobby?.players ?? [], net.id, lobby?.hostId === net.id, () => net.send({ t: 'toLobby' }));
      updateChrome();
      break;
    }
    case 'states':
      for (const s of m.s) {
        const p = players.get(s[0]);
        if (p) p.net = { p: [s[1], s[2], s[3]], yaw: s[4], flags: s[5], v: [s[6], s[7], s[8]] };
      }
      break;
    case 'game':
      if (phase === 'round' && game) game.onMessage(m.m);
      break;
    case 'damage': {
      const p = players.get(m.id);
      if (!p) break;
      p.char.addHit(m.hit.pos, m.hit.r);
      const w = p.char.root.localToWorld(new THREE.Vector3(...m.hit.pos));
      particles.burst([w.x, w.y, w.z], 8, [p.info.color, 0xffffff], 4, 0.1, 0.6);
      if (m.id === net.id) sfx.hurt();
      break;
    }
    case 'heal':
      players.get(m.id)?.char.heal(m.n);
      break;
    case 'impulse':
      body.v = [m.v[0], m.v[1], m.v[2]];
      body.tumble = m.tumble;
      body.grounded = false;
      body.coyote = 0;
      shake = Math.max(shake, 0.6);
      break;
    case 'teleport':
      teleport(m.p);
      break;
  }
};

net.connect({ t: 'hello', ...profile });

// ---------- boucle ----------
const lerpAngle = (a: number, b: number, k: number) => a + Math.atan2(Math.sin(b - a), Math.cos(b - a)) * k;
let last = performance.now();
const tmp = new THREE.Vector3();

function frame(tms: number) {
  requestAnimationFrame(frame);
  const dt = Math.min(0.05, Math.max(0.001, (tms - last) / 1000));
  last = tms;
  const now = net.now();

  // caméra : souris, ou flèches du clavier
  camYaw -= input.dx * 0.0028 + ((input.down('ArrowRight') ? 1 : 0) - (input.down('ArrowLeft') ? 1 : 0)) * 2 * dt;
  camPitch += input.dy * 0.0022 + ((input.down('ArrowUp') ? 1 : 0) - (input.down('ArrowDown') ? 1 : 0)) * 1.2 * dt;
  camPitch = Math.min(1.3, Math.max(-0.3, camPitch));

  const me = players.get(net.id);
  if (game) {
    cols = game.colliders(now);
    if (active) {
      const frozen = phase === 'round' && now < ctx.startAt;
      const f = (input.down('KeyW') ? 1 : 0) - (input.down('KeyS') ? 1 : 0);
      const r = (input.down('KeyD') ? 1 : 0) - (input.down('KeyA') ? 1 : 0);
      const fx = Math.sin(camYaw), fz = Math.cos(camYaw);
      let mx = fx * f - fz * r, mz = fz * f + fx * r;
      const len = Math.hypot(mx, mz);
      if (len > 1) { mx /= len; mz /= len; }
      if (frozen) { mx = 0; mz = 0; }
      const jump = !frozen && input.down('Space');
      acc = Math.min(acc + dt, 4 * H);
      while (acc >= H) {
        acc -= H;
        game.preStep?.(body, H);
        const contacts = stepBody(body, { mx, mz, jump }, cols, H);
        for (const p of players.values()) {
          if (p === me || p.pin || p.hidden || p.char.dead) continue;
          // le jeu peut gérer lui-même le contact entre joueurs (parcours : bousculades réglables) ; sinon on s'écarte simplement
          if (game.jostle) { if (game.jostle(body, [p.pos.x, p.pos.y, p.pos.z], p.net.v)) { sfx.hit(); shake = Math.max(shake, 0.4); } }
          else pushApart(body, [p.pos.x, p.pos.y, p.pos.z]);
        }
        game.postStep?.(body, contacts, H);
        if (body.jumped) sfx.jump();
        if (body.landed > 9) sfx.land();
      }
      if (aimMode) myYaw = lerpAngle(myYaw, camYaw, 1 - Math.exp(-18 * dt));
      else if (mx || mz) myYaw = lerpAngle(myYaw, Math.atan2(mx, mz), 1 - Math.exp(-14 * dt));
    }
  }
  if (me && !me.pin) {
    me.pos.set(body.p[0], body.p[1], body.p[2]);
    me.yaw = myYaw;
    me.flags = (body.grounded || body.coyote > 0 ? FLAG.grounded : 0) | (body.tumble > 0 ? FLAG.tumble : 0) | (charging ? FLAG.charging : 0) | poseFlags(body);
  }

  sendAcc += dt;
  if (sendAcc >= 1 / 30 && net.id) {
    sendAcc = 0;
    const r = (x: number) => Math.round(x * 100) / 100;
    net.send({ t: 'state', s: [r(body.p[0]), r(body.p[1]), r(body.p[2]), r(myYaw), me?.flags ?? 0, r(body.v[0]), r(body.v[1]), r(body.v[2])] });
  }

  for (const p of players.values()) {
    const mine = p === me;
    let speed: number, vy: number, flags: number, dance = false;
    if (p.pin) {
      p.pos.set(p.pin.p[0], p.pin.p[1], p.pin.p[2]);
      p.yaw = p.pin.yaw;
      speed = 0; vy = 0; flags = FLAG.grounded; dance = p.pin.dance;
    } else if (mine) {
      speed = Math.hypot(body.v[0] - body.groundVel[0], body.v[2] - body.groundVel[2]);
      vy = body.v[1]; flags = p.flags;
    } else {
      // autres joueurs : on glisse vers la dernière position reçue, légèrement extrapolée
      const n = p.net;
      tmp.set(n.p[0] + n.v[0] * 0.05, n.p[1] + n.v[1] * 0.05, n.p[2] + n.v[2] * 0.05);
      if (p.pos.distanceToSquared(tmp) > 36) p.pos.copy(tmp);
      else p.pos.lerp(tmp, 1 - Math.exp(-16 * dt));
      p.yaw = lerpAngle(p.yaw, n.yaw, 1 - Math.exp(-12 * dt));
      speed = Math.hypot(n.v[0], n.v[2]); vy = n.v[1]; flags = n.flags;
      p.flags = flags;
    }
    const root = p.char.root;
    root.visible = !p.hidden && (!waiting || mine) && phase !== 'boot';
    root.position.copy(p.pos);
    root.rotation.y = p.yaw;
    if (root.visible) p.char.update(dt, { speed, vy, grounded: !!(flags & FLAG.grounded), tumble: !!(flags & FLAG.tumble), charging: !!(flags & FLAG.charging), dance, ...(!p.pin && game?.pose?.(p.info.id, p.pos, mine, flags)) });
    // ombre « blob » projetée sur le sol le plus proche en dessous
    const gy = root.visible && !HIGH ? groundBelow(p.pos.x, p.pos.y + 0.3, p.pos.z, cols) : -Infinity;
    // en graphismes élevés, les vraies ombres remplacent l'ombre « blob »
    p.shadow.visible = !HIGH && gy > -Infinity && p.pos.y - gy < 12;
    if (p.shadow.visible) {
      p.shadow.position.set(p.pos.x, gy + 0.03, p.pos.z);
      p.shadow.scale.setScalar(Math.max(0.35, 1 - (p.pos.y - gy) * 0.08));
    }
  }

  // caméra troisième personne
  const dist = spectate ? spectate.dist : 7;
  if (spectate) tmp.set(spectate.target[0], spectate.target[1], spectate.target[2]);
  else tmp.set(body.p[0], body.p[1] + 1.3, body.p[2]);
  if (camTarget.distanceToSquared(tmp) > 900) camTarget.copy(tmp);
  else camTarget.lerp(tmp, 1 - Math.exp(-14 * dt));
  const ch = Math.cos(camPitch) * dist;
  camera.position.set(camTarget.x - Math.sin(camYaw) * ch, camTarget.y + Math.sin(camPitch) * dist + 0.4, camTarget.z - Math.cos(camYaw) * ch);
  if (shake > 0.01) {
    camera.position.x += (Math.random() - 0.5) * shake;
    camera.position.y += (Math.random() - 0.5) * shake;
    shake *= Math.exp(-7 * dt);
  }
  camera.lookAt(camTarget.x, camTarget.y + 0.4, camTarget.z);

  if (game) { try { game.onFrame(dt); } catch (e) { console.error(e); } }

  // compte à rebours de début de manche
  if (phase === 'round' && banner.style.display !== 'none') {
    const left = ctx.startAt - now;
    const count = banner.querySelector('.count')!;
    const n = Math.ceil(left);
    if (n !== lastCount) {
      lastCount = n;
      if (n > 0 && n <= 3) { count.textContent = String(n); sfx.tick(); }
      else if (n <= 0) { count.textContent = 'GO !'; sfx.go(); }
      else count.textContent = '';
    }
    if (left < -0.8) banner.style.display = 'none';
  }

  particles.update(dt);
  clouds.rotation.y += dt * 0.004;
  gfx.follow(camTarget);
  gfx.sea.update(now, camTarget.x, camTarget.z);
  gfx.sky.mesh.position.copy(camera.position);
  gfx.render();
  input.endFrame();
}
requestAnimationFrame(frame);

// accès pratique depuis la console pour le débogage
(window as any).jeux = { body, players, net, ctx, get phase() { return phase; }, get game() { return game; } };
