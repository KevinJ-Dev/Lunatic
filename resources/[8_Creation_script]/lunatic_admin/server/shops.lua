-- Lot C1 : magasins automatiques (tuile Catalogues) : LTD, Ammunation, Vangelico, grossistes…
-- Chaque magasin : catégorie, label, clé (slug), blip, image d'en-tête, jobs autorisés, articles, emplacements.
-- Diffusés dans GlobalState.lunaticShops et à lunatic_business (événement serveur lunatic_admin:shopsChanged),
-- qui les enregistre dans ox_inventory et affiche blips et marqueurs.

Shops = {}

local CATEGORIES = {}

for _, entry in ipairs(Config.ShopCategories) do
    CATEGORIES[entry.id] = entry
end

local LIMITS = { items = 200, locations = 50, price = 10000000 }

---@type table<number, table> magasins par id
local shops = {}
local licenses = {}

local ox = exports.ox_inventory

local function sortedLocations(shop)
    table.sort(shop.locations, function(a, b) return a.id < b.id end)
end

local function publish()
    local list = {}

    for _, shop in pairs(shops) do
        sortedLocations(shop)
        list[#list + 1] = shop
    end

    table.sort(list, function(a, b) return a.id < b.id end)
    GlobalState.lunaticShops = list
    TriggerEvent('lunatic_admin:shopsChanged', list)
end

AddEventHandler('lunatic_admin:shopsRequest', publish)

local function load()
    shops = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_shops`') or {}) do
        local ok, jobs = pcall(json.decode, row.jobs or '[]')
        local category = CATEGORIES[row.category]

        shops[tonumber(row.id)] = {
            id = tonumber(row.id), category = row.category, kind = category and category.kind or 'items', slug = row.slug, label = row.label,
            blip = { sprite = tonumber(row.blip_sprite), color = tonumber(row.blip_color), scale = tonumber(row.blip_scale), label = row.blip_label },
            header = row.header or '', jobs = ok and jobs or {}, items = {}, locations = {}, vehicles = {}, defaultPrice = tonumber(row.default_price) or 0,
        }
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_shop_items` ORDER BY `position`, `id`') or {}) do
        local shop = shops[tonumber(row.shop_id)]

        if shop then
            shop.items[#shop.items + 1] = { item = row.item, price = tonumber(row.price), license = row.license ~= '' and row.license or nil }
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_shop_locations` ORDER BY `id`') or {}) do
        local shop = shops[tonumber(row.shop_id)]

        if shop then
            shop.locations[#shop.locations + 1] = {
                id = tonumber(row.id), x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h),
                -- Location : sortie des véhicules (sinon devant l'emplacement)
                spawn = row.sx and { x = tonumber(row.sx), y = tonumber(row.sy), z = tonumber(row.sz), h = tonumber(row.sh) } or nil,
            }
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_shop_vehicles` ORDER BY `position`, `id`') or {}) do
        local shop = shops[tonumber(row.shop_id)]

        if shop then
            shop.vehicles[#shop.vehicles + 1] = {
                id = tonumber(row.id), model = row.model, label = row.label, type = row.type, price = tonumber(row.price), duration = tonumber(row.duration),
                category = row.category or '', image = row.image or '',
            }
        end
    end

    licenses = {}

    for _, row in ipairs(MySQL.query.await('SELECT `type`, `label` FROM `licenses`') or {}) do
        licenses[row.type] = Config.LicenseLabels[row.type] or row.label
    end

    publish()
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_shops` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `category` VARCHAR(24) NOT NULL,
            `slug` VARCHAR(30) NOT NULL,
            `label` VARCHAR(60) NOT NULL,
            `blip_sprite` INT NOT NULL DEFAULT 52,
            `blip_color` INT NOT NULL DEFAULT 2,
            `blip_scale` DOUBLE NOT NULL DEFAULT 0.8,
            `blip_label` VARCHAR(60) NOT NULL DEFAULT '',
            `header` VARCHAR(255) NOT NULL DEFAULT '',
            `jobs` LONGTEXT NULL DEFAULT NULL,
            `created_by` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_lunatic_shops_slug` (`slug`),
            KEY `idx_lunatic_shops_category` (`category`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_shop_items` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL,
            `item` VARCHAR(60) NOT NULL,
            `price` INT NOT NULL DEFAULT 0,
            `license` VARCHAR(60) NOT NULL DEFAULT '', -- vide = aucun permis
            `position` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_shop_items_shop` (`shop_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_shop_locations` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `h` DOUBLE NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_shop_locations_shop` (`shop_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Lot C3 : véhicules des agences de location et sortie des véhicules par emplacement
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_shop_vehicles` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `shop_id` INT NOT NULL,
            `model` VARCHAR(32) NOT NULL,
            `label` VARCHAR(60) NOT NULL,
            `type` VARCHAR(16) NOT NULL DEFAULT 'automobile',
            `price` INT NOT NULL DEFAULT 0,
            `duration` INT NOT NULL DEFAULT 30,
            `position` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_shop_vehicles_shop` (`shop_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Catalogues lot 1 : prix par défaut d'un magasin, catégorie et image des véhicules de location
    MySQL.query.await('ALTER TABLE `lunatic_shops` ADD COLUMN IF NOT EXISTS `default_price` INT NOT NULL DEFAULT 0')
    MySQL.query.await([[
        ALTER TABLE `lunatic_shop_vehicles`
            ADD COLUMN IF NOT EXISTS `category` VARCHAR(40) NOT NULL DEFAULT '',
            ADD COLUMN IF NOT EXISTS `image` VARCHAR(255) NOT NULL DEFAULT ''
    ]])

    MySQL.query.await([[
        ALTER TABLE `lunatic_shop_locations`
            ADD COLUMN IF NOT EXISTS `sx` DOUBLE NULL DEFAULT NULL,
            ADD COLUMN IF NOT EXISTS `sy` DOUBLE NULL DEFAULT NULL,
            ADD COLUMN IF NOT EXISTS `sz` DOUBLE NULL DEFAULT NULL,
            ADD COLUMN IF NOT EXISTS `sh` DOUBLE NULL DEFAULT NULL
    ]])

    load()
end)

---------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les catalogues.")
end

local function cleanText(value, min, max)
    if value == nil then
        value = ''
    end

    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length >= min and length <= max and text or nil
end

local function number(value, min, max, integer)
    local n = tonumber(value)

    if not n or n < min or n > max or (integer and n ~= math.floor(n)) then
        return nil
    end

    return n
end

local function shopFor(actor, id)
    if not Ranks.hasPermission(actor, 'catalogs.manage') then
        return nil, denied()
    end

    local shop = shops[tonumber(id) or -1]

    if not shop then
        return nil, Panel.fail('Magasin introuvable.')
    end

    return shop
end

local function positionOf(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z - 0.98, h = GetEntityHeading(ped) }
end

---------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------

Panel.actions['shops.categories'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'catalogs.manage') then
        return denied()
    end

    local counts = {}

    for _, shop in pairs(shops) do
        counts[shop.category] = (counts[shop.category] or 0) + 1
    end

    local list = {}

    for _, entry in ipairs(Config.ShopCategories) do
        list[#list + 1] = { id = entry.id, label = entry.label, kind = entry.kind, ready = entry.kind == 'items' or entry.kind == 'rental' or entry.kind == 'buyback', count = counts[entry.id] or 0 }
    end

    return { ok = true, silent = true, categories = list }
end

Panel.actions['shops.list'] = function(_, actor, data)
    if not Ranks.hasPermission(actor, 'catalogs.manage') then
        return denied()
    end

    local list = {}

    for _, shop in pairs(shops) do
        -- data.all : tous les magasins (recherche globale du panel)
        if data.all == true or shop.category == data.category then
            list[#list + 1] = { id = shop.id, category = shop.category, label = shop.label, slug = shop.slug, items = #shop.items, locations = #shop.locations, vehicles = #shop.vehicles }
        end
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return { ok = true, silent = true, shops = list }
end

Panel.actions['shops.info'] = function(_, actor, data)
    local shop, err = shopFor(actor, data.id)

    if not shop then
        return err
    end

    local items = {}

    for _, entry in ipairs(shop.items) do
        local item = ox:Items(entry.item)
        items[#items + 1] = { item = entry.item, price = entry.price, license = entry.license, label = item and item.label or entry.item, missing = item == nil }
    end

    local licenseList, jobList = {}, {}

    for type, label in pairs(licenses) do
        licenseList[#licenseList + 1] = { type = type, label = label }
    end

    for name, job in pairs(ESX.GetJobs()) do
        if name ~= 'unemployed' then
            jobList[#jobList + 1] = { name = name, label = job.label }
        end
    end

    table.sort(licenseList, function(a, b) return a.label < b.label end)
    table.sort(jobList, function(a, b) return a.label < b.label end)

    return { ok = true, silent = true, shop = {
        id = shop.id, category = shop.category, slug = shop.slug, label = shop.label, blip = shop.blip, header = shop.header,
        jobs = shop.jobs, items = items, locations = shop.locations, vehicles = shop.vehicles, kind = shop.kind, defaultPrice = shop.defaultPrice,
    }, licenses = licenseList, jobs = jobList }
end

---------------------------------------------------------------------
-- Création, enregistrement, suppression
---------------------------------------------------------------------

Panel.actions['shops.create'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'catalogs.manage') then
        return denied()
    end

    local category = CATEGORIES[data.category]

    if not category then
        return Panel.fail('Catégorie inconnue.')
    end

    local label = cleanText(data.label, 2, 60)
    local slug = type(data.slug) == 'string' and data.slug:lower() or ''

    if not label then
        return Panel.fail('Le label doit faire entre 2 et 60 caractères.')
    end

    if not slug:match('^[a-z0-9_]+$') or #slug < 2 or #slug > 30 then
        return Panel.fail('Clé invalide : 2 à 30 caractères, minuscules, chiffres et _.')
    end

    if (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `lunatic_shops` WHERE `slug` = ?', { slug })) or 0) > 0 then
        return Panel.fail('Un magasin utilise déjà cette clé.')
    end

    local id = MySQL.insert.await('INSERT INTO `lunatic_shops` (`category`, `slug`, `label`, `blip_sprite`, `blip_color`, `blip_scale`, `blip_label`, `jobs`, `created_by`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        category.id, slug, label, category.blip.sprite, category.blip.color, 0.8, label, '[]', Staff.displayName(src), os.time(),
    })

    load()
    Logs.add(src, 'shops.create', nil, { id = id, label = label, category = category.id })

    return { ok = true, silent = true, id = id }
end

-- Enregistrement de la fiche complète (articles compris), comme le bouton « Enregistrer »
Panel.actions['shops.save'] = function(src, actor, data)
    local shop, err = shopFor(actor, data.id)

    if not shop then
        return err
    end

    local label = cleanText(data.label, 2, 60)
    local blipLabel = cleanText(data.blipLabel, 0, 60)
    local header = cleanText(data.header, 0, 255)
    local slug = type(data.slug) == 'string' and data.slug:lower() or ''
    local sprite = number(data.blipSprite, 0, 900, true)
    local color = number(data.blipColor, 0, 85, true)
    local scale = number(data.blipScale, 0.1, 3)
    local defaultPrice = number(data.defaultPrice or 0, 0, LIMITS.price, true)

    if not label or not blipLabel or not header then
        return Panel.fail('Label (2-60), label du blip (60 max) ou image (255 max) invalide.')
    end

    if not slug:match('^[a-z0-9_]+$') or #slug < 2 or #slug > 30 then
        return Panel.fail('Clé invalide : 2 à 30 caractères, minuscules, chiffres et _.')
    end

    if slug ~= shop.slug and (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `lunatic_shops` WHERE `slug` = ?', { slug })) or 0) > 0 then
        return Panel.fail('Un magasin utilise déjà cette clé.')
    end

    if not defaultPrice then
        return Panel.fail('Prix par défaut invalide.')
    end

    if not sprite or not color or not scale then
        return Panel.fail('Blip invalide : sprite 0-900, couleur 0-85, taille 0,1-3.')
    end

    local jobs = {}
    local known = ESX.GetJobs()

    for _, name in ipairs(type(data.jobs) == 'table' and data.jobs or {}) do
        if type(name) == 'string' and known[name] then
            jobs[#jobs + 1] = name
        end
    end

    if type(data.items) ~= 'table' or #data.items > LIMITS.items then
        return Panel.fail(('Maximum %d articles.'):format(LIMITS.items))
    end

    local queries = {
        { query = 'UPDATE `lunatic_shops` SET `slug` = ?, `label` = ?, `blip_sprite` = ?, `blip_color` = ?, `blip_scale` = ?, `blip_label` = ?, `header` = ?, `jobs` = ?, `default_price` = ? WHERE `id` = ?',
            values = { slug, label, sprite, color, scale, blipLabel, header, json.encode(jobs), defaultPrice, shop.id } },
        { query = 'DELETE FROM `lunatic_shop_items` WHERE `shop_id` = ?', values = { shop.id } },
    }

    for index, entry in ipairs(data.items) do
        local price = type(entry) == 'table' and number(entry.price, 0, LIMITS.price, true)

        if not price or type(entry.item) ~= 'string' or not ox:Items(entry.item) then
            return Panel.fail(('Article %d : objet inconnu ou prix invalide.'):format(index))
        end

        local license = type(entry.license) == 'string' and entry.license ~= '' and entry.license or nil

        if license and not licenses[license] then
            return Panel.fail(('Article %d : permis inconnu.'):format(index))
        end

        queries[#queries + 1] = { query = 'INSERT INTO `lunatic_shop_items` (`shop_id`, `item`, `price`, `license`, `position`) VALUES (?, ?, ?, ?, ?)',
            values = { shop.id, entry.item, price, license or '', index } }
    end

    if not MySQL.transaction.await(queries) then
        return Panel.fail("Enregistrement impossible (voir la console du serveur).")
    end

    load()
    Logs.add(src, 'shops.save', nil, { id = shop.id, label = label, items = #data.items })

    return { ok = true, silent = true }
end

Panel.actions['shops.delete'] = function(src, actor, data)
    local shop, err = shopFor(actor, data.id)

    if not shop then
        return err
    end

    MySQL.transaction.await({
        { query = 'DELETE FROM `lunatic_shop_items` WHERE `shop_id` = ?', values = { shop.id } },
        { query = 'DELETE FROM `lunatic_shop_vehicles` WHERE `shop_id` = ?', values = { shop.id } },
        { query = 'DELETE FROM `lunatic_shop_locations` WHERE `shop_id` = ?', values = { shop.id } },
        { query = 'DELETE FROM `lunatic_shops` WHERE `id` = ?', values = { shop.id } },
    })

    -- Laissé vide pour ox_inventory : le magasin ne s'ouvre plus
    TriggerEvent('lunatic_admin:shopRemoved', shop.slug)
    load()
    Logs.add(src, 'shops.delete', nil, { id = shop.id, label = shop.label, category = shop.category })

    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Emplacements
---------------------------------------------------------------------

Panel.actions['shops.addLocation'] = function(src, actor, data)
    local shop, err = shopFor(actor, data.id)

    if not shop then
        return err
    end

    if #shop.locations >= LIMITS.locations then
        return Panel.fail(('Maximum %d emplacements par magasin.'):format(LIMITS.locations))
    end

    local position = positionOf(src)

    if not position then
        return Panel.fail("Votre personnage n'est pas encore apparu.")
    end

    MySQL.insert.await('INSERT INTO `lunatic_shop_locations` (`shop_id`, `x`, `y`, `z`, `h`) VALUES (?, ?, ?, ?, ?)', { shop.id, position.x, position.y, position.z, position.h })
    load()
    Logs.add(src, 'shops.location', nil, { id = shop.id, label = shop.label, operation = 'add' })

    return { ok = true, silent = true }
end

local function locationFor(actor, locationId)
    if not Ranks.hasPermission(actor, 'catalogs.manage') then
        return nil, nil, denied()
    end

    for _, shop in pairs(shops) do
        for _, location in ipairs(shop.locations) do
            if location.id == tonumber(locationId) then
                return shop, location
            end
        end
    end

    return nil, nil, Panel.fail('Emplacement introuvable.')
end

Panel.actions['shops.moveLocation'] = function(src, actor, data)
    local shop, location, err = locationFor(actor, data.locationId)

    if not shop then
        return err
    end

    local position = positionOf(src)

    if not position then
        return Panel.fail("Votre personnage n'est pas encore apparu.")
    end

    MySQL.update.await('UPDATE `lunatic_shop_locations` SET `x` = ?, `y` = ?, `z` = ?, `h` = ? WHERE `id` = ?', { position.x, position.y, position.z, position.h, location.id })
    load()
    Logs.add(src, 'shops.location', nil, { id = shop.id, label = shop.label, operation = 'move' })

    return { ok = true, silent = true }
end

Panel.actions['shops.deleteLocation'] = function(src, actor, data)
    local shop, location, err = locationFor(actor, data.locationId)

    if not shop then
        return err
    end

    MySQL.update.await('DELETE FROM `lunatic_shop_locations` WHERE `id` = ?', { location.id })
    load()
    Logs.add(src, 'shops.location', nil, { id = shop.id, label = shop.label, operation = 'delete' })

    return { ok = true, silent = true }
end

Panel.actions['shops.tpLocation'] = function(src, actor, data)
    local shop, location, err = locationFor(actor, data.locationId)

    if not shop then
        return err
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(location.x, location.y, location.z + 1.0))
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Agences de location (lot C3) : véhicules et sortie des véhicules
---------------------------------------------------------------------

local VEHICLE_TYPES = { automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true }

Panel.actions['shops.addVehicle'] = function(src, actor, data)
    local shop, err = shopFor(actor, data.id)

    if not shop then
        return err
    end

    if shop.kind ~= 'rental' then
        return Panel.fail("Ce magasin n'est pas une agence de location.")
    end

    local model = type(data.model) == 'string' and data.model:lower():gsub('%s', '') or ''
    local label = cleanText(data.label, 2, 60)
    local price = number(data.price, 0, LIMITS.price, true)
    local duration = number(data.duration, 1, 1440, true)
    local category = cleanText(data.category, 0, 40)
    local image = cleanText(data.image, 0, 255)

    if not category or not image then
        return Panel.fail('Catégorie (40 max) ou image (255 max) invalide.')
    end

    if not model:match('^[%w_]+$') or #model > 32 then
        return Panel.fail('Nom de modèle invalide.')
    end

    if not label or not price or not duration then
        return Panel.fail('Nom (2-60), prix (entier) ou durée (1 à 1440 minutes) invalide.')
    end

    -- Le serveur ne connaît pas les modèles : le jeu du staff vérifie qu'il existe et donne son type
    local ok, info = pcall(lib.callback.await, 'lunatic_admin:vehicleModel', src, model)

    if not ok or type(info) ~= 'table' then
        return Panel.fail('Vérification du modèle impossible (êtes-vous en jeu ?).')
    end

    if not info.ok or not VEHICLE_TYPES[info.type] then
        return Panel.fail(('Le modèle « %s » n\'existe pas.'):format(model))
    end

    MySQL.insert.await('INSERT INTO `lunatic_shop_vehicles` (`shop_id`, `model`, `label`, `type`, `price`, `duration`, `position`, `category`, `image`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        shop.id, model, label, info.type, price, duration, #shop.vehicles, category, image,
    })

    load()
    Logs.add(src, 'shops.save', nil, { id = shop.id, label = shop.label, operation = ('véhicule %s ajouté'):format(model) })

    return { ok = true, silent = true }
end

-- Modifier un véhicule de location sans le recréer (nom, prix, durée, catégorie, image)
Panel.actions['shops.updateVehicle'] = function(src, actor, data)
    local shop, err = shopFor(actor, data.id)

    if not shop then
        return err
    end

    local label = cleanText(data.label, 2, 60)
    local price = number(data.price, 0, LIMITS.price, true)
    local duration = number(data.duration, 1, 1440, true)
    local category = cleanText(data.category, 0, 40)
    local image = cleanText(data.image, 0, 255)

    if not label or not price or not duration or not category or not image then
        return Panel.fail('Nom (2-60), prix, durée (1 à 1440 min), catégorie (40 max) ou image (255 max) invalide.')
    end

    local changed = MySQL.update.await('UPDATE `lunatic_shop_vehicles` SET `label` = ?, `price` = ?, `duration` = ?, `category` = ?, `image` = ? WHERE `id` = ? AND `shop_id` = ?', {
        label, price, duration, category, image, tonumber(data.vehicleId) or -1, shop.id,
    })

    if (tonumber(changed) or 0) == 0 then
        return Panel.fail('Véhicule introuvable.')
    end

    load()
    Logs.add(src, 'shops.save', nil, { id = shop.id, label = shop.label, operation = ('véhicule %s modifié'):format(label) })

    return { ok = true, silent = true }
end

Panel.actions['shops.deleteVehicle'] = function(src, actor, data)
    local shop, err = shopFor(actor, data.id)

    if not shop then
        return err
    end

    local changed = MySQL.update.await('DELETE FROM `lunatic_shop_vehicles` WHERE `id` = ? AND `shop_id` = ?', { tonumber(data.vehicleId) or -1, shop.id })

    if (tonumber(changed) or 0) == 0 then
        return Panel.fail('Véhicule introuvable.')
    end

    load()
    return { ok = true, silent = true }
end

-- Sortie des véhicules d'un emplacement : position et orientation actuelles du staff
Panel.actions['shops.setSpawn'] = function(src, actor, data)
    local shop, location, err = locationFor(actor, data.locationId)

    if not shop then
        return err
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return Panel.fail("Votre personnage n'est pas encore apparu.")
    end

    local coords = GetEntityCoords(ped)
    MySQL.update.await('UPDATE `lunatic_shop_locations` SET `sx` = ?, `sy` = ?, `sz` = ?, `sh` = ? WHERE `id` = ?', { coords.x, coords.y, coords.z, GetEntityHeading(ped), location.id })
    load()
    Logs.add(src, 'shops.location', nil, { id = shop.id, label = shop.label, operation = 'sortie véhicules' })

    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Magasins chargé.')
