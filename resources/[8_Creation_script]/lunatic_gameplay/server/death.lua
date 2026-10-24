-- Mort et respawn (réglages : tuile Fonctionnalités → Gameplay → Mort & Respawn).
-- À la mort (événement ESX), le joueur reste inconscient : il peut appeler les secours, être réanimé par un médecin
-- (/reanimer), ou se réveiller à l'hôpital le plus proche une fois le délai écoulé (frais, inventaire vidé si réglé).
-- Le serveur garde l'heure de la mort : un client ne peut pas raccourcir le délai.

local ox = exports.ox_inventory

local deaths = {}    -- joueur -> { at, coords }
local lastCall = {}  -- joueur -> dernier appel aux secours

RegisterNetEvent('esx:onPlayerDeath', function()
    local src = source

    if not deaths[src] then
        local ped = GetPlayerPed(src)
        deaths[src] = { at = os.time(), coords = ped ~= 0 and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0) }
    end
end)

RegisterNetEvent('esx:onPlayerSpawn', function()
    deaths[source] = nil
end)

AddEventHandler('playerDropped', function()
    deaths[source] = nil
    lastCall[source] = nil
end)

local function nearestHospital(coords)
    local best, bestDistance

    for _, hospital in ipairs(Config.Hospitals) do
        local distance = #(coords - hospital.coords.xyz)

        if not bestDistance or distance < bestDistance then
            best, bestDistance = hospital, distance
        end
    end

    return best
end

-- Réveil à l'hôpital : délai écoulé, frais payés, inventaire vidé si réglé
lib.callback.register('lunatic_gameplay:respawn', function(src)
    local death = deaths[src]
    local settings = FeaturesOf('death')
    local xPlayer = ESX.GetPlayerFromId(src)

    if not death or not xPlayer then
        return { ok = false, error = "Vous n'êtes pas inconscient." }
    end

    local delay = settings.enabled == false and 10 or (tonumber(settings.delay) or 300)
    local remaining = death.at + delay - os.time()

    if remaining > 0 then
        return { ok = false, error = ('Encore %d secondes.'):format(remaining) }
    end

    local fee = settings.enabled == false and 0 or (tonumber(settings.fee) or 0)

    if fee > 0 then
        local bank = xPlayer.getAccount('bank')
        local paid = math.min(fee, bank and bank.money or 0)

        if paid > 0 then
            xPlayer.removeAccountMoney('bank', paid, "Frais d'hôpital")
        end
    end

    if settings.enabled ~= false and settings.clearInventory then
        local keep = {}

        for _, name in ipairs(Config.DeathKeepItems) do
            keep[#keep + 1] = name
        end

        if settings.keepCash then
            keep[#keep + 1] = 'money'
        end

        ox:ClearInventory(src, keep)
    end

    deaths[src] = nil
    local hospital = nearestHospital(death.coords)
    local c = hospital.coords

    GameLog('players', 'info', src, 'player.respawn', hospital.label, { fee = fee, cleared = settings.clearInventory == true })
    return { ok = true, x = c.x, y = c.y, z = c.z, h = c.w, label = hospital.label, fee = fee }
end)

-- Temps restant (affichage) : le serveur fait foi
lib.callback.register('lunatic_gameplay:deathState', function(src)
    local death = deaths[src]

    if not death then
        return nil
    end

    local settings = FeaturesOf('death')
    local delay = settings.enabled == false and 10 or (tonumber(settings.delay) or 300)
    return { remaining = math.max(0, death.at + delay - os.time()) }
end)

---------------------------------------------------------------------
-- Secours : appel des médecins, réanimation
---------------------------------------------------------------------

local function isMedic(xPlayer)
    local structure = StructureOf(xPlayer)
    return structure ~= nil and structure.kind == 'public' and Config.MedicTypes[structure.type] == true
end

RegisterNetEvent('lunatic_gameplay:callMedic', function()
    local src = source
    local death = deaths[src]
    local now = os.time()

    if not death or FeaturesOf('death').callMedic == false then
        return
    end

    if lastCall[src] and now - lastCall[src] < Config.MedicCallCooldown then
        return Notify(src, 'Les secours ont déjà été prévenus.', 'info')
    end

    lastCall[src] = now
    local count = 0

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        if isMedic(xPlayer) then
            count = count + 1
            TriggerClientEvent('lunatic_gameplay:medicCall', xPlayer.source, { x = death.coords.x, y = death.coords.y, z = death.coords.z, id = src })
        end
    end

    Notify(src, count > 0 and 'Les secours ont été prévenus.' or 'Aucun médecin en service pour le moment.', count > 0 and 'success' or 'error')
end)

lib.callback.register('lunatic_gameplay:revive', function(src, targetId)
    local xPlayer = ESX.GetPlayerFromId(src)
    targetId = tonumber(targetId)

    if FeaturesOf('death').medicRevive == false then
        return { ok = false, error = 'La réanimation par les médecins est désactivée.' }
    end

    if not xPlayer or not isMedic(xPlayer) then
        return { ok = false, error = 'Réservé aux médecins.' }
    end

    if not targetId or not deaths[targetId] then
        return { ok = false, error = "Personne d'inconscient à côté de vous." }
    end

    local me, target = GetPlayerPed(src), GetPlayerPed(targetId)

    if me == 0 or target == 0 or #(GetEntityCoords(me) - GetEntityCoords(target)) > Config.ReviveDistance + 1.0 then
        return { ok = false, error = 'Rapprochez-vous de la personne.' }
    end

    deaths[targetId] = nil
    TriggerClientEvent('lunatic_gameplay:revived', targetId)
    GameLog('players', 'success', src, 'player.revive', GetPlayerName(targetId), { target = targetId })
    Notify(targetId, 'Vous avez été réanimé.', 'success')
    return { ok = true }
end)
