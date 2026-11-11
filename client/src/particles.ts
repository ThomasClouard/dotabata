// Particules légères : un seul InstancedMesh de petites boules (confettis, débris, fumée, étincelles).
import * as THREE from 'three';

const CAP = 700;

export class Particles {
  readonly mesh: THREE.InstancedMesh;
  private pos = new Float32Array(CAP * 3);
  private vel = new Float32Array(CAP * 3);
  private life = new Float32Array(CAP);
  private max = new Float32Array(CAP);
  private size = new Float32Array(CAP);
  private grav = new Float32Array(CAP);
  private spin = new Float32Array(CAP);
  private next = 0;
  private m = new THREE.Matrix4();
  private q = new THREE.Quaternion();
  private e = new THREE.Euler();
  private s = new THREE.Vector3();
  private p = new THREE.Vector3();
  private c = new THREE.Color();

  constructor() {
    this.mesh = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.62, 1), new THREE.MeshBasicMaterial(), CAP);
    this.mesh.frustumCulled = false;
    this.mesh.userData.noShadow = true;
    this.mesh.count = CAP;
    this.m.makeScale(0, 0, 0);
    for (let i = 0; i < CAP; i++) { this.mesh.setMatrixAt(i, this.m); this.mesh.setColorAt(i, this.c.set(0xffffff)); }
  }

  emit(x: number, y: number, z: number, vx: number, vy: number, vz: number, color: number, size = 0.12, life = 0.8, gravity = 12): void {
    const i = this.next;
    this.next = (this.next + 1) % CAP;
    this.pos.set([x, y, z], i * 3);
    this.vel.set([vx, vy, vz], i * 3);
    this.life[i] = this.max[i] = life;
    this.size[i] = size;
    this.grav[i] = gravity;
    this.spin[i] = Math.random() * 10;
    this.mesh.setColorAt(i, this.c.set(color));
    this.mesh.instanceColor!.needsUpdate = true;
  }

  /** Gerbe de particules dans toutes les directions. */
  burst(p: [number, number, number], n: number, colors: number[], speed = 6, size = 0.14, life = 0.9, gravity = 14, up = 0.5): void {
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2, e = Math.random() * 2 - 1 + up, s = speed * (0.3 + Math.random() * 0.7);
      const h = Math.sqrt(Math.max(0, 1 - Math.min(1, e * e)));
      this.emit(p[0], p[1], p[2], Math.cos(a) * h * s, e * s, Math.sin(a) * h * s, colors[i % colors.length], size * (0.6 + Math.random() * 0.8), life * (0.6 + Math.random() * 0.6), gravity);
    }
  }

  update(dt: number): void {
    for (let i = 0; i < CAP; i++) {
      if (this.life[i] <= 0) continue;
      this.life[i] -= dt;
      const k = i * 3;
      if (this.life[i] <= 0) {
        this.m.makeScale(0, 0, 0);
        this.mesh.setMatrixAt(i, this.m);
        continue;
      }
      this.vel[k + 1] -= this.grav[i] * dt;
      this.pos[k] += this.vel[k] * dt; this.pos[k + 1] += this.vel[k + 1] * dt; this.pos[k + 2] += this.vel[k + 2] * dt;
      const sc = this.size[i] * Math.min(1, (this.life[i] / this.max[i]) * 2.5);
      this.e.set(this.spin[i] + this.life[i] * 6, this.spin[i] * 2 + this.life[i] * 4, 0);
      this.m.compose(this.p.set(this.pos[k], this.pos[k + 1], this.pos[k + 2]), this.q.setFromEuler(this.e), this.s.set(sc, sc, sc));
      this.mesh.setMatrixAt(i, this.m);
    }
    this.mesh.instanceMatrix.needsUpdate = true;
  }
}
