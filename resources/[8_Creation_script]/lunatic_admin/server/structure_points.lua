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

---@type table<number, table> véhicules de service par id
local vehicles = {}

local CATEGORIES, VEHICLE_TYPES = {}, {}

for _, entry in ipairs(Config.StructureVehicleCategories) do
    CATEGORIES[entry.id] = entry.label
end

for _, id in ipairs(Config.StructureVehicleTypes) do
    VEHICLE_TYPES[id] = true
end

local function toVehicle(row)
    return {
        id = tonumber(row.id), job = row.job, category = row.category, model = row.model, label = row.label,
        vtype = row.vtype, minGrade = tonumber(row.min_grade) or 0,
    }
end

-- Parc d'une structure (panel et lunatic_business)
function StructurePoints.vehiclesOf(jobName)
    local list = {}

    for _, vehicle in pairs(vehicles) do
        if vehicle.job == jobName then
            list[#list + 1] = vehicle
        end
    end

    table.sort(list, function(a, b)
        if a.category ~= b.category then
            return a.category < b.category
        end

        if a.minGrade ~= b.minGrade then
            return a.minGrade < b.minGrade
        end

        return a.label < b.label
    end)

    return list
end

exports('getStructureVehicles', StructurePoints.vehiclesOf)

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
        data = row.data and row.data ~= '' and json.decode(row.data) or {},
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
    MySQL.update.await('DELETE FROM `lunatic_structure_vehicles` WHERE `job` = ?', { jobName })

    for id, vehicle in pairs(vehicles) do
        if vehicle.job == jobName then
            vehicles[id] = nil
        end
    end

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

    -- Réglages propres au type (garage : catégorie de véhicules ; blip : sprite, couleur, taille)
    MySQL.query.await("ALTER TABLE `lunatic_structure_points` ADD COLUMN IF NOT EXISTS `data` VARCHAR(255) NOT NULL DEFAULT ''")

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_structure_vehicles` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `job` VARCHAR(50) NOT NULL,
            `category` VARCHAR(10) NOT NULL,
            `model` VARCHAR(40) NOT NULL,
            `label` VARCHAR(60) NOT NULL,
            `vtype` VARCHAR(12) NOT NULL DEFAULT 'automobile',
            `min_grade` INT NOT NULL DEFAULT 0,
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_structure_vehicles_job` (`job`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_structure_vehicles`') or {}) do
        vehicles[tonumber(row.id)] = toVehicle(row)
    end

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

-- Réglages d'un point selon son type (valeurs sûres, sinon celles par défaut)
local function pointData(typeId, data)
    if type(data) ~= 'table' then
        data = {}
    end

    if typeId == 'garage' then
        return { vehicle = CATEGORIES[data.vehicle] and data.vehicle or 'car' }
    end

    if typeId == 'blips' then
        local sprite, color, scale = tonumber(data.sprite), tonumber(data.color), tonumber(data.scale)

        return {
            sprite = sprite and sprite >= 0 and sprite <= 1000 and math.floor(sprite) or 60,
            color = color and color >= 0 and color <= 100 and math.floor(color) or 0,
            scale = scale and scale >= 0.1 and scale <= 3.0 and math.floor(scale * 100 + 0.5) / 100 or 0.8,
        }
    end

    return {}
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

    if TYPES[data.type].fleet then
        return Panel.fail('Les véhicules se règlent dans le groupe Véhicules, sans point.')
    end

    local settings = pointData(data.type, data.data or {})
    local id = MySQL.insert.await('INSERT INTO `lunatic_structure_points` (`job`, `type`, `label`, `x`, `y`, `z`, `h`, `data`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        structure.job, data.type, label, position.x, position.y, position.z, position.h, json.encode(settings), os.time(),
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

-- Réglages propres au type (garage, blip)
Panel.actions['structures.pointData'] = function(src, actor, data)
    local point, err = pointFor(actor, data.id)

    if not point then
        return err
    end

    local settings = pointData(point.type, data.data)
    MySQL.update.await('UPDATE `lunatic_structure_points` SET `data` = ? WHERE `id` = ?', { json.encode(settings), point.id })
    point.data = settings
    publish()

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

---------------------------------------------------------------------
-- Véhicules de service (groupe Véhicules de la fiche)
---------------------------------------------------------------------

local function cleanText(value, min, max)
    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length >= min and length <= max and text or nil
end

-- Ajout (sans id) ou modification d'un véhicule du parc
Panel.actions['structures.vehicleSave'] = function(src, actor, data)
    local structure = type(data.job) == 'string' and Structures.get(data.job)

    if not structure then
        return Panel.fail('Structure introuvable.')
    end

    if not canManage(actor, structure.job) then
        return denied()
    end

    local current = data.id and vehicles[tonumber(data.id) or -1]

    if data.id and (not current or current.job ~= structure.job) then
        return Panel.fail('Véhicule introuvable.')
    end

    local model = type(data.model) == 'string' and data.model:lower():match('^%s*([%w_]+)%s*$')
    local label = cleanText(data.label, 1, 60)
    local category = CATEGORIES[data.category] and data.category
    local vtype = VEHICLE_TYPES[data.vtype] and data.vtype
    local minGrade = tonumber(data.minGrade)

    if not model or #model > 40 then
        return Panel.fail('Modèle invalide : nom du véhicule (ex. police3), lettres, chiffres et _.')
    end

    if not label then
        return Panel.fail('Le nom affiché doit faire entre 1 et 60 caractères.')
    end

    if not category or not vtype then
        return Panel.fail('Catégorie ou type de véhicule inconnu.')
    end

    if not minGrade or minGrade ~= math.floor(minGrade) or minGrade < 0 or minGrade > 50 then
        return Panel.fail('Grade minimum invalide.')
    end

    if current then
        MySQL.update.await('UPDATE `lunatic_structure_vehicles` SET `category` = ?, `model` = ?, `label` = ?, `vtype` = ?, `min_grade` = ? WHERE `id` = ?', { category, model, label, vtype, minGrade, current.id })
        current.category, current.model, current.label, current.vtype, current.minGrade = category, model, label, vtype, minGrade
    else
        if #StructurePoints.vehiclesOf(structure.job) >= Config.StructureVehiclesMax then
            return Panel.fail(('Maximum %d véhicules par structure.'):format(Config.StructureVehiclesMax))
        end

        local id = MySQL.insert.await('INSERT INTO `lunatic_structure_vehicles` (`job`, `category`, `model`, `label`, `vtype`, `min_grade`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            structure.job, category, model, label, vtype, minGrade, os.time(),
        })
        vehicles[id] = { id = id, job = structure.job, category = category, model = model, label = label, vtype = vtype, minGrade = minGrade }
    end

    Logs.add(src, 'structures.vehicle', nil, { job = structure.job, label = label, model = model, operation = current and 'modification' or 'ajout' })
    return { ok = true, silent = true }
end

Panel.actions['structures.vehicleDelete'] = function(src, actor, data)
    local vehicle = vehicles[tonumber(data.id) or -1]

    if not vehicle then
        return Panel.fail('Véhicule introuvable.')
    end

    if not canManage(actor, vehicle.job) then
        return denied()
    end

    MySQL.update.await('DELETE FROM `lunatic_structure_vehicles` WHERE `id` = ?', { vehicle.id })
    vehicles[vehicle.id] = nil
    Logs.add(src, 'structures.vehicle', nil, { job = vehicle.job, label = vehicle.label, model = vehicle.model, operation = 'suppression' })

    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Points des structures chargé.')
