-- Carburant côté client (réglages : tuile Fonctionnalités → Gameplay → Carburant).
-- Le conducteur consomme selon le régime moteur et la classe du véhicule ; niveau partagé par le statebag « fuel »
-- du véhicule. À une pompe des stations-service : [E] ouvre la pompe (volume et prix en direct, moyen de paiement,
-- Valider puis Stop) ; le serveur mesure le plein et ne fait payer que les litres versés.

local pumpHashes = {}

for _, model in ipairs(Config.FuelPumpModels) do
    pumpHashes[#pumpHashes + 1] = joaat(model)
end

local function settings()
    return FeaturesOf('fuel')
end

local function fuelOf(vehicle)
    local level = Entity(vehicle).state.fuel

    if level == nil then
        level = tonumber(settings().startLevel) or 60.0
        Entity(vehicle).state:set('fuel', level, true)
    end

    return level
end

local function setFuel(vehicle, level)
    level = math.max(0.0, math.min(100.0, level + 0.0))
    Entity(vehicle).state:set('fuel', level, true)
    SetVehicleFuelLevel(vehicle, level)
end

exports('getFuel', function(vehicle)
    return fuelOf(vehicle)
end)

exports('setFuel', setFuel)

-- Consommation : chaque seconde, pour le conducteur
CreateThread(function()
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local s = settings()

        if s.enabled ~= false and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            local level = fuelOf(vehicle)
            local usage = Config.FuelClassUsage[GetVehicleClass(vehicle)] or 1.0

            if GetIsVehicleEngineRunning(vehicle) and usage > 0 then
                -- Environ 1,5 % par minute au ralenti, jusqu'à ~12 % par minute à fond (consommation 1,0)
                local rpm = GetVehicleCurrentRpm(vehicle)
                local perSecond = (0.025 + rpm * rpm * 0.18) * usage * (tonumber(s.consumption) or 1.0)
                level = level - perSecond
                setFuel(vehicle, level)
            else
                SetVehicleFuelLevel(vehicle, level)
            end

            if level <= 0.0 then
                SetVehicleEngineOn(vehicle, false, true, true)
            end
        end

        Wait(wait)
    end
end)

-- Moteur coupé tant que le réservoir est vide (le joueur pourrait le relancer)
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 and settings().enabled ~= false and (Config.FuelClassUsage[GetVehicleClass(vehicle)] or 1.0) > 0 and (Entity(vehicle).state.fuel or 1.0) <= 0.0 then
            SetVehicleEngineOn(vehicle, false, true, true)
            DisableControlAction(0, 71, true) -- accélérer
            Wait(0)
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------------
-- Stations-service
---------------------------------------------------------------------

local function nearStation(coords)
    for _, station in ipairs(Config.FuelStations) do
        if #(coords - station) < Config.FuelStationRadius then
            return true
        end
    end

    return false
end

local function nearPump(coords)
    for _, hash in ipairs(pumpHashes) do
        local pump = GetClosestObjectOfType(coords.x, coords.y, coords.z, Config.FuelPumpDistance, hash, false, false, false)

        if pump ~= 0 then
            return pump
        end
    end
end

-- Véhicule le plus proche de la pompe (pas celui dans lequel on est assis)
local function vehicleNear(coords)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, Config.FuelVehicleDistance, 0, 70)
    return vehicle ~= 0 and vehicle or nil
end

local busy = false
local shown = false

local pumpVehicle = nil -- véhicule de la pompe ouverte
local pumping = nil     -- plein en cours : { vehicle, started, max, rate }

local function currency()
    return GlobalState.lunaticCurrency or '$'
end

local function closePump()
    pumpVehicle = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'fuelHide' })
    ClearPedTasks(PlayerPedId())
    busy = false
end

-- Fin du plein (Stop, réservoir plein, joueur trop loin) : le serveur fait payer les litres versés
local function stopPumping(reported)
    local current = pumping

    if not current then
        return
    end

    pumping = nil
    local result = lib.callback.await('lunatic_gameplay:refuelStop', false, reported)
    ClearPedTasks(PlayerPedId())

    if not result or not result.ok then
        Notify(result and result.error or 'Plein interrompu.', 'error')
        return SendNUIMessage({ action = 'fuelDone', liters = 0, cost = 0 })
    end

    if result.liters > 0 then
        Notify(('%d litres pour %d %s (%s).'):format(result.liters, result.cost, currency(), result.account == 'bank' and 'carte bancaire' or 'espèces'), 'success')
    end

    SendNUIMessage({ action = 'fuelDone', liters = result.liters, cost = result.cost })
end

-- Pompe ouverte : volume et prix à zéro, choix du paiement, Valider
local function refuel(vehicle)
    busy = true
    lib.hideTextUI()
    shown = false

    if 100.0 - fuelOf(vehicle) < 1 then
        busy = false
        return Notify('Le réservoir est déjà plein.', 'info')
    end

    local accounts = {}

    for _, account in ipairs(ESX.GetPlayerData().accounts or {}) do
        accounts[account.name] = account.money
    end

    pumpVehicle = vehicle
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'fuelOpen', price = tonumber(settings().price) or 3, level = math.floor(fuelOf(vehicle)), cash = accounts.money or 0, bank = accounts.bank or 0,
        currency = currency(), banner = (GlobalState.lunaticImages or {}).fuel_banner,
    })
end

RegisterNUICallback('fuelStart', function(data, cb)
    cb({})

    if not pumpVehicle or pumping then
        return
    end

    local result = lib.callback.await('lunatic_gameplay:refuelStart', false, VehToNet(pumpVehicle), data.account == 'bank' and 'bank' or 'money')

    if not result or not result.ok then
        Notify(result and result.error or 'Pompe indisponible.', 'error')
        return SendNUIMessage({ action = 'fuelError' })
    end

    pumping = { vehicle = pumpVehicle, started = GetGameTimer(), max = result.max, rate = result.rate }
    local current = pumping

    if pcall(lib.requestAnimDict, 'timetable@gardener@filling_can', 3000) then
        TaskPlayAnim(PlayerPedId(), 'timetable@gardener@filling_can', 'gar_ig_5_filling_can', 4.0, -4.0, -1, 1, 0.0, false, false, false)
    end

    SendNUIMessage({ action = 'fuelRunning', max = result.max, rate = result.rate, price = result.price, limited = result.limited })

    if result.limited then
        Notify(('La pompe s’arrêtera à %d litres : c’est ce que vous pouvez payer.'):format(result.max), 'info')
    end

    -- Arrêt automatique : réservoir plein (ou somme atteinte), véhicule parti
    CreateThread(function()
        while pumping == current do
            local liters = (GetGameTimer() - current.started) / 1000 * current.rate

            if liters >= current.max then
                stopPumping(current.max)
            elseif not DoesEntityExist(current.vehicle) or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(current.vehicle)) > Config.FuelVehicleDistance + 3.0 then
                stopPumping(nil)
            end

            Wait(100)
        end
    end)
end)

-- Stop : seulement les litres versés jusque-là
RegisterNUICallback('fuelStop', function(data, cb)
    cb({})
    stopPumping(tonumber(data.liters))
end)

RegisterNUICallback('fuelClose', function(_, cb)
    cb({})
    stopPumping(nil)
    closePump()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and pumpVehicle then
        SetNuiFocus(false, false)
    end
end)

CreateThread(function()
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        if not busy and settings().enabled ~= false and not IsPedInAnyVehicle(ped, false) and nearStation(coords) then
            wait = 250
            local pump = nearPump(coords)

            -- [E] à chaque pompe ; le plein demande un véhicule garé à côté
            if pump then
                wait = 0
                local vehicle = vehicleNear(coords)
                local label = vehicle and ('[E] Pompe à essence (réservoir %d %%)'):format(math.floor(fuelOf(vehicle))) or '[E] Pompe à essence'

                if shown ~= label then
                    shown = label
                    lib.showTextUI(label)
                end

                if IsControlJustReleased(0, 38) then
                    if vehicle then
                        refuel(vehicle)
                    else
                        Notify('Garez un véhicule à côté de la pompe pour faire le plein.', 'info')
                    end
                end
            elseif shown then
                shown = false
                lib.hideTextUI()
            end
        elseif shown then
            shown = false
            lib.hideTextUI()
        end

        Wait(wait)
    end
end)

-- Blips des stations : gérés par la tuile Blips du panel (lunatic_admin)
