# novyra_hud — NightCraft Studio

HUD de statuts minimaliste pour ESX : vie, armure, faim, soif, endurance, oxygène.

## Installation

1. Place le dossier `novyra_hud` dans `resources/`.
2. Ajoute dans `server.cfg`, après `es_extended` et `esx_status` :

   ```
   ensure novyra_hud
   ```

3. Règle `config.lua` (position, taille, couleurs, statuts affichés).

La faim et la soif viennent de `esx_status` / `esx_basicneeds` s'ils tournent. Sinon le HUD les gère lui-même (voir « Faim et soif »).

## Styles

Dans `config.lua`, `Config.Style` change l'apparence des cercles :

- `'ring'` : anneau lumineux autour de l'icône
- `'liquid'` : bulle qui se remplit de liquide
- `'segments'` : anneau découpé en 12 crans (par défaut)

`Config.ShowPercent = true` affiche le pourcentage sous chaque cercle.
`Config.Animations = false` coupe toutes les animations.

## En jeu

- `/hud` : afficher / masquer le HUD.
- `/hud info` : valeurs exactes de faim et de soif, et qui les gère (le HUD ou `esx_status`).
- L'armure n'apparaît que si le joueur en porte, l'endurance quand elle baisse, l'oxygène sous l'eau.
- Sous 20 %, le cercle passe au rouge et clignote.
- Le cercle tremble en rouge quand on perd de la vie ou de l'armure, et s'illumine quand on se soigne, mange ou boit.
- À la mort, le cœur devient un crâne.

## Masquer le HUD depuis un autre script

```lua
exports.novyra_hud:setVisible(false) -- cacher (menu, cinématique, création de perso...)
exports.novyra_hud:setVisible(true)  -- réafficher
```

## Minimap et écrans

- `Config.MinimapLeft = true` colle la minimap tout à gauche sur les écrans larges (21:9, 32:9). Mets `false` si un autre script déplace déjà ta minimap.
- Le HUD se cale sur la vraie position de la minimap et suit le format d'écran, la résolution et le réglage « zone de sécurité » du jeu.

## Faim et soif

`Config.Needs.Mode` dans `config.lua` :

- `'auto'` (par défaut) : si `esx_status` + `esx_basicneeds` tournent, le HUD affiche leurs valeurs. Sinon il gère lui-même la faim et la soif.
- `'esx_status'` : uniquement `esx_status`.
- `'builtin'` : toujours géré par le HUD.

Quand le HUD gère la faim et la soif lui-même :

- elles descendent avec le temps (`HungerMinutes`, `ThirstMinutes`) et le joueur perd de la vie à 0 % ;
- elles sont sauvegardées par personnage, sur le PC du joueur ;
- la nourriture et les boissons d'`ox_inventory` fonctionnent sans rien changer (le HUD écoute `esx_status:add` / `esx_status:remove`).

Depuis un autre script (valeurs de 0 à 100) :

```lua
exports.novyra_hud:addStatus('hunger', 25)  -- manger
exports.novyra_hud:setStatus('thirst', 100) -- fixer la valeur
exports.novyra_hud:getStatus('hunger')      -- lire la valeur
```

## Aperçu sans lancer le jeu

Ouvre `html/index.html` dans un navigateur : le HUD s'affiche avec des valeurs de démonstration.
Touches `1` `2` `3` pour changer de style, `P` pour les pourcentages, `M` pour la position, `D` pour simuler des dégâts, `S` pour un soin.
