# lunatic_illegal

Côté jeu de l'illégal. Les données se gèrent dans le panel staff (`lunatic_admin`).

## Installation

Dans `resources/[8_Creation_script]`, démarrée par `ensure [8_Creation_script]`.
Dépendances : `es_extended`, `ox_lib`, `ox_inventory`. Utilise `lunatic_admin` (crews, drogues, recelleur) pendant son fonctionnement.
`lunatic_admin` n'est pas une dépendance déclarée dans le manifeste : sinon chaque `ensure lunatic_admin` arrêterait cette resource sans la relancer.

## Étape 1 : crews

Les crews (type Mafia, MC, Organisation ou Gang, rangs, membres, XP et level) se créent dans la tuile **Crews** du panel.
Un personnage appartient au plus à un crew, indépendamment de son métier ESX.

En jeu, **`/crew`** (configurable : `Config.CrewCommand`) :

- tout membre : type et level du crew, XP, liste des membres ;
- le **chef** (rang le plus haut) : inviter un joueur proche (`Config.InviteDistance`, réponse dans `Config.InviteTimeout` secondes), promouvoir, rétrograder, renvoyer (jamais un autre chef) ;
- les autres membres : quitter le crew (le chef ne peut pas : le staff nomme un autre chef depuis le panel).

Pour les autres scripts : `Player(source).state.crew` = `{ id, slug, label, type, color, rank, rankLabel, leader, level }` ou `nil`.
Exports serveur de `lunatic_admin` : `getCrewOf(identifier)`, `getCrewView(crewId)`, `setCrewMember(identifier, crewId|nil, rank)`, `addCrewXp(crewId, amount)`.

## Étape 2 : recelleur

Catalogue (objet, prix de rachat, catégorie) et emplacements des PNJ dans le panel (tuile Illégal, onglet Recelleur).
En jeu : PNJ immobile et invulnérable, sans blip ; `[E]` à `Config.FenceDistance` liste les objets du catalogue que le joueur possède ; revente vérifiée par le serveur (distance, quantité), payée sur `Config.FenceAccount` (argent sale par défaut). `Config.FenceCrewOnly` réserve le recelleur aux membres d'un crew.

## Étape 3 : drogues

Drogues et laboratoires dans le panel (tuile Illégal, onglet Drogues).

- **Laboratoires** : marqueur et `[E]` visibles par les membres d'un crew du type autorisé ; production en deux temps (barre de progression annulable, ingrédients retirés et drogue donnée à la fin, durée vérifiée par le serveur).
- **Vente aux passants** : avec au moins le volume minimum sur soi, `[E]` près d'un PNJ qui marche (`Config.SellDistance`), une tentative par passant. Le serveur vérifie la distance, le délai (`Config.SellCooldown`), le nombre de policiers en service (joueurs connectés au métier d'une structure de type Police) et la quantité. Acceptation `Config.SellChance`, quantité entre les volumes min et max, prix ±`Config.PriceVariation`, payé sur `Config.SellAccount`.
- **Crew** : XP ajoutée au crew du vendeur, influence journalisée avec la position (`lunatic_crew_influence`, pour les territoires).
- **Vue staff** : le bouton « Voir les labos en jeu » (onglet Drogues, permission `illegal.manage`) affiche tous les points de labo en orange, sans permettre de produire.
- **Police** : alerte anonyme avec probabilité `Config.AlertChance` (zone approximative sur la carte pendant `Config.AlertDuration` secondes).

## Étape 4 : territoires

Zones circulaires placées dans le panel (tuile Illégal, onglet Territoires) : nom, centre (position du staff), rayon, seuil d'influence, bonus de prix et d'XP.

- **Contrôle** : l'influence gagnée en vendant de la drogue dans la zone (sur `Config.TerritoryDays` jours de `lunatic_admin`, l'ancienne comptant de moins en moins) ; le crew en tête tient la zone dès qu'il atteint le seuil (à égalité, le crew en place la garde). Calcul côté serveur toutes les `Config.TerritoryRefresh` secondes et juste après chaque vente dans une zone ; « remettre à zéro » efface l'influence passée de la zone.
- **Bonus** : les ventes de drogue du crew qui tient la zone, faites dans la zone, rapportent le bonus de prix et d'XP.
- **Carte** : les membres d'un crew voient les zones (à leur crew en vert, à un autre en rouge, libres en blanc : `Config.TerritoryColors`) ; le staff peut les afficher avec « Voir sur ma carte ».
- **/crew** : section Territoires (zones tenues, influence du crew, crew en tête et seuil) ; les membres connectés sont prévenus quand leur crew gagne ou perd une zone.

## À venir

Craft d'armes et tablette, missions et braquages.
