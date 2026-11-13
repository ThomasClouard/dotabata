// Serveur MCP (stdio) pour créer et modifier les niveaux de parcours.
// Il partage le schéma zod et la physique du jeu : un niveau validé ici est exactement celui que le jeu charge.
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { LevelSchema, elementCatalog, type Level } from '../../shared/src/level';
import { asciiPreview, validateLevel } from '../../shared/src/level-validate';
import { LEVELS_DIR, deleteLevel, levelExists, listLevels, readLevel, writeLevel } from '../../shared/src/level-store';

const server = new McpServer({ name: 'jeux-niveaux', version: '1.0.0' });

const text = (t: string) => ({ content: [{ type: 'text' as const, text: t }] });
const fail = (t: string) => ({ content: [{ type: 'text' as const, text: t }], isError: true });
const json = (v: unknown) => JSON.stringify(v, null, 2);

const elementsArg = z.array(z.record(z.unknown())).describe('Éléments du niveau. Voir get_element_catalog pour les types et leurs paramètres.');
const meta = {
  title: z.string().optional().describe('Titre affiché en jeu'),
  author: z.string().optional(),
  difficulty: z.number().int().min(1).max(5).optional().describe('1 (facile) à 5 (corsé)'),
  sky: z.string().optional().describe('Couleur du ciel, "#rrggbb"'),
  sea: z.string().optional().describe('Couleur de la mer sous le parcours, "#rrggbb" (défaut : slime rose)'),
  killY: z.number().optional().describe('Altitude sous laquelle on réapparaît (par défaut : 12 m sous l\'élément le plus bas)'),
};

/** Valide la forme du niveau avec le schéma du jeu ; messages lisibles en cas d'erreur. */
function parse(raw: unknown): { level?: Level; error?: string } {
  const r = LevelSchema.safeParse(raw);
  if (r.success) return { level: r.data };
  const lines = r.error.issues.slice(0, 20).map((i) => `- ${i.path.join('.') || '(racine)'} : ${i.message}`);
  return { error: `Niveau mal formé :\n${lines.join('\n')}\nAppelle get_element_catalog pour voir les types et paramètres acceptés.` };
}

/** Donne un id unique à chaque élément qui n'en a pas, pour pouvoir les retirer par id ensuite. */
function withIds(level: Level): Level {
  const used = new Set(level.elements.map((e) => e.id).filter(Boolean));
  for (const e of level.elements) {
    if (e.id) continue;
    let k = 1;
    while (used.has(`${e.type}-${k}`)) k++;
    e.id = `${e.type}-${k}`;
    used.add(e.id);
  }
  return level;
}

function report(level: Level, action: string): string {
  const v = validateLevel(level);
  return [
    `${action} « ${level.name} » (${level.elements.length} éléments).`,
    v.ok ? `✅ Terminable — longueur ≈ ${v.stats.pathLength} m, durée estimée ≈ ${v.stats.estimatedSeconds} s, ${v.stats.checkpoints} checkpoint(s). Il apparaît dans le lobby du jeu sans redémarrage.`
      : '❌ Pas encore terminable : le jeu ne le proposera pas tant que ces erreurs subsistent.',
    ...v.errors.map((e) => `Erreur : ${e}`),
    ...v.warnings.map((w) => `Avertissement : ${w}`),
  ].join('\n');
}

function safely<A>(fn: (args: A) => ReturnType<typeof text>) {
  return async (args: A) => {
    try { return fn(args); } catch (e) { return fail(e instanceof Error ? e.message : String(e)); }
  };
}

server.registerTool('list_levels', { description: 'Liste les niveaux de parcours présents, avec leur état de validation.', inputSchema: {} }, safely(() => {
  const rows = listLevels().map((name) => {
    try {
      const l = readLevel(name), v = validateLevel(l);
      return { name, title: l.title, difficulty: l.difficulty, elements: l.elements.length, playable: v.ok, estimatedSeconds: v.stats.estimatedSeconds };
    } catch (e) {
      return { name, playable: false, error: e instanceof Error ? e.message : String(e) };
    }
  });
  return text(json({ directory: LEVELS_DIR, levels: rows }));
}));

server.registerTool('get_level', { description: 'Renvoie le JSON complet d\'un niveau.', inputSchema: { name: z.string() } }, safely(({ name }) => text(json(readLevel(name)))));

server.registerTool('get_element_catalog', {
  description: 'Catalogue des types d\'éléments (plateformes, obstacles, checkpoints…), de leurs paramètres, des conventions d\'axes et des limites de saut du personnage. À lire avant de créer un niveau.',
  inputSchema: {},
}, safely(() => text(json(elementCatalog()))));

server.registerTool('create_level', {
  description: 'Crée un nouveau niveau de parcours et l\'enregistre. Renvoie le rapport de validation (faisabilité des sauts, atteignabilité des checkpoints).',
  inputSchema: { name: z.string().describe('Identifiant : minuscules, chiffres, tirets'), ...meta, elements: elementsArg },
}, safely((a) => {
  if (levelExists(a.name)) return fail(`Le niveau « ${a.name} » existe déjà. Utilise update_level ou add_elements, ou choisis un autre nom.`);
  const p = parse(a);
  if (!p.level) return fail(p.error!);
  writeLevel(withIds(p.level));
  return text(report(p.level, 'Niveau créé :'));
}));

server.registerTool('update_level', {
  description: 'Modifie un niveau existant : métadonnées et/ou remplacement complet de la liste d\'éléments.',
  inputSchema: { name: z.string(), ...meta, elements: elementsArg.optional() },
}, safely((a) => {
  const cur = readLevel(a.name);
  const patch = Object.fromEntries(Object.entries(a).filter(([, v]) => v !== undefined));
  const p = parse({ ...cur, ...patch });
  if (!p.level) return fail(p.error!);
  writeLevel(withIds(p.level));
  return text(report(p.level, 'Niveau mis à jour :'));
}));

server.registerTool('add_elements', {
  description: 'Ajoute des éléments à un niveau. Par défaut à la fin ; `index` permet d\'insérer ailleurs (l\'ordre des checkpoints dans le tableau fixe leur numérotation).',
  inputSchema: { name: z.string(), elements: elementsArg, index: z.number().int().min(0).optional() },
}, safely(({ name, elements, index }) => {
  const cur = readLevel(name);
  const list: unknown[] = [...cur.elements];
  list.splice(index ?? list.length, 0, ...elements);
  const p = parse({ ...cur, elements: list });
  if (!p.level) return fail(p.error!);
  writeLevel(withIds(p.level));
  return text(report(p.level, `${elements.length} élément(s) ajouté(s) à`));
}));

server.registerTool('remove_elements', {
  description: 'Retire des éléments d\'un niveau, par id et/ou par index (voir get_level).',
  inputSchema: { name: z.string(), ids: z.array(z.string()).optional(), indices: z.array(z.number().int().min(0)).optional() },
}, safely(({ name, ids = [], indices = [] }) => {
  const cur = readLevel(name);
  const kept = cur.elements.filter((e, i) => !indices.includes(i) && !(e.id && ids.includes(e.id)));
  const removed = cur.elements.length - kept.length;
  if (!removed) return fail('Aucun élément ne correspond à ces ids / index.');
  const p = parse({ ...cur, elements: kept });
  if (!p.level) return fail(p.error!);
  writeLevel(p.level);
  return text(report(p.level, `${removed} élément(s) retiré(s) de`));
}));

server.registerTool('validate_level', {
  description: 'Vérifie qu\'un niveau est terminable avec la physique du jeu : départ et arrivée présents, chaque saut à portée, checkpoints atteignables dans l\'ordre. Passer `name` (niveau enregistré) ou `level` (brouillon non enregistré).',
  inputSchema: { name: z.string().optional(), level: z.record(z.unknown()).optional().describe('Niveau complet { name, elements, … } à vérifier sans l\'enregistrer') },
}, safely(({ name, level }) => {
  let l: Level;
  if (level) {
    const p = parse({ name: 'brouillon', ...level });
    if (!p.level) return fail(p.error!);
    l = p.level;
  } else if (name) l = readLevel(name);
  else return fail('Indique `name` ou `level`.');
  const v = validateLevel(l);
  return text(json({ ok: v.ok, errors: v.errors, warnings: v.warnings, stats: v.stats, path: v.path.map((i) => ({ index: i, type: l.elements[i].type, id: l.elements[i].id })) }));
}));

server.registerTool('preview_level', { description: 'Vue de dessus du niveau en ASCII, pour vérifier la disposition d\'un coup d\'œil.', inputSchema: { name: z.string() } },
  safely(({ name }) => text(asciiPreview(readLevel(name)))));

server.registerTool('delete_level', { description: 'Supprime définitivement un niveau.', inputSchema: { name: z.string() } }, safely(({ name }) => {
  if (!levelExists(name)) return fail(`Niveau introuvable : « ${name} ».`);
  deleteLevel(name);
  return text(`Niveau « ${name} » supprimé.`);
}));

await server.connect(new StdioServerTransport());
