-- Illégal, étape 6 : marché noir de la tablette des crews (tuile Illégal, onglet Tablette).
-- Catalogue (objet, prix, level de crew minimum, stock du jour) et points de livraison gérés dans le panel.
-- Une commande est payée tout de suite en argent sale, puis prête après un délai à un point de livraison tiré au hasard ;
-- un membre du crew la récupère sur place avant qu'elle n'expire. Les points ne sont jamais diffusés à tous :
-- chaque crew ne reçoit que ceux de ses commandes (exports pour lunatic_illegal en bas de fichier).

local ox = exports.ox_inventory

local LIMITS = { items = 100, dropoffs = 30, price = 1000000, stock = 10000, level = #Config.CrewLevels, quantity = 100 }

local items, dropoffs = {}, {}
local ready = false

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer l'illégal.")
end

local whole = Util.whole

local function positionOf(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z - 0.98, h = GetEntityHeading(ped) }
end

local function itemLabel(name)
    local item = ox:Items(name)
    return item and item.label or name, item == nil
end

local function today()
    return os.date('%Y-%m-%d')
end

local function load()
    items, dropoffs = {}, {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_market_items` ORDER BY `position`, `id`') or {}) do
        items[#items + 1] = {
            id = tonumber(row.id), item = row.item, price = tonumber(row.price), minLevel = tonumber(row.min_level) or 1,
            stockMax = tonumber(row.stock_max) or 0, stock = tonumber(row.stock) or 0, stockDay = row.stock_day or '',
        }
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_market_dropoffs` ORDER BY `id`') or {}) do
        dropoffs[#dropoffs + 1] = { id = tonumber(row.id), label = row.label, x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h) }
    end
end

-- Stock du jour : remis au maximum au premier achat (ou affichage) d'une nouvelle journée
local function refreshStock(entry)
    local day = today()

    if entry.stockDay ~= day then
        entry.stock = entry.stockMax
        entry.stockDay = day
        MySQL.update.await('UPDATE `lunatic_market_items` SET `stock` = ?, `stock_day` = ? WHERE `id` = ?', { entry.stock, day, entry.id })
    end
end

local function findItem(id)
    for _, entry in ipairs(items) do
        if entry.id == tonumber(id) then
            return entry
        end
    end
end

local function findDropoff(id)
    for _, point in ipairs(dropoffs) do
        if point.id == tonumber(id) then
            return point
        end
    end
end

-- Commandes en retard : marquées expirées (la marchandise est perdue)
local function expireOrders()
    MySQL.update.await("UPDATE `lunatic_market_orders` SET `status` = 'expired' WHERE `status` = 'pending' AND `expires_at` < ?", { os.time() })
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_market_items` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `item` VARCHAR(60) NOT NULL,
            `price` INT NOT NULL DEFAULT 0,
            `min_level` INT NOT NULL DEFAULT 1,
            `stock_max` INT NOT NULL DEFAULT 10,
            `stock` INT NOT NULL DEFAULT 10,
            `stock_day` VARCHAR(10) NOT NULL DEFAULT '',
            `position` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_market_dropoffs` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `label` VARCHAR(60) NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `h` DOUBLE NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_market_orders` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `crew_id` INT NOT NULL,
            `buyer` VARCHAR(60) NOT NULL,
            `buyer_name` VARCHAR(80) NOT NULL DEFAULT '',
            `item` VARCHAR(60) NOT NULL,
            `count` INT NOT NULL,
            `total` INT NOT NULL,
            `dropoff_id` INT NOT NULL,
            `ready_at` BIGINT NOT NULL,
            `expires_at` BIGINT NOT NULL,
            `status` VARCHAR(12) NOT NULL DEFAULT 'pending',
            `notified` TINYINT NOT NULL DEFAULT 0,
            `collected_by` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_market_orders_crew` (`crew_id`, `status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Colonne ajoutée après la première version de la table (syntaxe MariaDB)
    pcall(function()
        MySQL.query.await('ALTER TABLE `lunatic_market_orders` ADD COLUMN IF NOT EXISTS `notified` TINYINT NOT NULL DEFAULT 0')
    end)

    load()
    expireOrders()
    ready = true
end)

-- Commandes qui viennent d'arriver : les membres connectés du crew sont prévenus, l'acheteur reçoit le point GPS
local function announceReady()
    local now = os.time()
    local rows = MySQL.query.await("SELECT * FROM `lunatic_market_orders` WHERE `status` = 'pending' AND `notified` = 0 AND `ready_at` <= ? AND `expires_at` >= ?", { now, now }) or {}

    for _, row in ipairs(rows) do
        MySQL.update.await('UPDATE `lunatic_market_orders` SET `notified` = 1 WHERE `id` = ?', { row.id })
        local point = findDropoff(row.dropoff_id)

        if point then
            local label = itemLabel(row.item)

            for _, target in ipairs(Crews.onlineSources(tonumber(row.crew_id))) do
                local xPlayer = ESX.GetPlayerFromId(target)

                TriggerClientEvent('lunatic_illegal:orderReady', target, {
                    id = tonumber(row.id), label = label, count = tonumber(row.count), buyer = xPlayer and xPlayer.identifier == row.buyer,
                    dropoff = { label = point.label, x = point.x, y = point.y, z = point.z }, expiresIn = tonumber(row.expires_at) - now,
                })
            end
        end
    end
end

CreateThread(function()
    local nextExpire = 0

    while true do
        Wait(15000)

        if ready then
            announceReady()

            if os.time() >= nextExpire then
                nextExpire = os.time() + 60
                expireOrders()
            end
        end
    end
end)

---------------------------------------------------------------------
-- Exports (tablette, lunatic_illegal). Le crew vient toujours d'ici, jamais du client.
---------------------------------------------------------------------

local function orderView(row)
    local point = findDropoff(row.dropoff_id)
    local now = os.time()
    local label = itemLabel(row.item)

    return {
        id = tonumber(row.id), item = row.item, label = label, count = tonumber(row.count), total = tonumber(row.total),
        buyer = row.buyer_name, readyIn = math.max(0, tonumber(row.ready_at) - now), expiresIn = math.max(0, tonumber(row.expires_at) - now),
        ready = now >= tonumber(row.ready_at),
        dropoff = point and { id = point.id, label = point.label, x = point.x, y = point.y, z = point.z } or nil,
    }
end

-- Commandes en attente du crew du joueur (avec le point de livraison)
local function crewOrders(crewId)
    local list = {}

    for _, row in ipairs(MySQL.query.await("SELECT * FROM `lunatic_market_orders` WHERE `crew_id` = ? AND `status` = 'pending' AND `expires_at` >= ? ORDER BY `ready_at`", { crewId, os.time() }) or {}) do
        list[#list + 1] = orderView(row)
    end

    return list
end

exports('marketCatalog', function(src)
    local crew = Crews.ofPlayer(src)

    if not crew then
        return { ok = false, error = "Vous ne faites partie d'aucun crew." }
    end

    local list = {}

    for _, entry in ipairs(items) do
        refreshStock(entry)
        local label, missing = itemLabel(entry.item)

        if not missing then
            list[#list + 1] = { id = entry.id, item = entry.item, label = label, price = entry.price, minLevel = entry.minLevel, stock = entry.stock, stockMax = entry.stockMax, locked = crew.level < entry.minLevel }
        end
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local account = xPlayer and xPlayer.getAccount(Config.MarketAccount)

    return {
        ok = true, items = list, level = crew.level, money = account and account.money or 0, orders = crewOrders(crew.id),
        maxPending = Config.MarketMaxPending, delay = Config.MarketDelay, expire = Config.MarketExpire, dropoffs = #dropoffs,
    }
end)

exports('marketOrders', function(src)
    local crew = Crews.ofPlayer(src)
    return crew and crewOrders(crew.id) or {}
end)

exports('marketBuy', function(src, itemId, quantity)
    local crew = Crews.ofPlayer(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not crew or not xPlayer then
        return { ok = false, error = "Vous ne faites partie d'aucun crew." }
    end

    local entry = findItem(itemId)
    quantity = whole(quantity, 1, LIMITS.quantity)

    if not entry or not ox:Items(entry.item) then
        return { ok = false, error = 'Article introuvable.' }
    end

    if not quantity then
        return { ok = false, error = ('Quantité : de 1 à %d.'):format(LIMITS.quantity) }
    end

    if crew.level < entry.minLevel then
        return { ok = false, error = ('Réservé aux crews level %d.'):format(entry.minLevel) }
    end

    if #dropoffs == 0 then
        return { ok = false, error = 'Aucun point de livraison : le marché est fermé.' }
    end

    refreshStock(entry)

    if entry.stock < quantity then
        return { ok = false, error = ('Stock du jour insuffisant (%d restant).'):format(entry.stock) }
    end

    local pending = MySQL.scalar.await("SELECT COUNT(*) FROM `lunatic_market_orders` WHERE `crew_id` = ? AND `status` = 'pending' AND `expires_at` >= ?", { crew.id, os.time() }) or 0

    if pending >= Config.MarketMaxPending then
        return { ok = false, error = ('Votre crew a déjà %d commandes en cours.'):format(pending) }
    end

    local total = entry.price * quantity
    local account = xPlayer.getAccount(Config.MarketAccount)

    if not account or account.money < total then
        return { ok = false, error = "Vous n'avez pas assez d'argent sale sur vous." }
    end

    xPlayer.removeAccountMoney(Config.MarketAccount, total, 'Marché noir')
    entry.stock = entry.stock - quantity
    MySQL.update.await('UPDATE `lunatic_market_items` SET `stock` = ? WHERE `id` = ?', { entry.stock, entry.id })

    local now = os.time()
    local ready = now + math.random(Config.MarketDelay[1], Config.MarketDelay[2])
    local point = dropoffs[math.random(#dropoffs)]

    MySQL.insert.await('INSERT INTO `lunatic_market_orders` (`crew_id`, `buyer`, `buyer_name`, `item`, `count`, `total`, `dropoff_id`, `ready_at`, `expires_at`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        crew.id, xPlayer.identifier, xPlayer.getName(), entry.item, quantity, total, point.id, ready, ready + Config.MarketExpire, now,
    })

    return { ok = true, label = itemLabel(entry.item), count = quantity, total = total, readyIn = ready - now }
end)

exports('marketCollect', function(src, orderId)
    local crew = Crews.ofPlayer(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not crew or not xPlayer then
        return { ok = false, error = "Vous ne faites partie d'aucun crew." }
    end

    local row = MySQL.single.await('SELECT * FROM `lunatic_market_orders` WHERE `id` = ?', { tonumber(orderId) or -1 })

    if not row or tonumber(row.crew_id) ~= crew.id or row.status ~= 'pending' then
        return { ok = false, error = 'Commande introuvable.' }
    end

    local now = os.time()

    if now < tonumber(row.ready_at) then
        return { ok = false, error = "La commande n'est pas encore arrivée." }
    end

    if now > tonumber(row.expires_at) then
        return { ok = false, error = 'Trop tard : la commande est perdue.' }
    end

    local point = findDropoff(row.dropoff_id)
    local ped = GetPlayerPed(src)

    if not point or not ped or ped == 0 or #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)) > Config.MarketPickupDistance + 2.0 then
        return { ok = false, error = 'Vous êtes trop loin du point de livraison.' }
    end

    if not ox:CanCarryItem(src, row.item, tonumber(row.count)) then
        return { ok = false, error = "Vous n'avez pas assez de place." }
    end

    -- La commande n'est remise qu'une fois (deux membres sur place en même temps)
    local changed = MySQL.update.await("UPDATE `lunatic_market_orders` SET `status` = 'collected', `collected_by` = ? WHERE `id` = ? AND `status` = 'pending'", { xPlayer.getName(), row.id })

    if not changed or changed < 1 then
        return { ok = false, error = 'Commande déjà récupérée.' }
    end

    ox:AddItem(src, row.item, tonumber(row.count))
    return { ok = true, label = itemLabel(row.item), count = tonumber(row.count), x = point.x, y = point.y }
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function guard(actor)
    return Ranks.hasPermission(actor, 'illegal.manage')
end

-- Catalogue de départ : pièces d'armes et ingrédients des drogues de départ
local SEED = {
    { 'gun_barrel', 2500, 1, 10 }, { 'gun_slide', 2000, 1, 10 }, { 'gun_spring', 300, 1, 30 }, { 'gun_stock', 1500, 3, 10 },
    { 'gunpowder', 150, 1, 60 }, { 'bullet_casing', 10, 1, 500 },
    { 'weed_leaf', 40, 1, 100 }, { 'coca_leaf', 80, 2, 80 }, { 'pseudoephedrine', 120, 2, 60 }, { 'chemicals', 300, 2, 30 },
    { 'plastic_bag', 5, 1, 300 }, { 'empty_vial', 15, 1, 100 },
}

Panel.actions['market.info'] = function(_, actor)
    if not guard(actor) then
        return denied()
    end

    local list = {}

    for _, entry in ipairs(items) do
        refreshStock(entry)
        local label, missing = itemLabel(entry.item)
        list[#list + 1] = { id = entry.id, item = entry.item, label = label, missing = missing, price = entry.price, minLevel = entry.minLevel, stock = entry.stock, stockMax = entry.stockMax }
    end

    local orders = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_market_orders` ORDER BY `id` DESC LIMIT 30') or {}) do
        local crew = Crews.basic(row.crew_id)
        orders[#orders + 1] = {
            id = tonumber(row.id), crew = crew and crew.label or '?', buyer = row.buyer_name, label = (itemLabel(row.item)), count = tonumber(row.count),
            total = tonumber(row.total), status = row.status, createdAt = tonumber(row.created_at), collectedBy = row.collected_by,
        }
    end

    return { ok = true, silent = true, items = list, dropoffs = dropoffs, orders = orders, maxLevel = LIMITS.level, account = Config.MarketAccount, delay = Config.MarketDelay, expire = Config.MarketExpire }
end

Panel.actions['market.seed'] = function(src, actor)
    if not guard(actor) then
        return denied()
    end

    local used = {}

    for _, entry in ipairs(items) do
        used[entry.item] = true
    end

    local created = 0

    for _, entry in ipairs(SEED) do
        if not used[entry[1]] and ox:Items(entry[1]) and #items + created < LIMITS.items then
            created = created + 1
            MySQL.insert.await('INSERT INTO `lunatic_market_items` (`item`, `price`, `min_level`, `stock_max`, `stock`, `stock_day`, `position`) VALUES (?, ?, ?, ?, ?, ?, ?)', {
                entry[1], entry[2], entry[3], entry[4], entry[4], today(), #items + created,
            })
        end
    end

    load()
    Logs.add(src, 'market.item', nil, { operation = ('catalogue de départ, %d article(s)'):format(created) })

    return { ok = true, silent = true, created = created }
end

Panel.actions['market.saveItem'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    if type(data.item) ~= 'string' or not ox:Items(data.item) then
        return Panel.fail(("L'objet « %s » n'existe pas dans ox_inventory."):format(tostring(data.item)))
    end

    local price = whole(data.price, 0, LIMITS.price)
    local minLevel = whole(data.minLevel, 1, LIMITS.level)
    local stockMax = whole(data.stockMax, 1, LIMITS.stock)

    if not price or not minLevel or not stockMax then
        return Panel.fail(('Prix (0-%d), level (1-%d) ou stock du jour (1-%d) invalide.'):format(LIMITS.price, LIMITS.level, LIMITS.stock))
    end

    if data.id then
        local entry = findItem(data.id)

        if not entry then
            return Panel.fail('Article introuvable.')
        end

        -- Stock du jour ramené au nouveau maximum s'il le dépasse
        MySQL.update.await('UPDATE `lunatic_market_items` SET `item` = ?, `price` = ?, `min_level` = ?, `stock_max` = ?, `stock` = LEAST(`stock`, ?) WHERE `id` = ?', {
            data.item, price, minLevel, stockMax, stockMax, entry.id,
        })
    else
        if #items >= LIMITS.items then
            return Panel.fail(('Maximum %d articles.'):format(LIMITS.items))
        end

        MySQL.insert.await('INSERT INTO `lunatic_market_items` (`item`, `price`, `min_level`, `stock_max`, `stock`, `stock_day`, `position`) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            data.item, price, minLevel, stockMax, stockMax, today(), #items + 1,
        })
    end

    load()
    Logs.add(src, 'market.item', nil, { item = data.item, price = price, operation = data.id and 'edit' or 'add' })

    return { ok = true, silent = true }
end

Panel.actions['market.deleteItem'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local entry = findItem(data.id)

    if not entry then
        return Panel.fail('Article introuvable.')
    end

    MySQL.update.await('DELETE FROM `lunatic_market_items` WHERE `id` = ?', { entry.id })
    load()
    Logs.add(src, 'market.item', nil, { item = entry.item, operation = 'delete' })

    return { ok = true, silent = true }
end

Panel.actions['market.addDropoff'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local label = type(data.label) == 'string' and data.label:gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    local position = positionOf(src)

    if #label < 2 or #label > 60 then
        return Panel.fail('Le nom doit faire entre 2 et 60 caractères.')
    end

    if not position then
        return Panel.fail('Position introuvable.')
    end

    if #dropoffs >= LIMITS.dropoffs then
        return Panel.fail(('Maximum %d points de livraison.'):format(LIMITS.dropoffs))
    end

    MySQL.insert.await('INSERT INTO `lunatic_market_dropoffs` (`label`, `x`, `y`, `z`, `h`) VALUES (?, ?, ?, ?, ?)', { label, position.x, position.y, position.z, position.h })
    load()
    Logs.add(src, 'market.dropoff', nil, { label = label, operation = 'add' })

    return { ok = true, silent = true }
end

Panel.actions['market.moveDropoff'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findDropoff(data.id)
    local position = positionOf(src)

    if not point or not position then
        return Panel.fail('Point introuvable.')
    end

    MySQL.update.await('UPDATE `lunatic_market_dropoffs` SET `x` = ?, `y` = ?, `z` = ?, `h` = ? WHERE `id` = ?', { position.x, position.y, position.z, position.h, point.id })
    load()
    Logs.add(src, 'market.dropoff', nil, { label = point.label, operation = 'move' })

    return { ok = true, silent = true }
end

Panel.actions['market.deleteDropoff'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findDropoff(data.id)

    if not point then
        return Panel.fail('Point introuvable.')
    end

    local waiting = MySQL.scalar.await("SELECT COUNT(*) FROM `lunatic_market_orders` WHERE `dropoff_id` = ? AND `status` = 'pending'", { point.id }) or 0

    if waiting > 0 then
        return Panel.fail(('%d commande(s) attendent à ce point : déplacez-le plutôt que de le supprimer.'):format(waiting))
    end

    MySQL.update.await('DELETE FROM `lunatic_market_dropoffs` WHERE `id` = ?', { point.id })
    load()
    Logs.add(src, 'market.dropoff', nil, { label = point.label, operation = 'delete' })

    return { ok = true, silent = true }
end

Panel.actions['market.tpDropoff'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findDropoff(data.id)

    if not point then
        return Panel.fail('Point introuvable.')
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(point.x, point.y, point.z + 1.0))
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Marché noir chargé.')
