// Abri & mortier — côté client : îles, blocs instanciés, visée, obus, explosions, caisses, zone, HUD.
import * as THREE from 'three';
import { esc, type ClientCtx, type ClientGame } from '../../client/src/api';
import { mat as pm, mesh, rbox, rockUnder, shadowify, tex, tree } from '../../client/src/gfx';
import type { Collider, Vec3 } from '../../shared/src/physics';
import {
  M, MATS, MAT_KEYS, blockCenter, blockKey, cellAt, columnHeight, launch, mortarColliders, plotCenter, plotYaw, shellAt, shellRange, zoneRadius,
  type Block, type CrateKind, type Mat, type MortarInit, type ShellKind,
} from './shared';

const SHELL_COLOR: Record<ShellKind, number> = { normal: 0x2b2140, mega: 0xd00000, cluster: 0xff9f1c, sub: 0xff9f1c };
const CRATE_INFO: Record<CrateKind, { color: number; name: string }> = {
  mega: { color: 0xd00000, name: 'Méga-obus' },
  cluster: { color: 0xff9f1c, name: 'Obus à fragmentation' },
  repair: { color: 0x70e000, name: 'Réparation' },
};

export function createMortarClient(): ClientGame {
  let ctx: ClientCtx;
  let init: MortarInit;
  let n = 0;
  let myPlot = 0;
  let budget = 0;
  let mat: Mat = 'wood';
  let ammo: ShellKind = 'normal';
  let chargeStart = -1;
  let lastFire = -10;
  let dirty = true;
  let cols: Collider[] = [];
  let hudTimer = 0;
  let announced = false;
  const blocks = new Map<string, Block>();
  const hp = new Map<string, number>();
  const dead = new Set<string>();
  const shells = new Map<number, { mesh: THREE.Mesh; p: Vec3; v: Vec3; at: number; kind: ShellKind }>();
  const crates = new Map<number, { mesh: THREE.Mesh; p: Vec3; landAt: number; kind: CrateKind }>();
  const inst = {} as Record<Mat, THREE.InstancedMesh>;
  const tubes: THREE.Object3D[] = [];
  const rings: THREE.Mesh[] = [];
  let ghost: THREE.Mesh, marker: THREE.Mesh, grid: THREE.GridHelper;
  let top: HTMLElement, side: HTMLElement, bottom: HTMLElement;
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), v3 = new THREE.Vector3(), one = new THREE.Vector3(1, 1, 1);

  function rebuild() {
    const counts: Record<Mat, number> = { wood: 0, stone: 0, tramp: 0 };
    for (const b of blocks.values()) {
      const c = blockCenter(b, n);
      q.setFromAxisAngle(THREE.Object3D.DEFAULT_UP, plotYaw(b.plot, n));
      m4.compose(v3.set(c[0], c[1], c[2]), q, one);
      inst[b.mat].setMatrixAt(counts[b.mat]++, m4);
    }
    for (const k of MAT_KEYS) {
      inst[k].count = counts[k];
      inst[k].instanceMatrix.needsUpdate = true;
    }
    dirty = true;
  }

  function removeBlocks(keys: string[]) {
    for (const key of keys) {
      const b = blocks.get(key);
      if (!b) continue;
      blocks.delete(key);
      ctx.particles.burst(blockCenter(b, n), 8, [MATS[b.mat].color], 5, 0.22, 0.8);
    }
    rebuild();
  }

  function explosion(p: Vec3, r: number, kind: ShellKind) {
    ctx.particles.burst(p, kind === 'mega' ? 70 : 34, [0xffd60a, 0xff9f1c, 0xff4d6d, 0xffffff], r * 4.5, 0.3, 0.7, 10);
    ctx.particles.burst(p, 14, [0x6c757d, 0x495057], r * 2, 0.45, 1.3, 2, 0.8);
    const d = Math.hypot(p[0] - ctx.body.p[0], p[1] - ctx.body.p[1], p[2] - ctx.body.p[2]);
    ctx.sfx.boom(Math.max(0.15, Math.min(1, 14 / (d + 4))) * (kind === 'mega' ? 1.3 : 1));
    if (d < 14) ctx.shake((1 - d / 14) * (kind === 'mega' ? 1.1 : 0.7));
    // éclair : sphère qui gonfle puis disparaît
    const flash = new THREE.Mesh(new THREE.SphereGeometry(1, 20, 14), new THREE.MeshBasicMaterial({ color: 0xffe28a, transparent: true, opacity: 0.9 }));
    flash.position.set(p[0], p[1], p[2]);
    flash.userData = { life: 0.28, max: 0.28, r, noShadow: true };
    const wave = new THREE.Mesh(new THREE.TorusGeometry(1, 0.07, 8, 40).rotateX(Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.8 }));
    wave.position.set(p[0], Math.max(0.15, p[1]), p[2]);
    wave.userData = { life: 0.45, max: 0.45, r: r * 1.5, noShadow: true, wave: true };
    ctx.scene.add(flash, wave);
    flashes.push(flash, wave);
  }
  const flashes: THREE.Mesh[] = [];

  /** Case visée : 1,6 m devant le joueur, dans la direction de la caméra. */
  function aimCell(): { x: number; z: number; y: number } | null {
    const yaw = ctx.camYaw(), b = ctx.body.p;
    const cell = cellAt(myPlot, n, b[0] + Math.sin(yaw) * 1.6, b[2] + Math.cos(yaw) * 1.6);
    return cell ? { ...cell, y: columnHeight(blocks, myPlot, cell.x, cell.z) } : null;
  }

  return {
    onEnter(c, i: MortarInit) {
      ctx = c;
      init = i;
      n = init.n;
      myPlot = init.plots[ctx.myId] ?? 0;
      budget = init.budget;
      ctx.setSky(0x86ccff);
      ctx.setAimMode(true);
      ctx.setCamYaw(plotYaw(myPlot, n) + Math.PI); // face au centre de l'arène

      ctx.setSea(-9.5, 0x2a86e8);
      const owners = new Map(Object.entries(init.plots).map(([id, p]) => [p, id]));
      const grassTex = tex.soft('#7fdc6b', '#92e67c', 3, 3);
      for (let p = 0; p < n; p++) {
        const ctr = plotCenter(p, n), g = new THREE.Group();
        g.position.set(ctr[0], 0, ctr[2]);
        g.rotation.y = plotYaw(p, n);
        const S = M.island;
        mesh(rbox(S + 0.3, 0.5, S + 0.3, 0.24), pm(0xffffff, { map: grassTex, rough: 0.7 }), 0, -0.25, 0, g);
        mesh(rbox(S, M.thick - 0.4, S, 0.3), pm(0xb08968, { rough: 0.85 }), 0, -0.4 - (M.thick - 0.4) / 2, 0, g);
        const rock = rockUnder(S * 0.98, 6, S * 0.98, 0x8a5a3c, p * 7);
        rock.position.y = -M.thick + 0.1;
        g.add(rock);
        // cadre lumineux de la zone constructible, à la couleur du propriétaire
        const color = ctx.players.get(owners.get(p) ?? '')?.info.color ?? 0xffffff;
        const frame = pm(color, { glow: 0.9 });
        const half = M.grid / 2 + 0.1;
        for (const sgn of [-1, 1]) {
          mesh(rbox(M.grid + 0.4, 0.08, 0.14, 0.04), frame, 0, 0.04, sgn * half, g);
          mesh(rbox(0.14, 0.08, M.grid + 0.4, 0.04), frame, sgn * half, 0.04, 0, g);
        }
        // drapeau, buissons et cailloux sur le pourtour (hors de la zone constructible)
        mesh(new THREE.CylinderGeometry(0.06, 0.06, 3, 8), pm(0xffffff), 5.3, 1.5, 5.3, g);
        mesh(rbox(1.1, 0.7, 0.06, 0.03), pm(color, { rough: 0.5 }), 4.7, 2.6, 5.3, g);
        const bush = new THREE.SphereGeometry(1, 12, 9), stone = new THREE.DodecahedronGeometry(1, 1);
        for (let k = 0; k < 7; k++) {
          const a = ((k * 2.399 + p) % 4) | 0, u = ((k * 3.7 + p * 1.3) % 9) - 4.5, side = 5.3;
          const [x, z] = a === 0 ? [u, side] : a === 1 ? [u, -side] : a === 2 ? [side, u] : [-side, u];
          if (k % 3 === 0) mesh(stone, pm(0xaab3bd, { rough: 0.8 }), x, 0.15, z, g).scale.set(0.35, 0.25, 0.3);
          else mesh(bush, pm(k % 2 ? 0x3fbf6f : 0x55d07f, { rough: 0.8 }), x, 0.25, z, g).scale.set(0.5, 0.38, 0.45);
        }
        if (p % 2 === 0) { const t = tree(2.4); t.position.set(-5.3, 0, 5.3); g.add(t); }
        ctx.scene.add(g);
        const ring = new THREE.Mesh(new THREE.TorusGeometry(1, 0.012, 6, 72).rotateX(Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xff2a6d }));
        ring.position.set(ctr[0], 0.12, ctr[2]);
        ring.visible = false;
        ring.userData.noShadow = true;
        ctx.scene.add(ring);
        rings.push(ring);
      }
      const cap = Math.max(16, n * (init.budget + 2));
      const blockGeo = rbox(0.98, 0.98, 0.98, 0.1);
      const maps = { wood: tex.planks(), stone: tex.stone(), tramp: tex.target('#39c5ff', '#ffffff') };
      for (const k of MAT_KEYS) {
        inst[k] = new THREE.InstancedMesh(blockGeo, pm(0xffffff, { map: maps[k], rough: k === 'stone' ? 0.8 : 0.5 }), cap);
        inst[k].count = 0;
        inst[k].frustumCulled = false;
        ctx.scene.add(inst[k]);
      }
      ghost = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.45, depthWrite: false }));
      ghost.rotation.y = plotYaw(myPlot, n);
      ghost.visible = false;
      marker = new THREE.Mesh(new THREE.RingGeometry(0.7, 1, 36).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xff2a6d, side: THREE.DoubleSide, depthTest: false, transparent: true }));
      marker.visible = false;
      marker.renderOrder = 5;
      grid = new THREE.GridHelper(M.grid, M.grid, 0xffffff, 0xffffff);
      const mc = plotCenter(myPlot, n);
      grid.position.set(mc[0], 0.06, mc[2]);
      grid.rotation.y = plotYaw(myPlot, n);
      (grid.material as THREE.Material).transparent = true;
      (grid.material as THREE.Material).opacity = 0.6;
      ctx.scene.add(ghost, marker, grid);

      // chaque personnage porte son mortier
      for (const [id, p] of ctx.players) {
        if (!(id in init.plots)) continue;
        hp.set(id, init.hp);
        const tube = new THREE.Mesh(new THREE.CylinderGeometry(0.13, 0.17, 0.7, 16), pm(0x343a40, { metal: 0.7, rough: 0.3 }));
        tube.castShadow = true;
        mesh(new THREE.TorusGeometry(0.14, 0.035, 8, 16), pm(0xffd60a, { metal: 0.4, rough: 0.3 }), 0, 0.33, 0, tube).rotation.x = Math.PI / 2;
        tube.position.set(0.42, 0.85, 0.2);
        tube.rotation.x = Math.PI / 2 - M.elev;
        p.char.root.add(tube);
        tubes.push(tube);
      }
      top = document.createElement('div'); top.className = 'top card';
      side = document.createElement('div'); side.className = 'side card';
      bottom = document.createElement('div'); bottom.className = 'bottom card';
      ctx.hud.append(top, side, bottom);
    },

    colliders() {
      if (dirty) { cols = mortarColliders(n, blocks.values(), myPlot); dirty = false; }
      return cols;
    },

    postStep(_b, contacts) {
      if (contacts.some((c) => c.bounced)) ctx.sfx.boing();
    },

    onMessage(m) {
      switch (m.t) {
        case 'block': {
          const b = m.b as Block;
          blocks.set(blockKey(b.plot, b.x, b.y, b.z), b);
          rebuild();
          if (m.by === ctx.myId) { budget = m.budget; ctx.sfx.place(); }
          break;
        }
        case 'unblock':
          removeBlocks(m.keys);
          if (m.by === ctx.myId) { budget = m.budget; ctx.sfx.remove(); }
          break;
        case 'shell': {
          const kind = m.kind as ShellKind;
          const shell = new THREE.Mesh(new THREE.SphereGeometry(kind === 'mega' ? 0.42 : kind === 'sub' ? 0.16 : 0.24, 18, 12), pm(SHELL_COLOR[kind], { rough: 0.2, metal: 0.5 }));
          // mèche incandescente, bien visible de loin grâce au bloom
          mesh(new THREE.SphereGeometry(0.4, 8, 6), pm(0xffb703, { glow: 3 }), 0, 1, 0, shell);
          shadowify(shell);
          ctx.scene.add(shell);
          shells.set(m.id, { mesh: shell, p: m.p, v: m.v, at: m.at, kind });
          if (kind !== 'sub') ctx.sfx.fire();
          break;
        }
        case 'bounce': {
          const s = shells.get(m.id);
          if (s) { s.p = m.p; s.v = m.v; s.at = m.at; }
          ctx.sfx.boing();
          break;
        }
        case 'gone':
        case 'boom': {
          const s = shells.get(m.id);
          if (s) { s.mesh.removeFromParent(); shells.delete(m.id); }
          if (m.t === 'boom') { explosion(m.p, m.r, m.kind); removeBlocks(m.removed); }
          break;
        }
        case 'hp':
          hp.set(m.id, m.hp);
          break;
        case 'dead': {
          dead.add(m.id);
          hp.set(m.id, 0);
          const p = ctx.players.get(m.id);
          if (p) {
            if (m.cause === 'hp') { p.char.die(); ctx.sfx.xylo(); }
            else p.hidden = true;
          }
          if (m.id === ctx.myId) {
            ctx.setActive(false);
            ctx.setCharging(false);
            ctx.setSpectate([0, 3, 0], Math.max(18, plotCenter(0, n)[2] * 1.6));
            ctx.toast(m.cause === 'hp' ? '💀 Tu n\'es plus qu\'un tas d\'os !' : '🕳 Tombé dans le vide !', 3);
          } else if (p) ctx.toast(`${p.info.name} est éliminé !`, 1.5);
          break;
        }
        case 'ammo':
          ammo = m.kind;
          break;
        case 'crate': {
          const kind = m.kind as CrateKind;
          const crate = new THREE.Mesh(rbox(0.8, 0.8, 0.8, 0.12), pm(CRATE_INFO[kind].color, { rough: 0.35 }));
          mesh(rbox(0.86, 0.2, 0.86, 0.06), pm(0xffffff), 0, 0, 0, crate);
          mesh(rbox(0.2, 0.86, 0.86, 0.06), pm(0xffffff), 0, 0, 0, crate);
          // parachute, replié à l'atterrissage
          const chute = new THREE.Group();
          chute.name = 'parachute';
          mesh(new THREE.SphereGeometry(1.1, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), pm(0xffffff, { map: tex.stripes('#ffffff', '#ff4d6d', 6, 1), side: THREE.DoubleSide }), 0, 1.3, 0, chute);
          for (const [x, z] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
            const line = mesh(new THREE.CylinderGeometry(0.012, 0.012, 1.45, 4), new THREE.MeshBasicMaterial({ color: 0xffffff }), x * 0.5, 0.95, z * 0.5, chute);
            line.rotation.set(z * 0.38, 0, -x * 0.38);
            line.userData.noShadow = true;
          }
          crate.add(chute);
          shadowify(crate);
          ctx.scene.add(crate);
          crates.set(m.id, { mesh: crate, p: m.p, landAt: m.landAt, kind });
          break;
        }
        case 'crateTaken': {
          const cr = crates.get(m.id);
          if (cr) {
            cr.mesh.removeFromParent();
            crates.delete(m.id);
            ctx.particles.burst(cr.p, 20, [CRATE_INFO[cr.kind].color, 0xffffff], 5, 0.14, 0.8);
          }
          if (m.by === ctx.myId) { ctx.sfx.pickup(); ctx.toast(`${CRATE_INFO[m.kind as CrateKind].name} !`, 1.5); }
          break;
        }
      }
    },

    onFrame(dt) {
      const t = ctx.now(), inp = ctx.input;
      const started = t >= ctx.startAt, building = t < init.buildEnd, alive = !dead.has(ctx.myId);
      if (!building && !announced) {
        announced = true;
        ctx.toast('💣 Feu à volonté !', 2);
        ctx.sfx.go();
      }
      grid.visible = building;

      // ----- construction -----
      ghost.visible = false;
      if (building && started && alive) {
        for (let k = 0; k < 3; k++) if (inp.hit(`Digit${k + 1}`, `Numpad${k + 1}`)) mat = MAT_KEYS[k];
        const cell = aimCell();
        if (cell && cell.y < M.maxH) {
          const c = blockCenter({ plot: myPlot, ...cell }, n);
          ghost.position.set(c[0], c[1], c[2]);
          ghost.visible = true;
          (ghost.material as THREE.MeshBasicMaterial).color.set(budget >= MATS[mat].cost ? MATS[mat].color : 0xff0000);
        }
        if (cell && inp.hit('Mouse0', 'KeyF')) ctx.send({ t: 'place', x: cell.x, z: cell.z, mat });
        if (cell && inp.hit('Mouse2', 'KeyR')) ctx.send({ t: 'remove', x: cell.x, z: cell.z });
      }

      // ----- tir : maintenir pour charger, relâcher pour tirer -----
      marker.visible = false;
      if (!building && alive) {
        const ready = t - lastFire >= M.reload;
        if (chargeStart < 0 && ready && inp.hit('Mouse0', 'KeyF')) chargeStart = t;
        if (chargeStart >= 0) {
          // la jauge monte puis redescend, pour pouvoir doser les tirs courts comme les longs
          const u = ((t - chargeStart) / M.chargeTime) % 2;
          const power = u <= 1 ? u : 2 - u;
          const l = launch(ctx.body.p, ctx.camYaw(), power), range = shellRange(l.p, l.v);
          marker.position.set(l.p[0] + Math.sin(ctx.camYaw()) * range, 0.12, l.p[2] + Math.cos(ctx.camYaw()) * range);
          marker.visible = true;
          marker.rotation.y = t * 3;
          if (inp.up('Mouse0', 'KeyF') || !inp.down('Mouse0', 'KeyF')) {
            ctx.send({ t: 'fire', yaw: ctx.camYaw(), power });
            lastFire = t;
            chargeStart = -1;
          }
          bottom.dataset.power = String(power);
        }
        ctx.setCharging(chargeStart >= 0);
      }

      // ----- obus, éclairs, caisses, zone -----
      for (const s of shells.values()) {
        const p = shellAt(s.p, s.v, t - s.at);
        s.mesh.position.set(p[0], p[1], p[2]);
        if (Math.random() < 0.6) ctx.particles.emit(p[0], p[1], p[2], 0, 0.5, 0, s.kind === 'normal' ? 0xdee2e6 : SHELL_COLOR[s.kind], 0.13, 0.5, -1);
      }
      for (let i = flashes.length - 1; i >= 0; i--) {
        const f = flashes[i];
        f.userData.life -= dt;
        const k = 1 - f.userData.life / f.userData.max;
        const sc = f.userData.r * (0.25 + (1 - (1 - k) * (1 - k)) * 0.95);
        if (f.userData.wave) f.scale.set(sc, 1, sc); else f.scale.setScalar(sc);
        (f.material as THREE.MeshBasicMaterial).opacity = 0.9 * (1 - k);
        if (f.userData.life <= 0) { f.removeFromParent(); flashes.splice(i, 1); }
      }
      for (const cr of crates.values()) {
        const fall = Math.max(0, cr.landAt - t);
        cr.mesh.position.set(cr.p[0], cr.p[1] + fall * 7 + (fall ? 0 : Math.sin(t * 3) * 0.08), cr.p[2]);
        cr.mesh.rotation.y = fall ? Math.sin(t * 2) * 0.3 : t * 1.5;
        const chute = cr.mesh.getObjectByName('parachute');
        if (chute) chute.visible = fall > 0;
      }
      const shrinking = t > init.shrinkStart - 5 && init.shrinkStart < init.battleEnd;
      const zr = zoneRadius(t, init.shrinkStart, init.battleEnd);
      for (const r of rings) {
        r.visible = shrinking;
        r.scale.set(zr, 6 + Math.sin(t * 6) * 2, zr);
      }

      // ----- HUD -----
      hudTimer -= dt;
      if (hudTimer < 0) {
        hudTimer = 0.08;
        const left = Math.max(0, (building ? init.buildEnd : init.battleEnd) - Math.max(t, ctx.startAt));
        top.textContent = building ? `🧱 Construction : ${left.toFixed(0)} s` : `💣 Bataille : ${left.toFixed(0)} s${t > init.shrinkStart ? ' — la zone rétrécit !' : ''}`;
        const rows = [...hp.entries()].sort((a, b) => b[1] - a[1]).map(([id, v]) => {
          const p = ctx.players.get(id);
          if (!p) return '';
          const col = `#${p.info.color.toString(16).padStart(6, '0')}`;
          return `<div>${dead.has(id) ? '💀' : ''} ${esc(p.info.name)}${id === ctx.myId ? ' (toi)' : ''}</div><div class="bar"><i style="width:${(v / init.hp) * 100}%;background:${col}"></i></div>`;
        });
        side.innerHTML = rows.join('');
        if (!alive) bottom.textContent = 'Éliminé — tu regardes la fin de la bataille';
        else if (building) {
          bottom.innerHTML = `Budget : <b>${budget}</b> · ` + MAT_KEYS.map((k, i) => `<span class="mat${k === mat ? ' sel' : ''}">${i + 1} ${MATS[k].name} (${MATS[k].cost})</span>`).join('') +
            '<br><small>Clic gauche ou F : poser · Clic droit ou R : retirer · 1 2 3 : matériau</small>';
        } else {
          const power = chargeStart >= 0 ? Number(bottom.dataset.power ?? 0) : 0;
          const reload = Math.min(1, (t - lastFire) / M.reload);
          const special = ammo !== 'normal' ? ` · Munition : <b>${ammo === 'mega' ? 'Méga-obus' : 'Fragmentation'}</b>` : '';
          bottom.innerHTML = `Maintiens le clic gauche (ou F) pour charger, relâche pour tirer${special}` +
            `<div class="bar" style="width:320px;height:14px"><i style="width:${(chargeStart >= 0 ? power : reload) * 100}%;background:${chargeStart >= 0 ? '#ff4d6d' : reload < 1 ? '#adb5bd' : '#70e000'}"></i></div>`;
        }
      }
    },

    onExit() {
      for (const tube of tubes) tube.removeFromParent();
      ctx.setCharging(false);
    },
  };
}
