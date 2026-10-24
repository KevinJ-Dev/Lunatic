-- Catalogue des permissions, rangées par famille pour l'interface.
-- Chaque lot du panel ajoute ses permissions ici ; une permission absente du catalogue est refusée.

Permissions = {}

Permissions.Families = {
    { id = 'players',   label = 'Joueurs' },
    { id = 'sanctions', label = 'Sanctions' },
    { id = 'tools',     label = 'Outils' },
    { id = 'economy',   label = 'Économie' },
    { id = 'world',     label = 'Monde' },
    { id = 'server',    label = 'Serveur' },
    { id = 'dev',       label = 'Développeur' },
    { id = 'structures', label = 'Entreprises et services publics' },
    { id = 'illegal',    label = 'Illégal' },
    { id = 'shop',      label = 'Premium et boutique' },
    { id = 'chat',      label = 'Tchat' },
    { id = 'manage',    label = 'Gestion' },
}

Permissions.List = {
    -- Lot 2 : joueurs
    { id = 'players.view',     family = 'players', label = 'Voir la liste des joueurs et leur fiche' },
    { id = 'players.goto',     family = 'players', label = 'Aller vers un joueur' },
    { id = 'players.bring',    family = 'players', label = 'Ramener un joueur à soi et le renvoyer' },
    { id = 'players.spectate', family = 'players', label = 'Observer un joueur (caméra invisible)' },
    { id = 'players.freeze',   family = 'players', label = 'Figer et libérer un joueur' },
    { id = 'players.heal',     family = 'players', label = 'Soigner, réanimer et nourrir un joueur' },
    { id = 'players.appearance', family = 'players', label = "Ouvrir le menu d'apparence d'un joueur" },
    { id = 'players.recreate', family = 'players', label = 'Renvoyer un joueur à la création de personnage' },
    { id = 'players.licenses', family = 'players', label = 'Give un permis : donner et retirer les permis' },
    { id = 'players.copy_appearance', family = 'players', label = "Récupérer l'apparence d'un joueur" },
    { id = 'players.wipe', family = 'players', label = 'Wipe un joueur : réinitialiser complètement son personnage' },
    { id = 'players.offline', family = 'players', label = 'Gérer les joueurs offline (recherche en base et actions)' },
    { id = 'players.kick',     family = 'players', label = 'Expulser un joueur du serveur' },
    { id = 'players.crash',    family = 'players', label = 'Crash Player : déconnecter un joueur sans raison affichée (/crash)' },

    -- Lot H : gestion globale
    { id = 'server.manage', family = 'server', label = 'Gestion Global : redémarrage planifié, maintenance, actions de masse' },

    -- Lot K : outils développeur
    { id = 'dev.manage', family = 'dev', label = 'Gestion Développeur : resources, infos entité, affichage de debug' },

    -- Lot J : planning d'events
    { id = 'events.manage', family = 'server', label = 'Gestion des events : créer, modifier, annuler et annoncer' },

    -- Lot I : pôles (métiers ESX)
    { id = 'poles.manage', family = 'server', label = 'Pôle emploi : métiers, grades, salaires et membres' },

    -- Illégal
    { id = 'illegal.manage', family = 'illegal', label = 'Illégal : recelleur, puis drogues, territoires, craft d\'armes, tablette, missions' },
    { id = 'crews.manage', family = 'illegal', label = 'Crews : créer et gérer les crews (type, rangs, membres, XP)' },

    -- Lot E1 : entreprises et services publics
    { id = 'companies.manage', family = 'structures', label = 'Entreprises : créer et gérer les entreprises (fiche, grades, membres)' },
    { id = 'items.manage', family = 'manage', label = 'Items : créer, modifier, dupliquer, supprimer et donner les objets (appliqués au prochain redémarrage)' },
    { id = 'economy.manage', family = 'manage', label = "Économie : salaires, aide de l'État, banque, fourrière, devise et paie (appliqués tout de suite)" },
    { id = 'blips.manage', family = 'manage', label = 'Blips : créer, modifier, déplacer et supprimer les icônes de la carte (appliqués tout de suite)' },
    { id = 'catalogs.manage',  family = 'structures', label = 'Catalogues : magasins automatiques (LTD, Ammunation, grossistes…), prix, articles, emplacements' },
    { id = 'publics.manage',   family = 'structures', label = 'Services publics : créer et gérer police, médecins, administration, gouvernement' },

    -- Lot G : Premium et boutique
    { id = 'premium.manage', family = 'shop', label = 'Premium / Premium+ : attribuer et retirer les abonnements' },
    { id = 'shop.manage',    family = 'shop', label = 'Gestion Boutique : donner et retirer des crédits boutique' },

    -- Lot D : météo et heure (lunatic_world)
    { id = 'world.weather', family = 'world', label = 'Changer la météo, le cycle météo et les pannes de courant' },
    { id = 'world.time',    family = 'world', label = "Changer et figer l'heure" },

    -- Lot 5 : économie, métier, inventaire
    { id = 'economy.money',       family = 'economy', label = 'Donner, retirer et fixer liquide et banque' },
    { id = 'economy.black_money', family = 'economy', label = "Donner, retirer et fixer l'argent sale" },
    { id = 'economy.job',         family = 'economy', label = 'Changer le métier et le grade' },
    { id = 'economy.items',       family = 'economy', label = "Voir l'inventaire, donner et retirer des objets" },
    { id = 'economy.clear',       family = 'economy', label = "Vider l'inventaire d'un joueur" },
    { id = 'vehicles.give',       family = 'economy', label = 'Give un véhicule : ajouter un véhicule au garage d\'un joueur (/givecar)' },

    -- Lot 4 : outils staff
    { id = 'tools.noclip',    family = 'tools', label = 'Noclip (vol libre, invisible et invincible)' },
    { id = 'tools.invisible', family = 'tools', label = 'Se rendre invisible' },
    { id = 'tools.godmode',   family = 'tools', label = 'Se rendre invincible' },
    { id = 'tools.names',     family = 'tools', label = 'Voir les noms et ID au-dessus des têtes' },
    { id = 'tools.coords',    family = 'tools', label = 'Afficher et copier ses coordonnées' },
    { id = 'tools.tpm',       family = 'tools', label = 'Se téléporter au marqueur de la carte' },
    { id = 'tools.ghost',     family = 'tools', label = 'Godmod invisible (mode fantôme en un clic)' },
    { id = 'tools.vehicles',  family = 'tools', label = 'Faire apparaître, réparer et supprimer des véhicules' },

    -- Lot 3 : sanctions
    { id = 'sanctions.view',          family = 'sanctions', label = 'Voir les sanctions et les historiques' },
    { id = 'sanctions.warn',          family = 'sanctions', label = 'Avertir un joueur' },
    { id = 'sanctions.ban',           family = 'sanctions', label = 'Bannir temporairement' },
    { id = 'sanctions.ban_permanent', family = 'sanctions', label = 'Bannir définitivement' },
    { id = 'sanctions.jail',          family = 'sanctions', label = 'Mettre en prison staff et libérer' },
    { id = 'sanctions.revoke',        family = 'sanctions', label = 'Révoquer une sanction (rang inférieur ou soi-même)' },

    { id = 'contextmenu.use', family = 'manage', label = "Menu contextuel : options Staff d'ox_target sur les joueurs et véhicules (Alt)" },
    { id = 'contextmenu.dev', family = 'manage', label = 'Menu contextuel dev : copier coordonnées et modèle, geler, supprimer, infos d\'une entité' },
    { id = 'panel.open',   family = 'manage', label = 'Ouvrir le panel staff' },
    { id = 'ranks.view',   family = 'manage', label = 'Voir les rangs et leurs permissions' },
    { id = 'ranks.manage', family = 'manage', label = 'Créer, modifier et supprimer les rangs inférieurs' },
    { id = 'staff.online', family = 'manage', label = 'Liste des staff en ligne (accueil)' },
    { id = 'staff.view',   family = 'manage', label = 'Voir les membres du staff' },
    { id = 'logs.view',    family = 'manage', label = 'Voir les actions du staff (page Logs, tableau de bord)' },
    { id = 'logs.chat',    family = 'manage', label = "Lire l'historique du tchat" },
    { id = 'staff.manage', family = 'manage', label = 'Ajouter, promouvoir et retirer des membres inférieurs' },

    -- lunatic_chat
    { id = 'chat.staff',    family = 'chat', label = 'Lire et écrire dans le tchat staff (/sc)' },
    { id = 'chat.announce', family = 'chat', label = 'Faire une annonce serveur (/annonce)' },
    { id = 'chat.announce_mod', family = 'chat', label = 'Faire une annonce Modération (/annoncemodo)' },
    { id = 'chat.clear',    family = 'chat', label = 'Vider le tchat de tous les joueurs (/vidertchat)' },
}

-- Blocs de la page Permissions : Joueur, Serveur, Commandes, et Accès (tuiles du menu de gestion)
Permissions.Groups = {
    { id = 'player', label = 'Joueur' },
    { id = 'server', label = 'Serveur' },
    { id = 'commands', label = 'Commandes' },
    { id = 'access', label = 'Accès', sub = 'Menu de gestion' },
}

-- Bloc par famille ; le reste (tuiles et gestion) va dans Accès
local FAMILY_GROUP = { players = 'player', sanctions = 'player', economy = 'player', tools = 'commands', world = 'server', chat = 'server' }
local GROUP_OF = { ['players.crash'] = 'commands', ['contextmenu.use'] = 'commands', ['contextmenu.dev'] = 'commands', ['staff.online'] = 'server' }

-- Nom court affiché dans la page Permissions (le libellé complet s'affiche au survol)
local SHORT = {
    ['players.view'] = 'Fiche joueur', ['players.goto'] = 'Goto', ['players.bring'] = 'Bring / Return', ['players.spectate'] = 'Spectate',
    ['players.freeze'] = 'Freeze un joueur', ['players.heal'] = 'Heal / Revive', ['players.appearance'] = 'Menu apparence',
    ['players.recreate'] = 'Recréer le personnage', ['players.licenses'] = 'Give un permis', ['players.copy_appearance'] = "Récupérer l'apparence",
    ['players.wipe'] = 'Wipe un joueur', ['players.offline'] = 'Gérer les joueurs offline', ['players.kick'] = 'Kick', ['players.crash'] = 'Crash Player',
    ['server.manage'] = 'Gestion Global', ['dev.manage'] = 'Gestion Développeur', ['events.manage'] = 'Gestion des events', ['poles.manage'] = 'Pôle emploi',
    ['illegal.manage'] = 'Illégal', ['crews.manage'] = 'Crews', ['companies.manage'] = 'Entreprises', ['items.manage'] = 'Items', ['blips.manage'] = 'Blips', ['economy.manage'] = 'Économie',
    ['catalogs.manage'] = 'Catalogues', ['publics.manage'] = 'Services publics', ['premium.manage'] = 'Premium', ['shop.manage'] = 'Gestion Boutique',
    ['world.weather'] = 'Météo', ['world.time'] = 'Heure',
    ['economy.money'] = 'Argent (liquide, banque)', ['economy.black_money'] = 'Argent sale', ['economy.job'] = 'Changer de métier',
    ['economy.items'] = "Gérer l'inventaire", ['economy.clear'] = "Vider l'inventaire", ['vehicles.give'] = 'Give un véhicule',
    ['tools.noclip'] = 'Noclip', ['tools.invisible'] = 'Invisible', ['tools.godmode'] = 'Godmode', ['tools.names'] = 'Noms et ID',
    ['tools.coords'] = 'Coordonnées', ['tools.tpm'] = 'TP au marqueur', ['tools.ghost'] = 'Godmod invisible', ['tools.vehicles'] = 'Véhicules (spawn, réparer)',
    ['sanctions.view'] = 'Voir les sanctions', ['sanctions.warn'] = 'Avertir', ['sanctions.ban'] = 'Ban', ['sanctions.ban_permanent'] = 'Ban définitif',
    ['sanctions.jail'] = 'Prison staff', ['sanctions.revoke'] = 'Révoquer une sanction',
    ['contextmenu.use'] = 'Menu contextuel', ['contextmenu.dev'] = 'Menu contextuel dev', ['panel.open'] = 'Ouvrir le panel',
    ['ranks.view'] = 'Voir les permissions', ['ranks.manage'] = 'Permissions', ['staff.online'] = 'Liste des staff en ligne',
    ['staff.view'] = 'Voir les membres', ['logs.view'] = 'Logs', ['logs.chat'] = 'Historique du tchat', ['staff.manage'] = 'Gérer les membres',
    ['chat.staff'] = 'Tchat staff', ['chat.announce'] = 'Annonces Serveur', ['chat.announce_mod'] = 'Annonces Modérateur', ['chat.clear'] = 'Vider le tchat',
}

Permissions.Known = {}
for _, perm in ipairs(Permissions.List) do
    Permissions.Known[perm.id] = true
    perm.group = GROUP_OF[perm.id] or FAMILY_GROUP[perm.family] or 'access'
    perm.short = SHORT[perm.id]
end
