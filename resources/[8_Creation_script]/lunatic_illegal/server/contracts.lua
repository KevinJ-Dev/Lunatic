-- Illégal, étape 7a : contrats de mission (onglet Missions de la tablette).
-- Chaque crew reçoit ses propres offres, renouvelées toutes les Config.ContractRotation secondes.
-- Seuls les membres de rang Config.ContractMinRank ou plus acceptent ou abandonnent ; tout le crew peut ensuite participer.
-- Types : livraison (colis scellé A -> B), vol sur commande (véhicule -> garage), cargaison gardée (PNJ armés, caisse).
-- Réglages et points : panel staff (lunatic_admin, export getContractConfig). Tout est vérifié ici, côté serveur.

local ox = exports.ox_inventory
local admin = exports.lunatic_admin

local offers = {}  -- crewId -> { at, list }
local active = {}  -- crewId -> contrat en cours
local sequence = 0

local function fail(message)
    return { ok = false, error = message }
end

local function config()
    local found, value = pcall(function() return admin:getContractConfig() end)
    return found and value or nil
end

local function itemLabel(name)
    local item = ox:Items(name)
    return item and item.label or name
end

local function crewOnline(crewId)
    local found, list = pcall(function() return admin:getCrewOnline(crewId) end)
    return found and list or {}
end

local function notifyCrew(crewId, message, kind)
    for _, target in ipairs(crewOnline(crewId)) do
        TriggerClientEvent('esx:showNotification', target, message, kind or 'info')
    end
end

local function near(src, point, distance)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)) <= distance
end

local function money(amount)
    return ('%s $'):format(tostring(math.floor(amount or 0)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', ''))
end

local function pick(list)
    return list[math.random(#list)]
end

local function canLead(crew)
    return crew and crew.rank >= Config.ContractMinRank
end

---------------------------------------------------------------------
-- Offres
---------------------------------------------------------------------

local function newOffer(cfg, typeId, crew)
    local s = cfg.settings[typeId]
    local p = cfg.points
    sequence = sequence + 1
    local offer = {
        id = ('%d-%d'):format(crew.id, sequence), type = typeId, typeLabel = cfg.labels[typeId],
        reward = math.floor(math.random(s.rewardMin, math.max(s.rewardMin, s.rewardMax)) / 50 + 0.5) * 50,
        xp = s.xp, duration = s.duration, minLevel = s.minLevel,
    }

    if typeId == 'delivery' then
        local from = pick(p.pickup)
        local to = pick(p.dropoff)

        -- Une livraison qui ne bouge pas n'a pas d'intérêt : autre point de livraison si possible
        for _ = 1, 5 do
            if #(vector3(from.x, from.y, from.z) - vector3(to.x, to.y, to.z)) > 400.0 then
                break
            end

            to = pick(p.dropoff)
        end

        offer.from, offer.to = from, to
        offer.title = ('Livraison : %s -> %s'):format(from.label, to.label)
    elseif typeId == 'theft' then
        offer.from, offer.to, offer.model = pick(p.car_spawn), pick(p.garage), pick(s.vehicles)
        offer.title = ('Vol sur commande : %s'):format(offer.model)
    else
        offer.from = pick(p.cargo)
        offer.title = ('Cargaison gardée : %s'):format(offer.from.label)
    end

    return offer
end

-- Types que le crew peut faire (activés, points placés, level suffisant)
local function availableTypes(cfg, crew)
    local list = {}
    local need = { delivery = { 'pickup', 'dropoff' }, theft = { 'car_spawn', 'garage' }, cargo = { 'cargo' } }

    for typeId, kinds in pairs(need) do
        local s = cfg.settings[typeId]
        local ok = s and s.enabled and crew.level >= s.minLevel and (typeId ~= 'theft' or #(s.vehicles or {}) > 0)

        for _, kind in ipairs(kinds) do
            ok = ok and #(cfg.points[kind] or {}) > 0
        end

        if ok then
            list[#list + 1] = typeId
        end
    end

    table.sort(list)
    return list
end

local function offersFor(crew)
    local current = offers[crew.id]

    if current and os.time() - current.at < Config.ContractRotation then
        return current.list
    end

    local cfg = config()
    local list = {}

    if cfg then
        local types = availableTypes(cfg, crew)

        for index = 1, (#types > 0 and Config.ContractOffers or 0) do
            -- Un de chaque type d'abord, puis au hasard
            list[#list + 1] = newOffer(cfg, types[index] or pick(types), crew)
        end
    end

    offers[crew.id] = { at = os.time(), list = list }
    return list
end

---------------------------------------------------------------------
-- Contrat en cours
---------------------------------------------------------------------

local STAGES = {
    pickup = 'Récupérer le colis scellé',
    deliver_package = 'Livrer le colis',
    steal = 'Voler le véhicule',
    deliver_vehicle = 'Amener le véhicule au garage',
    assault = 'Éliminer les gardes et ouvrir la caisse',
}

-- Ce que voient les membres du crew (tablette et objectif au sol)
local function view(contract)
    local objective = contract.stage == 'pickup' and contract.from
        or contract.stage == 'deliver_package' and contract.to
        or contract.stage == 'steal' and contract.from
        or contract.stage == 'deliver_vehicle' and contract.to
        or contract.from

    return {
        id = contract.id, type = contract.type, title = contract.title, stage = contract.stage, stageText = STAGES[contract.stage],
        left = math.max(0, contract.deadline - os.time()), reward = contract.reward, xp = contract.xp, model = contract.model,
        vehicle = contract.vehicleNet, acceptedBy = contract.acceptedBy,
        objective = { label = objective.label, x = objective.x, y = objective.y, z = objective.z },
    }
end

local function broadcast(contract)
    local data = contract and view(contract) or nil

    for _, target in ipairs(crewOnline(contract.crewId)) do
        TriggerClientEvent('lunatic_illegal:contractUpdate', target, data)
    end
end

local function deleteNet(netId)
    if not netId then
        return
    end

    local entity = NetworkGetEntityFromNetworkId(netId)

    if entity and entity ~= 0 and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end

-- Fin du contrat (réussi, échoué, abandonné, annulé) : nettoyage et mise à jour des membres
local function finish(contract)
    active[contract.crewId] = nil
    deleteNet(contract.vehicleNet)

    for _, netId in ipairs(contract.guards or {}) do
        deleteNet(netId)
    end

    for _, target in ipairs(crewOnline(contract.crewId)) do
        TriggerClientEvent('lunatic_illegal:contractUpdate', target, nil)
    end
end

local function alertPolice(contract, coords, label)
    if math.random(100) > (contract.alertChance or 0) then
        return
    end

    for _, officer in ipairs(PolicePlayers()) do
        TriggerClientEvent('lunatic_illegal:contractAlert', officer, { x = coords.x + math.random(-60, 60), y = coords.y + math.random(-60, 60), label = label })
    end
end

-- Contrat réussi : argent sale au joueur qui le termine, XP au crew, butin tiré au sort
local function complete(src, contract, factor)
    local xPlayer = ESX.GetPlayerFromId(src)
    local reward = math.floor(contract.reward * (factor or 1))
    local loot = {}

    if xPlayer and reward > 0 then
        xPlayer.addAccountMoney(Config.ContractAccount, reward, 'Contrat')
    end

    if (contract.xp or 0) > 0 then
        pcall(function() admin:addCrewXp(contract.crewId, contract.xp) end)
    end

    for _, entry in ipairs(contract.loot or {}) do
        if math.random(100) <= entry.chance then
            local count = math.random(entry.min, entry.max)

            if ox:CanCarryItem(src, entry.item, count) and ox:AddItem(src, entry.item, count) then
                loot[#loot + 1] = ('%d × %s'):format(count, itemLabel(entry.item))
            end
        end
    end

    finish(contract)
    notifyCrew(contract.crewId, ('Contrat réussi : %s. %s en argent sale%s.'):format(contract.title, money(reward),
        #loot > 0 and (', butin : ' .. table.concat(loot, ', ')) or ''), 'success')
end

-- Délai dépassé : contrat échoué
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()

        for _, contract in pairs(active) do
            if now > contract.deadline then
                finish(contract)
                notifyCrew(contract.crewId, ('Contrat échoué : %s (délai dépassé).'):format(contract.title), 'error')
            end
        end
    end
end)

---------------------------------------------------------------------
-- Rappels (tablette et jeu)
---------------------------------------------------------------------

lib.callback.register('lunatic_illegal:contracts', function(src)
    if not HasCrewTablet(src) then
        return fail('Il vous faut une tablette de votre crew sur vous.')
    end

    local crew = CrewOf(src)
    local contract = active[crew.id]

    return {
        ok = true, offers = contract and {} or offersFor(crew), active = contract and view(contract) or nil,
        canLead = canLead(crew), minRank = Config.ContractMinRank, renewIn = math.max(0, Config.ContractRotation - (os.time() - (offers[crew.id] and offers[crew.id].at or os.time()))),
    }
end)

-- Contrat en cours du crew (connexion, redémarrage de la resource)
lib.callback.register('lunatic_illegal:contractState', function(src)
    local crew = CrewOf(src)
    local contract = crew and active[crew.id]
    return contract and view(contract) or nil
end)

lib.callback.register('lunatic_illegal:contractAccept', function(src, offerId)
    if not HasCrewTablet(src) then
        return fail('Il vous faut une tablette de votre crew sur vous.')
    end

    local crew = CrewOf(src)

    if not canLead(crew) then
        return fail("Seuls les rangs supérieurs du crew peuvent accepter un contrat.")
    end

    if active[crew.id] then
        return fail('Votre crew a déjà un contrat en cours.')
    end

    local offer, index

    for i, entry in ipairs(offersFor(crew)) do
        if entry.id == offerId then
            offer, index = entry, i
        end
    end

    local cfg = config()

    if not offer or not cfg then
        return fail("Ce contrat n'est plus disponible.")
    end

    local s = cfg.settings[offer.type]
    local xPlayer = ESX.GetPlayerFromId(src)
    local contract = {
        id = offer.id, crewId = crew.id, type = offer.type, title = offer.title, reward = offer.reward, xp = offer.xp,
        from = offer.from, to = offer.to, model = offer.model, deadline = os.time() + offer.duration * 60,
        alertChance = s.alertChance, loot = s.loot, acceptedBy = xPlayer and xPlayer.getName() or '?',
        stage = offer.type == 'delivery' and 'pickup' or offer.type == 'theft' and 'steal' or 'assault',
        guardsSettings = offer.type == 'cargo' and { count = s.guards, model = s.guardModel, weapon = s.guardWeapon } or nil,
    }

    -- Vol sur commande : le véhicule attend au point, portes fermées
    if offer.type == 'theft' then
        local vehicle = CreateVehicleServerSetter(joaat(offer.model), 'automobile', offer.from.x, offer.from.y, offer.from.z + 0.5, offer.from.h or 0.0)
        local timeout = GetGameTimer() + 5000

        while not DoesEntityExist(vehicle) and GetGameTimer() < timeout do
            Wait(50)
        end

        if not DoesEntityExist(vehicle) then
            return fail('Le véhicule ne peut pas apparaître (modèle invalide ?).')
        end

        -- 7 : fermé, mais on peut briser une vitre pour entrer (l'alarme se déclenche côté client)
        SetVehicleDoorsLocked(vehicle, 7)
        contract.vehicleNet = NetworkGetNetworkIdFromEntity(vehicle)
    end

    table.remove(offers[crew.id].list, index)
    active[crew.id] = contract
    broadcast(contract)
    notifyCrew(crew.id, ('Contrat accepté par %s : %s.'):format(contract.acceptedBy, contract.title), 'info')

    return { ok = true, contract = view(contract) }
end)

lib.callback.register('lunatic_illegal:contractAbandon', function(src)
    local crew = CrewOf(src)
    local contract = crew and active[crew.id]

    if not contract then
        return fail('Aucun contrat en cours.')
    end

    if not canLead(crew) then
        return fail("Seuls les rangs supérieurs du crew peuvent abandonner un contrat.")
    end

    finish(contract)
    notifyCrew(crew.id, ('Contrat abandonné : %s.'):format(contract.title), 'error')

    return { ok = true }
end)

-- Cargaison : le premier membre arrivé fait apparaître les gardes (une seule fois)
lib.callback.register('lunatic_illegal:contractGuards', function(src)
    local crew = CrewOf(src)
    local contract = crew and active[crew.id]

    if not contract or contract.type ~= 'cargo' or contract.guardsRequested or not near(src, contract.from, 200.0) then
        return nil
    end

    contract.guardsRequested = true
    return contract.guardsSettings
end)

RegisterNetEvent('lunatic_illegal:contractGuardsSpawned', function(netIds)
    local crew = CrewOf(source)
    local contract = crew and active[crew.id]

    if contract and contract.type == 'cargo' and type(netIds) == 'table' and not contract.guards then
        contract.guards = {}

        for index = 1, math.min(#netIds, 10) do
            contract.guards[#contract.guards + 1] = tonumber(netIds[index])
        end
    end
end)

local function guardsDown(contract)
    for _, netId in ipairs(contract.guards or {}) do
        local entity = NetworkGetEntityFromNetworkId(netId)

        if entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityHealth(entity) > 0 then
            return false
        end
    end

    return true
end

-- Étapes : chaque action est revérifiée (crew, étape, distance, objet, véhicule)
lib.callback.register('lunatic_illegal:contractAction', function(src, action)
    local crew = CrewOf(src)
    local contract = crew and active[crew.id]

    if not contract then
        return fail('Aucun contrat en cours.')
    end

    if action == 'pickup' and contract.stage == 'pickup' then
        if not near(src, contract.from, 5.0) then
            return fail('Vous êtes trop loin.')
        end

        if not ox:CanCarryItem(src, Config.ContractPackage, 1) then
            return fail("Vous n'avez pas assez de place pour le colis.")
        end

        ox:AddItem(src, Config.ContractPackage, 1, { contract = contract.id })
        contract.stage = 'deliver_package'
        alertPolice(contract, contract.from, 'Échange suspect')
        broadcast(contract)

        return { ok = true, message = ('Colis récupéré : livrez-le à %s.'):format(contract.to.label), waypoint = { x = contract.to.x, y = contract.to.y } }
    end

    if action == 'deliver' and contract.stage == 'deliver_package' then
        if not near(src, contract.to, 5.0) then
            return fail('Vous êtes trop loin.')
        end

        local carried

        for _, slot in pairs(ox:Search(src, 'slots', Config.ContractPackage) or {}) do
            if slot.metadata and slot.metadata.contract == contract.id then
                carried = slot
            end
        end

        if not carried then
            return fail("Vous n'avez pas le colis de ce contrat.")
        end

        ox:RemoveItem(src, Config.ContractPackage, 1, carried.metadata, carried.slot)
        complete(src, contract, 1)
        return { ok = true }
    end

    if action == 'entered' and contract.stage == 'steal' then
        local vehicle = GetVehiclePedIsIn(GetPlayerPed(src), false)

        if vehicle == 0 or NetworkGetNetworkIdFromEntity(vehicle) ~= contract.vehicleNet then
            return fail("Ce n'est pas le véhicule du contrat.")
        end

        contract.stage = 'deliver_vehicle'
        alertPolice(contract, GetEntityCoords(vehicle), 'Vol de véhicule')
        broadcast(contract)

        return { ok = true, message = ('Véhicule volé : amenez-le à %s.'):format(contract.to.label), waypoint = { x = contract.to.x, y = contract.to.y } }
    end

    if action == 'deliver' and contract.stage == 'deliver_vehicle' then
        local vehicle = GetVehiclePedIsIn(GetPlayerPed(src), false)

        if vehicle == 0 or NetworkGetNetworkIdFromEntity(vehicle) ~= contract.vehicleNet then
            return fail("Ce n'est pas le véhicule du contrat.")
        end

        if #(GetEntityCoords(vehicle) - vector3(contract.to.x, contract.to.y, contract.to.z)) > 10.0 then
            return fail('Amenez le véhicule dans le garage.')
        end

        -- Récompense selon l'état : carrosserie et moteur (1000 = neuf)
        local health = (math.max(0, GetVehicleBodyHealth(vehicle)) + math.max(0, GetVehicleEngineHealth(vehicle))) / 2000
        complete(src, contract, math.max(0.3, math.min(1, health)))

        return { ok = true }
    end

    if action == 'open' and contract.stage == 'assault' then
        if not near(src, contract.from, 4.0) then
            return fail('Vous êtes trop loin.')
        end

        if not guardsDown(contract) then
            return fail('Des gardes sont encore debout.')
        end

        alertPolice(contract, contract.from, 'Coups de feu signalés')
        complete(src, contract, 1)
        return { ok = true }
    end

    return fail('Action impossible à cette étape.')
end)

---------------------------------------------------------------------
-- Exports (panel staff)
---------------------------------------------------------------------

exports('getActiveContracts', function()
    local list = {}

    for crewId, contract in pairs(active) do
        local data = view(contract)
        data.crewId = crewId
        local found, crew = pcall(function() return admin:getCrewView(crewId) end)
        data.crew = found and crew and crew.label or ('Crew %d'):format(crewId)
        list[#list + 1] = data
    end

    return list
end)

exports('cancelContract', function(crewId)
    local contract = active[tonumber(crewId) or -1]

    if not contract then
        return false
    end

    finish(contract)
    notifyCrew(contract.crewId, ('Contrat annulé par le staff : %s.'):format(contract.title), 'error')
    return true
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    for _, contract in pairs(active) do
        deleteNet(contract.vehicleNet)

        for _, netId in ipairs(contract.guards or {}) do
            deleteNet(netId)
        end
    end
end)
