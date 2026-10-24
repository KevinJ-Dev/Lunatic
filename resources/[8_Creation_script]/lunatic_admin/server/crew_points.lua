-- Crews, infrastructure : positions (stockage commun, stockage séparé, garage) et propriétés (planques).
-- Placées depuis le panel (tuile Crews, colonne Infrastructure) à la position du staff ; utilisées en jeu par lunatic_illegal
-- (client/crewpoints.lua), qui reçoit seulement les points de son crew (export getCrewPoints) et revérifie tout.
-- Coffres ox_inventory : « crew_<crew> » (commun), « crew_<crew>_p<point> » (séparé), « crew_<crew>_h<point> » (planque).

CrewPoints = {}

local ox = exports.ox_inventory

local KINDS = {
    storage = { label = 'Stockage', default = 'Stockage' },
    stash = { label = 'Stockage séparé', default = 'Stockage séparé' },
    garage = { label = 'Garage', default = 'Garage', soon = true },
    property = { label = 'Propriété', default = 'Planque' },
}

---@type table<number, table> points par id
local points = {}

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les crews.")
end

-- Identifiant du coffre d'un point (nil pour un garage)
local function stashOf(point)
    if point.kind == 'storage' then
        return ('crew_%d'):format(point.crew)
    elseif point.kind == 'stash' then
        return ('crew_%d_p%d'):format(point.crew, point.id)
    elseif point.kind == 'property' then
        return ('crew_%d_h%d'):format(point.crew, point.id)
    end
end

local function registerStash(point)
    local id = stashOf(point)

    if not id then
        return
    end

    local crew = Crews.basic(point.crew)
    local label = point.kind == 'storage' and ('Coffre · %s'):format(crew and crew.label or 'crew') or ('%s · %s'):format(point.label, crew and crew.label or 'crew')
    ox:RegisterStash(id, label, Config.CrewStashSlots, Config.CrewStashWeight, false)
end

local function toPoint(row)
    return {
        id = tonumber(row.id), crew = tonumber(row.crew_id), kind = row.kind, label = row.label,
        x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h) or 0.0, interior = row.interior or '',
    }
end

-- Prévient les clients : ceux de ce crew rechargent leurs points
local function changed(crewId)
    TriggerClientEvent('lunatic_illegal:crewPointsChanged', -1, crewId)
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_crew_points` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `crew_id` INT NOT NULL,
            `kind` VARCHAR(12) NOT NULL,
            `label` VARCHAR(60) NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `h` DOUBLE NOT NULL DEFAULT 0,
            `interior` VARCHAR(20) NOT NULL DEFAULT '',
            `created_by` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_crew_points_crew` (`crew_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_crew_points`') or {}) do
        local point = toPoint(row)

        -- Points d'un crew supprimé : ignorés
        if Crews.basic(point.crew) then
            points[point.id] = point
            registerStash(point)
        end
    end
end)

---------------------------------------------------------------------
-- Pour le jeu (lunatic_illegal)
---------------------------------------------------------------------

function CrewPoints.list(crewId)
    local list = {}

    for _, point in pairs(points) do
        if point.crew == crewId then
            list[#list + 1] = {
                id = point.id, kind = point.kind, label = point.label, x = point.x, y = point.y, z = point.z, h = point.h,
                interior = point.interior, soon = KINDS[point.kind].soon == true,
            }
        end
    end

    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

exports('getCrewPoints', function(crewId)
    return CrewPoints.list(tonumber(crewId))
end)

-- Point d'un crew, avec l'identifiant de son coffre
exports('getCrewPoint', function(pointId)
    local point = points[tonumber(pointId) or -1]

    if not point then
        return nil
    end

    return {
        id = point.id, crew = point.crew, kind = point.kind, label = point.label, x = point.x, y = point.y, z = point.z, h = point.h,
        interior = point.interior, stash = stashOf(point),
    }
end)

-- Wipe d'un crew (server/crews.lua) : coffres vidés
-- Suppression d'un crew : ses points aussi
table.insert(Crews.deleteHooks, function(crewId)
    MySQL.update.await('DELETE FROM `lunatic_crew_points` WHERE `crew_id` = ?', { crewId })

    for id, point in pairs(points) do
        if point.crew == crewId then
            points[id] = nil
        end
    end

    changed(crewId)
end)

table.insert(Crews.wipeHooks, function(crewId)
    for _, point in pairs(points) do
        local id = point.crew == crewId and stashOf(point)

        if id then
            ox:ClearInventory(id)
        end
    end
end)

---------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------

local function cleanText(value, min, max)
    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length >= min and length <= max and text or nil
end

local function staffPosition(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z, h = GetEntityHeading(ped) }
end

local function pointFor(actor, id)
    if not Ranks.hasPermission(actor, 'crews.manage') then
        return nil, denied()
    end

    local point = points[tonumber(id) or -1]

    if not point then
        return nil, Panel.fail('Point introuvable.')
    end

    return point
end

Panel.actions['crews.points'] = function(_, actor, data)
    if not Ranks.hasPermission(actor, 'crews.manage') then
        return denied()
    end

    local interiors = {}

    for id, label in pairs(Config.CrewPropertyInteriors) do
        interiors[#interiors + 1] = { id = id, label = label }
    end

    table.sort(interiors, function(a, b) return a.label < b.label end)
    return { ok = true, silent = true, points = CrewPoints.list(tonumber(data.id)), interiors = interiors }
end

-- Nouveau point à la position du membre du staff
Panel.actions['crews.pointAdd'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'crews.manage') then
        return denied()
    end

    local crew = Crews.basic(data.id)
    local kind = KINDS[data.kind] and data.kind

    if not crew or not kind then
        return Panel.fail('Crew ou type de point inconnu.')
    end

    local count = 0

    for _, point in pairs(points) do
        if point.crew == crew.id then
            count = count + 1
        end
    end

    if count >= Config.CrewPointsMax then
        return Panel.fail(('Maximum %d points par crew.'):format(Config.CrewPointsMax))
    end

    local position = staffPosition(src)

    if not position then
        return Panel.fail('Position introuvable : êtes-vous en jeu ?')
    end

    local interior = ''

    if kind == 'property' then
        interior = Config.CrewPropertyInteriors[data.interior] and data.interior or next(Config.CrewPropertyInteriors)
    end

    local label = KINDS[kind].default
    local id = MySQL.insert.await('INSERT INTO `lunatic_crew_points` (`crew_id`, `kind`, `label`, `x`, `y`, `z`, `h`, `interior`, `created_by`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        crew.id, kind, label, position.x, position.y, position.z, position.h, interior, Staff.displayName(src), os.time(),
    })

    local point = { id = id, crew = crew.id, kind = kind, label = label, x = position.x, y = position.y, z = position.z, h = position.h, interior = interior }
    points[id] = point
    registerStash(point)
    changed(crew.id)
    Logs.add(src, 'crews.point', nil, { crew = crew.label, kind = KINDS[kind].label, label = label, operation = 'ajout' })

    return { ok = true, silent = true, id = id }
end

-- Nom et intérieur (planque)
Panel.actions['crews.pointSave'] = function(src, actor, data)
    local point, err = pointFor(actor, data.pointId)

    if not point then
        return err
    end

    local label = cleanText(data.label, 1, 60)

    if not label then
        return Panel.fail('Le nom doit faire entre 1 et 60 caractères.')
    end

    local interior = point.interior

    if point.kind == 'property' then
        interior = Config.CrewPropertyInteriors[data.interior] and data.interior or point.interior
    end

    MySQL.update.await('UPDATE `lunatic_crew_points` SET `label` = ?, `interior` = ? WHERE `id` = ?', { label, interior, point.id })
    point.label, point.interior = label, interior
    registerStash(point)
    changed(point.crew)
    Logs.add(src, 'crews.point', nil, { crew = (Crews.basic(point.crew) or {}).label, kind = KINDS[point.kind].label, label = label, operation = 'modification' })

    return { ok = true, silent = true }
end

-- « Définir » : le point passe à la position du membre du staff
Panel.actions['crews.pointMove'] = function(src, actor, data)
    local point, err = pointFor(actor, data.pointId)

    if not point then
        return err
    end

    local position = staffPosition(src)

    if not position then
        return Panel.fail('Position introuvable : êtes-vous en jeu ?')
    end

    MySQL.update.await('UPDATE `lunatic_crew_points` SET `x` = ?, `y` = ?, `z` = ?, `h` = ? WHERE `id` = ?', { position.x, position.y, position.z, position.h, point.id })
    point.x, point.y, point.z, point.h = position.x, position.y, position.z, position.h
    changed(point.crew)
    Logs.add(src, 'crews.point', nil, { crew = (Crews.basic(point.crew) or {}).label, kind = KINDS[point.kind].label, label = point.label, operation = 'déplacé' })

    return { ok = true, silent = true }
end

Panel.actions['crews.pointTp'] = function(src, actor, data)
    local point, err = pointFor(actor, data.pointId)

    if not point then
        return err
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(point.x, point.y, point.z + 0.5))
    return { ok = true, silent = true }
end

Panel.actions['crews.pointDelete'] = function(src, actor, data)
    local point, err = pointFor(actor, data.pointId)

    if not point then
        return err
    end

    MySQL.update.await('DELETE FROM `lunatic_crew_points` WHERE `id` = ?', { point.id })
    points[point.id] = nil
    changed(point.crew)
    Logs.add(src, 'crews.point', nil, { crew = (Crews.basic(point.crew) or {}).label, kind = KINDS[point.kind].label, label = point.label, operation = 'suppression' })

    return { ok = true, silent = true }
end
