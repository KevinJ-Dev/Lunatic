-- Braquages de magasins : un PNJ vendeur au comptoir (points et réglages dans le panel, page Braquages ;
-- statut, policiers, gain, XP, influence et level dans la page Missions). Ouvert à tous, crew ou non.
-- Le vendeur est créé ici, en réseau : tous les joueurs voient le même, et il peut être tué. Mort, la caisse
-- reste fermée (seul le coffre reste à percer) jusqu'à ce qu'un nouveau vendeur prenne sa place après le délai.
-- Le joueur menace le vendeur avec l'arme demandée (jamais les poings) ; avec une arme blanche il peut résister.
-- Sinon il remplit le sac pendant la durée réglée, tant que le joueur reste près de lui, arme en main.
-- Tout est revérifié ici : distance, arme, vendeur vivant, policiers, crew et level, délai, limite du jour, durée.

local ox = exports.ox_inventory
local admin = exports.lunatic_admin

local cooldowns = {} -- point -> fin du délai (os.time), gardé d'un redémarrage à l'autre
local robbing = {}   -- point -> joueur en train de le braquer
local pending = {}   -- joueur -> braquage en cours
local clerks = {}    -- point -> { ped, key } vendeur en réseau et réglages avec lesquels il a été créé
local deadUntil = {} -- point -> vendeur mort (ou parti) : remplacé après cette heure (os.time)

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
    return ('%s %s'):format(tostring(math.floor(amount or 0)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', ''), GlobalState.lunaticCurrency or '$')
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

local function alertPolice(point, label)
    for _, officer in ipairs(PolicePlayers()) do
        TriggerClientEvent('lunatic_illegal:heistAlert', officer, { x = point.x, y = point.y, label = label })
    end
end

---------------------------------------------------------------------
-- Vendeurs en réseau : créés quand un joueur approche, retirés quand plus personne n'est autour
---------------------------------------------------------------------

local function clerkPed(pointId)
    local clerk = clerks[pointId]
    return clerk and DoesEntityExist(clerk.ped) and clerk.ped or nil
end

-- Tant qu'aucun joueur ne contrôle le PNJ, sa santé n'est pas encore synchronisée : il est considéré vivant
local function clerkAlive(ped)
    return ped ~= nil and DoesEntityExist(ped) and (NetworkGetEntityOwner(ped) == -1 or GetEntityHealth(ped) > 0)
end

local function removeClerk(pointId)
    local ped = clerkPed(pointId)

    if ped then
        DeleteEntity(ped)
    end

    clerks[pointId] = nil
end

-- Animation du vendeur, jouée par le joueur qui contrôle le PNJ (et vue par tous) : robbed, done, resist, idle
local function clerkState(pointId, state, robber)
    local ped = clerkPed(pointId)

    if ped then
        TriggerClientEvent('lunatic_illegal:holdupClerk', -1, NetworkGetNetworkIdFromEntity(ped), state, robber)
    end
end

local function pointKey(point)
    return ('%s:%.2f:%.2f:%.2f:%.1f'):format(point.ped, point.x, point.y, point.z, point.h or 0.0)
end

local function spawnClerk(point)
    local ped = CreatePed(4, joaat(point.ped), point.x, point.y, point.z, point.h or 0.0, true, true)
    local timeout = GetGameTimer() + 3000

    while not DoesEntityExist(ped) and GetGameTimer() < timeout do
        Wait(50)
    end

    if not DoesEntityExist(ped) then
        -- Modèle de PNJ invalide ? Nouvel essai dans une minute (vérifier le modèle dans le panel)
        deadUntil[point.id] = os.time() + 60
        print(("^3[lunatic_illegal] Braquage #%d (%s) : le vendeur « %s » n'a pas pu être créé.^0"):format(point.id, point.label, point.ped))
        return
    end

    -- Les joueurs reconnaissent le vendeur par ce statebag (réglages du PNJ, menace)
    Entity(ped).state:set('lunaticClerk', point.id, true)
    clerks[point.id] = { ped = ped, key = pointKey(point) }
end

CreateThread(function()
    Wait(5000)

    while true do
        local cfg = config()

        if cfg then
            local now = os.time()
            local players = {}

            for _, id in ipairs(GetPlayers()) do
                local ped = GetPlayerPed(id)

                if ped and ped ~= 0 then
                    players[#players + 1] = GetEntityCoords(ped).xy
                end
            end

            local wanted = {}

            for _, point in ipairs(cfg.points) do
                -- Hauteur inconnue (placé sur la carte) : en attente de la mesure d'un joueur proche
                if available(cfg, point) and point.z > -100.0 then
                    local nearest = math.huge

                    for _, coords in ipairs(players) do
                        nearest = math.min(nearest, #(coords - vector2(point.x, point.y)))
                    end

                    if nearest < Config.HoldupSpawnRange or (clerks[point.id] and nearest < Config.HoldupSpawnRange + 40.0) then
                        wanted[point.id] = point
                    end
                end
            end

            for id, clerk in pairs(clerks) do
                local point = wanted[id]

                if not point or not DoesEntityExist(clerk.ped) or clerk.key ~= pointKey(point) then
                    removeClerk(id)
                elseif not clerkAlive(clerk.ped) then
                    -- Vendeur tué : la caisse reste fermée jusqu'à son remplaçant
                    if not deadUntil[id] then
                        local t = cfg.types[point.type]
                        deadUntil[id] = now + (t and t.settings.cooldown or 30) * 60
                    elseif now >= deadUntil[id] then
                        removeClerk(id)
                    end
                end
            end

            for id, point in pairs(wanted) do
                if not clerks[id] and (deadUntil[id] or 0) <= now then
                    deadUntil[id] = nil
                    spawnClerk(point)
                end
            end
        end

        Wait(2000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for id in pairs(clerks) do
            removeClerk(id)
        end
    end
end)

-- Hauteur du sol d'un point placé sur la carte du panel, mesurée par un joueur proche
RegisterNetEvent('lunatic_illegal:holdupGround', function(pointId, z)
    local src = source
    local cfg = config()
    local point = cfg and findPoint(cfg, pointId)
    local ped = GetPlayerPed(src)

    if not point or point.z > -100.0 or not ped or ped == 0 or #(GetEntityCoords(ped).xy - vector2(point.x, point.y)) > Config.HoldupSpawnRange + 20.0 then
        return
    end

    pcall(function() admin:setHoldupGround(point.id, z) end)
end)

---------------------------------------------------------------------
-- Configuration pour les joueurs (points dont la hauteur reste à mesurer)
---------------------------------------------------------------------

lib.callback.register('lunatic_illegal:holdupConfig', function()
    local cfg = config()

    if not cfg then
        return nil
    end

    local list = {}

    for _, point in ipairs(cfg.points) do
        if available(cfg, point) and point.z <= -100.0 then
            list[#list + 1] = { id = point.id, x = point.x, y = point.y }
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
    local clerk = clerkPed(point.id)

    if not clerkAlive(clerk) then
        return fail("Le vendeur est mort : plus personne pour ouvrir la caisse.")
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(clerk)) > Config.HoldupRange then
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

    -- Level du crew activé dans la page Missions : réservé aux crews du level requis ; sinon ouvert à tous
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

    -- Arme blanche : le vendeur peut ne pas se laisser faire (alarme, il s'enfuit, magasin fermé un moment)
    if WeaponClass(src) == 'melee' and math.random(100) <= (s.resist or 0) then
        cooldowns[point.id] = now + math.floor(s.cooldown * 60 / 2)
        saveCooldowns()
        clerkState(point.id, 'resist', src)
        alertPolice(point, ('Alarme : %s'):format(point.label))

        -- Parti en courant : un remplaçant prend sa place une minute plus tard
        SetTimeout(60000, function()
            removeClerk(point.id)
        end)

        return { ok = false, resisted = true, error = "Le vendeur ne s'est pas laissé impressionner : il a déclenché l'alarme !" }
    end

    cooldowns[point.id] = now + s.cooldown * 60
    saveCooldowns()
    robbing[point.id] = src
    pending[src] = { pointId = point.id, at = GetGameTimer(), duration = s.duration }
    clerkState(point.id, 'robbed', src)

    -- Alarme silencieuse : la police est prévenue quelques secondes après le début
    if math.random(100) <= (s.alert or 0) then
        SetTimeout(math.random(5, 15) * 1000, function()
            alertPolice(point, ('Alarme silencieuse : %s'):format(point.label))
        end)
    end

    return { ok = true, duration = s.duration, clerk = NetworkGetNetworkIdFromEntity(clerk) }
end)

-- Braquage interrompu (le joueur s'est éloigné, a baissé son arme ou le vendeur est mort)
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

    local clerk = clerkPed(point.id)

    if not clerkAlive(clerk) then
        abort(src, false)
        return fail('Le vendeur est mort : la caisse reste fermée.')
    end

    local ped = GetPlayerPed(src)
    local far = not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(clerk)) > Config.HoldupKeepRange

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

    -- Gain en argent sale (±20 %), butin éventuel ; XP et influence si le joueur est dans un crew
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
