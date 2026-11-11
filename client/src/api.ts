// Contrat client des mini-jeux. Le cœur (lobby, caméra, personnage, réseau) ne connaît que cette interface.
import type * as THREE from 'three';
import type { Body, Collider, Contact, Vec3 } from '../../shared/src/physics';
import type { PlayerInfo } from '../../shared/src/protocol';
import type { AnimState, Character } from './character/character';
import type { Sfx } from './audio';
import type { Particles } from './particles';
import type { Input } from './input';

export interface ClientPlayer {
  info: PlayerInfo;
  char: Character;
  pos: THREE.Vector3; // position affichée (interpolée pour les autres joueurs)
  yaw: number;
  flags: number;
  /** Fige le personnage à un endroit (podium) au lieu de suivre le réseau. */
  pin: { p: Vec3; yaw: number; dance: boolean } | null;
  /** Masque le personnage (ex. tombé dans le vide). Remis à faux à chaque changement de scène. */
  hidden: boolean;
}

/** Échappe un texte avant de l'insérer dans du HTML (pseudos des joueurs). */
export const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

export interface ClientCtx {
  scene: THREE.Group; // contenu du jeu ; vidé automatiquement à la sortie
  camera: THREE.PerspectiveCamera;
  myId: string;
  players: Map<string, ClientPlayer>;
  body: Body; // personnage local
  startAt: number;
  hud: HTMLElement;
  sfx: Sfx;
  particles: Particles;
  input: Input;
  now(): number; // horloge serveur synchronisée (secondes)
  send(msg: any): void;
  camYaw(): number;
  setCamYaw(yaw: number): void;
  shake(amount: number): void;
  setSky(color: number): void;
  /** Mer animée sous le décor, à l'altitude `y` (null = aucune). */
  setSea(y: number | null, color?: number): void;
  /** false = spectateur : plus de contrôle ni de physique pour le joueur local. */
  setActive(active: boolean): void;
  /** Caméra orbitale autour d'un point (null = retour sur le joueur). */
  setSpectate(target: Vec3 | null, dist?: number): void;
  /** Le personnage regarde dans la direction de la caméra (visée). */
  setAimMode(on: boolean): void;
  setCharging(on: boolean): void;
  toast(text: string, seconds?: number): void;
}

export interface ClientGame {
  onEnter(ctx: ClientCtx, init: any): void;
  onMessage(msg: any): void;
  onFrame(dt: number): void;
  onExit(): void;
  /** Collisions du joueur local à l'instant `t`. */
  colliders(t: number): Collider[];
  preStep?(body: Body, dt: number): void;
  postStep?(body: Body, contacts: Contact[], dt: number): void;
  /** Pose particulière d'un joueur (suspendu, en vol…) fusionnée dans son animation ; `local` = joueur de ce client. */
  pose?(id: string, pos: THREE.Vector3, local: boolean, flags: number): Partial<AnimState> | null | undefined;
  /** Contact avec un autre joueur (position, vitesse) à la place de l'écartement par défaut ; true = on a trébuché. */
  jostle?(body: Body, other: Vec3, otherVel: Vec3): boolean;
}

export type ClientGameFactory = () => ClientGame;
