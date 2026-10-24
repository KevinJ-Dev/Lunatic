-- Braquage Yacht (coffre dans le panel, page Braquages → Yacht ; réglages dans la page Missions → Braquage Yacht).
-- Un crew qui approche du yacht (150 m) le fait défendre : gardes armés à bord (créés par le premier joueur arrivé),
-- police prévenue. Une fois tous les gardes à terre, le coffre se pirate (outil, mini-jeu) puis se vide sans bouger.
-- Délai après le braquage ; un braquage pas terminé au bout de 30 min est abandonné (gardes retirés).
-- Tout est revérifié ici (mission, crew et level, gardes, outil, étapes, distance, durée, limite du jour).

local ox = exports.ox_inventory
local admin = exports.lunatic_admin

local heists = {}  -- point -> { active, startedAt, guards = { netId }, opening, untilAt }
local hacking = {} -- joueur -> { point, stage, at, duration }

local WINDOW = 30 * 60 -- secondes pour finir un braquage commencé

local function fail(message)
    return { ok = false, error = message }
end

local function itemLabel(name)
    local item = ox:Items(name)
    return item and item.label or name
end

local function yachts()
    local found, cfg = pcall(function() return admin:getHoldupConfig() end)
    local list = {}

    if found and cfg then
        for _, point in ipairs(cfg.points) do
            if point.active and point.type == 'yacht' and point.z > -100.0 then
                list[point.id] = point
            end
        end
    end

    return list
end

local function guardsDown(state)
    for _, netId in ipairs(state.guards or {}) do
        local entity = NetworkGetEntityFromNetworkId(netId)

        if entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityHealth(entity) > 0 then
            return false
        end
    end

    return true
end

local function removeGuards(state, delay)
    local guards = state.guards or {}
    state.guards = {}

    SetTimeout(delay or 0, function()
        for _, netId in ipairs(guards) do
            local entity = NetworkGetEntityFromNetworkId(netId)

            if entity and entity ~= 0 and DoesEntityExist(entity) then
                DeleteEntity(entity)
            end
        end
    end)
end

-- Fin du braquage (réussi ou abandonné) : délai, gardes retirés
local function close(state, cooldown)
    state.active, state.opening = false, nil
    state.untilAt = os.time() + cooldown
    removeGuards(state, 60000)
end

-- Yachts, pour l'approche et le coffre en jeu
lib.callback.register('lunatic_illegal:yachtConfig', function()
    local m = MissionSettings('heist_yacht')

    if not m or not m.enabled then
        return { enabled = false, points = {} }
    end

    local list = {}

    for _, point in pairs(yachts()) do
        list[#list + 1] = { id = point.id, x = point.x, y = point.y, z = point.z, label = point.label }
    end

    return { enabled = true, tool = m.advanced.tool, points = list }
end)

local function refreshClients()
    TriggerClientEvent('lunatic_illegal:yachtConfigChanged', -1)
end

AddEventHandler('lunatic_admin:heistsChanged', refreshClients)
AddEventHandler('lunatic_admin:holdupsChanged', refreshClients)

-- Un crew approche : le braquage commence, les gardes sont à créer (une seule fois)
lib.callback.register('lunatic_illegal:yachtApproach', function(src, pointId)
    local m = MissionSettings('heist_yacht')
    local point = yachts()[tonumber(pointId)]
    local ped = GetPlayerPed(src)

    if not point or MissionProblem(src, m) or IsPolice(src) then
        return nil
    end

    if not ped or ped == 0 or #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)) > 200.0 then
        return nil
    end

    local now = os.time()
    local state = heists[point.id]

    if state and state.active then
        return { ok = true }
    end

    if state and (state.untilAt or 0) > now then
        return nil
    end

    if not admin:takeMissionSlot('heist_yacht') then
        return nil
    end

    local a = m.advanced
    heists[point.id] = { active = true, startedAt = now, guards = {} }
    AlertPolice(vector3(point.x, point.y, point.z), ('Intrusion signalée : %s'):format(point.label), 50)

    return { ok = true, guards = { count = a.guards, model = a.guardModel, weapon = a.guardWeapon } }
end)

RegisterNetEvent('lunatic_illegal:yachtGuardsSpawned', function(pointId, netIds)
    local state = heists[tonumber(pointId)]

    if state and state.active and type(netIds) == 'table' and #state.guards == 0 then
        for index = 1, math.min(#netIds, 12) do
            state.guards[#state.guards + 1] = tonumber(netIds[index])
        end
    end
end)

---------------------------------------------------------------------
-- Coffre
---------------------------------------------------------------------

lib.callback.register('lunatic_illegal:yachtOpen', function(src, pointId)
    local m = MissionSettings('heist_yacht')
    local problem = MissionProblem(src, m)

    if problem then
        return fail(problem)
    end

    local point = yachts()[tonumber(pointId)]
    local state = point and heists[point.id]
    local ped = GetPlayerPed(src)

    if not point or not state or not state.active then
        return fail("Le coffre est fermé : il faut d'abord aborder le yacht.")
    end

    if not ped or ped == 0 or #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)) > 3.0 then
        return fail('Vous êtes trop loin du coffre.')
    end

    if not guardsDown(state) then
        return fail('Il reste des gardes à bord.')
    end

    if state.opening or hacking[src] then
        return fail("Quelqu'un est déjà sur le coffre.")
    end

    local a = m.advanced

    if a.tool ~= '' and (ox:GetItemCount(src, a.tool) or 0) < 1 then
        return fail(('Il vous faut : %s.'):format(itemLabel(a.tool)))
    end

    state.opening = src
    hacking[src] = { point = point.id, stage = 'hack' }
    return { ok = true, difficulty = a.difficulty }
end)

lib.callback.register('lunatic_illegal:yachtHacked', function(src, success)
    local job = hacking[src]
    local m = MissionSettings('heist_yacht')
    local state = job and heists[job.point]

    if not job or job.stage ~= 'hack' or not m or not state then
        hacking[src] = nil
        return fail('Piratage interrompu.')
    end

    local a = m.advanced

    if not success then
        hacking[src] = nil
        state.opening = nil

        if a.tool ~= '' and math.random(100) <= a.breakChance then
            ox:RemoveItem(src, a.tool, 1)
            return { ok = true, failed = true, broken = itemLabel(a.tool) }
        end

        return { ok = true, failed = true }
    end

    job.stage, job.at, job.duration = 'loot', GetGameTimer(), a.duration
    return { ok = true, duration = a.duration }
end)

lib.callback.register('lunatic_illegal:yachtFinish', function(src)
    local job = hacking[src]
    hacking[src] = nil

    local m = MissionSettings('heist_yacht')
    local state = job and heists[job.point]
    local point = job and yachts()[job.point]

    if not job or job.stage ~= 'loot' or not m or not state or not point then
        if state then
            state.opening = nil
        end

        return fail('Braquage interrompu.')
    end

    if GetGameTimer() - job.at < job.duration * 1000 - 1500 then
        state.opening = nil
        return fail('Trop rapide.')
    end

    local ped = GetPlayerPed(src)
    local coords = vector3(point.x, point.y, point.z)

    if not ped or ped == 0 or #(GetEntityCoords(ped) - coords) > 4.0 then
        state.opening = nil
        return fail('Vous vous êtes éloigné du coffre.')
    end

    close(state, m.advanced.cooldown * 60)
    local reward, loot = MissionPayout(src, m, coords, 'yacht', Config.HoldupAccount)
    return { ok = true, reward = MoneyText(reward), loot = loot }
end)

RegisterNetEvent('lunatic_illegal:yachtCancel', function()
    local job = hacking[source]
    hacking[source] = nil

    if job and heists[job.point] then
        heists[job.point].opening = nil
    end
end)

-- Braquage pas terminé à temps : abandonné (délai réduit de moitié), gardes retirés
CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        local m = MissionSettings('heist_yacht')

        for _, state in pairs(heists) do
            if state.active and now - state.startedAt > WINDOW then
                close(state, math.floor((m and m.advanced.cooldown or 60) * 60 / 2))
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local job = hacking[source]
    hacking[source] = nil

    if job and heists[job.point] then
        heists[job.point].opening = nil
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    for _, state in pairs(heists) do
        for _, netId in ipairs(state.guards or {}) do
            local entity = NetworkGetEntityFromNetworkId(netId)

            if entity and entity ~= 0 and DoesEntityExist(entity) then
                DeleteEntity(entity)
            end
        end
    end
end)
