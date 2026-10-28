-- Menu véhicule des joueurs dans le menu contextuel (ressource ContextMenu : Alt gauche maintenu + clic droit sur un
-- véhicule proche, ou n'importe où depuis l'intérieur de son véhicule) : état du véhicule, conduite automatique vers le
-- point GPS (conducteur seulement), portes et vitres. Le staff garde son propre menu (lunatic_admin) à côté.

local RESOURCE = 'ContextMenu'
local REACH = 5.0 -- distance maximale au véhicule cliqué de l'extérieur
local DOORS = { { 4, 'Capot' }, { 5, 'Coffre' }, { 0, 'Avant gauche' }, { 1, 'Avant droite' }, { 2, 'Arrière gauche' }, { 3, 'Arrière droite' } }
local WINDOWS = { { 0, 'Avant gauche' }, { 1, 'Avant droite' }, { 2, 'Arrière gauche' }, { 3, 'Arrière droite' } }
local NO_WINDOWS = { [8] = true, [13] = true, [14] = true } -- motos, vélos, bateaux

local windowsDown = {} -- véhicule -> { [vitre] = true }
local autopilot = nil  -- conduite automatique en cours : { vehicle }

local function isDriver(vehicle)
    return GetPedInVehicleSeat(vehicle, -1) == PlayerPedId()
end

local function vehicleLabel(vehicle)
    local display = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local label = GetLabelText(display)
    return label ~= 'NULL' and label or display
end

-- Contrôle réseau du véhicule (portes, vitres) : demandé au jeu qui le commande, une seconde au plus
local function control(vehicle)
    local limit = GetGameTimer() + 1000

    while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < limit do
        NetworkRequestControlOfEntity(vehicle)
        Wait(50)
    end

    if not NetworkHasControlOfEntity(vehicle) then
        Notify('Impossible : un autre joueur commande ce véhicule.', 'error')
        return false
    end

    return true
end

-- Action lancée dans un thread : l'attente du contrôle réseau ne bloque pas le menu
local function async(fn)
    return function()
        CreateThread(fn)
    end
end

---------------------------------------------------------------------
-- Conduite automatique (conducteur)
---------------------------------------------------------------------

local function stopAutopilot(message)
    local current = autopilot

    if not current then
        return
    end

    autopilot = nil

    if DoesEntityExist(current.vehicle) and isDriver(current.vehicle) then
        ClearPedTasks(PlayerPedId())
    end

    if message then
        Notify(message, 'info')
    end
end

local function startAutopilot(vehicle)
    local blip = GetFirstBlipInfoId(8)

    if not DoesBlipExist(blip) then
        return Notify("Posez d'abord un point GPS sur la carte.", 'error')
    end

    local destination = GetBlipInfoIdCoord(blip)
    TaskVehicleDriveToCoordLongrange(PlayerPedId(), vehicle, destination.x, destination.y, destination.z, 25.0, 786603, 15.0)
    autopilot = { vehicle = vehicle }
    local current = autopilot
    Notify('Conduite automatique vers le point GPS : accélérez ou freinez pour reprendre la main.', 'info')

    CreateThread(function()
        while autopilot == current do
            Wait(0)
            local coords = GetEntityCoords(vehicle)

            if not DoesEntityExist(vehicle) or not isDriver(vehicle) then
                stopAutopilot(nil)
            elseif IsControlJustPressed(0, 71) or IsControlJustPressed(0, 72) then
                stopAutopilot('Conduite automatique arrêtée : vous reprenez la main.')
            elseif #(vector2(coords.x, coords.y) - vector2(destination.x, destination.y)) < 20.0 then
                stopAutopilot('Arrivé à destination.')
            end
        end
    end)
end

---------------------------------------------------------------------
-- Portes et vitres
---------------------------------------------------------------------

local function toggleDoor(vehicle, door, inside)
    if not inside and GetVehicleDoorLockStatus(vehicle) >= 2 then
        return Notify('Ce véhicule est verrouillé.', 'error')
    end

    if not control(vehicle) then
        return
    end

    if GetVehicleDoorAngleRatio(vehicle, door) > 0.05 then
        SetVehicleDoorShut(vehicle, door, false)
    else
        SetVehicleDoorOpen(vehicle, door, false, false)
    end
end

local function shutDoors(vehicle)
    if control(vehicle) then
        SetVehicleDoorsShut(vehicle, false)
    end
end

local function toggleWindow(vehicle, window)
    if not control(vehicle) then
        return
    end

    windowsDown[vehicle] = windowsDown[vehicle] or {}

    if windowsDown[vehicle][window] then
        RollUpWindow(vehicle, window)
        windowsDown[vehicle][window] = nil
    else
        RollDownWindow(vehicle, window)
        windowsDown[vehicle][window] = true
    end
end

---------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------

local function build(_, _, _, entity)
    local ped = PlayerPedId()
    local inside = GetVehiclePedIsIn(ped, false)
    local vehicle = inside ~= 0 and inside or nil

    -- De l'extérieur : véhicule cliqué, à portée
    if not vehicle then
        if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 or #(GetEntityCoords(ped) - GetEntityCoords(entity)) > REACH then
            return
        end

        vehicle = entity
    end

    local ECM = exports[RESOURCE]
    local health = math.min(100, math.floor(math.max(0.0, GetVehicleEngineHealth(vehicle)) / 10 + 0.5))

    ECM:AddTextItem(0, ('%s · %s · état %d %%'):format(vehicleLabel(vehicle), GetVehicleNumberPlateText(vehicle), health))

    if isDriver(vehicle) then
        local driving = autopilot and autopilot.vehicle == vehicle
        ECM:AddItem(0, driving and 'Arrêter la conduite automatique' or 'Conduite automatique', function()
            if driving then
                stopAutopilot('Conduite automatique arrêtée.')
            else
                startAutopilot(vehicle)
            end
        end)
    end

    -- Portes existantes du véhicule
    local doors = {}

    for _, door in ipairs(DOORS) do
        if GetIsDoorValid(vehicle, door[1]) then
            doors[#doors + 1] = door
        end
    end

    if #doors > 0 then
        local menu = ECM:AddSubmenu(0, 'Portes')

        for _, door in ipairs(doors) do
            ECM:AddItem(menu, door[2], async(function() toggleDoor(vehicle, door[1], inside ~= 0) end))
        end

        ECM:AddItem(menu, 'Tout fermer', async(function() shutDoors(vehicle) end))
    end

    -- Vitres : depuis l'intérieur
    if inside ~= 0 and not NO_WINDOWS[GetVehicleClass(vehicle)] then
        local menu = ECM:AddSubmenu(0, 'Fenêtres')

        for _, window in ipairs(WINDOWS) do
            local down = windowsDown[vehicle] and windowsDown[vehicle][window[1]]
            ECM:AddItem(menu, ('%s : %s'):format(window[2], down and 'monter' or 'descendre'), async(function() toggleWindow(vehicle, window[1]) end))
        end
    end
end

local function register()
    local ok, err = pcall(function()
        exports[RESOURCE]:Register(build)
    end)

    if not ok then
        print(('[lunatic_gameplay] Menu véhicule : enregistrement dans %s impossible : %s'):format(RESOURCE, err))
    end
end

CreateThread(function()
    if GetResourceState(RESOURCE) == 'started' then
        register()
    end
end)

-- ContextMenu (re)démarré après nous
AddEventHandler('onClientResourceStart', function(resource)
    if resource == RESOURCE then
        register()
    end
end)
