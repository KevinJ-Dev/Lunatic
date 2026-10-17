Config = {}

-- Ouverture du panel : commande et touche par défaut (modifiable par chaque joueur dans Paramètres > Raccourcis > FiveM)
Config.Command = 'staff'
Config.DefaultKey = 'F10'

-- Niveau réservé au rang Fondateur : aucun autre rang ne peut l'atteindre
Config.OwnerLevel = 100

-- Limites de saisie des rangs
Config.RankNameMin = 2
Config.RankNameMax = 32
Config.MaxRanks = 30

-- Anti-spam : nombre maximal d'actions du panel par joueur et par fenêtre de temps
Config.RateLimit = { max = 15, windowMs = 5000 }

-- Rangs créés au premier démarrage (table vide). Ils restent ensuite modifiables en jeu.
-- owner = true : rang Fondateur (toutes les permissions, ne peut pas être supprimé)
Config.DefaultRanks = {
    { name = 'Fondateur',         color = '#9650ff', level = 100, owner = true },
    { name = 'Admin',             color = '#ff6b6b', level = 80, permissions = { 'panel.open', 'ranks.view', 'ranks.manage', 'staff.view', 'staff.manage' } },
    { name = 'Responsable staff', color = '#f2c26b', level = 60, permissions = { 'panel.open', 'ranks.view', 'staff.view', 'staff.manage' } },
    { name = 'Modérateur',        color = '#5fd3a0', level = 40, permissions = { 'panel.open', 'ranks.view', 'staff.view' } },
    { name = 'Modérateur test',   color = '#6bb8f2', level = 20, permissions = { 'panel.open' } },
}
