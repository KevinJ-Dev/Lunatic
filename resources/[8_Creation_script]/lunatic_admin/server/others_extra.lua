-- Tuile Autres (partie 3) : ascenseurs, objets de soin des médecins (Heal Items EMS) et tarifs custom du mécano.
--   - ascenseurs : table lunatic_elevators, GlobalState.lunaticElevators (jeu : lunatic_gameplay) ;
--   - objets de soin : KVP 'heal_items', GlobalState.lunaticHealItems (jeu : lunatic_gameplay) ;
--   - tarifs mécano : KVP 'mechanic_prices', export getMechanicPrice (pour le futur script de customisation).

local ox = exports.ox_inventory

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

local function allowed(actor)
    return Ranks.hasPermission(actor, 'others.manage')
end

local cleanText = Util.cleanText

local whole = Util.whole

local position = Util.position

local function jobExists(name)
    return name == '' or (ESX.GetJobs() or {})[name] ~= nil
end

local function jobsList()
    local jobs = {}

    for name, job in pairs(ESX.GetJobs() or {}) do
        jobs[#jobs + 1] = { name = name, label = job.label or name }
    end

    table.sort(jobs, function(a, b) return a.label < b.label end)
    return jobs
end

-- TP du staff sur une position d'une de ces pages
Panel.actions['others.tp'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local spot = position(data)

    if not spot then
        return Panel.fail('Position invalide.')
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(spot.x, spot.y, spot.z))
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Ascenseurs : étages reliés (nom, position), accès limité à un métier en option
---------------------------------------------------------------------

local elevators = {}

local function elevatorFromRow(row)
    local ok, floors = pcall(json.decode, row.floors or '[]')
    return { id = tonumber(row.id), label = row.label, job = row.job or '', active = tonumber(row.active) == 1 or row.active == true, floors = ok and type(floors) == 'table' and floors or {} }
end

local function publishElevators()
    local list = {}

    for _, elevator in pairs(elevators) do
        if elevator.active and #elevator.floors >= 2 then
            list[#list + 1] = elevator
        end
    end

    table.sort(list, function(a, b) return a.id < b.id end)
    GlobalState.lunaticElevators = list
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_elevators` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `label` VARCHAR(40) NOT NULL,
            `job` VARCHAR(50) NOT NULL DEFAULT '',
            `floors` TEXT NULL,
            `active` TINYINT NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    elevators = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_elevators`') or {}) do
        local elevator = elevatorFromRow(row)
        elevators[elevator.id] = elevator
    end

    publishElevators()
end)

Panel.actions['elevators.list'] = function(_, actor)
    if not allowed(actor) then
        return denied()
    end

    local list = {}

    for _, elevator in pairs(elevators) do
        list[#list + 1] = elevator
    end

    table.sort(list, function(a, b) return a.id < b.id end)
    return { ok = true, silent = true, elevators = list, jobs = jobsList() }
end

Panel.actions['elevators.save'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local id = tonumber(data.id)
    local existing = id and elevators[id]

    if id and not existing then
        return Panel.fail('Ascenseur introuvable.')
    end

    local label = cleanText(data.label, 2, 40)
    local job = type(data.job) == 'string' and data.job or ''

    if not label then
        return Panel.fail('Nom : de 2 à 40 caractères.')
    end

    if not jobExists(job) then
        return Panel.fail('Métier inconnu.')
    end

    local floors = {}

    if type(data.floors) ~= 'table' or #data.floors > 20 then
        return Panel.fail('20 étages au maximum.')
    end

    for index, floor in ipairs(data.floors) do
        local name = cleanText(floor.label, 1, 30)
        local spot = position(floor)

        if not name or not spot then
            return Panel.fail(('Étage n°%d : nom (1 à 30 caractères) et position requis.'):format(index))
        end

        floors[#floors + 1] = { label = name, x = spot.x, y = spot.y, z = spot.z, h = spot.h }
    end

    local values = { label, job, json.encode(floors), data.active == false and 0 or 1 }

    if existing then
        values[#values + 1] = id
        MySQL.update.await('UPDATE `lunatic_elevators` SET `label` = ?, `job` = ?, `floors` = ?, `active` = ? WHERE `id` = ?', values)
    else
        id = MySQL.insert.await('INSERT INTO `lunatic_elevators` (`label`, `job`, `floors`, `active`) VALUES (?, ?, ?, ?)', values)
    end

    elevators[id] = elevatorFromRow(MySQL.single.await('SELECT * FROM `lunatic_elevators` WHERE `id` = ?', { id }))
    publishElevators()

    Logs.add(src, existing and 'elevators.update' or 'elevators.create', label, { id = id, floors = #floors })
    return { ok = true, silent = true, id = id }
end

Panel.actions['elevators.delete'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local elevator = elevators[tonumber(data.id) or -1]

    if not elevator then
        return Panel.fail('Ascenseur introuvable.')
    end

    MySQL.update.await('DELETE FROM `lunatic_elevators` WHERE `id` = ?', { elevator.id })
    elevators[elevator.id] = nil
    publishElevators()

    Logs.add(src, 'elevators.delete', elevator.label, { id = elevator.id })
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Objets de soin (Heal Items EMS)
---------------------------------------------------------------------

local HEAL_TARGETS = { self = true, other = true, both = true }
local savedHeal = GetResourceKvpString('heal_items')
local healItems = savedHeal and json.decode(savedHeal) or {
    { item = 'bandage', heal = 25, armor = 0, revive = false, target = 'both', duration = 4, access = 'all', consume = true },
    { item = 'medikit', heal = 100, armor = 0, revive = true, target = 'other', duration = 8, access = 'medic', consume = true },
}

local function publishHeal()
    GlobalState.lunaticHealItems = healItems
end

publishHeal()

Panel.actions['healItems.list'] = function(_, actor)
    if not allowed(actor) then
        return denied()
    end

    return { ok = true, silent = true, items = healItems, jobs = jobsList() }
end

Panel.actions['healItems.save'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    if type(data.items) ~= 'table' or #data.items > 30 then
        return Panel.fail('30 objets de soin au maximum.')
    end

    local list, seen = {}, {}

    for index, entry in ipairs(data.items) do
        local heal, armor, duration = whole(entry.heal, 0, 100), whole(entry.armor, 0, 100), whole(entry.duration, 1, 60)
        local access = type(entry.access) == 'string' and entry.access or 'all'

        if type(entry.item) ~= 'string' or not ox:Items(entry.item) then
            return Panel.fail(('Objet de soin n°%d : objet inconnu.'):format(index))
        end

        if seen[entry.item] then
            return Panel.fail(("L'objet %s est en double."):format(entry.item))
        end

        if not heal or not armor or not duration then
            return Panel.fail(('%s : soin et armure de 0 à 100 %%, durée de 1 à 60 s.'):format(entry.item))
        end

        if not HEAL_TARGETS[entry.target] then
            return Panel.fail(('%s : cible invalide.'):format(entry.item))
        end

        if access ~= 'all' and access ~= 'medic' and not jobExists(access) then
            return Panel.fail(('%s : métier inconnu.'):format(entry.item))
        end

        seen[entry.item] = true
        list[#list + 1] = { item = entry.item, heal = heal, armor = armor, revive = entry.revive == true, target = entry.target, duration = duration, access = access, consume = entry.consume ~= false }
    end

    healItems = list
    SetResourceKvp('heal_items', json.encode(healItems))
    publishHeal()

    Logs.add(src, 'healItems.save', nil, { count = #list })
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Tarifs custom du mécano : par défaut, par classe GTA, par modèle (le plus précis l'emporte)
---------------------------------------------------------------------

local savedMechanic = GetResourceKvpString('mechanic_prices')
local mechanic = savedMechanic and json.decode(savedMechanic) or { default = {}, classes = {}, models = {} }

local function readPrices(value)
    local prices = {}

    for part, price in pairs(type(value) == 'table' and value or {}) do
        if type(part) == 'string' and part:match('^[%w_]+$') and #part <= 30 then
            local amount = whole(price, 0, 10000000)

            if not amount then
                return nil, ('Prix invalide pour « %s ».'):format(part)
            end

            prices[part] = amount
        end
    end

    return prices
end

Panel.actions['mechanic.get'] = function(_, actor)
    if not allowed(actor) then
        return denied()
    end

    return { ok = true, silent = true, prices = mechanic }
end

Panel.actions['mechanic.save'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local default, err = readPrices(data.default)

    if not default then
        return Panel.fail(err)
    end

    local classes, models = {}, {}

    for class, prices in pairs(type(data.classes) == 'table' and data.classes or {}) do
        local id = whole(class, 0, 22)
        local read, classError = readPrices(prices)

        if not id or not read then
            return Panel.fail(classError or 'Classe de véhicule invalide.')
        end

        if next(read) then
            classes[tostring(id)] = read
        end
    end

    local count = 0

    for model, prices in pairs(type(data.models) == 'table' and data.models or {}) do
        local name = type(model) == 'string' and model:lower():match('^[%w_]+$')
        local read, modelError = readPrices(prices)

        if not name or #name > 30 or not read then
            return Panel.fail(modelError or ('Modèle invalide : %s.'):format(tostring(model)))
        end

        count = count + 1

        if count > 200 then
            return Panel.fail('200 modèles au maximum.')
        end

        models[name] = read
    end

    mechanic = { default = default, classes = classes, models = models }
    SetResourceKvp('mechanic_prices', json.encode(mechanic))

    Logs.add(src, 'mechanic.save', nil, { models = count })
    return { ok = true, silent = true }
end

-- exports.lunatic_admin:getMechanicPrice('sultan', 4, 'engine') -> prix (modèle, sinon classe, sinon défaut)
exports('getMechanicPrice', function(model, class, part)
    model = type(model) == 'string' and model:lower() or ''
    local byModel = mechanic.models[model]
    local byClass = mechanic.classes[tostring(class)]

    return (byModel and byModel[part]) or (byClass and byClass[part]) or mechanic.default[part] or 0
end)

exports('getMechanicPrices', function()
    return json.decode(json.encode(mechanic))
end)

---------------------------------------------------------------------
-- Zone AFK : endroit où les joueurs vont avec /afk (et d'où ils reviennent), sans expulsion pour inactivité
---------------------------------------------------------------------

local AFK_DEFAULTS = { enabled = false, point = nil, radius = 30, command = true, autoSend = true, invincible = true, rewardAmount = 0, rewardMinutes = 15 }
local savedAfk = GetResourceKvpString('afk_zone')
local afkZone = savedAfk and json.decode(savedAfk) or json.decode(json.encode(AFK_DEFAULTS))

for key, value in pairs(AFK_DEFAULTS) do
    if afkZone[key] == nil and value ~= nil then
        afkZone[key] = value
    end
end

local function publishAfk()
    GlobalState.lunaticAfkZone = afkZone
end

publishAfk()

Panel.actions['afkZone.get'] = function(_, actor)
    if not allowed(actor) then
        return denied()
    end

    return { ok = true, silent = true, settings = afkZone, afk = { minutes = (GlobalState.lunaticFeatures and GlobalState.lunaticFeatures.misc or {}).afkMinutes } }
end

Panel.actions['afkZone.save'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local radius = whole(data.radius, 5, 300)
    local amount = whole(data.rewardAmount, 0, 100000)
    local minutes = whole(data.rewardMinutes, 1, 120)
    local point = data.point ~= nil and position(data.point) or nil

    if not radius or not amount or not minutes then
        return Panel.fail('Rayon (5 à 300 m), récompense (0 à 100000) ou intervalle (1 à 120 min) invalide.')
    end

    if data.point ~= nil and not point then
        return Panel.fail('Position de la zone invalide.')
    end

    if data.enabled == true and not point then
        return Panel.fail("Placez d'abord le point d'arrivée de la zone (« Ma position » en jeu).")
    end

    afkZone = {
        enabled = data.enabled == true, point = point, radius = radius, command = data.command ~= false, autoSend = data.autoSend == true,
        invincible = data.invincible ~= false, rewardAmount = amount, rewardMinutes = minutes,
    }

    SetResourceKvp('afk_zone', json.encode(afkZone))
    publishAfk()

    Logs.add(src, 'afkZone.save', nil, { enabled = afkZone.enabled })
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Création perso : lieux d'apparition et visuels du créateur de personnage (KVP 'creator_settings',
-- GlobalState.lunaticCreator, lu par lunatic_creator). Sans lieu réglé ici, ceux de sa config servent.
---------------------------------------------------------------------

local CREATOR_SPAWNS_MAX = 20
local savedCreator = GetResourceKvpString('creator_settings')
local creatorSettings = savedCreator and json.decode(savedCreator) or { showBanner = true, showLogo = true, spawns = {} }

local function publishCreator()
    GlobalState.lunaticCreator = creatorSettings
end

publishCreator()

local function creatorDefaultSpawns()
    if GetResourceState('lunatic_creator') ~= 'started' then
        return {}
    end

    local ok, list = pcall(function() return exports.lunatic_creator:getDefaultSpawns() end)
    return ok and type(list) == 'table' and list or {}
end

Panel.actions['creator.get'] = function(_, actor)
    if not allowed(actor) then
        return denied()
    end

    return { ok = true, silent = true, settings = creatorSettings, defaults = creatorDefaultSpawns() }
end

-- Modèle de lien des images de vêtements : vide, lien https ou chemin html/clothes/ de lunatic_creator, avec {drawable}
local function imageTemplate(value)
    local text = Util.cleanTextOrEmpty(value, 0, 300)

    if text == '' then
        return ''
    end

    if not text or not text:find('{drawable}', 1, true) then
        return nil
    end

    if text:match('^https://') or (text:match('^clothes/') and not text:find('..', 1, true)) then
        return text
    end

    return nil
end

Panel.actions['creator.save'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    if type(data) ~= 'table' or type(data.spawns) ~= 'table' then
        return Panel.fail('Réglages invalides.')
    end

    if #data.spawns > CREATOR_SPAWNS_MAX then
        return Panel.fail(("%d lieux d'apparition au maximum."):format(CREATOR_SPAWNS_MAX))
    end

    local spawns = {}

    for index, spawn in ipairs(data.spawns) do
        local label = type(spawn) == 'table' and cleanText(spawn.label, 2, 40)
        local group = type(spawn) == 'table' and cleanText(spawn.group, 2, 30)
        local point = type(spawn) == 'table' and position(spawn)
        local image = type(spawn) == 'table' and Util.cleanTextOrEmpty(spawn.image, 0, 300)

        if not label or not group then
            return Panel.fail(('Lieu %d : nom (2 à 40 caractères) et groupe (2 à 30) obligatoires.'):format(index))
        elseif not point then
            return Panel.fail(('Lieu %d : position invalide (« Définir position » en jeu).'):format(index))
        elseif not image or (image ~= '' and not image:match('^https://') and not image:match('^nui://')) then
            return Panel.fail(('Lieu %d : image invalide (lien https:// ou nui://).'):format(index))
        end

        spawns[#spawns + 1] = { label = label, group = group, x = point.x, y = point.y, z = point.z, h = point.h, image = image, enabled = spawn.enabled ~= false }
    end

    local active = 0

    for _, spawn in ipairs(spawns) do
        if spawn.enabled then
            active = active + 1
        end
    end

    if #spawns > 0 and active == 0 then
        return Panel.fail("Activez au moins un lieu d'apparition.")
    end

    local images = type(data.clothesImages) == 'table' and data.clothesImages or {}
    local component, prop = imageTemplate(images.component), imageTemplate(images.prop)

    if not component or not prop then
        return Panel.fail('Images des vêtements : lien https:// ou chemin clothes/…, contenant {drawable}.')
    end

    creatorSettings = {
        showBanner = data.showBanner ~= false, showLogo = data.showLogo ~= false, spawns = spawns,
        clothesImages = { component = component, prop = prop },
    }
    SetResourceKvp('creator_settings', json.encode(creatorSettings))
    publishCreator()

    Logs.add(src, 'creator.save', nil, { spawns = #spawns })
    return { ok = true, silent = true }
end

-- Outil photo : le personnage du staff prend chaque style du créateur pour en faire les miniatures
Panel.actions['creator.photos'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local sex = type(data) == 'table' and (data.sex == 'female' and 'female' or data.sex == 'male' and 'male') or nil

    if not sex then
        return Panel.fail('Choisissez homme ou femme.')
    end

    if GetResourceState('lunatic_creator') ~= 'started' then
        return Panel.fail("lunatic_creator n'est pas démarré.")
    end

    local ok, started = pcall(function() return exports.lunatic_creator:startPhotoSession(src, sex) end)

    if not ok or not started then
        return Panel.fail('Séance photo impossible (déjà en création de personnage ?).')
    end

    Logs.add(src, 'creator.photos', nil, { sex = sex })
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Hôpitaux : réveil après l'inconscience au plus proche (KVP 'hospitals', GlobalState.lunaticHospitals,
-- lu par lunatic_gameplay). Sans hôpital actif ici, ceux de sa config servent.
---------------------------------------------------------------------

local HOSPITALS_MAX = 20
local savedHospitals = GetResourceKvpString('hospitals')
local hospitalList = savedHospitals and json.decode(savedHospitals) or {}

local function publishHospitals()
    GlobalState.lunaticHospitals = hospitalList
end

publishHospitals()

local function defaultHospitals()
    if GetResourceState('lunatic_gameplay') ~= 'started' then
        return {}
    end

    local ok, list = pcall(function() return exports.lunatic_gameplay:getDefaultHospitals() end)
    return ok and type(list) == 'table' and list or {}
end

Panel.actions['hospitals.get'] = function(_, actor)
    if not allowed(actor) then
        return denied()
    end

    return { ok = true, silent = true, hospitals = hospitalList, defaults = defaultHospitals() }
end

Panel.actions['hospitals.save'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    if type(data) ~= 'table' or type(data.hospitals) ~= 'table' or #data.hospitals > HOSPITALS_MAX then
        return Panel.fail(('Hôpitaux : %d au maximum.'):format(HOSPITALS_MAX))
    end

    local list, active = {}, 0

    for index, hospital in ipairs(data.hospitals) do
        local label = type(hospital) == 'table' and cleanText(hospital.label, 2, 40)
        local point = type(hospital) == 'table' and position(hospital)

        if not label then
            return Panel.fail(('Hôpital %d : nom de 2 à 40 caractères.'):format(index))
        elseif not point then
            return Panel.fail(('Hôpital %d : position invalide (« Définir position » en jeu).'):format(index))
        end

        local enabled = hospital.enabled ~= false
        active = active + (enabled and 1 or 0)
        list[#list + 1] = { label = label, x = point.x, y = point.y, z = point.z, h = point.h, enabled = enabled }
    end

    if #list > 0 and active == 0 then
        return Panel.fail('Activez au moins un hôpital.')
    end

    hospitalList = list
    SetResourceKvp('hospitals', json.encode(hospitalList))
    publishHospitals()

    Logs.add(src, 'hospitals.save', nil, { count = #list })
    return { ok = true, silent = true }
end

print('[lunatic_admin] Modules Ascenseurs, Heal Items, Tarifs mécano, Zone AFK, Création perso et Hôpitaux chargés.')
