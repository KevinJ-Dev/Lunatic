-- GoFast et GoFast maritime côté client : au départ (garage ou quai), [E] lance le GoFast ; itinéraire vers la
-- livraison, temps restant à l'écran, [E] au point de livraison avec le véhicule. Le serveur revérifie tout.

local cfg = { enabled = false, starts = {} }
local busy = false
local promptText = nil
local run = nil -- { netId, drop, endsAt, blip, noun, radius }

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function showPrompt(text)
    if promptText ~= text then
        promptText = text
        lib.showTextUI(text)
    end
end

local function hidePrompt()
    if promptText then
        promptText = nil
        lib.hideTextUI()
    end
end

local function loadConfig()
    local result = lib.callback.await('lunatic_illegal:gofastConfig', false)

    if type(result) == 'table' then
        cfg = result
    end
end

CreateThread(function()
    Wait(3000)

    while true do
        loadConfig()
        Wait(60000)
    end
end)

RegisterNetEvent('lunatic_illegal:gofastConfigChanged', loadConfig)

-- GPS du jeu (point de passage) vers la livraison, réglé en montant dans le véhicule
local function setGps()
    SetNewWaypoint(run.drop.x + 0.0, run.drop.y + 0.0)
    run.gps = true
end

local function clearRun()
    if run and run.blip and DoesBlipExist(run.blip) then
        RemoveBlip(run.blip)
    end

    -- Retire le point GPS s'il visait encore la livraison
    if run and run.gps and IsWaypointActive() then
        local waypoint = GetBlipInfoIdCoord(GetFirstBlipInfoId(8))

        if #(vector2(waypoint.x, waypoint.y) - vector2(run.drop.x, run.drop.y)) < 5.0 then
            SetWaypointOff()
        end
    end

    run = nil
    hidePrompt()
end

local function start(point)
    busy = true
    hidePrompt()

    local res = lib.callback.await('lunatic_illegal:gofastStart', false, point.id, point.variant)

    if not res or not res.ok then
        notify(res and res.error or 'Impossible pour le moment.', 'error')
        Wait(1000)
        busy = false
        return
    end

    -- Livraison sur la carte ; le GPS du jeu s'active en montant dans le véhicule
    local blip = AddBlipForCoord(res.drop.x, res.drop.y, res.drop.z)
    SetBlipSprite(blip, 501)
    SetBlipColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Livraison GoFast')
    EndTextCommandSetBlipName(blip)

    run = { netId = res.netId, drop = res.drop, endsAt = GetGameTimer() + res.minutes * 60000, blip = blip, noun = res.noun or 'la voiture', radius = res.radius or 12.0 }
    notify(("GoFast : %s est prêt%s. Livrez à %s en moins de %d min, sans l'abîmer."):format(run.noun, run.noun == 'la voiture' and 'e' or '', res.drop.label, res.minutes), 'success')
    busy = false
end

local function finish()
    busy = true
    hidePrompt()

    local res = lib.callback.await('lunatic_illegal:gofastFinish', false)

    if res and res.ok then
        clearRun()
        notify(('GoFast livré : %s en argent sale%s.'):format(res.reward, res.damaged and ' (véhicule abîmé : gain réduit)' or ''), 'success')
    else
        notify(res and res.error or 'Livraison impossible.', 'error')
    end

    Wait(1000)
    busy = false
end

RegisterNetEvent('lunatic_illegal:gofastEnded', function(message)
    clearRun()
    notify(message, 'error')
end)

CreateThread(function()
    while true do
        local wait = 500
        local prompt = nil

        if not busy then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)

            if run then
                wait = 0
                local left = math.max(0, math.ceil((run.endsAt - GetGameTimer()) / 1000))
                local vehicle = NetworkDoesEntityExistWithNetworkId(run.netId) and NetToVeh(run.netId) or 0
                local inCar = vehicle ~= 0 and GetVehiclePedIsIn(ped, false) == vehicle

                -- En montant dans le véhicule : GPS vers la livraison (et de nouveau si le point a été retiré,
                -- sauf tout près de la livraison où le jeu le retire de lui-même)
                if inCar and (not run.gps or not IsWaypointActive()) and #(coords.xy - vector2(run.drop.x, run.drop.y)) > 60.0 then
                    setGps()
                end

                if #(coords.xy - vector2(run.drop.x, run.drop.y)) < run.radius and inCar then
                    prompt = ('[E] Livrer %s'):format(run.noun)

                    if IsControlJustPressed(0, 38) then
                        finish()
                    end
                else
                    prompt = ('GoFast · %s · %d:%02d'):format(run.drop.label, left // 60, left % 60)
                end
            elseif cfg.enabled and not IsPedInAnyVehicle(ped, false) then
                for _, point in ipairs(cfg.starts or {}) do
                    if #(coords.xy - vector2(point.x, point.y)) < 2.5 and math.abs(coords.z - point.z) < 5.0 then
                        wait = 0
                        prompt = point.variant == 'gofast_sea' and '[E] Lancer un GoFast maritime' or '[E] Lancer un GoFast'

                        if IsControlJustPressed(0, 38) then
                            start(point)
                        end

                        break
                    end
                end
            end
        end

        if prompt then
            showPrompt(prompt)
        else
            hidePrompt()
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clearRun()
    end
end)
