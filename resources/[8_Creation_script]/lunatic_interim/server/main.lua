-- Job Center (doc Vision « Jobs de farm ») côté serveur. L'intérim est un second métier, à part du métier ESX : on garde
-- son poste fixe (Burger Shot, LSPD…) et on peut prendre en plus un métier d'intérim. Il est enregistré par personnage
-- (table lunatic_interim_players) et partagé par le statebag du joueur « interimJob » (id du métier, nil sinon).
-- Fiche des métiers, accepter / quitter, tenues de travail enregistrées par le staff (homme et femme).

local MODELS = { [`mp_m_freemode_01`] = 'm', [`mp_f_freemode_01`] = 'f' }

local outfits = {} -- id du métier -> { m = tenue, f = tenue }

-- Métier d'intérim du joueur (fiche de la config), nil sinon
function InterimOf(src)
    return JobById(Player(src).state.interimJob)
end

local function setInterim(src, id)
    Player(src).state:set('interimJob', id, true)
    TriggerEvent('lunatic_interim:changed', src, id)
end

---------------------------------------------------------------------
-- Base de données
---------------------------------------------------------------------

local function loadPlayer(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer then
        return
    end

    local id = MySQL.scalar.await('SELECT `job` FROM `lunatic_interim_players` WHERE `identifier` = ?', { xPlayer.identifier })

    -- Ancien fonctionnement (métier ESX « interim_<id> ») : repris en métier d'intérim, le joueur redevient sans emploi
    local old = JobById(xPlayer.getJob().name:match('^' .. Config.JobPrefix .. '(.+)$') or '')

    if old then
        id = old.id
        MySQL.update.await('INSERT INTO `lunatic_interim_players` (`identifier`, `job`, `since`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `job` = VALUES(`job`)', { xPlayer.identifier, id, os.time() })
        xPlayer.setJob('unemployed', 0)
    end

    Player(src).state:set('interimJob', JobById(id) and id or nil, true)

    -- Déconnecté en pleine chasse : le fusil prêté est repris
    if ReturnHuntWeapon then
        ReturnHuntWeapon(src)
    end
end

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_interim_outfits` (
            `job` VARCHAR(30) NOT NULL,
            `model` CHAR(1) NOT NULL,
            `outfit` LONGTEXT NOT NULL,
            PRIMARY KEY (`job`, `model`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Métier d'intérim de chaque personnage (second métier, à part du métier ESX)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_interim_players` (
            `identifier` VARCHAR(64) NOT NULL,
            `job` VARCHAR(30) NOT NULL,
            `since` BIGINT NOT NULL,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    for _, row in ipairs(MySQL.query.await('SELECT `job`, `model`, `outfit` FROM `lunatic_interim_outfits`') or {}) do
        outfits[row.job] = outfits[row.job] or {}
        outfits[row.job][row.model] = json.decode(row.outfit)
    end

    -- Joueurs déjà connectés (redémarrage de la ressource)
    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        loadPlayer(xPlayer.source)
    end
end)

AddEventHandler('esx:playerLoaded', function(src)
    loadPlayer(src)
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
    local current = InterimOf(src)
    local job = xPlayer.getJob()
    local jobs = {}

    for _, entry in ipairs(Config.Jobs) do
        local settings = JobSettings(entry.id)

        -- Métier désactivé dans le panel : plus proposé (sauf à celui qui l'a déjà, pour le quitter)
        if settings.enabled or (current and current.id == entry.id) then
            jobs[#jobs + 1] = {
                id = entry.id, label = entry.label, company = entry.company, color = entry.color, salary = settings.salary, duration = entry.duration,
                participants = entry.participants, missions = entry.missions,
                outfit = model and outfits[entry.id] and outfits[entry.id][model] or nil,
            }
        end
    end

    return {
        ok = true, jobs = jobs, model = model, staff = isStaff(src), current = current and current.id or nil,
        -- Poste fixe (entreprise, service public…) : il est gardé, l'intérim s'ajoute
        mainJob = job.name ~= 'unemployed' and job.label or nil,
    }
end)

lib.callback.register('lunatic_interim:accept', function(src, index, id)
    local xPlayer = ESX.GetPlayerFromId(src)
    local job = JobById(id)

    if not xPlayer or not nearCenter(src, index) then
        return fail('Trop loin du Job Center.')
    elseif not job or not JobSettings(job.id).enabled then
        return fail('Métier introuvable.')
    end

    local previous = InterimOf(src)
    MySQL.update.await('INSERT INTO `lunatic_interim_players` (`identifier`, `job`, `since`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `job` = VALUES(`job`), `since` = VALUES(`since`)',
        { xPlayer.identifier, job.id, os.time() })
    setInterim(src, job.id)
    log(src, 'interim.accept', job.label, { previous = previous and previous.label or nil })

    local model = MODELS[GetEntityModel(GetPlayerPed(src))]
    return { ok = true, label = job.label, outfit = model and outfits[job.id] and outfits[job.id][model] or nil }
end)

lib.callback.register('lunatic_interim:quit', function(src, index)
    local xPlayer = ESX.GetPlayerFromId(src)
    local current = InterimOf(src)

    if not xPlayer or not nearCenter(src, index) then
        return fail('Trop loin du Job Center.')
    elseif not current then
        return fail("Vous n'avez pas de métier d'intérim.")
    end

    MySQL.update.await('DELETE FROM `lunatic_interim_players` WHERE `identifier` = ?', { xPlayer.identifier })
    setInterim(src, nil)
    log(src, 'interim.quit', current.label, nil)
    return { ok = true, label = current.label }
end)

-- Staff (permission Autres) : la tenue portée devient celle du métier, pour le modèle du personnage (homme ou femme)
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

-- Staff : habillage libre (lunatic_clothing, homme ou femme) avant d'enregistrer une tenue ; retour au Job Center ensuite
lib.callback.register('lunatic_interim:dress', function(src, index)
    if not isStaff(src) then
        return fail("Vous n'avez pas la permission.")
    elseif not nearCenter(src, index) then
        return fail('Trop loin du Job Center.')
    elseif GetResourceState('lunatic_clothing') ~= 'started' then
        return fail("lunatic_clothing n'est pas démarré.")
    end

    local ok = pcall(function() exports.lunatic_clothing:startStaffDressing(src, false, 'interim') end)
    return ok and { ok = true } or fail('Habillage indisponible.')
end)

-- Pour le panel (Autres → Job Center) et les missions
exports('getDefaultCenters', function()
    return Config.Centers
end)

-- Fiches des métiers pour le panel (Autres → Métiers d'intérim) : valeurs par défaut de la config
exports('getJobDefinitions', function()
    local list = {}

    for _, job in ipairs(Config.Jobs) do
        list[#list + 1] = { id = job.id, label = job.label, company = job.company, salary = job.salary, kind = job.kind, vehicle = job.vehicle, stops = job.stops or 5 }
    end

    return list
end)

exports('getInterimJob', function(src)
    return Player(tonumber(src) or 0).state.interimJob
end)
