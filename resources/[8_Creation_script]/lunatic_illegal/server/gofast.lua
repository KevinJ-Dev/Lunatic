-- GoFast et GoFast maritime (points dans le panel, page Braquages → GoFast ; réglages dans la page Missions).
-- Au départ (garage ou quai), [E] lance le GoFast : une voiture rapide ou un bateau chargé apparaît, la livraison est tirée au hasard
-- loin du départ, à faire avant la fin du temps. Si la police est sur le coup, elle reçoit la position de la voiture
-- à intervalle régulier. Gain réduit selon l'état de la carrosserie. Tout est revérifié ici (départ, véhicule conduit,
-- distance à la livraison, temps, délai par joueur, limite du jour).

local admin = exports.lunatic_admin

local runs = {}    -- joueur -> GoFast en cours { variant, vehicle, drop, deadline, tracked, nextTrack }
local lastRun = {} -- joueur -> dernier départ (os.time), toutes variantes confondues

-- Variantes : mission du panel, types de points, genre de véhicule, rayon de livraison
local VARIANTS = {
    gofast = { mission = 'gofast', start = 'gofast_start', drop = 'gofast_drop', kind = 'automobile', radius = 12.0, noun = 'la voiture' },
    gofast_sea = { mission = 'gofast_sea', start = 'gofast_sea_start', drop = 'gofast_sea_drop', kind = 'boat', radius = 25.0, noun = 'le bateau' },
}

local function fail(message)
    return { ok = false, error = message }
end

local function spots(v)
    local found, cfg = pcall(function() return admin:getHoldupConfig() end)
    local starts, drops = {}, {}

    if found and cfg then
        for _, point in ipairs(cfg.points) do
            if point.active and point.type == v.start then
                starts[point.id] = point
            elseif point.active and point.type == v.drop then
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

-- Départs des variantes activées, pour l'invite en jeu
lib.callback.register('lunatic_illegal:gofastConfig', function()
    local list = {}

    for id, v in pairs(VARIANTS) do
        local m = MissionSettings(v.mission)

        if m and m.enabled then
            for _, point in pairs((spots(v))) do
                list[#list + 1] = { id = point.id, variant = id, x = point.x, y = point.y, z = point.z }
            end
        end
    end

    return { enabled = #list > 0, starts = list }
end)

local function refreshClients()
    TriggerClientEvent('lunatic_illegal:gofastConfigChanged', -1)
end

AddEventHandler('lunatic_admin:heistsChanged', refreshClients)
AddEventHandler('lunatic_admin:holdupsChanged', refreshClients)

lib.callback.register('lunatic_illegal:gofastStart', function(src, startId, variantId)
    local v = VARIANTS[variantId] or VARIANTS.gofast
    local m = MissionSettings(v.mission)
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

    local starts, drops = spots(v)
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

    if not admin:takeMissionSlot(v.mission) then
        return fail("Plus de GoFast aujourd'hui : la route est surveillée.")
    end

    -- Bateau : 6 m devant le quai (dans la direction prise à « Définir »), sur l'eau
    local x, y, z = start.x, start.y, start.z + 0.5

    if v.kind == 'boat' then
        local heading = math.rad(start.h or 0.0)
        x, y, z = start.x - math.sin(heading) * 6.0, start.y + math.cos(heading) * 6.0, 0.5
    end

    -- Le véhicule est créé par le jeu du joueur (le véhicule créé par le serveur n'arrivait pas toujours chez lui),
    -- puis déclaré ici et vérifié (lunatic_illegal:gofastVehicle) ; sans véhicule au bout de 20 s, le GoFast est annulé
    lastRun[src] = now
    local plate = ('GF%04d'):format(math.random(0, 9999))
    runs[src] = {
        variant = v, vehicle = nil, model = joaat(a.vehicle), spawn = vector3(x, y, z), plate = plate, drop = drop, startedAt = now,
        deadline = now + a.duration * 60, tracked = math.random(100) <= a.alert, nextTrack = now + 20,
    }

    return {
        ok = true, model = a.vehicle, plate = plate, x = x, y = y, z = z, h = start.h or 0.0, minutes = a.duration, noun = v.noun, radius = v.radius,
        drop = { x = drop.x, y = drop.y, z = drop.z, label = drop.label },
    }
end)

-- Le joueur a créé le véhicule : bon modèle, au bon endroit, encore jamais déclaré
lib.callback.register('lunatic_illegal:gofastVehicle', function(src, netId)
    local run = runs[src]
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)

    if not run or run.vehicle then
        return false
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityModel(vehicle) ~= run.model or #(GetEntityCoords(vehicle) - run.spawn) > 25.0 then
        return false
    end

    run.vehicle = vehicle
    Entity(vehicle).state:set('lunaticGoFast', src, true)
    return true
end)

-- Temps écoulé, voiture détruite, et position envoyée à la police si elle est sur le coup
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()

        for src, run in pairs(runs) do
            local m = MissionSettings(run.variant.mission)

            -- Détruit = moteur explosé, une fois qu'un joueur contrôle le véhicule (avant, son état n'est pas encore
            -- synchronisé ; GetEntityHealth d'un véhicule vaut 0 côté serveur et le faisait croire détruit tout de suite)
            local wrecked = run.vehicle and DoesEntityExist(run.vehicle) and now - run.startedAt > 5 and NetworkGetEntityOwner(run.vehicle) ~= -1
                and GetVehicleEngineHealth(run.vehicle) <= -3900.0

            if not run.vehicle then
                -- Véhicule pas encore déclaré par le joueur
                if now - run.startedAt > 20 then
                    lastRun[src] = nil -- pas de délai : rien n'a commencé
                    stop(src, "Le véhicule n'est pas apparu : GoFast annulé, réessayez.", 0)
                end
            elseif not DoesEntityExist(run.vehicle) or wrecked then
                stop(src, ('%s est détruit : GoFast raté.'):format(run.variant.noun == 'le bateau' and 'Le bateau' or 'La voiture'), 0)
            elseif now > run.deadline then
                stop(src, 'Trop tard : le client ne vous attend plus. GoFast raté.', 30000)
            elseif run.tracked and m and now >= run.nextTrack then
                run.nextTrack = now + m.advanced.track
                AlertPolice(GetEntityCoords(run.vehicle), ('GoFast : %s repéré (%s)'):format(run.variant.kind == 'boat' and 'bateau rapide' or 'véhicule rapide', GetVehicleNumberPlateText(run.vehicle) or '?'), 80)
            end
        end
    end
end)

lib.callback.register('lunatic_illegal:gofastFinish', function(src)
    local run = runs[src]
    local m = run and MissionSettings(run.variant.mission)

    if not run or not m then
        return fail('Aucun GoFast en cours.')
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or GetVehiclePedIsIn(ped, false) ~= run.vehicle then
        return fail(('Il faut livrer avec %s du GoFast.'):format(run.variant.noun))
    end

    local coords = GetEntityCoords(run.vehicle)

    if #(coords.xy - vector2(run.drop.x, run.drop.y)) > run.variant.radius then
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

    local reward, loot = MissionPayout(src, paid, coords, run.variant.mission, Config.HoldupAccount)
    return { ok = true, reward = MoneyText(reward), loot = loot, damaged = factor < 0.95 }
end)

RegisterNetEvent('lunatic_illegal:gofastAbandon', function()
    stop(source, 'GoFast abandonné.', 10000)
end)

-- Le véhicule n'a pas pu être créé chez le joueur : annulé sans délai
RegisterNetEvent('lunatic_illegal:gofastSpawnFailed', function()
    local run = runs[source]

    if run and not run.vehicle then
        lastRun[source] = nil
        stop(source, "Le véhicule n'a pas pu apparaître : GoFast annulé, réessayez.", 0)
    end
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
            if run.vehicle and DoesEntityExist(run.vehicle) then
                DeleteEntity(run.vehicle)
            end
        end
    end
end)
