-- Tournées d'intérim côté client (Livreur, Facteur, Éboueur) : dépôt ([E] commencer / terminer / abandonner), arrêts tirés
-- au hasard sur les routes, colis à prendre à l'arrière du véhicule et à porter à l'arrêt (Livreur, Facteur), sacs à
-- ramasser à l'arrêt et à jeter dans la benne (Éboueur). Le serveur valide chaque étape et paie à la fin.

local mission = nil -- { task, netId, stops, index, bags, carrying, prop, pile, blip }
local depotBlip, depotBlipJob = nil, nil
local shown = false

local PROPS = { parcel = 'hei_prop_heist_box', bag = 'prop_cs_rub_binbag_01', pile = 'prop_rub_binbag_03b' }

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function prompt(text)
    if shown ~= text then
        shown = text
        lib.showTextUI(text)
    end
end

local function hidePrompt()
    if shown then
        shown = false
        lib.hideTextUI()
    end
end

-- Métier d'intérim du joueur (second métier, statebag interimJob) avec une tournée, et ses réglages
local function routeJob()
    local job = JobById(LocalPlayer.state.interimJob)
    return job and job.kind == 'route' and job or nil, job and JobSettings(job.id) or nil
end

local function missionVehicle()
    if not mission or not NetworkDoesNetworkIdExist(mission.netId) then
        return 0
    end

    return NetworkGetEntityFromNetworkId(mission.netId)
end

-- Arrière du véhicule (là où l'on prend un colis ou jette un sac)
local function vehicleRear(vehicle)
    local min = GetModelDimensions(GetEntityModel(vehicle))
    return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, min.y - 0.6, 0.0)
end

---------------------------------------------------------------------
-- Objets portés
---------------------------------------------------------------------

local function loadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000

    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
        Wait(10)
    end

    return HasAnimDictLoaded(dict)
end

local function dropCarried()
    if mission and mission.prop and DoesEntityExist(mission.prop) then
        DeleteEntity(mission.prop)
    end

    if mission then
        mission.prop, mission.carrying = nil, nil
    end

    ClearPedSecondaryTask(PlayerPedId())
end

-- Colis dans les mains, ou sac à la main droite
local function carry(kind)
    local ped = PlayerPedId()
    local model = joaat(kind == 'parcel' and PROPS.parcel or PROPS.bag)

    if not lib.requestModel(model, 5000) then
        return
    end

    local coords = GetEntityCoords(ped)
    local prop = CreateObject(model, coords.x, coords.y, coords.z + 0.2, true, true, false)
    SetModelAsNoLongerNeeded(model)

    if kind == 'parcel' then
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 60309), 0.025, 0.08, 0.255, -145.0, 290.0, 0.0, true, true, false, true, 1, true)

        if loadDict('anim@heists@box_carry@') then
            TaskPlayAnim(ped, 'anim@heists@box_carry@', 'idle', 3.0, 3.0, -1, 49, 0.0, false, false, false)
        end
    else
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 57005), 0.4, 0.0, 0.0, 0.0, 270.0, 60.0, true, true, false, true, 1, true)

        if loadDict('missfbi4prepp1') then
            TaskPlayAnim(ped, 'missfbi4prepp1', '_bag_walk_garbage_man', 3.0, 3.0, -1, 49, 0.0, false, false, false)
        end
    end

    mission.prop, mission.carrying = prop, kind
end

-- Tas de sacs posé à l'arrêt (Éboueur), visible seulement par ce joueur
local function placePile(stop)
    local model = joaat(PROPS.pile)

    if mission.pile or not lib.requestModel(model, 5000) then
        return
    end

    mission.pile = CreateObject(model, stop.x, stop.y, stop.z - 1.0, false, false, false)
    SetModelAsNoLongerNeeded(model)
    PlaceObjectOnGroundProperly(mission.pile)
    FreezeEntityPosition(mission.pile, true)
end

local function removePile()
    if mission and mission.pile and DoesEntityExist(mission.pile) then
        DeleteEntity(mission.pile)
    end

    if mission then
        mission.pile = nil
    end
end

---------------------------------------------------------------------
-- Arrêts
---------------------------------------------------------------------

-- Point au bord d'une route, entre min et max mètres du dépôt et à plus de gap des autres arrêts (trottoir si possible)
local function roadStop(depot, chosen)
    local route = Config.Route

    for _ = 1, 40 do
        local angle = math.random() * math.pi * 2
        local distance = route.minDistance + math.random() * (route.maxDistance - route.minDistance)
        local x, y = depot.x + math.cos(angle) * distance, depot.y + math.sin(angle) * distance

        RequestPathNodesInArea(x - 60.0, y - 60.0, x + 60.0, y + 60.0)
        local timeout = GetGameTimer() + 1000

        while not ArePathNodesLoadedInArea(x - 60.0, y - 60.0, x + 60.0, y + 60.0) and GetGameTimer() < timeout do
            Wait(0)
        end

        local found, node = GetClosestVehicleNode(x, y, 30.0, 0, 3.0, 0)

        if found then
            local far = #(vector2(node.x, node.y) - vector2(depot.x, depot.y))
            local spaced = far >= route.minDistance and far <= route.maxDistance

            for _, other in ipairs(chosen) do
                if #(vector2(node.x, node.y) - vector2(other.x, other.y)) < route.gap then
                    spaced = false
                end
            end

            if spaced then
                local safe, sidewalk = GetSafeCoordForPed(node.x, node.y, node.z, true, 16)
                local point = safe and #(sidewalk - node) < 15.0 and sidewalk or node
                return { x = point.x, y = point.y, z = point.z }
            end
        end
    end
end

local function setStopBlip()
    if mission.blip then
        RemoveBlip(mission.blip)
        mission.blip = nil
    end

    local _, settings = routeJob()
    local target = mission.stops[mission.index] or (settings and settings.depot)

    if not target then
        return
    end

    mission.blip = AddBlipForCoord(target.x, target.y, target.z)
    SetBlipSprite(mission.blip, mission.stops[mission.index] and 1 or 50)
    SetBlipColour(mission.blip, 27)
    SetBlipRoute(mission.blip, true)
    SetBlipRouteColour(mission.blip, 27)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(mission.stops[mission.index] and ('Arrêt %d / %d'):format(mission.index, #mission.stops) or 'Retour au dépôt')
    EndTextCommandSetBlipName(mission.blip)
end

local function endMission(message, kind)
    if not mission then
        return
    end

    dropCarried()
    removePile()

    if mission.blip then
        RemoveBlip(mission.blip)
    end

    mission = nil
    hidePrompt()

    if message then
        notify(message, kind)
    end
end

RegisterNetEvent('lunatic_interim:missionEnded', function(message, kind)
    endMission(message, kind)
end)

local function startMission(job, settings)
    notify('Préparation de la tournée…', 'info')
    local stops = {}

    for _ = 1, settings.stops do
        local point = roadStop(settings.depot, stops)

        if not point then
            return notify('Impossible de préparer la tournée ici, réessayez.', 'error')
        end

        stops[#stops + 1] = point
    end

    local result = lib.callback.await('lunatic_interim:missionStart', false, stops)

    if not result or not result.ok then
        return notify(result and result.error or 'Tournée impossible.', 'error')
    end

    mission = { task = result.task, netId = result.netId, stops = result.stops, index = 1, bags = result.bags }
    setStopBlip()
    notify(job.task == 'garbage'
        and ('Tournée de %d arrêts : ramassez les sacs à chaque arrêt et jetez-les dans la benne.'):format(#stops)
        or ('Tournée de %d arrêts : prenez un colis à l\u{2019}arrière du véhicule et livrez-le à chaque arrêt.'):format(#stops), 'success')
end

local function stopDone()
    local result = lib.callback.await('lunatic_interim:missionStop', false, mission.index)

    if not result or not result.ok then
        return notify(result and result.error or 'Arrêt refusé.', 'error')
    end

    removePile()
    mission.index = result.index
    mission.bags = Config.Route.garbageBags
    setStopBlip()
    notify(result.done and 'Tournée terminée : retournez au dépôt avec le véhicule.' or ('Arrêt fait. Suivant : %d / %d.'):format(mission.index, #mission.stops), 'success')
end

---------------------------------------------------------------------
-- Boucle : dépôt, arrêts, colis et sacs
---------------------------------------------------------------------

CreateThread(function()
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local onFoot = not IsPedInAnyVehicle(ped, false)
        local job, settings = routeJob()
        local text, action = nil, nil

        -- Blip du dépôt de son métier
        -- Autre métier ou dépôt déplacé : blip refait
        if depotBlip and (not job or not settings.depot or depotBlipJob ~= job.id .. (settings.depot and settings.depot.x or '')) then
            RemoveBlip(depotBlip)
            depotBlip = nil
        end

        if job and settings.depot and not depotBlip then
            depotBlipJob = job.id .. settings.depot.x
            depotBlip = AddBlipForCoord(settings.depot.x, settings.depot.y, settings.depot.z)
            SetBlipSprite(depotBlip, 478)
            SetBlipColour(depotBlip, 27)
            SetBlipScale(depotBlip, 0.8)
            SetBlipAsShortRange(depotBlip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(('Dépôt : %s'):format(job.label))
            EndTextCommandSetBlipName(depotBlip)
        end

        -- Dépôt : commencer, terminer ou abandonner
        if job and settings.depot then
            local depot = vector3(settings.depot.x, settings.depot.y, settings.depot.z)
            local distance = #(coords - depot)

            if distance < 30.0 then
                wait = 0
                DrawMarker(1, depot.x, depot.y, depot.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.3, 150, 80, 255, 110, false, false, 2, false, nil, nil, false)

                if distance <= 2.5 then
                    if not mission then
                        text, action = ('[E] Commencer la tournée (%s)'):format(job.label), function() startMission(job, settings) end
                    elseif mission.index > #mission.stops then
                        text, action = '[E] Terminer la tournée', function()
                            local result = lib.callback.await('lunatic_interim:missionFinish', false)

                            if result and result.ok then
                                endMission(result.salary > 0 and ('Tournée terminée : %d $ versés sur votre compte.'):format(result.salary) or 'Tournée terminée.', 'success')
                            else
                                notify(result and result.error or 'Impossible de terminer.', 'error')
                            end
                        end
                    else
                        text, action = '[E] Abandonner la tournée', function()
                            local answer = lib.alertDialog({ header = 'Abandonner la tournée ?', content = 'Le véhicule est rendu, la tournée n\u{2019}est pas payée.', centered = true, cancel = true, labels = { confirm = 'Abandonner', cancel = 'Continuer' } })

                            if answer == 'confirm' then
                                lib.callback.await('lunatic_interim:missionCancel', false)
                                endMission('Tournée abandonnée.', 'info')
                            end
                        end
                    end
                end
            end
        end

        -- Arrêt en cours
        local stop = mission and mission.stops[mission.index]

        if stop then
            local target = vector3(stop.x, stop.y, stop.z)
            local distance = #(coords - target)
            local vehicle = missionVehicle()

            if distance < 80.0 then
                wait = 0
                DrawMarker(1, target.x, target.y, target.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.3, 255, 200, 80, 140, false, false, 2, false, nil, nil, false)

                if mission.task == 'garbage' then
                    placePile(target)
                end
            end

            -- Porter dans un véhicule : l'objet est reposé
            if mission.carrying and not onFoot then
                dropCarried()
            end

            if onFoot and vehicle ~= 0 and DoesEntityExist(vehicle) then
                local rear = vehicleRear(vehicle)
                local nearRear = #(coords - rear) <= 2.5

                if nearRear then
                    wait = 0
                end

                if mission.task == 'parcel' then
                    if not mission.carrying and nearRear then
                        text, action = '[E] Prendre un colis', function() carry('parcel') end
                    elseif mission.carrying and distance <= 2.0 then
                        text, action = '[E] Livrer le colis', function()
                            dropCarried()
                            stopDone()
                        end
                    end
                else
                    if not mission.carrying and distance <= 2.0 and mission.bags > 0 then
                        text, action = ('[E] Ramasser un sac (%d)'):format(mission.bags), function() carry('bag') end
                    elseif mission.carrying and nearRear then
                        text, action = '[E] Jeter dans la benne', function()
                            if loadDict('missfbi4prepp1') then
                                TaskPlayAnim(PlayerPedId(), 'missfbi4prepp1', '_bag_throw_garbage_man', 8.0, 8.0, 1100, 48, 0.0, false, false, false)
                                Wait(800)
                            end

                            dropCarried()
                            mission.bags = mission.bags - 1

                            if mission.bags <= 0 then
                                stopDone()
                            end
                        end
                    end
                end
            end
        end

        if text then
            wait = 0
            prompt(text)

            if IsControlJustReleased(0, 38) then
                hidePrompt()
                action()
            end
        else
            hidePrompt()
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        endMission(nil)

        if depotBlip then
            RemoveBlip(depotBlip)
        end
    end
end)
