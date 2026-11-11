// Clavier + souris. Les touches sont lues par position physique (KeyW…) : ZQSD marche tel quel en AZERTY.
export class Input {
  private keys = new Set<string>();
  private pressed = new Set<string>();
  private released = new Set<string>();
  dx = 0;
  dy = 0;
  locked = false;
  private dragging = false;

  constructor(private canvas: HTMLCanvasElement) {
    const typing = () => /INPUT|SELECT|TEXTAREA/.test(document.activeElement?.tagName ?? '');
    window.addEventListener('keydown', (e) => {
      if (typing()) return;
      if (!this.keys.has(e.code)) this.pressed.add(e.code);
      this.keys.add(e.code);
      if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
    });
    window.addEventListener('keyup', (e) => {
      if (this.keys.delete(e.code)) this.released.add(e.code);
    });
    window.addEventListener('blur', () => this.keys.clear());
    canvas.addEventListener('mousedown', (e) => {
      const code = `Mouse${e.button}`;
      // le premier clic capture la souris ; il ne compte pas comme une action de jeu
      if (!this.locked) {
        this.dragging = true;
        canvas.requestPointerLock?.()?.catch?.(() => {});
        return;
      }
      this.pressed.add(code);
      this.keys.add(code);
    });
    window.addEventListener('mouseup', (e) => {
      this.dragging = false;
      if (this.keys.delete(`Mouse${e.button}`)) this.released.add(`Mouse${e.button}`);
    });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    document.addEventListener('pointerlockchange', () => {
      this.locked = document.pointerLockElement === canvas;
    });
    window.addEventListener('mousemove', (e) => {
      if (this.locked || this.dragging) {
        this.dx += e.movementX;
        this.dy += e.movementY;
      }
    });
  }

  down(...codes: string[]): boolean {
    return codes.some((c) => this.keys.has(c));
  }

  /** Vrai une seule fois, à la frame où la touche vient d'être enfoncée. */
  hit(...codes: string[]): boolean {
    return codes.some((c) => this.pressed.has(c));
  }

  up(...codes: string[]): boolean {
    return codes.some((c) => this.released.has(c));
  }

  endFrame(): void {
    this.pressed.clear();
    this.released.clear();
    this.dx = 0;
    this.dy = 0;
  }
}
