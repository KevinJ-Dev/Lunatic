-- Braquages de magasins côté client : PNJ vendeurs au comptoir (apparition à proximité), menace (viser le vendeur
-- avec une arme à feu, ou [E] tout près avec une arme blanche ou à feu), compte à rebours tant que le vendeur reste
-- tenu en respect. Les animations du vendeur sont partagées avec les joueurs proches. Le serveur revérifie tout.

local points = {}   -- id -> { id, x, y, z, h, ped, weapon }
local clerks = {}   -- id -> PNJ du vendeur (propre à chaque joueur)
local respawnAt = {} -- id -> moment où le vendeur reprend sa place (après avoir résisté)
local blocked = {}  -- id -> pas de nouvel essai avant (évite de relancer en boucle en visant)
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

local function removeClerk(id)
    local ped = clerks[id]

    if ped and DoesEntityExist(ped) then
        DeleteEntity(ped)
    end

    clerks[id] = nil
end

local function loadConfig()
    local list = lib.callback.await('lunatic_illegal:holdupConfig', false)

    if type(list) ~= 'table' then
        return
    end

    local fresh = {}

    for _, point in ipairs(list) do
        fresh[point.id] = point
    end

    -- Points retirés ou modifiés dans le panel : le vendeur réapparaît avec les nouveaux réglages
    for id in pairs(clerks) do
        local old, new = points[id], fresh[id]

        if not new or not old or old.x ~= new.x or old.y ~= new.y or old.z ~= new.z or old.h ~= new.h or old.ped ~= new.ped then
            removeClerk(id)
        end
    end

    points = fresh
end

CreateThread(function()
    Wait(2500)
    loadConfig()
end)

RegisterNetEvent('lunatic_illegal:holdupConfigChanged', loadConfig)

---------------------------------------------------------------------
-- Vendeurs : apparition près des joueurs
---------------------------------------------------------------------

-- Hauteur du sol sous le point (point placé sur la carte du panel : hauteur inconnue)
local function groundZ(point)
    if point.z > -100.0 then
        local found, z = GetGroundZFor_3dCoord(point.x, point.y, point.z + 1.0, false)
        return found and math.abs(z - point.z) < 2.0 and z or point.z
    end

    for height = 1000.0, 0.0, -25.0 do
        RequestCollisionAtCoord(point.x, point.y, height)
        local found, z = GetGroundZFor_3dCoord(point.x, point.y, height, false)

        if found then
            return z
        end
    end

    return nil
end

local function spawnClerk(point)
    local model = joaat(point.ped)

    if not IsModelInCdimage(model) or not IsModelAPed(model) then
        return
    end

    if not pcall(lib.requestModel, model, 5000) then
        return
    end

    local z = groundZ(point)

    if not z then
        return
    end

    local ped = CreatePed(4, model, point.x, point.y, z, point.h or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)

    if ped == 0 then
        return
    end

    SetEntityHeading(ped, point.h or 0.0)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    FreezeEntityPosition(ped, true)
    clerks[point.id] = ped
end

CreateThread(function()
    while true do
        local coords = GetEntityCoords(PlayerPedId()).xy
        local now = GetGameTimer()

        for id, point in pairs(points) do
            local distance = #(coords - vector2(point.x, point.y))

            if distance < Config.HoldupSpawnRange then
                if respawnAt[id] and now >= respawnAt[id] then
                    respawnAt[id] = nil
                    removeClerk(id)
                end

                if not clerks[id] or not DoesEntityExist(clerks[id]) then
                    spawnClerk(point)
                end
            elseif clerks[id] and distance > Config.HoldupSpawnRange + 20.0 then
                respawnAt[id] = nil
                removeClerk(id)
            end
        end

        for id in pairs(clerks) do
            if not points[id] then
                removeClerk(id)
            end
        end

        Wait(1000)
    end
end)

---------------------------------------------------------------------
-- Animations du vendeur (envoyées par le serveur à tous les joueurs)
---------------------------------------------------------------------

local function playAnim(ped, dict, clip, flag)
    if not pcall(lib.requestAnimDict, dict, 3000) then
        return
    end

    TaskPlayAnim(ped, dict, clip, 8.0, -8.0, -1, flag, 0, false, false, false)
    RemoveAnimDict(dict)
end

RegisterNetEvent('lunatic_illegal:holdupClerk', function(id, state)
    local ped = clerks[id]

    if not ped or not DoesEntityExist(ped) then
        return
    end

    ClearPedTasks(ped)

    if state == 'robbed' then
        -- Mains en l'air, puis vide la caisse dans le sac
        playAnim(ped, 'mp_am_hold_up', 'holdup_victim_20s', 1)
    elseif state == 'done' then
        playAnim(ped, 'missminuteman_1ig_2', 'handsup_base', 49)

        SetTimeout(45000, function()
            if DoesEntityExist(ped) then
                ClearPedTasks(ped)
            end
        end)
    elseif state == 'resist' then
        -- A appuyé sur l'alarme et se met à l'abri derrière le comptoir
        FreezeEntityPosition(ped, false)
        TaskCower(ped, -1)
        respawnAt[id] = GetGameTimer() + 60000
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

    local clerk = clerks[id]
    local endAt = GetGameTimer() + res.duration * 1000
    local shown = -1
    local cancelled = false

    -- Garder le vendeur en respect : rester près de lui, arme en main
    while GetGameTimer() < endAt do
        local ped = PlayerPedId()
        local left = math.ceil((endAt - GetGameTimer()) / 1000)

        if left ~= shown then
            shown = left
            lib.showTextUI(('Le vendeur remplit le sac… %d s'):format(left))
        end

        local far = not clerk or not DoesEntityExist(clerk) or #(GetEntityCoords(ped) - GetEntityCoords(clerk)) > Config.HoldupKeepRange

        if far or IsEntityDead(ped) or not IsPedArmed(ped, 5) then
            cancelled = true
            break
        end

        Wait(100)
    end

    lib.hideTextUI()

    if cancelled then
        TriggerServerEvent('lunatic_illegal:holdupCancel')
        notify("Vous avez lâché le vendeur : il a déclenché l'alarme.", 'error')
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
                if DoesEntityExist(clerk) and not respawnAt[id] and (blocked[id] or 0) < now then
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

        for id in pairs(clerks) do
            removeClerk(id)
        end
    end
end)
