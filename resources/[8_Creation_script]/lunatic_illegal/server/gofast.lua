-- GoFast (points dans le panel, page Braquages → GoFast ; réglages dans la page Missions → GoFast).
-- Au garage de départ, [E] lance le GoFast : une voiture rapide chargée apparaît, la livraison est tirée au hasard
-- loin du départ, à faire avant la fin du temps. Si la police est sur le coup, elle reçoit la position de la voiture
-- à intervalle régulier. Gain réduit selon l'état de la carrosserie. Tout est revérifié ici (départ, véhicule conduit,
-- distance à la livraison, temps, délai par joueur, limite du jour).

local admin = exports.lunatic_admin

local runs = {}    -- joueur -> GoFast en cours { vehicle, drop, deadline, tracked, nextTrack }
local lastRun = {} -- joueur -> dernier départ (os.time)

local function fail(message)
    return { ok = false, error = message }
end

local function spots()
    local found, cfg = pcall(function() return admin:getHoldupConfig() end)
    local starts, drops = {}, {}

    if found and cfg then
        for _, point in ipairs(cfg.points) do
            if point.active and point.type == 'gofast_start' then
                starts[point.id] = point
            elseif point.active and point.type == 'gofast_drop' then
                drops[#drops + 1] = point
            end
        end
    end

    return starts, drops
end

local function removeVehicle(vehicle, delay)
    SetTimeout(delay or 0, function()
        if vehicle and DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end
    end)
end

-- Fin du GoFast (raté, abandonné) : message au joueur, voiture retirée un peu plus tard
local function stop(src, message, delay)
    local run = runs[src]
    runs[src] = nil

    if run then
        removeVehicle(run.vehicle, delay)
        TriggerClientEvent('lunatic_illegal:gofastEnded', src, message)
    end
end

-- Garages de départ, pour l'invite en jeu
lib.callback.register('lunatic_illegal:gofastConfig', function()
    local m = MissionSettings('gofast')

    if not m or not m.enabled then
        return { enabled = false, starts = {} }
    end

    local list = {}
    local starts = spots()

    for _, point in pairs(starts) do
        list[#list + 1] = { id = point.id, x = point.x, y = point.y, z = point.z }
    end

    return { enabled = true, starts = list }
end)

local function refreshClients()
    TriggerClientEvent('lunatic_illegal:gofastConfigChanged', -1)
end

AddEventHandler('lunatic_admin:heistsChanged', refreshClients)
AddEventHandler('lunatic_admin:holdupsChanged', refreshClients)

lib.callback.register('lunatic_illegal:gofastStart', function(src, startId)
    local m = MissionSettings('gofast')
    local problem = MissionProblem(src, m)

    if problem then
        return fail(problem)
    end

    if runs[src] then
        return fail('Vous avez déjà un GoFast en cours.')
    end

    if IsPolice(src) then
        return fail('Vous êtes en service.')
    end

    local a = m.advanced
    local now = os.time()
    local wait = (lastRun[src] or 0) + a.cooldown * 60 - now

    if wait > 0 then
        return fail(('Faites-vous oublier un peu : encore %d min.'):format(math.max(1, math.ceil(wait / 60))))
    end

    local starts, drops = spots()
    local start = starts[tonumber(startId)]
    local ped = GetPlayerPed(src)

    if not start then
        return fail('Pas de GoFast ici.')
    end

    if start.z < -100.0 then
        return fail('Ce départ a été placé sur la carte : faites « Définir » en jeu à cet endroit.')
    end

    if not ped or ped == 0 or #(GetEntityCoords(ped).xy - vector2(start.x, start.y)) > 4.0 then
        return fail('Vous êtes trop loin.')
    end

    -- Livraison au hasard parmi celles assez loin (sinon la plus éloignée)
    local far, farthest, best = {}, nil, -1

    for _, drop in ipairs(drops) do
        local distance = #(vector2(drop.x, drop.y) - vector2(start.x, start.y))

        if distance >= a.minDistance then
            far[#far + 1] = drop
        end

        if distance > best then
            farthest, best = drop, distance
        end
    end

    local drop = #far > 0 and far[math.random(#far)] or farthest

    if not drop then
        return fail("Aucun point de livraison : à placer dans le panel.")
    end

    if not admin:takeMissionSlot('gofast') then
        return fail("Plus de GoFast aujourd'hui : la route est surveillée.")
    end

    local vehicle = CreateVehicleServerSetter(joaat(a.vehicle), 'automobile', start.x, start.y, start.z + 0.5, start.h or 0.0)
    local timeout = GetGameTimer() + 5000

    while not DoesEntityExist(vehicle) and GetGameTimer() < timeout do
        Wait(50)
    end

    if not DoesEntityExist(vehicle) then
        return fail("Le véhicule n'a pas pu apparaître.")
    end

    SetVehicleNumberPlateText(vehicle, ('GF%04d'):format(math.random(0, 9999)))
    Entity(vehicle).state:set('lunaticGoFast', src, true)

    lastRun[src] = now
    local run = { vehicle = vehicle, drop = drop, deadline = now + a.duration * 60, tracked = math.random(100) <= a.alert, nextTrack = now + 20 }
    runs[src] = run

    return {
        ok = true, netId = NetworkGetNetworkIdFromEntity(vehicle), minutes = a.duration,
        drop = { x = drop.x, y = drop.y, z = drop.z, label = drop.label },
    }
end)

-- Temps écoulé, voiture détruite, et position envoyée à la police si elle est sur le coup
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        local m = MissionSettings('gofast')

        for src, run in pairs(runs) do
            if not DoesEntityExist(run.vehicle) or GetEntityHealth(run.vehicle) <= 0 then
                stop(src, 'La voiture est détruite : GoFast raté.', 0)
            elseif now > run.deadline then
                stop(src, 'Trop tard : le client ne vous attend plus. GoFast raté.', 30000)
            elseif run.tracked and m and now >= run.nextTrack then
                run.nextTrack = now + m.advanced.track
                AlertPolice(GetEntityCoords(run.vehicle), ('GoFast : véhicule rapide repéré (%s)'):format(GetVehicleNumberPlateText(run.vehicle) or '?'), 80)
            end
        end
    end
end)

lib.callback.register('lunatic_illegal:gofastFinish', function(src)
    local run = runs[src]
    local m = MissionSettings('gofast')

    if not run or not m then
        return fail('Aucun GoFast en cours.')
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or GetVehiclePedIsIn(ped, false) ~= run.vehicle then
        return fail('Il faut livrer avec la voiture du GoFast.')
    end

    local coords = GetEntityCoords(run.vehicle)

    if #(coords.xy - vector2(run.drop.x, run.drop.y)) > 12.0 then
        return fail("Vous n'êtes pas au point de livraison.")
    end

    if os.time() > run.deadline then
        stop(src, 'Trop tard : GoFast raté.', 30000)
        return fail('Trop tard.')
    end

    -- Gain selon l'état de la carrosserie (au moins 30 %)
    local factor = math.max(0.3, math.min(1.0, (GetVehicleBodyHealth(run.vehicle) or 1000.0) / 1000.0))
    local paid = json.decode(json.encode(m))
    paid.reward = math.floor((m.reward or 0) * factor)

    runs[src] = nil
    removeVehicle(run.vehicle, 15000)

    local reward, loot = MissionPayout(src, paid, coords, 'gofast', Config.HoldupAccount)
    return { ok = true, reward = MoneyText(reward), loot = loot, damaged = factor < 0.95 }
end)

RegisterNetEvent('lunatic_illegal:gofastAbandon', function()
    stop(source, 'GoFast abandonné.', 10000)
end)

AddEventHandler('playerDropped', function()
    local run = runs[source]
    runs[source] = nil

    if run then
        removeVehicle(run.vehicle, 0)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        -- Directement : un SetTimeout ne tournerait plus, la resource s'arrête
        for _, run in pairs(runs) do
            if DoesEntityExist(run.vehicle) then
                DeleteEntity(run.vehicle)
            end
        end
    end
end)
