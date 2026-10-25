-- Tuile Boutique (partie 2) : catalogues des packs, véhicules et armes vendus contre des crédits.
-- Catégories (nom, image, type) et produits (nom, image, prix, contenu) en base ; lus par la boutique des joueurs
-- (partie 3) avec StoreCatalog.list(kind).

StoreCatalog = {}

local KINDS = { packs = true, vehicles = true, weapons = true }
local VEHICLE_TYPES = { car = true, bike = true, boat = true, heli = true, plane = true }
local LIMITS = { label = 60, url = 255, price = 10000000, money = 100000000, items = 20, vehicles = 5, categories = 30, products = 200 }

-- Catégories créées au premier démarrage (comme la boutique de Vision)
local DEFAULT_CATEGORIES = {
    { 'packs', 'Starter' }, { 'packs', 'Véhicule' }, { 'packs', 'Nourriture' }, { 'packs', 'Illégal' }, { 'packs', 'VIP' },
    { 'vehicles', 'Sportive', 'car' }, { 'vehicles', 'SUV', 'car' }, { 'vehicles', 'Berline', 'car' }, { 'vehicles', 'Moto', 'bike' }, { 'vehicles', 'Utilitaire', 'car' },
    { 'weapons', 'Armes de poing' }, { 'weapons', 'Armes automatiques' }, { 'weapons', 'Fusils à pompe' }, { 'weapons', 'Armes lourdes' }, { 'weapons', 'Armes blanches' },
}

local ox = exports.ox_inventory

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer la boutique.")
end

local cleanText = Util.cleanTextOrEmpty

local function cleanUrl(value)
    local url = cleanText(value, 0, LIMITS.url)

    if not url or url == '' then
        return url
    end

    return url:match('^https://[%w%-%.]+%.%a+/.*') and url or nil
end

local whole = Util.whole

local function decode(value)
    local ok, data = pcall(json.decode, value or '{}')
    return ok and type(data) == 'table' and data or {}
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_store_categories` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `kind` VARCHAR(10) NOT NULL,
            `label` VARCHAR(60) NOT NULL,
            `image` VARCHAR(255) NOT NULL DEFAULT '',
            `type` VARCHAR(10) NOT NULL DEFAULT '',
            `position` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_store_categories_kind` (`kind`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_store_products` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `category_id` INT NOT NULL,
            `label` VARCHAR(60) NOT NULL,
            `image` VARCHAR(255) NOT NULL DEFAULT '',
            `price` INT NOT NULL DEFAULT 0,
            `data` TEXT NULL,
            `active` TINYINT NOT NULL DEFAULT 1,
            `position` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_store_products_category` (`category_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    if (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `lunatic_store_categories`')) or 0) == 0 then
        for index, entry in ipairs(DEFAULT_CATEGORIES) do
            MySQL.insert.await('INSERT INTO `lunatic_store_categories` (`kind`, `label`, `type`, `position`) VALUES (?, ?, ?, ?)', { entry[1], entry[2], entry[3] or '', index })
        end
    end
end)

---@param kind string packs | vehicles | weapons
---@param activeOnly boolean|nil seulement les produits en vente (boutique des joueurs)
---@return table[] catégories avec leurs produits
function StoreCatalog.list(kind, activeOnly)
    local categories, byId = {}, {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_store_categories` WHERE `kind` = ? ORDER BY `position`, `id`', { kind }) or {}) do
        local category = { id = tonumber(row.id), label = row.label, image = row.image, type = row.type, products = {} }
        categories[#categories + 1] = category
        byId[category.id] = category
    end

    for _, row in ipairs(MySQL.query.await('SELECT p.* FROM `lunatic_store_products` p JOIN `lunatic_store_categories` c ON c.`id` = p.`category_id` WHERE c.`kind` = ? ORDER BY p.`position`, p.`id`', { kind }) or {}) do
        local category = byId[tonumber(row.category_id)]
        local active = tonumber(row.active) == 1 or row.active == true

        if category and (active or not activeOnly) then
            category.products[#category.products + 1] = {
                id = tonumber(row.id), category = category.id, label = row.label, image = row.image, price = tonumber(row.price),
                active = active, data = decode(row.data),
            }
        end
    end

    return categories
end

---@return table|nil produit (avec son type de catalogue)
function StoreCatalog.product(id)
    local row = MySQL.single.await('SELECT p.*, c.`kind` FROM `lunatic_store_products` p JOIN `lunatic_store_categories` c ON c.`id` = p.`category_id` WHERE p.`id` = ?', { tonumber(id) or -1 })

    if not row then
        return nil
    end

    return { id = tonumber(row.id), kind = row.kind, label = row.label, image = row.image, price = tonumber(row.price), active = tonumber(row.active) == 1 or row.active == true, data = decode(row.data) }
end

-- Boutique des joueurs (lunatic_store) : produits en vente seulement
exports('getStoreCatalog', function(kind)
    return KINDS[kind] and StoreCatalog.list(kind, true) or {}
end)

exports('getStoreProduct', function(id)
    local product = StoreCatalog.product(id)

    if product then
        local category = MySQL.single.await('SELECT `type` FROM `lunatic_store_categories` c JOIN `lunatic_store_products` p ON p.`category_id` = c.`id` WHERE p.`id` = ?', { product.id })
        product.categoryType = category and category.type or ''
    end

    return product
end)

---------------------------------------------------------------------
-- Contenu des produits
---------------------------------------------------------------------

local function readModel(value)
    local model = type(value) == 'string' and value:lower():match('^[%w_]+$')
    return model and #model <= 30 and model or nil
end

---@return table|nil data, string|nil error
local function readData(kind, data)
    data = type(data) == 'table' and data or {}

    if kind == 'vehicles' then
        local model = readModel(data.model)
        return model and { model = model } or nil, 'Modèle du véhicule invalide (ex. sultan).'
    end

    if kind == 'weapons' then
        local item = type(data.item) == 'string' and data.item:upper() or nil
        local ammo = whole(data.ammo or 0, 0, 1000)

        if not item or not item:match('^WEAPON_') or not ox:Items(item) then
            return nil, "Arme inconnue d'ox_inventory (ex. WEAPON_PISTOL)."
        end

        if not ammo then
            return nil, 'Munitions : de 0 à 1000.'
        end

        return { item = item, ammo = ammo }
    end

    -- Pack : argent, objets, véhicules
    local cash, bank = whole(data.cash or 0, 0, LIMITS.money), whole(data.bank or 0, 0, LIMITS.money)

    if not cash or not bank then
        return nil, 'Argent du pack : un nombre entier positif.'
    end

    local items, vehicles = {}, {}

    if type(data.items) == 'table' and #data.items > LIMITS.items or type(data.vehicles) == 'table' and #data.vehicles > LIMITS.vehicles then
        return nil, ('Pack : %d objets et %d véhicules au maximum.'):format(LIMITS.items, LIMITS.vehicles)
    end

    for _, entry in ipairs(type(data.items) == 'table' and data.items or {}) do
        local count = whole(entry.count, 1, 10000)

        if type(entry.item) ~= 'string' or not ox:Items(entry.item) then
            return nil, ('Objet inconnu : %s.'):format(tostring(entry.item))
        end

        if not count then
            return nil, ('Quantité de %s : de 1 à 10000.'):format(entry.item)
        end

        items[#items + 1] = { item = entry.item, count = count }
    end

    for _, entry in ipairs(type(data.vehicles) == 'table' and data.vehicles or {}) do
        local model = readModel(entry.model)
        local label = cleanText(entry.label, 0, 40)

        if not model or not label then
            return nil, 'Véhicule du pack : modèle invalide.'
        end

        vehicles[#vehicles + 1] = { model = model, label = label ~= '' and label or model }
    end

    if cash == 0 and bank == 0 and #items == 0 and #vehicles == 0 then
        return nil, 'Le pack est vide.'
    end

    return { cash = cash, bank = bank, items = items, vehicles = vehicles }
end

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function allowed(actor)
    return Ranks.hasPermission(actor, 'shop.manage')
end

Panel.actions['storeCatalog.list'] = function(_, actor, data)
    if not allowed(actor) then
        return denied()
    end

    if not KINDS[data.kind] then
        return Panel.fail('Catalogue inconnu.')
    end

    return { ok = true, silent = true, categories = StoreCatalog.list(data.kind, false) }
end

Panel.actions['storeCatalog.saveCategory'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local id = tonumber(data.id)
    local row = id and MySQL.single.await('SELECT * FROM `lunatic_store_categories` WHERE `id` = ?', { id })
    local kind = row and row.kind or data.kind

    if id and not row or not KINDS[kind] then
        return Panel.fail('Catégorie introuvable.')
    end

    local label = cleanText(data.label, 2, 40)
    local image = cleanUrl(data.image)
    local vehicleType = kind == 'vehicles' and (VEHICLE_TYPES[data.type] and data.type or nil) or ''

    if not label then
        return Panel.fail('Nom de la catégorie : de 2 à 40 caractères.')
    end

    if not image then
        return Panel.fail('Image : un lien https.')
    end

    if not vehicleType then
        return Panel.fail('Type de véhicule invalide.')
    end

    if row then
        MySQL.update.await('UPDATE `lunatic_store_categories` SET `label` = ?, `image` = ?, `type` = ? WHERE `id` = ?', { label, image, vehicleType, id })
    else
        if (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `lunatic_store_categories` WHERE `kind` = ?', { kind })) or 0) >= LIMITS.categories then
            return Panel.fail(('%d catégories au maximum.'):format(LIMITS.categories))
        end

        id = MySQL.insert.await('INSERT INTO `lunatic_store_categories` (`kind`, `label`, `image`, `type`, `position`) VALUES (?, ?, ?, ?, ?)', {
            kind, label, image, vehicleType, (tonumber(MySQL.scalar.await('SELECT COALESCE(MAX(`position`), 0) FROM `lunatic_store_categories` WHERE `kind` = ?', { kind })) or 0) + 1,
        })
    end

    Logs.add(src, row and 'storeCatalog.updateCategory' or 'storeCatalog.createCategory', label, { id = id, kind = kind })
    return { ok = true, silent = true, id = id }
end

Panel.actions['storeCatalog.deleteCategory'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local row = MySQL.single.await('SELECT * FROM `lunatic_store_categories` WHERE `id` = ?', { tonumber(data.id) or -1 })

    if not row then
        return Panel.fail('Catégorie introuvable.')
    end

    MySQL.update.await('DELETE FROM `lunatic_store_products` WHERE `category_id` = ?', { row.id })
    MySQL.update.await('DELETE FROM `lunatic_store_categories` WHERE `id` = ?', { row.id })
    Logs.add(src, 'storeCatalog.deleteCategory', row.label, { id = row.id, kind = row.kind })
    return { ok = true, silent = true }
end

Panel.actions['storeCatalog.saveProduct'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local id = tonumber(data.id)
    local existing = id and StoreCatalog.product(id)
    local category = MySQL.single.await('SELECT * FROM `lunatic_store_categories` WHERE `id` = ?', { tonumber(data.category) or -1 })

    if (id and not existing) or not category then
        return Panel.fail('Produit ou catégorie introuvable.')
    end

    local label = cleanText(data.label, 2, LIMITS.label)
    local image = cleanUrl(data.image)
    local price = whole(data.price, 0, LIMITS.price)

    if not label then
        return Panel.fail(('Nom du produit : de 2 à %d caractères.'):format(LIMITS.label))
    end

    if not image then
        return Panel.fail('Image : un lien https.')
    end

    if not price then
        return Panel.fail('Prix : un nombre entier de crédits.')
    end

    local content, err = readData(category.kind, data.data)

    if not content then
        return Panel.fail(err)
    end

    if existing then
        MySQL.update.await('UPDATE `lunatic_store_products` SET `category_id` = ?, `label` = ?, `image` = ?, `price` = ?, `data` = ?, `active` = ? WHERE `id` = ?', {
            category.id, label, image, price, json.encode(content), data.active == false and 0 or 1, id,
        })
    else
        if (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `lunatic_store_products`')) or 0) >= LIMITS.products * 3 then
            return Panel.fail('Trop de produits dans la boutique.')
        end

        id = MySQL.insert.await('INSERT INTO `lunatic_store_products` (`category_id`, `label`, `image`, `price`, `data`, `active`, `position`) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            category.id, label, image, price, json.encode(content), data.active == false and 0 or 1,
            (tonumber(MySQL.scalar.await('SELECT COALESCE(MAX(`position`), 0) FROM `lunatic_store_products` WHERE `category_id` = ?', { category.id })) or 0) + 1,
        })
    end

    Logs.add(src, existing and 'storeCatalog.updateProduct' or 'storeCatalog.createProduct', label, { id = id, kind = category.kind, price = price })
    return { ok = true, silent = true, id = id }
end

Panel.actions['storeCatalog.deleteProduct'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local product = StoreCatalog.product(data.id)

    if not product then
        return Panel.fail('Produit introuvable.')
    end

    MySQL.update.await('DELETE FROM `lunatic_store_products` WHERE `id` = ?', { product.id })
    Logs.add(src, 'storeCatalog.deleteProduct', product.label, { id = product.id, kind = product.kind })
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Catalogues de la boutique chargé.')
