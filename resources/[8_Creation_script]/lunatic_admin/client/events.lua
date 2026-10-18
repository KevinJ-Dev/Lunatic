-- Lot J : points des events sur la carte et itinéraire /eventgps

local blips = {}

local function clearBlips()
    for _, blip in pairs(blips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    blips = {}
end

local function drawBlips(list)
    clearBlips()

    for _, event in ipairs(type(list) == 'table' and list or {}) do
        local blip = AddBlipForCoord(event.x + 0.0, event.y + 0.0, event.z + 0.0)
        SetBlipSprite(blip, 439)
        SetBlipColour(blip, 27)
        SetBlipScale(blip, 1.0)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(('Event : %s'):format(event.title))
        EndTextCommandSetBlipName(blip)
        blips[event.id] = blip
    end
end

AddStateBagChangeHandler('lunaticEventBlips', 'global', function(_, _, value)
    drawBlips(value)
end)

CreateThread(function()
    drawBlips(GlobalState.lunaticEventBlips)
    TriggerEvent('chat:addSuggestion', '/events', 'Voir les events à venir')
    TriggerEvent('chat:addSuggestion', '/eventgps', "Itinéraire GPS vers le prochain event")
end)

RegisterNetEvent('lunatic_admin:eventWaypoint', function(coords, title)
    if type(coords) ~= 'table' or not coords.x then
        return
    end

    SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
    ESX.ShowNotification(('Itinéraire tracé vers « %s ».'):format(title or 'event'), 'info')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clearBlips()
    end
end)
