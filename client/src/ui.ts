// Interface HTML : panneau du lobby (formulaire généré depuis les réglages déclarés par chaque jeu), scores, podium.
import type { GameMeta } from '../../shared/src/game-api';
import { COLORS, HATS, HAT_COLOR, MAX_PLAYERS, type PlayerInfo, type ServerMsg, type SessionSettings } from '../../shared/src/protocol';

type LobbyMsg = Extract<ServerMsg, { t: 'lobby' }>;
type RoundEndMsg = Extract<ServerMsg, { t: 'roundEnd' }>;

export const css = (c: number) => `#${c.toString(16).padStart(6, '0')}`;

function el<K extends keyof HTMLElementTagNameMap>(tag: K, props: Partial<HTMLElementTagNameMap[K]> & Record<string, any> = {}, ...kids: (Node | string)[]): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag);
  Object.assign(e, props);
  e.append(...kids);
  return e;
}

export interface LobbyHandlers {
  profile(p: { name: string; color: number; hat: string }): void;
  settings(s: SessionSettings): void;
  bots(n: number): void;
  start(): void;
  quality: { high: boolean; toggle(): void };
}

export function renderLobby(root: HTMLElement, m: LobbyMsg, myId: string, h: LobbyHandlers): void {
  // ne pas reconstruire le panneau pendant que l'utilisateur tape dans un champ
  const active = document.activeElement;
  if (active && root.contains(active) && /INPUT|SELECT/.test(active.tagName) && (active as HTMLInputElement).type !== 'checkbox') {
    active.addEventListener('blur', () => renderLobby(root, m, myId, h), { once: true });
    return;
  }
  const me = m.players.find((p) => p.id === myId);
  if (!me) return;
  const host = m.hostId === myId;
  const s: SessionSettings = structuredClone(m.settings);
  const push = () => h.settings(s);
  const scroll = root.scrollTop;
  root.replaceChildren();

  root.append(el('h1', {}, '🎉 Dotabata!'));
  const name = el('input', { value: me.name, maxLength: 16, onchange: () => h.profile({ name: name.value, color: me.color, hat: me.hat }) });
  name.addEventListener('keydown', (e) => { if (e.key === 'Enter') name.blur(); });
  root.append(el('div', { className: 'row' }, el('label', {}, 'Pseudo'), name));
  const sw = el('div', { className: 'row' });
  for (const c of COLORS) {
    const b = el('button', { className: `swatch${c === me.color ? ' sel' : ''}`, title: 'Couleur', onclick: () => h.profile({ name: me.name, color: c, hat: me.hat }) });
    b.style.background = css(c);
    sw.append(b);
  }
  root.append(sw);
  const hats = el('div', { className: 'row' });
  for (const hat of HATS) hats.append(el('button', { className: `small${hat === me.hat ? ' sel' : ''}`, title: 'Personnage', onclick: () => h.profile({ name: me.name, color: HAT_COLOR[hat], hat }) }, hat));
  root.append(hats);

  root.append(el('h2', {}, `Joueurs (${m.players.length}/${MAX_PLAYERS})`));
  for (const p of m.players) {
    const dot = el('span', { className: 'dot' });
    dot.style.background = css(p.color);
    root.append(el('div', { className: 'player' }, dot, `${p.name}${p.id === m.hostId ? ' 👑' : ''}${p.isBot ? ' 🤖' : ''}${p.id === myId ? ' (toi)' : ''}`));
  }
  if (host) {
    const bots = m.players.filter((p) => p.isBot).length;
    root.append(el('div', { className: 'row' }, el('label', {}, 'Bots pour compléter'),
      el('button', { className: 'small', onclick: () => h.bots(bots - 1) }, '−'), String(bots), el('button', { className: 'small', onclick: () => h.bots(bots + 1) }, '+')));
  }

  root.append(el('h2', {}, host ? 'Réglages de la partie' : 'Réglages (choisis par l\'hôte)'));
  const num = (value: number, min: number, max: number, step: number, set: (v: number) => void) => {
    const i = el('input', { type: 'number', value: String(value), min: String(min), max: String(max), step: String(step), disabled: !host });
    i.onchange = () => { set(Number(i.value)); push(); };
    return i;
  };
  root.append(el('div', { className: 'row' }, el('label', {}, 'Nombre de manches'), num(s.rounds, 1, 15, 1, (v) => (s.rounds = v))));
  const order = el('select', { disabled: !host, onchange: () => { s.order = order.value as SessionSettings['order']; push(); } },
    el('option', { value: 'alternate' }, 'Alterné'), el('option', { value: 'random' }, 'Aléatoire'), el('option', { value: 'list' }, 'Liste choisie'));
  order.value = s.order;
  root.append(el('div', { className: 'row' }, el('label', {}, 'Ordre des jeux'), order));
  const inc = el('div', { className: 'chips' });
  for (const g of m.metas) {
    const cb = el('input', { type: 'checkbox', checked: s.games.includes(g.id), disabled: !host });
    cb.onchange = () => {
      s.games = m.metas.map((x) => x.id).filter((id) => (id === g.id ? cb.checked : s.games.includes(id)));
      push();
    };
    inc.append(el('label', {}, cb, ` ${g.name}`));
  }
  root.append(el('div', { className: 'row' }, el('label', {}, 'Jeux inclus'), inc));
  if (s.order === 'list') {
    const list = el('div', { className: 'chips' });
    for (let i = 0; i < s.rounds; i++) {
      const sel = el('select', { disabled: !host, title: `Manche ${i + 1}` }, ...m.metas.map((g) => el('option', { value: g.id }, `${i + 1}. ${g.name}`)));
      sel.value = s.list[i] ?? m.metas[0].id;
      sel.onchange = () => { s.list[i] = sel.value; push(); };
      list.append(sel);
    }
    root.append(list);
  }

  // réglages propres à chaque jeu, générés automatiquement depuis leur schéma
  for (const g of m.metas) {
    if (!s.games.includes(g.id) && s.order !== 'list') continue;
    root.append(el('h3', {}, g.name));
    const vals = (s.game[g.id] ??= {});
    for (const [key, def] of Object.entries(g.settings)) {
      const row = el('div', { className: 'row' }, el('label', {}, def.label + (def.type === 'number' && def.unit ? ` (${def.unit})` : '')));
      if (def.type === 'number') row.append(num(vals[key] ?? def.default, def.min, def.max, def.step ?? 1, (v) => (vals[key] = v)));
      else if (def.type === 'bool') {
        const cb = el('input', { type: 'checkbox', checked: !!vals[key], disabled: !host });
        cb.onchange = () => { vals[key] = cb.checked; push(); };
        row.append(cb);
      } else {
        const chosen: string[] = vals[key] ?? [];
        const chips = el('div', { className: 'chips' });
        for (const opt of def.options) {
          const cb = el('input', { type: 'checkbox', checked: chosen.length === 0 || chosen.includes(opt), disabled: !host });
          cb.onchange = () => {
            const cur = chosen.length ? chosen : [...def.options];
            const next = def.options.filter((o) => (o === opt ? cb.checked : cur.includes(o)));
            vals[key] = next.length === def.options.length ? [] : next; // tout coché = pas de restriction
            push();
          };
          chips.append(el('label', {}, cb, ` ${opt}`));
        }
        row.append(chips);
      }
      root.append(row);
    }
  }

  if (host) root.append(el('button', { className: 'big', onclick: () => h.start() }, '▶ Lancer la partie'));
  else root.append(el('small', {}, 'En attente du lancement par l\'hôte… Entraîne-toi sur le terrain !'));
  if (m.urls.length) root.append(el('small', {}, `Adresse à donner aux autres joueurs : ${m.urls.join('  ou  ')}`));
  root.append(el('small', {}, 'Z Q S D : bouger · Espace : sauter · Souris : caméra (clic sur le jeu pour la capturer, Échap pour la libérer) · Flèches : caméra au clavier'));
  root.append(el('div', { className: 'row' }, el('label', {}, `Graphismes : ${h.quality.high ? 'élevés' : 'légers'}`),
    el('button', { className: 'small', onclick: () => h.quality.toggle() }, h.quality.high ? 'Passer en légers' : 'Passer en élevés')));
  root.scrollTop = scroll;
}

const medal = (i: number) => ['🥇', '🥈', '🥉'][i] ?? `${i + 1}.`;

export function renderScores(card: HTMLElement, m: RoundEndMsg, players: PlayerInfo[], myId: string, gameName: string): void {
  const byId = new Map(players.map((p) => [p.id, p]));
  const round = new Map(m.results.map((r) => [r.id, r]));
  const rows = Object.entries(m.totals).sort((a, b) => b[1] - a[1]);
  const table = el('table');
  rows.forEach(([id, total], i) => {
    const p = byId.get(id);
    if (!p) return;
    const r = round.get(id);
    const dot = el('span', { className: 'dot' });
    dot.style.background = css(p.color);
    table.append(el('tr', { className: id === myId ? 'me' : '' },
      el('td', {}, medal(i)), el('td', {}, dot, ` ${p.name}`), el('td', {}, r?.label ?? '—'),
      el('td', { className: 'num' }, r ? `+${r.points}` : ''), el('td', { className: 'num' }, String(total))));
  });
  card.replaceChildren(
    el('h1', {}, `Manche ${m.index + 1}/${m.total}`),
    el('h2', {}, gameName),
    table,
    el('small', {}, m.last ? 'Direction le podium…' : 'Prochaine manche dans quelques secondes…'),
  );
}

export function renderPodium(hud: HTMLElement, totals: Record<string, number>, players: PlayerInfo[], myId: string, host: boolean, back: () => void): string[] {
  const byId = new Map(players.map((p) => [p.id, p]));
  const rows = Object.entries(totals).filter(([id]) => byId.has(id)).sort((a, b) => b[1] - a[1]);
  const table = el('table');
  rows.forEach(([id, total], i) => {
    const p = byId.get(id)!;
    table.append(el('tr', { className: id === myId ? 'me' : '' }, el('td', {}, medal(i)), el('td', {}, p.name), el('td', { className: 'num' }, `${total} pts`)));
  });
  const side = el('div', { className: 'side card' }, el('h2', {}, 'Classement final'), table);
  side.style.pointerEvents = 'auto';
  if (host) side.append(el('button', { className: 'big', onclick: back }, 'Retour au lobby'));
  const winner = rows[0] ? byId.get(rows[0][0])!.name : '';
  hud.replaceChildren(el('div', { className: 'top card' }, `🏆 ${winner} remporte la partie !`), side);
  return rows.map(([id]) => id);
}

export type { GameMeta };
