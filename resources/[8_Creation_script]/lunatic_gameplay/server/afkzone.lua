-- Zone AFK (panel : tuile Autres → Zone AFK, GlobalState.lunaticAfkZone) : /afk pour y aller puis revenir,
-- inactifs envoyés dans la zone au lieu d'être expulsés (si réglé), récompense en banque pour les présents.
-- L'état « dans la zone » est posé par le serveur (Player(src).state.afkZone), lu par le client.

local afk = {}      -- joueur -> position de retour
local minutes = {}  -- joueur -> minutes passées dans la zone depuis la dernière récompense
local lastUse = {}

local function zone()
    local z = GlobalState.lunaticAfkZone
    return type(z) == 'table' and z.enabled and z.point and z or nil
end

local function setState(src, value)
    Player(src).state:set('afkZone', value or nil, true)
end

-- Envoie un joueur dans la zone (aussi appelé par l'anti-AFK, server/misc.lua)
function SendToAfk(src)
    local z = zone()

    if not z then
        return false
    end

    if afk[src] then
        return true
    end

    local ped = GetPlayerPed(src)

    if ped == 0 then
        return false
    end

    local coords = GetEntityCoords(ped)
    afk[src] = { x = coords.x, y = coords.y, z = coords.z, h = GetEntityHeading(ped) }
    minutes[src] = 0
    setState(src, true)
    TriggerClientEvent('lunatic_gameplay:afkTeleport', src, z.point)
    Notify(src, 'Vous êtes dans la zone AFK. Tapez /afk pour revenir.', 'info')
    return true
end

local function leave(src, goBack)
    local back = afk[src]
    afk[src], minutes[src] = nil, nil
    setState(src, false)

    if goBack and back then
        TriggerClientEvent('lunatic_gameplay:afkTeleport', src, back)
    end
end

RegisterCommand('afk', function(src)
    local z = zone()

    if src == 0 or not z or not z.command then
        return
    end

    if lastUse[src] and os.time() - lastUse[src] < 10 then
        return Notify(src, 'Patientez quelques secondes.', 'error')
    end

    lastUse[src] = os.time()

    if afk[src] then
        leave(src, true)
        return Notify(src, 'Retour à votre position.', 'success')
    end

    if IsPlayerDown(src) or GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then
        return Notify(src, 'Impossible maintenant (inconscient ou en véhicule).', 'error')
    end

    SendToAfk(src)
end, false)

-- Récompense et sortie de zone (le joueur s'est éloigné à pied : il n'est plus AFK)
CreateThread(function()
    while true do
        Wait(60000)
        local z = zone()

        for src in pairs(afk) do
            local ped = GetPlayerPed(src)

            if not z or ped == 0 then
                leave(src, false)
            elseif #(GetEntityCoords(ped) - vector3(z.point.x, z.point.y, z.point.z)) > z.radius + 10.0 then
                leave(src, false)
            elseif (tonumber(z.rewardAmount) or 0) > 0 then
                minutes[src] = (minutes[src] or 0) + 1

                if minutes[src] >= (tonumber(z.rewardMinutes) or 15) then
                    minutes[src] = 0
                    local xPlayer = ESX.GetPlayerFromId(src)

                    if xPlayer then
                        xPlayer.addAccountMoney('bank', z.rewardAmount, 'Zone AFK')
                        Notify(src, ('Zone AFK : +%d %s en banque.'):format(z.rewardAmount, GlobalState.lunaticCurrency or '$'), 'success')
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    afk[source], minutes[source], lastUse[source] = nil, nil, nil
end)
