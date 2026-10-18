-- Lot C : prison staff côté joueur. Le serveur décide (entrée, sortie, temps restant) ;
-- le client affiche le compte à rebours, empêche de tirer et ramène dans la cour.

---@type {endsAt:number, reason:string}|nil
local jail

local function drawJailText(text, y, scale, rgb)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextColour(rgb[1], rgb[2], rgb[3], 240)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, y)
end

local function formatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ('%d:%02d'):format(seconds // 60, seconds % 60)
end

local function jailLoop()
    CreateThread(function()
        local nextCheck = 0

        while jail do
            local remaining = (jail.endsAt - GetGameTimer()) / 1000

            drawJailText(('PRISON STAFF  ·  %s restantes'):format(formatTime(remaining)), 0.88, 0.5, { 255, 138, 132 })
            drawJailText(jail.reason, 0.915, 0.34, { 255, 255, 255 })

            -- Pas d'armes en prison
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)  -- attaque
            DisableControlAction(0, 25, true)  -- viser
            DisableControlAction(0, 140, true) -- coups de poing
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)

            -- Sortie de la zone : retour immédiat dans la cour (le serveur vérifie aussi)
            if GetGameTimer() >= nextCheck then
                nextCheck = GetGameTimer() + 1000

                if #(GetEntityCoords(PlayerPedId()) - Config.Jail.spawn) > Config.Jail.radius then
                    Teleport(Config.Jail.spawn)
                    ESX.ShowNotification('Vous ne pouvez pas quitter la prison.', 'error')
                end
            end

            Wait(0)
        end
    end)
end

RegisterNetEvent('lunatic_admin:jail', function(remaining, reason)
    if type(remaining) ~= 'number' then
        return
    end

    local first = jail == nil
    jail = { endsAt = GetGameTimer() + remaining * 1000, reason = type(reason) == 'string' and reason or '' }

    if first then
        local ped = PlayerPedId()

        -- Sort d'un éventuel véhicule et range l'arme avant le transfert
        if IsPedInAnyVehicle(ped, false) then
            TaskLeaveAnyVehicle(ped, 0, 16)
            Wait(500)
        end

        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        Teleport(Config.Jail.spawn)
        jailLoop()
    end
end)

-- Recalage du compte à rebours sur le temps du serveur
RegisterNetEvent('lunatic_admin:jailSync', function(remaining)
    if jail and type(remaining) == 'number' then
        jail.endsAt = GetGameTimer() + remaining * 1000
    end
end)

RegisterNetEvent('lunatic_admin:jailBack', function()
    if jail then
        Teleport(Config.Jail.spawn)
    end
end)

RegisterNetEvent('lunatic_admin:unjail', function()
    if not jail then
        return
    end

    jail = nil
    Teleport(Config.Jail.release)
end)
