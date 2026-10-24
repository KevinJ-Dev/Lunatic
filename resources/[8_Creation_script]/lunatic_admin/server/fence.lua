-- Illégal, étape 2 : recelleur (tuile Illégal, onglet Recelleur).
-- Catalogue des objets rachetés (objet, prix, catégorie) et emplacements des PNJ recelleurs.
-- Diffusé dans GlobalState.lunaticFence ; la revente en jeu est dans lunatic_illegal.

local ox = exports.ox_inventory

local items = {}
local locations = {}

-- Accès pour les autres modules (braquages : ajout du butin au catalogue)
Fence = {}

local function publish()
    GlobalState.lunaticFence = { items = items, locations = locations }
end

local function load()
    items, locations = {}, {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_fence_items` ORDER BY `category`, `position`, `id`') or {}) do
        items[#items + 1] = { id = tonumber(row.id), item = row.item, price = tonumber(row.price), category = row.category }
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_fence_locations` ORDER BY `id`') or {}) do
        locations[#locations + 1] = {
            id = tonumber(row.id), x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h), ped = row.ped,
            radius = tonumber(row.radius) or Config.FenceDistance or 2.0, showBlip = tonumber(row.show_blip) == 1,
        }
    end

    publish()
end

function Fence.reload()
    load()
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_fence_items` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `item` VARCHAR(60) NOT NULL,
            `price` INT NOT NULL DEFAULT 0,
            `category` VARCHAR(40) NOT NULL DEFAULT 'Objets volés',
            `position` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_fence_locations` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `h` DOUBLE NOT NULL DEFAULT 0,
            `ped` VARCHAR(40) NOT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Interactions : rayon du [E] et blip (caché par défaut : le recelleur est discret)
    MySQL.query.await([[
        ALTER TABLE `lunatic_fence_locations`
            ADD COLUMN IF NOT EXISTS `radius` DOUBLE NOT NULL DEFAULT 2.0,
            ADD COLUMN IF NOT EXISTS `show_blip` TINYINT NOT NULL DEFAULT 0
    ]])

    load()
end)

---------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer l'illégal.")
end

local function allowed(actor)
    return Ranks.hasPermission(actor, 'illegal.manage')
end

local function cleanText(value, min, max)
    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length >= min and length <= max and text or nil
end

local function positionOf(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z - 0.98, h = GetEntityHeading(ped) } -- PNJ posé au sol
end

-- Le serveur ne connaît pas les modèles : le jeu du staff vérifie que c'est bien un PNJ (aussi pour les magasins)
---@return string|nil model, table|nil error
function Panel.checkPed(src, model)
    model = type(model) == 'string' and model:lower():gsub('%s', '') or ''

    if not model:match('^[%w_]+$') or #model > 40 then
        return nil, Panel.fail('Nom de modèle de PNJ invalide.')
    end

    local ok, valid = pcall(lib.callback.await, 'lunatic_admin:pedModel', src, model)

    if not ok then
        return nil, Panel.fail('Vérification du modèle impossible (êtes-vous en jeu ?).')
    end

    if not valid then
        return nil, Panel.fail(('Le modèle de PNJ « %s » n\'existe pas.'):format(model))
    end

    return model
end

local checkPed = Panel.checkPed

-- Emplacements : onglet Recelleur ou tuile Interactions
local function canPlace(actor)
    return allowed(actor) or Ranks.hasPermission(actor, 'interactions.manage')
end

local function locationById(id)
    for _, location in ipairs(locations) do
        if location.id == tonumber(id) then
            return location
        end
    end
end

---------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------

Panel.actions['fence.info'] = function(_, actor)
    if not allowed(actor) then
        return denied()
    end

    local list, categories, seen = {}, {}, {}

    for _, entry in ipairs(items) do
        local item = ox:Items(entry.item)
        list[#list + 1] = { id = entry.id, item = entry.item, price = entry.price, category = entry.category, label = item and item.label or entry.item, missing = item == nil }

        if not seen[entry.category] then
            seen[entry.category] = true
            categories[#categories + 1] = entry.category
        end
    end

    return { ok = true, silent = true, items = list, categories = categories, locations = locations, defaultPed = Config.FenceDefaultPed }
end

Panel.actions['fence.saveItem'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    if type(data.item) ~= 'string' or not ox:Items(data.item) then
        return Panel.fail("Cet objet n'existe pas dans ox_inventory.")
    end

    local price = tonumber(data.price)
    local category = cleanText(data.category, 2, 40)

    if not price or price ~= math.floor(price) or price < 0 or price > 10000000 then
        return Panel.fail('Prix invalide (nombre entier de 0 à 10 000 000).')
    end

    if not category then
        return Panel.fail('La catégorie doit faire entre 2 et 40 caractères.')
    end

    local id = tonumber(data.id)

    if id then
        local changed = MySQL.update.await('UPDATE `lunatic_fence_items` SET `item` = ?, `price` = ?, `category` = ? WHERE `id` = ?', { data.item, price, category, id })

        if (tonumber(changed) or 0) == 0 then
            return Panel.fail('Objet introuvable.')
        end
    else
        for _, entry in ipairs(items) do
            if entry.item == data.item then
                return Panel.fail('Cet objet est déjà dans le catalogue du recelleur.')
            end
        end

        MySQL.insert.await('INSERT INTO `lunatic_fence_items` (`item`, `price`, `category`, `position`) VALUES (?, ?, ?, ?)', { data.item, price, category, #items })
    end

    load()
    Logs.add(src, 'fence.item', nil, { item = data.item, price = price, category = category, operation = id and 'edit' or 'add' })

    return { ok = true, silent = true }
end

Panel.actions['fence.deleteItem'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local changed = MySQL.update.await('DELETE FROM `lunatic_fence_items` WHERE `id` = ?', { tonumber(data.id) or -1 })

    if (tonumber(changed) or 0) == 0 then
        return Panel.fail('Objet introuvable.')
    end

    load()
    return { ok = true, silent = true }
end

Panel.actions['fence.addLocation'] = function(src, actor, data)
    if not canPlace(actor) then
        return denied()
    end

    local model, err = checkPed(src, data.ped or Config.FenceDefaultPed)

    if not model then
        return err
    end

    local position = positionOf(src)

    if not position then
        return Panel.fail("Votre personnage n'est pas encore apparu.")
    end

    MySQL.insert.await('INSERT INTO `lunatic_fence_locations` (`x`, `y`, `z`, `h`, `ped`) VALUES (?, ?, ?, ?, ?)', { position.x, position.y, position.z, position.h, model })
    load()
    Logs.add(src, 'fence.location', nil, { operation = 'add', ped = model })

    return { ok = true, silent = true }
end

Panel.actions['fence.moveLocation'] = function(src, actor, data)
    if not canPlace(actor) then
        return denied()
    end

    local location = locationById(data.id)
    local position = positionOf(src)

    if not location or not position then
        return Panel.fail('Emplacement introuvable.')
    end

    MySQL.update.await('UPDATE `lunatic_fence_locations` SET `x` = ?, `y` = ?, `z` = ?, `h` = ? WHERE `id` = ?', { position.x, position.y, position.z, position.h, location.id })
    load()
    Logs.add(src, 'fence.location', nil, { operation = 'move' })

    return { ok = true, silent = true }
end

Panel.actions['fence.setPed'] = function(src, actor, data)
    if not canPlace(actor) then
        return denied()
    end

    local location = locationById(data.id)

    if not location then
        return Panel.fail('Emplacement introuvable.')
    end

    local model, err = checkPed(src, data.ped)

    if not model then
        return err
    end

    MySQL.update.await('UPDATE `lunatic_fence_locations` SET `ped` = ? WHERE `id` = ?', { model, location.id })
    load()

    return { ok = true, silent = true }
end

Panel.actions['fence.deleteLocation'] = function(src, actor, data)
    if not canPlace(actor) then
        return denied()
    end

    MySQL.update.await('DELETE FROM `lunatic_fence_locations` WHERE `id` = ?', { tonumber(data.id) or -1 })
    load()
    Logs.add(src, 'fence.location', nil, { operation = 'delete' })

    return { ok = true, silent = true }
end

Panel.actions['fence.tpLocation'] = function(src, actor, data)
    if not canPlace(actor) then
        return denied()
    end

    local location = locationById(data.id)

    if not location then
        return Panel.fail('Emplacement introuvable.')
    end

    -- À côté du PNJ, pas dessus
    local heading = math.rad(location.h or 0.0)
    TriggerClientEvent('lunatic_admin:teleport', src, vector3(location.x - math.sin(heading) * 1.5, location.y + math.cos(heading) * 1.5, location.z + 1.0))
    return { ok = true, silent = true }
end

-- Réglages d'interaction : rayon du [E], blip affiché (le modèle se change par fence.setPed)
Panel.actions['fence.locationSettings'] = function(src, actor, data)
    if not canPlace(actor) then
        return denied()
    end

    local location = locationById(data.id)
    local radius = tonumber(data.radius)

    if not location then
        return Panel.fail('Emplacement introuvable.')
    end

    if not radius or radius < Config.InteractionRadius.min or radius > Config.InteractionRadius.max then
        return Panel.fail(('Rayon : de %.1f à %.1f m.'):format(Config.InteractionRadius.min, Config.InteractionRadius.max))
    end

    MySQL.update.await('UPDATE `lunatic_fence_locations` SET `radius` = ?, `show_blip` = ? WHERE `id` = ?', { math.floor(radius * 10 + 0.5) / 10, data.showBlip == true and 1 or 0, location.id })
    load()

    return { ok = true, silent = true }
end

function Fence.locations()
    return locations
end

print('[lunatic_admin] Module Recelleur chargé.')
