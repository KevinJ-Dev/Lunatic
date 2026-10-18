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

## Sanctions (lot 3)

- **Avertir** (fiche joueur) : le joueur voit une fenêtre plein écran à valider avec « J'ai compris ».
- **Bannir** : 1 h, 6 h, 1 j, 3 j, 7 j, 30 j, durée personnalisée (1 an maximum) ou définitif. Le ban vise la licence, les autres identifiants (Discord, Steam, FiveM… mais pas l'IP) et les identifiants matériels du PC : un second compte sur le même PC est bloqué.
- **Déconnexions récentes** (page Sanctions) : les 50 derniers joueurs partis peuvent être bannis hors ligne.
- **Révoquer** : uniquement les sanctions données par un rang inférieur au sien ou par soi-même (le Fondateur peut tout révoquer). La sanction reste dans l'historique.

| Permission | Effet |
|---|---|
| `sanctions.view` | Page Sanctions et historique sur la fiche |
| `sanctions.warn` | Avertir |
| `sanctions.ban` | Bannir temporairement (et voir les déconnexions récentes) |
| `sanctions.ban_permanent` | Bannir définitivement |
| `sanctions.revoke` | Révoquer |

Commande console de secours : `lunatic_admin_unban <référence>` (ex. `lunatic_admin_unban 42`).

Table `lunatic_admin_sanctions` créée au démarrage ; dates en secondes Unix.

## Outils (lot 4)

Page « Outils » du panel. Les modes restent actifs panel fermé ; un badge en haut de l'écran les rappelle. Si un membre perd une permission, l'outil se coupe dans les 5 secondes.

| Outil | Permission | Détail |
|---|---|---|
| Noclip | `tools.noclip` | Touche **F2** (raccourci FiveM « Staff : noclip »). Z/Q/S/D, E monter, A descendre, Maj rapide, Ctrl lent, molette = vitesse |
| Invisibilité | `tools.invisible` | Le staff se voit lui-même en transparence |
| Invincibilité | `tools.godmode` | |
| Noms au-dessus des têtes | `tools.names` | `[ID] Prénom Nom` à 50 m, couleur du rang pour le staff |
| Coordonnées | `tools.coords` | À l'écran + copie `vector3` / `vector4` depuis le panel |
| Téléportation au marqueur | `tools.tpm` | Bouton du panel ou raccourci FiveM « Staff : téléportation au marqueur » (sans touche par défaut) |
| Véhicules | `tools.vehicles` | Faire apparaître (créé par le serveur, plaque `STAFF`), réparer, retourner, supprimer le sien ou les véhicules vides autour (50 m max) |

Noclip, invisibilité, invincibilité, apparitions et suppressions de véhicules sont enregistrés dans `lunatic_admin_logs`.

## Économie, métier et inventaire (lot 5)

Section ajoutée à la fiche joueur (joueurs connectés uniquement ; masquée pour un staff de rang égal ou supérieur).

| Section | Permission | Détail |
|---|---|---|
| Argent (liquide, banque) | `economy.money` | Donner, retirer, fixer. Raison obligatoire, 1 000 000 $ max par opération (`Config.MaxMoneyAction`) sauf pour le Fondateur |
| Argent sale | `economy.black_money` | Pareil, permission séparée |
| Métier | `economy.job` | Métier et grade parmi les métiers ESX en base |
| Inventaire | `economy.items` | Voir (ox_inventory), donner un objet (1 000 max), retirer une quantité ou tout |
| Vider l'inventaire | `economy.clear` | Raison obligatoire ; la liste des objets supprimés est gardée dans les logs |

Chaque opération est enregistrée dans `lunatic_admin_logs` avec l'ancienne et la nouvelle valeur.

## Logs et tableau de bord (lot 6)

- **Accueil = tableau de bord**, rafraîchi toutes les 5 secondes : joueurs en ligne et courbe des 24 h (relevé toutes les 5 min, en mémoire : repart de zéro au redémarrage), staff en ligne, bans actifs et sanctions des 24 h (`sanctions.view`), 8 dernières actions du staff (`logs.view`).
- **Page Logs** :
  - *Actions du staff* (`logs.view`) : filtres catégorie / membre / période, recherche, « Charger plus », détail complet au clic (avant, après, raison…).
  - *Tchat* (`logs.chat`) : historique de `lunatic_chat` (HRP, /me, /do, staff, annonces), filtre par canal, recherche.
- Les actions du staff de plus de `Config.LogRetentionDays` jours (90 par défaut) sont supprimées automatiquement.

## Ajouts (lot B)

| Action | Où | Permission |
|---|---|---|
| Nourrir (faim et soif au maximum) | Fiche, Soins | `players.heal` |
| Soigner la zone (10 / 25 / 50 m : relève, soigne, nourrit) | Outils | `players.heal` |
| Apparence (menu complet illenium-appearance, gratuit, comme `/pedmenu`) | Fiche, Personnage | `players.appearance` |
| Recréer (identité + apparence effacées, retour à la création ; argent, inventaire et métier conservés) | Fiche, Personnage | `players.recreate` |

« Recréer » utilise l'export `resetIdentity` ajouté à **esx_identity** (modification locale à reporter lors des mises à jour d'ESX).
