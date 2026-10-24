-- Tuile Fonctionnalités : réglages du gameplay appliqués en direct (GlobalState.lunaticFeatures), sans redémarrage.
-- Chaque section a un schéma (type, bornes, valeur par défaut) : le panel n'envoie que des valeurs revérifiées ici.
-- Lecteurs : lunatic_admin (client/features.lua : PvP, population, HUD, Discord ; inventaire ox ci-dessous),
-- esx_basicneeds (faim et soif), lunatic_chat (chat textuel), lunatic_world (temps en jeu),
-- es_extended (argent de départ, salaire hors service) et les systèmes ajoutés ensuite (mort, carburant…).

Features = {}

local function bool(default) return { type = 'bool', default = default } end
local function num(default, min, max, step) return { type = 'number', default = default, min = min, max = max, step = step } end
local function text(default, max, pattern) return { type = 'string', default = default, max = max, pattern = pattern } end

-- Ordre d'affichage dans le panel : FIELDS[section] = { { key, label, hint }, … } (libellés dans web/features_page.js)
local SCHEMA = {
    toggles = {
        pvp = bool(true), needs = bool(true), chat = bool(true),
        hud = bool(true), minimap = bool(true), speedometer = bool(true),
    },
    needs = {
        hunger = num(100, 0, 2000, 1), thirst = num(75, 0, 2000, 1), sprint = num(1.5, 1, 5, 0.1),
    },
    inventory = {
        weight = num(30000, 5000, 500000, 1000), slots = num(50, 10, 120, 1),
    },
    population = {
        peds = num(1.0, 0, 1, 0.05), vehicles = num(1.0, 0, 1, 0.05), parked = num(1.0, 0, 1, 0.05), scenario = num(1.0, 0, 1, 0.05),
    },
    time = {
        minute = num(2000, 250, 60000, 250),
    },
    newPlayers = {
        bank = num(50000, 0, 10000000, 100), money = num(0, 0, 10000000, 100), offDuty = num(0.5, 0, 1, 0.05),
    },
    discord = {
        enabled = bool(false), appId = text('', 25, '^%d*$'), asset = text('', 40, '^[%w_%-]*$'), assetText = text('', 80),
        presence = text('{player_rp_name} · {server_players}/{server_maxplayers} joueurs', 120),
    },
}

local settings = {}

local function defaults(section)
    local values = {}

    for key, field in pairs(SCHEMA[section]) do
        values[key] = field.default
    end

    return values
end

-- Valeur sûre d'un champ (nil si invalide)
local function clean(field, value)
    if field.type == 'bool' then
        if type(value) == 'boolean' then
            return value
        end

        return nil
    end

    if field.type == 'number' then
        local number = tonumber(value)

        if not number or number < field.min or number > field.max then
            return nil
        end

        local step = field.step or 1
        return math.floor(number / step + 0.5) * step
    end

    if type(value) ~= 'string' then
        return nil
    end

    local str = value:gsub('%c', ' '):match('^%s*(.-)%s*$')

    if utf8.len(str) == nil or utf8.len(str) > field.max or (field.pattern and not str:match(field.pattern)) then
        return nil
    end

    return str
end

local function load()
    local saved = GetResourceKvpString('features')
    local ok, decoded = pcall(json.decode, saved or '{}')
    decoded = ok and type(decoded) == 'table' and decoded or {}

    for section, fields in pairs(SCHEMA) do
        settings[section] = defaults(section)

        for key, field in pairs(fields) do
            local value = decoded[section] and clean(field, decoded[section][key])

            if value ~= nil then
                settings[section][key] = value
            end
        end
    end
end

-- Liste des sections ajoutées par d'autres modules (mort, carburant…) : même mécanisme
function Features.register(section, fields)
    SCHEMA[section] = fields
    load()
    GlobalState.lunaticFeatures = settings
end

function Features.get(section)
    return settings[section]
end

exports('getFeatures', function(section)
    return section and settings[section] or settings
end)

load()
GlobalState.lunaticFeatures = settings

-- Nombre de joueurs (Rich Presence Discord)
CreateThread(function()
    GlobalState.lunaticMaxPlayers = GetConvarInt('sv_maxclients', 64)

    while true do
        GlobalState.lunaticPlayerCount = #GetPlayers()
        Wait(30000)
    end
end)

---------------------------------------------------------------------
-- Inventaire des joueurs (ox_inventory) : poids et emplacements
---------------------------------------------------------------------

local ox = exports.ox_inventory

local function applyInventory(src)
    local values = settings.inventory
    pcall(function()
        ox:SetMaxWeight(src, values.weight)
        ox:SetSlotCount(src, values.slots)
    end)
end

AddEventHandler('esx:playerLoaded', function(playerId)
    SetTimeout(3000, function()
        if GetPlayerName(playerId) then
            applyInventory(playerId)
        end
    end)
end)

---------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les fonctionnalités.")
end

-- Schéma pour le panel (bornes des curseurs)
local function schemaForPanel()
    local list = {}

    for section, fields in pairs(SCHEMA) do
        list[section] = {}

        for key, field in pairs(fields) do
            list[section][key] = { type = field.type, default = field.default, min = field.min, max = field.max, step = field.step, maxLength = field.max }
        end
    end

    return list
end

Panel.actions['features.get'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'features.manage') then
        return denied()
    end

    return { ok = true, silent = true, settings = settings, schema = schemaForPanel() }
end

Panel.actions['features.save'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'features.manage') then
        return denied()
    end

    local fields = SCHEMA[data.section]

    if not fields or type(data.values) ~= 'table' then
        return Panel.fail('Section inconnue.')
    end

    local values, changed = {}, {}

    for key, field in pairs(fields) do
        local value = data.values[key]

        if value == nil then
            value = settings[data.section][key]
        end

        local safe = clean(field, value)

        if safe == nil then
            return Panel.fail(('Valeur invalide : %s.'):format(key))
        end

        values[key] = safe

        if safe ~= settings[data.section][key] then
            changed[#changed + 1] = key
        end
    end

    settings[data.section] = values
    SetResourceKvp('features', json.encode(settings))
    GlobalState.lunaticFeatures = settings

    if data.section == 'inventory' then
        for _, id in ipairs(GetPlayers()) do
            applyInventory(tonumber(id))
        end
    end

    Logs.add(src, 'features.save', nil, { section = data.section, changed = changed })
    return { ok = true, silent = true }
end
