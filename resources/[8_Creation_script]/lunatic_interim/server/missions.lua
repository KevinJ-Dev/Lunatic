-- Tournées d'intérim (Livreur, Facteur, Éboueur) côté serveur. Au dépôt, le joueur lance la tournée : le véhicule de
-- service sort et les arrêts tirés par son client sont vérifiés (distances au dépôt et entre eux). Chaque arrêt est
-- validé sur place (position, temps minimum, véhicule pas loin) ; au retour au dépôt avec le véhicule, la paie part
-- sur son compte bancaire. Véhicule détruit, métier changé ou déconnexion : la tournée s'arrête, sans paie.

local missions = {} -- joueur -> { job, label, task, vehicle, stops, index, last, salary, depot }

local function fail(message)
    return { ok = false, error = message }
end

local function log(src, action, target, details)
    pcall(function() exports.lunatic_admin:log('companies', 'info', src, action, target, details) end)
end

local function vec(point)
    return vector3(point.x, point.y, point.z)
end

local function flat(a, b)
    return #(vector2(a.x, a.y) - vector2(b.x, b.y))
end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetEntityCoords(ped) or nil
end

local function deleteVehicle(mission)
    if mission and mission.vehicle and DoesEntityExist(mission.vehicle) then
        DeleteEntity(mission.vehicle)
    end
end

local function stop(src, message, kind)
    local mission = missions[src]

    if not mission then
        return
    end

    deleteVehicle(mission)
    missions[src] = nil
    TriggerClientEvent('lunatic_interim:missionEnded', src, message, kind)
end

-- Arrêts proposés par le client : nombre, carte, distances au dépôt et entre eux (avec un peu de marge)
local function cleanStops(list, settings)
    if type(list) ~= 'table' or #list ~= settings.stops then
        return nil
    end

    local route, depot, stops = Config.Route, settings.depot, {}

    for _, point in ipairs(list) do
        local x, y, z = type(point) == 'table' and tonumber(point.x), type(point) == 'table' and tonumber(point.y), type(point) == 'table' and tonumber(point.z)

        if not x or not y or not z or x < -4500 or x > 4500 or y < -4500 or y > 8500 then
            return nil
        end

        local here = vector3(x, y, z)
        local distance = flat(here, depot)

        if distance < route.minDistance * 0.8 or distance > route.maxDistance * 1.2 then
            return nil
        end

        for _, other in ipairs(stops) do
            if flat(here, other) < route.gap * 0.8 then
                return nil
            end
        end

        stops[#stops + 1] = here
    end

    return stops
end

lib.callback.register('lunatic_interim:missionStart', function(src, list)
    local xPlayer = ESX.GetPlayerFromId(src)
    local job = xPlayer and JobFromName(xPlayer.getJob().name)
    local settings = job and JobSettings(job.id)
    local coords = pedCoords(src)

    if not job or job.kind ~= 'route' then
        return fail("Votre métier n'a pas de tournée.")
    elseif not settings.enabled then
        return fail('Ce métier est fermé pour le moment.')
    elseif not settings.depot or not settings.spawn or not settings.vehicle then
        return fail('Dépôt pas encore réglé : prévenez le staff.')
    elseif missions[src] then
        return fail('Vous avez déjà une tournée en cours.')
    elseif not coords or #(coords - vec(settings.depot)) > 6.0 then
        return fail('Rendez-vous au dépôt.')
    end

    local stops = cleanStops(list, settings)

    if not stops then
        return fail('Tournée invalide, réessayez.')
    end

    local spawn = settings.spawn

    for _, vehicle in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(vehicle) - vec(spawn)) < 3.0 then
            return fail('La sortie du dépôt est encombrée : dégagez-la puis réessayez.')
        end
    end

    local vehicle = CreateVehicleServerSetter(joaat(settings.vehicle), 'automobile', spawn.x, spawn.y, spawn.z, spawn.h or 0.0)
    local timeout = GetGameTimer() + 3000

    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return fail(("Le véhicule n'a pas pu sortir (modèle %s introuvable ?)."):format(settings.vehicle))
    end

    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(vehicle, ('INT%05d'):format(math.random(0, 99999)))
    TaskWarpPedIntoVehicle(GetPlayerPed(src), vehicle, -1)

    missions[src] = {
        job = job.id, label = job.label, task = job.task, vehicle = vehicle, stops = stops, index = 1, last = os.time(),
        salary = settings.salary, depot = vec(settings.depot),
    }

    return { ok = true, netId = NetworkGetNetworkIdFromEntity(vehicle), task = job.task, stops = stops, bags = Config.Route.garbageBags }
end)

-- Arrêt fait : le joueur est sur place (Éboueur : près du camion, à l'arrêt), assez de temps depuis l'arrêt d'avant
lib.callback.register('lunatic_interim:missionStop', function(src, index)
    local mission = missions[src]
    local coords = pedCoords(src)

    if not mission or tonumber(index) ~= mission.index or not mission.stops[mission.index] then
        return fail('Arrêt introuvable.')
    elseif not DoesEntityExist(mission.vehicle) then
        stop(src, 'Le véhicule de service a disparu : tournée arrêtée.', 'error')
        return fail('Véhicule disparu.')
    end

    local reach = mission.task == 'garbage' and 30.0 or Config.Route.reach

    if not coords or #(coords - mission.stops[mission.index]) > reach then
        return fail("Vous n'êtes pas à l'arrêt.")
    elseif os.time() - mission.last < Config.Route.stopSeconds then
        return fail('Trop rapide : prenez le temps de faire le travail.')
    elseif #(GetEntityCoords(mission.vehicle) - coords) > 60.0 then
        return fail('Le véhicule de service est trop loin.')
    end

    mission.index = mission.index + 1
    mission.last = os.time()
    return { ok = true, index = mission.index, done = mission.index > #mission.stops }
end)

-- Retour au dépôt avec le véhicule, tous les arrêts faits : paie sur le compte bancaire
lib.callback.register('lunatic_interim:missionFinish', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    local mission = missions[src]
    local coords = pedCoords(src)

    if not xPlayer or not mission then
        return fail("Vous n'avez pas de tournée en cours.")
    elseif mission.index <= #mission.stops then
        return fail(('Tournée pas finie : %d / %d arrêts.'):format(mission.index - 1, #mission.stops))
    elseif not coords or #(coords - mission.depot) > 10.0 then
        return fail('Rendez-vous au dépôt.')
    elseif not DoesEntityExist(mission.vehicle) or #(GetEntityCoords(mission.vehicle) - mission.depot) > 30.0 then
        return fail('Ramenez le véhicule de service au dépôt.')
    end

    deleteVehicle(mission)
    missions[src] = nil

    if mission.salary > 0 then
        xPlayer.addAccountMoney('bank', mission.salary, ("Mission d'intérim : %s"):format(mission.label))
    end

    log(src, 'interim.mission', mission.label, { salary = mission.salary, stops = #mission.stops })
    return { ok = true, salary = mission.salary }
end)

lib.callback.register('lunatic_interim:missionCancel', function(src)
    if not missions[src] then
        return fail("Vous n'avez pas de tournée en cours.")
    end

    stop(src, nil)
    return { ok = true }
end)

-- Véhicule détruit ou supprimé : tournée arrêtée
CreateThread(function()
    while true do
        Wait(5000)

        for src, mission in pairs(missions) do
            if not DoesEntityExist(mission.vehicle) or GetVehicleEngineHealth(mission.vehicle) <= 0 then
                stop(src, 'Le véhicule de service est hors d\u{2019}usage : tournée arrêtée, sans paie.', 'error')
            end
        end
    end
end)

-- Métier changé en cours de tournée
AddEventHandler('esx:setJob', function(src, job)
    local mission = missions[src]

    if mission and (not job or job.name ~= Config.JobPrefix .. mission.job) then
        stop(src, 'Vous avez changé de métier : tournée arrêtée.', 'info')
    end
end)

AddEventHandler('playerDropped', function()
    local mission = missions[source]
    deleteVehicle(mission)
    missions[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, mission in pairs(missions) do
            deleteVehicle(mission)
        end
    end
end)
