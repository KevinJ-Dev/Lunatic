-- Job Center (doc Vision « Jobs de farm ») côté serveur : métiers ESX d'intérim créés s'ils manquent, fiche des métiers,
-- accepter (métier ESX « interim_<id> », grade 0) ou quitter (sans emploi), tenues de travail enregistrées par le staff.
-- Les missions de chaque métier arrivent dans les parties suivantes (paiement à la mission).

local MODELS = { [`mp_m_freemode_01`] = 'm', [`mp_f_freemode_01`] = 'f' }
local UNEMPLOYED = 'unemployed'

local outfits = {} -- id du métier -> { m = tenue, f = tenue }

local function jobName(job)
    return Config.JobPrefix .. job.id
end

-- Métier d'intérim du joueur (fiche de la config), nil sinon
local function interimOf(xPlayer)
    local name = xPlayer.getJob().name

    for _, job in ipairs(Config.Jobs) do
        if jobName(job) == name then
            return job
        end
    end
end

---------------------------------------------------------------------
-- Base de données : métiers ESX et tenues
---------------------------------------------------------------------

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_interim_outfits` (
            `job` VARCHAR(30) NOT NULL,
            `model` CHAR(1) NOT NULL,
            `outfit` LONGTEXT NOT NULL,
            PRIMARY KEY (`job`, `model`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    for _, row in ipairs(MySQL.query.await('SELECT `job`, `model`, `outfit` FROM `lunatic_interim_outfits`') or {}) do
        outfits[row.job] = outfits[row.job] or {}
        outfits[row.job][row.model] = json.decode(row.outfit)
    end

    -- Métiers ESX manquants : un grade « Intérimaire » (nom technique boss, comme tous les métiers du Pôle emploi), paie à 0
    local created = 0

    for _, job in ipairs(Config.Jobs) do
        local name = jobName(job)

        if not MySQL.scalar.await('SELECT 1 FROM `jobs` WHERE `name` = ?', { name }) then
            MySQL.insert.await('INSERT INTO `jobs` (`name`, `label`, `whitelisted`) VALUES (?, ?, 0)', { name, job.label })
            created = created + 1
        end

        if not MySQL.scalar.await('SELECT 1 FROM `job_grades` WHERE `job_name` = ? LIMIT 1', { name }) then
            MySQL.insert.await("INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`) VALUES (?, 0, 'boss', 'Intérimaire', 0, '{}', '{}')", { name })
            created = created + 1
        end
    end

    if created > 0 then
        ESX.RefreshJobs()
        print(('[lunatic_interim] Métiers d\u{2019}intérim créés ou complétés : %d ligne(s).'):format(created))
    end
end)

---------------------------------------------------------------------
-- Job Center
---------------------------------------------------------------------

local function nearCenter(src, index)
    local center = Centers()[tonumber(index) or 0]
    local ped = GetPlayerPed(src)

    return center and ped ~= 0 and #(GetEntityCoords(ped) - vector3(center.x, center.y, center.z)) <= Config.ServerDistance and center or nil
end

local function fail(message)
    return { ok = false, error = message }
end

local function log(src, action, target, details)
    pcall(function() exports.lunatic_admin:log('companies', 'info', src, action, target, details) end)
end

local function isStaff(src)
    local ok, allowed = pcall(function() return exports.lunatic_admin:can(src, 'others.manage') end)
    return ok and allowed == true
end

lib.callback.register('lunatic_interim:open', function(src, index)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not nearCenter(src, index) then
        return fail('Trop loin du Job Center.')
    end

    local model = MODELS[GetEntityModel(GetPlayerPed(src))]
    local current = interimOf(xPlayer)
    local job = xPlayer.getJob()
    local jobs = {}

    for _, entry in ipairs(Config.Jobs) do
        jobs[#jobs + 1] = {
            id = entry.id, label = entry.label, company = entry.company, color = entry.color, salary = entry.salary, duration = entry.duration,
            participants = entry.participants, missions = entry.missions,
            outfit = model and outfits[entry.id] and outfits[entry.id][model] or nil,
        }
    end

    return {
        ok = true, jobs = jobs, model = model, staff = isStaff(src), current = current and current.id or nil,
        -- Métier actuel hors intérim (entreprise, service public…) : le joueur est prévenu qu'il le quitte en acceptant
        otherJob = not current and job.name ~= UNEMPLOYED and job.label or nil,
    }
end)

lib.callback.register('lunatic_interim:accept', function(src, index, id)
    local xPlayer = ESX.GetPlayerFromId(src)
    local job = JobById(id)

    if not xPlayer or not nearCenter(src, index) then
        return fail('Trop loin du Job Center.')
    elseif not job then
        return fail('Métier introuvable.')
    elseif not ESX.DoesJobExist(jobName(job), 0) then
        return fail('Ce métier n\u{2019}est pas encore prêt (redémarrez la ressource).')
    end

    local previous = xPlayer.getJob().label
    xPlayer.setJob(jobName(job), 0)
    log(src, 'interim.accept', job.label, { previous = previous })

    local model = MODELS[GetEntityModel(GetPlayerPed(src))]
    return { ok = true, label = job.label, outfit = model and outfits[job.id] and outfits[job.id][model] or nil }
end)

lib.callback.register('lunatic_interim:quit', function(src, index)
    local xPlayer = ESX.GetPlayerFromId(src)
    local current = xPlayer and interimOf(xPlayer)

    if not xPlayer or not nearCenter(src, index) then
        return fail('Trop loin du Job Center.')
    elseif not current then
        return fail('Vous n\u{2019}avez pas de métier d\u{2019}intérim.')
    end

    xPlayer.setJob(UNEMPLOYED, 0)
    log(src, 'interim.quit', current.label, nil)
    return { ok = true, label = current.label }
end)

-- Staff (permission Autres) : la tenue portée devient celle du métier, pour le modèle du personnage
lib.callback.register('lunatic_interim:saveOutfit', function(src, index, id, outfit)
    local job = JobById(id)
    local model = MODELS[GetEntityModel(GetPlayerPed(src))]

    if not isStaff(src) then
        return fail("Vous n'avez pas la permission.")
    elseif not nearCenter(src, index) then
        return fail('Trop loin du Job Center.')
    elseif not job then
        return fail('Métier introuvable.')
    elseif not model then
        return fail('Tenues réservées aux personnages homme ou femme du jeu (freemode).')
    elseif type(outfit) ~= 'table' or type(outfit.components) ~= 'table' or type(outfit.props) ~= 'table' then
        return fail('Tenue invalide.')
    end

    local clean = { components = outfit.components, props = outfit.props }
    local encoded = json.encode(clean)

    if #encoded > 20000 then
        return fail('Tenue invalide.')
    end

    MySQL.query.await('INSERT INTO `lunatic_interim_outfits` (`job`, `model`, `outfit`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `outfit` = VALUES(`outfit`)', { job.id, model, encoded })
    outfits[job.id] = outfits[job.id] or {}
    outfits[job.id][model] = clean
    log(src, 'interim.outfit', job.label, { model = model })

    return { ok = true, model = model }
end)

-- Pour le panel (Autres → Job Center) et les missions à venir
exports('getDefaultCenters', function()
    return Config.Centers
end)

exports('getInterimJob', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    local job = xPlayer and interimOf(xPlayer)
    return job and job.id or nil
end)
