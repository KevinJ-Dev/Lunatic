-- Illégal : braquages de magasins avec un PNJ au comptoir (tuile Illégal, page Braquages).
-- Ici : les points (type, label, modèle du PNJ, position, entreprise), les points par défaut des magasins
-- de la carte et le TP. Les réglages communs sont ceux de la page Missions (heist_<type>).
-- Le braquage en jeu (PNJ menacé, sac, alarme) est dans lunatic_illegal.

local TYPES = {
    store = { label = 'Supérette', short = 'SUP', ped = 'mp_m_shopkeep_01' },
    barber = { label = 'Barber', short = 'BARBER', ped = 's_f_m_fembarber' },
    binco = { label = 'Binco', short = 'BINCO', ped = 's_f_y_shop_low' },
    ammunation = { label = 'Ammunation', short = 'AMMU', ped = 's_m_y_ammucity_01' },
    tattoo = { label = 'Tattoo', short = 'TATTOO', ped = 'u_m_y_tattoo_01' },
    heliwave = { label = 'Heliwave', short = 'HELI', ped = 's_m_y_airworker', soon = true },
    company = { label = 'Entreprise', short = 'ENTR', ped = 'a_m_y_business_02' },
}
local ORDER = { 'store', 'barber', 'binco', 'ammunation', 'tattoo', 'company', 'heliwave' }

-- Magasins de la carte de base : position du vendeur derrière le comptoir (à vérifier en jeu avec le TP)
local DEFAULT_POINTS = {
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
local LIMITS = { points = 300 }

local points = {}

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

local function load()
    points = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_holdups` ORDER BY `id`') or {}) do
        if TYPES[row.type] then
            points[#points + 1] = {
                id = tonumber(row.id), type = row.type, label = row.label, ped = row.ped, company = row.company ~= '' and row.company or nil,
                x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h), active = tonumber(row.active) == 1,
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

-- Ajoute les magasins de la carte absents (même type et même nom) ; renvoie le nombre ajouté
local function seed()
    local known, created = {}, 0

    for _, point in ipairs(points) do
        known[point.type .. ':' .. point.label] = true
    end

    for typeId, list in pairs(DEFAULT_POINTS) do
        for _, entry in ipairs(list) do
            if not known[typeId .. ':' .. entry[1]] then
                MySQL.insert.await('INSERT INTO `lunatic_holdups` (`type`, `label`, `ped`, `x`, `y`, `z`, `h`, `active`) VALUES (?, ?, ?, ?, ?, ?, ?, 1)', {
                    typeId, entry[1], TYPES[typeId].ped, entry[2], entry[3], entry[4], entry[5],
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

    load()

    -- Premier démarrage : les magasins de la carte sont placés d'office
    if not GetResourceKvpString('holdups_seeded') then
        SetResourceKvp('holdups_seeded', '1')

        if seed() > 0 then
            load()
        end
    end
end)

-- Points et types lus par lunatic_illegal (serveur)
exports('getHoldupConfig', function()
    local types = {}

    for id, entry in pairs(TYPES) do
        types[id] = { label = entry.label, soon = entry.soon == true }
    end

    return { types = types, points = points }
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
        types[#types + 1] = { id = id, label = entry.label, short = entry.short, ped = entry.ped, soon = entry.soon == true }
    end

    return { ok = true, silent = true, types = types, points = points, companies = companies() }
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

    if not ped or not ped:match('^[%w_]+$') then
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

        MySQL.update.await('UPDATE `lunatic_holdups` SET `type` = ?, `label` = ?, `ped` = ?, `company` = ?, `active` = ? WHERE `id` = ?', {
            typeId, label, ped, company, active and 1 or 0, point.id,
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

        id = MySQL.insert.await('INSERT INTO `lunatic_holdups` (`type`, `label`, `ped`, `company`, `x`, `y`, `z`, `h`, `active`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            typeId, label, ped, company, position.x, position.y, position.z, position.h, active and 1 or 0,
        })
    end

    load()
    Logs.add(src, 'holdups.save', nil, { label = label, operation = data.id and 'edit' or 'add' })

    return { ok = true, silent = true, id = id }
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

    -- Devant le comptoir, face au vendeur (hauteur inconnue : le client cherche le sol)
    local heading = math.rad(point.h or 0.0)
    local x, y = point.x - math.sin(heading) * 1.5, point.y + math.cos(heading) * 1.5

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
