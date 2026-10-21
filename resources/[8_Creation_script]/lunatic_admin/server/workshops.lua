-- Illégal, étape 5 : craft d'armes (tuile Illégal, onglet Craft d'armes).
-- Un atelier : nom, types de crew autorisés, level de crew minimum, alerte police, emplacements et recettes.
-- Une recette : objet fabriqué (arme, munitions, accessoire…), quantité, durée, level minimum, XP du crew, ingrédients.
-- Diffusé dans GlobalState.lunaticWorkshops ; la fabrication en jeu est dans lunatic_illegal (tout y est revérifié).

local ox = exports.ox_inventory

local CREW_TYPES = {}

for _, entry in ipairs(Config.CrewTypes) do
    CREW_TYPES[entry.id] = entry.label
end

local LIMITS = { workshops = 50, locations = 20, recipes = 50, count = 500, duration = 900, level = #Config.CrewLevels, xp = 10000 }

local workshops = {}

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

local function publish()
    GlobalState.lunaticWorkshops = workshops
end

local function decode(text, fallback)
    local ok, value = pcall(json.decode, text or '')
    return ok and type(value) == 'table' and value or fallback
end

local function load()
    workshops = {}
    local byId = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_workshops` ORDER BY `id`') or {}) do
        local workshop = {
            id = tonumber(row.id), label = row.label, crewTypes = decode(row.crew_types, {}), minLevel = tonumber(row.min_level) or 1,
            alert = tonumber(row.alert) == 1, locations = {}, recipes = {},
        }
        workshops[#workshops + 1] = workshop
        byId[workshop.id] = workshop
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_workshop_locations` ORDER BY `id`') or {}) do
        local workshop = byId[tonumber(row.workshop_id)]

        if workshop then
            workshop.locations[#workshop.locations + 1] = { id = tonumber(row.id), x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h) }
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_workshop_recipes` ORDER BY `position`, `id`') or {}) do
        local workshop = byId[tonumber(row.workshop_id)]

        if workshop then
            workshop.recipes[#workshop.recipes + 1] = {
                id = tonumber(row.id), item = row.item, count = tonumber(row.count), duration = tonumber(row.duration),
                minLevel = tonumber(row.min_level) or 1, xp = tonumber(row.xp) or 0, ingredients = decode(row.ingredients, {}),
            }
        end
    end

    publish()
end

local function findWorkshop(id)
    for _, workshop in ipairs(workshops) do
        if workshop.id == tonumber(id) then
            return workshop
        end
    end
end

local function findLocation(locationId)
    for _, workshop in ipairs(workshops) do
        for _, location in ipairs(workshop.locations) do
            if location.id == tonumber(locationId) then
                return location, workshop
            end
        end
    end
end

local function findRecipe(recipeId)
    for _, workshop in ipairs(workshops) do
        for _, recipe in ipairs(workshop.recipes) do
            if recipe.id == tonumber(recipeId) then
                return recipe, workshop
            end
        end
    end
end

local function readIngredients(list)
    if type(list) ~= 'table' or #list < 1 or #list > 10 then
        return nil, 'Une recette a entre 1 et 10 ingrédients.'
    end

    local ingredients = {}

    for _, entry in ipairs(list) do
        local count = type(entry) == 'table' and whole(entry.count, 1, 1000)

        if not count or type(entry.item) ~= 'string' or not ox:Items(entry.item) then
            return nil, 'Ingrédient invalide.'
        end

        ingredients[#ingredients + 1] = { item = entry.item, count = count }
    end

    return ingredients
end

local function readCrewTypes(list)
    if type(list) ~= 'table' or #list < 1 then
        return nil
    end

    local types, seen = {}, {}

    for _, value in ipairs(list) do
        if not CREW_TYPES[value] then
            return nil
        end

        if not seen[value] then
            seen[value] = true
            types[#types + 1] = value
        end
    end

    return types
end

-- Atelier de départ (bouton du panel) : armes de poing, mitraillette, fusil et munitions, avec les pièces d'armes
local SEED = {
    label = "Atelier d'armes",
    recipes = {
        { item = 'WEAPON_SNSPISTOL', count = 1, duration = 60, minLevel = 1, xp = 15, ingredients = { { 'gun_barrel', 1 }, { 'gun_slide', 1 }, { 'gun_spring', 2 }, { 'scrapmetal', 4 } } },
        { item = 'WEAPON_PISTOL', count = 1, duration = 75, minLevel = 2, xp = 20, ingredients = { { 'gun_barrel', 1 }, { 'gun_slide', 1 }, { 'gun_spring', 2 }, { 'scrapmetal', 6 } } },
        { item = 'WEAPON_MICROSMG', count = 1, duration = 120, minLevel = 4, xp = 40, ingredients = { { 'gun_barrel', 1 }, { 'gun_slide', 1 }, { 'gun_spring', 3 }, { 'gun_stock', 1 }, { 'scrapmetal', 10 } } },
        { item = 'WEAPON_ASSAULTRIFLE', count = 1, duration = 180, minLevel = 6, xp = 60, ingredients = { { 'gun_barrel', 2 }, { 'gun_slide', 1 }, { 'gun_spring', 3 }, { 'gun_stock', 1 }, { 'scrapmetal', 15 } } },
        { item = 'ammo-9', count = 24, duration = 20, minLevel = 1, xp = 2, ingredients = { { 'gunpowder', 2 }, { 'bullet_casing', 24 } } },
        { item = 'ammo-45', count = 24, duration = 20, minLevel = 3, xp = 3, ingredients = { { 'gunpowder', 2 }, { 'bullet_casing', 24 } } },
        { item = 'ammo-rifle2', count = 30, duration = 30, minLevel = 5, xp = 4, ingredients = { { 'gunpowder', 4 }, { 'bullet_casing', 30 } } },
    },
}

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_workshops` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `label` VARCHAR(60) NOT NULL,
            `crew_types` VARCHAR(255) NOT NULL DEFAULT '[]',
            `min_level` INT NOT NULL DEFAULT 1,
            `alert` TINYINT NOT NULL DEFAULT 1,
            `created_by` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_workshop_locations` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `workshop_id` INT NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `h` DOUBLE NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_workshop_locations_workshop` (`workshop_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_workshop_recipes` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `workshop_id` INT NOT NULL,
            `item` VARCHAR(60) NOT NULL,
            `count` INT NOT NULL DEFAULT 1,
            `duration` INT NOT NULL DEFAULT 60,
            `min_level` INT NOT NULL DEFAULT 1,
            `xp` INT NOT NULL DEFAULT 0,
            `ingredients` TEXT NOT NULL,
            `position` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_workshop_recipes_workshop` (`workshop_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    load()
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function guard(actor)
    return Ranks.hasPermission(actor, 'illegal.manage')
end

Panel.actions['workshops.info'] = function(_, actor)
    if not guard(actor) then
        return denied()
    end

    local function label(name)
        local item = ox:Items(name)
        return item and item.label or name, item == nil
    end

    local list = {}

    for _, workshop in ipairs(workshops) do
        local copy = json.decode(json.encode(workshop))

        for _, recipe in ipairs(copy.recipes) do
            recipe.label, recipe.missing = label(recipe.item)

            for _, ingredient in ipairs(recipe.ingredients) do
                ingredient.label, ingredient.missing = label(ingredient.item)
            end
        end

        list[#list + 1] = copy
    end

    return { ok = true, silent = true, workshops = list, crewTypes = Config.CrewTypes, crewCounts = Crews.countByType(), maxLevel = LIMITS.level }
end

Panel.actions['workshops.seed'] = function(src, actor)
    if not guard(actor) then
        return denied()
    end

    for _, workshop in ipairs(workshops) do
        if workshop.label == SEED.label then
            return Panel.fail(("L'atelier « %s » existe déjà."):format(SEED.label))
        end
    end

    local types = {}

    for _, entry in ipairs(Config.CrewTypes) do
        types[#types + 1] = entry.id
    end

    local id = MySQL.insert.await('INSERT INTO `lunatic_workshops` (`label`, `crew_types`, `min_level`, `alert`, `created_by`, `created_at`) VALUES (?, ?, 1, 1, ?, ?)', {
        SEED.label, json.encode(types), Staff.displayName(src), os.time(),
    })
    local created, skipped = 0, {}

    for position, recipe in ipairs(SEED.recipes) do
        local ingredients, valid = {}, ox:Items(recipe.item) ~= nil

        for _, entry in ipairs(recipe.ingredients) do
            if not ox:Items(entry[1]) then
                valid = false
            end

            ingredients[#ingredients + 1] = { item = entry[1], count = entry[2] }
        end

        if valid then
            MySQL.insert.await('INSERT INTO `lunatic_workshop_recipes` (`workshop_id`, `item`, `count`, `duration`, `min_level`, `xp`, `ingredients`, `position`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
                id, recipe.item, recipe.count, recipe.duration, recipe.minLevel, recipe.xp, json.encode(ingredients), position,
            })
            created = created + 1
        else
            skipped[#skipped + 1] = recipe.item
        end
    end

    load()
    Logs.add(src, 'workshops.save', nil, { label = SEED.label, operation = ('atelier de départ, %d recette(s)'):format(created) })

    return { ok = true, silent = true, created = created, skipped = skipped }
end

Panel.actions['workshops.save'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local label = type(data.label) == 'string' and data.label:gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    local types = readCrewTypes(data.crewTypes)
    local minLevel = whole(data.minLevel, 1, LIMITS.level)

    if #label < 2 or #label > 60 then
        return Panel.fail('Le nom doit faire entre 2 et 60 caractères.')
    end

    if not types then
        return Panel.fail('Choisissez au moins un type de crew.')
    end

    if not minLevel then
        return Panel.fail(('Level minimum : de 1 à %d.'):format(LIMITS.level))
    end

    local alert = data.alert ~= false and 1 or 0

    if data.id then
        local workshop = findWorkshop(data.id)

        if not workshop then
            return Panel.fail('Atelier introuvable.')
        end

        MySQL.update.await('UPDATE `lunatic_workshops` SET `label` = ?, `crew_types` = ?, `min_level` = ?, `alert` = ? WHERE `id` = ?', { label, json.encode(types), minLevel, alert, workshop.id })
    else
        if #workshops >= LIMITS.workshops then
            return Panel.fail(('Maximum %d ateliers.'):format(LIMITS.workshops))
        end

        MySQL.insert.await('INSERT INTO `lunatic_workshops` (`label`, `crew_types`, `min_level`, `alert`, `created_by`, `created_at`) VALUES (?, ?, ?, ?, ?, ?)', {
            label, json.encode(types), minLevel, alert, Staff.displayName(src), os.time(),
        })
    end

    load()
    Logs.add(src, 'workshops.save', nil, { label = label, operation = data.id and 'edit' or 'add' })

    return { ok = true, silent = true }
end

Panel.actions['workshops.delete'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local workshop = findWorkshop(data.id)

    if not workshop then
        return Panel.fail('Atelier introuvable.')
    end

    MySQL.transaction.await({
        { query = 'DELETE FROM `lunatic_workshop_recipes` WHERE `workshop_id` = ?', values = { workshop.id } },
        { query = 'DELETE FROM `lunatic_workshop_locations` WHERE `workshop_id` = ?', values = { workshop.id } },
        { query = 'DELETE FROM `lunatic_workshops` WHERE `id` = ?', values = { workshop.id } },
    })

    load()
    Logs.add(src, 'workshops.delete', nil, { label = workshop.label })

    return { ok = true, silent = true }
end

Panel.actions['workshops.saveRecipe'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local workshop = findWorkshop(data.workshopId)

    if not workshop then
        return Panel.fail('Atelier introuvable.')
    end

    if type(data.item) ~= 'string' or not ox:Items(data.item) then
        return Panel.fail(("L'objet « %s » n'existe pas dans ox_inventory."):format(tostring(data.item)))
    end

    local count = whole(data.count, 1, LIMITS.count)
    local duration = whole(data.duration, 1, LIMITS.duration)
    local minLevel = whole(data.minLevel, 1, LIMITS.level)
    local xp = whole(data.xp, 0, LIMITS.xp)
    local ingredients, err = readIngredients(data.ingredients)

    if not count or not duration or not minLevel or not xp then
        return Panel.fail(('Quantité (1-%d), durée (1-%d s), level (1-%d) ou XP (0-%d) invalide.'):format(LIMITS.count, LIMITS.duration, LIMITS.level, LIMITS.xp))
    end

    if not ingredients then
        return Panel.fail(err)
    end

    local recipeId = tonumber(data.recipeId)

    if recipeId then
        local recipe, owner = findRecipe(recipeId)

        if not recipe or owner.id ~= workshop.id then
            return Panel.fail('Recette introuvable.')
        end

        MySQL.update.await('UPDATE `lunatic_workshop_recipes` SET `item` = ?, `count` = ?, `duration` = ?, `min_level` = ?, `xp` = ?, `ingredients` = ? WHERE `id` = ?', {
            data.item, count, duration, minLevel, xp, json.encode(ingredients), recipe.id,
        })
    else
        if #workshop.recipes >= LIMITS.recipes then
            return Panel.fail(('Maximum %d recettes par atelier.'):format(LIMITS.recipes))
        end

        MySQL.insert.await('INSERT INTO `lunatic_workshop_recipes` (`workshop_id`, `item`, `count`, `duration`, `min_level`, `xp`, `ingredients`, `position`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
            workshop.id, data.item, count, duration, minLevel, xp, json.encode(ingredients), #workshop.recipes + 1,
        })
    end

    load()
    Logs.add(src, 'workshops.recipe', nil, { label = workshop.label, item = data.item, operation = recipeId and 'edit' or 'add' })

    return { ok = true, silent = true }
end

Panel.actions['workshops.deleteRecipe'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local recipe, workshop = findRecipe(data.recipeId)

    if not recipe then
        return Panel.fail('Recette introuvable.')
    end

    MySQL.update.await('DELETE FROM `lunatic_workshop_recipes` WHERE `id` = ?', { recipe.id })
    load()
    Logs.add(src, 'workshops.recipe', nil, { label = workshop.label, item = recipe.item, operation = 'delete' })

    return { ok = true, silent = true }
end

Panel.actions['workshops.addLocation'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local workshop = findWorkshop(data.id)
    local position = positionOf(src)

    if not workshop or not position then
        return Panel.fail('Atelier introuvable.')
    end

    if #workshop.locations >= LIMITS.locations then
        return Panel.fail(('Maximum %d emplacements par atelier.'):format(LIMITS.locations))
    end

    MySQL.insert.await('INSERT INTO `lunatic_workshop_locations` (`workshop_id`, `x`, `y`, `z`, `h`) VALUES (?, ?, ?, ?, ?)', { workshop.id, position.x, position.y, position.z, position.h })
    load()

    return { ok = true, silent = true }
end

Panel.actions['workshops.moveLocation'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local location = findLocation(data.locationId)
    local position = positionOf(src)

    if not location or not position then
        return Panel.fail('Emplacement introuvable.')
    end

    MySQL.update.await('UPDATE `lunatic_workshop_locations` SET `x` = ?, `y` = ?, `z` = ?, `h` = ? WHERE `id` = ?', { position.x, position.y, position.z, position.h, location.id })
    load()

    return { ok = true, silent = true }
end

Panel.actions['workshops.deleteLocation'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local location = findLocation(data.locationId)

    if not location then
        return Panel.fail('Emplacement introuvable.')
    end

    MySQL.update.await('DELETE FROM `lunatic_workshop_locations` WHERE `id` = ?', { location.id })
    load()

    return { ok = true, silent = true }
end

Panel.actions['workshops.tpLocation'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local location = findLocation(data.locationId)

    if not location then
        return Panel.fail('Emplacement introuvable.')
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(location.x, location.y, location.z + 1.0))
    return { ok = true, silent = true }
end

-- Vue staff : tous les ateliers visibles en jeu (orange), sans fabriquer
Panel.actions['workshops.staffView'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    TriggerClientEvent('lunatic_illegal:staffWorkshops', src, data.enabled == true)
    return { ok = true, silent = true }
end

print("[lunatic_admin] Module Craft d'armes chargé.")
