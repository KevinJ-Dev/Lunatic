-- Mort et respawn côté client : écran d'inconscience (html/ : délai, appel des secours, réveil à l'hôpital),
-- réanimation par un médecin (/reanimer). Le serveur valide le délai, les frais et la réanimation.

local dead = false
local remaining = 0
local responding = false -- un secouriste a pris l'appel : distance mise à jour plus souvent
local deathCam = nil

-- Caméra libre autour du personnage inconscient (souris : tourner, molette : zoom) ; GTA bloque la sienne à la mort
local function startDeathCamera()
    local ped = PlayerPedId()
    local heading, pitch, distance = GetEntityHeading(ped) + 180.0, 20.0, 3.5

    deathCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    RenderScriptCams(true, true, 600, true, true)

    CreateThread(function()
        while deathCam do
            ped = PlayerPedId()
            heading = heading - GetDisabledControlNormal(0, 1) * 6.0
            pitch = math.max(-5.0, math.min(70.0, pitch + GetDisabledControlNormal(0, 2) * 6.0))

            if IsDisabledControlPressed(0, 241) then distance = math.max(1.5, distance - 0.15) end
            if IsDisabledControlPressed(0, 242) then distance = math.min(7.0, distance + 0.15) end

            local target = GetEntityCoords(ped) + vector3(0.0, 0.0, 0.3)
            local h, p = math.rad(heading), math.rad(pitch)
            local wanted = target + vector3(-math.sin(h) * math.cos(p) * distance, math.cos(h) * math.cos(p) * distance, math.sin(p) * distance)

            -- Pas de caméra dans les murs : on s'arrête avant l'obstacle
            local ray = StartExpensiveSynchronousShapeTestLosProbe(target.x, target.y, target.z, wanted.x, wanted.y, wanted.z, 1 + 16, ped, 4)
            local _, hit, hitCoords = GetShapeTestResult(ray)
            local position = hit == 1 and (target + (hitCoords - target) * 0.9) or wanted

            SetCamCoord(deathCam, position.x, position.y, position.z)
            PointCamAtCoord(deathCam, target.x, target.y, target.z)
            Wait(0)
        end
    end)
end

local function stopDeathCamera()
    if deathCam then
        RenderScriptCams(false, true, 400, true, true)
        DestroyCam(deathCam, false)
        deathCam = nil
    end
end

-- Réglages de l'écran (panel : Fonctionnalités → Gameplay → Écran de mort), joints à chaque envoi à la page
local function screenSettings(state)
    local screen = FeaturesOf('deathScreen')
    state.title = screen.title
    state.showMedics = screen.showMedics ~= false
    state.showDistance = screen.showDistance ~= false
    state.shade = screen.shade == true
    return state
end

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
    responding = false
    stopDeathCamera()
    SendNUIMessage({ action = 'deathHide' })
end

-- État de l'écran (temps restant, secouristes en service, appel déjà fait) : le serveur fait foi ; true si reçu
local function refreshDeath()
    local state = lib.callback.await('lunatic_gameplay:deathState', false)

    if not state or not dead then
        return false
    end

    remaining = state.remaining or remaining
    responding = state.responder ~= nil
    state.action = 'deathUpdate'
    SendNUIMessage(screenSettings(state))
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
        local untilAt = GetGameTimer() + (event.noKO and 1500 or (tonumber(FeaturesOf('death').eventRespawnDelay) or 5) * 1000)

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
    remaining = 300

    -- Effet sombre de GTA : désactivé par défaut pour voir le jeu normalement (panel : Écran de mort)
    if FeaturesOf('deathScreen').effect == true then
        AnimpostfxPlay('DeathFailOut', 0, true)
    end
    SendNUIMessage(screenSettings({ action = 'death', remaining = remaining, callMedic = FeaturesOf('death').callMedic ~= false }))

    if FeaturesOf('deathScreen').freeCamera ~= false then
        startDeathCamera()
    end

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

            if not synced or tick % (responding and (tonumber(FeaturesOf('deathScreen').responderRefresh) or 3) or 10) == 0 then
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
            -- Inconscient : seulement la caméra (lue à part), le vocal (si autorisé) et le menu Échap
            DisableAllControlActions(0)
            EnableControlAction(0, 199, true)
            EnableControlAction(0, 200, true)

            if FeaturesOf('deathScreen').voice ~= false then
                EnableControlAction(0, 249, true)
            end

            if remaining <= 0 and IsDisabledControlJustReleased(0, 38) then
                respawn()
            end

            if FeaturesOf('death').callMedic ~= false and IsDisabledControlJustReleased(0, 47) then
                CreateThread(callMedic)
            end

            Wait(0)
        end
    end)
end

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

local incoming = nil -- dernier appel reçu par ce secouriste : { id, x, y, expires }

RegisterNetEvent('lunatic_gameplay:medicCall', function(call)
    incoming = { id = call.id, x = call.x, y = call.y, expires = GetGameTimer() + (tonumber(FeaturesOf('death').takeCallSeconds) or 120) * 1000 }
    Notify(("Appel aux secours : personne inconsciente (ID %d). [%s] pour prendre l'appel."):format(call.id, Config.TakeCallKey), 'info')

    local blip = AddBlipForCoord(call.x, call.y, call.z)
    SetBlipSprite(blip, 153)
    SetBlipColour(blip, 1)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Personne inconsciente')
    EndTextCommandSetBlipName(blip)
    SetTimeout(180000, function() RemoveBlip(blip) end)
end)

-- Appel pris par un autre secouriste
RegisterNetEvent('lunatic_gameplay:medicCallTaken', function(call)
    if incoming and incoming.id == call.id then
        incoming = nil
    end

    Notify(('Appel ID %d pris par %s.'):format(call.id, call.by or 'un collègue'), 'info')
end)

lib.addKeybind({
    name = 'lunatic_take_medic_call',
    description = 'Secours : prendre le dernier appel reçu',
    defaultKey = Config.TakeCallKey,
    onReleased = function()
        if not incoming or GetGameTimer() > incoming.expires then
            return
        end

        TriggerServerEvent('lunatic_gameplay:acceptCall', incoming.id)
        SetNewWaypoint(incoming.x + 0.0, incoming.y + 0.0)
        incoming = nil
    end,
})

local function closestDeadPlayer()
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local best, bestDistance

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)

        if ped ~= myPed and (IsEntityDead(ped) or IsPedFatallyInjured(ped)) then
            local distance = #(GetEntityCoords(ped) - myCoords)

            if distance <= (tonumber(FeaturesOf('death').reviveDistance) or 3.0) and (not bestDistance or distance < bestDistance) then
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
        stopDeathCamera()
    end
end)
