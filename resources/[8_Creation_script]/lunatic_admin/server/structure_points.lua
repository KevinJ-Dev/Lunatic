-- Lot E2 : points d'interaction des entreprises et services publics.
-- Le staff les place depuis le panel (à sa position) ; la liste est diffusée à tous dans GlobalState.lunaticStructurePoints
-- et la resource lunatic_business (gameplay) est prévenue par l'événement serveur lunatic_admin:structurePointsChanged.

StructurePoints = {}

---@type table<number, table> points par id
local points = {}

local TYPES = {}

for _, entry in ipairs(Config.StructurePointTypes) do
    TYPES[entry.id] = entry
end

local function toPoint(row)
    local structure = Structures.get(row.job)
    local kind = TYPES[row.type]

    return {
        id = tonumber(row.id),
        job = row.job,
        kind = structure and structure.kind or nil,
        type = row.type,
        typeLabel = kind and kind.label or row.type,
        label = row.label ~= '' and row.label or (kind and kind.label or row.type),
        x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), h = tonumber(row.h),
    }
end

-- Diffusion : tous les clients (marqueurs) et le serveur de lunatic_business (coffres)
local function publish()
    local list = {}

    for _, point in pairs(points) do
        list[#list + 1] = point
    end

    table.sort(list, function(a, b) return a.id < b.id end)
    GlobalState.lunaticStructurePoints = list
    TriggerEvent('lunatic_admin:structurePointsChanged', list)
end

function StructurePoints.ofJob(jobName)
    local list = {}

    for _, point in pairs(points) do
        if point.job == jobName then
            list[#list + 1] = point
        end
    end

    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function StructurePoints.deleteJob(jobName)
    MySQL.update.await('DELETE FROM `lunatic_structure_points` WHERE `job` = ?', { jobName })

    for id, point in pairs(points) do
        if point.job == jobName then
            points[id] = nil
        end
    end

    publish()
end

exports('getStructurePoints', function()
    local list = {}

    for _, point in pairs(points) do
        list[#list + 1] = point
    end

    return list
end)

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_structure_points` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `job` VARCHAR(50) NOT NULL,
            `type` VARCHAR(24) NOT NULL,
            `label` VARCHAR(60) NOT NULL DEFAULT '',
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `h` DOUBLE NOT NULL DEFAULT 0,
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_structure_points_job` (`job`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Les fiches sont chargées par le hook de server/structures.lua (enregistré avant celui-ci)
    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_structure_points`') or {}) do
        points[tonumber(row.id)] = toPoint(row)
    end

    publish()
end)

-- lunatic_business (re)démarré : il redemande la liste
AddEventHandler('lunatic_admin:structurePointsRequest', function()
    publish()
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

local function canManage(actor, jobName)
    local permission = Structures.permissionFor(jobName)
    return permission and Ranks.hasPermission(actor, permission)
end

-- Type autorisé pour cette catégorie (entreprise, service public ou les deux)
local function typeAllowed(typeId, kind)
    local entry = TYPES[typeId]
    return entry and (entry.kinds == 'both' or entry.kinds == kind)
end

local function positionOf(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z - 0.98, h = GetEntityHeading(ped) } -- au sol, sous les pieds
end

local function cleanLabel(value)
    if value == nil or value == '' then
        return ''
    end

    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length <= 60 and text or nil
end

---@return table|nil point, table|nil error
local function pointFor(actor, id)
    local point = points[tonumber(id) or -1]

    if not point then
        return nil, Panel.fail('Point introuvable.')
    end

    if not canManage(actor, point.job) then
        return nil, denied()
    end

    return point
end

Panel.actions['structures.addPoint'] = function(src, actor, data)
    local structure = type(data.job) == 'string' and Structures.get(data.job)

    if not structure then
        return Panel.fail('Structure introuvable.')
    end

    if not canManage(actor, structure.job) then
        return denied()
    end

    if not typeAllowed(data.type, structure.kind) then
        return Panel.fail("Ce type de point n'existe pas pour cette structure.")
    end

    local label = cleanLabel(data.label)

    if not label then
        return Panel.fail('Le nom du point fait 60 caractères au maximum.')
    end

    local position = positionOf(src)

    if not position then
        return Panel.fail("Votre personnage n'est pas encore apparu.")
    end

    local id = MySQL.insert.await('INSERT INTO `lunatic_structure_points` (`job`, `type`, `label`, `x`, `y`, `z`, `h`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        structure.job, data.type, label, position.x, position.y, position.z, position.h, os.time(),
    })

    points[id] = toPoint(MySQL.single.await('SELECT * FROM `lunatic_structure_points` WHERE `id` = ?', { id }))
    publish()
    Logs.add(src, 'structures.point', nil, { job = structure.job, operation = 'add', type = data.type, id = id })

    return { ok = true, silent = true, id = id }
end

-- Définir : le point prend la position et l'orientation actuelles du staff
Panel.actions['structures.movePoint'] = function(src, actor, data)
    local point, err = pointFor(actor, data.id)

    if not point then
        return err
    end

    local position = positionOf(src)

    if not position then
        return Panel.fail("Votre personnage n'est pas encore apparu.")
    end

    MySQL.update.await('UPDATE `lunatic_structure_points` SET `x` = ?, `y` = ?, `z` = ?, `h` = ? WHERE `id` = ?', { position.x, position.y, position.z, position.h, point.id })
    point.x, point.y, point.z, point.h = position.x, position.y, position.z, position.h
    publish()
    Logs.add(src, 'structures.point', nil, { job = point.job, operation = 'move', type = point.type, id = point.id })

    return { ok = true, silent = true }
end

Panel.actions['structures.renamePoint'] = function(src, actor, data)
    local point, err = pointFor(actor, data.id)

    if not point then
        return err
    end

    local label = cleanLabel(data.label)

    if not label then
        return Panel.fail('Le nom du point fait 60 caractères au maximum.')
    end

    MySQL.update.await('UPDATE `lunatic_structure_points` SET `label` = ? WHERE `id` = ?', { label, point.id })
    point.label = label ~= '' and label or point.typeLabel
    publish()

    return { ok = true, silent = true }
end

Panel.actions['structures.deletePoint'] = function(src, actor, data)
    local point, err = pointFor(actor, data.id)

    if not point then
        return err
    end

    MySQL.update.await('DELETE FROM `lunatic_structure_points` WHERE `id` = ?', { point.id })
    points[point.id] = nil
    publish()
    Logs.add(src, 'structures.point', nil, { job = point.job, operation = 'delete', type = point.type, id = point.id })

    return { ok = true, silent = true }
end

Panel.actions['structures.tpPoint'] = function(src, actor, data)
    local point, err = pointFor(actor, data.id)

    if not point then
        return err
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(point.x, point.y, point.z + 1.0))
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Points des structures chargé.')
