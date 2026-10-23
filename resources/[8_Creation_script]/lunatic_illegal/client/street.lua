-- Délinquance de rue côté client : vol à l'arraché. Tout près d'un passant à pied, [E] arrache son sac.
-- Le serveur décide (réussite, témoin, gain) ; ici l'animation du voleur et la réaction du passant.

local enabled = { snatch = false }
local busy = false
local tried = {} -- passants déjà visés par ce joueur
local promptText = nil

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

-- Passant volable : PNJ humain vivant, à pied, ni policier ni vendeur de magasin, en réseau
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

local function snatch(target)
    busy = true
    hidePrompt()
    tried[target] = true

    local me = PlayerPedId()
    playAnim(me, 'mp_common', 'givetake1_a', 1200)
    Wait(700)

    local res = lib.callback.await('lunatic_illegal:snatch', false, NetworkGetNetworkIdFromEntity(target))

    -- Le passant réagit : il tombe et s'enfuit, ou se débat et appelle à l'aide
    if DoesEntityExist(target) then
        NetworkRequestControlOfEntity(target)
        local timeout = GetGameTimer() + 1000

        while not NetworkHasControlOfEntity(target) and GetGameTimer() < timeout do
            Wait(0)
        end

        if res and res.ok and res.success then
            SetPedToRagdoll(target, 1500, 2000, 0, false, false, false)
            SetTimeout(1600, function()
                if DoesEntityExist(target) then
                    TaskSmartFleePed(target, me, 150.0, -1, false, false)
                end
            end)
        elseif res and res.ok then
            TaskSmartFleePed(target, me, 150.0, -1, false, false)
        end
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

CreateThread(function()
    while true do
        local wait = 400
        local target = nil

        if enabled.snatch and not busy then
            local me = PlayerPedId()

            if not IsPedInAnyVehicle(me, false) and not IsEntityDead(me) then
                local coords = GetEntityCoords(me)
                local best = 1.6

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

        if target then
            showPrompt("[E] Arracher son sac")
            local until_ = GetGameTimer() + 400

            -- Attente de la touche tant que le passant reste à portée
            while GetGameTimer() < until_ and not busy do
                if IsControlJustPressed(0, 38) then
                    snatch(target)
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
