-- Illégal : braquages de magasins avec un PNJ au comptoir (tuile Illégal, page Braquages).
-- Ici : les points (type, label, modèle du PNJ, position, entreprise), les points par défaut des magasins
-- de la carte, le TP et les réglages de chaque type (arme exigée, durée, délai, alarme, résistance, butin).
-- Les réglages communs (statut, policiers, gain, XP, influence, level) sont ceux de la page Missions (heist_<type>).
-- Le braquage en jeu (PNJ menacé, sac, alarme) est dans lunatic_illegal.

local TYPES = {
    store = { label = 'Supérette', short = 'SUP', ped = 'mp_m_shopkeep_01' },
    barber = { label = 'Barber', short = 'BARBER', ped = 's_f_m_fembarber' },
    binco = { label = 'Binco', short = 'BINCO', ped = 's_f_y_shop_low' },
    ammunation = { label = 'Ammunation', short = 'AMMU', ped = 's_m_y_ammucity_01' },
    tattoo = { label = 'Tattoo', short = 'TATTOO', ped = 'u_m_y_tattoo_01' },
    heliwave = { label = 'Heliwave', short = 'HELI', ped = 's_m_y_airworker', soon = true },
    -- Cambriolage : la porte d'une maison (pas de PNJ), avec l'intérieur où l'on entre (lunatic_illegal, Config.BurglaryInteriors)
    house = { label = 'Maison', short = 'MAISON', ped = '', house = true },
    company = { label = 'Entreprise', short = 'ENTR', ped = 'a_m_y_business_02' },
}
local ORDER = { 'store', 'barber', 'binco', 'ammunation', 'tattoo', 'company', 'house', 'heliwave' }
local INTERIORS = { low = 'Petit appartement', mid = 'Appartement moyen' }

-- Réglages par type, selon la difficulté : arme en main exigée (any = blanche ou à feu, jamais les poings),
-- durée pour remplir le sac (s), délai avant de rebraquer le même point (min), alarme silencieuse (%),
-- résistance du vendeur face à une arme blanche (%), butin en objets en plus du gain (page Missions)
local DEFAULT_SETTINGS = {
    store = { weapon = 'any', duration = 30, cooldown = 45, alert = 50, resist = 25, loot = {} },
    barber = { weapon = 'any', duration = 25, cooldown = 45, alert = 40, resist = 25, loot = {} },
    binco = { weapon = 'any', duration = 25, cooldown = 45, alert = 40, resist = 25, loot = {} },
    tattoo = { weapon = 'any', duration = 25, cooldown = 45, alert = 40, resist = 30, loot = {} },
    ammunation = { weapon = 'firearm', duration = 40, cooldown = 90, alert = 100, resist = 40, loot = {} },
    company = { weapon = 'firearm', duration = 35, cooldown = 60, alert = 80, resist = 20, loot = {} },
    heliwave = { weapon = 'firearm', duration = 40, cooldown = 90, alert = 80, resist = 20, loot = {} },
    house = { weapon = 'any', duration = 0, cooldown = 0, alert = 0, resist = 0, loot = {} }, -- réglages : page Missions → Cambriolage
}
local WEAPONS = { any = true, melee = true, firearm = true }

-- Magasins de la carte de base : position du vendeur derrière le comptoir (à vérifier en jeu avec le TP)
local DEFAULT_POINTS = {
    -- Maisons : position devant la porte, tourné vers elle ; 6e valeur : intérieur
    house = {
        { 'Maison Forum Drive', -14.3, -1441.0, 31.1, 0.0, 'low' }, { 'Maison Grove Street', 126.7, -1930.1, 21.4, 210.0, 'low' },
        { 'Maison Grove Street (2)', 114.3, -1961.2, 21.3, 200.0, 'low' }, { 'Maison Grove Street (3)', 85.7, -1959.4, 21.1, 230.0, 'low' },
        { 'Maison Chamberlain Hills', -147.5, -1596.4, 34.8, 50.0, 'low' }, { 'Maison El Burro Heights', 1273.9, -1719.5, 54.8, 30.0, 'low' },
        { 'Maison Mirror Park', 1060.6, -378.4, 68.2, 40.0, 'mid' }, { 'Maison Mirror Park (2)', 1100.9, -411.4, 67.6, 80.0, 'mid' },
        { 'Maison Mirror Park (3)', 1250.5, -515.4, 69.3, 75.0, 'mid' }, { 'Appartement Vespucci Beach', -1150.8, -1520.7, 10.6, 35.0, 'low' },
        { 'Villa Rockford Hills', -816.7, 178.0, 72.2, 110.0, 'mid' }, { 'Villa Vinewood Hills', 7.7, 538.6, 176.0, 155.0, 'mid' },
        { 'Caravane Sandy Shores', 1973.3, 3815.9, 33.4, 300.0, 'low' }, { 'Maison Paleto Bay', -360.3, 6260.7, 31.5, 315.0, 'low' },
        { 'Ferme Grapeseed', 1662.0, 4776.0, 42.0, 280.0, 'low' },
    },
    store = {
        { 'Supérette Innocence Blvd', 24.5, -1346.6, 29.5, 271.0 }, { 'Supérette Clinton Ave', 372.5, 326.4, 103.6, 255.0 },
        { 'Supérette Palomino Fwy', 2557.4, 380.8, 108.6, 355.0 }, { 'Supérette Sandy Shores', 1959.8, 3740.1, 32.3, 300.0 },
        { 'Supérette Route 68', 549.1, 2669.9, 42.2, 99.0 }, { 'Supérette Senora Fwy', 2677.0, 3279.5, 55.2, 333.0 },
        { 'Supérette Mont Chiliad', 1728.6, 6416.8, 35.0, 247.0 }, { 'Supérette Barbareno Rd', -3242.9, 1000.0, 12.8, 357.0 },
        { 'Supérette Ineseno Rd', -3040.0, 584.0, 7.9, 17.0 }, { 'LTD Grove Street', -46.7, -1757.9, 29.4, 47.0 },
        { 'LTD Mirror Park', 1164.9, -323.6, 69.2, 100.0 }, { 'LTD Little Seoul', -706.1, -914.5, 19.2, 89.0 },
        { 'LTD Richman Glen', -1820.0, 794.5, 138.1, 130.0 }, { 'LTD Grapeseed', 1697.9, 4923.0, 42.1, 324.0 },
        { "Rob's Liquor Vespucci", -1221.9, -908.3, 12.3, 31.0 }, { "Rob's Liquor Morningwood", -1486.3, -377.6, 40.2, 133.0 },
        { "Rob's Liquor El Rancho", 1134.3, -982.5, 46.4, 275.0 }, { "Rob's Liquor Chumash", -2966.4, 391.0, 15.0, 88.0 },
        { 'Scoops Liquor Route 68', 1165.9, 2710.8, 38.2, 179.0 }, { 'Liquor Ace Sandy Shores', 1392.7, 3606.4, 35.0, 201.0 },
    },
    barber = {
        { 'Herr Kutz Davis', 134.6, -1707.9, 29.3, 140.0 }, { 'Herr Kutz Mirror Park', 1211.5, -470.6, 66.2, 70.0 },
        { 'Herr Kutz Paleto Bay', -277.9, 6230.5, 31.7, 50.0 }, { "O'Sheas Sandy Shores", 1930.9, 3728.1, 32.8, 210.0 },
        { 'Bob Mulet Rockford Hills', -813.4, -183.7, 37.6, 120.0 }, { 'Beachcombover Vespucci', -1284.2, -1115.3, 7.0, 90.0 },
        { 'Hair on Hawick', -30.7, -151.6, 57.1, 340.0 },
    },
    binco = {
        { 'Binco Textile City', 427.1, -806.0, 29.5, 90.0 }, { 'Binco Vespucci Canals', -823.1, -1072.3, 11.3, 210.0 },
        { 'Discount Store Strawberry', 73.9, -1392.9, 29.4, 270.0 }, { 'Discount Store Paleto Bay', 5.8, 6511.3, 31.9, 40.0 },
        { 'Discount Store Grapeseed', 1695.4, 4823.0, 42.1, 100.0 }, { 'Discount Store Route 68', 1196.6, 2711.6, 38.2, 180.0 },
    },
    ammunation = {
        { 'Ammunation Pillbox Hill', 22.1, -1107.3, 29.8, 160.0 }, { 'Ammunation Cypress Flats', 810.1, -2158.9, 29.6, 358.0 },
        { 'Ammunation Hawick', 253.7, -50.5, 69.9, 70.0 }, { 'Ammunation La Mesa', 842.4, -1035.3, 28.2, 0.0 },
        { 'Ammunation Little Seoul', -661.9, -933.5, 21.8, 180.0 }, { 'Ammunation Morningwood', -1303.9, -394.6, 36.7, 75.0 },
        { 'Ammunation Chumash', -3173.5, 1088.3, 20.8, 250.0 }, { 'Ammunation Sandy Shores', 1692.6, 3761.4, 34.7, 230.0 },
        { 'Ammunation Palomino Fwy', 2567.9, 292.5, 108.7, 0.0 }, { 'Ammunation Paleto Bay', -331.6, 6085.0, 31.5, 225.0 },
        { 'Ammunation Route 68', -1118.5, 2699.5, 18.6, 220.0 },
    },
    tattoo = {
        { 'Tattoo Vinewood', 319.8, 181.0, 103.6, 250.0 }, { 'Tattoo Vespucci', -1152.4, -1424.1, 5.0, 30.0 },
        { 'Tattoo Sandy Shores', 1862.6, 3748.4, 33.0, 30.0 }, { 'Tattoo Paleto Bay', -292.0, 6199.9, 31.5, 225.0 },
        { 'Tattoo Chumash', -3170.6, 1073.1, 20.8, 250.0 }, { 'Tattoo El Burro Heights', 1324.7, -1650.0, 52.3, 130.0 },
    },
}

-- Hauteur inconnue (point placé sur la carte du panel) : le TP cherche le sol ; « Définir » en jeu donne la vraie hauteur
local UNKNOWN_Z = -200.0
local LIMITS = { points = 300, duration = 180, cooldown = 1440, loot = 8 }

local points, settings = {}, {}

local ox = exports.ox_inventory

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer l'illégal.")
end

local function guard(actor)
    return Ranks.hasPermission(actor, 'illegal.manage')
end

local function positionOf(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z - 0.98, h = GetEntityHeading(ped) }
end

-- Position cliquée sur la carte du panel (x / y dans la zone jouable)
local function mapPosition(data)
    local x, y = tonumber(data.x), tonumber(data.y)

    if not x or not y or x < -5000 or x > 5000 or y < -5000 or y > 9000 then
        return nil
    end

    return { x = x, y = y }
end

local function cleanText(value, max)
    local text = type(value) == 'string' and value:gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    return #text <= max and text or nil
end

local function loadSettings()
    settings = {}

    for typeId, defaults in pairs(DEFAULT_SETTINGS) do
        settings[typeId] = json.decode(json.encode(defaults))
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_holdup_settings`') or {}) do
        local ok, value = pcall(json.decode, row.settings or '')

        if ok and type(value) == 'table' and settings[row.type] then
            for key, default in pairs(DEFAULT_SETTINGS[row.type]) do
                if value[key] == nil then
                    value[key] = default
                end
            end

            settings[row.type] = value
        end
    end
end

local function load()
    points = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_holdups` ORDER BY `id`') or {}) do
        if TYPES[row.type] then
            points[#points + 1] = {
                id = tonumber(row.id), type = row.type, label = row.label, ped = row.ped, company = row.company ~= '' and row.company or nil,
                interior = INTERIORS[row.interior] and row.interior or 'low',
                x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h),
                -- TINYINT(1) : oxmysql le renvoie en booléen
                active = row.active == true or tonumber(row.active) == 1,
            }
        end
    end

    -- lunatic_illegal recharge les PNJ des magasins
    TriggerEvent('lunatic_admin:holdupsChanged')
end

local function findPoint(id)
    for _, point in ipairs(points) do
        if point.id == tonumber(id) then
            return point
        end
    end
end

-- Ajoute les points par défaut absents (même type et même nom), d'un seul type si demandé ; renvoie le nombre ajouté
local function seed(onlyType)
    local known, created = {}, 0

    for _, point in ipairs(points) do
        known[point.type .. ':' .. point.label] = true
    end

    for typeId, list in pairs(DEFAULT_POINTS) do
        for _, entry in ipairs(list) do
            if (not onlyType or typeId == onlyType) and not known[typeId .. ':' .. entry[1]] then
                MySQL.insert.await('INSERT INTO `lunatic_holdups` (`type`, `label`, `ped`, `x`, `y`, `z`, `h`, `interior`, `active`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)', {
                    typeId, entry[1], TYPES[typeId].ped, entry[2], entry[3], entry[4], entry[5], entry[6] or '',
                })
                created = created + 1
            end
        end
    end

    return created
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_holdups` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `type` VARCHAR(20) NOT NULL,
            `label` VARCHAR(60) NOT NULL,
            `ped` VARCHAR(40) NOT NULL,
            `company` VARCHAR(50) NULL DEFAULT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `h` DOUBLE NOT NULL DEFAULT 0,
            `active` TINYINT(1) NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_holdups_type` (`type`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Cambriolage : intérieur où mène la porte d'une maison
    MySQL.query.await("ALTER TABLE `lunatic_holdups` ADD COLUMN IF NOT EXISTS `interior` VARCHAR(20) NOT NULL DEFAULT ''")

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_holdup_settings` (
            `type` VARCHAR(20) NOT NULL,
            `settings` TEXT NOT NULL,
            PRIMARY KEY (`type`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    loadSettings()
    load()

    -- Premier démarrage : les magasins de la carte sont placés d'office ; les maisons (ajoutées plus tard) une fois aussi
    local created = 0

    if not GetResourceKvpString('holdups_seeded') then
        SetResourceKvp('holdups_seeded', '1')
        SetResourceKvp('holdups_houses_seeded', '1')
        created = seed()
    elseif not GetResourceKvpString('holdups_houses_seeded') then
        SetResourceKvp('holdups_houses_seeded', '1')
        created = seed('house')
    end

    if created > 0 then
        load()
    end
end)

-- Points et types lus par lunatic_illegal (serveur) : réglages du type + réglages communs de la mission
exports('getHoldupConfig', function()
    local types = {}

    for id, entry in pairs(TYPES) do
        local mission = Missions.get('heist_' .. id)
        types[id] = {
            label = entry.label, soon = entry.soon == true, settings = settings[id],
            mission = mission and {
                id = 'heist_' .. id, enabled = mission.enabled, police = mission.bypass and 0 or mission.police, levelRequired = mission.levelRequired,
                minLevel = mission.minLevel, xp = mission.xp, influence = mission.influence, reward = mission.reward,
            } or nil,
        }
    end

    return { types = types, points = points }
end)

-- Hauteur du sol d'un point placé sur la carte, mesurée en jeu par un joueur proche (lunatic_illegal)
exports('setHoldupGround', function(id, z)
    local point = findPoint(id)
    z = tonumber(z)

    if not point or point.z > -100.0 or not z or z < -100.0 or z > 1500.0 then
        return false
    end

    MySQL.update.await('UPDATE `lunatic_holdups` SET `z` = ? WHERE `id` = ?', { z, point.id })
    load()
    return true
end)

-- Points d'un type (fiches de la page Missions)
Holdups = {}

function Holdups.points(typeId)
    local list = {}

    for _, point in ipairs(points) do
        if point.type == typeId then
            list[#list + 1] = point
        end
    end

    return list
end

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

-- Entreprises du panel (un point de braquage par entreprise, activable une par une)
local function companies()
    local list = {}

    for name, job in pairs(ESX.GetJobs()) do
        local structure = Structures.get(name)

        if structure and structure.kind == 'company' then
            list[#list + 1] = { job = name, label = job.label }
        end
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

Panel.actions['holdups.list'] = function(_, actor)
    if not guard(actor) then
        return denied()
    end

    local types = {}

    for _, id in ipairs(ORDER) do
        local entry = TYPES[id]
        local s = json.decode(json.encode(settings[id]))

        for _, loot in ipairs(s.loot or {}) do
            local item = ox:Items(loot.item)
            loot.label, loot.missing = item and item.label or loot.item, not item
        end

        types[#types + 1] = { id = id, label = entry.label, short = entry.short, ped = entry.ped, soon = entry.soon == true, house = entry.house == true, settings = s }
    end

    local interiors = {}

    for key, label in pairs(INTERIORS) do
        interiors[#interiors + 1] = { id = key, label = label }
    end

    table.sort(interiors, function(a, b) return a.id < b.id end)
    return { ok = true, silent = true, types = types, points = points, companies = companies(), interiors = interiors }
end

Panel.actions['holdups.save'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local typeId = TYPES[data.type] and data.type
    local label = cleanText(data.label, 60)
    local ped = cleanText(data.ped, 40)
    local company = '' -- jamais nil : oxmysql refuse nil au milieu des paramètres

    if not typeId then
        return Panel.fail('Type de braquage inconnu.')
    end

    if not label or #label < 2 then
        return Panel.fail('Le label doit faire entre 2 et 60 caractères.')
    end

    local interior = ''

    -- Maison : pas de PNJ, mais un intérieur
    if TYPES[typeId].house then
        ped = ''
        interior = INTERIORS[data.interior] and data.interior or nil

        if not interior then
            return Panel.fail("Choisissez l'intérieur de la maison.")
        end
    elseif not ped or not ped:match('^[%w_]+$') then
        return Panel.fail('Modèle du PNJ : lettres, chiffres et _ uniquement (ex. mp_m_shopkeep_01).')
    end

    if typeId == 'company' then
        company = type(data.company) == 'string' and data.company or ''
        local structure = Structures.get(company)

        if not structure or structure.kind ~= 'company' then
            return Panel.fail("Choisissez l'entreprise braquée.")
        end
    end

    local placed = nil

    if data.x ~= nil or data.y ~= nil then
        placed = mapPosition(data)

        if not placed then
            return Panel.fail('Position sur la carte invalide.')
        end
    end

    local active = data.active ~= false
    local id = nil

    if data.id then
        local point = findPoint(data.id)

        if not point then
            return Panel.fail('Point introuvable.')
        end

        MySQL.update.await('UPDATE `lunatic_holdups` SET `type` = ?, `label` = ?, `ped` = ?, `company` = ?, `interior` = ?, `active` = ? WHERE `id` = ?', {
            typeId, label, ped, company, interior, active and 1 or 0, point.id,
        })

        if placed then
            MySQL.update.await('UPDATE `lunatic_holdups` SET `x` = ?, `y` = ?, `z` = ? WHERE `id` = ?', { placed.x, placed.y, UNKNOWN_Z, point.id })
        end

        id = point.id
    else
        if #points >= LIMITS.points then
            return Panel.fail(('Maximum %d points de braquage.'):format(LIMITS.points))
        end

        local position = positionOf(src)

        if placed then
            position = { x = placed.x, y = placed.y, z = UNKNOWN_Z, h = 0.0 }
        end

        if not position then
            return Panel.fail('Position introuvable.')
        end

        id = MySQL.insert.await('INSERT INTO `lunatic_holdups` (`type`, `label`, `ped`, `company`, `interior`, `x`, `y`, `z`, `h`, `active`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            typeId, label, ped, company, interior, position.x, position.y, position.z, position.h, active and 1 or 0,
        })
    end

    load()
    Logs.add(src, 'holdups.save', nil, { label = label, operation = data.id and 'edit' or 'add' })

    return { ok = true, silent = true, id = id }
end

-- Réglages d'un type de braquage (arme, durée, délai, alarme, résistance, butin)
Panel.actions['holdups.saveSettings'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local typeId = TYPES[data.type] and data.type
    local input = type(data.settings) == 'table' and data.settings or {}

    if not typeId then
        return Panel.fail('Type de braquage inconnu.')
    end

    local whole = function(value, min, max)
        local n = tonumber(value)
        return n and n == math.floor(n) and n >= min and n <= max and math.floor(n) or nil
    end

    local value = {
        weapon = WEAPONS[input.weapon] and input.weapon or nil,
        duration = whole(input.duration, 5, LIMITS.duration),
        cooldown = whole(input.cooldown, 5, LIMITS.cooldown),
        alert = whole(input.alert, 0, 100),
        resist = whole(input.resist, 0, 100),
        loot = {},
    }

    if not value.weapon then
        return Panel.fail('Arme exigée : choisissez une option.')
    end

    if not value.duration or not value.cooldown or not value.alert or not value.resist then
        return Panel.fail(('Durée (5 à %d s), délai (5 à %d min), alarme et résistance (0 à 100 %%) requis.'):format(LIMITS.duration, LIMITS.cooldown))
    end

    if type(input.loot) ~= 'table' or #input.loot > LIMITS.loot then
        return Panel.fail(('Butin : %d objets maximum.'):format(LIMITS.loot))
    end

    for _, entry in ipairs(input.loot) do
        local min, max, chance = whole(entry.min, 1, 1000), whole(entry.max, 1, 1000), whole(entry.chance, 1, 100)

        if type(entry.item) ~= 'string' or not ox:Items(entry.item) or not min or not max or not chance or min > max then
            return Panel.fail(('Butin invalide : %s.'):format(tostring(entry.item)))
        end

        value.loot[#value.loot + 1] = { item = entry.item, min = min, max = max, chance = chance }
    end

    settings[typeId] = value
    MySQL.update.await('INSERT INTO `lunatic_holdup_settings` (`type`, `settings`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `settings` = VALUES(`settings`)', { typeId, json.encode(value) })
    TriggerEvent('lunatic_admin:holdupsChanged')
    Logs.add(src, 'holdups.save', nil, { label = TYPES[typeId].label, operation = 'settings' })

    return { ok = true, silent = true }
end

-- PNJ replacé à la position et dans la direction du staff
Panel.actions['holdups.move'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findPoint(data.id)
    local position = positionOf(src)

    if not point or not position then
        return Panel.fail(point and 'Position introuvable.' or 'Point introuvable.')
    end

    MySQL.update.await('UPDATE `lunatic_holdups` SET `x` = ?, `y` = ?, `z` = ?, `h` = ? WHERE `id` = ?', { position.x, position.y, position.z, position.h, point.id })
    load()
    Logs.add(src, 'holdups.save', nil, { label = point.label, operation = 'move' })

    return { ok = true, silent = true }
end

Panel.actions['holdups.tp'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findPoint(data.id)

    if not point then
        return Panel.fail('Point introuvable.')
    end

    -- Devant le comptoir, face au vendeur ; maison : devant la porte (hauteur inconnue : le client cherche le sol)
    local heading = math.rad(point.h or 0.0)
    local x, y = point.x - math.sin(heading) * 1.5, point.y + math.cos(heading) * 1.5

    if TYPES[point.type] and TYPES[point.type].house then
        x, y = point.x, point.y
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(x, y, point.z + (point.z > -100.0 and 1.0 or 0.0)))
    return { ok = true, silent = true }
end

Panel.actions['holdups.delete'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local point = findPoint(data.id)

    if not point then
        return Panel.fail('Point introuvable.')
    end

    MySQL.update.await('DELETE FROM `lunatic_holdups` WHERE `id` = ?', { point.id })
    load()
    Logs.add(src, 'holdups.save', nil, { label = point.label, operation = 'delete' })

    return { ok = true, silent = true }
end

-- Remet les magasins de la carte de base qui manquent
Panel.actions['holdups.seed'] = function(src, actor)
    if not guard(actor) then
        return denied()
    end

    local created = seed()
    load()
    Logs.add(src, 'holdups.save', nil, { label = ('%d magasin(s) de la carte'):format(created), operation = 'add' })

    return { ok = true, silent = true, created = created }
end
