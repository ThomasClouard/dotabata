import { describe, expect, it } from 'vitest';
import { PHYS, groundBelow, jumpHeight, jumpReach, makeBody, stepBody, type Collider } from '../shared/src/physics';

const floor: Collider = { id: 0, c: [0, -0.5, 0], h: [20, 0.5, 20], yaw: 0 };
const DT = 1 / 60;
const run = (b: ReturnType<typeof makeBody>, cols: Collider[], steps: number, inp = { mx: 0, mz: 0, jump: false }) => {
  for (let i = 0; i < steps; i++) stepBody(b, inp, cols, DT);
};

describe('physique partagée', () => {
  it('pose le personnage sur le sol', () => {
    const b = makeBody([0, 3, 0]);
    run(b, [floor], 120);
    expect(b.grounded).toBe(true);
    expect(b.p[1]).toBeCloseTo(0, 2);
  });

  it('saute à la hauteur annoncée', () => {
    const b = makeBody([0, 0, 0]);
    run(b, [floor], 5);
    let apex = 0;
    stepBody(b, { mx: 0, mz: 0, jump: true }, [floor], DT);
    for (let i = 0; i < 90; i++) { stepBody(b, { mx: 0, mz: 0, jump: false }, [floor], DT); apex = Math.max(apex, b.p[1]); }
    expect(apex).toBeGreaterThan(jumpHeight() * 0.92);
    expect(apex).toBeLessThan(jumpHeight() * 1.05);
  });

  it('franchit en courant la distance prévue par jumpReach', () => {
    const b = makeBody([0, 0, 0]);
    run(b, [floor], 40, { mx: 0, mz: 1, jump: false });
    const z0 = b.p[2];
    stepBody(b, { mx: 0, mz: 1, jump: true }, [floor], DT);
    let steps = 0;
    while (!b.grounded && steps++ < 200) stepBody(b, { mx: 0, mz: 1, jump: false }, [floor], DT);
    const dist = b.p[2] - z0;
    expect(dist).toBeGreaterThan(jumpReach(0) * 0.9);
    expect(dist).toBeLessThan(jumpReach(0) * 1.1);
    expect(jumpReach(jumpHeight() + 0.1)).toBe(-1);
  });

  it('est arrêté par un mur, même tourné', () => {
    const wall: Collider = { id: 1, c: [0, 2, 5], h: [6, 2, 0.5], yaw: 0.4 };
    const b = makeBody([0, 0, 0]);
    run(b, [floor, wall], 50, { mx: 0, mz: 1, jump: false });
    // toujours du côté proche du mur (coordonnée z dans le repère du mur), en glissant le long
    const lz = b.p[0] * Math.sin(0.4) + (b.p[2] - 5) * Math.cos(0.4);
    expect(lz).toBeLessThan(-0.85);
    expect(lz).toBeGreaterThan(-1);
    const straight = makeBody([0, 0, 0]);
    run(straight, [floor, { ...wall, yaw: 0 }], 240, { mx: 0, mz: 1, jump: false });
    expect(straight.p[2]).toBeCloseTo(5 - 0.5 - PHYS.radius, 2);
    expect(b.p[1]).toBeCloseTo(0, 1);
  });

  it('est emporté par une plateforme mobile et rebondit sur un trampoline', () => {
    const b = makeBody([0, 0.1, 0]);
    for (let i = 0; i < 120; i++) {
      const x = i * DT * 2;
      stepBody(b, { mx: 0, mz: 0, jump: false }, [{ id: 2, c: [x, -0.5, 0], h: [2, 0.5, 2], yaw: 0, vel: [2, 0, 0] }], DT);
    }
    expect(b.p[0]).toBeGreaterThan(3);
    const t = makeBody([0, 1, 0]);
    let apex = 0;
    for (let i = 0; i < 120; i++) { stepBody(t, { mx: 0, mz: 0, jump: false }, [{ ...floor, bounce: 15 }], DT); apex = Math.max(apex, t.p[1]); }
    expect(apex).toBeGreaterThan(jumpHeight(15) * 0.9);
  });

  it('trouve le sol sous un point', () => {
    expect(groundBelow(0, 5, 0, [floor])).toBe(0);
    expect(groundBelow(50, 5, 0, [floor])).toBe(-Infinity);
    expect(PHYS.radius).toBeGreaterThan(0);
  });
});
