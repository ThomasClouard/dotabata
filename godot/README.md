# Dotabata! — le jeu (Godot 4)

Tout le jeu est ici, **serveur compris** : menu principal avec la liste des parties du réseau local, création
d'une partie, lobby, Parcours délirant, Abri & mortier, écran des scores, podium. Chaque exe peut héberger une partie
(`server/`) ou rejoindre celle d'un autre. Tout est procédural (aucune image, aucun son, aucun modèle à charger).

## Lancer

Il faut Godot 4.7 (`winget install GodotEngine.GodotEngine`).

```bash
godot --path godot
```

Le menu principal (`ui/main_menu.gd`, décor `scenes/menu_scene.gd`) s'ouvre sur l'écran titre : ton personnage
danse dans le décor, à côté des boutons **Jouer** (parties du réseau local, qui apparaissent toutes seules, ou
rejoindre par adresse, `192.168.1.20:3000` par exemple), **Créer une partie** (nom, joueurs max, mot de passe
facultatif), **Personnage** (carrousel des 8 personnages, pseudo), **Options** (graphismes, plein écran, volume,
sensibilité de la souris, manette) et **Quitter**. Tout se pilote à la souris, au clavier (flèches, Entrée, Échap pour revenir)
ou à la manette (croix, A, B). Le créateur d'une partie en est l'hôte : il règle la partie au lobby, et les réglages
du serveur à tout moment, même pendant une manche.

Pour tester seul, `--host` crée directement un serveur (implicite avec `--bots` ou `--autostart`) :

```bash
godot --path godot -- --host --bots=5
```

Pour jouer à plusieurs sur un seul PC, lance une deuxième instance : elle trouve le serveur de la première dans
sa liste (le second serveur éventuel d'un même PC prend le port suivant).

Sur une petite carte graphique, le moteur de rendu « Compatibilité » est environ deux fois plus rapide :

```bash
godot --path godot --rendering-method gl_compatibility --rendering-driver opengl3
```

Le panneau du lobby propose trois niveaux de graphismes (légers, moyens, élevés). Au premier lancement,
les puces intégrées Intel et le web démarrent en « moyens », les autres en « élevés ».

## Réseau

- Le serveur (`server/host.gd`) écoute en WebSocket sur le port TCP 3000, ou le premier libre jusqu'à 3009. Le
  créateur s'y connecte en boucle locale avec une clé secrète qui le désigne comme hôte.
- La découverte LAN (`core/discovery.gd`) envoie toutes les 2 s une requête UDP `dotabata?` en diffusion (et vers
  ce PC) sur les ports 3000 à 3009 ; chaque serveur répond depuis le port UDP de même numéro avec son nom, ses
  joueurs, son maximum, sa phase et s'il demande un mot de passe.
- Refus à la connexion : code de fermeture 4000 (complet), 4001 (mot de passe incorrect) ; 4002 quand l'hôte
  ferme le serveur. Le mot de passe n'est jamais renvoyé aux clients.
- Windows demande d'autoriser le jeu sur le réseau au premier serveur créé : il faut accepter pour les réseaux
  privés, sinon les autres PC ne voient ni ne rejoignent le serveur.
- Le web ne peut ni héberger ni découvrir (pas de sockets serveur ni d'UDP dans un navigateur) : il rejoint par
  adresse.

Fichiers du dossier utilisateur (`user://`, soit `%APPDATA%\Godot\app_userdata\Dotabata!\` sous Windows) :
`jeux.cfg` (profil, graphismes, options, dernière adresse, réglages du serveur hébergé), `last-settings.json` (derniers
réglages de partie de l'hôte), `levels/parkour/` (niveaux perso, en plus de ceux de `levels/parkour/`).

## Ce que Godot apporte

- ombres en cascade à pénombre progressive, occlusion ambiante, halo lumineux ;
- reflets en espace écran : les îles et les obstacles se reflètent dans la mer et sur la glace ;
- mer éclairée par le moteur (reflets du ciel et du soleil, vaguelettes et écume par pixel) ;
- léger flou des lointains, façon maquette ;
- membres des personnages déformés dans le vertex shader (plus aucun recalcul de maillage par image).

Ces effets demandent le moteur Forward+ et le niveau « élevés ». Le web et le moteur Compatibilité
gardent les ombres, le halo et la mer, sans occlusion ambiante, reflets ni flou.

## Options de lancement

Après `--` sur bureau, ou dans l'URL sur le web (`?server=…&bots=9`) :

| Option | Effet |
|---|---|
| `--host` | crée un serveur dès le lancement (implicite avec `--bots` ou `--autostart`) |
| `--server=hôte:port` | rejoint directement ce serveur |
| `--name=…`, `--hat=…` | pseudo et personnage |
| `--quality=basse\|moyenne\|haute` | niveau de graphismes |
| `--msaa=on\|off` | force le MSAA du niveau « élevés » (coupé d'office sur les Radeon HD 7000 à R9 300, dont le pilote noircit l'image avec l'occlusion ambiante et les reflets) |
| `--no-save` | ne pas enregistrer le profil ni les réglages |
| `--bots=9` | remplit le lobby de bots (si l'on est l'hôte) |
| `--autostart` | lance la partie dès que les bots sont là |
| `--games=mortar --rounds=1` | restreint les jeux et le nombre de manches |
| `--set=mortar.buildTime=5,parkour.duration=45` | règle des options de jeu |
| `--auto`, `--auto=fire` | pilote automatique (court et saute, ou reste sur place et tire) |
| `--shot=chemin.png --shot-at=5,12` | captures d'écran à ces instants, puis quitte |
| `--looks=x,y,z,lacet,tangage,dist;…` | vue imposée 1,2 s avant chaque capture (dist = 0 : téléporte le joueur en x,y,z) |
| `--menu=jouer\|creer\|personnage\|options\|manette` | ouvre directement cet écran du menu |
| `--keys=3:ui_down,3.3:ui_accept,4:joy0` | navigation simulée : action d'interface ou bouton de manette (`joyN`) à cet instant |
| `--trace`, `--quit-at=30`, `--vsync=off` | mesures et arrêt automatique |

Exemple : une manche de mortier contre neuf bots, avec deux captures.

```bash
godot --path godot -- --bots=9 --games=mortar --rounds=1 --autostart --shot=capture.png --shot-at=10,25
```

Attention : `--games`, `--rounds` et `--set` envoient des réglages au serveur, qui les enregistre dans
`user://last-settings.json` comme le ferait l'hôte depuis le lobby.

## Tests

Le serveur : parties complètes jouées par des bots sur les 7 niveaux et les niveaux d'essai, règles du parcours
avec de faux joueurs (boutons, leviers, dalles mémoire, objets, pièces), bataille de mortier.

```bash
godot --headless --path godot -s res://tests/run_server_tests.gd
```

`-- --only=balade,mortier` ne lance que certains cas. Bout en bout : un vrai serveur sur un port, des clients
WebSocket (hôte, mot de passe refusé puis accepté, serveur plein), la découverte UDP, les réglages du serveur
modifiés avec un autre joueur connecté puis en pleine manche, la fermeture annoncée.

```bash
godot --headless --path godot -s res://tests/run_host_test.gd
```

Parité : la physique, la cinématique des obstacles, la balistique, le validateur de niveaux (chemin des bots), le
schéma des niveaux, les réglages et les scores sont portés à l'identique de la référence TypeScript (`shared/`,
`games/*/shared.ts`, que le MCP de niveaux utilise aussi). `tools/gen-golden.mjs` rejoue des scénarios avec ces
sources et enregistre les résultats ; `tests/run_tests.gd` rejoue les mêmes en GDScript et compare à 10⁻⁶ près.

```bash
node --import tsx godot/tools/gen-golden.mjs
```

```bash
godot --headless --path godot -s res://tests/run_tests.gd
```

À relancer après toute modification de `shared/src/` ou des fichiers `games/*/shared.ts`, puis reporter le
changement dans `godot/sim/` ou `godot/server/`.

## Exports

Les modèles d'export de Godot doivent être installés (éditeur : Éditeur → Gérer les modèles d'export).
Sous Windows, `compiler.cmd` à la racine du dépôt fait tout : il trouve Godot dans le PATH ou dans son
installation winget, installe si besoin les modèles d'export de cette version (`tools/install-templates.ps1`,
téléchargés depuis les versions officielles de Godot sur GitHub, environ 1,3 Go), importe les ressources puis exporte ;
`compiler.cmd web` exporte aussi la version web.
À la main :

```bash
godot --headless --path godot --export-release "Windows Desktop" build/windows/Dotabata.exe
```

L'exe contient tout (niveaux de `levels/parkour/` et `config/defaults.json` compris) : c'est le seul fichier à
copier sur les PC des joueurs.

```bash
godot --headless --path godot --export-release "Web" build/web/index.html
```

La version web se sert avec un petit serveur statique, `node godot/tools/serve-web.mjs` (port 8080). Elle se
connecte au serveur de jeu de la machine qui sert la page (port 3000), hébergé par un exe lancé sur ce PC. La
page doit être servie en `http://` : en `https://`, le navigateur refuserait la connexion `ws://`.

## Organisation

| Dossier | Rôle |
|---|---|
| `core/` | boucle, phases, réseau, découverte LAN, entrées clavier / souris / manette (`pad.gd` : boutons réglables), options |
| `server/` | serveur intégré : WebSocket et découverte (`host.gd`), session (`session.gd`), scores, niveaux sur le disque, validateur, fiches des jeux |
| `server/games/` | règles serveur et bots des deux mini-jeux |
| `sim/` | physique, obstacles, règles partagées (float 64 bits) |
| `character/` | personnages procéduraux, peau trouée, squelette |
| `gfx/` | matériaux, formes, textures, ciel, mer, particules, shaders |
| `games/` | affichage des deux mini-jeux |
| `scenes/` | terrain du lobby, décor du menu, podium |
| `ui/` | thème, logo, curseurs de souris, menu principal, lobby, scores, podium, HUD |
| `audio/` | 17 sons synthétisés au démarrage |
| `levels/parkour/` | niveaux de parcours (écrits aussi par le MCP) |
| `config/` | réglages de partie par défaut |
| `tests/`, `tools/` | tests du serveur et de parité, vecteurs de référence, serveur web statique |

Ajouter un mini-jeu : sa fiche dans `server/metas.gd`, sa classe `ServerGame` dans `server/games/`, sa classe
`ClientGame` dans `games/<nom>/` inscrite dans `core/registry.gd` (détails dans le README racine).
