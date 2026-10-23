-- Braquage ATM (réglages dans le panel, page Missions → « Braquage ATM »).
-- Devant un distributeur, avec l'outil demandé : piratage (mini-jeu), puis les billets sortent pendant la durée réglée.
-- Échec : l'outil peut casser. Alarme selon un pourcentage. Délai par distributeur et par joueur. Ouvert à tous ;
-- XP et influence si le joueur a un crew. Tout est revérifié ici (distance, outil, étapes, durée, délais, limite du jour).

local ox = exports.ox_inventory
local admin = exports.lunatic_admin

local cooldowns = {} -- distributeur -> fin du délai (os.time), gardé d'un redémarrage à l'autre
local lastHack = {}  -- joueur -> dernier piratage (os.time)
local pending = {}   -- joueur -> piratage en cours { key, coords, stage, at, duration }

local function fail(message)
    return { ok = false, error = message }
end

local function itemLabel(name)
    local item = ox:Items(name)
    return item and item.label or name
end

-- Un distributeur = sa position arrondie au mètre
local function atmKey(coords)
    return ('%d:%d:%d'):format(math.floor(coords.x + 0.5), math.floor(coords.y + 0.5), math.floor(coords.z + 0.5))
end

do
    local ok, saved = pcall(json.decode, GetResourceKvpString('atms') or '{}')

    for key, untilAt in pairs(ok and type(saved) == 'table' and saved or {}) do
        if tonumber(untilAt) and tonumber(untilAt) > os.time() then
            cooldowns[key] = tonumber(untilAt)
        end
    end
end

local function saveCooldowns()
    local list, now = {}, os.time()

    for key, untilAt in pairs(cooldowns) do
        if untilAt > now then
            list[key] = untilAt
        end
    end

    SetResourceKvp('atms', json.encode(list))
end

-- Mission activée et outil demandé, pour afficher ou non l'invite en jeu
lib.callback.register('lunatic_illegal:atmConfig', function()
    local m = MissionSettings('heist_atm')
    return { enabled = m ~= nil and m.enabled == true, tool = m and m.advanced.tool or '' }
end)

AddEventHandler('lunatic_admin:heistsChanged', function()
    TriggerClientEvent('lunatic_illegal:atmConfigChanged', -1)
end)

lib.callback.register('lunatic_illegal:atmStart', function(src, coords)
    local m = MissionSettings('heist_atm')
    local problem = MissionProblem(src, m)

    if problem then
        return fail(problem)
    end

    if type(coords) ~= 'vector3' then
        return fail('Distributeur invalide.')
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or #(GetEntityCoords(ped) - coords) > 2.5 then
        return fail('Vous êtes trop loin du distributeur.')
    end

    if pending[src] then
        return fail('Vous êtes déjà occupé.')
    end

    if IsPolice(src) then
        return fail('Vous êtes en service.')
    end

    local a = m.advanced
    local now = os.time()
    local wait = (lastHack[src] or 0) + a.playerCooldown - now

    if wait > 0 then
        return fail(('Faites-vous oublier un peu : encore %d min.'):format(math.max(1, math.ceil(wait / 60))))
    end

    if a.tool ~= '' and (ox:GetItemCount(src, a.tool) or 0) < 1 then
        return fail(('Il vous faut : %s.'):format(itemLabel(a.tool)))
    end

    local key = atmKey(coords)

    if (cooldowns[key] or 0) > now then
        return fail(('Ce distributeur est vide : revenez dans %d min.'):format(math.max(1, math.ceil((cooldowns[key] - now) / 60))))
    end

    if not admin:takeMissionSlot('heist_atm') then
        return fail("Plus de distributeur aujourd'hui : les banques sont sur leurs gardes.")
    end

    lastHack[src] = now
    pending[src] = { key = key, coords = coords, stage = 'hack', at = GetGameTimer() }

    return { ok = true, difficulty = a.difficulty, duration = a.duration }
end)

-- Fin du mini-jeu : raté (l'outil peut casser) ou réussi (les billets commencent à sortir)
lib.callback.register('lunatic_illegal:atmHacked', function(src, success)
    local job = pending[src]
    local m = MissionSettings('heist_atm')

    if not job or job.stage ~= 'hack' or not m then
        pending[src] = nil
        return fail('Piratage interrompu.')
    end

    local a = m.advanced

    if not success then
        pending[src] = nil

        if a.tool ~= '' and math.random(100) <= a.breakChance then
            ox:RemoveItem(src, a.tool, 1)
            return { ok = true, failed = true, broken = itemLabel(a.tool) }
        end

        return { ok = true, failed = true }
    end

    cooldowns[job.key] = os.time() + a.cooldown * 60
    saveCooldowns()
    job.stage, job.at, job.duration = 'cash', GetGameTimer(), a.duration

    -- Alarme du distributeur : la police est prévenue quelques secondes plus tard
    if math.random(100) <= a.alert then
        local coords = job.coords

        SetTimeout(math.random(5, 15) * 1000, function()
            AlertPolice(coords, 'Alarme : distributeur forcé', 0)
        end)
    end

    return { ok = true, duration = a.duration }
end)

lib.callback.register('lunatic_illegal:atmFinish', function(src)
    local job = pending[src]
    pending[src] = nil

    local m = MissionSettings('heist_atm')

    if not job or job.stage ~= 'cash' or not m then
        return fail('Piratage interrompu.')
    end

    if GetGameTimer() - job.at < job.duration * 1000 - 1500 then
        return fail('Trop rapide.')
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or #(GetEntityCoords(ped) - job.coords) > 4.0 then
        return fail('Vous vous êtes éloigné : les billets sont restés dans la machine.')
    end

    local reward, loot = MissionPayout(src, m, job.coords, 'atm', Config.HoldupAccount)
    return { ok = true, reward = MoneyText(reward), loot = loot }
end)

RegisterNetEvent('lunatic_illegal:atmCancel', function()
    pending[source] = nil
end)

AddEventHandler('playerDropped', function()
    pending[source] = nil
end)
