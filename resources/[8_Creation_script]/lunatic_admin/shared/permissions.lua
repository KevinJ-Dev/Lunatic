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

    -- Lot E1 : entreprises et services publics
    { id = 'companies.manage', family = 'structures', label = 'Entreprises : créer et gérer les entreprises (fiche, grades, membres)' },
    { id = 'catalogs.manage',  family = 'structures', label = 'Catalogues : boutiques, équipements et recettes de craft, rattachés aux structures' },
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

Permissions.Known = {}
for _, perm in ipairs(Permissions.List) do
    Permissions.Known[perm.id] = true
end
