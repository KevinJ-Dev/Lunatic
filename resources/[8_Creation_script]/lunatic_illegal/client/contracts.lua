-- Contrats de mission côté client : objectif du contrat en cours du crew (blip, marqueur, [E]),
-- alarme du véhicule volé, gardes de la cargaison et caisse. Le serveur valide chaque étape.

local contract = nil
local blip, crate
local busy = false
local guardsAsked = false

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function removeBlip()
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end

    blip = nil
end

local function removeCrate()
    if crate and DoesEntityExist(crate) then
        DeleteEntity(crate)
    end

    crate = nil
end

-- Blip de l'objectif pour tous les membres du crew
local function refreshBlip()
    removeBlip()

    if not contract then
        return
    end

    local o = contract.objective
    blip = AddBlipForCoord(o.x + 0.0, o.y + 0.0, o.z + 0.0)
    SetBlipSprite(blip, contract.type == 'theft' and 225 or contract.type == 'cargo' and 478 or 501)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.85)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('Contrat : %s'):format(contract.stageText))
    EndTextCommandSetBlipName(blip)
end

RegisterNetEvent('lunatic_illegal:contractUpdate', function(data)
    local previous = contract
    contract = data

    if not data then
        guardsAsked = false
        removeCrate()

        if previous then
            notify('Le contrat du crew est terminé.', 'info')
        end
    elseif not previous or previous.id ~= data.id then
        guardsAsked = false
    end

    refreshBlip()
end)

CreateThread(function()
    Wait(3000)

    if LocalPlayer.state.crew then
        contract = lib.callback.await('lunatic_illegal:contractState', false)
        refreshBlip()
    end
end)

AddStateBagChangeHandler('crew', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    if not value then
        contract = nil
        refreshBlip()
        removeCrate()
    end
end)

local function run(action)
    busy = true
    local result = lib.callback.await('lunatic_illegal:contractAction', false, action)
    busy = false

    if not result or not result.ok then
        return notify(result and result.error or 'Action impossible.', 'error')
    end

    if result.message then
        notify(result.message, 'success')
    end

    if result.waypoint then
        SetNewWaypoint(result.waypoint.x + 0.0, result.waypoint.y + 0.0)
    end
end

local function withProgress(duration, label, anim, action)
    busy = true

    local done = lib.progressBar({
        duration = duration, label = label, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = anim,
    })

    busy = false

    if done then
        run(action)
    end
end

---------------------------------------------------------------------
-- Cargaison gardée : gardes hostiles (réseau, visibles par tous) et caisse
---------------------------------------------------------------------

local GUARDS = `LUNATIC_CONTRACT_GUARDS`

local function spawnGuards(settings)
    AddRelationshipGroup('LUNATIC_CONTRACT_GUARDS')
    SetRelationshipBetweenGroups(5, GUARDS, `PLAYER`)
    SetRelationshipBetweenGroups(5, `PLAYER`, GUARDS)

    local model = joaat(settings.model)
    lib.requestModel(model)
    local o = contract.objective
    local netIds = {}

    for _ = 1, settings.count do
        local angle = math.random() * math.pi * 2
        local distance = math.random(6, 16)
        local x, y = o.x + math.cos(angle) * distance, o.y + math.sin(angle) * distance
        local found, ground = GetGroundZFor_3dCoord(x, y, o.z + 5.0, false)
        local ped = CreatePed(4, model, x, y, found and ground or o.z, math.random(0, 359) + 0.0, true, true)

        SetEntityAsMissionEntity(ped, true, true)
        SetPedRelationshipGroupHash(ped, GUARDS)
        GiveWeaponToPed(ped, joaat(settings.weapon), 250, false, true)
        SetPedArmour(ped, 50)
        SetPedAccuracy(ped, 35)
        SetPedCombatAbility(ped, 1)
        SetPedCombatRange(ped, 1)
        SetPedCombatAttributes(ped, 46, true)
        SetPedFleeAttributes(ped, 0, false)
        SetPedDropsWeaponsWhenDead(ped, false)
        TaskCombatHatedTargetsAroundPed(ped, 80.0, 0)

        local netId = NetworkGetNetworkIdFromEntity(ped)
        SetNetworkIdCanMigrate(netId, true)
        netIds[#netIds + 1] = netId
    end

    SetModelAsNoLongerNeeded(model)
    TriggerServerEvent('lunatic_illegal:contractGuardsSpawned', netIds)
end

---------------------------------------------------------------------
-- Boucle : objectif au sol et [E]
---------------------------------------------------------------------

CreateThread(function()
    local shown
    local vehicleReported = false

    while true do
        local sleep = 1000
        local text, action

        if contract and not busy then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local o = contract.objective
            local point = vector3(o.x, o.y, o.z)
            local distance = #(coords - point)
            local vehicle = GetVehiclePedIsIn(ped, false)

            if contract.stage == 'pickup' or contract.stage == 'deliver_package' then
                if distance < 40.0 then
                    sleep = 0
                    DrawMarker(1, o.x, o.y, o.z - 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.6, 242, 194, 107, 120, false, false, 2, false, nil, nil, false)

                    if distance < 1.8 and vehicle == 0 then
                        if contract.stage == 'pickup' then
                            text, action = '[E] Récupérer le colis scellé', function() withProgress(3000, 'Récupération du colis', { dict = 'anim@heists@box_carry@', clip = 'idle' }, 'pickup') end
                        else
                            text, action = '[E] Livrer le colis', function() withProgress(3000, 'Remise du colis', { dict = 'mp_common', clip = 'givetake1_a' }, 'deliver') end
                        end
                    end
                end
            elseif contract.stage == 'steal' then
                -- Entrée dans le véhicule du contrat : alarme, puis le serveur passe à l'étape suivante
                if vehicle ~= 0 and contract.vehicle and NetworkGetNetworkIdFromEntity(vehicle) == contract.vehicle then
                    if not vehicleReported then
                        vehicleReported = true
                        SetVehicleAlarm(vehicle, true)
                        StartVehicleAlarm(vehicle)
                        CreateThread(function()
                            run('entered')
                            vehicleReported = false
                        end)
                    end
                end
            elseif contract.stage == 'deliver_vehicle' then
                if distance < 50.0 then
                    sleep = 0
                    DrawMarker(1, o.x, o.y, o.z - 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 6.0, 6.0, 0.8, 242, 194, 107, 90, false, false, 2, false, nil, nil, false)

                    if distance < 8.0 and vehicle ~= 0 and NetworkGetNetworkIdFromEntity(vehicle) == contract.vehicle and GetPedInVehicleSeat(vehicle, -1) == ped then
                        text, action = '[E] Livrer le véhicule', function() run('deliver') end
                    end
                end
            elseif contract.stage == 'assault' then
                if distance < 150.0 then
                    sleep = 0

                    if not guardsAsked then
                        guardsAsked = true
                        CreateThread(function()
                            local settings = lib.callback.await('lunatic_illegal:contractGuards', false)

                            if settings and settings.count > 0 then
                                spawnGuards(settings)
                            end
                        end)
                    end

                    -- Caisse posée au point (objet local)
                    if not crate then
                        lib.requestModel(`prop_box_wood02a`)
                        crate = CreateObject(`prop_box_wood02a`, o.x, o.y, o.z, false, false, false)
                        PlaceObjectOnGroundProperly(crate)
                        FreezeEntityPosition(crate, true)
                        SetModelAsNoLongerNeeded(`prop_box_wood02a`)
                    end

                    if distance < 2.5 and vehicle == 0 then
                        text, action = '[E] Ouvrir la caisse', function() withProgress(8000, 'Ouverture de la caisse', { dict = 'mini@repair', clip = 'fixing_a_ped' }, 'open') end
                    end
                elseif crate then
                    removeCrate()
                end
            end
        end

        if text then
            if shown ~= text then
                shown = text
                lib.showTextUI(text)
            end

            if IsControlJustReleased(0, 38) then
                lib.hideTextUI()
                shown = nil
                CreateThread(action)
            end
        elseif shown then
            shown = nil
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)

-- Alerte police liée à un contrat
RegisterNetEvent('lunatic_illegal:contractAlert', function(alert)
    notify(('Signalement : %s dans le secteur indiqué sur la carte.'):format(alert.label:lower()), 'error')
    local area = AddBlipForRadius(alert.x + 0.0, alert.y + 0.0, 0.0, 100.0)
    SetBlipColour(area, 1)
    SetBlipAlpha(area, 120)
    local center = AddBlipForCoord(alert.x + 0.0, alert.y + 0.0, 0.0)
    SetBlipSprite(center, 161)
    SetBlipColour(center, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(alert.label)
    EndTextCommandSetBlipName(center)

    SetTimeout(Config.AlertDuration * 1000, function()
        RemoveBlip(area)
        RemoveBlip(center)
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        removeBlip()
        removeCrate()
    end
end)
