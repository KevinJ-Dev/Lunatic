-- Catalogue des permissions, rangées par famille pour l'interface.
-- Chaque lot du panel ajoute ses permissions ici ; une permission absente du catalogue est refusée.

Permissions = {}

Permissions.Families = {
    { id = 'players',   label = 'Joueurs' },
    { id = 'sanctions', label = 'Sanctions' },
    { id = 'tools',     label = 'Outils' },
    { id = 'economy',   label = 'Économie' },
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
    { id = 'players.kick',     family = 'players', label = 'Expulser un joueur du serveur' },

    -- Lot 5 : économie, métier, inventaire
    { id = 'economy.money',       family = 'economy', label = 'Donner, retirer et fixer liquide et banque' },
    { id = 'economy.black_money', family = 'economy', label = "Donner, retirer et fixer l'argent sale" },
    { id = 'economy.job',         family = 'economy', label = 'Changer le métier et le grade' },
    { id = 'economy.items',       family = 'economy', label = "Voir l'inventaire, donner et retirer des objets" },
    { id = 'economy.clear',       family = 'economy', label = "Vider l'inventaire d'un joueur" },

    -- Lot 4 : outils staff
    { id = 'tools.noclip',    family = 'tools', label = 'Noclip (vol libre, invisible et invincible)' },
    { id = 'tools.invisible', family = 'tools', label = 'Se rendre invisible' },
    { id = 'tools.godmode',   family = 'tools', label = 'Se rendre invincible' },
    { id = 'tools.names',     family = 'tools', label = 'Voir les noms et ID au-dessus des têtes' },
    { id = 'tools.coords',    family = 'tools', label = 'Afficher et copier ses coordonnées' },
    { id = 'tools.tpm',       family = 'tools', label = 'Se téléporter au marqueur de la carte' },
    { id = 'tools.vehicles',  family = 'tools', label = 'Faire apparaître, réparer et supprimer des véhicules' },

    -- Lot 3 : sanctions
    { id = 'sanctions.view',          family = 'sanctions', label = 'Voir les sanctions et les historiques' },
    { id = 'sanctions.warn',          family = 'sanctions', label = 'Avertir un joueur' },
    { id = 'sanctions.ban',           family = 'sanctions', label = 'Bannir temporairement' },
    { id = 'sanctions.ban_permanent', family = 'sanctions', label = 'Bannir définitivement' },
    { id = 'sanctions.revoke',        family = 'sanctions', label = 'Révoquer une sanction (rang inférieur ou soi-même)' },

    { id = 'panel.open',   family = 'manage', label = 'Ouvrir le panel staff' },
    { id = 'ranks.view',   family = 'manage', label = 'Voir les rangs et leurs permissions' },
    { id = 'ranks.manage', family = 'manage', label = 'Créer, modifier et supprimer les rangs inférieurs' },
    { id = 'staff.view',   family = 'manage', label = 'Voir les membres du staff' },
    { id = 'logs.view',    family = 'manage', label = 'Voir les actions du staff (page Logs, tableau de bord)' },
    { id = 'logs.chat',    family = 'manage', label = "Lire l'historique du tchat" },
    { id = 'staff.manage', family = 'manage', label = 'Ajouter, promouvoir et retirer des membres inférieurs' },

    -- lunatic_chat
    { id = 'chat.staff',    family = 'chat', label = 'Lire et écrire dans le tchat staff (/sc)' },
    { id = 'chat.announce', family = 'chat', label = 'Faire une annonce serveur (/annonce)' },
    { id = 'chat.clear',    family = 'chat', label = 'Vider le tchat de tous les joueurs (/vidertchat)' },
}

Permissions.Known = {}
for _, perm in ipairs(Permissions.List) do
    Permissions.Known[perm.id] = true
end
