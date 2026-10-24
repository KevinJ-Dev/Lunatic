-- Carburant côté serveur : paiement du plein, seulement près d'une station-service.

lib.callback.register('lunatic_gameplay:refuel', function(src, liters)
    local settings = FeaturesOf('fuel')
    local xPlayer = ESX.GetPlayerFromId(src)
    liters = math.floor(tonumber(liters) or 0)

    if settings.enabled == false or not xPlayer then
        return { ok = false, error = 'Le carburant est désactivé.' }
    end

    if liters < 1 or liters > 100 then
        return { ok = false, error = 'Quantité invalide.' }
    end

    local ped = GetPlayerPed(src)
    local coords = ped ~= 0 and GetEntityCoords(ped)
    local near = false

    for _, station in ipairs(Config.FuelStations) do
        if coords and #(coords - station) < Config.FuelStationRadius + 5.0 then
            near = true
        end
    end

    if not near then
        return { ok = false, error = "Vous n'êtes pas à une station-service." }
    end

    local cost = math.ceil(liters * (tonumber(settings.price) or 3))

    if cost > 0 then
        local cash = xPlayer.getAccount('money')

        if cash and cash.money >= cost then
            xPlayer.removeAccountMoney('money', cost, 'Carburant')
        else
            local bank = xPlayer.getAccount('bank')

            if not bank or bank.money < cost then
                return { ok = false, error = "Pas assez d'argent." }
            end

            xPlayer.removeAccountMoney('bank', cost, 'Carburant')
        end
    end

    return { ok = true, cost = cost }
end)
