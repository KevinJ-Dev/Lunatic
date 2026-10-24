-- Infrastructure des crews côté client : marqueurs des points du crew du joueur (coffres, garage, portes des planques),
-- [E] pour ouvrir un coffre ou entrer ; dans une planque : coffre et sortie. Seuls les points de son crew sont reçus.
-- Si le joueur se déconnecte dans une planque, il est ramené devant la porte à sa reconnexion (KVP local).

local points = {}
local crewId = nil
local busy = false
local promptText = nil
local current = nil -- planque où l'on est : { point, interior }

local MARKER = { storage = { 120, 200, 90 }, stash = { 120, 200, 90 }, garage = { 90, 160, 255 }, property = { 150, 80, 255 } }

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

local function load()
    local crew = LocalPlayer.state.crew
    crewId = crew and crew.id or nil

    if not crewId then
        points = {}
        return
    end

    local result = lib.callback.await('lunatic_illegal:crewPoints', false)
    points = type(result) == 'table' and result or {}
end

AddStateBagChangeHandler('crew', ('player:%s'):format(GetPlayerServerId(PlayerId())), function()
    SetTimeout(500, load)
end)

RegisterNetEvent('lunatic_illegal:crewPointsChanged', function(changedCrew)
    if changedCrew == crewId then
        load()
    end
end)

-- Téléportation avec fondu ; whileBlack : appelé écran noir, une fois arrivé
local function teleport(x, y, z, h, whileBlack)
    local ped = PlayerPedId()
    DoScreenFadeOut(300)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    SetEntityHeading(ped, h or 0.0)

    local timeout = GetGameTimer() + 3000

    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        Wait(0)
    end

    if whileBlack then
        whileBlack()
    end

    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(300)
end

local function openStash(point)
    busy = true
    hidePrompt()
    local result = lib.callback.await('lunatic_illegal:crewStash', false, point.id)

    if not result or not result.ok then
        notify(result and result.error or 'Coffre indisponible.', 'error')
    end

    Wait(500)
    busy = false
end

local function enterProperty(point)
    busy = true
    hidePrompt()
    local result = lib.callback.await('lunatic_illegal:crewPropertyEnter', false, point.id)
    local interior = result and result.ok and Config.BurglaryInteriors[result.interior]

    if not interior then
        notify(result and result.error or "Impossible d'entrer.", 'error')
        busy = false
        return
    end

    current = { point = point, interior = interior }
    SetResourceKvp('crew_property_door', json.encode({ x = point.x, y = point.y, z = point.z }))
    teleport(interior.entry.x, interior.entry.y, interior.entry.z, interior.entry.w)
    busy = false
end

local function leaveProperty()
    busy = true
    hidePrompt()

    local result = lib.callback.await('lunatic_illegal:crewPropertyExit', false)
    local door = result and result.ok and result or (current and current.point)
    current = nil
    DeleteResourceKvp('crew_property_door')

    -- D'abord dehors (encore dans le monde de la planque), puis retour dans le monde normal, écran noir
    if door then
        teleport(door.x, door.y, door.z, ((door.h or 0.0) + 180.0) % 360.0, function()
            lib.callback.await('lunatic_illegal:crewPropertyLeave', false)
            Wait(500)
        end)
    else
        lib.callback.await('lunatic_illegal:crewPropertyLeave', false)
    end

    busy = false
end

CreateThread(function()
    Wait(4000)

    -- Reconnecté dans une planque : retour devant la porte
    local saved = GetResourceKvpString('crew_property_door')

    if saved then
        DeleteResourceKvp('crew_property_door')
        local ok, door = pcall(json.decode, saved)
        local coords = GetEntityCoords(PlayerPedId())

        for _, interior in pairs(Config.BurglaryInteriors) do
            if ok and door and #(coords - interior.entry.xyz) < 80.0 then
                teleport(door.x, door.y, door.z, 0.0)
                break
            end
        end
    end

    load()
end)

CreateThread(function()
    while true do
        local wait = 500
        local prompt = nil

        if not busy then
            local coords = GetEntityCoords(PlayerPedId())

            if current then
                wait = 0
                local interior = current.interior
                local chest = interior.spots[1] and interior.spots[1].coords

                if chest then
                    DrawMarker(2, chest.x, chest.y, chest.z, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.25, 0.25, 0.25, 120, 200, 90, 170, true, true, 2, false, nil, nil, false)

                    if #(coords - chest) < Config.CrewPointDistance then
                        prompt = ('[E] Coffre : %s'):format(current.point.label)

                        if IsControlJustPressed(0, 38) then
                            openStash(current.point)
                        end
                    end
                end

                DrawMarker(1, interior.exit.x, interior.exit.y, interior.exit.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 0.8, 0.3, 255, 255, 255, 80, false, false, 2, false, nil, nil, false)

                if not prompt and #(coords - interior.exit) < 1.5 then
                    prompt = '[E] Sortir'

                    if IsControlJustPressed(0, 38) then
                        leaveProperty()
                    end
                end

                -- Sorti autrement (mort, téléporté) : plus dans la planque
                if #(coords - interior.entry.xyz) > 60.0 then
                    current = nil
                    DeleteResourceKvp('crew_property_door')
                end
            else
                for _, point in ipairs(points) do
                    local position = vector3(point.x, point.y, point.z)
                    local distance = #(coords - position)

                    if distance < 20.0 then
                        wait = 0
                        local color = MARKER[point.kind] or MARKER.storage
                        DrawMarker(point.kind == 'property' and 21 or 25, point.x, point.y, point.z + (point.kind == 'property' and 0.3 or -0.95), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            point.kind == 'property' and 0.6 or 1.1, point.kind == 'property' and 0.6 or 1.1, point.kind == 'property' and 0.6 or 1.0,
                            color[1], color[2], color[3], 150, point.kind == 'property', true, 2, false, nil, nil, false)

                        if not prompt and distance < Config.CrewPointDistance then
                            if point.kind == 'garage' then
                                prompt = ('%s : bientôt disponible'):format(point.label)
                            elseif point.kind == 'property' then
                                prompt = ('[E] Entrer : %s'):format(point.label)

                                if IsControlJustPressed(0, 38) then
                                    enterProperty(point)
                                end
                            else
                                prompt = ('[E] Coffre : %s'):format(point.label)

                                if IsControlJustPressed(0, 38) then
                                    openStash(point)
                                end
                            end
                        end
                    end
                end
            end
        end

        if prompt then
            showPrompt(prompt)
        else
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
