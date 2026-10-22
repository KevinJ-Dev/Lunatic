-- Lot E3 : catalogues des structures (onglet Catalogues de la fiche d'une entreprise ou d'un service public).
--   equipment : équipement des membres selon leur grade, payé par le compte de la société (prix 0 = gratuit)
--   craft     : recettes de fabrication des membres (ingrédients consommés)
-- Un catalogue peut être partagé entre plusieurs structures (ex. armurerie commune à la police).
-- Droits : la permission de la tuile (Entreprises / Services publics) d'une des structures rattachées.
-- Tout est diffusé dans GlobalState.lunaticCatalogs (lu par lunatic_business).
-- Les magasins automatiques (LTD, Ammunation…) sont dans server/shops.lua (tuile Catalogues).

Catalogs = {}

local KINDS = { equipment = 'Équipement', craft = 'Craft' }
local LIMITS = { count = 1000, price = 10000000, grade = 50, duration = 600, ingredients = 10, lines = 200 }

---@type table<number, table> catalogues par id
local catalogs = {}

local ox = exports.ox_inventory

local function publish()
    local list = {}

    for id, catalog in pairs(catalogs) do
        list[tostring(id)] = catalog
    end

    GlobalState.lunaticCatalogs = list
end

local function itemLabels()
    local labels = {}

    for name, item in pairs(ox:Items() or {}) do
        labels[name] = item.label or name
    end

    return labels
end

-- Catalogues d'une structure, lignes comprises (fiche)
function Catalogs.ofJob(jobName)
    local labels = itemLabels()
    local list = {}

    for _, catalog in pairs(catalogs) do
        if catalog.jobs[jobName] then
            local shared = 0

            for job in pairs(catalog.jobs) do
                if job ~= jobName then
                    shared = shared + 1
                end
            end

            local lines = {}

            for _, line in ipairs(catalog.lines) do
                local ingredients = {}

                for _, entry in ipairs(line.ingredients or {}) do
                    ingredients[#ingredients + 1] = { item = entry.item, count = entry.count, label = labels[entry.item] or entry.item }
                end

                lines[#lines + 1] = {
                    id = line.id, item = line.item, label = labels[line.item] or line.item, missing = labels[line.item] == nil,
                    count = line.count, price = line.price, minGrade = line.minGrade, duration = line.duration, ingredients = ingredients,
                }
            end

            list[#list + 1] = { id = catalog.id, label = catalog.label, kind = catalog.kind, kindLabel = KINDS[catalog.kind], shared = shared, lines = lines }
        end
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

-- Catalogues qu'une structure peut rattacher (partagés par d'autres structures)
function Catalogs.all()
    local list = {}

    for _, catalog in pairs(catalogs) do
        list[#list + 1] = { id = catalog.id, label = catalog.label, kind = catalog.kind, kindLabel = KINDS[catalog.kind] }
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

function Catalogs.deleteJob(jobName)
    MySQL.update.await('DELETE FROM `lunatic_structure_catalogs` WHERE `job` = ?', { jobName })

    for _, catalog in pairs(catalogs) do
        catalog.jobs[jobName] = nil
    end

    publish()
end

local function load()
    catalogs = {}

    -- Les anciennes boutiques (type shop) sont remplacées par les magasins automatiques
    for _, row in ipairs(MySQL.query.await("SELECT * FROM `lunatic_catalogs` WHERE `kind` IN ('equipment', 'craft')") or {}) do
        catalogs[tonumber(row.id)] = { id = tonumber(row.id), label = row.label, kind = row.kind, createdBy = row.created_by, lines = {}, jobs = {} }
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_catalog_lines` ORDER BY `position`, `id`') or {}) do
        local catalog = catalogs[tonumber(row.catalog_id)]

        if catalog then
            local ok, ingredients = pcall(json.decode, row.ingredients or '[]')
            catalog.lines[#catalog.lines + 1] = {
                id = tonumber(row.id), item = row.item, count = tonumber(row.count), price = tonumber(row.price),
                minGrade = tonumber(row.min_grade), duration = tonumber(row.duration), ingredients = ok and ingredients or {},
            }
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_structure_catalogs`') or {}) do
        local catalog = catalogs[tonumber(row.catalog_id)]

        if catalog then
            catalog.jobs[row.job] = true
        end
    end

    publish()
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_catalogs` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `label` VARCHAR(60) NOT NULL,
            `kind` VARCHAR(12) NOT NULL,
            `created_by` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- count : quantité donnée (équipement) ou fabriquée (craft) ; ingredients : JSON [{ item, count }]
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_catalog_lines` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `catalog_id` INT NOT NULL,
            `item` VARCHAR(60) NOT NULL,
            `count` INT NOT NULL DEFAULT 1,
            `price` INT NOT NULL DEFAULT 0,
            `min_grade` INT NOT NULL DEFAULT 0,
            `duration` INT NOT NULL DEFAULT 5,
            `ingredients` LONGTEXT NULL DEFAULT NULL,
            `position` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_catalog_lines_catalog` (`catalog_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_structure_catalogs` (
            `job` VARCHAR(50) NOT NULL,
            `catalog_id` INT NOT NULL,
            PRIMARY KEY (`job`, `catalog_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    load()
end)

---------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer ce catalogue.")
end

local function cleanText(value, min, max)
    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length >= min and length <= max and text or nil
end

local function wholeNumber(value, min, max)
    local number = tonumber(value)
    return number and number == math.floor(number) and number >= min and number <= max and math.floor(number) or nil
end

local function itemExists(name)
    return type(name) == 'string' and ox:Items(name) ~= nil
end

local function canManageJob(actor, jobName)
    local permission = type(jobName) == 'string' and Structures.permissionFor(jobName)
    return permission and Ranks.hasPermission(actor, permission) or false
end

-- Droit sur un catalogue : la permission d'une des structures rattachées
local function catalogFor(actor, id)
    local catalog = catalogs[tonumber(id) or -1]

    if not catalog then
        return nil, Panel.fail('Catalogue introuvable.')
    end

    for job in pairs(catalog.jobs) do
        if canManageJob(actor, job) then
            return catalog
        end
    end

    -- Catalogue rattaché à aucune structure : toute personne qui gère des structures
    if next(catalog.jobs) == nil and (Ranks.hasPermission(actor, 'companies.manage') or Ranks.hasPermission(actor, 'publics.manage')) then
        return catalog
    end

    return nil, denied()
end

---------------------------------------------------------------------
-- Actions : catalogues
---------------------------------------------------------------------

-- Liste des objets d'ox_inventory (recherche dans les formulaires)
Panel.actions['catalogs.items'] = function(_, actor)
    if not (Ranks.hasPermission(actor, 'companies.manage') or Ranks.hasPermission(actor, 'publics.manage') or Ranks.hasPermission(actor, 'catalogs.manage') or Ranks.hasPermission(actor, 'illegal.manage') or Ranks.hasPermission(actor, 'items.manage')) then
        return denied()
    end

    local list = {}

    for name, item in pairs(ox:Items() or {}) do
        list[#list + 1] = { name = name, label = item.label or name, price = ItemsCatalog and ItemsCatalog.price(name) or 0 }
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return { ok = true, silent = true, items = list }
end

-- Création depuis la fiche d'une structure : le catalogue lui est rattaché
Panel.actions['catalogs.create'] = function(src, actor, data)
    if not canManageJob(actor, data.job) then
        return denied()
    end

    local label = cleanText(data.label, 2, 60)

    if not label then
        return Panel.fail('Le nom doit faire entre 2 et 60 caractères.')
    end

    if not KINDS[data.kind] then
        return Panel.fail('Type de catalogue inconnu.')
    end

    local id = MySQL.insert.await('INSERT INTO `lunatic_catalogs` (`label`, `kind`, `created_by`, `created_at`) VALUES (?, ?, ?, ?)', {
        label, data.kind, Staff.displayName(src), os.time(),
    })

    MySQL.insert.await('INSERT INTO `lunatic_structure_catalogs` (`job`, `catalog_id`) VALUES (?, ?)', { data.job, id })
    catalogs[id] = { id = id, label = label, kind = data.kind, createdBy = Staff.displayName(src), lines = {}, jobs = { [data.job] = true } }
    publish()
    Logs.add(src, 'catalogs.create', nil, { id = id, label = label, kind = data.kind, job = data.job })

    return { ok = true, silent = true, id = id }
end

Panel.actions['catalogs.rename'] = function(src, actor, data)
    local catalog, err = catalogFor(actor, data.id)

    if not catalog then
        return err
    end

    local label = cleanText(data.label, 2, 60)

    if not label then
        return Panel.fail('Le nom doit faire entre 2 et 60 caractères.')
    end

    MySQL.update.await('UPDATE `lunatic_catalogs` SET `label` = ? WHERE `id` = ?', { label, catalog.id })
    catalog.label = label
    publish()

    return { ok = true, silent = true }
end

Panel.actions['catalogs.delete'] = function(src, actor, data)
    local catalog, err = catalogFor(actor, data.id)

    if not catalog then
        return err
    end

    MySQL.transaction.await({
        { query = 'DELETE FROM `lunatic_catalog_lines` WHERE `catalog_id` = ?', values = { catalog.id } },
        { query = 'DELETE FROM `lunatic_structure_catalogs` WHERE `catalog_id` = ?', values = { catalog.id } },
        { query = 'DELETE FROM `lunatic_catalogs` WHERE `id` = ?', values = { catalog.id } },
    })

    catalogs[catalog.id] = nil
    publish()
    Logs.add(src, 'catalogs.delete', nil, { id = catalog.id, label = catalog.label, kind = catalog.kind })

    return { ok = true, silent = true }
end

-- Rattacher un catalogue partagé, ou le détacher (il reste pour les autres structures)
Panel.actions['catalogs.link'] = function(src, actor, data)
    local catalog = catalogs[tonumber(data.id) or -1]

    if not catalog then
        return Panel.fail('Catalogue introuvable.')
    end

    if not canManageJob(actor, data.job) then
        return denied()
    end

    if data.linked == true then
        MySQL.query.await('INSERT IGNORE INTO `lunatic_structure_catalogs` (`job`, `catalog_id`) VALUES (?, ?)', { data.job, catalog.id })
        catalog.jobs[data.job] = true
    else
        MySQL.update.await('DELETE FROM `lunatic_structure_catalogs` WHERE `job` = ? AND `catalog_id` = ?', { data.job, catalog.id })
        catalog.jobs[data.job] = nil
    end

    publish()
    Logs.add(src, 'catalogs.link', nil, { id = catalog.id, label = catalog.label, job = data.job, linked = data.linked == true })

    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Actions : lignes
---------------------------------------------------------------------

Panel.actions['catalogs.saveLine'] = function(src, actor, data)
    local catalog, err = catalogFor(actor, data.catalogId)

    if not catalog then
        return err
    end

    if not itemExists(data.item) then
        return Panel.fail("Cet objet n'existe pas dans ox_inventory.")
    end

    local craft = catalog.kind == 'craft'
    local count = wholeNumber(data.count, 1, LIMITS.count)
    local price = craft and 0 or wholeNumber(data.price, 0, LIMITS.price)
    local minGrade = wholeNumber(data.minGrade, 0, LIMITS.grade)
    local duration = craft and wholeNumber(data.duration, 1, LIMITS.duration) or 5

    if not count or not price or not minGrade or not duration then
        return Panel.fail(('Valeurs invalides : quantité 1-%d, prix 0-%d, grade 0-%d, durée 1-%d s.'):format(LIMITS.count, LIMITS.price, LIMITS.grade, LIMITS.duration))
    end

    local ingredients = {}

    if craft then
        if type(data.ingredients) ~= 'table' or #data.ingredients < 1 or #data.ingredients > LIMITS.ingredients then
            return Panel.fail(('Une recette a entre 1 et %d ingrédients.'):format(LIMITS.ingredients))
        end

        for _, entry in ipairs(data.ingredients) do
            local amount = type(entry) == 'table' and wholeNumber(entry.count, 1, LIMITS.count)

            if not amount or not itemExists(entry.item) then
                return Panel.fail('Ingrédient invalide.')
            end

            ingredients[#ingredients + 1] = { item = entry.item, count = amount }
        end
    end

    local lineId = tonumber(data.lineId)
    local encoded = json.encode(ingredients)

    if lineId then
        local found = false

        for _, line in ipairs(catalog.lines) do
            if line.id == lineId then
                found = true
            end
        end

        if not found then
            return Panel.fail('Ligne introuvable.')
        end

        MySQL.update.await('UPDATE `lunatic_catalog_lines` SET `item` = ?, `count` = ?, `price` = ?, `min_grade` = ?, `duration` = ?, `ingredients` = ? WHERE `id` = ?', {
            data.item, count, price, minGrade, duration, encoded, lineId,
        })
    else
        if #catalog.lines >= LIMITS.lines then
            return Panel.fail(('Maximum %d lignes par catalogue.'):format(LIMITS.lines))
        end

        lineId = MySQL.insert.await('INSERT INTO `lunatic_catalog_lines` (`catalog_id`, `item`, `count`, `price`, `min_grade`, `duration`, `ingredients`, `position`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
            catalog.id, data.item, count, price, minGrade, duration, encoded, #catalog.lines,
        })
    end

    load()
    Logs.add(src, 'catalogs.line', nil, { id = catalog.id, label = catalog.label, item = data.item, price = price, operation = data.lineId and 'edit' or 'add' })

    return { ok = true, silent = true, lineId = lineId }
end

Panel.actions['catalogs.deleteLine'] = function(src, actor, data)
    local catalog, err = catalogFor(actor, data.catalogId)

    if not catalog then
        return err
    end

    local lineId = tonumber(data.lineId)
    local changed = MySQL.update.await('DELETE FROM `lunatic_catalog_lines` WHERE `id` = ? AND `catalog_id` = ?', { lineId or -1, catalog.id })

    if (tonumber(changed) or 0) == 0 then
        return Panel.fail('Ligne introuvable.')
    end

    load()
    Logs.add(src, 'catalogs.line', nil, { id = catalog.id, label = catalog.label, operation = 'delete', lineId = lineId })

    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Catalogues des structures chargé.')
