-- Braquages côté client : détection des cibles (modèle du décor ou point du panel), [E], mini-jeux ox_lib,
-- porte du coffre des Fleeca, alertes police, vue staff. Le serveur revérifie chaque étape.

local cfg = nil        -- { types = { store = { label, actions = { register = { tool, models, duration, points } } } } }
local hashes = {}      -- actionId -> { hash du modèle }
local doors = {}       -- portes de coffre ouvertes
local doorHeadings = {} -- cap d'origine des portes déplacées (objet -> cap)
local busy = false
local staffView = false

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function loadConfig()
    local result = lib.callback.await('lunatic_illegal:heistConfig', false)

    if not result then
        return
    end

    cfg = result
    doors = result.doors or {}
    hashes = {}

    for _, typeData in pairs(cfg.types) do
        for actionId, action in pairs(typeData.actions) do
            hashes[actionId] = {}

            for _, model in ipairs(action.models or {}) do
                hashes[actionId][#hashes[actionId] + 1] = joaat(model)
            end
        end
    end
end

CreateThread(function()
    Wait(2000)
    loadConfig()
end)

RegisterNetEvent('lunatic_illegal:heistConfigChanged', loadConfig)

RegisterNetEvent('lunatic_illegal:heistDoors', function(list)
    doors = type(list) == 'table' and list or {}
end)

RegisterNetEvent('lunatic_illegal:staffHeists', function(enabled)
    staffView = enabled == true
    notify(staffView and 'Vue staff : les cibles de braquage proches sont affichées en orange.' or 'Vue staff des braquages désactivée.', 'info')
end)

---------------------------------------------------------------------
-- Détection
---------------------------------------------------------------------

local TEXTS = {
    register = '[E] Crocheter la caisse',
    safe = '[E] Percer le coffre',
    case = '[E] Briser la vitrine',
    door = '[E] Pirater la porte du coffre',
    locker = '[E] Percer un casier',
}

-- Cible la plus proche dans le rayon : objet du décor d'un modèle connu, ou point placé dans le panel
local function nearestTarget(coords, radius)
    local best, bestDistance

    for typeId, typeData in pairs(cfg.types) do
        for actionId, action in pairs(typeData.actions) do
            if actionId ~= 'locker' then
                for _, hash in ipairs(hashes[actionId] or {}) do
                    local object = GetClosestObjectOfType(coords.x, coords.y, coords.z, radius, hash, false, false, false)

                    if object ~= 0 then
                        local position = GetEntityCoords(object)
                        local distance = #(coords - position)

                        if not bestDistance or distance < bestDistance then
                            best, bestDistance = { type = typeId, action = actionId, coords = position }, distance
                        end
                    end
                end

                for _, point in ipairs(action.points or {}) do
                    local position = vector3(point.x, point.y, point.z)
                    local distance = #(coords - position)

                    if distance <= radius and (not bestDistance or distance < bestDistance) then
                        best, bestDistance = { type = typeId, action = actionId, coords = position }, distance
                    end
                end
            end
        end
    end

    -- Casiers : dans le coffre d'une Fleeca dont la porte est ouverte
    if cfg.types.fleeca and cfg.types.fleeca.actions.locker then
        for _, door in ipairs(doors) do
            local position = vector3(door.x, door.y, door.z)

            if #(coords - position) <= 7.0 and (not bestDistance or bestDistance > 1.0) then
                return { type = 'fleeca', action = 'locker', coords = position }
            end
        end
    end

    return best
end

---------------------------------------------------------------------
-- Déroulement : mini-jeu, barre de progression, résultat
---------------------------------------------------------------------

local SKILLS = {
    register = { 'easy', 'easy', 'medium' },
    safe = { 'medium', 'medium', 'medium' },
    door = { 'medium', 'hard', 'hard', 'hard' },
    locker = { 'easy', 'medium', 'medium' },
}

local ANIMS = {
    register = { dict = 'oddjobs@shop_robbery@rob_till', clip = 'loop' },
    safe = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle' },
    case = { dict = 'missheist_jewel', clip = 'smash_case' },
    door = { dict = 'anim@heists@ornate_bank@hack', clip = 'hack_loop' },
    locker = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle' },
}

local LABELS = {
    register = 'Crochetage de la caisse',
    safe = 'Perçage du coffre',
    case = 'Vitrine brisée : vous ramassez les bijoux',
    door = 'Piratage de la porte',
    locker = 'Perçage du casier',
}

local function attempt(target)
    busy = true
    local start = lib.callback.await('lunatic_illegal:heistStart', false, target.type, target.action, target.coords)

    if not start or not start.ok then
        busy = false
        return notify(start and start.error or 'Impossible.', 'error')
    end

    -- Mini-jeu (pas pour les vitrines : on casse et on ramasse)
    local success = true

    if SKILLS[target.action] then
        success = lib.skillCheck(SKILLS[target.action], { 'w', 'a', 's', 'd' })
    end

    if success then
        success = lib.progressBar({
            duration = start.duration * 1000,
            label = LABELS[target.action],
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = ANIMS[target.action],
        })

        if not success then
            TriggerServerEvent('lunatic_illegal:heistCancel')
            busy = false
            return notify('Abandonné.', 'error')
        end
    end

    local result = lib.callback.await('lunatic_illegal:heistFinish', false, success)
    busy = false

    if not result or not result.ok then
        return notify(result and result.error or 'Raté.', 'error')
    end

    if result.failed then
        return notify(result.broken and ('Raté : %s est cassé.'):format(result.broken) or 'Raté, recommencez.', 'error')
    end

    if result.door then
        notify('Porte du coffre ouverte : percez les casiers.', 'success')
    end

    if result.loot and #result.loot > 0 then
        notify(('Butin : %s.'):format(table.concat(result.loot, ', ')), 'success')
    elseif not result.door then
        notify('Rien de plus ici.', 'info')
    end
end

---------------------------------------------------------------------
-- Boucle : [E] près d'une cible, vue staff
---------------------------------------------------------------------

CreateThread(function()
    local shown
    local target, nextScan = nil, 0

    while true do
        local sleep = 500
        local text, action

        if cfg and not busy then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)

            if not IsPedInAnyVehicle(ped, false) then
                -- Recherche des cibles au plus 4 fois par seconde
                if GetGameTimer() >= nextScan then
                    nextScan = GetGameTimer() + 250
                    target = nearestTarget(coords, 1.4)
                end

                if target then
                    sleep = 0
                    local current = target
                    text, action = TEXTS[current.action], function() attempt(current) end
                end

                -- Vue staff : cibles détectées et points dans un rayon de 25 m
                if staffView then
                    sleep = 0

                    for _, typeData in pairs(cfg.types) do
                        for actionId, actionData in pairs(typeData.actions) do
                            for _, hash in ipairs(hashes[actionId] or {}) do
                                local object = GetClosestObjectOfType(coords.x, coords.y, coords.z, 25.0, hash, false, false, false)

                                if object ~= 0 then
                                    local p = GetEntityCoords(object)
                                    DrawMarker(0, p.x, p.y, p.z + 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, 242, 160, 60, 200, true, true, 2, false, nil, nil, false)
                                end
                            end

                            for _, point in ipairs(actionData.points or {}) do
                                if #(coords - vector3(point.x, point.y, point.z)) < 25.0 then
                                    DrawMarker(0, point.x, point.y, point.z + 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, 242, 160, 60, 200, true, true, 2, false, nil, nil, false)
                                end
                            end
                        end
                    end
                end
            end
        end

        if text then
            if shown ~= text then
                shown = text
                lib.showTextUI(text)
            end

            if IsControlJustReleased(0, 38) then
                lib.hideTextUI()
                shown = nil
                CreateThread(action)
            end
        elseif shown then
            shown = nil
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)

---------------------------------------------------------------------
-- Portes des coffres Fleeca : ouvertes pour tout le monde tant que le lieu est braqué
---------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(1500)

        if cfg and cfg.types.fleeca and cfg.types.fleeca.actions.door then
            local coords = GetEntityCoords(PlayerPedId())
            local opened = {}

            for _, door in ipairs(doors) do
                if #(coords - vector3(door.x, door.y, door.z)) < 80.0 then
                    for _, hash in ipairs(hashes.door or {}) do
                        local object = GetClosestObjectOfType(door.x, door.y, door.z, 3.0, hash, false, false, false)

                        if object ~= 0 then
                            opened[object] = true

                            if not doorHeadings[object] then
                                doorHeadings[object] = GetEntityHeading(object)
                                FreezeEntityPosition(object, true)
                                SetEntityHeading(object, doorHeadings[object] - 90.0)
                            end
                        end
                    end
                end
            end

            -- Portes refermées (délai écoulé ou lieu remis à zéro)
            for object, heading in pairs(doorHeadings) do
                if not opened[object] then
                    if DoesEntityExist(object) then
                        SetEntityHeading(object, heading)
                    end

                    doorHeadings[object] = nil
                end
            end
        end
    end
end)

-- Alerte police : alarme d'un commerce ou d'une banque (position exacte)
RegisterNetEvent('lunatic_illegal:heistAlert', function(alert)
    notify(('%s : rendez-vous sur place, position sur la carte.'):format(alert.label), 'error')
    local center = AddBlipForCoord(alert.x + 0.0, alert.y + 0.0, 0.0)
    SetBlipSprite(center, 161)
    SetBlipColour(center, 1)
    SetBlipScale(center, 1.2)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(alert.label)
    EndTextCommandSetBlipName(center)
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)

    SetTimeout(Config.AlertDuration * 1000 * 2, function()
        RemoveBlip(center)
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for object, heading in pairs(doorHeadings) do
            if DoesEntityExist(object) then
                SetEntityHeading(object, heading)
            end
        end
    end
end)
