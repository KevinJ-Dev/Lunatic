# lunatic_illegal

Côté jeu de l'illégal. Les données se gèrent dans le panel staff (`lunatic_admin`).

## Installation

Dans `resources/[8_Creation_script]`, démarrée par `ensure [8_Creation_script]` après `lunatic_admin` (dépendance).
Dépendances : `es_extended`, `ox_lib`, `lunatic_admin`.

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

## À venir

Drogues (laboratoires et vente), territoires (zones, multiplicateur, influence), craft d'armes et tablette, missions et braquages.
