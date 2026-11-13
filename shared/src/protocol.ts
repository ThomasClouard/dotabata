// Protocole WebSocket (JSON). Le serveur fait autorité sur les règles ; chaque client simule son personnage.
import type { Body, Vec3 } from './physics';
import type { GameMeta } from './game-api';

export interface PlayerInfo {
  id: string;
  name: string;
  color: number;
  hat: string;
  isBot: boolean;
  score: number;
}

export interface SessionSettings {
  rounds: number;
  order: 'alternate' | 'random' | 'list';
  games: string[]; // jeux inclus, dans l'ordre d'alternance
  list: string[]; // ordre explicite quand order === 'list'
  game: Record<string, Record<string, any>>; // réglages propres à chaque jeu
}

/** Trou dans la peau d'un personnage, en coordonnées locales du personnage. */
export interface Hit {
  pos: Vec3;
  r: number;
  part?: string;
}

// zip / flight / boost / shield : pose transmise aux autres joueurs (vague 3) ; un client qui ne les envoie pas reste compatible
export const FLAG = { grounded: 1, tumble: 2, charging: 4, hidden: 8, zip: 16, flight: 32, boost: 64, shield: 128 } as const;

/** Bits de pose d'un corps (à combiner aux autres drapeaux de l'état 30 Hz). */
export function poseFlags(b: Body): number {
  return (b.zip >= 0 ? FLAG.zip : 0) | (b.flight > 0 ? FLAG.flight : 0) | (b.boost > 0 ? FLAG.boost : 0) | (b.shield > 0 ? FLAG.shield : 0);
}
/** [id, x, y, z, yaw, flags, vx, vy, vz] */
export type StateTuple = [string, number, number, number, number, number, number, number, number];

export interface RoundResultRow {
  id: string;
  rank: number;
  label: string;
  points: number;
}

export type Phase = 'lobby' | 'round' | 'scores' | 'podium';

export type ClientMsg =
  | { t: 'hello'; name: string; color: number; hat: string }
  | { t: 'profile'; name: string; color: number; hat: string }
  | { t: 'ping'; c: number }
  | { t: 'settings'; settings: SessionSettings }
  | { t: 'bots'; n: number }
  | { t: 'start' }
  | { t: 'stop' }
  | { t: 'toLobby' }
  /** Écran des scores : « Jeu suivant ». */
  | { t: 'next' }
  | { t: 'state'; s: [number, number, number, number, number, number, number, number] }
  | { t: 'game'; m: any };

export type ServerMsg =
  | { t: 'welcome'; id: string; time: number }
  | { t: 'pong'; c: number; time: number }
  | { t: 'lobby'; phase: Phase; players: PlayerInfo[]; hostId: string; settings: SessionSettings; metas: GameMeta[]; urls: string[] }
  | { t: 'round'; index: number; total: number; gameId: string; init: any; spawns: Record<string, Vec3>; startAt: number }
  | { t: 'roundEnd'; gameId: string; index: number; total: number; results: RoundResultRow[]; totals: Record<string, number>; last: boolean }
  /** Écran des scores : joueurs prêts (`ids`) parmi ceux qu'on attend (`need`). Tous prêts : la suite démarre. */
  | { t: 'ready'; ids: string[]; need: string[] }
  | { t: 'podium'; totals: Record<string, number> }
  | { t: 'wait' }
  | { t: 'states'; s: StateTuple[] }
  | { t: 'game'; m: any }
  | { t: 'damage'; id: string; hit: Hit }
  | { t: 'heal'; id: string; n: number }
  | { t: 'impulse'; v: Vec3; tumble: number }
  | { t: 'teleport'; p: Vec3 };

/** Personnages (le champ `hat` du profil désigne le personnage choisi) et leur couleur d'origine. */
export const HAT_COLOR: Record<string, number> = {
  haricot: 0xf0629a, casquette: 0x4a8fe8, spaghetti: 0xffc636, hélice: 0x9a6be0,
  bouée: 0x7dc95a, crochet: 0xf78a3c, bandeau: 0x7ccdf2, arche: 0xb08cf0,
};
export const HATS = Object.keys(HAT_COLOR);
export const COLORS = [...Object.values(HAT_COLOR), 0xff4d6d, 0xf8f9fa];
export const MAX_PLAYERS = 10;
