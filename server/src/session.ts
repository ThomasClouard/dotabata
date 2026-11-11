// Cœur du serveur : lobby, enchaînement des manches, scores, relais des états. Ne connaît aucun jeu en particulier.
import fs from 'node:fs';
import path from 'node:path';
import type { WebSocket } from 'ws';
import { gameMetas } from '../../games/registry';
import { serverGames } from '../../games/registry.server';
import type { GameMeta, ServerCtx, ServerGame, ServerPlayer } from '../../shared/src/game-api';
import { makeBody, type Body, type Vec3 } from '../../shared/src/physics';
import { COLORS, FLAG, HATS, poseFlags, HAT_COLOR, MAX_PLAYERS, type ClientMsg, type Phase, type PlayerInfo, type ServerMsg, type SessionSettings, type StateTuple } from '../../shared/src/protocol';
import { buildRoundList, sanitizeSettings, scoreRound } from '../../shared/src/scoring';
import { LEVELS_DIR, ROOT } from '../../shared/src/level-store';

const BOT_NAMES = ['Nouille', 'Patate', 'Cornichon', 'Biscotte', 'Gnocchi', 'Tartine', 'Zigoto', 'Pompon', 'Bidule', 'Saucisse'];
const DEFAULTS_FILE = path.join(ROOT, 'config', 'defaults.json');
const LAST_FILE = path.join(ROOT, 'config', 'last-settings.json');
const COUNTDOWN = 4;
const SCORES_TIME = 9;

interface SPlayer extends ServerPlayer {
  color: number;
  hat: string;
  score: number;
  ws?: WebSocket;
  inRound: boolean;
}

const readJson = (f: string) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; } };
const cleanName = (s: unknown) => String(s ?? '').replace(/[<>\n\r]/g, '').trim().slice(0, 16) || 'Anonyme';

export class Session {
  private players = new Map<string, SPlayer>();
  private hostId = '';
  private settings: SessionSettings;
  private phase: Phase = 'lobby';
  private game: ServerGame | null = null;
  private ctx: ServerCtx | null = null;
  private gameId = '';
  private rounds: string[] = [];
  private roundIndex = 0;
  private endRequested = false;
  private timer: NodeJS.Timeout | null = null;
  private nextId = 1;
  private t0 = performance.now();
  private lastTick = 0;

  constructor(private urls: string[]) {
    // réglages : valeurs par défaut du dépôt, puis derniers réglages de l'hôte
    this.settings = sanitizeSettings(readJson(LAST_FILE) ?? readJson(DEFAULTS_FILE) ?? {}, gameMetas);
    setInterval(() => this.tick(), 1000 / 30);
    try {
      fs.mkdirSync(LEVELS_DIR, { recursive: true });
      let deb: NodeJS.Timeout | null = null;
      fs.watch(LEVELS_DIR, () => { if (deb) clearTimeout(deb); deb = setTimeout(() => this.sendLobby(), 300); });
    } catch { /* la surveillance des niveaux est un confort, pas une nécessité */ }
  }

  now(): number {
    return (performance.now() - this.t0) / 1000;
  }

  // ---------- connexions ----------

  connect(ws: WebSocket) {
    let me: SPlayer | null = null;
    ws.on('message', (data) => {
      let msg: ClientMsg;
      try { msg = JSON.parse(String(data)); } catch { return; }
      if (!msg || typeof msg !== 'object') return;
      if (!me) {
        if (msg.t !== 'hello') return;
        if ([...this.players.values()].filter((p) => !p.isBot).length >= MAX_PLAYERS) { ws.close(1000, 'Partie complète'); return; }
        if (this.players.size >= MAX_PLAYERS) this.setBots(this.bots().length - 1);
        me = this.addPlayer(cleanName(msg.name), msg.color, msg.hat, false);
        me.ws = ws;
        if (!this.hostId) this.hostId = me.id;
        this.send(me, { t: 'welcome', id: me.id, time: this.now() });
        this.sendLobby();
        if (this.phase !== 'lobby') this.send(me, { t: 'wait' });
        return;
      }
      try { this.onMessage(me, msg); } catch (e) { console.error('Erreur en traitant un message :', e); }
    });
    ws.on('close', () => { if (me) this.removePlayer(me.id); });
    ws.on('error', () => ws.close());
  }

  private addPlayer(name: string, color: unknown, hat: unknown, isBot: boolean): SPlayer {
    const id = `p${this.nextId++}`;
    const a = Math.random() * Math.PI * 2, r = 3 + Math.random() * 4;
    const p: SPlayer = {
      id, name, isBot, score: 0, inRound: false,
      color: COLORS.includes(color as number) ? (color as number) : COLORS[this.players.size % COLORS.length],
      hat: HATS.includes(hat as string) ? (hat as string) : HATS[0],
      p: [Math.sin(a) * r, 0, Math.cos(a) * r], v: [0, 0, 0], yaw: a + Math.PI, flags: FLAG.grounded,
    };
    if (isBot) p.body = makeBody(p.p);
    this.players.set(id, p);
    return p;
  }

  private removePlayer(id: string) {
    const p = this.players.get(id);
    if (!p) return;
    this.players.delete(id);
    if (p.inRound && this.game) { try { this.game.onPlayerLeave(id); } catch (e) { console.error(e); } }
    const humans = [...this.players.values()].filter((x) => !x.isBot);
    if (!humans.length) {
      // plus personne : retour au lobby, sans bots
      this.players.clear();
      this.hostId = '';
      this.toLobby();
      return;
    }
    if (this.hostId === id) this.hostId = humans[0].id;
    this.sendLobby();
  }

  private bots() {
    return [...this.players.values()].filter((p) => p.isBot);
  }

  private setBots(n: number) {
    const humans = this.players.size - this.bots().length;
    n = Math.max(0, Math.min(MAX_PLAYERS - humans, Math.floor(n) || 0));
    while (this.bots().length > n) {
      const b = this.bots().pop()!;
      this.players.delete(b.id);
      if (b.inRound && this.game) this.game.onPlayerLeave(b.id);
    }
    while (this.bots().length < n) {
      const used = new Set([...this.players.values()].map((p) => p.name));
      const name = BOT_NAMES.find((x) => !used.has(x)) ?? `Bot ${this.nextId}`;
      const taken = (c: number) => [...this.players.values()].some((p) => p.color === c);
      // de préférence un personnage dont la couleur d'origine est encore libre
      const free = HATS.filter((h) => !taken(HAT_COLOR[h]));
      const hat = (free.length ? free : HATS)[Math.floor(Math.random() * (free.length || HATS.length))];
      this.addPlayer(name, taken(HAT_COLOR[hat]) ? COLORS.find((c) => !taken(c)) : HAT_COLOR[hat], hat, true);
    }
  }

  // ---------- messages ----------

  private onMessage(me: SPlayer, msg: ClientMsg) {
    const host = me.id === this.hostId;
    switch (msg.t) {
      case 'ping':
        this.send(me, { t: 'pong', c: msg.c, time: this.now() });
        break;
      case 'state': {
        const s = msg.s;
        if (!Array.isArray(s) || s.length < 8 || !s.every((x) => Number.isFinite(x))) break;
        me.p = [s[0], s[1], s[2]]; me.yaw = s[3]; me.flags = s[4]; me.v = [s[5], s[6], s[7]];
        break;
      }
      case 'profile':
        me.name = cleanName(msg.name);
        if (COLORS.includes(msg.color)) me.color = msg.color;
        if (HATS.includes(msg.hat)) me.hat = msg.hat;
        this.sendLobby();
        break;
      case 'settings':
        if (!host || this.phase !== 'lobby') break;
        this.settings = sanitizeSettings(msg.settings, gameMetas);
        try { fs.writeFileSync(LAST_FILE, JSON.stringify(this.settings, null, 2)); } catch { /* mémorisation facultative */ }
        this.sendLobby();
        break;
      case 'bots':
        if (host && this.phase === 'lobby') { this.setBots(msg.n); this.sendLobby(); }
        break;
      case 'start':
        if (host && this.phase === 'lobby') this.startSession();
        break;
      case 'stop':
      case 'toLobby':
        if (host && this.phase !== 'lobby') this.toLobby();
        break;
      case 'game':
        if (this.phase === 'round' && me.inRound && this.game) this.game.onPlayerMessage(me.id, msg.m);
        break;
    }
  }

  private send(p: SPlayer, msg: ServerMsg) {
    if (p.ws && p.ws.readyState === 1) p.ws.send(JSON.stringify(msg));
  }

  private broadcast(msg: ServerMsg, onlyInRound = false) {
    const data = JSON.stringify(msg);
    for (const p of this.players.values()) if (p.ws && p.ws.readyState === 1 && (!onlyInRound || p.inRound)) p.ws.send(data);
  }

  private metas(): GameMeta[] {
    // injecte les options dynamiques (ex. niveaux présents sur le disque)
    return gameMetas.map((m) => {
      const dyn = serverGames[m.id]?.dynamicOptions?.() ?? {};
      const settings = { ...m.settings };
      for (const [k, opts] of Object.entries(dyn)) {
        const def = settings[k];
        if (def?.type === 'multi') settings[k] = { ...def, options: opts };
      }
      return { ...m, settings };
    });
  }

  private sendLobby() {
    const players: PlayerInfo[] = [...this.players.values()].map((p) => ({ id: p.id, name: p.name, color: p.color, hat: p.hat, isBot: p.isBot, score: p.score }));
    this.broadcast({ t: 'lobby', phase: this.phase, players, hostId: this.hostId, settings: this.settings, metas: this.metas(), urls: this.urls });
  }

  // ---------- déroulement ----------

  private clearTimer() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
  }

  private toLobby() {
    this.clearTimer();
    this.phase = 'lobby';
    this.game = null;
    this.ctx = null;
    let i = 0;
    for (const p of this.players.values()) {
      p.score = 0;
      p.inRound = false;
      if (p.isBot) {
        const a = (i++ / 9) * Math.PI * 2;
        p.p = [Math.sin(a) * 6, 0, Math.cos(a) * 6]; p.v = [0, 0, 0]; p.yaw = a + Math.PI; p.flags = FLAG.grounded;
        p.body = makeBody(p.p);
      }
    }
    this.sendLobby();
  }

  private startSession() {
    this.rounds = buildRoundList(this.settings);
    this.roundIndex = 0;
    for (const p of this.players.values()) p.score = 0;
    this.startRound();
  }

  private startRound() {
    this.clearTimer();
    this.gameId = this.rounds[this.roundIndex];
    const mod = serverGames[this.gameId];
    const startAt = this.now() + COUNTDOWN;
    const inRound = new Map<string, ServerPlayer>();
    for (const p of this.players.values()) { p.inRound = true; inRound.set(p.id, p); }
    const gameMsg = (m: any): ServerMsg => ({ t: 'game', m });
    const ctx: ServerCtx = {
      players: inRound,
      settings: this.settings.game[this.gameId] ?? {},
      startAt,
      now: () => this.now(),
      broadcast: (m) => this.broadcast(gameMsg(m), true),
      send: (id, m) => { const p = this.players.get(id); if (p) this.send(p, gameMsg(m)); },
      damage: (id, hit) => this.broadcast({ t: 'damage', id, hit }),
      heal: (id, n) => this.broadcast({ t: 'heal', id, n }),
      impulse: (id, v, tumble) => {
        const p = this.players.get(id);
        if (!p) return;
        if (p.body) { p.body.v = [v[0], v[1], v[2]]; p.body.tumble = tumble; p.body.grounded = false; p.body.coyote = 0; }
        else this.send(p, { t: 'impulse', v, tumble });
      },
      teleport: (id, pos) => {
        const p = this.players.get(id);
        if (!p) return;
        if (p.body) { p.body.p = [pos[0], pos[1], pos[2]]; p.body.v = [0, 0, 0]; }
        else this.send(p, { t: 'teleport', p: pos });
      },
      end: () => { this.endRequested = true; },
    };
    try {
      const game = mod.create(ctx);
      const { init, spawns } = game.onStart();
      for (const p of this.players.values()) {
        const s = spawns[p.id];
        if (!s) continue;
        p.p = [s[0], s[1], s[2]]; p.v = [0, 0, 0];
        if (p.isBot) p.body = makeBody(s);
      }
      this.game = game;
      this.ctx = ctx;
      this.phase = 'round';
      this.endRequested = false;
      this.sendLobby();
      this.broadcast({ t: 'round', index: this.roundIndex, total: this.rounds.length, gameId: this.gameId, init, spawns, startAt });
    } catch (e) {
      console.error(`Impossible de lancer la manche « ${this.gameId} » :`, e);
      this.toLobby();
    }
  }

  private endRound() {
    if (!this.game) return;
    const rows = scoreRound(this.game.getResults());
    for (const r of rows) { const p = this.players.get(r.id); if (p) p.score += r.points; }
    const totals: Record<string, number> = {};
    for (const p of this.players.values()) totals[p.id] = p.score;
    const last = this.roundIndex >= this.rounds.length - 1;
    this.phase = 'scores';
    this.game = null;
    this.broadcast({ t: 'roundEnd', gameId: this.gameId, index: this.roundIndex, total: this.rounds.length, results: rows, totals, last });
    this.sendLobby();
    this.timer = setTimeout(() => {
      if (last) {
        this.phase = 'podium';
        this.broadcast({ t: 'podium', totals });
        this.sendLobby();
        this.timer = setTimeout(() => this.toLobby(), 60_000);
      } else {
        this.roundIndex++;
        this.startRound();
      }
    }, SCORES_TIME * 1000);
  }

  private tick() {
    const t = this.now();
    const dt = Math.min(0.1, t - this.lastTick);
    this.lastTick = t;
    if (!this.players.size) return;
    if (this.phase === 'round' && this.game && this.ctx) {
      try {
        if (this.game.botTick && t >= this.ctx.startAt) {
          for (const p of this.players.values()) {
            if (!p.isBot || !p.inRound || !p.body) continue;
            this.game.botTick(p, dt);
            syncBot(p, p.body);
          }
        }
        this.game.onTick(dt);
      } catch (e) {
        console.error('Erreur dans la manche :', e);
        this.endRequested = true;
      }
      if (this.endRequested) this.endRound();
    }
    const s: StateTuple[] = [];
    const r = (x: number) => Math.round(x * 100) / 100;
    for (const p of this.players.values()) s.push([p.id, r(p.p[0]), r(p.p[1]), r(p.p[2]), r(p.yaw), p.flags, r(p.v[0]), r(p.v[1]), r(p.v[2])]);
    this.broadcast({ t: 'states', s });
  }
}

function syncBot(p: ServerPlayer, b: Body) {
  p.p = [b.p[0], b.p[1], b.p[2]] as Vec3;
  p.v = [b.v[0], b.v[1], b.v[2]] as Vec3;
  p.flags = (b.grounded || b.coyote > 0 ? FLAG.grounded : 0) | (b.tumble > 0 ? FLAG.tumble : 0) | poseFlags(b);
}
