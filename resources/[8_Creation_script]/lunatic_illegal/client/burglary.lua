-- Cambriolage côté client : devant la porte d'une maison, [E] la crochète (mini-jeu) ou y entre si un complice l'a
-- déjà forcée. Dans l'intérieur : repères au sol à fouiller ([E]) et porte de sortie. Le serveur revérifie tout.
-- Si le joueur se déconnecte dans la maison, il est ramené devant la porte à sa reconnexion (KVP local).

local cfg = { enabled = false, houses = {} }
local busy = false
local promptText = nil
local current = nil -- maison où l'on est : { house, interior, searched = {} }

local DIFFICULTY = {
    easy = { 'easy', 'easy' },
    medium = { 'easy', 'medium', 'medium' },
    hard = { 'medium', 'hard', 'hard' },
}

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

local function loadConfig()
    local result = lib.callback.await('lunatic_illegal:burglaryConfig', false)

    if type(result) == 'table' then
        cfg = result
    end
end

RegisterNetEvent('lunatic_illegal:burglaryConfigChanged', loadConfig)

local function hasTool()
    return not cfg.tool or cfg.tool == '' or (exports.ox_inventory:Search('count', cfg.tool) or 0) > 0
end

-- Téléportation avec fondu ; hauteur inconnue (porte placée sur la carte) : recherche du sol
-- whileBlack : appelé écran noir, une fois arrivé (ex. retour dans le monde normal après la sortie)
local function teleport(x, y, z, h, whileBlack)
    local ped = PlayerPedId()
    DoScreenFadeOut(300)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    FreezeEntityPosition(ped, true)

    if z < -150.0 then
        z = 200.0

        for height = 1000.0, 0.0, -25.0 do
            RequestCollisionAtCoord(x, y, height)
            Wait(0)
            local found, ground = GetGroundZFor_3dCoord(x, y, height, false)

            if found then
                z = ground
                break
            end
        end
    end

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

---------------------------------------------------------------------
-- Entrée et sortie
---------------------------------------------------------------------

local function enter(house)
    busy = true
    hidePrompt()

    local res = lib.callback.await('lunatic_illegal:burglaryStart', false, house.id)

    if not res or not res.ok then
        notify(res and res.error or 'Impossible pour le moment.', 'error')
        Wait(1000)
        busy = false
        return
    end

    local success = true

    -- Porte à crocheter (sauf si un complice l'a déjà forcée)
    if not res.open then
        local ped = PlayerPedId()

        if pcall(lib.requestAnimDict, 'mp_common_heist', 2000) then
            TaskPlayAnim(ped, 'mp_common_heist', 'pick_door', 3.0, 3.0, -1, 1, 0, false, false, false)
            RemoveAnimDict('mp_common_heist')
        end

        success = lib.skillCheck(DIFFICULTY[res.difficulty] or DIFFICULTY.medium, { 'e' })
        ClearPedTasks(ped)
    end

    local result = lib.callback.await('lunatic_illegal:burglaryEnter', false, success)

    if not result or not result.ok then
        notify(result and result.error or 'Cambriolage interrompu.', 'error')
        busy = false
        return
    end

    if result.failed then
        notify(result.broken and ('Crochetage raté : %s a cassé.'):format(result.broken) or 'Crochetage raté.', 'error')
        Wait(1000)
        busy = false
        return
    end

    local interior = Config.BurglaryInteriors[result.interior]
    current = { house = house, interior = interior, searched = result.searched or {} }

    -- Pour être ramené devant la porte si l'on se déconnecte dedans
    SetResourceKvp('burglary_door', json.encode({ x = house.x, y = house.y, z = house.z }))

    teleport(interior.entry.x, interior.entry.y, interior.entry.z, interior.entry.w)
    notify("Vous êtes entré. Fouillez vite et sans bruit.", 'info')
    busy = false
end

local function leaveHouse()
    busy = true
    hidePrompt()

    local res = lib.callback.await('lunatic_illegal:burglaryExit', false)
    local house = current and current.house
    current = nil
    DeleteResourceKvp('burglary_door')

    local door = res and res.ok and res or house

    -- D'abord dehors (encore dans le monde de la maison), puis seulement retour dans le monde normal, écran noir
    if door then
        teleport(door.x, door.y, door.z, ((door.h or 0.0) + 180.0) % 360.0, function()
            lib.callback.await('lunatic_illegal:burglaryLeave', false)
            Wait(500)
        end)
    else
        lib.callback.await('lunatic_illegal:burglaryLeave', false)
    end

    busy = false
end

RegisterNetEvent('lunatic_illegal:burglaryWoke', function()
    notify("Le propriétaire s'est réveillé : la police arrive, filez !", 'error')
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
end)

-- Un complice a fouillé un endroit
RegisterNetEvent('lunatic_illegal:burglarySearched', function(index)
    if current then
        current.searched[index] = true
    end
end)

---------------------------------------------------------------------
-- Fouille
---------------------------------------------------------------------

local function search(index, spot)
    busy = true
    hidePrompt()

    local done = lib.progressCircle({
        duration = (cfg.search or 6) * 1000,
        label = ('Fouille : %s…'):format(spot.label),
        position = 'bottom',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search' },
    })

    if done then
        local res = lib.callback.await('lunatic_illegal:burglarySearch', false, index)

        if res and res.ok then
            current.searched[index] = true
            local found = {}

            if res.cash then
                found[#found + 1] = res.cash
            end

            for _, entry in ipairs(res.loot or {}) do
                found[#found + 1] = entry
            end

            notify(#found > 0 and ('Trouvé : %s.'):format(table.concat(found, ', ')) or "Rien d'intéressant ici.", #found > 0 and 'success' or 'info')
        else
            if res and res.error == 'Déjà fouillé.' then
                current.searched[index] = true
            end

            notify(res and res.error or 'Fouille interrompue.', 'error')
        end
    end

    busy = false
end

---------------------------------------------------------------------
-- Boucles : porte des maisons dehors, repères et sortie dedans
---------------------------------------------------------------------

CreateThread(function()
    Wait(3000)

    -- Reconnecté dans un intérieur : retour devant la porte
    local saved = GetResourceKvpString('burglary_door')

    if saved then
        DeleteResourceKvp('burglary_door')
        local ok, door = pcall(json.decode, saved)
        local coords = GetEntityCoords(PlayerPedId())

        for _, interior in pairs(Config.BurglaryInteriors) do
            if ok and door and #(coords - interior.entry.xyz) < 80.0 then
                teleport(door.x, door.y, door.z, 0.0)
                break
            end
        end
    end

    while true do
        loadConfig()
        Wait(60000)
    end
end)

CreateThread(function()
    while true do
        local wait = 500
        local prompt = nil

        if not busy then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)

            if current then
                wait = 0
                local interior = current.interior

                -- Repères des endroits à fouiller
                for index, spot in ipairs(interior.spots) do
                    if not current.searched[index] then
                        DrawMarker(2, spot.coords.x, spot.coords.y, spot.coords.z, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.2, 0.2, 0.2, 150, 80, 255, 160, true, true, 2, false, nil, nil, false)

                        if not prompt and #(coords - spot.coords) < 1.6 then
                            prompt = ('[E] Fouiller : %s'):format(spot.label)

                            if IsControlJustPressed(0, 38) then
                                search(index, spot)
                            end
                        end
                    end
                end

                DrawMarker(1, interior.exit.x, interior.exit.y, interior.exit.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 0.8, 0.3, 255, 255, 255, 80, false, false, 2, false, nil, nil, false)

                if not prompt and #(coords - interior.exit) < 1.5 then
                    prompt = '[E] Sortir'

                    if IsControlJustPressed(0, 38) then
                        leaveHouse()
                    end
                end

                -- Sorti autrement (mort, téléporté) : plus dans la maison
                if #(coords - interior.entry.xyz) > 60.0 then
                    current = nil
                    DeleteResourceKvp('burglary_door')
                end
            elseif cfg.enabled and not IsPedInAnyVehicle(ped, false) then
                for _, house in ipairs(cfg.houses or {}) do
                    if #(coords.xy - vector2(house.x, house.y)) < 1.8 and (house.z < -150.0 or math.abs(coords.z - house.z) < 3.0) then
                        wait = 0
                        prompt = hasTool() and '[E] Crocheter la porte' or '[E] Entrer'

                        if IsControlJustPressed(0, 38) then
                            enter(house)
                        end

                        break
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
