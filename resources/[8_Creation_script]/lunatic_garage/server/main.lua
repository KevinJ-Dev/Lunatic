-- Garage public et fourrière : véhicules des joueurs (table owned_vehicles d'ESX) rangés, sortis et récupérés aux
-- emplacements des catégories « Garage public » et « Fourrière » de la tuile Catalogues (lunatic_admin, GlobalState.lunaticShops).
-- État d'un véhicule : rangé (stored = 1), dehors (stored = 0 et présent sur la carte) ou en fourrière (stored = 0 et
-- absent : détruit, disparu, serveur redémarré, ou mis en fourrière par le staff : lunatic_impound = 1).

MySQL.ready(function()
    MySQL.query.await('ALTER TABLE `owned_vehicles` ADD COLUMN IF NOT EXISTS `lunatic_impound` TINYINT NOT NULL DEFAULT 0')
end)

local busy = {}

-- Types acceptés par CreateVehicleServerSetter (donnés par le jeu du joueur, qui connaît le modèle)
local ENTITY_TYPES = { automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true }

local function fail(message)
    return { ok = false, error = message }
end

local function log(src, action, target, details)
    if GetResourceState('lunatic_admin') == 'started' then
        pcall(function() exports.lunatic_admin:log('vehicles', 'info', src, action, target, details) end)
    end
end

-- Plaque comparable : le jeu la complète à 8 caractères avec des espaces
local function plateKey(plate)
    if type(plate) ~= 'string' then
        return ''
    end

    return (plate:gsub('^%s+', ''):gsub('%s+$', ''):upper())
end

-- Modèle comparable (signé ou non selon la source)
local function modelKey(model)
    return math.floor(tonumber(model) or 0) % 4294967296
end

local function decode(raw)
    local ok, value = pcall(json.decode, raw or '')
    return ok and type(value) == 'table' and value or {}
end

local function isStored(row)
    return row.stored == true or tonumber(row.stored) == 1
end

-- Emplacement d'un garage de la tuile Catalogues, joueur à côté (et du bon job si le garage est réservé)
local function locationAt(src, slug, index, kind, distance)
    local shop

    for _, entry in ipairs(GlobalState.lunaticShops or {}) do
        if entry.slug == slug and entry.kind == kind then
            shop = entry
        end
    end

    local location = shop and shop.locations and shop.locations[tonumber(index) or -1]

    if not location then
        return nil, nil, nil, 'Garage introuvable.'
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local ped = GetPlayerPed(src)

    if not xPlayer or ped == 0 then
        return nil, nil, nil, 'Personnage non chargé.'
    end

    if #(GetEntityCoords(ped) - vector3(location.x, location.y, location.z)) > distance then
        return nil, nil, nil, 'Vous êtes trop loin.'
    end

    if shop.jobs and #shop.jobs > 0 then
        local allowed = false

        for _, job in ipairs(shop.jobs) do
            allowed = allowed or xPlayer.getJob().name == job
        end

        if not allowed then
            return nil, nil, nil, 'Garage réservé.'
        end
    end

    return shop, location, xPlayer
end

-- Sortie des véhicules : celle définie dans le panel, sinon 4 m devant l'emplacement (comme lunatic_business)
local function spawnOf(location)
    if location.spawn then
        return location.spawn
    end

    local heading = math.rad(location.h or 0.0)
    return { x = location.x - math.sin(heading) * 4.0, y = location.y + math.cos(heading) * 4.0, z = location.z + 0.5, h = location.h or 0.0 }
end

-- Véhicules présents sur la carte, par plaque
local function worldPlates()
    local list = {}

    for _, vehicle in ipairs(GetAllVehicles()) do
        list[plateKey(GetVehicleNumberPlateText(vehicle))] = vehicle
    end

    return list
end

-- Places : base de la config, ou celles du rang Premium (tuile Boutique) si plus nombreuses
local function slotsOf(src)
    local slots = Config.BaseSlots

    if GetResourceState('lunatic_admin') == 'started' then
        local ok, perks = pcall(function() return exports.lunatic_admin:getPremiumPerks(src) end)

        if ok and type(perks) == 'table' and tonumber(perks.garageSlots) then
            slots = math.max(slots, math.floor(tonumber(perks.garageSlots)))
        end
    end

    return slots
end

-- Frais de fourrière de la tuile Économie (lunatic_admin), par catégorie de véhicule. La catégorie vient du jeu du
-- joueur (classe du modèle), limitée à celles possibles pour le type du garage.
local FEE_CLASSES = { car = { car = true, bike = true, truck = true }, boat = { boat = true }, aircraft = { heli = true, plane = true } }
local FEE_DEFAULT = { car = 'car', boat = 'boat', aircraft = 'heli' }

local function feeOf(vehicleType, feeClass)
    local allowed = FEE_CLASSES[vehicleType] or FEE_CLASSES.car
    feeClass = allowed[feeClass] and feeClass or FEE_DEFAULT[vehicleType] or 'car'
    local fees = type(GlobalState.lunaticEconomy) == 'table' and GlobalState.lunaticEconomy.impound or {}
    return math.max(0, math.floor(tonumber(fees[feeClass]) or 0)), feeClass
end

local function storedCount(identifier)
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `owned_vehicles` WHERE `owner` = ? AND `stored` = 1', { identifier })) or 0
end

---------------------------------------------------------------------
-- Ouverture : véhicules du joueur pour ce type de garage, avec leur état
---------------------------------------------------------------------

-- Garage public : tous ses véhicules du type ; fourrière : seulement ceux à récupérer (staff = mis en fourrière par le staff)
lib.callback.register('lunatic_garage:open', function(src, slug, index, kind)
    kind = kind == 'impound' and 'impound' or 'garage'
    local shop, location, xPlayer, err = locationAt(src, slug, index, kind, Config.ActionDistance)

    if not shop then
        return fail(err)
    end

    local world = worldPlates()
    local vehicles = {}

    for _, row in ipairs(MySQL.query.await('SELECT `plate`, `vehicle`, `type`, `stored`, `lunatic_impound` FROM `owned_vehicles` WHERE `owner` = ?', { xPlayer.identifier }) or {}) do
        if (row.type or 'car') == (shop.vehicleType or 'car') then
            local props = decode(row.vehicle)
            local state = isStored(row) and 'stored' or world[plateKey(row.plate)] and 'out' or 'impound'

            if kind == 'garage' or state == 'impound' then
                vehicles[#vehicles + 1] = { plate = row.plate, model = tonumber(props.model) or 0, props = props, state = state, staff = tonumber(row.lunatic_impound) == 1 }
            end
        end
    end

    return {
        ok = true, kind = kind, label = shop.label, vehicleType = shop.vehicleType or 'car', vehicles = vehicles,
        slots = slotsOf(src), stored = storedCount(xPlayer.identifier), spawn = spawnOf(location),
        cash = xPlayer.getAccount('money').money, bank = xPlayer.getAccount('bank').money,
    }
end)

---------------------------------------------------------------------
-- Sortir : véhicule rangé posé à la sortie de l'emplacement (le jeu du joueur le met au volant et pose ses réglages)
---------------------------------------------------------------------

lib.callback.register('lunatic_garage:takeOut', function(src, slug, index, plate, entityType)
    if busy[src] then
        return fail('Patientez un instant.')
    end

    local shop, location, xPlayer, err = locationAt(src, slug, index, 'garage', Config.ActionDistance)

    if not shop then
        return fail(err)
    end

    local row = type(plate) == 'string' and MySQL.single.await('SELECT `plate`, `vehicle`, `type`, `stored` FROM `owned_vehicles` WHERE `owner` = ? AND `plate` = ?', { xPlayer.identifier, plate })

    if not row or not isStored(row) then
        return fail("Ce véhicule n'est pas au garage.")
    end

    if (row.type or 'car') ~= (shop.vehicleType or 'car') then
        return fail("Ce garage n'accueille pas ce type de véhicule.")
    end

    local props = decode(row.vehicle)

    if not tonumber(props.model) then
        return fail('Véhicule illisible : prévenez le staff.')
    end

    local spawn = spawnOf(location)
    local spawnCoords = vector3(spawn.x, spawn.y, spawn.z)

    for _, vehicle in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(vehicle) - spawnCoords) < 3.0 then
            return fail('La sortie est encombrée : dégagez-la puis réessayez.')
        end
    end

    busy[src] = true

    -- Marqué sorti avant d'apparaître : un double clic ne le sort pas deux fois
    local changed = MySQL.update.await('UPDATE `owned_vehicles` SET `stored` = 0, `lunatic_impound` = 0 WHERE `owner` = ? AND `plate` = ? AND `stored` = 1', { xPlayer.identifier, row.plate })

    if (tonumber(changed) or 0) == 0 then
        busy[src] = nil
        return fail("Ce véhicule n'est plus au garage.")
    end

    local vehicle = CreateVehicleServerSetter(math.floor(tonumber(props.model)), ENTITY_TYPES[entityType] and entityType or 'automobile', spawn.x, spawn.y, spawn.z, spawn.h or 0.0)
    local timeout = GetGameTimer() + 3000

    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        MySQL.update.await('UPDATE `owned_vehicles` SET `stored` = 1 WHERE `owner` = ? AND `plate` = ?', { xPlayer.identifier, row.plate })
        busy[src] = nil
        return fail("Le véhicule n'a pas pu sortir : il reste au garage.")
    end

    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(vehicle, row.plate)
    busy[src] = nil

    log(src, 'garage.out', row.plate, { garage = shop.label })
    return { ok = true, netId = NetworkGetNetworkIdFromEntity(vehicle), props = props, plate = row.plate }
end)

---------------------------------------------------------------------
-- Ranger : le conducteur range son propre véhicule, réglages compris (modifications, couleurs, dégâts, carburant)
---------------------------------------------------------------------

lib.callback.register('lunatic_garage:store', function(src, slug, index, netId, props)
    if busy[src] then
        return fail('Patientez un instant.')
    end

    local shop, _, xPlayer, err = locationAt(src, slug, index, 'garage', Config.StoreDistance)

    if not shop then
        return fail(err)
    end

    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return fail('Véhicule introuvable.')
    end

    if GetPedInVehicleSeat(vehicle, -1) ~= GetPlayerPed(src) then
        return fail('Prenez le volant pour ranger le véhicule.')
    end

    local plate = plateKey(GetVehicleNumberPlateText(vehicle))
    local row = MySQL.single.await('SELECT `plate`, `vehicle`, `type`, `stored` FROM `owned_vehicles` WHERE `owner` = ? AND UPPER(TRIM(`plate`)) = ?', { xPlayer.identifier, plate })

    if not row then
        return fail("Ce véhicule n'est pas à vous.")
    end

    if (row.type or 'car') ~= (shop.vehicleType or 'car') then
        return fail("Ce garage n'accueille pas ce type de véhicule.")
    end

    local slots = slotsOf(src)

    if storedCount(xPlayer.identifier) >= slots then
        return fail(('Garage plein (%d place%s) : sortez-en un pour ranger celui-ci.'):format(slots, slots > 1 and 's' or ''))
    end

    local saved = decode(row.vehicle)

    if modelKey(GetEntityModel(vehicle)) ~= modelKey(saved.model) then
        return fail("Ce véhicule n'est pas celui enregistré à cette plaque.")
    end

    -- Réglages lus par le jeu du joueur : gardés s'ils sont lisibles, modèle et plaque toujours ceux enregistrés
    if type(props) ~= 'table' or #json.encode(props) > 30000 then
        props = saved
    end

    props.model, props.plate = saved.model, row.plate

    busy[src] = true
    MySQL.update.await('UPDATE `owned_vehicles` SET `vehicle` = ?, `stored` = 1 WHERE `owner` = ? AND `plate` = ?', { json.encode(props), xPlayer.identifier, row.plate })
    DeleteEntity(vehicle)
    busy[src] = nil

    log(src, 'garage.store', row.plate, { garage = shop.label })
    return { ok = true, plate = row.plate }
end)

---------------------------------------------------------------------
-- Fourrière : véhicule absent de la carte récupéré contre les frais, posé à la sortie de la fourrière
---------------------------------------------------------------------

lib.callback.register('lunatic_garage:retrieve', function(src, slug, index, plate, entityType, feeClass, account)
    if busy[src] then
        return fail('Patientez un instant.')
    end

    local shop, location, xPlayer, err = locationAt(src, slug, index, 'impound', Config.ActionDistance)

    if not shop then
        return fail(err)
    end

    local row = type(plate) == 'string' and MySQL.single.await('SELECT `plate`, `vehicle`, `type`, `stored` FROM `owned_vehicles` WHERE `owner` = ? AND `plate` = ?', { xPlayer.identifier, plate })

    if not row or isStored(row) then
        return fail("Ce véhicule n'est pas en fourrière.")
    end

    if worldPlates()[plateKey(row.plate)] then
        return fail("Ce véhicule est encore sur la carte : il n'est pas en fourrière.")
    end

    if (row.type or 'car') ~= (shop.vehicleType or 'car') then
        return fail("Cette fourrière n'accueille pas ce type de véhicule.")
    end

    local props = decode(row.vehicle)

    if not tonumber(props.model) then
        return fail('Véhicule illisible : prévenez le staff.')
    end

    local fee = feeOf(shop.vehicleType or 'car', feeClass)
    account = account == 'bank' and 'bank' or 'money'

    if fee > 0 and xPlayer.getAccount(account).money < fee then
        return fail(account == 'bank' and 'Solde bancaire insuffisant.' or "Vous n'avez pas assez de liquide.")
    end

    local spawn = spawnOf(location)
    local spawnCoords = vector3(spawn.x, spawn.y, spawn.z)

    for _, vehicle in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(vehicle) - spawnCoords) < 3.0 then
            return fail('La sortie est encombrée : dégagez-la puis réessayez.')
        end
    end

    busy[src] = true

    if fee > 0 then
        xPlayer.removeAccountMoney(account, fee, ('Fourrière : %s'):format(row.plate))
    end

    local vehicle = CreateVehicleServerSetter(math.floor(tonumber(props.model)), ENTITY_TYPES[entityType] and entityType or 'automobile', spawn.x, spawn.y, spawn.z, spawn.h or 0.0)
    local timeout = GetGameTimer() + 3000

    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        if fee > 0 then
            xPlayer.addAccountMoney(account, fee, 'Remboursement fourrière')
        end

        busy[src] = nil
        return fail("Le véhicule n'a pas pu sortir. Vous avez été remboursé.")
    end

    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(vehicle, row.plate)
    MySQL.update.await('UPDATE `owned_vehicles` SET `lunatic_impound` = 0 WHERE `owner` = ? AND `plate` = ?', { xPlayer.identifier, row.plate })
    busy[src] = nil

    log(src, 'garage.impound_out', row.plate, { impound = shop.label, fee = fee, account = account })
    return { ok = true, netId = NetworkGetNetworkIdFromEntity(vehicle), props = props, plate = row.plate, fee = fee }
end)

-- Mise en fourrière par le staff (menu staff sur un véhicule, lunatic_admin) : véhicule retiré de la carte et, s'il
-- appartient à un joueur, marqué « mis en fourrière par le staff ». Renvoie { ok, owned = true s'il avait un propriétaire }.
exports('impoundVehicle', function(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return { ok = false }
    end

    local plate = plateKey(GetVehicleNumberPlateText(vehicle))
    local changed = plate ~= '' and MySQL.update.await('UPDATE `owned_vehicles` SET `stored` = 0, `lunatic_impound` = 1 WHERE UPPER(TRIM(`plate`)) = ?', { plate }) or 0
    DeleteEntity(vehicle)
    return { ok = true, owned = (tonumber(changed) or 0) > 0 }
end)

AddEventHandler('playerDropped', function()
    busy[source] = nil
end)
