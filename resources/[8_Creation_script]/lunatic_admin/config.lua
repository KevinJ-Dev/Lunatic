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

-- Soins de zone : rayon maximal
Config.CareZoneMaxRadius = 50.0

-- Noms français des permis ESX (table licenses) ; un type absent garde le libellé de la base
Config.LicenseLabels = {
    dmv = 'Code de la route',
    drive = 'Permis voiture',
    drive_bike = 'Permis moto',
    drive_truck = 'Permis poids lourd',
    boat = 'Permis bateau',
    weapon = "Port d'arme",
    weed_processing = 'Licence de transformation',
}

-- Raison d'une expulsion : longueur minimale et maximale
Config.KickReasonMin = 3
Config.KickReasonMax = 120

-- Sanctions (lot 3)
Config.ServerName = "Lunatic RP"     -- affiché aux joueurs bannis
Config.SanctionReasonMin = 3
Config.SanctionReasonMax = 200
Config.BanMaxHours = 8760            -- durée maximale d'un ban temporaire (1 an)
Config.RecentDisconnects = 50        -- joueurs récemment partis, bannissables depuis le panel

-- Prison staff (hors RP) : cour de la prison de Bolingbroke
-- (ajustables avec l'outil Coordonnées du panel)
Config.Jail = {
    spawn = vector3(1641.64, 2571.08, 45.56),    -- arrivée dans la cour
    radius = 40.0,                              -- distance maximale autour de l'arrivée avant d'y être renvoyé
    release = vector3(1847.07, 2585.69, 45.67), -- sortie, devant le portail
    maxMinutes = 600,                           -- durée maximale d'une peine
}

-- Premium et boutique (lot G)
Config.PremiumTiers = {
    premium = { label = 'Premium', color = '#f2c26b' },
    premium_plus = { label = 'Premium+', color = '#9650ff' },
}
Config.PremiumMaxDays = 3650         -- durée maximale d'un abonnement (hors « à vie »)
Config.CreditsMaxAction = 100000     -- crédits maximum par opération
Config.CreditsName = 'crédits'       -- nom affiché de la monnaie boutique

-- Outils staff (lot 4)
Config.GhostKey = ''                    -- touche du mode fantôme (aucune par défaut, à choisir dans les raccourcis FiveM)
Config.NoclipKey = 'F2'                 -- touche par défaut du noclip (modifiable dans les raccourcis FiveM)
Config.NoclipSpeed = 12.0                 -- vitesse de base du noclip (m/s), Maj x4, Ctrl x0.25
Config.NamesDistance = 50.0               -- portée des noms au-dessus des têtes
Config.VehicleDeleteMaxRadius = 50.0      -- rayon maximal de suppression des véhicules
Config.VehiclePlate = 'STAFF'            -- plaque des véhicules apparus via le panel

-- Économie (lot 5)
Config.MaxMoneyAction = 1000000           -- montant maximal par opération (le Fondateur n'a pas de limite)
Config.MaxItemCount = 1000                -- quantité maximale d'objets donnée en une fois
Config.EconomyReasonMin = 3

-- Logs et tableau de bord (lot 6)
Config.LogRetentionDays = 90              -- les actions du staff plus anciennes sont supprimées
Config.DashboardSampleMinutes = 5         -- relevé du nombre de joueurs pour la courbe des 24 h
Config.LogsPageSize = 50

-- Anti-spam : nombre maximal d'actions du panel par joueur et par fenêtre de temps
Config.RateLimit = { max = 15, windowMs = 5000 }

-- Rangs créés au premier démarrage (table vide). Ils restent ensuite modifiables en jeu.
-- owner = true : rang Fondateur (toutes les permissions, ne peut pas être supprimé)
local world = { 'world.weather', 'world.time' }
local economy = { 'economy.money', 'economy.black_money', 'economy.job', 'economy.items', 'economy.clear' }
local tools = { 'tools.noclip', 'tools.invisible', 'tools.godmode', 'tools.ghost', 'tools.names', 'tools.coords', 'tools.tpm', 'tools.vehicles' }
local profile = { 'players.licenses', 'players.copy_appearance', 'staff.online', 'players.offline' }
local shop = { 'premium.manage', 'shop.manage' }
local sanctions = { 'sanctions.view', 'sanctions.warn', 'sanctions.ban', 'sanctions.jail' }
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
    { name = 'Admin',             color = '#ff6b6b', level = 80, permissions = with(players, sanctions, tools, economy, world, profile, shop, { 'players.wipe', 'logs.view', 'logs.chat', 'sanctions.ban_permanent', 'sanctions.revoke', 'panel.open', 'ranks.view', 'ranks.manage', 'staff.view', 'staff.manage', 'chat.staff', 'chat.announce', 'chat.clear' }) },
    { name = 'Responsable staff', color = '#f2c26b', level = 60, permissions = with(players, sanctions, tools, world, profile, { 'logs.view', 'economy.money', 'economy.job', 'economy.items', 'sanctions.revoke', 'panel.open', 'ranks.view', 'staff.view', 'staff.manage', 'chat.staff', 'chat.announce' }) },
    { name = 'Modérateur',        color = '#5fd3a0', level = 40, permissions = with(players, sanctions, { 'staff.online', 'tools.noclip', 'tools.names', 'tools.tpm', 'tools.vehicles', 'panel.open', 'ranks.view', 'staff.view', 'chat.staff' }) },
    { name = 'Modérateur test',   color = '#6bb8f2', level = 20, permissions = { 'panel.open', 'chat.staff', 'players.view', 'players.goto', 'players.spectate', 'players.heal', 'sanctions.view', 'sanctions.warn', 'tools.noclip', 'tools.names' } },
}
