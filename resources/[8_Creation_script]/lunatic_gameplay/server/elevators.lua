-- Ascenseurs (panel : tuile Autres → Ascenseurs, GlobalState.lunaticElevators).
-- Le serveur vérifie que le joueur est devant un étage de l'ascenseur et qu'il y a accès, puis donne l'arrivée.

local function elevatorOf(id)
    for _, elevator in ipairs(GlobalState.lunaticElevators or {}) do
        if elevator.id == id then
            return elevator
        end
    end
end

lib.callback.register('lunatic_gameplay:elevator', function(src, id, from, to)
    local elevator = elevatorOf(tonumber(id))
    local start = elevator and elevator.floors[tonumber(from)]
    local arrival = elevator and elevator.floors[tonumber(to)]

    if not start or not arrival or from == to then
        return nil
    end

    if elevator.job ~= '' then
        local xPlayer = ESX.GetPlayerFromId(src)

        if not xPlayer or xPlayer.getJob().name ~= elevator.job then
            return { error = 'Accès réservé.' }
        end
    end

    local ped = GetPlayerPed(src)

    if ped == 0 or #(GetEntityCoords(ped) - vector3(start.x, start.y, start.z)) > 3.0 then
        return nil
    end

    return { x = arrival.x, y = arrival.y, z = arrival.z, h = arrival.h or 0.0 }
end)
