-- Cambriolage (maisons dans le panel, page Braquages → Maison ; réglages dans la page Missions → Cambriolage).
-- Devant la porte, avec l'outil demandé : crochetage (mini-jeu), puis entrée dans l'intérieur de la maison, isolé dans
-- son propre monde (routing bucket) : les complices qui arrivent pendant le cambriolage entrent sans crocheter.
-- Chaque endroit se fouille une fois (argent et butin) ; à chaque fouille le propriétaire peut se réveiller : police.
-- Seulement la nuit si réglé. Délai par maison. Ouvert à tous ; XP et influence une fois par crew et par maison.
-- Tout est revérifié ici : porte, outil, heure, étapes, distance aux endroits, rythme des fouilles, limite du jour.

local ox = exports.ox_inventory
local admin = exports.lunatic_admin

local houses = {}  -- maison -> { untilAt, openUntil, searched = {}, woke, credited = { crew = true } }
local inside = {}  -- joueur -> { house, interior }
local pending = {} -- joueur -> maison en cours de crochetage
local lastSearch = {} -- joueur -> dernière fouille (os.time)

local OPEN_WINDOW = 20 * 60 -- secondes pendant lesquelles les complices peuvent entrer sans crocheter

local function fail(message)
    return { ok = false, error = message }
end

local function itemLabel(name)
    local item = ox:Items(name)
    return item and item.label or name
end

local function houseList()
    local found, cfg = pcall(function() return admin:getHoldupConfig() end)
    local list = {}

    if found and cfg then
        for _, point in ipairs(cfg.points) do
            if point.type == 'house' and point.active and Config.BurglaryInteriors[point.interior] then
                list[point.id] = point
            end
        end
    end

    return list
end

-- Heure du jeu (lunatic_world) dans la nuit réglée ? Sans horloge, toujours permis
local function isNight(a)
    if a.night ~= 'yes' then
        return true
    end

    local clock = GlobalState.lunaticClock
    local hour = clock and tonumber(clock.h)

    if not hour then
        return true
    end

    if a.nightStart <= a.nightEnd then
        return hour >= a.nightStart and hour < a.nightEnd
    end

    return hour >= a.nightStart or hour < a.nightEnd
end

local function setBucket(src, bucket)
    SetPlayerRoutingBucket(src, bucket)

    if bucket ~= 0 then
        SetRoutingBucketPopulationEnabled(bucket, false)
    end
end

-- Maisons et outil, pour les invites en jeu
lib.callback.register('lunatic_illegal:burglaryConfig', function()
    local m = MissionSettings('burglary')

    if not m or not m.enabled then
        return { enabled = false, houses = {} }
    end

    local list = {}

    for _, house in pairs(houseList()) do
        list[#list + 1] = { id = house.id, label = house.label, x = house.x, y = house.y, z = house.z, interior = house.interior }
    end

    return { enabled = true, tool = m.advanced.tool, search = m.advanced.search, houses = list }
end)

local function refreshClients()
    TriggerClientEvent('lunatic_illegal:burglaryConfigChanged', -1)
end

AddEventHandler('lunatic_admin:heistsChanged', refreshClients)
AddEventHandler('lunatic_admin:holdupsChanged', refreshClients)

---------------------------------------------------------------------
-- Entrée
---------------------------------------------------------------------

lib.callback.register('lunatic_illegal:burglaryStart', function(src, houseId)
    local m = MissionSettings('burglary')
    local problem = MissionProblem(src, m)

    if problem then
        return fail(problem)
    end

    local house = houseList()[tonumber(houseId)]
    local ped = GetPlayerPed(src)

    if not house then
        return fail("Il n'y a rien à cambrioler ici.")
    end

    if not ped or ped == 0 or #(GetEntityCoords(ped).xy - vector2(house.x, house.y)) > 3.0 then
        return fail('Vous êtes trop loin de la porte.')
    end

    if inside[src] or pending[src] then
        return fail('Vous êtes déjà occupé.')
    end

    if IsPolice(src) then
        return fail('Vous êtes en service.')
    end

    local now = os.time()
    local state = houses[house.id]

    -- Cambriolage en cours : les complices entrent par la porte forcée
    if state and state.openUntil > now then
        pending[src] = house.id
        return { ok = true, open = true }
    end

    local a = m.advanced

    if state and state.untilAt > now then
        return fail(('Cette maison a déjà été visitée : revenez dans %d min.'):format(math.max(1, math.ceil((state.untilAt - now) / 60))))
    end

    if not isNight(a) then
        return fail(('Trop risqué en plein jour : revenez la nuit (%dh - %dh).'):format(a.nightStart, a.nightEnd))
    end

    if a.tool ~= '' and (ox:GetItemCount(src, a.tool) or 0) < 1 then
        return fail(('Il vous faut : %s.'):format(itemLabel(a.tool)))
    end

    pending[src] = house.id
    return { ok = true, difficulty = a.difficulty }
end)

-- Fin du crochetage (ou entrée d'un complice) : dans la maison, ou outil cassé
lib.callback.register('lunatic_illegal:burglaryEnter', function(src, success)
    local houseId = pending[src]
    pending[src] = nil

    local m = MissionSettings('burglary')
    local house = houseId and houseList()[houseId]

    if not house or not m then
        return fail('Cambriolage interrompu.')
    end

    local now = os.time()
    local state = houses[house.id]
    local joining = state and state.openUntil > now

    if not joining then
        local a = m.advanced

        if not success then
            if a.tool ~= '' and math.random(100) <= a.breakChance then
                ox:RemoveItem(src, a.tool, 1)
                return { ok = true, failed = true, broken = itemLabel(a.tool) }
            end

            return { ok = true, failed = true }
        end

        if not admin:takeMissionSlot('burglary') then
            return fail("Plus de cambriolage aujourd'hui : le quartier est sur ses gardes.")
        end

        state = { untilAt = now + a.cooldown * 60, openUntil = now + OPEN_WINDOW, searched = {}, woke = false, credited = {} }
        houses[house.id] = state
    end

    inside[src] = { house = house.id, interior = house.interior }
    setBucket(src, Config.BurglaryBucket + house.id)

    return { ok = true, interior = house.interior, searched = state.searched }
end)

---------------------------------------------------------------------
-- Fouille
---------------------------------------------------------------------

local function insidePlayers(houseId)
    local list = {}

    for src, entry in pairs(inside) do
        if entry.house == houseId then
            list[#list + 1] = src
        end
    end

    return list
end

lib.callback.register('lunatic_illegal:burglarySearch', function(src, index)
    local entry = inside[src]
    local m = MissionSettings('burglary')
    local state = entry and houses[entry.house]
    local interior = entry and Config.BurglaryInteriors[entry.interior]
    local spot = interior and interior.spots[tonumber(index)]

    if not state or not m or not spot then
        return fail('Rien à fouiller ici.')
    end

    if state.searched[index] then
        return fail('Déjà fouillé.')
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or #(GetEntityCoords(ped) - spot.coords) > 3.0 then
        return fail('Vous êtes trop loin.')
    end

    local a = m.advanced
    local now = os.time()

    if now - (lastSearch[src] or 0) < a.search - 1 then
        return fail('Trop rapide.')
    end

    lastSearch[src] = now
    state.searched[index] = true

    -- Argent : le gain de la mission partagé entre les endroits (60 à 140 %), et butin
    local cash = math.floor((m.reward or 0) * math.random(60, 140) / 100 / #interior.spots)
    local xPlayer = ESX.GetPlayerFromId(src)

    if xPlayer and cash > 0 then
        xPlayer.addAccountMoney(Config.BurglaryAccount, cash, 'Cambriolage')
    end

    local loot = {}

    for _, l in ipairs(m.loot or {}) do
        if math.random(100) <= l.chance then
            local count = math.random(l.min, l.max)

            if ox:CanCarryItem(src, l.item, count) and ox:AddItem(src, l.item, count) then
                loot[#loot + 1] = ('%d × %s'):format(count, itemLabel(l.item))
            end
        end
    end

    -- XP et influence : une fois par crew et par maison
    local crew = CrewOf(src)
    local house = houseList()[entry.house]

    if crew and not state.credited[crew.id] then
        state.credited[crew.id] = true

        if (m.xp or 0) > 0 then
            pcall(function() admin:addCrewXp(crew.id, m.xp) end)
        end

        if (m.influence or 0) > 0 and house then
            pcall(function() admin:addCrewInfluence(crew.id, m.influence, house.x, house.y, 'burglary') end)
        end
    end

    -- Le propriétaire se réveille : police prévenue, tous les cambrioleurs de la maison avertis
    if not state.woke and math.random(100) <= a.wake then
        state.woke = true

        if house then
            AlertPolice(vector3(house.x, house.y, 0.0), 'Cambriolage en cours', 30)
        end

        for _, target in ipairs(insidePlayers(entry.house)) do
            TriggerClientEvent('lunatic_illegal:burglaryWoke', target)
        end
    end

    for _, target in ipairs(insidePlayers(entry.house)) do
        TriggerClientEvent('lunatic_illegal:burglarySearched', target, index)
    end

    return { ok = true, cash = MoneyText(cash), loot = loot }
end)

---------------------------------------------------------------------
-- Sortie
---------------------------------------------------------------------

local function leave(src)
    local entry = inside[src]
    inside[src] = nil

    if entry then
        setBucket(src, 0)
    end

    return entry
end

lib.callback.register('lunatic_illegal:burglaryExit', function(src)
    local entry = leave(src)
    local house = entry and houseList()[entry.house]

    if not house then
        return fail("Vous n'êtes dans aucune maison.")
    end

    return { ok = true, x = house.x, y = house.y, z = house.z, h = house.h }
end)

-- Sorti autrement (mort, téléporté) : retour dans le monde normal
CreateThread(function()
    while true do
        Wait(2000)

        for src, entry in pairs(inside) do
            local ped = GetPlayerPed(src)
            local interior = Config.BurglaryInteriors[entry.interior]

            if not ped or ped == 0 or not interior or #(GetEntityCoords(ped) - interior.entry.xyz) > 60.0 then
                leave(src)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    inside[source] = nil
    pending[source] = nil
end)
