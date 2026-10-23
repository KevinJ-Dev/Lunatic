-- Illégal, étape 7b : braquages (supérettes, bijouterie, banques Fleeca).
-- Les cibles sont détectées côté client (modèle ou point du panel) ; ici tout est revérifié :
-- distance, policiers en service, crew et level, outil, arme en main, étape, cible déjà prise, délai du lieu.
-- Un lieu = les cibles proches d'un même type (Config.HeistClusterRadius). Une fois braqué, il reste ouvert
-- Config.HeistWindow secondes pour finir, puis fermé jusqu'à la fin de son délai (réglé dans le panel).

local ox = exports.ox_inventory
local admin = exports.lunatic_admin

local places = {}   -- lieux braqués récemment
local pending = {}  -- action en cours par joueur
local sequence = 0

local function fail(message)
    return { ok = false, error = message }
end

local function config()
    local found, value = pcall(function() return admin:getHeistConfig() end)
    return found and value or nil
end

local function itemLabel(name)
    local item = ox:Items(name)
    return item and item.label or name
end

local function targetKey(coords)
    return ('%.1f:%.1f:%.1f'):format(math.floor(coords.x * 2 + 0.5) / 2, math.floor(coords.y * 2 + 0.5) / 2, math.floor(coords.z * 2 + 0.5) / 2)
end

---------------------------------------------------------------------
-- Lieux braqués (gardés d'un redémarrage à l'autre)
---------------------------------------------------------------------

local function save()
    local list = {}

    for key, place in pairs(places) do
        list[#list + 1] = { key = key, type = place.type, x = place.x, y = place.y, z = place.z, started = place.started, untilAt = place.untilAt, done = place.done, lockers = place.lockers, doorOpen = place.doorOpen, alerted = place.alerted, rewarded = place.rewarded }
    end

    SetResourceKvp('heists', json.encode(list))
end

do
    local ok, list = pcall(json.decode, GetResourceKvpString('heists') or '[]')

    for _, entry in ipairs(ok and type(list) == 'table' and list or {}) do
        if entry.untilAt and entry.untilAt > os.time() then
            places[entry.key] = entry
        end
    end
end

local function openDoors()
    local list = {}

    for _, place in pairs(places) do
        if place.doorOpen then
            list[#list + 1] = { x = place.doorX or place.x, y = place.doorY or place.y, z = place.doorZ or place.z }
        end
    end

    return list
end

local function broadcastDoors()
    TriggerClientEvent('lunatic_illegal:heistDoors', -1, openDoors())
end

local function findPlace(typeId, coords)
    local radius = Config.HeistClusterRadius[typeId] or 25.0

    for key, place in pairs(places) do
        if place.type == typeId and #(vector3(place.x, place.y, place.z) - coords) <= radius then
            return place, key
        end
    end
end

-- Délais écoulés : lieux à nouveau disponibles, portes des coffres refermées
CreateThread(function()
    while true do
        Wait(30000)
        local now, changed, doors = os.time(), false, false

        for key, place in pairs(places) do
            if place.untilAt <= now then
                doors = doors or place.doorOpen
                places[key] = nil
                changed = true
            end
        end

        if changed then
            save()
        end

        if doors then
            broadcastDoors()
        end
    end
end)

---------------------------------------------------------------------
-- Rappels
---------------------------------------------------------------------

-- Configuration de détection pour les joueurs (modèles, points, actions)
lib.callback.register('lunatic_illegal:heistConfig', function()
    local cfg = config()

    if not cfg then
        return nil
    end

    local list = {}

    for typeId, s in pairs(cfg.settings) do
        if s.enabled then
            local actions = {}

            for actionId, action in pairs(s.actions or {}) do
                actions[actionId] = { tool = action.tool, models = action.models, duration = action.duration, points = cfg.points[actionId] or {} }
            end

            list[typeId] = { label = cfg.labels[typeId].label, actions = actions }
        end
    end

    return { types = list, doors = openDoors() }
end)

AddEventHandler('lunatic_admin:heistsChanged', function()
    TriggerClientEvent('lunatic_illegal:heistConfigChanged', -1)
end)

local function alert(place, coords, label)
    for _, officer in ipairs(PolicePlayers()) do
        TriggerClientEvent('lunatic_illegal:heistAlert', officer, { x = coords.x, y = coords.y, label = label })
    end

    place.alerted = true
end

local ALARMS = { register = 'Alarme : caisse forcée', safe = 'Alarme : coffre de magasin', case = 'Alarme : bijouterie', door = 'Alarme : banque Fleeca', locker = 'Alarme : banque Fleeca' }

lib.callback.register('lunatic_illegal:heistStart', function(src, typeId, actionId, coords)
    local cfg = config()
    local s = cfg and cfg.settings[typeId]
    local action = s and s.actions and s.actions[actionId]

    if not action or not s.enabled then
        return fail('Rien à braquer ici.')
    end

    if type(coords) ~= 'vector3' then
        return fail('Cible invalide.')
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or #(GetEntityCoords(ped) - coords) > (actionId == 'locker' and 9.0 or 3.0) then
        return fail('Vous êtes trop loin.')
    end

    if #PolicePlayers() < s.police then
        return fail("Trop risqué : il n'y a pas assez de policiers en ville.")
    end

    if s.crewOnly then
        local crew = CrewOf(src)

        if not crew then
            return fail("Ce coup-là, c'est pour les crews.")
        end

        if crew.level < s.minLevel then
            return fail(('Votre crew doit être level %d pour ce coup.'):format(s.minLevel))
        end
    end

    if action.tool ~= '' and (ox:GetItemCount(src, action.tool) or 0) < 1 then
        return fail(('Il vous faut : %s.'):format(itemLabel(action.tool)))
    end

    -- Vitrines : il faut quelque chose en main pour les briser
    if actionId == 'case' and GetSelectedPedWeapon(ped) == `WEAPON_UNARMED` then
        return fail('Il vous faut une arme en main pour briser la vitrine.')
    end

    if pending[src] then
        return fail('Vous êtes déjà occupé.')
    end

    local place, key = findPlace(typeId, coords)
    local now = os.time()

    if place and now > place.started + Config.HeistWindow then
        return fail(('Cet endroit a déjà été braqué : revenez dans %d min.'):format(math.max(1, math.ceil((place.untilAt - now) / 60))))
    end

    local target = targetKey(coords)

    if place then
        if actionId == 'locker' then
            if not place.doorOpen then
                return fail("La porte du coffre est fermée.")
            end

            if (place.lockers or 0) >= (action.count or 1) then
                return fail('Tous les casiers ont été vidés.')
            end
        elseif place.done[target] then
            return fail('Déjà vidé.')
        end

        if actionId == 'door' and place.doorOpen then
            return fail('La porte est déjà ouverte.')
        end
    elseif actionId == 'locker' then
        return fail("La porte du coffre est fermée.")
    end

    -- Nouveau lieu = une mission commencée : limite du jour réglée dans la page Missions du panel
    if not place and s.mission and not admin:takeMissionSlot(s.mission.id) then
        return fail("Plus de coup de ce genre aujourd'hui : la ville est sur ses gardes.")
    end

    if not place then
        sequence = sequence + 1
        key = ('%s-%d-%d'):format(typeId, now, sequence)
        place = { type = typeId, x = coords.x, y = coords.y, z = coords.z, started = now, untilAt = now + s.cooldown * 60, done = {}, lockers = 0 }
        places[key] = place
        save()
    end

    pending[src] = { key = key, typeId = typeId, actionId = actionId, target = target, coords = coords, at = GetGameTimer(), duration = action.duration }

    -- Alarme : à chaque tentative selon le pourcentage, une seule fois par lieu pour la bijouterie et la banque
    if math.random(100) <= action.alert and (typeId == 'store' or not place.alerted) then
        alert(place, coords, ALARMS[actionId])
        save()
    end

    return { ok = true, duration = action.duration }
end)

lib.callback.register('lunatic_illegal:heistFinish', function(src, success)
    local job = pending[src]
    pending[src] = nil

    if not job then
        return fail('Action interrompue.')
    end

    local cfg = config()
    local action = cfg and cfg.settings[job.typeId] and cfg.settings[job.typeId].actions[job.actionId]
    local place = places[job.key]

    if not action or not place then
        return fail('Action interrompue.')
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or #(GetEntityCoords(ped) - job.coords) > (job.actionId == 'locker' and 10.0 or 4.0) then
        return fail('Vous vous êtes éloigné.')
    end

    -- Échec du mini-jeu : l'outil peut casser
    if not success then
        if action.tool ~= '' and math.random(100) <= action.breakChance then
            ox:RemoveItem(src, action.tool, 1)
            return { ok = true, failed = true, broken = itemLabel(action.tool) }
        end

        return { ok = true, failed = true }
    end

    if GetGameTimer() - job.at < job.duration * 1000 - 1500 then
        return fail('Trop rapide.')
    end

    if job.actionId == 'locker' then
        if (place.lockers or 0) >= (action.count or 1) then
            return fail('Tous les casiers ont été vidés.')
        end

        place.lockers = (place.lockers or 0) + 1
    else
        if place.done[job.target] then
            return fail('Déjà vidé.')
        end

        place.done[job.target] = true
    end

    if job.actionId == 'door' then
        place.doorOpen = true
        place.doorX, place.doorY, place.doorZ = job.coords.x, job.coords.y, job.coords.z
        broadcastDoors()
    end

    -- XP et influence du crew (page Missions) : une fois par lieu, à la première action réussie
    local mission = cfg.settings[job.typeId].mission

    if mission and not place.rewarded then
        local crew = CrewOf(src)

        if crew then
            place.rewarded = true

            if (mission.xp or 0) > 0 then
                pcall(function() admin:addCrewXp(crew.id, mission.xp) end)
            end

            if (mission.influence or 0) > 0 then
                pcall(function() admin:addCrewInfluence(crew.id, mission.influence, job.coords.x, job.coords.y, "heist:" .. job.typeId) end)
            end
        end
    end

    save()

    local loot = {}

    for _, entry in ipairs(action.loot or {}) do
        if math.random(100) <= entry.chance then
            local count = math.random(entry.min, entry.max)

            if ox:CanCarryItem(src, entry.item, count) and ox:AddItem(src, entry.item, count) then
                loot[#loot + 1] = ('%d × %s'):format(count, itemLabel(entry.item))
            end
        end
    end

    return { ok = true, loot = loot, door = job.actionId == 'door' }
end)

RegisterNetEvent('lunatic_illegal:heistCancel', function()
    pending[source] = nil
end)

AddEventHandler('playerDropped', function()
    pending[source] = nil
end)

---------------------------------------------------------------------
-- Exports (panel staff)
---------------------------------------------------------------------

exports('getHeistStates', function()
    local cfg = config()
    local list, now = {}, os.time()

    for key, place in pairs(places) do
        local done = place.lockers or 0

        for _ in pairs(place.done or {}) do
            done = done + 1
        end

        list[#list + 1] = {
            key = key, type = place.type, typeLabel = cfg and cfg.labels[place.type] and cfg.labels[place.type].label or place.type,
            x = place.x, y = place.y, left = place.untilAt - now, active = now <= place.started + Config.HeistWindow, done = done, doorOpen = place.doorOpen == true,
        }
    end

    table.sort(list, function(a, b) return a.left < b.left end)
    return list
end)

exports('resetHeist', function(key)
    local place = places[key]

    if not place then
        return false
    end

    places[key] = nil
    save()

    if place.doorOpen then
        broadcastDoors()
    end

    return true
end)
