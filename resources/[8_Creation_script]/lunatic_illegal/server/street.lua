-- Délinquance de rue (réglages dans le panel, page Missions → « Vol à l'arraché » et « Racket »).
-- Vol à l'arraché, mains nues : le joueur arrache le sac d'un passant ([E] tout près) ; réussite selon un pourcentage,
-- sinon le passant se débat. Racket, arme en main : le passant lève les mains et donne son argent tant qu'on le
-- tient en respect. Un témoin peut appeler la police. Ouvert à tous ; XP et influence si le joueur a un crew.
-- Tout est revérifié ici : passant réel (PNJ vivant, à pied, tout près), délai par joueur, policiers, level, limite du jour.

local ox = exports.ox_inventory
local admin = exports.lunatic_admin

local lastSnatch = {} -- joueur -> dernier vol (os.time)
local robbed = {}     -- PNJ -> déjà volé (os.time), un passant ne se fait pas voler deux fois

local function fail(message)
    return { ok = false, error = message }
end

local function mission(id)
    local found, value = pcall(function() return admin:getMissionSettings(id) end)
    return found and value or nil
end

local function itemLabel(name)
    local item = ox:Items(name)
    return item and item.label or name
end

local function money(amount)
    return ('%s $'):format(tostring(math.floor(amount or 0)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', ''))
end

-- Réglages communs aux missions de rue : activée, policiers, crew et level, limite du jour
local function checkMission(src, m)
    if not m or not m.enabled then
        return "Ce n'est pas le moment."
    end

    if #PolicePlayers() < (m.police or 0) then
        return "Trop risqué : il n'y a pas assez de policiers en ville."
    end

    if m.levelRequired then
        local crew = CrewOf(src)

        if not crew then
            return "Ce coup-là, c'est pour les crews."
        end

        if crew.level < (m.minLevel or 1) then
            return ('Votre crew doit être level %d pour ce coup.'):format(m.minLevel)
        end
    end
end

-- Gain, butin, XP et influence (crew) d'une mission de rue réussie
local function payOut(src, m, coords, origin)
    local reward = math.floor((m.reward or 0) * math.random(60, 140) / 100)
    local xPlayer = ESX.GetPlayerFromId(src)

    if xPlayer and reward > 0 then
        xPlayer.addAccountMoney(Config.StreetAccount, reward, origin)
    end

    local loot = {}

    for _, entry in ipairs(m.loot or {}) do
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
            pcall(function() admin:addCrewInfluence(crew.id, m.influence, coords.x, coords.y, origin) end)
        end
    end

    return reward, loot
end

local function alertPolice(coords, label)
    for _, officer in ipairs(PolicePlayers()) do
        TriggerClientEvent('lunatic_illegal:heistAlert', officer, { x = coords.x + math.random(-40, 40), y = coords.y + math.random(-40, 40), label = label })
    end
end

-- Missions de rue activées, pour afficher ou non les invites en jeu
lib.callback.register('lunatic_illegal:streetConfig', function()
    local snatch, racket = mission('snatch'), mission('racket')
    return { snatch = snatch ~= nil and snatch.enabled == true, racket = racket ~= nil and racket.enabled == true }
end)

AddEventHandler('lunatic_admin:heistsChanged', function()
    TriggerClientEvent('lunatic_illegal:streetConfigChanged', -1)
end)

---------------------------------------------------------------------
-- Vol à l'arraché
---------------------------------------------------------------------

lib.callback.register('lunatic_illegal:snatch', function(src, netId)
    local m = mission('snatch')
    local problem = checkMission(src, m)

    if problem then
        return fail(problem)
    end

    local now = os.time()
    local wait = (lastSnatch[src] or 0) + m.advanced.cooldown - now

    if wait > 0 then
        return fail(('Faites-vous oublier un peu : encore %d s.'):format(wait))
    end

    -- Le passant : un PNJ vivant, à pied, tout près du joueur
    local target = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local ped = GetPlayerPed(src)

    if not target or target == 0 or not DoesEntityExist(target) or GetEntityType(target) ~= 1 or IsPedAPlayer(target) then
        return fail('Personne à voler ici.')
    end

    if GetEntityHealth(target) <= 0 or GetVehiclePedIsIn(target, false) ~= 0 or Entity(target).state.lunaticClerk then
        return fail('Personne à voler ici.')
    end

    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(target)) > 3.0 then
        return fail('Vous êtes trop loin.')
    end

    if robbed[target] then
        return fail("Il n'a plus rien sur lui.")
    end

    if not admin:takeMissionSlot('snatch') then
        return fail("Plus de vol de ce genre aujourd'hui : la rue est sur ses gardes.")
    end

    lastSnatch[src] = now
    robbed[target] = now

    local coords = GetEntityCoords(ped)

    -- Un témoin a tout vu
    if math.random(100) <= m.advanced.alert then
        alertPolice(coords, "Vol à l'arraché signalé")
    end

    if math.random(100) > m.advanced.success then
        return { ok = true, success = false }
    end

    local reward, loot = payOut(src, m, coords, 'snatch')
    return { ok = true, success = true, reward = money(reward), loot = loot }
end)

---------------------------------------------------------------------
-- Racket : menacer un passant avec une arme ; il donne son argent tant qu'on le tient en respect
---------------------------------------------------------------------

local lastRacket = {} -- joueur -> dernier racket (os.time)
local rackets = {}    -- joueur -> racket en cours

-- Le passant visé : PNJ vivant, à pied, assez près
local function streetTarget(src, netId, range)
    local target = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local ped = GetPlayerPed(src)

    if not target or target == 0 or not DoesEntityExist(target) or GetEntityType(target) ~= 1 or IsPedAPlayer(target) then
        return nil, 'Personne à racketter ici.'
    end

    if GetEntityHealth(target) <= 0 or GetVehiclePedIsIn(target, false) ~= 0 or Entity(target).state.lunaticClerk then
        return nil, 'Personne à racketter ici.'
    end

    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(target)) > range then
        return nil, 'Vous êtes trop loin.'
    end

    return target
end

lib.callback.register('lunatic_illegal:racketStart', function(src, netId)
    local m = mission('racket')
    local problem = checkMission(src, m)

    if problem then
        return fail(problem)
    end

    if rackets[src] then
        return fail('Vous êtes déjà occupé.')
    end

    -- Un policier en service qui met en joue un passant ne le rackette pas
    for _, officer in ipairs(PolicePlayers()) do
        if officer == src then
            return fail('Vous êtes en service.')
        end
    end

    local now = os.time()
    local wait = (lastRacket[src] or 0) + m.advanced.cooldown - now

    if wait > 0 then
        return fail(('Faites-vous oublier un peu : encore %d s.'):format(wait))
    end

    if not WeaponAllowed(src, m.advanced.weapon) then
        return fail(WeaponRuleText(m.advanced.weapon))
    end

    local target, err = streetTarget(src, netId, 8.0)

    if not target then
        return fail(err)
    end

    if robbed[target] then
        return fail("Il n'a plus rien sur lui.")
    end

    if not admin:takeMissionSlot('racket') then
        return fail("Plus de racket aujourd'hui : la rue est sur ses gardes.")
    end

    lastRacket[src] = now
    robbed[target] = now
    local coords = GetEntityCoords(target)

    if math.random(100) <= m.advanced.alert then
        alertPolice(coords, 'Racket signalé')
    end

    -- Il ne se laisse pas faire : il s'enfuit
    if math.random(100) > m.advanced.success then
        return { ok = true, refused = true }
    end

    rackets[src] = { target = target, at = GetGameTimer(), duration = m.advanced.duration }
    return { ok = true, duration = m.advanced.duration }
end)

RegisterNetEvent('lunatic_illegal:racketCancel', function()
    rackets[source] = nil
end)

lib.callback.register('lunatic_illegal:racketFinish', function(src)
    local job = rackets[src]
    rackets[src] = nil

    if not job then
        return fail('Racket interrompu.')
    end

    local m = mission('racket')

    if not m or not m.enabled then
        return fail('Racket interrompu.')
    end

    if GetGameTimer() - job.at < job.duration * 1000 - 1500 then
        return fail('Trop rapide.')
    end

    local ped = GetPlayerPed(src)

    if not DoesEntityExist(job.target) or GetEntityHealth(job.target) <= 0 or not ped or ped == 0
        or #(GetEntityCoords(ped) - GetEntityCoords(job.target)) > 10.0 or not WeaponAllowed(src, m.advanced.weapon) then
        return fail("Vous l'avez lâché : il s'est enfui.")
    end

    local reward, loot = payOut(src, m, GetEntityCoords(ped), 'racket')
    return { ok = true, reward = money(reward), loot = loot }
end)

AddEventHandler('playerDropped', function()
    lastRacket[source] = nil
    rackets[source] = nil
end)

-- Passants volés : oubliés au bout d'une heure (le PNJ a disparu depuis longtemps)
CreateThread(function()
    while true do
        Wait(600000)
        local limit = os.time() - 3600

        for entity, at in pairs(robbed) do
            if at < limit or not DoesEntityExist(entity) then
                robbed[entity] = nil
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    lastSnatch[source] = nil
end)
