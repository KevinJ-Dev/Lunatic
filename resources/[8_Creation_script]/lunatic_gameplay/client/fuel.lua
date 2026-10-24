-- Carburant côté client (réglages : tuile Fonctionnalités → Gameplay → Carburant).
-- Le conducteur consomme selon le régime moteur et la classe du véhicule ; niveau partagé par le statebag « fuel »
-- du véhicule. À une pompe des stations-service : [E] Faire le plein (payé et vérifié par le serveur).

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

local function refuel(vehicle)
    busy = true
    lib.hideTextUI()
    shown = false

    local s = settings()
    local level = fuelOf(vehicle)
    local missing = math.floor(100.0 - level)

    if missing < 1 then
        busy = false
        return Notify('Le réservoir est déjà plein.', 'info')
    end

    local price = tonumber(s.price) or 3
    local input = lib.inputDialog('Faire le plein', {
        { type = 'slider', label = ('Litres (%s %s le litre)'):format(price, GlobalState.lunaticCurrency or '$'), min = 1, max = missing, default = missing, step = 1 },
    })

    if not input or not input[1] then
        busy = false
        return
    end

    local liters = math.floor(input[1])
    local result = lib.callback.await('lunatic_gameplay:refuel', false, liters)

    if not result or not result.ok then
        busy = false
        return Notify(result and result.error or 'Paiement refusé.', 'error')
    end

    local done = lib.progressBar({
        duration = math.max(2000, liters * 120), label = 'Plein en cours…', canCancel = false,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'timetable@gardener@filling_can', clip = 'gar_ig_5_filling_can' },
    })

    if done and DoesEntityExist(vehicle) then
        setFuel(vehicle, fuelOf(vehicle) + liters)
        Notify(('%d litres ajoutés (%s %s).'):format(liters, result.cost, GlobalState.lunaticCurrency or '$'), 'success')
    end

    busy = false
end

CreateThread(function()
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        if not busy and settings().enabled ~= false and not IsPedInAnyVehicle(ped, false) and nearStation(coords) then
            wait = 250
            local pump = nearPump(coords)
            local vehicle = pump and vehicleNear(coords)

            if vehicle then
                wait = 0

                if not shown then
                    shown = true
                    lib.showTextUI(('[E] Faire le plein (%d %%)'):format(math.floor(fuelOf(vehicle))))
                end

                if IsControlJustReleased(0, 38) then
                    refuel(vehicle)
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
