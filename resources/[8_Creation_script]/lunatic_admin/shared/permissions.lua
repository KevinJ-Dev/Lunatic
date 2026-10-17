-- Catalogue des permissions, rangées par famille pour l'interface.
-- Chaque lot du panel ajoute ses permissions ici ; une permission absente du catalogue est refusée.

Permissions = {}

Permissions.Families = {
    { id = 'players',   label = 'Joueurs' },
    { id = 'sanctions', label = 'Sanctions' },
    { id = 'tools',     label = 'Outils' },
    { id = 'chat',      label = 'Tchat' },
    { id = 'manage',    label = 'Gestion' },
}

Permissions.List = {
    { id = 'panel.open',   family = 'manage', label = 'Ouvrir le panel staff' },
    { id = 'ranks.view',   family = 'manage', label = 'Voir les rangs et leurs permissions' },
    { id = 'ranks.manage', family = 'manage', label = 'Créer, modifier et supprimer les rangs inférieurs' },
    { id = 'staff.view',   family = 'manage', label = 'Voir les membres du staff' },
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
