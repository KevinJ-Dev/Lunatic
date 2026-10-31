-- Carburant côté serveur : plein à une pompe des stations-service (doc Vision « Pompe à essence »).
-- Le plein est mesuré ici : début (lunatic_gameplay:refuelStart), puis fin à Stop ou réservoir plein
-- (lunatic_gameplay:refuelStop). Les litres payés sont ceux que la pompe a pu verser pendant ce temps (Config.FuelRate),
-- jamais plus que demandé ni que ce que le joueur annonce ; le paiement se fait à la fin, le niveau est posé ici.

local sessions = {} -- joueur -> { started, max, price, account, vehicle, level }

local function nearStation(src)
    local ped = GetPlayerPed(src)
    local coords = ped ~= 0 and GetEntityCoords(ped)

    for _, station in ipairs(Config.FuelStations) do
        if coords and #(coords - station) < Config.FuelStationRadius + 5.0 then
            return true
        end
    end

    return false
end

lib.callback.register('lunatic_gameplay:refuelStart', function(src, netId, account)
    local settings = FeaturesOf('fuel')
    local xPlayer = ESX.GetPlayerFromId(src)

    if settings.enabled == false or not xPlayer then
        return { ok = false, error = 'Le carburant est désactivé.' }
    end

    if sessions[src] then
        return { ok = false, error = 'Un plein est déjà en cours.' }
    end

    if not nearStation(src) then
        return { ok = false, error = "Vous n'êtes pas à une station-service." }
    end

    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or #(GetEntityCoords(vehicle) - GetEntityCoords(GetPlayerPed(src))) > Config.FuelVehicleDistance + 4.0 then
        return { ok = false, error = 'Garez le véhicule à côté de la pompe.' }
    end

    local level = tonumber(Entity(vehicle).state.fuel) or tonumber(settings.startLevel) or 60.0
    local missing = math.floor(100.0 - level)

    if missing < 1 then
        return { ok = false, error = 'Le réservoir est déjà plein.' }
    end

    account = account == 'bank' and 'bank' or 'money'
    local price = tonumber(settings.price) or 3
    local balance = xPlayer.getAccount(account)
    local max = missing

    -- Pas de quoi faire le plein : la pompe s'arrête à ce que le joueur peut payer
    if price > 0 then
        max = math.min(missing, math.floor((balance and balance.money or 0) / price))
    end

    if max < 1 then
        return { ok = false, error = account == 'bank' and 'Solde bancaire insuffisant.' or "Vous n'avez pas assez de liquide." }
    end

    sessions[src] = { started = GetGameTimer(), max = max, price = price, account = account, vehicle = vehicle, level = level }
    return { ok = true, max = max, rate = Config.FuelRate, price = price, limited = max < missing }
end)

-- Fin du plein : reported = litres affichés chez le joueur (au plus ce que la pompe a pu verser)
lib.callback.register('lunatic_gameplay:refuelStop', function(src, reported)
    local session = sessions[src]
    sessions[src] = nil

    if not session then
        return { ok = false, error = 'Aucun plein en cours.' }
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local elapsed = (GetGameTimer() - session.started) / 1000
    local liters = math.min(session.max, math.floor(elapsed * Config.FuelRate + 0.5))

    if tonumber(reported) then
        liters = math.min(liters, math.max(0, math.floor(tonumber(reported))))
    end

    if liters < 1 or not xPlayer then
        return { ok = true, liters = 0, cost = 0 }
    end

    local cost = math.ceil(liters * session.price)
    local balance = xPlayer.getAccount(session.account)

    -- Argent dépensé entre-temps : seulement les litres payables
    if session.price > 0 and balance and balance.money < cost then
        liters = math.floor(balance.money / session.price)
        cost = math.ceil(liters * session.price)
    end

    if cost > 0 then
        xPlayer.removeAccountMoney(session.account, cost, 'Carburant')
    end

    if DoesEntityExist(session.vehicle) then
        local level = tonumber(Entity(session.vehicle).state.fuel) or session.level
        Entity(session.vehicle).state:set('fuel', math.min(100.0, level + liters), true)
    end

    return { ok = true, liters = liters, cost = cost, account = session.account }
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
end)

-- Stations-service (config), pour d'autres scripts : livraisons du pompiste d'intérim (lunatic_interim)
exports('getFuelStations', function()
    return Config.FuelStations
end)
