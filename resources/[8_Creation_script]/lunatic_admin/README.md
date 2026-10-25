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

« Recréer » et le wipe utilisent l'export `resetIdentity` de **lunatic_creator** (esx_identity a été retiré : lunatic_creator gère toute l'identité).

## Prison staff (lot C)

- Fiche joueur → **Prison** : durée en minutes (1 à 600) et raison. Le joueur est envoyé dans la cour de Bolingbroke (`Config.Jail`), voit un compte à rebours, ne peut ni tirer ni sortir de la zone (renvoyé dans la cour, contrôle aussi côté serveur).
- Le temps ne s'écoule que joueur connecté ; à la reconnexion (ou au redémarrage de la resource), il retourne en prison.
- À la fin, il est relâché devant le portail. **Sortir de prison** (fiche) ou **Révoquer** (page Sanctions) le libère plus tôt.
- Permission `sanctions.jail` ; peines visibles dans l'historique (type « Prison ») ; table `lunatic_admin_jail` créée au démarrage.

## Monde (lot D)

Page « Monde » : heure (raccourcis aube / midi / soir / nuit, heure précise, figer), météo (14 météos, transition progressive), cycle météo automatique et panne de courant. Nécessite la resource `lunatic_world`. Permissions `world.weather` et `world.time`.

## Lot E : permis, apparence, wipe, mode fantôme

| Fonction | Où | Permission |
|---|---|---|
| Give un permis (donner / retirer, libellés FR dans `Config.LicenseLabels`) | Fiche, bloc Permis | `players.licenses` |
| Récupérer l'apparence d'un joueur (copie non enregistrée) / « Mon apparence » pour revenir | Fiche, Personnage | `players.copy_appearance` |
| Wipe un joueur (argent de départ, inventaire, métier, véhicules, permis, identité, apparence ; nom à retaper ; état avant wipe dans les logs) | Fiche, Personnage | `players.wipe` |
| Godmod invisible (mode fantôme, raccourci FiveM « Staff : mode fantôme » sans touche par défaut) | Outils | `tools.ghost` |
| Liste des staff en ligne (accueil) | Accueil | `staff.online` |

## Joueurs hors ligne (lot F)

Page Joueurs → onglet **Hors ligne** (permission `players.offline`) : recherche dans la table `users` par nom RP ou licence, fiche en base (identité, argent, métier, permis, sanctions, dernière connexion).

Actions (chacune exige aussi sa propre permission) : bannir (par licence), argent, métier, permis, recréer à la prochaine connexion, wipe. Un joueur connecté est refusé ici : ses données se modifient depuis l'onglet En ligne (sinon ESX les écraserait à la sauvegarde).

## Premium et boutique (lot G)

Carte « Premium et boutique » des fiches (en ligne et hors ligne).

- **Premium / Premium+** (`premium.manage`) : 7, 30, 90 jours, 1 an ou à vie ; un même abonnement encore actif est prolongé. Expiration automatique (vérifiée chaque minute).
- **Crédits boutique** (`shop.manage`) : donner / retirer avec raison, solde jamais négatif, historique des 15 derniers mouvements.

Pour les autres scripts :

```lua
-- serveur
exports.lunatic_admin:getPremium(source)                 -- { tier, label, expires } ou nil
exports.lunatic_admin:isPremium(source, 'premium_plus')  -- Premium+ inclut Premium
exports.lunatic_admin:getCredits(source)
exports.lunatic_admin:removeCredits(source, montant, raison) -- true si le solde suffisait (achat boutique)
-- client
LocalPlayer.state.premium                                 -- 'premium', 'premium_plus' ou nil
```

Tables `lunatic_admin_premium`, `lunatic_admin_credits`, `lunatic_admin_credit_log` créées au démarrage.

## Serveur (lot H)

Page « Serveur » du panel, permission `server.manage` (Gestion Global).

- **Redémarrage planifié** : délai de 1 à 30 min (1 à 60 côté serveur) et raison facultative. Annonces automatiques à 15, 10, 5, 2 et 1 min puis 30 et 10 s, puis tous les joueurs sont expulsés (ESX les sauvegarde à la déconnexion). Relancer ensuite le serveur depuis le panel de l'hébergeur. Annulable tant que le compte à rebours tourne.
- **Mode maintenance** : seuls les membres du staff peuvent se connecter, les autres voient le message choisi (5 à 200 caractères). L'état est conservé après un redémarrage (KVP de la resource) et signalé dans la console au démarrage.
- **Actions de masse** : soigner tout le serveur (réanimation, soin, faim/soif), téléporter tout le monde à soi, expulser tout le monde (le staff connecté reste).

## Pôle emploi (lot I)

Page « Pôles » du panel, permission `poles.manage` (Gestion Pôle). Travaille directement sur les métiers ESX (tables `jobs` et `job_grades`) puis recharge le métier avec `ESX.RefreshJob` : aucun redémarrage, les membres connectés sont mis à jour tout de suite (salaire compris).

- **Liste** : chaque métier avec ses membres connectés, son effectif total (joueurs hors ligne compris) et ses grades.
- **Fiche** : renommer (nom affiché), liste blanche (pas proposé au pôle emploi), grades (nom et salaire), ajout d'un grade au-dessus des autres, retrait du grade le plus haut s'il est vide, membres (changer de grade, renvoyer), connectés ou non. Le staff de rang égal ou supérieur n'est pas modifiable.
- **Création** : nom affiché, nom technique (minuscules, chiffres, `_`), liste blanche, grades du plus bas (embauche) au plus haut (patron).
- **Suppression** : seulement sans aucun membre ; `unemployed` est protégé.

Le grade le plus haut d'un métier a toujours le nom technique `boss` (repère ESX des patrons, utile pour les futures entreprises) ; les autres grades prennent un nom technique tiré de leur libellé. Limites dans `config.lua` : `Config.PolesMaxGrades`, `Config.PolesMaxSalary`.

## Events (lot J)

Page « Events » du panel, permission `events.manage` (Gestion des events). Table `lunatic_admin_events` créée au démarrage.

- **Programmer** un event : titre, date et heure (celles du PC du staff), lieu, description, point sur la carte facultatif (« Ma position actuelle »), annonce immédiate facultative.
- **Modifier** (event pas encore commencé, annonce facultative), **annuler** (annoncé), **terminer** un event en cours.
- **Automatique** : rappel `Config.EventReminderMinutes` (15) min avant, annonce au début, point sur la carte des joueurs du rappel jusqu'à `Config.EventBlipMinutes` (30) min après le début. Un event raté pendant que le serveur était éteint est clos sans annonce.
- **Joueurs** : `/events` (events à venir dans le tchat), `/eventgps` (itinéraire vers le prochain event avec un point).

Les annonces passent par lunatic_chat (étiquette « Event ») : les dates y sont envoyées en jeton `{date:...}` et affichées à l'heure du PC de chaque joueur. Sans lunatic_chat, une notification ESX à l'heure du serveur.

## Développeur (lot K)

Page « Dév » du panel, permission `dev.manage` (Gestion Développeur, réservée au Fondateur par défaut).

- **Resources** : liste avec état, version et auteur ; démarrer, arrêter, redémarrer (natives `StartResource` / `StopResource`). Les resources de `Config.DevProtectedResources` (ESX, oxmysql, ox_lib, ox_inventory, lunatic_admin…) ne peuvent être ni arrêtées ni redémarrées depuis le panel.
- **Chercher les nouvelles (refresh)** : demande une ligne dans `server.cfg`, puis un redémarrage du serveur :
  ```
  add_ace resource.lunatic_admin command.refresh allow
  ```
- **Infos entité** : un viseur au centre de l'écran ; l'entité visée est surlignée avec son type, modèle, hash, position, heading, santé, id réseau, joueur qui la gère, plaque. **E** envoie ces infos dans la page (boutons de copie) et dans la console F8.
- **Affichage de debug** : en haut à gauche, ID serveur, FPS, position, rue et zone, intérieur, santé et armure, nombre de peds / véhicules / objets, véhicule actuel (modèle, vitesse, moteur, plaque).

## Navigation

Panel façon tablette : **onglets** comme un navigateur (un onglet par page, les pages d'un groupe comme Rangs et Membres partagent l'onglet « Permissions »). Le premier onglet, **Accueil** (grille de tuiles), est épinglé : Ctrl+T y ramène. Les autres se **déplacent par glisser-déposer** ; × ou Ctrl+W (ou clic molette) ferme, Ctrl+Tab passe à l'onglet suivant. La pastille en haut à droite montre la **tête du personnage** (portrait pris en jeu à chaque ouverture). Chaque onglet garde son état (fiche ouverte, défilement, recherche) ; les onglets restent ouverts à la fermeture du panel et sont mémorisés pour la reconnexion (stockage local du panel).

Boutons de fenêtre : **Réduire** (le panel se cache, un rappel « F10 » reste en bas d'écran), **Agrandir** (plein écran, mémorisé), **Fermer**. Pour ajouter une page : une entrée dans `NAV` (`web/app.js`), une `<section class="view">` dans `index.html` et sa fonction de rendu.

## Commandes staff (lot L)

Les commandes qui n'existaient ni dans le tchat ni dans le panel ; elles passent par les mêmes actions que le panel (permissions, protection des rangs supérieurs, logs).

| Commande | Permission | Effet |
|---|---|---|
| `/crash <id>` | `players.crash` (Crash Player) | Déconnecte le joueur avec `Config.CrashMessage`, sans raison affichée. Aussi « Déconnecter » dans la fiche. |
| `/givecar <id> <modèle>` | `vehicles.give` (Give un véhicule) | Ajoute le véhicule au garage du joueur (`owned_vehicles`, plaque libre « ABC 1234 », rangé). Le modèle est vérifié par le jeu du staff. Aussi « Donner un véhicule » dans la fiche. |
| `/inv <id>` | `economy.items` | Ouvre l'inventaire du joueur à côté du sien (ox_inventory) : prendre, déposer, déplacer. |
| `/annoncemodo <message>` | `chat.announce_mod` | Annonce signée « Modération » (dans lunatic_chat). |

Perquisition, menottes, propriétés, prise de service, stocks et mode créateur viendront avec leurs systèmes.

## Menu contextuel (lot M)

Utilise la resource **ContextMenu** (Kiminaze, v2.1.0) placée dans `resources/[0_Libs]/ContextMenu` (le nom du dossier doit rester `ContextMenu`). En jeu : maintenir **Alt gauche**, **clic droit** sur ce qu'on vise (son propre personnage compris), clic gauche sur l'option.

- **Joueur** (`contextmenu.use`) : ouvrir sa fiche, aller vers, ramener, figer / libérer, soigner, réanimer, observer, inventaire. Chaque option demande aussi la permission du panel correspondante ; sur soi-même, seulement fiche, soigner et réanimer.
- **Véhicule** (`contextmenu.use` + `tools.vehicles`) : réparer, retourner, monter dedans (place libre), propriétaire (d'après `owned_vehicles`), supprimer (refusé si un joueur est dedans).
- **Dév** (`contextmenu.dev`) : sous-menu sur joueurs et véhicules, menu direct sur PNJ et objets : copier `vector3` / `vector4` / modèle (presse-papiers), infos complètes (page Dév + console F8), geler / dégeler, supprimer l'entité (pas un joueur ; un décor non synchronisé n'est retiré que pour soi).

Le serveur envoie au client les droits du menu (rafraîchis toutes les 5 s s'ils changent) et revérifie chaque action ; tout est dans les logs. Sans ContextMenu, le module ne fait rien.

## Entreprises et services publics (lot E1)

Deux tuiles, une même page : **Entreprises** (`companies.manage` : boîte de nuit, concessionnaire, entreprise, mécanique, médias, restaurant) et **Services publics** (`publics.manage` : police, médecins, administration, gouvernement). Types dans `Config.StructureTypes`.

Une structure = un métier ESX (`jobs` / `job_grades`, toujours en liste blanche) + une fiche (`lunatic_structures`) :

- **Création** : nouveau métier (label, nom interne, grades proposés selon le type) ou métier existant du Pôle emploi (il en sort). Disponible tout de suite, sans redémarrage.
- **Identité** : label, type, lead (personnage responsable, services publics), couleur (entreprises), logo, icône radiale (Font Awesome, pour le futur menu radial), bannière.
- **Grades** et **Membres** : les mêmes actions que le Pôle emploi, autorisées par la permission de la tuile. Ajout d'un membre par ID en jeu ou par nom RP (choix si plusieurs personnages correspondent), embauché au grade le plus bas.
- **Temps de jeu** : une minute de plus chaque minute pour chaque membre connecté avec ce métier (`lunatic_structure_playtime`).
- **Suppression** : fiche, métier et temps de jeu, seulement sans membre.

Export : `exports.lunatic_admin:getStructure(jobName)` (fiche ou `nil`). Le Pôle emploi (ancienne tuile « Service public ») ne liste plus que les métiers sans fiche.

## Points et compte des structures (lot E2)

Onglets **Points** et **Compte** de la fiche d'une structure :

- **Points** (`lunatic_structure_points`) : ajouter un point d'un type (`Config.StructurePointTypes`) à sa position, **Définir** (le replacer à sa position et orientation), **TP**, renommer, supprimer. Diffusés en direct dans `GlobalState.lunaticStructurePoints` et à `lunatic_business` (événement `lunatic_admin:structurePointsChanged`). Export `getStructurePoints()`.
- **Compte** : solde, historique, ajout ou retrait par le staff avec motif (`Config.StructureAccountMaxAction`). Le compte est géré par `lunatic_business`.

## Catalogues des structures (lot E3)

Onglet **Catalogues** de la fiche d'une entreprise ou d'un service public (permission de sa tuile). Deux types (`lunatic_catalogs`, lignes `lunatic_catalog_lines`) :

- **Équipement** : membres seulement, aux points Catalogue et Armurerie, filtré par grade minimum ; payé par le compte de la société (prix 0 = gratuit).
- **Craft** : recettes des membres au point Craft (objet et quantité fabriqués, ingrédients consommés, durée, grade minimum).

Un catalogue peut être partagé entre plusieurs structures (`lunatic_structure_catalogs`, ex. armurerie commune à la police). Diffusés dans `GlobalState.lunaticCatalogs`.

## Magasins automatiques (tuile Catalogues, lot C1)

Tuile **Catalogues** (`catalogs.manage`) : grille des catégories (`Config.ShopCategories` : LTD, Binco, Vangelico, Barber, Ammunation, Location, Masquerade, Shenails, Skateshop, Tattoo, Grossistes), puis les magasins d'une catégorie.

Chaque magasin (`lunatic_shops`, `lunatic_shop_items`, `lunatic_shop_locations`) : label, clé (slug), blip (sprite, couleur, taille, label), image d'en-tête (pour la future interface maison), jobs autorisés (vide = tout le monde), articles (objet, prix, permis requis), emplacements (ajouter à sa position, Définir, TP, supprimer). Bouton **Enregistrer** pour la fiche et les articles ; les emplacements sont enregistrés tout de suite.

En jeu (`lunatic_business`) : blips, marqueur et `[E]`, interface de magasin d'ox_inventory (paiement en liquide, permis, distance). Catégories prêtes : celles de type `items` (LTD, Vangelico, Ammunation, Skateshop, Grossistes) et **Location** (lot C3). Magasins d'apparence (Binco, Barber, Tattoo…) : plus tard, avec un magasin de vêtements maison.

**Location (lot C3)** : à la place des articles, une liste de véhicules (`lunatic_shop_vehicles` : modèle vérifié par le jeu du staff, nom, prix, durée en minutes) ; chaque emplacement a une **Sortie** des véhicules (bouton, à sa position et orientation ; sinon 4 m devant le comptoir).

Les magasins par défaut d'ox_inventory (`data/shops.lua`) sont retirés, sauf les distributeurs (modification locale d'ox_inventory à garder lors des mises à jour).

## Crews (illégal, étape 1)

Tuile **Crews** (`crews.manage`, famille Illégal). Tables `lunatic_crews`, `lunatic_crew_ranks`, `lunatic_crew_members` (un crew au plus par personnage).

- **Création** : nom, clé, type (`Config.CrewTypes` : Mafia, MC, Organisation, Gang) ; rangs par défaut `Config.CrewDefaultRanks` (Rang C → Rang S, le plus haut = chef).
- **Fiche** : identité (nom, type, couleur, logo), rangs (renommer, ajouter au-dessus, retirer le plus haut s'il est vide), membres (ajout par ID ou nom RP, rang, retrait), progression (XP, level selon `Config.CrewLevels`, ajustement d'XP ; l'influence viendra avec les territoires).
- Statebag `crew` des joueurs connectés et exports pour `lunatic_illegal` (tablette en jeu).

## Illégal (tuile Illégal)

Tuile **Illégal** (`illegal.manage`), avec un onglet par étape (les suivantes sont marquées « bientôt »).

- **Recelleur** (étape 2) : catalogue des objets rachetés (objet ox_inventory, prix unitaire, catégorie ; ajouter, modifier, dupliquer, supprimer) et emplacements des PNJ (`Config.FenceDefaultPed`, modèle vérifié par le jeu du staff ; Ajouter à ma position, Définir, TP, changer le modèle). Tables `lunatic_fence_items`, `lunatic_fence_locations`, diffusion `GlobalState.lunaticFence` ; revente en jeu dans `lunatic_illegal`.
- **Drogues** (étape 3) : drogues (objet, statut, prix de base, XP et influence par vente, policiers requis, volumes min et max ; dupliquer = copie désactivée avec ses recettes) et laboratoires (type de crew, recette : ingrédients, durée, quantité produite ; emplacements avec Définir et TP). Tables `lunatic_drugs`, `lunatic_drug_labs`, `lunatic_drug_lab_locations`, diffusion `GlobalState.lunaticDrugs`. Journal d'influence `lunatic_crew_influence` (export `addCrewInfluence(crewId, amount, x, y, source)`) pour les territoires.
  Drogues de départ créées une fois au premier démarrage (weed → Gang, cocaïne → Mafia, meth → MC, fentanyl → Organisation, avec leurs recettes ; laboratoires sans emplacement, à placer en jeu). Console : `lunatic_drugs_seed` les recrée si la liste est vide. Objets et ingrédients ajoutés dans `ox_inventory/data/items.lua` (weed, cocaine, meth, fentanyl, weed_leaf, coca_leaf, pseudoephedrine, chemicals, plastic_bag, empty_vial).
