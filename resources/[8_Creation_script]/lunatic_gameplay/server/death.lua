-- Mort et respawn (réglages : tuile Fonctionnalités → Gameplay → Mort & Respawn).
-- À la mort (événement ESX), le joueur reste inconscient : il peut appeler les secours, être réanimé par un médecin
-- (/reanimer), ou se réveiller à l'hôpital le plus proche une fois le délai écoulé (frais, inventaire vidé si réglé).
-- Le serveur garde l'heure de la mort : un client ne peut pas raccourcir le délai.

local ox = exports.ox_inventory

local deaths = {}     -- joueur -> { at, coords }
local lastCall = {}   -- joueur -> dernier appel aux secours
local responders = {} -- joueur inconscient -> secouriste qui a pris son appel

-- Fin de l'inconscience (réveil, réanimation, déconnexion) : plus de mort ni de secouriste en route
local function clearDeath(src)
    deaths[src] = nil
    responders[src] = nil
end

RegisterNetEvent('esx:onPlayerDeath', function()
    local src = source

    if not deaths[src] then
        local ped = GetPlayerPed(src)
        deaths[src] = { at = os.time(), coords = ped ~= 0 and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0) }
    end
end)

RegisterNetEvent('esx:onPlayerSpawn', function()
    clearDeath(source)
end)

AddEventHandler('playerDropped', function()
    local src = source
    clearDeath(src)
    lastCall[src] = nil

    -- Secouriste déconnecté : ses appels redeviennent libres
    for victim, medic in pairs(responders) do
        if medic == src then
            responders[victim] = nil
        end
    end
end)

local isMedic -- défini plus bas (secours)

-- Secouristes en service : membres d'un service public de type Médecins, en service
local function medicsOnDuty()
    local count = 0

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        if isMedic(xPlayer) and xPlayer.getJob().onDuty ~= false then
            count = count + 1
        end
    end

    return count
end

-- Délai avant le réveil à l'hôpital : réduit quand aucun secouriste n'est en service
local function deathDelay(settings)
    if settings.enabled == false then
        return 10
    end

    if medicsOnDuty() > 0 then
        return tonumber(settings.delay) or 300
    end

    return tonumber(settings.delayNoMedic) or 150
end

-- Liste « a,b,c » d'un réglage du panel -> ensemble { a = true, … }
local function listSetting(value, fallback)
    local set = {}

    for name in tostring(value or fallback):gmatch('[^,%s]+') do
        set[name] = true
    end

    return set
end

-- Hôpitaux actifs réglés dans le panel (Autres → Hôpitaux), sinon ceux de la config
local function hospitals()
    local list = {}

    for _, entry in ipairs(GlobalState.lunaticHospitals or {}) do
        if entry.enabled ~= false then
            list[#list + 1] = { label = entry.label, coords = vector4(entry.x + 0.0, entry.y + 0.0, entry.z + 0.0, (entry.h or 0) + 0.0) }
        end
    end

    return #list > 0 and list or Config.Hospitals
end

exports('getDefaultHospitals', function()
    local list = {}

    for _, hospital in ipairs(Config.Hospitals) do
        local c = hospital.coords
        list[#list + 1] = { label = hospital.label, x = c.x, y = c.y, z = c.z, h = c.w, enabled = true }
    end

    return list
end)

local function nearestHospital(coords)
    local best, bestDistance

    for _, hospital in ipairs(hospitals()) do
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

    local remaining = death.at + deathDelay(settings) - os.time()

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

        for name in pairs(listSetting(settings.keepItems, 'phone,id_card')) do
            keep[#keep + 1] = name
        end

        if settings.keepCash then
            keep[#keep + 1] = 'money'
        end

        ox:ClearInventory(src, keep)
    end

    clearDeath(src)
    local hospital = nearestHospital(death.coords)
    local c = hospital.coords

    GameLog('players', 'info', src, 'player.respawn', hospital.label, { fee = fee, cleared = settings.clearInventory == true })
    return { ok = true, x = c.x, y = c.y, z = c.z, h = c.w, label = hospital.label, fee = fee }
end)

-- Temps restant (affichage) : le serveur fait foi
-- Secouriste qui a pris l'appel : distance jusqu'au joueur inconscient (mètres), ou nil
local function responderOf(src, death)
    local medic = responders[src]
    local ped = medic and GetPlayerPed(medic) or 0

    if ped == 0 then
        responders[src] = nil
        return nil
    end

    return { distance = math.floor(#(GetEntityCoords(ped) - death.coords)) }
end

lib.callback.register('lunatic_gameplay:deathState', function(src)
    local death = deaths[src]

    if not death then
        return nil
    end

    local settings = FeaturesOf('death')
    local medics = medicsOnDuty()

    return {
        remaining = math.max(0, death.at + deathDelay(settings) - os.time()),
        medics = medics,
        callMedic = settings.callMedic ~= false,
        called = lastCall[src] ~= nil and os.time() - lastCall[src] < (tonumber(settings.callCooldown) or 60),
        responder = responderOf(src, death),
    }
end)

-- Zone d'un event (lunatic_admin) : pas de coma (réveil sur place) ou respawn au centre de la zone.
-- Les règles viennent de l'état du joueur, posé par le serveur : le client ne peut pas se les donner.
lib.callback.register('lunatic_gameplay:eventRevive', function(src)
    local event = Player(src).state.lunaticEvent

    if not deaths[src] or type(event) ~= 'table' or not (event.noKO or event.respawn) then
        return { ok = false }
    end

    clearDeath(src)
    GameLog('players', 'info', src, 'player.eventRevive', event.label, { respawn = not event.noKO })

    if event.noKO then
        return { ok = true, here = true }
    end

    return { ok = true, x = event.x, y = event.y, z = event.z or -200.0 }
end)

---------------------------------------------------------------------
-- Secours : appel des médecins, réanimation
---------------------------------------------------------------------

function isMedic(xPlayer)
    local structure = StructureOf(xPlayer)
    return structure ~= nil and structure.kind == 'public' and listSetting(FeaturesOf('death').medicTypes, 'medic')[structure.type] == true
end

-- Partagé avec les objets de soin (server/healitems.lua)
IsMedic = isMedic

function IsPlayerDown(src)
    return deaths[src] ~= nil
end

-- Réanimation sur place (objet de soin) : le joueur se relève là où il est tombé
function RevivePlayer(src, by)
    if not deaths[src] then
        return false
    end

    clearDeath(src)
    TriggerClientEvent('lunatic_gameplay:revived', src)
    GameLog('players', 'success', by, 'player.revive', GetPlayerName(src), { target = src, item = true })
    Notify(src, 'Vous avez été réanimé.', 'success')
    return true
end

RegisterNetEvent('lunatic_gameplay:callMedic', function()
    local src = source
    local death = deaths[src]
    local now = os.time()

    if not death or FeaturesOf('death').callMedic == false then
        return
    end

    if lastCall[src] and now - lastCall[src] < (tonumber(FeaturesOf('death').callCooldown) or 60) then
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

RegisterNetEvent('lunatic_gameplay:acceptCall', function(victim)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    victim = tonumber(victim)

    if not xPlayer or not isMedic(xPlayer) then
        return
    end

    if not victim or not deaths[victim] then
        return Notify(src, "Cet appel n'est plus actif.", 'error')
    end

    local current = responders[victim]

    if current and current ~= src and GetPlayerName(current) then
        return Notify(src, 'Un autre secouriste a déjà pris cet appel.', 'error')
    end

    responders[victim] = src
    Notify(src, ("Vous avez pris l'appel (ID %d) : le point GPS est placé."):format(victim), 'success')
    Notify(victim, 'Un EMS a pris votre appel.', 'success')
    GameLog('players', 'info', src, 'player.medicCall', GetPlayerName(victim), { target = victim })

    for _, other in pairs(ESX.GetExtendedPlayers()) do
        if other.source ~= src and isMedic(other) then
            TriggerClientEvent('lunatic_gameplay:medicCallTaken', other.source, { id = victim, by = xPlayer.getName() })
        end
    end
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

    if me == 0 or target == 0 or #(GetEntityCoords(me) - GetEntityCoords(target)) > (tonumber(FeaturesOf('death').reviveDistance) or 3.0) + 1.0 then
        return { ok = false, error = 'Rapprochez-vous de la personne.' }
    end

    clearDeath(targetId)
    TriggerClientEvent('lunatic_gameplay:revived', targetId)
    GameLog('players', 'success', src, 'player.revive', GetPlayerName(targetId), { target = targetId })
    Notify(targetId, 'Vous avez été réanimé.', 'success')
    return { ok = true }
end)
