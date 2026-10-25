-- Tuile Autres → Récoltes : points de récolte (objet obtenu, quantité, durée, outil, limite par heure, métier)
-- et points de transformation (objets donnés → objet obtenu). La revente se fait aux Grossistes (tuile Catalogues).
-- Publiés dans GlobalState.lunaticHarvest ; le jeu (lunatic_gameplay) vérifie tout côté serveur.

local KINDS = { harvest = true, process = true }
local LIMITS = { label = 40, points = 200, radius = 50, count = 1000, duration = 600, limit = 10000, inputs = 6 }

local ox = exports.ox_inventory
local points = {}

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les récoltes.")
end

local whole = Util.whole

local cleanText = Util.cleanText

local function fromRow(row)
    local ok, data = pcall(json.decode, row.data or '{}')

    return {
        id = tonumber(row.id), kind = row.kind, label = row.label,
        x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), radius = tonumber(row.radius) or 3,
        active = tonumber(row.active) == 1 or row.active == true, blip = tonumber(row.blip) == 1 or row.blip == true,
        data = ok and type(data) == 'table' and data or {},
    }
end

local function publish()
    local list = {}

    for _, point in pairs(points) do
        if point.active then
            list[#list + 1] = point
        end
    end

    table.sort(list, function(a, b) return a.id < b.id end)
    GlobalState.lunaticHarvest = list
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_harvest_points` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `kind` VARCHAR(10) NOT NULL,
            `label` VARCHAR(40) NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `radius` DOUBLE NOT NULL DEFAULT 3,
            `data` TEXT NULL,
            `active` TINYINT NOT NULL DEFAULT 1,
            `blip` TINYINT NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    points = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_harvest_points`') or {}) do
        local point = fromRow(row)
        points[point.id] = point
    end

    publish()
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function allowed(actor)
    return Ranks.hasPermission(actor, 'others.manage')
end

Panel.actions['harvest.list'] = function(_, actor)
    if not allowed(actor) then
        return denied()
    end

    local list = {}

    for _, point in pairs(points) do
        list[#list + 1] = point
    end

    table.sort(list, function(a, b) return a.id < b.id end)

    local jobs = {}

    for name, job in pairs(ESX.GetJobs() or {}) do
        jobs[#jobs + 1] = { name = name, label = job.label or name }
    end

    table.sort(jobs, function(a, b) return a.label < b.label end)
    return { ok = true, silent = true, points = list, jobs = jobs }
end

local function item(name)
    return type(name) == 'string' and name ~= '' and ox:Items(name) ~= nil
end

---@return table|nil data, string|nil error
local function readData(kind, data)
    data = type(data) == 'table' and data or {}
    local duration = whole(data.duration, 1, LIMITS.duration)
    local job = type(data.job) == 'string' and data.job or ''

    if not duration then
        return nil, ('Durée : de 1 à %d secondes.'):format(LIMITS.duration)
    end

    if job ~= '' and not (ESX.GetJobs() or {})[job] then
        return nil, 'Métier requis inconnu.'
    end

    if kind == 'harvest' then
        local min, max = whole(data.min, 1, LIMITS.count), whole(data.max, 1, LIMITS.count)
        local limit = whole(data.limit, 0, LIMITS.limit)
        local tool = type(data.tool) == 'string' and data.tool or ''

        if not item(data.item) then
            return nil, ('Objet récolté inconnu : %s.'):format(tostring(data.item))
        end

        if not min or not max or min > max then
            return nil, 'Quantité : minimum et maximum entre 1 et 1000 (minimum ≤ maximum).'
        end

        if not limit then
            return nil, 'Limite par heure : un nombre entier (0 = sans limite).'
        end

        if tool ~= '' and not item(tool) then
            return nil, ('Outil inconnu : %s.'):format(tool)
        end

        return { item = data.item, min = min, max = max, duration = duration, limit = limit, tool = tool, job = job }
    end

    local count = whole(data.count, 1, LIMITS.count)
    local inputs = {}

    if not item(data.item) or not count then
        return nil, 'Objet obtenu ou quantité invalide.'
    end

    if type(data.inputs) ~= 'table' or #data.inputs < 1 or #data.inputs > LIMITS.inputs then
        return nil, ('De 1 à %d objets à transformer.'):format(LIMITS.inputs)
    end

    for _, entry in ipairs(data.inputs) do
        local amount = whole(entry.count, 1, LIMITS.count)

        if not item(entry.item) or not amount then
            return nil, ('Objet à transformer invalide : %s.'):format(tostring(entry.item))
        end

        inputs[#inputs + 1] = { item = entry.item, count = amount }
    end

    return { item = data.item, count = count, inputs = inputs, duration = duration, job = job }
end

Panel.actions['harvest.save'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local id = tonumber(data.id)
    local existing = id and points[id]

    if id and not existing then
        return Panel.fail('Point introuvable.')
    end

    local kind = existing and existing.kind or data.kind

    if not KINDS[kind] then
        return Panel.fail('Type de point inconnu.')
    end

    local label = cleanText(data.label, 2, LIMITS.label)
    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    local radius = tonumber(data.radius)

    if not label then
        return Panel.fail(('Nom : de 2 à %d caractères.'):format(LIMITS.label))
    end

    if not x or not y or not z or x < -5000 or x > 5000 or y < -5000 or y > 9000 or z < -300 or z > 3000 then
        return Panel.fail("Position invalide : utilisez « Ma position » en jeu.")
    end

    if not radius or radius < 1 or radius > LIMITS.radius then
        return Panel.fail(('Rayon : de 1 à %d mètres.'):format(LIMITS.radius))
    end

    local content, err = readData(kind, data.data)

    if not content then
        return Panel.fail(err)
    end

    local values = { kind, label, x, y, z, radius, json.encode(content), data.active == false and 0 or 1, data.blip == false and 0 or 1 }

    if existing then
        values[#values + 1] = id
        MySQL.update.await('UPDATE `lunatic_harvest_points` SET `kind` = ?, `label` = ?, `x` = ?, `y` = ?, `z` = ?, `radius` = ?, `data` = ?, `active` = ?, `blip` = ? WHERE `id` = ?', values)
    else
        local total = 0

        for _ in pairs(points) do
            total = total + 1
        end

        if total >= LIMITS.points then
            return Panel.fail(('%d points au maximum.'):format(LIMITS.points))
        end

        id = MySQL.insert.await('INSERT INTO `lunatic_harvest_points` (`kind`, `label`, `x`, `y`, `z`, `radius`, `data`, `active`, `blip`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', values)
    end

    points[id] = fromRow(MySQL.single.await('SELECT * FROM `lunatic_harvest_points` WHERE `id` = ?', { id }))
    publish()

    Logs.add(src, existing and 'harvest.update' or 'harvest.create', label, { id = id, kind = kind })
    return { ok = true, silent = true, id = id }
end

Panel.actions['harvest.delete'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local point = points[tonumber(data.id) or -1]

    if not point then
        return Panel.fail('Point introuvable.')
    end

    MySQL.update.await('DELETE FROM `lunatic_harvest_points` WHERE `id` = ?', { point.id })
    points[point.id] = nil
    publish()

    Logs.add(src, 'harvest.delete', point.label, { id = point.id })
    return { ok = true, silent = true }
end

Panel.actions['harvest.tp'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    local point = points[tonumber(data.id) or -1]

    if not point then
        return Panel.fail('Point introuvable.')
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(point.x, point.y, point.z + 0.5))
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Récoltes chargé.')
