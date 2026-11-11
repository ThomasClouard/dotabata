// Sons entièrement synthétisés en WebAudio : aucun fichier à charger.
export class Sfx {
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private noise: AudioBuffer | null = null;

  constructor() {
    // les navigateurs exigent un geste de l'utilisateur avant de produire du son
    const unlock = () => {
      if (!this.ctx) {
        try {
          this.ctx = new AudioContext();
          this.master = this.ctx.createGain();
          this.master.gain.value = 0.35;
          this.master.connect(this.ctx.destination);
          const len = this.ctx.sampleRate;
          this.noise = this.ctx.createBuffer(1, len, len);
          const d = this.noise.getChannelData(0);
          for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
        } catch { /* pas de son : le jeu reste jouable */ }
      }
      this.ctx?.resume();
    };
    window.addEventListener('mousedown', unlock);
    window.addEventListener('keydown', unlock);
  }

  private tone(type: OscillatorType, f0: number, f1: number, dur: number, vol = 0.5, delay = 0): void {
    if (!this.ctx || !this.master) return;
    const t = this.ctx.currentTime + delay;
    const o = this.ctx.createOscillator(), g = this.ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(f0, t);
    o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g).connect(this.master);
    o.start(t);
    o.stop(t + dur + 0.02);
  }

  private burst(dur: number, vol: number, freq: number, delay = 0): void {
    if (!this.ctx || !this.master || !this.noise) return;
    const t = this.ctx.currentTime + delay;
    const src = this.ctx.createBufferSource(), f = this.ctx.createBiquadFilter(), g = this.ctx.createGain();
    src.buffer = this.noise;
    f.type = 'lowpass';
    f.frequency.setValueAtTime(freq, t);
    f.frequency.exponentialRampToValueAtTime(60, t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    src.connect(f).connect(g).connect(this.master);
    src.start(t, Math.random() * 0.5, dur + 0.05);
  }

  jump() { this.tone('square', 260, 620, 0.14, 0.18); }
  land() { this.burst(0.09, 0.25, 500); }
  boing() { this.tone('sine', 180, 720, 0.28, 0.4); this.tone('sine', 360, 900, 0.2, 0.15, 0.05); }
  hit() { this.burst(0.18, 0.6, 1400); this.tone('sawtooth', 220, 60, 0.22, 0.3); }
  hurt() { this.tone('square', 420, 140, 0.18, 0.22); }
  fire() { this.tone('sine', 520, 90, 0.25, 0.5); this.burst(0.12, 0.35, 2500); }
  boom(vol = 1) { this.burst(0.7, 0.9 * vol, 900); this.tone('sine', 110, 30, 0.6, 0.8 * vol); }
  place() { this.tone('triangle', 500, 320, 0.08, 0.3); }
  remove() { this.tone('triangle', 300, 180, 0.1, 0.25); }
  pickup() { [660, 880, 1320].forEach((f, i) => this.tone('square', f, f, 0.09, 0.2, i * 0.07)); }
  checkpoint() { [523, 659, 784].forEach((f, i) => this.tone('triangle', f, f, 0.14, 0.35, i * 0.09)); }
  tick() { this.tone('square', 440, 440, 0.08, 0.25); }
  go() { this.tone('square', 880, 880, 0.35, 0.3); }
  win() { [523, 659, 784, 1047, 784, 1047].forEach((f, i) => this.tone('square', f, f, 0.16, 0.22, i * 0.13)); }
  crumble() { this.burst(0.35, 0.4, 700); }
  /** Vague 2 : téléporteur, speed pad, bulle qui éclate, tyrolienne (accroche / lâcher), canon à joueurs. */
  warp() { this.tone('sine', 300, 1600, 0.3, 0.3); this.tone('triangle', 1600, 400, 0.25, 0.18, 0.18); }
  whoosh() { this.burst(0.35, 0.45, 5000); this.tone('sine', 500, 1100, 0.2, 0.12); }
  pop() { this.tone('sine', 900, 200, 0.07, 0.35); this.burst(0.05, 0.25, 6000); }
  zip() { this.tone('sawtooth', 700, 1100, 0.5, 0.06); this.burst(0.5, 0.15, 3000); }
  unzip() { this.tone('triangle', 900, 500, 0.12, 0.25); }
  launch() { this.boom(0.55); this.tone('square', 200, 900, 0.35, 0.2, 0.05); }
  /** Vague 3 : porte / trappe, pièce, dalle sûre, glissade sur une banane. */
  door() { this.tone('square', 160, 90, 0.25, 0.2); this.burst(0.3, 0.25, 900, 0.05); }
  coin() { this.tone('square', 988, 988, 0.07, 0.2); this.tone('square', 1319, 1319, 0.2, 0.2, 0.07); }
  ding() { this.tone('sine', 1047, 1040, 0.18, 0.25); }
  slip() { this.tone('sine', 900, 200, 0.35, 0.3); this.tone('sine', 1200, 300, 0.3, 0.15, 0.05); }
  /** Chute dans la lave (grésillement), l'eau (plouf) ou l'acide (bulles). */
  sizzle() { this.burst(0.6, 0.5, 4500); this.burst(0.3, 0.3, 9000, 0.05); this.tone('sawtooth', 160, 50, 0.4, 0.25); }
  splash() { this.burst(0.45, 0.7, 1800); this.tone('sine', 300, 70, 0.3, 0.45); this.tone('sine', 900, 1500, 0.12, 0.12, 0.2); }
  bubbles() { [0, 0.07, 0.13, 0.22, 0.3].forEach((d, i) => this.tone('sine', 300 + i * 90, 900 + i * 150, 0.07, 0.25, d)); this.tone('square', 220, 90, 0.3, 0.12); }
  /** Petit air de xylophone quand un squelette s'écroule. */
  xylo() { [1568, 1319, 1175, 988, 784, 659, 523].forEach((f, i) => this.tone('sine', f, f * 0.99, 0.22, 0.4, i * 0.065 + Math.random() * 0.02)); }
}
