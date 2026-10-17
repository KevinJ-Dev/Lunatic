# nc_pommes — NightCraft Studio

Farm de pommes pour ESX + ox_inventory : **récolte** au verger de Grapeseed → **pressage** en jus → **vente** au grossiste.

## Dépendances

- es_extended (ESX Legacy)
- ox_lib
- ox_inventory

Pas besoin d'ox_target : tout se fait à la touche **E**.

## Installation

1. Dépose le dossier `nc_pommes` dans `resources/`.
2. Ouvre `ox_inventory/data/items.lua` et colle le contenu de `install/items.lua` à l'intérieur du `return { ... }`.
3. Copie `install/images/pomme.png` et `install/images/jus_pomme.png` dans `ox_inventory/web/images/`.
4. Dans `server.cfg`, après ox_lib, es_extended et ox_inventory :
   ```
   ensure nc_pommes
   ```
5. Redémarre le serveur (ox_inventory ne recharge les items qu'au redémarrage).

Aucune table SQL à importer.

## Comment ça marche en jeu

| Étape | Où | Ce qui se passe |
|---|---|---|
| Récolte | 7 arbres au verger | 6 s de cueillette, 2 à 4 pommes, l'arbre repousse au bout de 90 s (commun à tous les joueurs) |
| Pressage | Pressoir | 3 pommes → 1 jus, 2,5 s par jus, choix de la quantité |
| Vente | Grossiste (PNJ) | Pomme 6 $, jus 28 $ — le jus rapporte plus que les pommes brutes |

Les pommes se mangent (faim) et le jus se boit (soif).

## Réglages

Tout est dans `config.lua` : job requis, positions, durées, quantités, prix, compte payé (`money`, `bank`, `black_money`), blips, marqueurs et textes.

### Ajouter ou déplacer des arbres

1. Mets `Config.Debug = true` et redémarre la resource.
2. Place-toi au pied d'un arbre et tape `/pommepos` : la ligne `vec3(x, y, z),` est copiée dans ton presse-papier.
3. Colle-la dans `Config.Harvest.trees`.
4. Remets `Config.Debug = false`.

La même commande sert pour déplacer le pressoir ou le grossiste.

### Réserver à un job

```lua
Config.Job = 'fermier'              -- un job
Config.Job = { 'fermier', 'autre' } -- plusieurs
Config.Job = false                  -- tout le monde
```

## Sécurité

Le serveur vérifie tout : distance au point, durée réelle de l'action, stock et place dans l'inventaire, quantités envoyées. Un joueur qui déclenche les events à la main ne reçoit rien.
