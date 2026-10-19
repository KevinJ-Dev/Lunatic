-- Lot E3 : catalogues (tuile Catalogues). Trois types :
--   shop      : boutique ouverte à tous, payée par le client, argent versé au compte de la société
--   equipment : équipement des membres selon leur grade, payé par le compte de la société (prix 0 = gratuit)
--   craft     : recettes de fabrication des membres (ingrédients consommés)
-- Un catalogue peut être rattaché à plusieurs structures. Tout est diffusé dans GlobalState.lunaticCatalogs
-- (lu par lunatic_business, côté serveur pour vérifier et côté client pour afficher).

Catalogs = {}

local KINDS = { shop = 'Boutique', equipment = 'Équipement', craft = 'Craft' }
local LIMITS = { count = 1000, price = 10000000, grade = 50, duration = 600, ingredients = 10, lines = 200 }

---@type table<number, table> catalogues par id
local catalogs = {}

local ox = exports.ox_inventory

local function now()
    return os.time()
end

local function publish()
    local list = {}

    for id, catalog in pairs(catalogs) do
        list[tostring(id)] = catalog
    end

    GlobalState.lunaticCatalogs = list
end

-- Catalogues rattachés à une structure
function Catalogs.ofJob(jobName)
    local list = {}

    for _, catalog in pairs(catalogs) do
        if catalog.jobs[jobName] then
            list[#list + 1] = { id = catalog.id, label = catalog.label, kind = catalog.kind, kindLabel = KINDS[catalog.kind], lines = #catalog.lines }
        end
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

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

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_catalogs`') or {}) do
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

    -- count : quantité donnée (achat) ou fabriquée (craft) ; ingredients : JSON [{ item, count }]
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
    return Panel.fail("Vous n'avez pas la permission de gérer les catalogues.")
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

local function catalogFor(actor, id)
    if not Ranks.hasPermission(actor, 'catalogs.manage') then
        return nil, denied()
    end

    local catalog = catalogs[tonumber(id) or -1]

    if not catalog then
        return nil, Panel.fail('Catalogue introuvable.')
    end

    return catalog
end

local function structuresList()
    local jobs = ESX.GetJobs()
    local list = {}

    for _, entry in ipairs(MySQL.query.await('SELECT `job`, `kind` FROM `lunatic_structures`') or {}) do
        list[#list + 1] = { job = entry.job, label = jobs[entry.job] and jobs[entry.job].label or entry.job, kind = entry.kind }
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

---------------------------------------------------------------------
-- Actions : catalogues
---------------------------------------------------------------------

Panel.actions['catalogs.list'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'catalogs.manage') then
        return denied()
    end

    local list = {}

    for _, catalog in pairs(catalogs) do
        local jobs = 0

        for _ in pairs(catalog.jobs) do
            jobs = jobs + 1
        end

        list[#list + 1] = { id = catalog.id, label = catalog.label, kind = catalog.kind, kindLabel = KINDS[catalog.kind], lines = #catalog.lines, structures = jobs }
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return { ok = true, silent = true, catalogs = list, kinds = KINDS }
end

Panel.actions['catalogs.info'] = function(_, actor, data)
    local catalog, err = catalogFor(actor, data.id)

    if not catalog then
        return err
    end

    local labels = {}

    for name, item in pairs(ox:Items() or {}) do
        labels[name] = item.label or name
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

    local linked = {}

    for job in pairs(catalog.jobs) do
        linked[#linked + 1] = job
    end

    return { ok = true, silent = true, catalog = {
        id = catalog.id, label = catalog.label, kind = catalog.kind, kindLabel = KINDS[catalog.kind], createdBy = catalog.createdBy,
        lines = lines, linked = linked,
    }, structures = structuresList() }
end

-- Liste des objets d'ox_inventory (recherche dans le formulaire de ligne)
Panel.actions['catalogs.items'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'catalogs.manage') then
        return denied()
    end

    local list = {}

    for name, item in pairs(ox:Items() or {}) do
        list[#list + 1] = { name = name, label = item.label or name }
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return { ok = true, silent = true, items = list }
end

Panel.actions['catalogs.create'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'catalogs.manage') then
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
        label, data.kind, Staff.displayName(src), now(),
    })

    catalogs[id] = { id = id, label = label, kind = data.kind, createdBy = Staff.displayName(src), lines = {}, jobs = {} }
    publish()
    Logs.add(src, 'catalogs.create', nil, { id = id, label = label, kind = data.kind })

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

    local count = wholeNumber(data.count, 1, LIMITS.count)
    local price = catalog.kind == 'craft' and 0 or wholeNumber(data.price, 0, LIMITS.price)
    local minGrade = catalog.kind == 'shop' and 0 or wholeNumber(data.minGrade, 0, LIMITS.grade)
    local duration = catalog.kind == 'craft' and wholeNumber(data.duration, 1, LIMITS.duration) or 5

    if not count or not price or not minGrade or not duration then
        return Panel.fail(('Valeurs invalides : quantité 1-%d, prix 0-%d, grade 0-%d, durée 1-%d s.'):format(LIMITS.count, LIMITS.price, LIMITS.grade, LIMITS.duration))
    end

    local ingredients = {}

    if catalog.kind == 'craft' then
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

---------------------------------------------------------------------
-- Rattachement à une structure (tuile Catalogues ou fiche de la structure)
---------------------------------------------------------------------

Panel.actions['catalogs.link'] = function(src, actor, data)
    local catalog = catalogs[tonumber(data.id) or -1]

    if not catalog then
        return Panel.fail('Catalogue introuvable.')
    end

    local permission = type(data.job) == 'string' and Structures.permissionFor(data.job)

    if not permission then
        return Panel.fail('Structure introuvable.')
    end

    if not Ranks.hasPermission(actor, 'catalogs.manage') and not Ranks.hasPermission(actor, permission) then
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

print('[lunatic_admin] Module Catalogues chargé.')
