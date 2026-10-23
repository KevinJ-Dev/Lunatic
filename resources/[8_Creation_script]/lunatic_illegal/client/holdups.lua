-- Braquages de magasins côté client. Les vendeurs sont créés par le serveur (en réseau, vus de tous, tuables) et
-- reconnus ici par leur statebag « lunaticClerk ». Menace : viser le vendeur avec une arme à feu, ou [E] tout près
-- avec une arme blanche ou à feu ; compte à rebours tant que le vendeur reste tenu en respect.
-- Le joueur qui contrôle le PNJ joue ses animations (vues de tous). Le serveur revérifie tout.

local clerks = {}   -- point -> PNJ du vendeur (présent autour du joueur)
local prepared = {} -- PNJ -> réglé par ce joueur (quand il en a le contrôle)
local unknown = {}  -- points placés sur la carte dont la hauteur reste à mesurer : id -> { x, y }
local measured = {} -- points déjà mesurés par ce joueur
local blocked = {}  -- point -> pas de nouvel essai avant (évite de relancer en boucle en visant)
local busy = false
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
    local list = lib.callback.await('lunatic_illegal:holdupConfig', false)

    if type(list) ~= 'table' then
        return
    end

    unknown, measured = {}, {}

    for _, point in ipairs(list) do
        unknown[point.id] = point
    end
end

CreateThread(function()
    Wait(2500)
    loadConfig()
end)

RegisterNetEvent('lunatic_illegal:holdupConfigChanged', loadConfig)

---------------------------------------------------------------------
-- Vendeurs autour du joueur
---------------------------------------------------------------------

-- Réglages du PNJ par le joueur qui le contrôle : reste à son comptoir, ne réagit pas tout seul
local function prepare(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedKeepTask(ped, true)
    SetPedCanBeTargetted(ped, true)
end

-- Hauteur du sol sous un point placé sur la carte du panel
local function groundZ(x, y)
    for height = 1000.0, 0.0, -25.0 do
        RequestCollisionAtCoord(x, y, height)
        Wait(0)
        local found, z = GetGroundZFor_3dCoord(x, y, height, false)

        if found then
            return z
        end
    end
end

CreateThread(function()
    while true do
        local found = {}
        local me = PlayerId()
        local coords = GetEntityCoords(PlayerPedId())

        for _, ped in ipairs(GetGamePool('CPed')) do
            local id = Entity(ped).state.lunaticClerk

            if id then
                found[id] = ped

                if NetworkGetEntityOwner(ped) == me then
                    if not prepared[ped] then
                        prepared[ped] = true
                        prepare(ped)
                    end
                else
                    prepared[ped] = nil
                end
            end
        end

        clerks = found

        for ped in pairs(prepared) do
            if not DoesEntityExist(ped) then
                prepared[ped] = nil
            end
        end

        -- Mesure du sol pour les points placés sur la carte : le serveur pourra ensuite y faire apparaître le vendeur
        for id, point in pairs(unknown) do
            if not measured[id] and #(coords.xy - vector2(point.x, point.y)) < Config.HoldupSpawnRange then
                measured[id] = true
                local z = groundZ(point.x, point.y)

                if z then
                    TriggerServerEvent('lunatic_illegal:holdupGround', id, z)
                end
            end
        end

        Wait(1000)
    end
end)

---------------------------------------------------------------------
-- Animations du vendeur (jouées par le joueur qui le contrôle, vues de tous)
---------------------------------------------------------------------

local function playAnim(ped, dict, clip, flag)
    if not pcall(lib.requestAnimDict, dict, 3000) then
        return
    end

    TaskPlayAnim(ped, dict, clip, 8.0, -8.0, -1, flag, 0, false, false, false)
    RemoveAnimDict(dict)
end

RegisterNetEvent('lunatic_illegal:holdupClerk', function(netId, state, robber)
    if not NetworkDoesEntityExistWithNetworkId(netId) then
        return
    end

    local ped = NetToPed(netId)

    if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) or NetworkGetEntityOwner(ped) ~= PlayerId() then
        return
    end

    ClearPedTasks(ped)

    if state == 'robbed' then
        -- Mains en l'air, puis vide la caisse dans le sac
        playAnim(ped, 'mp_am_hold_up', 'holdup_victim_20s', 1)
    elseif state == 'done' then
        playAnim(ped, 'missminuteman_1ig_2', 'handsup_base', 49)

        SetTimeout(45000, function()
            if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) and NetworkGetEntityOwner(ped) == PlayerId() then
                ClearPedTasks(ped)
            end
        end)
    elseif state == 'resist' then
        -- A appuyé sur l'alarme et s'enfuit
        local player = robber and GetPlayerFromServerId(robber)
        local target = player and player ~= -1 and GetPlayerPed(player) or PlayerPedId()
        TaskSmartFleePed(ped, target, 100.0, -1, false, false)
    end
end)

---------------------------------------------------------------------
-- Braquage
---------------------------------------------------------------------

local function startHoldup(id)
    busy = true
    hidePrompt()

    local res = lib.callback.await('lunatic_illegal:holdupStart', false, id)

    if not res or not res.ok then
        notify(res and res.error or 'Impossible pour le moment.', 'error')
        blocked[id] = GetGameTimer() + 10000
        busy = false
        return
    end

    local endAt = GetGameTimer() + res.duration * 1000
    local shown = -1
    local cancelled = nil

    -- Garder le vendeur en respect : rester près de lui, arme en main ; s'il meurt, la caisse reste fermée
    while GetGameTimer() < endAt do
        local ped = PlayerPedId()
        local clerk = clerks[id]
        local left = math.ceil((endAt - GetGameTimer()) / 1000)

        if left ~= shown then
            shown = left
            lib.showTextUI(('Le vendeur remplit le sac… %d s'):format(left))
        end

        if not clerk or not DoesEntityExist(clerk) or IsPedDeadOrDying(clerk, true) then
            cancelled = 'dead'
            break
        end

        if #(GetEntityCoords(ped) - GetEntityCoords(clerk)) > Config.HoldupKeepRange or IsEntityDead(ped) or not IsPedArmed(ped, 5) then
            cancelled = 'left'
            break
        end

        Wait(100)
    end

    lib.hideTextUI()

    if cancelled then
        TriggerServerEvent('lunatic_illegal:holdupCancel')
        notify(cancelled == 'dead' and 'Le vendeur est mort : la caisse reste fermée.' or "Vous avez lâché le vendeur : il a déclenché l'alarme.", 'error')
    else
        local done = lib.callback.await('lunatic_illegal:holdupFinish', false)

        if done and done.ok then
            notify(('Braquage réussi : %s en argent sale%s.'):format(done.reward, #done.loot > 0 and (', ' .. table.concat(done.loot, ', ')) or ''), 'success')
        else
            notify(done and done.error or 'Braquage raté.', 'error')
        end
    end

    blocked[id] = GetGameTimer() + 10000
    busy = false
end

CreateThread(function()
    while true do
        local wait = 500
        local prompt = false

        if not busy then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local now = GetGameTimer()

            for id, clerk in pairs(clerks) do
                if DoesEntityExist(clerk) and not IsPedDeadOrDying(clerk, true) and (blocked[id] or 0) < now then
                    local distance = #(coords - GetEntityCoords(clerk))

                    if distance < 15.0 then
                        wait = 0

                        -- Arme à feu pointée sur le vendeur : il lève les mains
                        if distance <= Config.HoldupRange and IsPedArmed(ped, 4) and IsPlayerFreeAimingAtEntity(PlayerId(), clerk) then
                            startHoldup(id)
                            break
                        end

                        -- Tout près, arme blanche ou arme à feu en main (les poings ne suffisent pas)
                        if distance <= 2.5 and IsPedArmed(ped, 5) then
                            prompt = true
                            showPrompt('[E] Menacer le vendeur')

                            if IsControlJustPressed(0, 38) then
                                startHoldup(id)
                                break
                            end
                        end
                    end
                end
            end
        end

        if not prompt then
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
