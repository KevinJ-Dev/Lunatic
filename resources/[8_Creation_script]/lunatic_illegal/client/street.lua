-- Délinquance de rue côté client, près d'un passant à pied :
-- mains nues, [E] arrache son sac (vol à l'arraché) ; arme en main, le viser avec une arme à feu ou [E] tout près
-- le racketter (il lève les mains et vide ses poches tant qu'on le tient en respect).
-- Le serveur décide (réussite, témoin, gain) ; ici les animations et la réaction du passant.

local enabled = { snatch = false, racket = false }
local busy = false
local tried = {} -- passants déjà visés par ce joueur
local promptText = nil
local aimTarget, aimSince = nil, 0 -- passant visé avec une arme à feu, et depuis quand

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
    local cfg = lib.callback.await('lunatic_illegal:streetConfig', false)

    if type(cfg) == 'table' then
        enabled = cfg
    end
end

CreateThread(function()
    Wait(3000)
    loadConfig()
end)

RegisterNetEvent('lunatic_illegal:streetConfigChanged', loadConfig)

-- Passant visable : PNJ humain vivant, à pied, ni policier ni vendeur de magasin, en réseau
local IGNORED_TYPES = { [6] = true, [27] = true, [28] = true, [29] = true } -- policiers, SWAT, animaux, armée

local function isTarget(ped)
    return not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped, true) and not IsPedInAnyVehicle(ped, true)
        and not IGNORED_TYPES[GetPedType(ped)] and IsPedHuman(ped) and NetworkGetEntityIsNetworked(ped)
        and not Entity(ped).state.lunaticClerk and not tried[ped]
end

local function playAnim(ped, dict, clip, duration)
    if not pcall(lib.requestAnimDict, dict, 2000) then
        return
    end

    TaskPlayAnim(ped, dict, clip, 8.0, -8.0, duration, 48, 0, false, false, false)
    RemoveAnimDict(dict)
end

-- Contrôle réseau du passant, pour lui donner des ordres (tomber, fuir, lever les mains)
local function control(ped)
    if not DoesEntityExist(ped) then
        return false
    end

    NetworkRequestControlOfEntity(ped)
    local timeout = GetGameTimer() + 1000

    while not NetworkHasControlOfEntity(ped) and GetGameTimer() < timeout do
        Wait(0)
    end

    return NetworkHasControlOfEntity(ped)
end

local function flee(ped)
    if control(ped) then
        ClearPedTasks(ped)
        TaskSmartFleePed(ped, PlayerPedId(), 150.0, -1, false, false)
    end
end

---------------------------------------------------------------------
-- Vol à l'arraché (mains nues)
---------------------------------------------------------------------

local function snatch(target)
    busy = true
    hidePrompt()
    tried[target] = true

    playAnim(PlayerPedId(), 'mp_common', 'givetake1_a', 1200)
    Wait(700)

    local res = lib.callback.await('lunatic_illegal:snatch', false, NetworkGetNetworkIdFromEntity(target))

    -- Le passant réagit : il tombe et s'enfuit, ou se débat et appelle à l'aide
    if res and res.ok and res.success and control(target) then
        SetPedToRagdoll(target, 1500, 2000, 0, false, false, false)
        SetTimeout(1600, function() flee(target) end)
    elseif res and res.ok then
        flee(target)
    end

    if not res or not res.ok then
        notify(res and res.error or 'Impossible pour le moment.', 'error')
    elseif res.success then
        notify(('Vol réussi : %s%s.'):format(res.reward, #res.loot > 0 and (', ' .. table.concat(res.loot, ', ')) or ''), 'success')
    else
        notify("Le passant s'est débattu et appelle à l'aide !", 'error')
    end

    Wait(1500)
    busy = false
end

---------------------------------------------------------------------
-- Racket (arme en main)
---------------------------------------------------------------------

local function racket(target)
    busy = true
    hidePrompt()
    tried[target] = true

    local res = lib.callback.await('lunatic_illegal:racketStart', false, NetworkGetNetworkIdFromEntity(target))

    if not res or not res.ok then
        notify(res and res.error or 'Impossible pour le moment.', 'error')
        Wait(1000)
        busy = false
        return
    end

    if res.refused then
        flee(target)
        notify("Il ne se laisse pas impressionner et s'enfuit !", 'error')
        Wait(1500)
        busy = false
        return
    end

    -- Mains en l'air, tourné vers le joueur, pendant qu'il vide ses poches
    if control(target) then
        ClearPedTasks(target)
        TaskHandsUp(target, (res.duration + 3) * 1000, PlayerPedId(), -1, true)
    end

    local endAt = GetGameTimer() + res.duration * 1000
    local shown = -1
    local cancelled = false

    while GetGameTimer() < endAt do
        local me = PlayerPedId()
        local left = math.ceil((endAt - GetGameTimer()) / 1000)

        if left ~= shown then
            shown = left
            lib.showTextUI(('Il vide ses poches… %d s'):format(left))
        end

        if not DoesEntityExist(target) or IsPedDeadOrDying(target, true) or IsEntityDead(me) or not IsPedArmed(me, 5)
            or #(GetEntityCoords(me) - GetEntityCoords(target)) > 10.0 then
            cancelled = true
            break
        end

        Wait(100)
    end

    lib.hideTextUI()

    if cancelled then
        TriggerServerEvent('lunatic_illegal:racketCancel')
        notify("Vous l'avez lâché : il s'est enfui.", 'error')
    else
        local done = lib.callback.await('lunatic_illegal:racketFinish', false)

        if done and done.ok then
            notify(('Racket réussi : %s%s.'):format(done.reward, #done.loot > 0 and (', ' .. table.concat(done.loot, ', ')) or ''), 'success')
        else
            notify(done and done.error or 'Racket raté.', 'error')
        end
    end

    flee(target)
    Wait(1500)
    busy = false
end

---------------------------------------------------------------------
-- Détection des passants
---------------------------------------------------------------------

CreateThread(function()
    while true do
        local wait = 400
        local target, armed = nil, false

        if (enabled.snatch or enabled.racket) and not busy then
            local me = PlayerPedId()

            if not IsPedInAnyVehicle(me, false) and not IsEntityDead(me) then
                armed = IsPedArmed(me, 5)

                -- Arme à feu pointée sur un passant (jusqu'à 8 m) pendant une seconde : racket
                if armed and enabled.racket and IsPedArmed(me, 4) then
                    local found, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())

                    if found and entity ~= 0 and IsEntityAPed(entity) and isTarget(entity) and #(GetEntityCoords(me) - GetEntityCoords(entity)) <= 8.0 then
                        wait = 100

                        if aimTarget ~= entity then
                            aimTarget, aimSince = entity, GetGameTimer()
                        elseif GetGameTimer() - aimSince >= 1000 then
                            aimTarget = nil
                            racket(entity)
                        end
                    else
                        aimTarget = nil
                    end
                end

                if not busy and ((armed and enabled.racket) or (not armed and enabled.snatch)) then
                    local coords = GetEntityCoords(me)
                    local best = armed and 2.0 or 1.6

                    for _, ped in ipairs(GetGamePool('CPed')) do
                        if ped ~= me then
                            local distance = #(coords - GetEntityCoords(ped))

                            if distance < best and isTarget(ped) then
                                best, target = distance, ped
                            end
                        end
                    end
                end
            end
        end

        if target then
            showPrompt(armed and '[E] Racketter' or '[E] Arracher son sac')
            local untilAt = GetGameTimer() + 400

            -- Attente de la touche tant que le passant reste à portée
            while GetGameTimer() < untilAt and not busy do
                if IsControlJustPressed(0, 38) then
                    if armed then
                        racket(target)
                    else
                        snatch(target)
                    end

                    break
                end

                Wait(0)
            end

            wait = 0
        else
            hidePrompt()
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        hidePrompt()
    end
end)
