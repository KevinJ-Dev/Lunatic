Config = {}

-- Ouverture du panel : commande et touche par défaut
-- (modifiable par chaque joueur : Échap > Paramètres > Raccourcis clavier > catégorie FiveM)
Config.Command = 'staff'
Config.DefaultKey = 'F10'

-- Niveau réservé au rang Fondateur : aucun autre rang ne peut l'atteindre
Config.OwnerLevel = 100

-- Limites de saisie des rangs
Config.RankNameMin = 2
Config.RankNameMax = 32
Config.MaxRanks = 30

-- Raison d'une expulsion : longueur minimale et maximale
Config.KickReasonMin = 3
Config.KickReasonMax = 120

-- Sanctions (lot 3)
Config.ServerName = "Lunatic RP"     -- affiché aux joueurs bannis
Config.SanctionReasonMin = 3
Config.SanctionReasonMax = 200
Config.BanMaxHours = 8760            -- durée maximale d'un ban temporaire (1 an)
Config.RecentDisconnects = 50        -- joueurs récemment partis, bannissables depuis le panel

-- Anti-spam : nombre maximal d'actions du panel par joueur et par fenêtre de temps
Config.RateLimit = { max = 15, windowMs = 5000 }

-- Rangs créés au premier démarrage (table vide). Ils restent ensuite modifiables en jeu.
-- owner = true : rang Fondateur (toutes les permissions, ne peut pas être supprimé)
local sanctions = { 'sanctions.view', 'sanctions.warn', 'sanctions.ban' }
local players = { 'players.view', 'players.goto', 'players.bring', 'players.spectate', 'players.freeze', 'players.heal', 'players.kick' }

local function with(...)
    local list = {}

    for _, group in ipairs({ ... }) do
        for _, id in ipairs(group) do
            list[#list + 1] = id
        end
    end

    return list
end

Config.DefaultRanks = {
    { name = 'Fondateur',         color = '#9650ff', level = 100, owner = true },
    { name = 'Admin',             color = '#ff6b6b', level = 80, permissions = with(players, sanctions, { 'sanctions.ban_permanent', 'sanctions.revoke', 'panel.open', 'ranks.view', 'ranks.manage', 'staff.view', 'staff.manage', 'chat.staff', 'chat.announce', 'chat.clear' }) },
    { name = 'Responsable staff', color = '#f2c26b', level = 60, permissions = with(players, sanctions, { 'sanctions.revoke', 'panel.open', 'ranks.view', 'staff.view', 'staff.manage', 'chat.staff', 'chat.announce' }) },
    { name = 'Modérateur',        color = '#5fd3a0', level = 40, permissions = with(players, sanctions, { 'panel.open', 'ranks.view', 'staff.view', 'chat.staff' }) },
    { name = 'Modérateur test',   color = '#6bb8f2', level = 20, permissions = { 'panel.open', 'chat.staff', 'players.view', 'players.goto', 'players.spectate', 'players.heal', 'sanctions.view', 'sanctions.warn' } },
}
