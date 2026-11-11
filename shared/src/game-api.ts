// Types partagés des mini-jeux (fiches et réglages du lobby). Le jeu lui-même — serveur compris — vit dans godot/ ;
// ces sources TypeScript servent au MCP de niveaux et à générer les vecteurs des tests de parité.
import type { Body, Vec3 } from './physics';
import type { Hit } from './protocol';

export type SettingDef =
  | { type: 'number'; label: string; default: number; min: number; max: number; step?: number; unit?: string }
  | { type: 'bool'; label: string; default: boolean }
  | { type: 'multi'; label: string; default: string[]; options: string[] }; // liste vide = tout autorisé

export type SettingsSchema = Record<string, SettingDef>;

export interface GameMeta {
  id: string;
  name: string;
  description: string;
  settings: SettingsSchema;
}

export interface ServerPlayer {
  id: string;
  name: string;
  isBot: boolean;
  p: Vec3;
  v: Vec3;
  yaw: number;
  flags: number;
  body?: Body; // seulement pour les bots, simulés par le serveur
}

export interface RoundResult {
  id: string;
  rank: number; // 0 = premier ; les ex æquo partagent le même rang
  label: string;
}

export interface ServerCtx {
  players: Map<string, ServerPlayer>;
  settings: Record<string, any>;
  startAt: number; // fin du compte à rebours (horloge serveur, en secondes)
  now(): number;
  broadcast(msg: any): void;
  send(id: string, msg: any): void;
  /** Montre un impact sur la peau du joueur à tout le monde (les PV sont gérés par le jeu). */
  damage(id: string, hit: Hit): void;
  heal(id: string, n: number): void;
  impulse(id: string, v: Vec3, tumble: number): void;
  teleport(id: string, p: Vec3): void;
  end(): void;
}

export interface ServerGame {
  onStart(): { init: any; spawns: Record<string, Vec3> };
  onTick(dt: number): void;
  onPlayerMessage(id: string, msg: any): void;
  onPlayerLeave(id: string): void;
  getResults(): RoundResult[];
  botTick?(player: ServerPlayer, dt: number): void;
}

export interface ServerGameModule {
  create(ctx: ServerCtx): ServerGame;
  /** Options calculées au moment de l'affichage du lobby (ex. liste des niveaux présents sur le disque). */
  dynamicOptions?(): Record<string, string[]>;
}
