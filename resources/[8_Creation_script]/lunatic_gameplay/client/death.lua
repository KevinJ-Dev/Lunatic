-- Mort et respawn côté client : écran d'inconscience (délai, appel des secours, réveil à l'hôpital),
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

AddEventHandler('esx:onPlayerDeath', function()
    if dead then
        return
    end

    dead = true
    AnimpostfxPlay('DeathFailOut', 0, true)

    local state = lib.callback.await('lunatic_gameplay:deathState', false)
    remaining = state and state.remaining or 300

    -- Compte à rebours (le serveur revérifie au moment du réveil)
    CreateThread(function()
        while dead and remaining > 0 do
            Wait(1000)
            remaining = remaining - 1
        end

        -- Mort désactivée dans le panel : réveil automatique à l'hôpital
        if dead and FeaturesOf('death').enabled == false then
            respawn()
        end
    end)

    CreateThread(function()
        local settings = FeaturesOf('death')

        while dead do
            DrawScreenText(0.5, 0.80, 'Vous êtes inconscient', 0.7)

            if remaining > 0 then
                DrawScreenText(0.5, 0.86, ("Réveil à l'hôpital possible dans %d:%02d"):format(math.floor(remaining / 60), remaining % 60), 0.45)
            else
                DrawScreenText(0.5, 0.86, "[E] Se réveiller à l'hôpital", 0.45)

                if IsControlJustReleased(0, 38) then
                    respawn()
                end
            end

            if settings.callMedic ~= false then
                DrawScreenText(0.5, 0.90, '[G] Appeler les secours', 0.4)

                if IsControlJustReleased(0, 47) then
                    TriggerServerEvent('lunatic_gameplay:callMedic')
                end
            end

            Wait(0)
        end
    end)
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
    end
end)
