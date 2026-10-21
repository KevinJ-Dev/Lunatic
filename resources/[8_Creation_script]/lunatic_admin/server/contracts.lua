-- Illégal, étape 7a : contrats de mission (tuile Illégal, onglet Missions).
-- Ici : réglages de chaque type de contrat et points en ville, gérés dans le panel.
-- Le déroulement en jeu (offres, contrats en cours, récompenses) est dans lunatic_illegal/server/contracts.lua,
-- qui lit cette configuration par l'export getContractConfig (jamais diffusée aux joueurs).

local ox = exports.ox_inventory

local TYPES = {
    delivery = { label = 'Livraison', points = { pickup = 'Points de récupération', dropoff = 'Points de livraison' } },
    theft = { label = 'Vol sur commande', points = { car_spawn = 'Véhicules à voler', garage = 'Garages de livraison' } },
    cargo = { label = 'Cargaison gardée', points = { cargo = 'Cargaisons' } },
}

local KIND_TYPE = {}

for typeId, entry in pairs(TYPES) do
    for kind in pairs(entry.points) do
        KIND_TYPE[kind] = typeId
    end
end

local DEFAULTS = {
    delivery = { enabled = true, minLevel = 1, rewardMin = 1500, rewardMax = 3000, xp = 25, duration = 15, alertChance = 30,
        loot = { { item = 'gun_spring', min = 1, max = 3, chance = 50 }, { item = 'bullet_casing', min = 10, max = 30, chance = 50 } } },
    theft = { enabled = true, minLevel = 2, rewardMin = 3000, rewardMax = 6000, xp = 40, duration = 25, alertChance = 50,
        vehicles = { 'sultan', 'buffalo', 'felon', 'jackal', 'oracle', 'tailgater' }, loot = { { item = 'gun_slide', min = 1, max = 1, chance = 30 } } },
    cargo = { enabled = true, minLevel = 3, rewardMin = 4000, rewardMax = 8000, xp = 60, duration = 25, alertChance = 40,
        guards = 4, guardModel = 'g_m_y_mexgoon_01', guardWeapon = 'WEAPON_PISTOL',
        loot = { { item = 'gun_barrel', min = 1, max = 2, chance = 60 }, { item = 'gun_slide', min = 1, max = 1, chance = 50 }, { item = 'gunpowder', min = 2, max = 5, chance = 80 }, { item = 'bullet_casing', min = 20, max = 50, chance = 80 } } },
}

local LIMITS = { points = 60, reward = 1000000, xp = 10000, duration = 120, level = #Config.CrewLevels, loot = 10, vehicles = 20, guards = 10 }

local settings, points = {}, {}

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer l'illégal.")
end

local function whole(value, min, max)
    local n = tonumber(value)
    return n and n == math.floor(n) and n >= min and n <= max and math.floor(n) or nil
end

local function positionOf(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z - 0.98, h = GetEntityHeading(ped) }
end

local function copy(value)
    return json.decode(json.encode(value))
end

local function load()
    settings, points = {}, {}

    for typeId, defaults in pairs(DEFAULTS) do
        settings[typeId] = copy(defaults)
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_contract_settings`') or {}) do
        local ok, value = pcall(json.decode, row.settings or '')

        if ok and type(value) == 'table' and settings[row.type] then
            for key, entry in pairs(value) do
                settings[row.type][key] = entry
            end
        end
    end

    for kind in pairs(KIND_TYPE) do
        points[kind] = {}
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_contract_points` ORDER BY `id`') or {}) do
        if points[row.kind] then
            points[row.kind][#points[row.kind] + 1] = { id = tonumber(row.id), kind = row.kind, label = row.label, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h) }
        end
    end
end

local function findPoint(id)
    for _, list in pairs(points) do
        for _, point in ipairs(list) do
            if point.id == tonumber(id) then
                return point
            end
        end
    end
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_contract_settings` (
            `type` VARCHAR(20) NOT NULL,
            `settings` TEXT NOT NULL,
            PRIMARY KEY (`type`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_contract_points` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `kind` VARCHAR(20) NOT NULL,
            `label` VARCHAR(60) NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `h` DOUBLE NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_contract_points_kind` (`kind`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    load()
end)

-- Configuration lue par lunatic_illegal (serveur uniquement)
exports('getContractConfig', function()
    return { settings = settings, points = points, labels = { delivery = TYPES.delivery.label, theft = TYPES.theft.label, cargo = TYPES.cargo.label } }
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function guard(actor)
    return Ranks.hasPermission(actor, 'illegal.manage')
end

local function activeContracts()
    local found, list = pcall(function() return exports.lunatic_illegal:getActiveContracts() end)
    return found and type(list) == 'table' and list or {}
end

Panel.actions['contracts.info'] = function(_, actor)
    if not guard(actor) then
        return denied()
    end

    local types = {}

    for typeId, entry in pairs(TYPES) do
        local kinds = {}

        for kind, label in pairs(entry.points) do
            kinds[#kinds + 1] = { id = kind, label = label, points = points[kind] or {} }
        end

        table.sort(kinds, function(a, b) return a.id > b.id end)
        types[#types + 1] = { id = typeId, label = entry.label, settings = copy(settings[typeId]), kinds = kinds }
    end

    local order = { delivery = 1, theft = 2, cargo = 3 }
    table.sort(types, function(a, b) return order[a.id] < order[b.id] end)

    -- Objets du butin : libellé et existence dans ox_inventory
    for _, entry in ipairs(types) do
        for _, loot in ipairs(entry.settings.loot or {}) do
            local item = ox:Items(loot.item)
            loot.label = item and item.label or loot.item
            loot.missing = item == nil
        end
    end

    return { ok = true, silent = true, types = types, active = activeContracts(), maxLevel = LIMITS.level }
end

Panel.actions['contracts.saveSettings'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local typeId = data.type

    if not TYPES[typeId] or type(data.settings) ~= 'table' then
        return Panel.fail('Type de contrat inconnu.')
    end

    local input = data.settings
    local value = {
        enabled = input.enabled ~= false,
        minLevel = whole(input.minLevel, 1, LIMITS.level),
        rewardMin = whole(input.rewardMin, 0, LIMITS.reward),
        rewardMax = whole(input.rewardMax, 0, LIMITS.reward),
        xp = whole(input.xp, 0, LIMITS.xp),
        duration = whole(input.duration, 3, LIMITS.duration),
        alertChance = whole(input.alertChance, 0, 100),
        loot = {},
    }

    if not value.minLevel or not value.rewardMin or not value.rewardMax or not value.xp or not value.duration or not value.alertChance then
        return Panel.fail('Une valeur est invalide (level, récompense, XP, durée de 3 à 120 min, alerte de 0 à 100 %).')
    end

    if value.rewardMin > value.rewardMax then
        return Panel.fail('La récompense minimum dépasse le maximum.')
    end

    if type(input.loot) ~= 'table' or #input.loot > LIMITS.loot then
        return Panel.fail(('Butin : %d objets maximum.'):format(LIMITS.loot))
    end

    for _, entry in ipairs(input.loot) do
        local min, max, chance = whole(entry.min, 1, 1000), whole(entry.max, 1, 1000), whole(entry.chance, 1, 100)

        if type(entry.item) ~= 'string' or not ox:Items(entry.item) or not min or not max or not chance or min > max then
            return Panel.fail(('Butin invalide : %s.'):format(tostring(entry.item)))
        end

        value.loot[#value.loot + 1] = { item = entry.item, min = min, max = max, chance = chance }
    end

    if typeId == 'theft' then
        value.vehicles = {}

        if type(input.vehicles) ~= 'table' or #input.vehicles < 1 or #input.vehicles > LIMITS.vehicles then
            return Panel.fail(('Vol sur commande : de 1 à %d modèles de véhicule.'):format(LIMITS.vehicles))
        end

        for _, model in ipairs(input.vehicles) do
            if type(model) ~= 'string' or not model:match('^[%w_]+$') or #model > 30 then
                return Panel.fail(('Modèle de véhicule invalide : %s.'):format(tostring(model)))
            end

            value.vehicles[#value.vehicles + 1] = model:lower()
        end
    end

    if typeId == 'cargo' then
        value.guards = whole(input.guards, 0, LIMITS.guards)
        value.guardModel = type(input.guardModel) == 'string' and input.guardModel:match('^[%w_]+$') and input.guardModel or nil
        value.guardWeapon = type(input.guardWeapon) == 'string' and input.guardWeapon:upper():match('^WEAPON_[%w_]+$') or nil

        if not value.guards or not value.guardModel or not value.guardWeapon then
            return Panel.fail('Gardes : nombre (0 à 10), modèle de PNJ et arme (WEAPON_…) requis.')
        end
    end

    MySQL.query.await('INSERT INTO `lunatic_contract_settings` (`type`, `settings`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `settings` = VALUES(`settings`)', { typeId, json.encode(value) })
    load()
    Logs.add(src, 'contracts.save', nil, { label = TYPES[typeId].label, operation = 'edit' })

    return { ok = true, silent = true }
end

Panel.actions['contracts.addPoint'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local label = type(data.label) == 'string' and data.label:gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    local position = positionOf(src)

    if not KIND_TYPE[data.kind] then
        return Panel.fail('Type de point inconnu.')
    end

    if #label < 2 or #label > 60 then
        return Panel.fail('Le nom doit faire entre 2 et 60 caractères.')
    end

    if not position then
        return Panel.fail('Position introuvable.')
    end

    if #(points[data.kind] or {}) >= LIMITS.points then
        return Panel.fail(('Maximum %d points de ce type.'):format(LIMITS.points))
    end

    MySQL.insert.await('INSERT INTO `lunatic_contract_points` (`kind`, `label`, `x`, `y`, `z`, `h`) VALUES (?, ?, ?, ?, ?, ?)', { data.kind, label, position.x, position.y, position.z, position.h })
    load()
    Logs.add(src, 'contracts.point', nil, { label = label, operation = 'add' })

    return { ok = true, silent = true }
end

Panel.actions['contracts.movePoint'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findPoint(data.id)
    local position = positionOf(src)

    if not point or not position then
        return Panel.fail('Point introuvable.')
    end

    MySQL.update.await('UPDATE `lunatic_contract_points` SET `x` = ?, `y` = ?, `z` = ?, `h` = ? WHERE `id` = ?', { position.x, position.y, position.z, position.h, point.id })
    load()
    Logs.add(src, 'contracts.point', nil, { label = point.label, operation = 'move' })

    return { ok = true, silent = true }
end

Panel.actions['contracts.deletePoint'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findPoint(data.id)

    if not point then
        return Panel.fail('Point introuvable.')
    end

    MySQL.update.await('DELETE FROM `lunatic_contract_points` WHERE `id` = ?', { point.id })
    load()
    Logs.add(src, 'contracts.point', nil, { label = point.label, operation = 'delete' })

    return { ok = true, silent = true }
end

Panel.actions['contracts.tpPoint'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findPoint(data.id)

    if not point then
        return Panel.fail('Point introuvable.')
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(point.x, point.y, point.z + 1.0))
    return { ok = true, silent = true }
end

-- Annule le contrat en cours d'un crew (lunatic_illegal nettoie véhicule et gardes)
Panel.actions['contracts.cancel'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local found, done = pcall(function() return exports.lunatic_illegal:cancelContract(tonumber(data.crewId)) end)

    if not found or not done then
        return Panel.fail('Contrat introuvable (déjà terminé ?).')
    end

    Logs.add(src, 'contracts.cancel', nil, { label = tostring(data.label or data.crewId) })
    return { ok = true, silent = true }
end

print("[lunatic_admin] Module Contrats chargé.")
