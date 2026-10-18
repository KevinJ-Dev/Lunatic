# lunatic_business

Côté jeu des entreprises et services publics créés dans le panel staff (`lunatic_admin`, tuiles Entreprises et Services publics).
Le staff place les points (onglet **Points** de la fiche) ; cette resource les rend utilisables.

## Installation

Dans `resources/[8_Creation_script]`, démarrée automatiquement par `ensure [8_Creation_script]` (après `lunatic_admin`, dont elle dépend).
Dépendances : `es_extended`, `ox_lib`, `oxmysql`, `ox_inventory`, `lunatic_admin` ; `illenium-appearance` pour le vestiaire.
Les tables sont créées au démarrage : `lunatic_business_accounts`, `lunatic_business_account_log`, `lunatic_business_outfits`.

## En jeu

Les membres de la structure voient un marqueur au sol (`Config.MarkerDistance`) et `[E]` à `Config.InteractDistance`.
La **Sonnette** est visible par tous ; les autres points seulement par les membres.

| Point | Effet |
|---|---|
| Gestion | Patron (grade le plus haut) : compte de société (solde, dépôt, retrait, historique), membres (promouvoir, rétrograder, renvoyer, temps de service), recruter un joueur proche |
| Stockage | Coffre ox_inventory partagé, un par point (`lb_storage_<id>`), réservé au métier |
| Casier | Coffre personnel par membre et par structure (`lb_locker_<métier>`) |
| Vestiaire | Tenues par grade (homme / femme) : le patron enregistre la tenue qu'il porte pour un grade ; les membres enfilent celles de leur grade et des grades inférieurs, ou reprennent leur tenue civile |
| Sonnette | Prévient les membres connectés (notification + point GPS), une sonnerie toutes les `Config.DoorbellCooldown` secondes |
| Custom | Événement serveur `lunatic_business:custom` (src, point) et client `lunatic_business:customClient` (point) |

Les autres types (Catalogue, Craft, Garages, DJ…) sont plaçables mais affichent « pas encore disponible ».

Le serveur revérifie tout : métier, grade (patron pour la gestion, jamais d'autre patron nommé ou renvoyé), distance au point.

## Exports serveur

```lua
exports.lunatic_business:getBalance(job)                       -- solde du compte de société
exports.lunatic_business:addMoney(job, amount, reason, actor)  -- true / false
exports.lunatic_business:removeMoney(job, amount, reason, actor) -- false si solde insuffisant
exports.lunatic_business:getHistory(job, limit)                -- { amount, balance, reason, actor, created }
```
