// Lecture / écriture des niveaux sur le disque (Node uniquement : serveur de jeu et serveur MCP).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { LevelSchema, type Level } from './level';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const LEVELS_DIR = process.env.JEUX_LEVELS_DIR ?? path.join(ROOT, 'godot', 'levels', 'parkour');

const NAME = /^[a-z0-9][a-z0-9_-]{0,40}$/;
function fileOf(name: string): string {
  if (!NAME.test(name)) throw new Error(`Nom de niveau invalide : « ${name} » (minuscules, chiffres, tirets).`);
  return path.join(LEVELS_DIR, `${name}.json`);
}

export function listLevels(): string[] {
  if (!fs.existsSync(LEVELS_DIR)) return [];
  return fs.readdirSync(LEVELS_DIR).filter((f) => f.endsWith('.json')).map((f) => f.slice(0, -5)).filter((n) => NAME.test(n)).sort();
}

export function levelExists(name: string): boolean {
  return fs.existsSync(fileOf(name));
}

export function readLevel(name: string): Level {
  const file = fileOf(name);
  if (!fs.existsSync(file)) throw new Error(`Niveau introuvable : « ${name} ». Niveaux disponibles : ${listLevels().join(', ') || '(aucun)'}.`);
  return LevelSchema.parse({ ...JSON.parse(fs.readFileSync(file, 'utf8')), name });
}

export function writeLevel(level: Level): string {
  const file = fileOf(level.name);
  fs.mkdirSync(LEVELS_DIR, { recursive: true });
  fs.writeFileSync(file, JSON.stringify(level, null, 2) + '\n');
  return file;
}

export function deleteLevel(name: string): void {
  fs.rmSync(fileOf(name));
}
