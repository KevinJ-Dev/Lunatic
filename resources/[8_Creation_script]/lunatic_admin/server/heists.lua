-- Illégal, étape 7b : braquages (tuile Illégal, onglet Braquages).
-- Ici : réglages de chaque type (supérettes, bijouterie, banques Fleeca) et points ajoutés à la main.
-- Les cibles sont surtout détectées en jeu par leur modèle (caisses, coffres, vitrines, portes de coffre) :
-- tous les magasins de la carte sont braquables sans rien placer. Le déroulement est dans lunatic_illegal/server/heists.lua.

local ox = exports.ox_inventory

local TYPES = {
    store = { label = 'Supérettes', actions = { register = 'Caisse', safe = 'Coffre' } },
    jewelry = { label = 'Bijouterie', actions = { case = 'Vitrine' } },
    fleeca = { label = 'Banques Fleeca', actions = { door = 'Porte du coffre', locker = 'Casier' } },
}
local ORDER = { store = 1, jewelry = 2, fleeca = 3 }
local ACTION_ORDER = { register = 1, safe = 2, case = 1, door = 1, locker = 2 }
-- Les casiers n'ont pas de point : ils se percent dans le coffre, une fois la porte ouverte
local POINT_KINDS = { register = 'store', safe = 'store', case = 'jewelry', door = 'fleeca' }

local DEFAULTS = {
    store = { enabled = true, police = 1, cooldown = 45, crewOnly = false, minLevel = 1, actions = {
        register = { duration = 12, tool = 'lockpick', breakChance = 30, alert = 40, models = { 'prop_till_01' }, loot = { { item = 'marked_bills', min = 3, max = 8, chance = 100 } } },
        safe = { duration = 45, tool = 'drill', breakChance = 15, alert = 100, models = { 'p_v_43_safe_s' }, loot = { { item = 'marked_bills', min = 10, max = 20, chance = 100 } } },
    } },
    jewelry = { enabled = true, police = 3, cooldown = 120, crewOnly = true, minLevel = 2, actions = {
        case = { duration = 5, tool = '', breakChance = 0, alert = 100, models = { 'des_jewel_cab_start', 'des_jewel_cab2_start', 'des_jewel_cab3_start', 'des_jewel_cab4_start' },
            loot = { { item = 'jewel_watch', min = 1, max = 2, chance = 50 }, { item = 'jewel_ring', min = 1, max = 3, chance = 60 }, { item = 'jewel_necklace', min = 1, max = 1, chance = 40 } } },
    } },
    fleeca = { enabled = true, police = 4, cooldown = 180, crewOnly = true, minLevel = 3, actions = {
        door = { duration = 15, tool = 'hack_device', breakChance = 25, alert = 100, models = { 'v_ilev_gb_vauldr' }, loot = {} },
        locker = { duration = 30, tool = 'drill', breakChance = 10, alert = 0, count = 4, models = {}, loot = { { item = 'marked_bills', min = 15, max = 30, chance = 100 }, { item = 'gold_bar', min = 1, max = 1, chance = 15 } } },
    } },
}

-- Prix proposés au recelleur pour le butin (bouton « Ajouter le butin au recelleur »)
local FENCE_LOOT = { { 'marked_bills', 70 }, { 'jewel_watch', 450 }, { 'jewel_ring', 300 }, { 'jewel_necklace', 600 }, { 'gold_bar', 3000 } }

local LIMITS = { points = 100, police = 20, cooldown = 1440, duration = 300, loot = 8, models = 10, count = 20 }

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
    return { x = coords.x, y = coords.y, z = coords.z, h = GetEntityHeading(ped) }
end

local function copy(value)
    return json.decode(json.encode(value))
end

local function load()
    settings, points = {}, {}

    for typeId, defaults in pairs(DEFAULTS) do
        settings[typeId] = copy(defaults)
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_heist_settings`') or {}) do
        local ok, value = pcall(json.decode, row.settings or '')

        if ok and type(value) == 'table' and settings[row.type] then
            settings[row.type] = value
        end
    end

    for kind in pairs(POINT_KINDS) do
        points[kind] = {}
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_heist_points` ORDER BY `id`') or {}) do
        if points[row.kind] then
            points[row.kind][#points[row.kind] + 1] = { id = tonumber(row.id), kind = row.kind, label = row.label, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h) }
        end
    end

    -- Les joueurs rechargent la configuration (lunatic_illegal)
    TriggerEvent('lunatic_admin:heistsChanged')
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
        CREATE TABLE IF NOT EXISTS `lunatic_heist_settings` (
            `type` VARCHAR(20) NOT NULL,
            `settings` TEXT NOT NULL,
            PRIMARY KEY (`type`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_heist_points` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `kind` VARCHAR(20) NOT NULL,
            `label` VARCHAR(60) NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `h` DOUBLE NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_heist_points_kind` (`kind`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    load()
end)

-- Configuration lue par lunatic_illegal (serveur, puis envoyée aux joueurs pour la détection)
exports('getHeistConfig', function()
    local labels = {}

    for typeId, entry in pairs(TYPES) do
        labels[typeId] = { label = entry.label, actions = entry.actions }
    end

    return { settings = settings, points = points, labels = labels }
end)

---------------------------------------------------------------------
-- Validation des réglages
---------------------------------------------------------------------

local function readAction(input, actionId)
    if type(input) ~= 'table' then
        return nil, 'Réglages incomplets.'
    end

    local action = {
        duration = whole(input.duration, 3, LIMITS.duration),
        tool = type(input.tool) == 'string' and input.tool or '',
        breakChance = whole(input.breakChance, 0, 100),
        alert = whole(input.alert, 0, 100),
        models = {},
        loot = {},
    }

    if not action.duration or not action.breakChance or not action.alert then
        return nil, ("%s : durée (3 à %d s), casse de l'outil et alerte (0 à 100 %%) requises."):format(actionId, LIMITS.duration)
    end

    if action.tool ~= '' and not ox:Items(action.tool) then
        return nil, ("L'outil « %s » n'existe pas dans ox_inventory."):format(action.tool)
    end

    if actionId == 'locker' then
        action.count = whole(input.count, 1, LIMITS.count)

        if not action.count then
            return nil, ('Casiers : de 1 à %d par braquage.'):format(LIMITS.count)
        end
    end

    if type(input.models) ~= 'table' or #input.models > LIMITS.models then
        return nil, ('%d modèles maximum.'):format(LIMITS.models)
    end

    for _, model in ipairs(input.models) do
        if type(model) ~= 'string' or not model:match('^[%w_]+$') or #model > 40 then
            return nil, ('Modèle invalide : %s.'):format(tostring(model))
        end

        action.models[#action.models + 1] = model:lower()
    end

    if type(input.loot) ~= 'table' or #input.loot > LIMITS.loot then
        return nil, ('Butin : %d objets maximum.'):format(LIMITS.loot)
    end

    for _, entry in ipairs(input.loot) do
        local min, max, chance = whole(entry.min, 1, 1000), whole(entry.max, 1, 1000), whole(entry.chance, 1, 100)

        if type(entry.item) ~= 'string' or not ox:Items(entry.item) or not min or not max or not chance or min > max then
            return nil, ('Butin invalide : %s.'):format(tostring(entry.item))
        end

        action.loot[#action.loot + 1] = { item = entry.item, min = min, max = max, chance = chance }
    end

    return action
end

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function guard(actor)
    return Ranks.hasPermission(actor, 'illegal.manage')
end

local function heistStates()
    local found, list = pcall(function() return exports.lunatic_illegal:getHeistStates() end)
    return found and type(list) == 'table' and list or {}
end

Panel.actions['heists.info'] = function(_, actor)
    if not guard(actor) then
        return denied()
    end

    local function label(name)
        local item = name ~= '' and ox:Items(name)
        return item and item.label or name, name ~= '' and not item
    end

    local types = {}

    for typeId, entry in pairs(TYPES) do
        local s = copy(settings[typeId])
        local actions = {}

        for actionId, actionLabel in pairs(entry.actions) do
            local action = s.actions[actionId] or {}
            action.id, action.label = actionId, actionLabel
            action.toolLabel, action.toolMissing = label(action.tool or '')

            for _, loot in ipairs(action.loot or {}) do
                loot.label, loot.missing = label(loot.item)
            end

            action.points = points[actionId]
            actions[#actions + 1] = action
        end

        table.sort(actions, function(a, b) return ACTION_ORDER[a.id] < ACTION_ORDER[b.id] end)
        s.actions = nil
        types[#types + 1] = { id = typeId, label = entry.label, settings = s, actions = actions }
    end

    table.sort(types, function(a, b) return ORDER[a.id] < ORDER[b.id] end)

    local fenceMissing = {}
    local present = {}

    for _, entry in ipairs((GlobalState.lunaticFence or {}).items or {}) do
        present[entry.item] = true
    end

    for _, entry in ipairs(FENCE_LOOT) do
        if not present[entry[1]] then
            fenceMissing[#fenceMissing + 1] = entry[1]
        end
    end

    return { ok = true, silent = true, types = types, states = heistStates(), fenceMissing = fenceMissing, maxLevel = #Config.CrewLevels }
end

Panel.actions['heists.saveSettings'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local typeId = data.type
    local input = data.settings

    if not TYPES[typeId] or type(input) ~= 'table' or type(input.actions) ~= 'table' then
        return Panel.fail('Type de braquage inconnu.')
    end

    local value = {
        enabled = input.enabled ~= false,
        police = whole(input.police, 0, LIMITS.police),
        cooldown = whole(input.cooldown, 5, LIMITS.cooldown),
        crewOnly = input.crewOnly == true,
        minLevel = whole(input.minLevel, 1, #Config.CrewLevels),
        actions = {},
    }

    if not value.police or not value.cooldown or not value.minLevel then
        return Panel.fail(('Policiers (0 à %d), délai (5 à %d min) ou level de crew invalide.'):format(LIMITS.police, LIMITS.cooldown))
    end

    for actionId in pairs(TYPES[typeId].actions) do
        local action, err = readAction(input.actions[actionId], actionId)

        if not action then
            return Panel.fail(err)
        end

        value.actions[actionId] = action
    end

    MySQL.query.await('INSERT INTO `lunatic_heist_settings` (`type`, `settings`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `settings` = VALUES(`settings`)', { typeId, json.encode(value) })
    load()
    Logs.add(src, 'heists.save', nil, { label = TYPES[typeId].label, operation = 'edit' })

    return { ok = true, silent = true }
end

Panel.actions['heists.addPoint'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local label = type(data.label) == 'string' and data.label:gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    local position = positionOf(src)

    if not POINT_KINDS[data.kind] then
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

    MySQL.insert.await('INSERT INTO `lunatic_heist_points` (`kind`, `label`, `x`, `y`, `z`, `h`) VALUES (?, ?, ?, ?, ?, ?)', { data.kind, label, position.x, position.y, position.z, position.h })
    load()
    Logs.add(src, 'heists.point', nil, { label = label, operation = 'add' })

    return { ok = true, silent = true }
end

Panel.actions['heists.movePoint'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findPoint(data.id)
    local position = positionOf(src)

    if not point or not position then
        return Panel.fail('Point introuvable.')
    end

    MySQL.update.await('UPDATE `lunatic_heist_points` SET `x` = ?, `y` = ?, `z` = ?, `h` = ? WHERE `id` = ?', { position.x, position.y, position.z, position.h, point.id })
    load()
    Logs.add(src, 'heists.point', nil, { label = point.label, operation = 'move' })

    return { ok = true, silent = true }
end

Panel.actions['heists.deletePoint'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findPoint(data.id)

    if not point then
        return Panel.fail('Point introuvable.')
    end

    MySQL.update.await('DELETE FROM `lunatic_heist_points` WHERE `id` = ?', { point.id })
    load()
    Logs.add(src, 'heists.point', nil, { label = point.label, operation = 'delete' })

    return { ok = true, silent = true }
end

Panel.actions['heists.tpPoint'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findPoint(data.id)

    if not point then
        return Panel.fail('Point introuvable.')
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(point.x, point.y, point.z))
    return { ok = true, silent = true }
end

-- Lieu braqué récemment : le rendre à nouveau disponible (porte du coffre refermée)
Panel.actions['heists.reset'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local found, done = pcall(function() return exports.lunatic_illegal:resetHeist(data.key) end)

    if not found or not done then
        return Panel.fail('Lieu introuvable (déjà disponible ?).')
    end

    Logs.add(src, 'heists.reset', nil, { label = tostring(data.label or data.key) })
    return { ok = true, silent = true }
end

-- Ajoute au recelleur les objets du butin qui n'y sont pas encore
Panel.actions['heists.seedFence'] = function(src, actor)
    if not guard(actor) then
        return denied()
    end

    local present = {}

    for _, entry in ipairs((GlobalState.lunaticFence or {}).items or {}) do
        present[entry.item] = true
    end

    local created = 0

    for _, entry in ipairs(FENCE_LOOT) do
        if not present[entry[1]] and ox:Items(entry[1]) then
            created = created + 1
            MySQL.insert.await('INSERT INTO `lunatic_fence_items` (`item`, `price`, `category`, `position`) VALUES (?, ?, ?, ?)', { entry[1], entry[2], 'Butin de braquage', 100 + created })
        end
    end

    if created > 0 and Fence and Fence.reload then
        Fence.reload()
    end

    Logs.add(src, 'heists.save', nil, { label = 'Recelleur', operation = ('%d objet(s) de butin ajouté(s)'):format(created) })
    return { ok = true, silent = true, created = created }
end

-- Vue staff : cibles détectées et points affichés en jeu (orange)
Panel.actions['heists.staffView'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    TriggerClientEvent('lunatic_illegal:staffHeists', src, data.enabled == true)
    return { ok = true, silent = true }
end

print("[lunatic_admin] Module Braquages chargé.")
