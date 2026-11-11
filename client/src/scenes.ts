// Scènes intégrées au cœur : le terrain de jeu du lobby et le podium final. Elles suivent le même contrat que les mini-jeux.
import * as THREE from 'three';
import type { Collider } from '../../shared/src/physics';
import type { ClientCtx, ClientGame } from './api';
import { balloon, mat, mesh, rbox, sign, slab, tex, tree } from './gfx';

const PARTY = [0xff4d6d, 0xffd60a, 0x70e000, 0x00b4d8, 0x9d4edd, 0xff9f1c];

/** Pose un décor à l'emplacement exact d'une boîte de collision. */
function place(scene: THREE.Object3D, o: THREE.Object3D, c: Collider): THREE.Object3D {
  o.position.set(c.c[0], c.c[1], c.c[2]);
  o.rotation.y = c.yaw;
  scene.add(o);
  return o;
}

/** Lobby : un terrain de jeu où l'on court et saute en attendant que l'hôte lance la partie. */
export function createLobbyScene(): ClientGame {
  let ctx: ClientCtx;
  const cols: Collider[] = [
    { id: 0, c: [0, -0.75, 0], h: [16, 0.75, 16], yaw: 0 },
    { id: 1, c: [6, 0.25, 6], h: [1.5, 0.25, 1.5], yaw: 0, bounce: 15 },
    { id: 2, c: [-6, 0.5, 5], h: [1.5, 0.5, 1.5], yaw: 0.4 },
    { id: 3, c: [-8.5, 1, 7.5], h: [1.5, 1, 1.5], yaw: 0.4 },
    { id: 4, c: [-11, 1.5, 10], h: [1.5, 1.5, 1.5], yaw: 0.4 },
    { id: 5, c: [7, 0.45, -7], h: [3, 0.3, 0.3], yaw: 0, angVel: 1.4 },
  ];
  // troncs des arbres aux quatre coins
  [[-13, -13], [13, -13], [-13.5, 13.5], [13, 12]].forEach(([x, z], i) => cols.push({ id: 10 + i, c: [x, 1, z], h: [0.3, 1, 0.3], yaw: 0 }));
  let bar: THREE.Object3D;
  const balloons: THREE.Object3D[] = [];
  return {
    onEnter(c) {
      ctx = c;
      ctx.setSky(0x7cc8ff);
      ctx.setSea(-9, 0x1fb6e0);
      const s = ctx.scene;
      place(s, slab(32, 1.5, 32, 0x7ddc6a, { top: 0xffffff, topMap: tex.soft('#8fe07a', '#a8ec8c', 4, 4) }), cols[0]);

      // trampoline : socle + toile cible
      const tr = place(s, new THREE.Group(), cols[1]);
      mesh(rbox(3, 0.5, 3, 0.2), mat(0x4361ee), 0, 0, 0, tr);
      const pad = mesh(new THREE.CylinderGeometry(1.25, 1.25, 0.06, 32), mat(0xffffff, { map: tex.target('#ffd60a', '#ff4d6d') }), 0, 0.27, 0, tr);
      pad.name = 'toile';

      // marches de couleurs
      [0xffc971, 0xff8fab, 0xcdb4db].forEach((color, i) => {
        const col = cols[2 + i];
        place(s, slab(col.h[0] * 2, col.h[1] * 2, col.h[2] * 2, color, { under: false }), col);
      });

      // barre tournante rembourrée sur son axe
      bar = place(s, new THREE.Group(), cols[5]);
      const padBar = mesh(new THREE.CapsuleGeometry(0.3, 5.4, 6, 16), mat(0xffffff, { map: tex.stripes('#ff4d6d', '#ffffff', 1, 6) }), 0, 0, 0, bar);
      padBar.rotation.z = Math.PI / 2;
      mesh(new THREE.CylinderGeometry(0.28, 0.4, 0.5, 16), mat(0x495057, { metal: 0.6, rough: 0.3 }), 7, 0.2, -7, s);

      // arbres, pancarte et ballons
      for (let i = 0; i < 4; i++) {
        const t = tree(3.2 + (i % 2) * 0.8, i % 2 ? 0x52d681 : 0x3bc47a);
        t.position.set(cols[6 + i].c[0], 0, cols[6 + i].c[2]);
        s.add(t);
      }
      const board = sign('JEUX', 7, 2.2, '#ff4d6d', '#ffd60a');
      board.position.set(0, 4, -14.5);
      s.add(board);
      for (const x of [-3, 3]) mesh(new THREE.CylinderGeometry(0.14, 0.14, 4, 10), mat(0xffffff), x, 2, -14.6, s);
      for (let i = 0; i < 12; i++) {
        const b = balloon(PARTY[i % PARTY.length]);
        const a = (i / 12) * Math.PI * 2;
        b.position.set(Math.sin(a) * (19 + (i % 3) * 3), 4 + (i % 4) * 2.2, Math.cos(a) * (19 + (i % 3) * 3));
        b.userData.y = b.position.y;
        s.add(b);
        balloons.push(b);
      }
      for (const x of [-2.6, 2.6]) {
        const b = balloon(x < 0 ? 0xffd60a : 0x00b4d8);
        b.position.set(x * 1.45, 6.6, -14.5);
        b.userData.y = 6.6;
        s.add(b);
        balloons.push(b);
      }
    },
    onMessage() {},
    onFrame() {
      const t = ctx.now();
      cols[5].yaw = t * 1.4;
      bar.rotation.y = cols[5].yaw;
      balloons.forEach((b, i) => { b.position.y = b.userData.y + Math.sin(t * 0.8 + i) * 0.4; b.rotation.z = Math.sin(t * 0.6 + i * 2) * 0.12; });
      if (ctx.body.p[1] < -9) { ctx.body.p = [0, 3, 0]; ctx.body.v = [0, 0, 0]; }
    },
    onExit() {},
    colliders: () => cols,
  };
}

/** Podium final : les trois premiers dansent sous les confettis et les projecteurs. */
export function createPodiumScene(ranking: string[]): ClientGame {
  let ctx: ClientCtx;
  let confetti = 0;
  const cols: Collider[] = [{ id: 0, c: [0, -0.75, 0], h: [14, 0.75, 14], yaw: 0 }];
  const steps: [number, number, number][] = [[0, 2, 0xffd60a], [-2.3, 1.4, 0xd5dbe3], [2.3, 0.9, 0xe0915a]];
  const beams: THREE.Mesh[] = [];
  return {
    onEnter(c) {
      ctx = c;
      ctx.setSky(0x6a4cff);
      ctx.setSea(-9, 0xc34bff);
      const s = ctx.scene;
      const floor = new THREE.Group();
      mesh(new THREE.CylinderGeometry(14, 13, 1.5, 64), mat(0xff8fab, { rough: 0.25 }), 0, 0, 0, floor);
      mesh(new THREE.CylinderGeometry(9, 9, 0.04, 64), mat(0xffb3c6, { rough: 0.2 }), 0, 0.76, 0, floor);
      mesh(new THREE.TorusGeometry(13.6, 0.22, 10, 64), mat(0xffd60a, { glow: 0.6 }), 0, 0.7, 0, floor).rotation.x = Math.PI / 2;
      place(s, floor, cols[0]);
      steps.forEach(([x, h, color], i) => {
        mesh(new THREE.CylinderGeometry(1.05, 1.15, h, 32), mat(color, { rough: 0.22, metal: i === 0 ? 0.35 : 0.2 }), x, h / 2, 0, s);
        const n = sign(String(i + 1), 0.9, 0.9, '#2b2140', '#ffffff');
        n.position.set(x, h * 0.55, 1.16);
        n.scale.z = 0.2;
        s.add(n);
      });
      // projecteurs
      [0xfff3b0, 0x9bf6ff, 0xffadad].forEach((color, i) => {
        const beam = mesh(new THREE.ConeGeometry(2.4, 16, 24, 1, true), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.13, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending }), steps[i][0], 8 + steps[i][1], 0, s);
        beam.userData.noShadow = true;
        beams.push(beam);
      });
      for (let i = 0; i < 10; i++) {
        const b = balloon(PARTY[i % PARTY.length]);
        const a = (i / 10) * Math.PI * 2;
        b.position.set(Math.sin(a) * 12, 3 + (i % 3) * 1.5, Math.cos(a) * 12);
        s.add(b);
      }
      ranking.forEach((id, i) => {
        const p = ctx.players.get(id);
        if (!p) return;
        p.char.resetDamage();
        if (i < 3) p.pin = { p: [steps[i][0], steps[i][1], 0], yaw: 0, dance: true };
        else {
          const a = ((i - 3) / Math.max(1, ranking.length - 3) - 0.5) * 2.2;
          p.pin = { p: [Math.sin(a) * 6, 0, 3.5 + Math.cos(a) * 1.5], yaw: Math.PI + a, dance: false };
        }
      });
      ctx.setActive(false);
      ctx.setSpectate([0, 1.8, 0], 9);
      ctx.setCamYaw(Math.PI);
      ctx.sfx.win();
    },
    onMessage() {},
    onFrame(dt) {
      const t = ctx.now();
      beams.forEach((b, i) => { b.rotation.z = Math.sin(t * 1.1 + i * 2) * 0.12; b.rotation.x = Math.cos(t * 0.9 + i) * 0.08; });
      confetti -= dt;
      if (confetti < 0) {
        confetti = 0.05;
        for (let i = 0; i < 3; i++) {
          ctx.particles.emit((Math.random() - 0.5) * 12, 8 + Math.random() * 2, (Math.random() - 0.5) * 8, (Math.random() - 0.5) * 2, -1, (Math.random() - 0.5) * 2, PARTY[Math.floor(Math.random() * PARTY.length)], 0.16, 4, 2.5);
        }
      }
    },
    onExit() {
      for (const p of ctx.players.values()) p.pin = null;
      ctx.setActive(true);
      ctx.setSpectate(null);
    },
    colliders: () => cols,
  };
}
