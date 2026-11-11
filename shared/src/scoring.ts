// Scores et réglages de session.
import type { GameMeta, RoundResult } from './game-api';
import type { RoundResultRow, SessionSettings } from './protocol';

/** Points d'une manche : n pour le premier (+2 de bonus), puis n-1, n-2… ; 1 point pour le dernier. */
export function pointsForRank(rank: number, n: number): number {
  return Math.max(1, n - rank) + (rank === 0 ? 2 : 0);
}

export function scoreRound(results: RoundResult[]): RoundResultRow[] {
  const n = results.length;
  return [...results]
    .sort((a, b) => a.rank - b.rank)
    .map((r) => ({ id: r.id, rank: r.rank, label: r.label, points: pointsForRank(r.rank, n) }));
}

/** Transforme une liste ordonnée de groupes d'ex æquo en rangs (0, 0, 2, 3…). */
export function ranksFromGroups(groups: { id: string; label: string }[][]): RoundResult[] {
  const out: RoundResult[] = [];
  let rank = 0;
  for (const g of groups) {
    for (const e of g) out.push({ id: e.id, rank, label: e.label });
    rank += g.length;
  }
  return out;
}

export function defaultGameSettings(meta: GameMeta): Record<string, any> {
  const out: Record<string, any> = {};
  for (const [k, def] of Object.entries(meta.settings)) out[k] = def.default;
  return out;
}

const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v));

/** Nettoie des réglages reçus du réseau ou d'un fichier : seules les valeurs valides sont gardées. */
export function sanitizeSettings(raw: any, metas: GameMeta[]): SessionSettings {
  const ids = metas.map((m) => m.id);
  const pick = (a: any) => (Array.isArray(a) ? a.filter((x) => ids.includes(x)) : []);
  const rounds = clamp(Math.round(Number(raw?.rounds) || 5), 1, 15);
  let games = [...new Set(pick(raw?.games))] as string[];
  if (!games.length) games = ids;
  const order = raw?.order === 'random' || raw?.order === 'list' ? raw.order : 'alternate';
  const list = pick(raw?.list).slice(0, rounds);
  while (list.length < rounds) list.push(games[list.length % games.length]);
  const game: Record<string, Record<string, any>> = {};
  for (const meta of metas) {
    const src = raw?.game?.[meta.id] ?? {};
    const dst = defaultGameSettings(meta);
    for (const [k, def] of Object.entries(meta.settings)) {
      const v = src[k];
      if (v === undefined) continue;
      if (def.type === 'number' && Number.isFinite(Number(v))) dst[k] = clamp(Number(v), def.min, def.max);
      else if (def.type === 'bool') dst[k] = !!v;
      else if (def.type === 'multi' && Array.isArray(v)) dst[k] = v.filter((x) => typeof x === 'string').slice(0, 100);
    }
    game[meta.id] = dst;
  }
  return { rounds, order, games, list, game };
}

export function buildRoundList(s: SessionSettings, rnd: () => number = Math.random): string[] {
  const out: string[] = [];
  for (let i = 0; i < s.rounds; i++) {
    if (s.order === 'list') out.push(s.list[i] ?? s.games[i % s.games.length]);
    else if (s.order === 'random') {
      // aléatoire, mais jamais trois fois le même jeu d'affilée s'il y a le choix
      let g = s.games[Math.floor(rnd() * s.games.length)];
      if (s.games.length > 1 && i >= 2 && out[i - 1] === g && out[i - 2] === g) g = s.games.find((x) => x !== g)!;
      out.push(g);
    } else out.push(s.games[i % s.games.length]);
  }
  return out;
}
