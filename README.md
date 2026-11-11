# 🎉 Dotabata! — party game LAN 3D dans le navigateur

Party game pour 2 à 10 joueurs sur le même réseau local. Un PC héberge, les autres ouvrent un lien dans leur navigateur : rien à installer côté joueurs. Une partie enchaîne des manches de mini-jeux (10–15 min au total) avec classement cumulé et podium final.

*Dotabata* (ドタバタ) : en japonais, le chahut maladroit, tout le monde qui court et trébuche dans tous les sens.

Deux mini-jeux pour l'instant :

- **Parcours délirant** — course d'obstacles avec checkpoints, 7 niveaux : *balade*, *usine*, *vertige*, *fete-foraine*, *volcan*, *labo*, *chateau*. Éléments :
  - sols : plateformes, glace, tapis roulants, dalles friables, plateformes mobiles, rouleaux, plateaux tournants, grande roue, pistons, dalles clignotantes, boue, gélatine, rampes et toboggans, speed pads, bulles ;
  - obstacles : marteaux, barres tournantes, balayeurs, canons pousseurs, poinçonneurs, guillotines, boules de démolition, étaux, boules qui dévalent, lave / eau / acide ;
  - propulseurs et zones : trampolines (simples ou directionnels), ventilateurs, canons à joueurs, tyroliennes, téléporteurs, zones lunaires, rafales ;
  - interactions : boutons et portes, leviers et trappes, dalles mémoire piégées, boîtes surprise (super saut, bouclier, banane, gant de boxe), pièces ;
  - décor : arbres, ballons, foule, panneaux, brouillard, faux murs (raccourcis secrets).

  Réglages de la manche en plus de la durée et des niveaux : **Bousculades entre joueurs** (on peut faire trébucher en fonçant sur quelqu'un ; désactivé = on se traverse) et **Pièces : départager les ex æquo**.
- **Abri & mortier** — chacun construit un abri sur son île flottante, puis bombarde les voisins au mortier. Dernier survivant gagne.

## Lancer une partie

Prérequis : Node.js 22.

```bash
npm install
```

```bash
npm start
```

Le serveur affiche l'adresse à donner aux autres joueurs (`http://<ip-du-pc>:3000`). Si les autres PC n'arrivent pas à se connecter, autorise Node.js dans le pare-feu Windows (réseau privé, port 3000).

Le premier joueur connecté est l'hôte (👑) : il règle la partie dans le lobby et la lance. Tout est paramétrable : nombre de manches, ordre des jeux (alterné, aléatoire ou liste choisie), jeux inclus, niveaux autorisés et réglages propres à chaque jeu. Les valeurs de départ sont dans [config/defaults.json](config/defaults.json) ; les derniers réglages de l'hôte sont mémorisés dans `config/last-settings.json`.

Variable d'environnement : `JEUX_PORT` change le port du serveur (3000 par défaut).

### Commandes

| Action | Touches |
| --- | --- |
| Bouger | Z Q S D (les touches sont lues par position : W A S D sur un clavier QWERTY) |
| Sauter | Espace |
| Parcours — utiliser l'objet tenu | E ou clic droit |
| Caméra | Souris (clic sur le jeu pour la capturer, Échap pour la libérer) ou flèches |
| Mortier — construire | Clic gauche ou F : poser · clic droit ou R : retirer · 1 2 3 : matériau |
| Mortier — tirer | Maintenir le clic gauche (ou F) pour charger, relâcher pour tirer |

## Développement

```bash
npm run dev
```

Lance le serveur de jeu (port 3000, relancé à chaque modification) et Vite (port 5173, rechargement à chaud). Ouvre `http://localhost:5173`.

- `http://localhost:5173/?bots=9` remplit le lobby de bots pour tester seul (l'hôte peut aussi en ajouter depuis le lobby).
- `npm test` — tests vitest : physique, schéma et validation des niveaux, scores, balistique, et **parties complètes jouées par des bots** sur chaque niveau.
- `npm run typecheck` — vérification TypeScript de tout le dépôt.
- Dans la console du navigateur, `jeux` donne accès à l'état du client (corps du joueur, joueurs, réseau).

## Architecture

```
shared/src/   physique maison, protocole, contrat des jeux, scores, format + validation des niveaux
server/src/   serveur HTTP + WebSocket : lobby, manches, scores, relais des états
client/src/   rendu three.js, caméra, personnage désarticulé, interface, sons synthétisés
games/<id>/   un mini-jeu = shared.ts (règles communes) + server.ts (autorité) + client.ts (affichage)
levels/parkour/*.json   niveaux de parcours
mcp/src/      serveur MCP pour créer des niveaux
tests/        tests vitest
```

Principes réseau, pensés pour le LAN :

- **Chaque client simule son propre personnage** avec la physique partagée et envoie son état 30 fois par seconde : réactivité parfaite, sans prédiction ni réconciliation. Les autres joueurs sont interpolés.
- **Le serveur fait autorité sur les règles** : phases, chronos, checkpoints, arrivées, obus, destruction des blocs, dégâts, scores.
- **Les obstacles sont déterministes** : leur position est une fonction pure de l'horloge serveur synchronisée, donc rien à synchroniser.

Le rendu est entièrement procédural (aucune texture ni modèle à charger) : formes arrondies, matériaux brillants, ombres portées, ciel en dégradé, mer animée et bloom, réunis dans [client/src/gfx.ts](client/src/gfx.ts). Sur une petite machine, le bouton « Graphismes » en bas du lobby bascule en mode léger (sans ombres ni bloom) ; le choix est mémorisé par navigateur.

Les dégâts sont visibles sans une goutte de sang : chaque personnage a un squelette cartoon sous sa peau, et le shader de la peau efface les fragments autour des points d'impact. À 0 PV il ne reste qu'un tas d'os (et un petit air de xylophone).

## Ajouter un mini-jeu

1. Crée `games/<id>/shared.ts` avec un `GameMeta` : identifiant, nom, description et `settings` (chaque réglage déclare son type, sa valeur par défaut et ses bornes — le lobby génère le formulaire tout seul).
2. Crée `games/<id>/server.ts` qui exporte un `ServerGameModule` ([shared/src/game-api.ts](shared/src/game-api.ts)) : `onStart` (renvoie les données d'initialisation et les points d'apparition), `onTick`, `onPlayerMessage`, `onPlayerLeave`, `getResults`, et `botTick` si tu veux des bots.
3. Crée `games/<id>/client.ts` qui exporte une fabrique de `ClientGame` ([client/src/api.ts](client/src/api.ts)) : `onEnter`, `onMessage`, `onFrame`, `onExit`, `colliders` (les boîtes de collision du joueur local).
4. Ajoute une ligne dans chacun des trois registres : [games/registry.ts](games/registry.ts), [games/registry.server.ts](games/registry.server.ts), [games/registry.client.ts](games/registry.client.ts).

Le cœur fournit le reste : personnage, caméra, réseau, `ctx.damage()` pour marquer la peau d'un joueur, `ctx.impulse()` pour l'envoyer valser, scores et enchaînement des manches.

## Créer des niveaux de parcours avec le MCP

Le dépôt contient un serveur MCP déclaré dans [.mcp.json](.mcp.json) : ouvre le dossier avec Claude Code, accepte le serveur `jeux-niveaux`, puis demande par exemple « crée un niveau de parcours difficile avec trois marteaux et un passage sur la glace ».

Outils disponibles : `list_levels`, `get_level`, `get_element_catalog`, `create_level`, `update_level`, `add_elements`, `remove_elements`, `validate_level`, `preview_level`, `delete_level`.

`validate_level` utilise le schéma et la physique du jeu : il vérifie qu'il y a un départ et une arrivée, que chaque saut est à portée du personnage (avec 15 % de marge) et que les checkpoints s'enchaînent. Un niveau enregistré apparaît dans le lobby sans redémarrer le serveur ; un niveau non terminable n'est jamais proposé en jeu.

On peut aussi écrire les fichiers à la main dans `levels/parkour/` — le format est décrit par `get_element_catalog` et par [shared/src/level.ts](shared/src/level.ts).

## Limites connues

- La physique est maison (capsule contre boîtes). Elle suffit pour ces deux jeux ; un futur jeu qui demanderait de vrais empilements ou des véhicules devra brancher un moteur (Rapier) derrière `shared/src/physics.ts`.
- Un joueur qui arrive en cours de partie attend la manche suivante.
- Les clients sont de confiance (chacun annonce sa propre position) : c'est un jeu entre amis, pas un jeu en ligne compétitif.
