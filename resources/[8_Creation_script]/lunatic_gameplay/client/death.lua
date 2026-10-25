-- Mort et respawn côté client : écran d'inconscience (html/ : délai, appel des secours, réveil à l'hôpital),
-- réanimation par un médecin (/reanimer). Le serveur valide le délai, les frais et la réanimation.

local dead = false
local remaining = 0

local function resurrect(x, y, z, h)
    local ped = PlayerPedId()
    DoScreenFadeOut(400)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    NetworkResurrectLocalPlayer(x, y, z, h or 0.0, true, false)
    ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    ClearPedBloodDamage(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))

    -- ESX repasse le joueur en vie et relance sa détection de mort
    TriggerServerEvent('esx:onPlayerSpawn')
    TriggerEvent('esx:onPlayerSpawn')

    Wait(500)
    DoScreenFadeIn(600)
end

local function stopDeath()
    dead = false
    AnimpostfxStop('DeathFailOut')
    SendNUIMessage({ action = 'deathHide' })
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
end

-- État de l'écran (temps restant, secouristes en service, appel déjà fait) : le serveur fait foi ; true si reçu
local function refreshDeath()
    local state = lib.callback.await('lunatic_gameplay:deathState', false)

    if not state or not dead then
        return false
    end

    remaining = state.remaining or remaining
    state.action = 'deathUpdate'
    SendNUIMessage(state)
    return true
end

local function callMedic()
    TriggerServerEvent('lunatic_gameplay:callMedic')
    Wait(300)
    refreshDeath()
end

local function respawn()
    local result = lib.callback.await('lunatic_gameplay:respawn', false)

    if not result or not result.ok then
        return Notify(result and result.error or 'Réveil impossible.', 'error')
    end

    stopDeath()
    resurrect(result.x, result.y, result.z, result.h)
    Notify(result.fee > 0 and ('Vous vous réveillez à %s (frais : %s %s).'):format(result.label, result.fee, GlobalState.lunaticCurrency or '$')
        or ('Vous vous réveillez à %s.'):format(result.label), 'info')
end

-- Sol sous un point placé sur la carte du panel (hauteur inconnue)
local function groundAt(x, y)
    for height = 1000.0, 0.0, -25.0 do
        RequestCollisionAtCoord(x, y, height)
        Wait(0)

        local found, z = GetGroundZFor_3dCoord(x, y, height, false)

        if found then
            return z
        end
    end

    return 200.0
end

-- Zone d'un event (lunatic_admin) sans coma : réveil sur place ; avec respawn : au centre de la zone après un délai
local function eventRevive(event, fallback)
    dead = true

    CreateThread(function()
        local untilAt = GetGameTimer() + (event.noKO and 1500 or Config.EventRespawnDelay * 1000)

        while GetGameTimer() < untilAt do
            if not event.noKO then
                DrawScreenText(0.5, 0.86, ('Respawn dans %d s'):format(math.ceil((untilAt - GetGameTimer()) / 1000)), 0.45)
            end

            Wait(0)
        end

        local result = lib.callback.await('lunatic_gameplay:eventRevive', false)

        if not result or not result.ok then
            -- Plus dans la zone (event déchargé entre-temps) : mort normale
            dead = false
            return fallback()
        end

        dead = false

        if result.here then
            local coords = GetEntityCoords(PlayerPedId())
            return resurrect(coords.x, coords.y, coords.z, GetEntityHeading(PlayerPedId()))
        end

        resurrect(result.x, result.y, result.z > -100.0 and result.z or groundAt(result.x, result.y) + 1.0, 0.0)
    end)
end

local function startDeath(skipEvent)
    if dead then
        return
    end

    local event = LocalPlayer.state.lunaticEvent

    if not skipEvent and event and (event.noKO or event.respawn) then
        return eventRevive(event, function() startDeath(true) end)
    end

    dead = true
    AnimpostfxPlay('DeathFailOut', 0, true)
    remaining = 300
    SendNUIMessage({ action = 'death', remaining = remaining, callMedic = FeaturesOf('death').callMedic ~= false })

    -- Souris pour les boutons ; le jeu garde le clavier (vocal, touches [G] et [E])
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)

    -- Compte à rebours, recalé sur le serveur toutes les 10 s (secouristes qui prennent ou quittent leur service)
    CreateThread(function()
        local tick = 0
        local synced = false

        -- Le serveur enregistre la mort juste après ce client : premiers essais rapprochés
        for _ = 1, 10 do
            Wait(300)
            synced = refreshDeath()

            if synced or not dead then
                break
            end
        end

        while dead and remaining > 0 do
            Wait(1000)
            remaining = remaining - 1
            tick = tick + 1

            if not synced or tick % 10 == 0 then
                synced = refreshDeath() or synced
            end
        end

        -- Mort désactivée dans le panel : réveil automatique à l'hôpital
        if dead and FeaturesOf('death').enabled == false then
            respawn()
        end
    end)

    CreateThread(function()
        while dead do
            -- Pas de caméra ni d'attaque à la souris pendant que le curseur est affiché
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)

            if remaining <= 0 and IsControlJustReleased(0, 38) then
                respawn()
            end

            if FeaturesOf('death').callMedic ~= false and IsControlJustReleased(0, 47) then
                CreateThread(callMedic)
            end

            Wait(0)
        end
    end)
end

RegisterNUICallback('deathAlert', function(_, cb)
    cb({})

    if dead and FeaturesOf('death').callMedic ~= false then
        callMedic()
    end
end)

RegisterNUICallback('deathRise', function(_, cb)
    cb({})

    if dead and remaining <= 0 then
        respawn()
    end
end)

AddEventHandler('esx:onPlayerDeath', function()
    startDeath(false)
end)

AddEventHandler('esx:onPlayerSpawn', function()
    if dead then
        stopDeath()
    end
end)

-- Réanimé par un médecin : sur place
RegisterNetEvent('lunatic_gameplay:revived', function()
    if not dead then
        return
    end

    stopDeath()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    resurrect(coords.x, coords.y, coords.z, GetEntityHeading(ped))
end)

---------------------------------------------------------------------
-- Médecins : appels et réanimation
---------------------------------------------------------------------

RegisterNetEvent('lunatic_gameplay:medicCall', function(call)
    Notify(('Appel aux secours : personne inconsciente (ID %d). Point GPS ajouté.'):format(call.id), 'info')
    SetNewWaypoint(call.x + 0.0, call.y + 0.0)

    local blip = AddBlipForCoord(call.x, call.y, call.z)
    SetBlipSprite(blip, 153)
    SetBlipColour(blip, 1)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Personne inconsciente')
    EndTextCommandSetBlipName(blip)
    SetTimeout(180000, function() RemoveBlip(blip) end)
end)

local function closestDeadPlayer()
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local best, bestDistance

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)

        if ped ~= myPed and (IsEntityDead(ped) or IsPedFatallyInjured(ped)) then
            local distance = #(GetEntityCoords(ped) - myCoords)

            if distance <= Config.ReviveDistance and (not bestDistance or distance < bestDistance) then
                best, bestDistance = GetPlayerServerId(player), distance
            end
        end
    end

    return best
end

RegisterCommand('reanimer', function()
    local target = closestDeadPlayer()

    if not target then
        return Notify("Personne d'inconscient à côté de vous.", 'error')
    end

    local done = lib.progressBar({
        duration = 8000, label = 'Réanimation…', canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' },
    })

    if not done then
        return
    end

    local result = lib.callback.await('lunatic_gameplay:revive', false, target)

    if not result or not result.ok then
        Notify(result and result.error or 'Réanimation impossible.', 'error')
    end
end, false)

TriggerEvent('chat:addSuggestion', '/reanimer', 'Réanimer la personne inconsciente la plus proche (médecins)')

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        AnimpostfxStop('DeathFailOut')

        if dead then
            SetNuiFocusKeepInput(false)
            SetNuiFocus(false, false)
        end
    end
end)
