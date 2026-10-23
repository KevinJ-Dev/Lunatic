-- Braquages de magasins : un PNJ vendeur au comptoir (points et réglages dans le panel, page Braquages ;
-- statut, policiers, gain, XP, influence et level dans la page Missions).
-- Le joueur menace le vendeur avec l'arme demandée (jamais les poings) ; avec une arme blanche il peut résister.
-- Sinon il remplit le sac pendant la durée réglée, tant que le joueur reste près de lui, arme en main.
-- Tout est revérifié ici : distance, arme, policiers, crew et level, délai du magasin, limite du jour, durée.

local ox = exports.ox_inventory
local admin = exports.lunatic_admin

local cooldowns = {} -- point -> fin du délai (os.time), gardé d'un redémarrage à l'autre
local robbing = {}   -- point -> joueur en train de le braquer
local pending = {}   -- joueur -> braquage en cours

local function fail(message)
    return { ok = false, error = message }
end

local function config()
    local found, value = pcall(function() return admin:getHoldupConfig() end)
    return found and value or nil
end

local function itemLabel(name)
    local item = ox:Items(name)
    return item and item.label or name
end

local function money(amount)
    return ('%s $'):format(tostring(math.floor(amount or 0)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', ''))
end

do
    local ok, saved = pcall(json.decode, GetResourceKvpString('holdups') or '{}')

    for id, untilAt in pairs(ok and type(saved) == 'table' and saved or {}) do
        if tonumber(untilAt) and tonumber(untilAt) > os.time() then
            cooldowns[tonumber(id)] = tonumber(untilAt)
        end
    end
end

local function saveCooldowns()
    local list = {}

    for id, untilAt in pairs(cooldowns) do
        if untilAt > os.time() then
            list[tostring(id)] = untilAt
        end
    end

    SetResourceKvp('holdups', json.encode(list))
end

local function findPoint(cfg, id)
    for _, point in ipairs(cfg.points) do
        if point.id == tonumber(id) then
            return point
        end
    end
end

-- Un point est braquable en jeu : actif, type disponible, mission activée
local function available(cfg, point)
    local t = point and cfg.types[point.type]
    return point and point.active and t and not t.soon and t.mission and t.mission.enabled and t or nil
end

-- État du vendeur pour tous les joueurs proches : robbed (mains en l'air, remplit le sac), resist, done, idle
local function clerkState(pointId, state)
    TriggerClientEvent('lunatic_illegal:holdupClerk', -1, pointId, state)
end

local function alertPolice(point, label)
    for _, officer in ipairs(PolicePlayers()) do
        TriggerClientEvent('lunatic_illegal:heistAlert', officer, { x = point.x, y = point.y, label = label })
    end
end

---------------------------------------------------------------------
-- Configuration pour les joueurs (PNJ à faire apparaître, arme demandée)
---------------------------------------------------------------------

lib.callback.register('lunatic_illegal:holdupConfig', function()
    local cfg = config()

    if not cfg then
        return nil
    end

    local list = {}

    for _, point in ipairs(cfg.points) do
        local t = available(cfg, point)

        if t then
            list[#list + 1] = { id = point.id, x = point.x, y = point.y, z = point.z, h = point.h, ped = point.ped, weapon = t.settings.weapon }
        end
    end

    return list
end)

-- Panel : points ou réglages changés, missions activées ou non
local function refreshClients()
    TriggerClientEvent('lunatic_illegal:holdupConfigChanged', -1)
end

AddEventHandler('lunatic_admin:holdupsChanged', refreshClients)
AddEventHandler('lunatic_admin:heistsChanged', refreshClients)

---------------------------------------------------------------------
-- Braquage
---------------------------------------------------------------------

lib.callback.register('lunatic_illegal:holdupStart', function(src, pointId)
    local cfg = config()
    local point = cfg and findPoint(cfg, pointId)
    local t = cfg and available(cfg, point)

    if not t then
        return fail("Il n'y a rien à braquer ici.")
    end

    local s, m = t.settings, t.mission
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or #(GetEntityCoords(ped).xy - vector2(point.x, point.y)) > Config.HoldupRange then
        return fail('Vous êtes trop loin du vendeur.')
    end

    if not WeaponAllowed(src, s.weapon) then
        return fail(WeaponRuleText(s.weapon))
    end

    if pending[src] then
        return fail('Vous êtes déjà occupé.')
    end

    if robbing[point.id] then
        return fail('Ce magasin est déjà en train de se faire braquer.')
    end

    local now = os.time()

    if (cooldowns[point.id] or 0) > now then
        return fail(('Ce magasin a déjà été braqué : la caisse est vide, revenez dans %d min.'):format(math.max(1, math.ceil((cooldowns[point.id] - now) / 60))))
    end

    if #PolicePlayers() < (m.police or 0) then
        return fail("Trop risqué : il n'y a pas assez de policiers en ville.")
    end

    local crew = CrewOf(src)

    if m.levelRequired then
        if not crew then
            return fail("Ce coup-là, c'est pour les crews.")
        end

        if crew.level < (m.minLevel or 1) then
            return fail(('Votre crew doit être level %d pour ce coup.'):format(m.minLevel))
        end
    end

    if not admin:takeMissionSlot(m.id) then
        return fail("Plus de braquage de ce genre aujourd'hui : la ville est sur ses gardes.")
    end

    -- Arme blanche : le vendeur peut ne pas se laisser faire (alarme, magasin fermé un moment)
    if WeaponClass(src) == 'melee' and math.random(100) <= (s.resist or 0) then
        cooldowns[point.id] = now + math.floor(s.cooldown * 60 / 2)
        saveCooldowns()
        clerkState(point.id, 'resist')
        alertPolice(point, ('Alarme : %s'):format(point.label))
        return { ok = false, resisted = true, error = "Le vendeur ne s'est pas laissé impressionner : il a déclenché l'alarme !" }
    end

    cooldowns[point.id] = now + s.cooldown * 60
    saveCooldowns()
    robbing[point.id] = src
    pending[src] = { pointId = point.id, typeId = point.type, at = GetGameTimer(), duration = s.duration, crewId = crew and crew.id or nil }
    clerkState(point.id, 'robbed')

    -- Alarme silencieuse : la police est prévenue quelques secondes après le début
    if math.random(100) <= (s.alert or 0) then
        SetTimeout(math.random(5, 15) * 1000, function()
            alertPolice(point, ('Alarme silencieuse : %s'):format(point.label))
        end)
    end

    return { ok = true, duration = s.duration }
end)

-- Braquage interrompu (le joueur s'est éloigné ou a baissé son arme) : le vendeur donne l'alerte
local function abort(src, alarm)
    local job = pending[src]
    pending[src] = nil

    if not job then
        return
    end

    robbing[job.pointId] = nil
    clerkState(job.pointId, 'idle')

    if alarm then
        local cfg = config()
        local point = cfg and findPoint(cfg, job.pointId)

        if point then
            alertPolice(point, ('Alarme : %s'):format(point.label))
        end
    end
end

RegisterNetEvent('lunatic_illegal:holdupCancel', function()
    abort(source, true)
end)

AddEventHandler('playerDropped', function()
    abort(source, false)
end)

lib.callback.register('lunatic_illegal:holdupFinish', function(src)
    local job = pending[src]

    if not job then
        return fail('Braquage interrompu.')
    end

    local cfg = config()
    local point = cfg and findPoint(cfg, job.pointId)
    local t = point and cfg.types[point.type]

    if not t or not t.mission then
        abort(src, false)
        return fail('Braquage interrompu.')
    end

    local ped = GetPlayerPed(src)
    local far = not ped or ped == 0 or #(GetEntityCoords(ped).xy - vector2(point.x, point.y)) > Config.HoldupKeepRange

    if far or not WeaponAllowed(src, t.settings.weapon) then
        abort(src, true)
        return fail("Vous avez lâché le vendeur : il a déclenché l'alarme.")
    end

    if GetGameTimer() - job.at < job.duration * 1000 - 1500 then
        abort(src, true)
        return fail('Trop rapide.')
    end

    pending[src] = nil
    robbing[job.pointId] = nil
    clerkState(job.pointId, 'done')

    -- Gain en argent sale (±20 %), butin éventuel, XP et influence du crew
    local m = t.mission
    local reward = math.floor((m.reward or 0) * math.random(80, 120) / 100)
    local xPlayer = ESX.GetPlayerFromId(src)

    if xPlayer and reward > 0 then
        xPlayer.addAccountMoney(Config.HoldupAccount, reward, 'Braquage')
    end

    local loot = {}

    for _, entry in ipairs(t.settings.loot or {}) do
        if math.random(100) <= entry.chance then
            local count = math.random(entry.min, entry.max)

            if ox:CanCarryItem(src, entry.item, count) and ox:AddItem(src, entry.item, count) then
                loot[#loot + 1] = ('%d × %s'):format(count, itemLabel(entry.item))
            end
        end
    end

    local crew = CrewOf(src)

    if crew then
        if (m.xp or 0) > 0 then
            pcall(function() admin:addCrewXp(crew.id, m.xp) end)
        end

        if (m.influence or 0) > 0 then
            pcall(function() admin:addCrewInfluence(crew.id, m.influence, point.x, point.y, 'holdup:' .. point.type) end)
        end
    end

    return { ok = true, reward = money(reward), loot = loot }
end)
