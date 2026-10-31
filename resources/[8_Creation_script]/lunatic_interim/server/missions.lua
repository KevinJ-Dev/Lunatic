-- Tournées d'intérim côté serveur : Livreur, Facteur, Éboueur, Pompiste, Pilote, Canadair. Au dépôt, le joueur lance la
-- tournée : le véhicule de service sort (avec sa remorque pour le pompiste) et les arrêts tirés par son client sont
-- vérifiés selon le métier (routes au hasard, stations-service, aérodromes). Chaque arrêt est validé sur place (position,
-- temps minimum, véhicule pas loin) ; au retour au dépôt avec le véhicule, la paie part sur son compte bancaire.
-- Véhicule détruit, métier d'intérim changé ou déconnexion : la tournée s'arrête, sans paie.
-- Récoltes (Mineur, Pêcheur, Chasseur) : quota à récolter dans la zone autour du dépôt, compté ici (pas d'objet
-- d'inventaire), puis paie au dépôt. Chaque récolte est contrôlée : zone, temps minimum, gibier vraiment abattu.

local missions = {} -- joueur -> tournée { job, label, task, vehicle, trailer, stops, index, last, salary, depot } ou récolte { gather = true, count, quota… }

local function fail(message)
    return { ok = false, error = message }
end

local function log(src, action, target, details)
    pcall(function() exports.lunatic_admin:log('companies', 'info', src, action, target, details) end)
end

local function vec(point)
    return vector3(point.x, point.y, point.z)
end

local function flat(a, b)
    return #(vector2(a.x, a.y) - vector2(b.x, b.y))
end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetEntityCoords(ped) or nil
end

-- Fin de mission : véhicule, remorque et gibier encore en vie retirés
local function deleteVehicle(mission)
    for _, entity in ipairs({ mission and mission.vehicle, mission and mission.trailer }) do
        if entity and DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end

    -- Rame (tramway, train) : motrice et voitures
    for _, car in ipairs(mission and mission.cars or {}) do
        if DoesEntityExist(car) then
            DeleteEntity(car)
        end
    end

    for netId in pairs(mission and mission.animals or {}) do
        local animal = NetworkGetEntityFromNetworkId(netId)

        if animal ~= 0 and DoesEntityExist(animal) then
            DeleteEntity(animal)
        end
    end
end

---------------------------------------------------------------------
-- Chasseur : fusil prêté (objets marqués « interim »), repris à la fin ; il ne blesse que les animaux
---------------------------------------------------------------------

local function ox()
    return GetResourceState('ox_inventory') == 'started' and exports.ox_inventory or nil
end

local function lendWeapon(src)
    local inventory, gear = ox(), Config.HuntWeapon

    if not inventory then
        return false
    end

    if not inventory:CanCarryItem(src, gear.weapon, 1) or not inventory:AddItem(src, gear.weapon, 1, { interim = true }) then
        return false
    end

    inventory:AddItem(src, gear.ammo, gear.count, { interim = true })
    return true
end

-- Aussi appelé à la connexion (server/main.lua) : fusil resté après une déconnexion en pleine chasse
function ReturnHuntWeapon(src)
    local inventory, gear = ox(), Config.HuntWeapon

    if not inventory then
        return
    end

    for _, name in ipairs({ gear.weapon, gear.ammo }) do
        local count = inventory:Search(src, 'count', name, { interim = true }) or 0

        if count > 0 then
            inventory:RemoveItem(src, name, count, { interim = true })
        end
    end
end

local function isPlayerPed(entity)
    for _, id in ipairs(GetPlayers()) do
        if GetPlayerPed(id) == entity then
            return true
        end
    end

    return false
end

-- Tir du fusil prêté sur un joueur : dégâts annulés
AddEventHandler('weaponDamageEvent', function(sender, data)
    local mission = missions[tonumber(sender)]

    if not mission or mission.task ~= 'hunt' or data.weaponType ~= joaat(Config.HuntWeapon.weapon) then
        return
    end

    local targets = type(data.hitGlobalIds) == 'table' and data.hitGlobalIds or { data.hitGlobalId }

    for _, netId in ipairs(targets) do
        local entity = netId and NetworkGetEntityFromNetworkId(netId) or 0

        if entity ~= 0 and isPlayerPed(entity) then
            CancelEvent()
            return
        end
    end
end)

-- Le fusil et ses munitions prêtés ne quittent pas l'inventaire du chasseur (ni donnés, ni jetés, ni rangés)
CreateThread(function()
    while GetResourceState('ox_inventory') ~= 'started' do
        Wait(1000)
    end

    local gear = Config.HuntWeapon
    exports.ox_inventory:registerHook('swapItems', function(payload)
        local slot = payload.fromSlot

        if type(slot) == 'table' and type(slot.metadata) == 'table' and slot.metadata.interim and payload.fromInventory ~= payload.toInventory then
            return false
        end

        return true
    end, { itemFilter = { [gear.weapon] = true, [gear.ammo] = true } })
end)

local function stop(src, message, kind)
    local mission = missions[src]

    if not mission then
        return
    end

    if mission.rail then
        TriggerClientEvent('lunatic_interim:railEnded', src)
    end

    if mission.task == 'hunt' then
        ReturnHuntWeapon(src)
    end

    deleteVehicle(mission)
    missions[src] = nil
    TriggerClientEvent('lunatic_interim:missionEnded', src, message, kind)
end

-- Lieux fixes d'un métier : stations-service (lunatic_gameplay) ou aérodromes (config)
local function fixedPlaces(task)
    if task == 'flight' then
        return Config.Airports
    end

    if task == 'fuel' and GetResourceState('lunatic_gameplay') == 'started' then
        local ok, stations = pcall(function() return exports.lunatic_gameplay:getFuelStations() end)
        return ok and stations or nil
    end
end

local function nearPlace(point, places, radius)
    for _, place in ipairs(places or {}) do
        if flat(point, place) <= radius then
            return true
        end
    end

    return false
end

-- Arrêts proposés par le client : nombre, carte, lieux fixes ou distances au dépôt, et espacement (avec un peu de marge)
local function cleanStops(list, settings, task)
    if type(list) ~= 'table' or #list ~= settings.stops then
        return nil
    end

    local rules, depot, stops = TaskSettings(task), settings.depot, {}
    local places = fixedPlaces(task)

    if (task == 'fuel' or task == 'flight') and not places then
        return nil
    end

    for _, point in ipairs(list) do
        local x, y, z = type(point) == 'table' and tonumber(point.x), type(point) == 'table' and tonumber(point.y), type(point) == 'table' and tonumber(point.z)

        if not x or not y or not z or x < -4500 or x > 4500 or y < -4500 or y > 8500 then
            return nil
        end

        local here = vector3(x, y, z)
        local distance = flat(here, depot)

        if places then
            if not nearPlace(here, places, 80.0) or distance < (task == 'flight' and rules.minDistance * 0.8 or 150.0) then
                return nil
            end
        elseif distance < rules.minDistance * 0.8 or distance > rules.maxDistance * 1.2 then
            return nil
        end

        -- Escales : deux de suite au même endroit interdites ; ailleurs, arrêts espacés
        local previous = stops[#stops]

        if task == 'flight' then
            if previous and flat(here, previous) < 500.0 then
                return nil
            end
        else
            for _, other in ipairs(stops) do
                if flat(here, other) < rules.gap * 0.8 then
                    return nil
                end
            end
        end

        stops[#stops + 1] = here
    end

    return stops
end

local function spawnVehicle(model, vtype, spot)
    local vehicle = CreateVehicleServerSetter(joaat(model), vtype or 'automobile', spot.x, spot.y, spot.z, spot.h or 0.0)
    local timeout = GetGameTimer() + 3000

    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < timeout do
        Wait(0)
    end

    return vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) and vehicle or nil
end

lib.callback.register('lunatic_interim:missionStart', function(src, list)
    local xPlayer = ESX.GetPlayerFromId(src)
    local job = xPlayer and InterimOf(src)
    local settings = job and JobSettings(job.id)
    local coords = pedCoords(src)

    if not job or job.kind ~= 'route' then
        return fail("Votre métier n'a pas de tournée.")
    elseif not settings.enabled then
        return fail('Ce métier est fermé pour le moment.')
    elseif not settings.depot or not settings.spawn or not settings.vehicle then
        return fail('Dépôt pas encore réglé : prévenez le staff.')
    elseif missions[src] then
        return fail('Vous avez déjà une tournée en cours.')
    elseif not coords or #(coords - vec(settings.depot)) > 6.0 then
        return fail('Rendez-vous au dépôt.')
    end

    local stops = cleanStops(list, settings, job.task)

    if not stops then
        return fail('Tournée invalide, réessayez.')
    end

    local spawn = settings.spawn

    for _, vehicle in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(vehicle) - vec(spawn)) < (job.vtype == 'plane' and 8.0 or 3.0) then
            return fail('La sortie du dépôt est encombrée : dégagez-la puis réessayez.')
        end
    end

    local vehicle = spawnVehicle(settings.vehicle, job.vtype, spawn)

    if not vehicle then
        return fail(("Le véhicule n'a pas pu sortir (modèle %s introuvable ?)."):format(settings.vehicle))
    end

    -- Pompiste : citerne derrière le camion (le client l'attelle)
    local trailer = nil

    if job.trailer then
        local h = math.rad(spawn.h or 0.0)
        trailer = spawnVehicle(job.trailer, 'trailer', { x = spawn.x + math.sin(h) * 10.0, y = spawn.y - math.cos(h) * 10.0, z = spawn.z, h = spawn.h })

        if not trailer then
            DeleteEntity(vehicle)
            return fail(("La remorque n'a pas pu sortir (modèle %s introuvable ?)."):format(job.trailer))
        end

        SetEntityRoutingBucket(trailer, GetPlayerRoutingBucket(src))
    end

    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(vehicle, ('INT%05d'):format(math.random(0, 99999)))
    TaskWarpPedIntoVehicle(GetPlayerPed(src), vehicle, -1)

    missions[src] = {
        job = job.id, label = job.label, task = job.task, vehicle = vehicle, trailer = trailer, stops = stops, index = 1, last = os.time(),
        salary = settings.salary, depot = vec(settings.depot),
    }

    return {
        ok = true, netId = NetworkGetNetworkIdFromEntity(vehicle), trailerNetId = trailer and NetworkGetNetworkIdFromEntity(trailer) or nil,
        task = job.task, stops = stops, bags = Config.Route.garbageBags,
    }
end)

-- Arrêt fait : le joueur est sur place, assez de temps depuis l'arrêt d'avant, véhicule (et citerne) pas loin
lib.callback.register('lunatic_interim:missionStop', function(src, index)
    local mission = missions[src]
    local coords = pedCoords(src)

    if not mission or not mission.stops or tonumber(index) ~= mission.index or not mission.stops[mission.index] then
        return fail('Arrêt introuvable.')
    elseif not mission.rail and not DoesEntityExist(mission.vehicle) then
        stop(src, 'Le véhicule de service a disparu : tournée arrêtée.', 'error')
        return fail('Véhicule disparu.')
    end

    local rules = TaskSettings(mission.task)
    local target = mission.stops[mission.index]

    if not coords or #(coords - target) > rules.reach then
        return fail("Vous n'êtes pas à l'arrêt.")
    elseif os.time() - mission.last < rules.stopSeconds then
        return fail('Trop rapide : prenez le temps de faire le travail.')
    elseif not mission.rail and #(GetEntityCoords(mission.vehicle) - coords) > 60.0 then
        return fail('Le véhicule de service est trop loin.')
    elseif mission.rail and not InRailCab(src) then
        return fail('Validez la gare depuis la cabine.')
    elseif mission.trailer and (not DoesEntityExist(mission.trailer) or #(GetEntityCoords(mission.trailer) - target) > rules.reach) then
        return fail('Amenez la citerne jusqu\u{2019}à la station.')
    end

    mission.index = mission.index + 1
    mission.last = os.time()
    return { ok = true, index = mission.index, done = mission.index > #mission.stops }
end)

-- Retour au dépôt avec le véhicule, tous les arrêts faits : paie sur le compte bancaire
lib.callback.register('lunatic_interim:missionFinish', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    local mission = missions[src]
    local coords = pedCoords(src)
    local rules = mission and TaskSettings(mission.task)

    if not xPlayer or not mission then
        return fail("Vous n'avez pas de tournée en cours.")
    elseif mission.gather then
        if mission.count < mission.quota then
            return fail(('Récolte pas finie : %d / %d.'):format(mission.count, mission.quota))
        elseif not coords or #(coords - mission.depot) > rules.finish then
            return fail('Rendez-vous au dépôt.')
        end
    elseif mission.rail then
        -- Rame : fin à la dernière gare (ou au départ)
        local last = mission.stops[#mission.stops]

        if mission.index <= #mission.stops then
            return fail(('Service pas fini : %d / %d gares.'):format(mission.index - 1, #mission.stops))
        elseif not coords or (#(coords - last) > rules.finish and #(coords - mission.depot) > rules.finish) then
            return fail('Terminez le service en gare.')
        end
    elseif mission.index <= #mission.stops then
        return fail(('Tournée pas finie : %d / %d arrêts.'):format(mission.index - 1, #mission.stops))
    elseif not coords or #(coords - mission.depot) > rules.finish then
        return fail('Rendez-vous au dépôt.')
    elseif not DoesEntityExist(mission.vehicle) or #(GetEntityCoords(mission.vehicle) - mission.depot) > rules.finish + 30.0 then
        return fail('Ramenez le véhicule de service au dépôt.')
    end

    deleteVehicle(mission)
    missions[src] = nil

    if mission.task == 'hunt' then
        ReturnHuntWeapon(src)
    end

    if mission.salary > 0 then
        xPlayer.addAccountMoney('bank', mission.salary, ("Mission d'intérim : %s"):format(mission.label))
    end

    log(src, 'interim.mission', mission.label, { salary = mission.salary, stops = mission.gather and mission.quota or #mission.stops })
    TriggerClientEvent('lunatic_interim:railEnded', src)
    return { ok = true, salary = mission.salary }
end)

---------------------------------------------------------------------
-- Récoltes : Mineur (rochers), Pêcheur (au bord de l'eau), Chasseur (gibier)
---------------------------------------------------------------------

lib.callback.register('lunatic_interim:gatherStart', function(src)
    local job = InterimOf(src)
    local settings = job and JobSettings(job.id)
    local coords = pedCoords(src)

    if not job or job.kind ~= 'gather' then
        return fail("Votre métier n'a pas de récolte.")
    elseif not settings.enabled then
        return fail('Ce métier est fermé pour le moment.')
    elseif not settings.depot then
        return fail('Dépôt pas encore réglé : prévenez le staff.')
    elseif missions[src] then
        return fail('Vous avez déjà une mission en cours.')
    elseif not coords or #(coords - vec(settings.depot)) > 6.0 then
        return fail('Rendez-vous au dépôt.')
    end

    if job.task == 'hunt' and not lendWeapon(src) then
        return fail("Impossible de vous prêter le fusil (inventaire plein ?).")
    end

    local rules = TaskSettings(job.task)
    missions[src] = {
        gather = true, job = job.id, label = job.label, task = job.task, count = 0, quota = settings.stops, last = os.time(),
        salary = settings.salary, depot = vec(settings.depot), animals = {},
    }

    return { ok = true, task = job.task, quota = settings.stops, radius = rules.radius, depot = settings.depot, rocks = rules.rocks, animals = rules.animals }
end)

-- Chasseur : gibier apparu par le client, enregistré pour être reconnu (et retiré à la fin)
RegisterNetEvent('lunatic_interim:animal', function(netId)
    local mission = missions[source]
    netId = tonumber(netId)

    if mission and mission.gather and mission.task == 'hunt' and netId then
        local count = 0

        for _ in pairs(mission.animals) do
            count = count + 1
        end

        if count < 12 then
            mission.animals[netId] = true
        end
    end
end)

lib.callback.register('lunatic_interim:gather', function(src, netId)
    local mission = missions[src]
    local coords = pedCoords(src)

    if not mission or not mission.gather then
        return fail("Vous n'avez pas de récolte en cours.")
    elseif mission.count >= mission.quota then
        return fail('Quota atteint : retournez au dépôt.')
    end

    local rules = TaskSettings(mission.task)

    if not coords or #(coords - mission.depot) > rules.radius + 20.0 then
        return fail('Vous êtes sorti de la zone de travail.')
    elseif os.time() - mission.last < rules.gatherSeconds then
        return fail('Trop rapide : prenez le temps de faire le travail.')
    end

    -- Chasseur : un animal de sa chasse, abattu, juste à côté
    if mission.task == 'hunt' then
        netId = tonumber(netId)
        local animal = netId and mission.animals[netId] and NetworkGetEntityFromNetworkId(netId) or 0

        if animal == 0 or not DoesEntityExist(animal) or GetEntityType(animal) ~= 1 then
            return fail('Animal introuvable.')
        elseif GetEntityHealth(animal) > 0 then
            return fail("L\u{2019}animal n\u{2019}est pas abattu.")
        elseif #(GetEntityCoords(animal) - coords) > 5.0 then
            return fail('Approchez-vous de l\u{2019}animal.')
        end

        mission.animals[netId] = nil
        DeleteEntity(animal)
    end

    mission.count = mission.count + 1
    mission.last = os.time()
    return { ok = true, count = mission.count, quota = mission.quota, done = mission.count >= mission.quota }
end)

---------------------------------------------------------------------
-- Tramway et train : la rame est créée par le client (le serveur ne peut pas en créer) ; gares du panel, dans l'ordre
---------------------------------------------------------------------

local RAIL_MODELS = {}

for _, model in ipairs(Config.TrainModels) do
    RAIL_MODELS[joaat(model)] = true
end

-- Le joueur est dans une rame (modèle de train connu)
function InRailCab(src)
    local vehicle = GetVehiclePedIsIn(GetPlayerPed(src), false)
    return vehicle ~= 0 and RAIL_MODELS[GetEntityModel(vehicle)] == true
end

lib.callback.register('lunatic_interim:railStart', function(src)
    local job = InterimOf(src)
    local settings = job and JobSettings(job.id)
    local coords = pedCoords(src)

    if not job or job.kind ~= 'rail' then
        return fail("Votre métier n'est pas un métier du rail.")
    elseif not settings.enabled then
        return fail('Ce métier est fermé pour le moment.')
    elseif not settings.depot or #settings.stations < 1 then
        return fail('Départ ou gares pas encore réglés : prévenez le staff.')
    elseif missions[src] then
        return fail('Vous avez déjà une mission en cours.')
    elseif not coords or #(coords - vec(settings.depot)) > 8.0 then
        return fail('Rendez-vous au point de départ.')
    end

    -- Gares dans l'ordre de la ligne, autant que demandé (dans la limite de celles placées)
    local stops = {}

    for index = 1, math.min(settings.stops, #settings.stations) do
        stops[index] = vec(settings.stations[index])
    end

    missions[src] = {
        rail = true, job = job.id, label = job.label, task = job.task, stops = stops, index = 1, last = os.time(),
        salary = settings.salary, depot = vec(settings.depot),
    }

    return { ok = true, task = job.task, stops = stops, depot = settings.depot, variation = job.variation, maxSpeed = job.maxSpeed, direction = job.direction ~= false }
end)

-- Voitures de la rame créée par le client : retirées à la fin (ou à la déconnexion)
RegisterNetEvent('lunatic_interim:railCars', function(netIds)
    local src = source
    local mission = missions[src]

    if not mission or not mission.rail or mission.cars or type(netIds) ~= 'table' then
        return
    end

    mission.cars = {}

    for index, netId in ipairs(netIds) do
        local car = index <= 30 and tonumber(netId) and NetworkGetEntityFromNetworkId(netId) or 0

        if car ~= 0 and DoesEntityExist(car) and RAIL_MODELS[GetEntityModel(car)] then
            mission.cars[#mission.cars + 1] = car
        end
    end
end)

lib.callback.register('lunatic_interim:missionCancel', function(src)
    if not missions[src] then
        return fail("Vous n'avez pas de tournée en cours.")
    end

    stop(src, nil)
    return { ok = true }
end)

-- Véhicule détruit ou supprimé : tournée arrêtée
CreateThread(function()
    while true do
        Wait(5000)

        for src, mission in pairs(missions) do
            if not mission.gather and not mission.rail and (not DoesEntityExist(mission.vehicle) or GetVehicleEngineHealth(mission.vehicle) <= 0) then
                stop(src, 'Le véhicule de service est hors d\u{2019}usage : tournée arrêtée, sans paie.', 'error')
            end
        end
    end
end)

-- Métier d'intérim quitté ou changé en cours de tournée
AddEventHandler('lunatic_interim:changed', function(src, id)
    local mission = missions[src]

    if mission and id ~= mission.job then
        stop(src, 'Vous avez changé de métier d\u{2019}intérim : tournée arrêtée.', 'info')
    end
end)

AddEventHandler('playerDropped', function()
    local mission = missions[source]
    deleteVehicle(mission)
    missions[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, mission in pairs(missions) do
            deleteVehicle(mission)
        end
    end
end)
