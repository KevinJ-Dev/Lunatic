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

-- Développeur (lot K) : resources qu'on ne peut ni arrêter ni redémarrer depuis le panel
Config.DevProtectedResources = {
    'lunatic_admin', 'es_extended', 'oxmysql', 'ox_lib', 'ox_inventory',
    'monitor', 'sessionmanager', 'spawnmanager', 'mapmanager', 'hardcap', 'yarn', 'webpack',
}

-- Events (lot J)
Config.EventReminderMinutes = 15     -- rappel automatique avant le début
Config.EventBlipMinutes = 30         -- point sur la carte encore visible après le début

-- Commandes (lot L) : message vu par un joueur déconnecté avec /crash
Config.CrashMessage = 'Vous avez été déconnecté du serveur.'

-- Illégal : crews
Config.CrewTypes = {
    { id = 'mafia', label = 'Mafia' },
    { id = 'mc', label = 'MC' },
    { id = 'organisation', label = 'Organisation' },
    { id = 'gang', label = 'Gang' },
}
Config.CrewDefaultRanks = { 'Rang C', 'Rang B', 'Rang A', 'Rang S' } -- du plus bas au plus haut (le plus haut = chef)
Config.CrewLevels = { 0, 1000, 2500, 5000, 10000, 20000, 35000, 55000, 80000, 120000 } -- XP nécessaire pour chaque level (level 1 à 10)

-- Illégal : territoires (zones placées dans le panel, onglet Territoires)
Config.TerritoryDays = 7       -- l'influence des N derniers jours compte (la plus ancienne de moins en moins)
Config.TerritoryRefresh = 300  -- secondes entre deux recalculs complets (et recalcul juste après chaque vente dans une zone)

-- Illégal : recelleur
Config.FenceDefaultPed = 's_m_y_dealer_01' -- modèle du PNJ d'un nouvel emplacement (modifiable ensuite)

-- Entreprises et services publics (lot E1) : types proposés à la création
Config.StructureTypes = {
    company = {
        { id = 'nightclub', label = 'Boîte de nuit' },
        { id = 'dealer', label = 'Concessionnaire' },
        { id = 'business', label = 'Entreprise' },
        { id = 'mechanic', label = 'Mécanique' },
        { id = 'media', label = 'Médias' },
        { id = 'restaurant', label = 'Restaurant' },
    },
    public = {
        { id = 'police', label = 'Police' },
        { id = 'medic', label = 'Médecins' },
        { id = 'administration', label = 'Administration' },
        { id = 'government', label = 'Gouvernement' },
    },
}

-- Points d'interaction (lot E2) : kinds = 'company', 'public' ou 'both' ; ready = utilisable en jeu (lunatic_business)
Config.StructurePointTypes = {
    { id = 'management', label = 'Gestion', kinds = 'both', ready = true },
    { id = 'storage', label = 'Stockage', kinds = 'both', ready = true },
    { id = 'locker', label = 'Casier', kinds = 'both', ready = true },
    { id = 'wardrobe', label = 'Vestiaire', kinds = 'both', ready = true },
    { id = 'doorbell', label = 'Sonnette', kinds = 'both', ready = true },
    { id = 'custom', label = 'Custom', kinds = 'both', ready = true },
    { id = 'catalog', label = 'Catalogue', kinds = 'both', ready = true },
    { id = 'craft', label = 'Craft', kinds = 'both', ready = true },
    { id = 'garage', label = 'Garages', kinds = 'both' },
    { id = 'vehicles', label = 'Véhicules', kinds = 'both' },
    { id = 'dj', label = 'DJ', kinds = 'both' },
    { id = 'blips', label = 'Blips', kinds = 'public' },
    { id = 'weapon_analysis', label = 'Analyse armes', kinds = 'public' },
    { id = 'bracelet', label = 'Bracelet', kinds = 'public' },
    { id = 'armory', label = 'Armurerie', kinds = 'public', ready = true },
    { id = 'id_card', label = "Carte d'identité", kinds = 'public' },
    { id = 'eup', label = 'Binco EUP', kinds = 'public' },
    { id = 'properties', label = 'Propriétés', kinds = 'public' },
}
Config.StructureAccountMaxAction = 10000000

-- Magasins automatiques (tuile Catalogues, lot C1) : kind = items (magasin ox_inventory), clothing / barber / tattoo (apparence, lot C2), rental (location, lot C3)
Config.ShopCategories = {
    { id = 'ltd', label = 'LTD', kind = 'items', blip = { sprite = 52, color = 2 } },
    { id = 'binco', label = 'Binco', kind = 'clothing', blip = { sprite = 73, color = 47 } },
    { id = 'vangelico', label = 'Vangelico', kind = 'items', blip = { sprite = 617, color = 3 } },
    { id = 'barber', label = 'Barber', kind = 'barber', blip = { sprite = 71, color = 51 } },
    { id = 'ammunation', label = 'Ammunation', kind = 'items', blip = { sprite = 110, color = 1 } },
    { id = 'rental', label = 'Location', kind = 'rental', blip = { sprite = 225, color = 3 } },
    { id = 'masquerade', label = 'Masquerade', kind = 'clothing', blip = { sprite = 362, color = 27 } },
    { id = 'shenails', label = 'Shenails', kind = 'clothing', blip = { sprite = 621, color = 8 } },
    { id = 'skateshop', label = 'Skateshop', kind = 'items', blip = { sprite = 59, color = 5 } },
    { id = 'tattoo', label = 'Tattoo', kind = 'tattoo', blip = { sprite = 75, color = 1 } },
    { id = 'wholesale', label = 'Grossistes', kind = 'items', blip = { sprite = 478, color = 66 } },
} -- montant maximum d'une opération staff sur un compte de société

-- Pôle emploi (lot I)
Config.PolesMaxGrades = 20           -- grades maximum par métier
Config.PolesMaxSalary = 100000       -- salaire maximum d'un grade (par paie ESX)

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
local shop = { 'premium.manage', 'shop.manage', 'server.manage', 'poles.manage', 'events.manage' }
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
    { name = 'Admin',             color = '#ff6b6b', level = 80, permissions = with(players, sanctions, tools, economy, world, profile, shop, { 'players.wipe', 'illegal.manage', 'crews.manage', 'companies.manage', 'publics.manage', 'catalogs.manage', 'contextmenu.use', 'players.crash', 'vehicles.give', 'chat.announce_mod', 'logs.view', 'logs.chat', 'sanctions.ban_permanent', 'sanctions.revoke', 'panel.open', 'ranks.view', 'ranks.manage', 'staff.view', 'staff.manage', 'chat.staff', 'chat.announce', 'chat.clear' }) },
    { name = 'Responsable staff', color = '#f2c26b', level = 60, permissions = with(players, sanctions, tools, world, profile, { 'logs.view', 'economy.money', 'economy.job', 'economy.items', 'sanctions.revoke', 'panel.open', 'ranks.view', 'staff.view', 'staff.manage', 'chat.staff', 'chat.announce' }) },
    { name = 'Modérateur',        color = '#5fd3a0', level = 40, permissions = with(players, sanctions, { 'staff.online', 'tools.noclip', 'tools.names', 'tools.tpm', 'tools.vehicles', 'panel.open', 'ranks.view', 'staff.view', 'chat.staff' }) },
    { name = 'Modérateur test',   color = '#6bb8f2', level = 20, permissions = { 'panel.open', 'chat.staff', 'players.view', 'players.goto', 'players.spectate', 'players.heal', 'sanctions.view', 'sanctions.warn', 'tools.noclip', 'tools.names' } },
}
