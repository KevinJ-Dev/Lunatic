# lunatic_admin

Panel staff de Lunatic RP : rangs modifiables en jeu, permissions et gestion du staff.

## Installation

Rien à importer : les tables `lunatic_admin_ranks`, `lunatic_admin_staff` et `lunatic_admin_logs` sont créées au démarrage, avec les rangs par défaut (Fondateur, Admin, Responsable staff, Modérateur, Modérateur test).

## Premier Fondateur

Dans la console du serveur (console de l'hébergeur ou txAdmin) :

```
lunatic_admin_founder <id du joueur connecté>
```

Tapée sans id, la commande affiche la liste des joueurs connectés avec leur id.

Pour retirer n'importe quel membre, y compris un Fondateur :

```
lunatic_admin_unstaff <id du joueur ou licence "license:...">
```

Ces deux commandes ne fonctionnent que depuis la console.

## En jeu

- **F10** (modifiable dans Paramètres > Raccourcis > FiveM) ou `/staff` dans le tchat (ou `staff` dans la console F8) ouvre le panel.
- Un membre ne peut modifier, dupliquer ou supprimer que les rangs **strictement inférieurs** au sien, et ne peut donner que les permissions qu'il possède.
- Le rang Fondateur a toutes les permissions et ne peut pas être supprimé.
- Toutes les actions sont revérifiées côté serveur et enregistrées dans `lunatic_admin_logs`.

## Ajouter une permission (lots suivants)

Déclarer la permission dans `shared/permissions.lua`, puis la vérifier côté serveur avec `Staff.can(source, 'id.permission')`.

## Exports serveur

```lua
exports.lunatic_admin:can(source, 'chat.staff')   -- true / false
exports.lunatic_admin:getRank(source)             -- { id, name, color, level, owner } ou nil
exports.lunatic_admin:getDisplayName(source)      -- "Prénom Nom" (pseudo si pas d'identité)
```

## Page Joueurs (lot 2)

Liste des joueurs connectés (rafraîchie toutes les 5 secondes) et fiche détaillée : identité, métier, argent, santé, armure.

| Action | Permission | Sur un staff de rang égal ou supérieur |
|---|---|---|
| Aller vers | `players.goto` | autorisé |
| Ramener / Renvoyer | `players.bring` | refusé |
| Observer (Retour arrière pour arrêter) | `players.spectate` | autorisé |
| Figer / Libérer | `players.freeze` | refusé |
| Soigner / Réanimer | `players.heal` | autorisé |
| Expulser (raison obligatoire) | `players.kick` | refusé |

Toutes les actions sont enregistrées dans `lunatic_admin_logs`.
