-- Ascenseurs, côté client (provisoire, en attendant la passe « full ox » des interactions) :
-- marqueur devant chaque étage, [E] ouvre la liste des étages, le serveur valide puis on arrive à l'étage choisi.

local function travel(elevator, from, to)
    local arrival = lib.callback.await('lunatic_gameplay:elevator', false, elevator.id, from, to)

    if not arrival then
        return
    end

    if arrival.error then
        return Notify(arrival.error, 'error')
    end

    DoScreenFadeOut(400)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    local ped = PlayerPedId()
    RequestCollisionAtCoord(arrival.x, arrival.y, arrival.z)
    SetEntityCoords(ped, arrival.x + 0.0, arrival.y + 0.0, arrival.z - 0.98, false, false, false, false)
    SetEntityHeading(ped, arrival.h + 0.0)
    Wait(600)
    DoScreenFadeIn(400)
end

local function openMenu(elevator, from)
    local options = {}

    for index, floor in ipairs(elevator.floors) do
        options[#options + 1] = {
            title = floor.label,
            description = index == from and 'Vous êtes ici' or nil,
            icon = index == from and 'location-dot' or 'elevator',
            disabled = index == from,
            onSelect = function() travel(elevator, from, index) end,
        }
    end

    lib.registerContext({ id = 'lunatic_elevator', title = elevator.label, options = options })
    lib.showContext('lunatic_elevator')
end

CreateThread(function()
    while true do
        local list = GlobalState.lunaticElevators
        local wait = 1000

        if type(list) == 'table' then
            local coords = GetEntityCoords(PlayerPedId())

            for _, elevator in ipairs(list) do
                for index, floor in ipairs(elevator.floors) do
                    local distance = #(coords - vector3(floor.x, floor.y, floor.z))

                    if distance < 10.0 then
                        wait = 0
                        DrawMarker(1, floor.x, floor.y, floor.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.3, 150, 80, 255, 110, false, false, 2, false, nil, nil, false)

                        if distance <= 1.5 then
                            BeginTextCommandDisplayHelp('STRING')
                            AddTextComponentSubstringPlayerName(('~INPUT_CONTEXT~ %s · %s'):format(elevator.label, floor.label))
                            EndTextCommandDisplayHelp(0, false, true, -1)

                            if IsControlJustReleased(0, 38) then
                                openMenu(elevator, index)
                            end
                        end
                    end
                end
            end
        end

        Wait(wait)
    end
end)
