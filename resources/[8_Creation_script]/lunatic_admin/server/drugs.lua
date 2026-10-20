-- Illégal, étape 3 : drogues (tuile Illégal, onglet Drogues).
-- Une drogue : objet vendu, statut, prix, XP et influence par vente, policiers requis, volumes.
-- Ses laboratoires : type de crew autorisé, recette (ingrédients, durée, quantité produite), emplacements.
-- Diffusé dans GlobalState.lunaticDrugs ; production et vente en jeu dans lunatic_illegal.
-- L'influence gagnée est journalisée (lunatic_crew_influence) pour les territoires.

local ox = exports.ox_inventory

local CREW_TYPES = {}

for _, entry in ipairs(Config.CrewTypes) do
    CREW_TYPES[entry.id] = entry.label
end

local drugs = {}

local function publish()
    GlobalState.lunaticDrugs = drugs
end

local function load()
    drugs = {}
    local byId, labsById = {}, {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_drugs` ORDER BY `position`, `id`') or {}) do
        local drug = {
            id = tonumber(row.id), item = row.item, active = row.active == true or row.active == 1, price = tonumber(row.price),
            xp = tonumber(row.xp), influence = tonumber(row.influence), cops = tonumber(row.cops),
            volumeMin = tonumber(row.volume_min), volumeMax = tonumber(row.volume_max), labs = {},
        }
        drugs[#drugs + 1] = drug
        byId[drug.id] = drug
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_drug_labs` ORDER BY `id`') or {}) do
        local drug = byId[tonumber(row.drug_id)]

        if drug then
            local ok, ingredients = pcall(json.decode, row.ingredients or '[]')
            local lab = { id = tonumber(row.id), crewType = row.crew_type, output = tonumber(row.output), duration = tonumber(row.duration), ingredients = ok and ingredients or {}, locations = {} }
            drug.labs[#drug.labs + 1] = lab
            labsById[lab.id] = lab
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_drug_lab_locations` ORDER BY `id`') or {}) do
        local lab = labsById[tonumber(row.lab_id)]

        if lab then
            lab.locations[#lab.locations + 1] = { id = tonumber(row.id), x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h) }
        end
    end

    publish()
end

-- Drogues de départ (une seule fois, si aucune drogue n'existe) : objets définis dans ox_inventory/data/items.lua.
-- Les laboratoires sont créés sans emplacement : le staff les place en jeu (onglet Drogues, « Emplacement »).
local SEED = {
    { item = 'weed', price = 90, xp = 4, influence = 1, cops = 0, volumeMin = 1, volumeMax = 5,
        lab = { crewType = 'gang', output = 5, duration = 30, ingredients = { { item = 'weed_leaf', count = 5 }, { item = 'plastic_bag', count = 5 } } } },
    { item = 'cocaine', price = 220, xp = 8, influence = 3, cops = 2, volumeMin = 1, volumeMax = 4,
        lab = { crewType = 'mafia', output = 4, duration = 45, ingredients = { { item = 'coca_leaf', count = 4 }, { item = 'chemicals', count = 1 }, { item = 'plastic_bag', count = 4 } } } },
    { item = 'meth', price = 180, xp = 7, influence = 2, cops = 2, volumeMin = 1, volumeMax = 4,
        lab = { crewType = 'mc', output = 4, duration = 45, ingredients = { { item = 'pseudoephedrine', count = 3 }, { item = 'chemicals', count = 1 }, { item = 'plastic_bag', count = 4 } } } },
    { item = 'fentanyl', price = 320, xp = 10, influence = 4, cops = 3, volumeMin = 1, volumeMax = 3,
        lab = { crewType = 'organisation', output = 3, duration = 60, ingredients = { { item = 'pseudoephedrine', count = 2 }, { item = 'chemicals', count = 2 }, { item = 'empty_vial', count = 3 } } } },
}

-- Ajoute les drogues de départ dont l'objet n'est pas encore utilisé par une drogue existante
---@return number created, string[] missing objets absents d'ox_inventory
local function seedMissing()
    local used = {}

    for _, row in ipairs(MySQL.query.await('SELECT `item` FROM `lunatic_drugs`') or {}) do
        used[row.item] = true
    end

    local position = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `lunatic_drugs`')) or 0
    local created, missing = 0, {}

    for _, entry in ipairs(SEED) do
        if not used[entry.item] then
            if ox:Items(entry.item) then
                local id = MySQL.insert.await('INSERT INTO `lunatic_drugs` (`item`, `active`, `price`, `xp`, `influence`, `cops`, `volume_min`, `volume_max`, `position`) VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?)', {
                    entry.item, entry.price, entry.xp, entry.influence, entry.cops, entry.volumeMin, entry.volumeMax, position,
                })

                MySQL.insert.await('INSERT INTO `lunatic_drug_labs` (`drug_id`, `crew_type`, `output`, `duration`, `ingredients`) VALUES (?, ?, ?, ?, ?)', {
                    id, entry.lab.crewType, entry.lab.output, entry.lab.duration, json.encode(entry.lab.ingredients),
                })

                created, position = created + 1, position + 1
            else
                missing[#missing + 1] = entry.item
            end
        end
    end

    return created, missing
end

-- Premier démarrage : une seule fois (retenté au démarrage suivant si des objets manquent dans ox_inventory)
local function seedOnce()
    if GetResourceKvpString('drugs_seeded') then
        return
    end

    local created, missing = seedMissing()

    if #missing > 0 then
        print(('[lunatic_admin] Drogues de départ : objets absents d\'ox_inventory (%s). Envoyez ox_inventory/data/items.lua et redémarrez le serveur.'):format(table.concat(missing, ', ')))
    else
        SetResourceKvp('drugs_seeded', '1')
    end

    if created > 0 then
        print(('[lunatic_admin] %d drogue(s) de départ créée(s) : placez leurs laboratoires depuis le panel.'):format(created))
    end
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_drugs` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `item` VARCHAR(60) NOT NULL,
            `active` TINYINT(1) NOT NULL DEFAULT 1,
            `price` INT NOT NULL DEFAULT 100,
            `xp` INT NOT NULL DEFAULT 5,
            `influence` INT NOT NULL DEFAULT 1,
            `cops` INT NOT NULL DEFAULT 0,
            `volume_min` INT NOT NULL DEFAULT 1,
            `volume_max` INT NOT NULL DEFAULT 5,
            `position` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_drug_labs` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `drug_id` INT NOT NULL,
            `crew_type` VARCHAR(20) NOT NULL,
            `output` INT NOT NULL DEFAULT 1,
            `duration` INT NOT NULL DEFAULT 20,
            `ingredients` LONGTEXT NULL DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_drug_labs_drug` (`drug_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_drug_lab_locations` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `lab_id` INT NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `h` DOUBLE NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_drug_lab_locations_lab` (`lab_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Influence gagnée par les crews, avec la position (pour les territoires)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_crew_influence` (
            `id` BIGINT NOT NULL AUTO_INCREMENT,
            `crew_id` INT NOT NULL,
            `amount` INT NOT NULL,
            `x` DOUBLE NOT NULL DEFAULT 0,
            `y` DOUBLE NOT NULL DEFAULT 0,
            `source` VARCHAR(30) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_crew_influence_crew` (`crew_id`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    seedOnce()
    load()
end)

exports('addCrewInfluence', function(crewId, amount, x, y, origin)
    amount = math.floor(tonumber(amount) or 0)

    if not tonumber(crewId) or amount == 0 then
        return false
    end

    MySQL.insert('INSERT INTO `lunatic_crew_influence` (`crew_id`, `amount`, `x`, `y`, `source`, `created_at`) VALUES (?, ?, ?, ?, ?, ?)', {
        tonumber(crewId), amount, tonumber(x) or 0, tonumber(y) or 0, tostring(origin or ''):sub(1, 30), os.time(),
    })

    -- Territoires touchés : recalculés dans les secondes qui suivent (server/territories.lua)
    if Territories then
        Territories.touch(x, y)
    end

    return true
end)

---------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------

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

local function findDrug(id)
    for _, drug in ipairs(drugs) do
        if drug.id == tonumber(id) then
            return drug
        end
    end
end

local function findLab(id)
    for _, drug in ipairs(drugs) do
        for _, lab in ipairs(drug.labs) do
            if lab.id == tonumber(id) then
                return lab, drug
            end
        end
    end
end

local function findLocation(id)
    for _, drug in ipairs(drugs) do
        for _, lab in ipairs(drug.labs) do
            for _, location in ipairs(lab.locations) do
                if location.id == tonumber(id) then
                    return location, lab
                end
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

---------------------------------------------------------------------
-- Actions : drogues
---------------------------------------------------------------------

Panel.actions['drugs.info'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local function label(name)
        local item = ox:Items(name)
        return item and item.label or name, item == nil
    end

    local list = {}

    for _, drug in ipairs(drugs) do
        local copy = json.decode(json.encode(drug))
        copy.label, copy.missing = label(drug.item)

        for _, lab in ipairs(copy.labs) do
            lab.crewTypeLabel = CREW_TYPES[lab.crewType] or lab.crewType

            for _, ingredient in ipairs(lab.ingredients) do
                ingredient.label, ingredient.missing = label(ingredient.item)
            end
        end

        list[#list + 1] = copy
    end

    return { ok = true, silent = true, drugs = list, crewTypes = Config.CrewTypes, crewCounts = Crews.countByType() }
end

-- Bouton « Drogues de départ » : ajoute celles qui manquent (weed, cocaïne, meth, fentanyl et leurs laboratoires)
Panel.actions['drugs.seed'] = function(src, actor)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local created, missing = seedMissing()
    load()

    if created == 0 and #missing > 0 then
        return Panel.fail(("Objets absents d'ox_inventory : %s. Envoyez ox_inventory/data/items.lua puis redémarrez le serveur."):format(table.concat(missing, ', ')))
    end

    if created == 0 then
        return Panel.fail('Les drogues de départ sont déjà toutes présentes.')
    end

    Logs.add(src, 'drugs.save', nil, { item = 'drogues de départ', operation = ('%d ajoutée(s)'):format(created) })
    return { ok = true, silent = true, created = created, missing = missing }
end

Panel.actions['drugs.save'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    if type(data.item) ~= 'string' or not ox:Items(data.item) then
        return Panel.fail("Cet objet n'existe pas dans ox_inventory.")
    end

    local price = whole(data.price, 0, 1000000)
    local xp = whole(data.xp, 0, 10000)
    local influence = whole(data.influence, 0, 10000)
    local cops = whole(data.cops, 0, 50)
    local volumeMin = whole(data.volumeMin, 1, 1000)
    local volumeMax = whole(data.volumeMax, 1, 1000)

    if not price or not xp or not influence or not cops or not volumeMin or not volumeMax or volumeMin > volumeMax then
        return Panel.fail('Valeurs invalides : nombres entiers positifs, volume min ≤ volume max.')
    end

    local values = { data.item, data.active == false and 0 or 1, price, xp, influence, cops, volumeMin, volumeMax }
    local id = tonumber(data.id)

    if id then
        if not findDrug(id) then
            return Panel.fail('Drogue introuvable.')
        end

        values[#values + 1] = id
        MySQL.update.await('UPDATE `lunatic_drugs` SET `item` = ?, `active` = ?, `price` = ?, `xp` = ?, `influence` = ?, `cops` = ?, `volume_min` = ?, `volume_max` = ? WHERE `id` = ?', values)
    else
        values[#values + 1] = #drugs
        id = MySQL.insert.await('INSERT INTO `lunatic_drugs` (`item`, `active`, `price`, `xp`, `influence`, `cops`, `volume_min`, `volume_max`, `position`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', values)
    end

    load()
    Logs.add(src, 'drugs.save', nil, { item = data.item, price = price, operation = data.id and 'edit' or 'add' })

    return { ok = true, silent = true, id = id }
end

-- Copie de la drogue et de ses laboratoires (recettes), sans les emplacements
Panel.actions['drugs.duplicate'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local drug = findDrug(data.id)

    if not drug then
        return Panel.fail('Drogue introuvable.')
    end

    local id = MySQL.insert.await('INSERT INTO `lunatic_drugs` (`item`, `active`, `price`, `xp`, `influence`, `cops`, `volume_min`, `volume_max`, `position`) VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?)', {
        drug.item, drug.price, drug.xp, drug.influence, drug.cops, drug.volumeMin, drug.volumeMax, #drugs,
    })

    for _, lab in ipairs(drug.labs) do
        MySQL.insert.await('INSERT INTO `lunatic_drug_labs` (`drug_id`, `crew_type`, `output`, `duration`, `ingredients`) VALUES (?, ?, ?, ?, ?)', {
            id, lab.crewType, lab.output, lab.duration, json.encode(lab.ingredients),
        })
    end

    load()
    return { ok = true, silent = true, id = id }
end

Panel.actions['drugs.delete'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local drug = findDrug(data.id)

    if not drug then
        return Panel.fail('Drogue introuvable.')
    end

    local queries = { { query = 'DELETE FROM `lunatic_drugs` WHERE `id` = ?', values = { drug.id } } }

    for _, lab in ipairs(drug.labs) do
        queries[#queries + 1] = { query = 'DELETE FROM `lunatic_drug_lab_locations` WHERE `lab_id` = ?', values = { lab.id } }
    end

    queries[#queries + 1] = { query = 'DELETE FROM `lunatic_drug_labs` WHERE `drug_id` = ?', values = { drug.id } }
    MySQL.transaction.await(queries)
    load()
    Logs.add(src, 'drugs.delete', nil, { item = drug.item })

    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Actions : laboratoires et emplacements
---------------------------------------------------------------------

Panel.actions['drugs.saveLab'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local drug = findDrug(data.drugId)

    if not drug then
        return Panel.fail('Drogue introuvable.')
    end

    if not CREW_TYPES[data.crewType] then
        return Panel.fail('Type de crew inconnu.')
    end

    local output = whole(data.output, 1, 1000)
    local duration = whole(data.duration, 1, 600)
    local ingredients, err = readIngredients(data.ingredients)

    if not output or not duration then
        return Panel.fail('Quantité produite (1-1000) ou durée (1-600 s) invalide.')
    end

    if not ingredients then
        return Panel.fail(err)
    end

    local labId = tonumber(data.labId)

    if labId then
        local lab = findLab(labId)

        if not lab then
            return Panel.fail('Laboratoire introuvable.')
        end

        MySQL.update.await('UPDATE `lunatic_drug_labs` SET `crew_type` = ?, `output` = ?, `duration` = ?, `ingredients` = ? WHERE `id` = ?', { data.crewType, output, duration, json.encode(ingredients), labId })
    else
        MySQL.insert.await('INSERT INTO `lunatic_drug_labs` (`drug_id`, `crew_type`, `output`, `duration`, `ingredients`) VALUES (?, ?, ?, ?, ?)', { drug.id, data.crewType, output, duration, json.encode(ingredients) })
    end

    load()
    Logs.add(src, 'drugs.lab', nil, { item = drug.item, crewType = data.crewType, operation = labId and 'edit' or 'add' })

    return { ok = true, silent = true }
end

Panel.actions['drugs.deleteLab'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local lab, drug = findLab(data.labId)

    if not lab then
        return Panel.fail('Laboratoire introuvable.')
    end

    MySQL.transaction.await({
        { query = 'DELETE FROM `lunatic_drug_lab_locations` WHERE `lab_id` = ?', values = { lab.id } },
        { query = 'DELETE FROM `lunatic_drug_labs` WHERE `id` = ?', values = { lab.id } },
    })

    load()
    Logs.add(src, 'drugs.lab', nil, { item = drug.item, crewType = lab.crewType, operation = 'delete' })

    return { ok = true, silent = true }
end

Panel.actions['drugs.addLocation'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local lab = findLab(data.labId)
    local position = positionOf(src)

    if not lab or not position then
        return Panel.fail('Laboratoire introuvable.')
    end

    MySQL.insert.await('INSERT INTO `lunatic_drug_lab_locations` (`lab_id`, `x`, `y`, `z`, `h`) VALUES (?, ?, ?, ?, ?)', { lab.id, position.x, position.y, position.z, position.h })
    load()

    return { ok = true, silent = true }
end

Panel.actions['drugs.moveLocation'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local location = findLocation(data.locationId)
    local position = positionOf(src)

    if not location or not position then
        return Panel.fail('Emplacement introuvable.')
    end

    MySQL.update.await('UPDATE `lunatic_drug_lab_locations` SET `x` = ?, `y` = ?, `z` = ?, `h` = ? WHERE `id` = ?', { position.x, position.y, position.z, position.h, location.id })
    load()

    return { ok = true, silent = true }
end

Panel.actions['drugs.deleteLocation'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    MySQL.update.await('DELETE FROM `lunatic_drug_lab_locations` WHERE `id` = ?', { tonumber(data.locationId) or -1 })
    load()

    return { ok = true, silent = true }
end

Panel.actions['drugs.tpLocation'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local location = findLocation(data.locationId)

    if not location then
        return Panel.fail('Emplacement introuvable.')
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(location.x, location.y, location.z + 1.0))
    return { ok = true, silent = true }
end

-- Vue staff : affiche en jeu tous les points de laboratoire (lunatic_illegal), pour vérifier leur placement.
-- Les emplacements sont déjà dans GlobalState : rien de secret n'est envoyé.
Panel.actions['drugs.staffView'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    TriggerClientEvent('lunatic_illegal:staffView', src, data.enabled == true)
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Drogues chargé.')
