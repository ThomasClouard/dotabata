# Dotabata! — client Godot

Réécriture du **client** du jeu avec le moteur Godot 4. Le jeu d'origine (client navigateur three.js et
serveur Node) n'est pas modifié : ce client parle au **même serveur**, par le même protocole WebSocket.
Les joueurs Godot et les joueurs navigateur se retrouvent donc dans la même partie.

Tout le jeu est là : lobby, Parcours délirant, Abri & mortier, écran des scores, podium. Comme dans
l'original, tout est procédural (aucune image, aucun son, aucun modèle à charger).

## Lancer

Il faut Godot 4.7 (`winget install GodotEngine.GodotEngine`) et le serveur du jeu d'origine.

```bash
npm run serve
```

```bash
godot --path godot
```

`npm run serve` démarre le serveur sans reconstruire le client d'origine (port 3000). Le client Godot
s'y connecte tout seul sur `localhost:3000` ; sinon il affiche un écran où saisir l'adresse
(`192.168.1.20:3000` par exemple), qu'il retient pour la fois suivante.

Sur une petite carte graphique, le moteur de rendu « Compatibilité » est environ deux fois plus rapide :

```bash
godot --path godot --rendering-method gl_compatibility --rendering-driver opengl3
```

Le panneau du lobby propose trois niveaux de graphismes (légers, moyens, élevés). Au premier lancement,
les puces intégrées Intel et le web démarrent en « moyens », les autres en « élevés ».

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
| `--server=hôte:port` | adresse du serveur de jeu |
| `--name=…`, `--hat=…` | pseudo et personnage |
| `--quality=basse\|moyenne\|haute` | niveau de graphismes |
| `--no-save` | ne pas enregistrer le profil ni les réglages |
| `--bots=9` | remplit le lobby de bots (si l'on est l'hôte), comme `?bots=9` du client d'origine |
| `--autostart` | lance la partie dès que les bots sont là |
| `--games=mortar --rounds=1` | restreint les jeux et le nombre de manches |
| `--set=mortar.buildTime=5,parkour.duration=45` | règle des options de jeu |
| `--auto`, `--auto=fire` | pilote automatique (court et saute, ou reste sur place et tire) |
| `--shot=chemin.png --shot-at=5,12` | captures d'écran à ces instants, puis quitte |
| `--looks=x,y,z,lacet,tangage,dist;…` | vue imposée 1,2 s avant chaque capture (dist = 0 : téléporte le joueur en x,y,z) |
| `--trace`, `--quit-at=30`, `--vsync=off` | mesures et arrêt automatique |

Exemple : une manche de mortier contre neuf bots, avec deux captures.

```bash
godot --path godot -- --bots=9 --games=mortar --rounds=1 --autostart --shot=capture.png --shot-at=10,25
```

Attention : `--games`, `--rounds` et `--set` envoient des réglages au serveur, qui les enregistre dans
`config/last-settings.json` comme le ferait l'hôte depuis le lobby.

## Tests de parité

La physique, la cinématique des obstacles et la balistique sont portées à l'identique : c'est ce qui
garantit que tout le monde voit les mêmes obstacles au même instant et saute aussi loin.
`tools/gen-golden.mjs` rejoue des scénarios avec les sources TypeScript d'origine et enregistre les
résultats (dont le niveau d'essai `tests/fixtures/parkour/vague1.json`, qui contient tous les types d'éléments) ; `tests/run_tests.gd` rejoue les mêmes en GDScript et compare à 10⁻⁶ près.

```bash
node --import tsx godot/tools/gen-golden.mjs
```

```bash
godot --headless --path godot -s res://tests/run_tests.gd
```

À relancer après toute modification de `shared/src/physics.ts`, `shared/src/level.ts` ou des fichiers
`games/*/shared.ts`, puis reporter le changement dans `godot/sim/`.

## Exports

Les modèles d'export de Godot doivent être installés (éditeur : Éditeur → Gérer les modèles d'export).

```bash
godot --headless --path godot --export-release "Windows Desktop" build/windows/Dotabata.exe
```

```bash
godot --headless --path godot --export-release "Web" build/web/index.html
```

La version web se sert avec un petit serveur statique séparé, pour ne pas toucher au serveur du jeu :

```bash
node godot/tools/serve-web.mjs
```

Elle s'ouvre sur `http://<adresse>:8080` et se connecte au serveur de jeu de la même machine (port 3000).
La page doit être servie en `http://` : en `https://`, le navigateur refuserait la connexion `ws://`.

## Organisation

| Dossier | Rôle | Origine |
|---|---|---|
| `core/` | boucle, phases, réseau, entrées, options | `client/src/main.ts`, `net.ts`, `input.ts`, `api.ts` |
| `sim/` | physique, obstacles, règles partagées (float 64 bits) | `shared/src/physics.ts`, `level.ts`, `games/*/shared.ts` |
| `character/` | personnages procéduraux, peau trouée, squelette | `client/src/character/character.ts` |
| `gfx/` | matériaux, formes, textures, ciel, mer, particules, shaders | `client/src/gfx.ts`, `particles.ts` |
| `games/` | affichage des deux mini-jeux | `games/*/client.ts` |
| `scenes/` | terrain du lobby, podium | `client/src/scenes.ts` |
| `ui/` | thème, lobby, scores, podium, HUD | `client/index.html`, `client/src/ui.ts` |
| `audio/` | 17 sons synthétisés au démarrage | `client/src/audio.ts` |
| `tests/`, `tools/` | parité, vecteurs de référence, serveur web statique | `tests/*.test.ts` |

Ajouter un mini-jeu : écrire sa classe `ClientGame` dans `games/<nom>/`, puis l'inscrire dans
`core/registry.gd` (l'équivalent de `games/registry.client.ts`).

## Différences avec le client d'origine

- Les emojis de l'interface sont remplacés par du texte (pas de police d'emojis sur le web).
- Le changement de graphismes s'applique tout de suite, sans recharger.
- L'adresse affichée dans le lobby reste celle du client navigateur d'origine.
- Les teintes diffèrent légèrement (autre courbe de tons que three.js).
