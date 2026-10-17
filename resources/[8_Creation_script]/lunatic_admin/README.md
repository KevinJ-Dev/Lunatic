# lunatic_admin

Panel staff de Lunatic RP : rangs modifiables en jeu, permissions et gestion du staff.

## Installation

Rien à importer : les tables `lunatic_admin_ranks`, `lunatic_admin_staff` et `lunatic_admin_logs` sont créées au démarrage, avec les rangs par défaut (Fondateur, Admin, Responsable staff, Modérateur, Modérateur test).

## Premier Fondateur

Dans la console du serveur (txAdmin > Console) :

```
lunatic_admin_founder <id du joueur connecté>
```

Pour retirer n'importe quel membre, y compris un Fondateur :

```
lunatic_admin_unstaff <id du joueur ou licence "license:...">
```

Ces deux commandes ne fonctionnent que depuis la console.

## En jeu

- `/staff` ou **F10** (modifiable dans Paramètres > Raccourcis > FiveM) ouvre le panel.
- Un membre ne peut modifier, dupliquer ou supprimer que les rangs **strictement inférieurs** au sien, et ne peut donner que les permissions qu'il possède.
- Le rang Fondateur a toutes les permissions et ne peut pas être supprimé.
- Toutes les actions sont revérifiées côté serveur et enregistrées dans `lunatic_admin_logs`.

## Ajouter une permission (lots suivants)

Déclarer la permission dans `shared/permissions.lua`, puis la vérifier côté serveur avec `Staff.can(source, 'id.permission')`.
