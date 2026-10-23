-- Illégal : catalogue des missions (tuile Illégal, page Missions).
-- Chaque mission a les mêmes réglages communs : statut, XP, influence, policiers requis (ou bypass), gain,
-- limite par jour et level de crew. Ils priment sur ceux des braquages et des contrats (server/heists.lua,
-- server/contracts.lua), dont il ne reste que les réglages avancés (actions, butin, points…).
-- Les missions pas encore codées sont listées (« à venir ») et déjà réglables.

Missions = {}

local CATEGORIES = {
    { id = 'heist', label = 'Braquages' },
    { id = 'contract', label = 'Contrats' },
    { id = 'traffic', label = 'Trafic' },
    { id = 'street', label = 'Rue' },
}

-- link : système déjà en jeu qui applique ces réglages ; reward : la mission paie un gain en argent sale ;
-- holdup : type des points de la page Braquages (PNJ au comptoir) ; places : lieux fixes de la carte, pour le TP ;
-- ready : codée dans lunatic_illegal ; advanced : réglages propres à la mission (nombres entiers), loot : butin par défaut
local CATALOG = {
    { id = 'heist_ammunation', label = 'Braquage Ammunation', category = 'heist', description = "Menacer l'armurier au comptoir.", holdup = 'ammunation', reward = true },
    { id = 'heist_atm', label = 'Braquage ATM', category = 'heist', description = 'Braquer un distributeur automatique.' },
    { id = 'heist_barber', label = 'Braquage Barber', category = 'heist', description = 'Menacer le coiffeur au comptoir.', holdup = 'barber', reward = true },
    { id = 'heist_binco', label = 'Braquage Binco', category = 'heist', description = 'Menacer le vendeur de la boutique de vêtements.', holdup = 'binco', reward = true },
    { id = 'heist_company', label = 'Braquage Entreprise', category = 'heist', description = 'Braquer une entreprise (activable une par une).', holdup = 'company', reward = true },
    { id = 'heist_fleeca', label = 'Braquage Fleeca', category = 'heist', description = 'Pirater la porte du coffre, puis percer les casiers.', link = { 'heist', 'fleeca' },
        places = { { 'Fleeca Legion Square', 146.9, -1046.0, 29.4 }, { 'Fleeca Alta', 311.3, -284.5, 54.2 }, { 'Fleeca Burton', -353.5, -55.4, 49.0 },
            { 'Fleeca Rockford Hills', -1211.0, -336.6, 37.8 }, { 'Fleeca Banham Canyon', -2957.7, 481.7, 15.7 }, { 'Fleeca Route 68', 1176.1, 2712.9, 38.1 } } },
    { id = 'heist_store', label = 'Braquage Supérette', category = 'heist', description = 'Menacer le vendeur au comptoir, puis percer le coffre.', link = { 'heist', 'store' }, holdup = 'store', reward = true },
    { id = 'heist_tattoo', label = 'Braquage Tattoo', category = 'heist', description = 'Menacer le tatoueur au comptoir.', holdup = 'tattoo', reward = true },
    { id = 'heist_jewelry', label = 'Braquage Vangelico', category = 'heist', description = 'Briser les vitrines de la bijouterie.', link = { 'heist', 'jewelry' },
        places = { { 'Vangelico Rockford Hills', -630.7, -237.0, 38.1 } } },
    { id = 'heist_yacht', label = 'Braquage Yacht', category = 'heist', description = 'Braquer le yacht.' },
    { id = 'contract_delivery', label = 'Livraison', category = 'contract', description = 'Récupérer un colis scellé et le livrer à temps.', link = { 'contract', 'delivery' }, reward = true },
    { id = 'contract_theft', label = 'Vol sur commande', category = 'contract', description = "Voler un modèle précis et l'amener au garage.", link = { 'contract', 'theft' }, reward = true },
    { id = 'contract_cargo', label = 'Cargaison gardée', category = 'contract', description = 'Éliminer les gardes et ouvrir la caisse.', link = { 'contract', 'cargo' }, reward = true },
    { id = 'gofast', label = 'GoFast', category = 'traffic', description = 'Livraison de drogue terrestre.', reward = true },
    { id = 'gofast_sea', label = 'GoFast Maritime', category = 'traffic', description = 'Livraison de drogue maritime.', reward = true },
    { id = 'burglary', label = 'Cambriolage', category = 'street', description = 'Cambrioler des habitations.' },
    { id = 'racket', label = 'Racket', category = 'street', description = 'Racketter des PNJ.', reward = true },
    { id = 'snatch', label = "Vol à l'arraché", category = 'street', description = "Arracher le sac ou le portefeuille d'un passant ([E] tout près de lui).", ready = true, reward = true,
        advanced = {
            { key = 'success', label = 'Chance de réussite (%)', min = 0, max = 100, default = 70 },
            { key = 'alert', label = 'Un témoin appelle la police (%)', min = 0, max = 100, default = 25 },
            { key = 'cooldown', label = 'Délai entre deux vols, par joueur (s)', min = 10, max = 3600, default = 90 },
        },
        loot = { { item = 'jewel_ring', min = 1, max = 1, chance = 10 }, { item = 'jewel_watch', min = 1, max = 1, chance = 6 } } },
}

local BY_ID = {}

for index, entry in ipairs(CATALOG) do
    entry.order = index
    BY_ID[entry.id] = entry
end

-- Valeurs de départ (les missions déjà en jeu reprennent leurs réglages actuels au premier démarrage)
local START = {
    heist_store = { xp = 10, influence = 2 }, heist_jewelry = { xp = 30, influence = 5 }, heist_fleeca = { xp = 60, influence = 10 },
    contract_delivery = { influence = 3 }, contract_theft = { influence = 5 }, contract_cargo = { influence = 8 },
}

-- Gain de départ des braquages de magasins (argent sale, ±20 % à chaque braquage)
local HOLDUP_REWARDS = { heist_store = 1500, heist_barber = 1200, heist_binco = 1200, heist_tattoo = 1500, heist_ammunation = 4000, heist_company = 3000 }

-- Missions codées après coup : réglages de départ appliqués une fois (KVP) sur la ligne déjà créée
local READY_START = {
    snatch = { kvp = 'missions_snatch_ready', values = { reward = 250, xp = 2, influence = 1, police = 0, levelRequired = false } },
}

local LIMITS = { xp = 10000, influence = 1000, police = 20, reward = 1000000, daily = 500, loot = 8 }

local ox = exports.ox_inventory

local settings = {}
local daily = { date = '', counts = {} }

local function whole(value, min, max)
    local n = tonumber(value)
    return n and n == math.floor(n) and n >= min and n <= max and math.floor(n) or nil
end

local function maxLevel()
    return #Config.CrewLevels
end

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer l'illégal.")
end

local function defaultsFor(entry)
    -- Les braquages de magasins sont ouverts à tous les joueurs (crew ou non) ; les autres missions demandent un crew
    local base = { enabled = false, xp = 20, influence = 3, police = 2, bypass = false, reward = 0, dailyLimit = 0, levelRequired = entry.holdup == nil, minLevel = 1 }
    local start = START[entry.id] or {}

    for key, value in pairs(start) do
        base[key] = value
    end

    -- Reprise des réglages actuels des braquages et contrats
    if entry.link then
        local current = entry.link[1] == 'heist' and Heists.settings(entry.link[2]) or Contracts.settings(entry.link[2])

        if current then
            base.enabled = current.enabled ~= false

            if entry.link[1] == 'heist' then
                base.police = current.police or base.police
                base.levelRequired = current.crewOnly == true
                base.minLevel = current.minLevel or 1
            else
                base.police = 0
                base.minLevel = current.minLevel or 1
                base.xp = current.xp or base.xp
                base.reward = math.floor(((current.rewardMin or 0) + (current.rewardMax or 0)) / 2)
            end
        end
    end

    return base
end

---------------------------------------------------------------------
-- Compteurs du jour (tout le serveur, remis à zéro à minuit)
---------------------------------------------------------------------

local function today()
    local date = os.date('%Y-%m-%d')

    if daily.date ~= date then
        daily = { date = date, counts = {} }
    end

    return daily.counts
end

do
    local saved = GetResourceKvpString('missions_daily')
    local ok, value = pcall(json.decode, saved or '')

    if ok and type(value) == 'table' and type(value.counts) == 'table' then
        daily = { date = tostring(value.date or ''), counts = value.counts }
    end
end

-- Une mission commence : refusée si la limite du jour est atteinte, sinon comptée
function Missions.take(id)
    local s = settings[id]
    local counts = today()
    local used = counts[id] or 0

    if s and s.dailyLimit > 0 and used >= s.dailyLimit then
        return false
    end

    counts[id] = used + 1
    SetResourceKvp('missions_daily', json.encode(daily))
    return true
end

exports('takeMissionSlot', Missions.take)

-- Réglages communs d'une mission (nil si inconnue)
function Missions.get(id)
    return settings[id]
end

-- Réglages complets d'une mission codée dans lunatic_illegal : communs + avancés (valeurs par défaut comprises) + butin
exports('getMissionSettings', function(id)
    local entry, s = BY_ID[id], settings[id]

    if not entry or not s then
        return nil
    end

    local full = json.decode(json.encode(s))
    full.id = id
    full.police = s.bypass and 0 or s.police
    full.advanced = full.advanced or {}

    for _, field in ipairs(entry.advanced or {}) do
        if full.advanced[field.key] == nil then
            full.advanced[field.key] = field.default
        end
    end

    full.loot = full.loot or json.decode(json.encode(entry.loot or {}))
    return full
end)

-- Réglages communs appliqués sur ceux d'un braquage ou d'un contrat (utilisé par getHeistConfig / getContractConfig)
function Missions.apply(kind, typeId, s)
    local id = (kind == 'heist' and 'heist_' or 'contract_') .. typeId
    local m = settings[id]

    if not m then
        return s
    end

    s.enabled = m.enabled
    s.police = m.bypass and 0 or m.police
    s.minLevel = m.levelRequired and m.minLevel or 1
    s.mission = { id = id, xp = m.xp, influence = m.influence }

    if kind == 'heist' then
        s.crewOnly = m.levelRequired
    else
        s.xp = m.xp
        s.rewardMin = math.floor(m.reward * 0.8)
        s.rewardMax = math.floor(m.reward * 1.2)
    end

    return s
end

---------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------

local function load()
    settings = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_missions`') or {}) do
        local ok, value = pcall(json.decode, row.settings or '')

        if ok and type(value) == 'table' and BY_ID[row.id] then
            settings[row.id] = value
        end
    end

    -- Missions sans réglages : valeurs de départ enregistrées une fois (elles ne bougent plus ensuite)
    for _, entry in ipairs(CATALOG) do
        if not settings[entry.id] then
            settings[entry.id] = defaultsFor(entry)
            MySQL.insert.await('INSERT INTO `lunatic_missions` (`id`, `settings`) VALUES (?, ?)', { entry.id, json.encode(settings[entry.id]) })
        end
    end

    -- Braquages de magasins (lot 2b) : un gain de départ pour ceux qui n'en avaient pas encore
    if not GetResourceKvpString('missions_holdup_rewards') then
        SetResourceKvp('missions_holdup_rewards', '1')

        for id, reward in pairs(HOLDUP_REWARDS) do
            local s = settings[id]

            if s and (s.reward or 0) == 0 then
                s.reward = reward
                MySQL.update.await('UPDATE `lunatic_missions` SET `settings` = ? WHERE `id` = ?', { json.encode(s), id })
            end
        end
    end

    -- Braquages de magasins ouverts à tous les joueurs, pas seulement aux crews (une fois, pour les réglages déjà créés)
    if not GetResourceKvpString('missions_holdup_open') then
        SetResourceKvp('missions_holdup_open', '1')

        for id in pairs(HOLDUP_REWARDS) do
            local s = settings[id]

            if s and s.levelRequired then
                s.levelRequired = false
                MySQL.update.await('UPDATE `lunatic_missions` SET `settings` = ? WHERE `id` = ?', { json.encode(s), id })
            end
        end
    end

    for id, start in pairs(READY_START) do
        local s = settings[id]

        if s and not GetResourceKvpString(start.kvp) then
            SetResourceKvp(start.kvp, '1')

            for key, value in pairs(start.values) do
                if key ~= 'reward' or (s.reward or 0) == 0 then
                    s[key] = value
                end
            end

            MySQL.update.await('UPDATE `lunatic_missions` SET `settings` = ? WHERE `id` = ?', { json.encode(s), id })
        end
    end

    TriggerEvent('lunatic_admin:heistsChanged')
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_missions` (
            `id` VARCHAR(30) NOT NULL,
            `settings` TEXT NOT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    load()
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

Panel.actions['missions.list'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local counts = today()
    local list = {}

    local function itemLabel(name)
        local item = ox:Items(name)
        return item and item.label or name, not item
    end

    for _, entry in ipairs(CATALOG) do
        local places = {}
        local advanced, loot = nil, nil

        -- Réglages avancés : champs du catalogue avec la valeur enregistrée, et butin avec le nom des objets
        if entry.advanced then
            local saved = settings[entry.id] and settings[entry.id].advanced or {}
            advanced = {}

            for _, field in ipairs(entry.advanced) do
                advanced[#advanced + 1] = { key = field.key, label = field.label, min = field.min, max = field.max, value = saved[field.key] or field.default }
            end

            loot = {}

            for _, l in ipairs(settings[entry.id] and settings[entry.id].loot or entry.loot or {}) do
                local label, missing = itemLabel(l.item)
                loot[#loot + 1] = { item = l.item, min = l.min, max = l.max, chance = l.chance, label = label, missing = missing }
            end
        end

        for index, place in ipairs(entry.places or {}) do
            places[#places + 1] = { index = index, label = place[1], x = place[2], y = place[3], z = place[4] }
        end

        list[#list + 1] = {
            id = entry.id, label = entry.label, category = entry.category, description = entry.description,
            ready = entry.ready == true or entry.link ~= nil or (entry.holdup ~= nil and entry.holdup ~= 'heliwave'), link = entry.link and { kind = entry.link[1], type = entry.link[2] } or nil, reward = entry.reward == true,
            holdup = entry.holdup, places = places, settings = settings[entry.id], today = counts[entry.id] or 0,
            advanced = advanced, loot = loot,
        }
    end

    return { ok = true, silent = true, categories = CATEGORIES, missions = list, maxLevel = maxLevel() }
end

-- TP à un lieu fixe d'une mission (banques Fleeca, bijouterie)
Panel.actions['missions.tp'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local entry = BY_ID[data.id]
    local place = entry and entry.places and entry.places[tonumber(data.index)]

    if not place then
        return Panel.fail('Lieu introuvable.')
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(place[2], place[3], place[4] + 1.0))
    return { ok = true, silent = true }
end

Panel.actions['missions.save'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local entry = BY_ID[data.id]
    local input = type(data.settings) == 'table' and data.settings or {}

    if not entry then
        return Panel.fail('Mission inconnue.')
    end

    local s = {
        enabled = input.enabled == true,
        xp = whole(input.xp, 0, LIMITS.xp),
        influence = whole(input.influence, 0, LIMITS.influence),
        police = whole(input.police, 0, LIMITS.police),
        bypass = input.bypass == true,
        reward = entry.reward and whole(input.reward, 0, LIMITS.reward) or 0,
        dailyLimit = whole(input.dailyLimit, 0, LIMITS.daily),
        levelRequired = input.levelRequired == true,
        minLevel = whole(input.minLevel, 1, maxLevel()),
    }

    if not s.xp or not s.influence then
        return Panel.fail(('XP (0 à %d) et influence (0 à %d) : des nombres entiers.'):format(LIMITS.xp, LIMITS.influence))
    end

    if not s.police then
        return Panel.fail(('Policiers requis : un nombre entier entre 0 et %d.'):format(LIMITS.police))
    end

    if not s.reward then
        return Panel.fail(('Gain : un nombre entier entre 0 et %d $.'):format(LIMITS.reward))
    end

    if not s.dailyLimit then
        return Panel.fail(('Limite par jour : un nombre entier entre 0 (sans limite) et %d.'):format(LIMITS.daily))
    end

    if not s.minLevel then
        return Panel.fail(('Level requis : un nombre entier entre 1 et %d.'):format(maxLevel()))
    end

    -- Les réglages avancés et le butin se gardent (ils s'enregistrent à part)
    local previous = settings[entry.id] or {}
    s.advanced, s.loot = previous.advanced, previous.loot

    settings[entry.id] = s
    MySQL.update.await('INSERT INTO `lunatic_missions` (`id`, `settings`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `settings` = VALUES(`settings`)', { entry.id, json.encode(s) })
    TriggerEvent('lunatic_admin:heistsChanged')
    TriggerEvent('lunatic_admin:holdupsChanged')
    Logs.add(src, 'missions.save', nil, { label = entry.label, operation = s.enabled and 'active' or 'désactivée' })

    return { ok = true, silent = true }
end

-- Réglages avancés d'une mission (champs décrits dans le catalogue) et butin
Panel.actions['missions.saveAdvanced'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local entry = BY_ID[data.id]
    local s = entry and settings[entry.id]

    if not s or not entry.advanced then
        return Panel.fail('Mission inconnue.')
    end

    local input = type(data.advanced) == 'table' and data.advanced or {}
    local advanced = {}

    for _, field in ipairs(entry.advanced) do
        local value = whole(input[field.key], field.min, field.max)

        if not value then
            return Panel.fail(('%s : un nombre entier entre %d et %d.'):format(field.label, field.min, field.max))
        end

        advanced[field.key] = value
    end

    local loot = {}

    if type(data.loot) ~= 'table' or #data.loot > LIMITS.loot then
        return Panel.fail(('Butin : %d objets maximum.'):format(LIMITS.loot))
    end

    for _, l in ipairs(data.loot) do
        local min, max, chance = whole(l.min, 1, 1000), whole(l.max, 1, 1000), whole(l.chance, 1, 100)

        if type(l.item) ~= 'string' or not ox:Items(l.item) or not min or not max or not chance or min > max then
            return Panel.fail(('Butin invalide : %s.'):format(tostring(l.item)))
        end

        loot[#loot + 1] = { item = l.item, min = min, max = max, chance = chance }
    end

    s.advanced, s.loot = advanced, loot
    MySQL.update.await('UPDATE `lunatic_missions` SET `settings` = ? WHERE `id` = ?', { json.encode(s), entry.id })
    TriggerEvent('lunatic_admin:heistsChanged')
    Logs.add(src, 'missions.save', nil, { label = entry.label, operation = 'réglages avancés' })

    return { ok = true, silent = true }
end
