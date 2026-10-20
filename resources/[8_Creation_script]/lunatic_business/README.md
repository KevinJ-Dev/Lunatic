# lunatic_business

Côté jeu des entreprises et services publics créés dans le panel staff (`lunatic_admin`, tuiles Entreprises et Services publics).
Le staff place les points (onglet **Points** de la fiche) ; cette resource les rend utilisables.

## Installation

Dans `resources/[8_Creation_script]`, démarrée automatiquement par `ensure [8_Creation_script]`.
Dépendances : `es_extended`, `ox_lib`, `oxmysql`, `ox_inventory` ; `illenium-appearance` pour le vestiaire. Utilise `lunatic_admin` (points, catalogues, magasins) pendant son fonctionnement.
`lunatic_admin` n'est pas une dépendance déclarée dans le manifeste : sinon chaque `ensure lunatic_admin` arrêterait cette resource sans la relancer.
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
| Catalogue | Équipements des membres selon leur grade, payés par le compte de la société |
| Armurerie | Équipements seulement (services publics) |
| Craft | Recettes : barre de progression annulable, ingrédients retirés et objet donné à la fin seulement (durée vérifiée par le serveur) |

Les autres types (Garages, DJ…) sont plaçables mais affichent « pas encore disponible ». 

Le serveur revérifie tout : métier, grade (patron pour la gestion, jamais d'autre patron nommé ou renvoyé), distance au point.

## Exports serveur

```lua
exports.lunatic_business:getBalance(job)                       -- solde du compte de société
exports.lunatic_business:addMoney(job, amount, reason, actor)  -- true / false
exports.lunatic_business:removeMoney(job, amount, reason, actor) -- false si solde insuffisant
exports.lunatic_business:getHistory(job, limit)                -- { amount, balance, reason, actor, created }
```

## Magasins automatiques

Les magasins de la tuile Catalogues du panel (LTD, Ammunation, grossistes…) sont enregistrés dans ox_inventory (`lunatic_<slug>`) à chaque modification : blips, marqueur et `[E]` à chaque emplacement, interface de magasin d'ox_inventory. Un magasin réservé à des jobs n'apparaît qu'à leurs membres.

## Location de véhicules

Au comptoir d'une agence : choix du véhicule, paiement en liquide ou par carte, le véhicule sort à la sortie définie (refusé si elle est encombrée) avec une plaque `LOC00000` et le joueur est mis au volant. Une location à la fois. Avertissements avant la fin (`Config.RentalWarnings`), puis le véhicule est repris dès qu'il est vide, ou de force après `Config.RentalGrace` secondes. Il peut être rendu plus tôt au comptoir (à moins de `Config.RentalReturnDistance`), sans remboursement. Déconnexion = véhicule repris.
