-- Lot M : menu contextuel staff dans ox_target (Alt, puis clic sur un joueur, un véhicule, un PNJ ou un objet).
-- Joueurs et véhicules : sous-menu « Staff » ; PNJ et objets : sous-menu « Dév ».
-- Les options visibles dépendent des droits envoyés par le serveur, qui revérifie chaque action.

local STAFF_MENU = 'lunatic_staff'
local DEV_MENU = 'lunatic_dev'
local DISTANCE = 20.0

---@type table<string, true> droits du menu (server/context.lua)
local flags = {}

RegisterNetEvent('lunatic_admin:contextFlags', function(value)
    flags = type(value) == 'table' and value or {}
end)

CreateThread(function()
    TriggerServerEvent('lunatic_admin:contextFlagsRequest')
end)

local function ask(action, payload)
    return lib.callback.await('lunatic_admin:action', false, action, payload or {})
end

local function done(result, okMessage)
    if result and result.ok then
        if okMessage then
            ESX.ShowNotification(okMessage, 'success')
        end

        return true
    end

    ESX.ShowNotification(result and result.error or 'Action impossible.', 'error')
    return false
end

local function allowed(key)
    return function()
        return flags.use == true and flags[key] == true
    end
end

local function devAllowed()
    return flags.dev == true
end

local function serverIdOf(ped)
    local player = NetworkGetPlayerIndexFromPed(ped)
    return player ~= -1 and GetPlayerServerId(player) or nil
end

local function netIdOf(entity)
    return NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or nil
end

-- Prend le contrôle réseau d'une entité (nécessaire pour la modifier depuis ce client)
local function control(entity)
    local timeout = GetGameTimer() + 1000

    NetworkRequestControlOfEntity(entity)

    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
    end

    return NetworkHasControlOfEntity(entity)
end

---------------------------------------------------------------------
-- Joueurs
---------------------------------------------------------------------

local function playerAction(action, okMessage)
    return function(data)
        local id = serverIdOf(data.entity)

        if id then
            done(ask(action, { serverId = id }), okMessage)
        end
    end
end

local function playerOptions()
    return {
        { name = 'lunatic:staff', icon = 'fa-solid fa-user-shield', label = 'Staff', openMenu = STAFF_MENU, distance = DISTANCE,
            canInteract = function() return flags.use == true or flags.dev == true end },
        { name = 'lunatic:fiche', menuName = STAFF_MENU, icon = 'fa-solid fa-id-card', label = 'Ouvrir la fiche', distance = DISTANCE,
            canInteract = allowed('view'),
            onSelect = function(data)
                local id = serverIdOf(data.entity)

                if id then
                    OpenPanelOnPlayer(id)
                end
            end },
        { name = 'lunatic:goto', menuName = STAFF_MENU, icon = 'fa-solid fa-person-walking-arrow-right', label = 'Aller vers', distance = DISTANCE,
            canInteract = allowed('goto'), onSelect = playerAction('player.goto', nil) },
        { name = 'lunatic:bring', menuName = STAFF_MENU, icon = 'fa-solid fa-person-walking-arrow-loop-left', label = 'Ramener', distance = DISTANCE,
            canInteract = allowed('bring'), onSelect = playerAction('player.bring', 'Joueur ramené.') },
        { name = 'lunatic:freeze', menuName = STAFF_MENU, icon = 'fa-solid fa-snowflake', label = 'Figer / libérer', distance = DISTANCE,
            canInteract = allowed('freeze'), onSelect = playerAction('player.freeze', 'Joueur figé ou libéré.') },
        { name = 'lunatic:heal', menuName = STAFF_MENU, icon = 'fa-solid fa-heart-pulse', label = 'Soigner', distance = DISTANCE,
            canInteract = allowed('heal'), onSelect = playerAction('player.heal', 'Joueur soigné.') },
        { name = 'lunatic:revive', menuName = STAFF_MENU, icon = 'fa-solid fa-kit-medical', label = 'Réanimer', distance = DISTANCE,
            canInteract = allowed('heal'), onSelect = playerAction('player.revive', 'Joueur réanimé.') },
        { name = 'lunatic:spectate', menuName = STAFF_MENU, icon = 'fa-solid fa-eye', label = 'Observer', distance = DISTANCE,
            canInteract = allowed('spectate'), onSelect = playerAction('player.spectate', nil) },
        { name = 'lunatic:inventory', menuName = STAFF_MENU, icon = 'fa-solid fa-box-open', label = 'Inventaire', distance = DISTANCE,
            canInteract = allowed('items'), onSelect = playerAction('inventory.open', nil) },
        { name = 'lunatic:todev', menuName = STAFF_MENU, icon = 'fa-solid fa-code', label = 'Dév', openMenu = DEV_MENU, distance = DISTANCE,
            canInteract = devAllowed },
    }
end

---------------------------------------------------------------------
-- Véhicules
---------------------------------------------------------------------

local function vehicleAction(operation, apply, okMessage)
    return function(data)
        local vehicle = data.entity
        local netId = netIdOf(vehicle)

        if not netId then
            return ESX.ShowNotification('Véhicule non synchronisé : action impossible.', 'error')
        end

        local result = ask('context.vehicle', { netId = netId, operation = operation })

        if not done(result, okMessage) then
            return
        end

        if apply then
            apply(vehicle, result)
        end
    end
end

local function repair(vehicle)
    if control(vehicle) then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehicleDirtLevel(vehicle, 0.0)
    end
end

local function flip(vehicle)
    if control(vehicle) then
        SetEntityRotation(vehicle, 0.0, 0.0, GetEntityHeading(vehicle), 2, true)
        SetVehicleOnGroundProperly(vehicle)
    end
end

local function enter(vehicle)
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if IsVehicleSeatFree(vehicle, seat) then
            TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, seat)
            return
        end
    end

    ESX.ShowNotification('Aucune place libre dans ce véhicule.', 'error')
end

local function showOwner(_, result)
    if result.owner then
        ESX.ShowNotification(('Propriétaire : %s (plaque %s).'):format(result.owner, result.plate), 'info')
    else
        ESX.ShowNotification(('Aucun propriétaire enregistré (plaque %s).'):format(result.plate ~= '' and result.plate or '?'), 'info')
    end
end

local function vehicleOptions()
    return {
        { name = 'lunatic:staff', icon = 'fa-solid fa-user-shield', label = 'Staff', openMenu = STAFF_MENU, distance = DISTANCE,
            canInteract = function() return (flags.use == true and flags.vehicles == true) or flags.dev == true end },
        { name = 'lunatic:vrepair', menuName = STAFF_MENU, icon = 'fa-solid fa-wrench', label = 'Réparer', distance = DISTANCE,
            canInteract = allowed('vehicles'), onSelect = vehicleAction('repair', repair, 'Véhicule réparé.') },
        { name = 'lunatic:vflip', menuName = STAFF_MENU, icon = 'fa-solid fa-rotate', label = 'Retourner', distance = DISTANCE,
            canInteract = allowed('vehicles'), onSelect = vehicleAction('flip', flip, 'Véhicule retourné.') },
        { name = 'lunatic:venter', menuName = STAFF_MENU, icon = 'fa-solid fa-car-side', label = 'Monter dedans', distance = DISTANCE,
            canInteract = allowed('vehicles'), onSelect = vehicleAction('enter', enter, nil) },
        { name = 'lunatic:vowner', menuName = STAFF_MENU, icon = 'fa-solid fa-user-tag', label = 'Propriétaire', distance = DISTANCE,
            canInteract = allowed('vehicles'), onSelect = vehicleAction('owner', showOwner, nil) },
        { name = 'lunatic:vdelete', menuName = STAFF_MENU, icon = 'fa-solid fa-trash', label = 'Supprimer', distance = DISTANCE,
            canInteract = allowed('vehicles'), onSelect = vehicleAction('delete', nil, 'Véhicule supprimé.') },
        { name = 'lunatic:todev', menuName = STAFF_MENU, icon = 'fa-solid fa-code', label = 'Dév', openMenu = DEV_MENU, distance = DISTANCE,
            canInteract = devAllowed },
    }
end

---------------------------------------------------------------------
-- Section Dév (toutes les entités)
---------------------------------------------------------------------

local function copy(text, message)
    lib.setClipboard(text)
    ESX.ShowNotification(message, 'success')
end

local function modelText(entity)
    local model = GetEntityModel(entity)
    local hex = ('0x%08X'):format(model & 0xFFFFFFFF)

    if GetEntityType(entity) == 2 then
        return ('%s (%d / %s)'):format(GetDisplayNameFromVehicleModel(model):lower(), model, hex)
    end

    return ('%d / %s'):format(model, hex)
end

local function entityOperation(entity, operation, okMessage)
    local netId = netIdOf(entity)
    local isLocal = netId == nil
    local result = ask('context.entity', { netId = netId, operation = operation, ['local'] = isLocal, model = GetEntityModel(entity) })

    if not done(result, okMessage) or not isLocal then
        return
    end

    -- Entité locale : appliquée seulement de ce côté (décor de la carte compris)
    if operation == 'delete' then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    else
        FreezeEntityPosition(entity, operation == 'freeze')
    end
end

local function devOptions(top)
    local options = {
        { name = 'lunatic:vec3', menuName = DEV_MENU, icon = 'fa-solid fa-location-crosshairs', label = 'Copier vector3', distance = DISTANCE,
            canInteract = devAllowed,
            onSelect = function(data)
                local c = GetEntityCoords(data.entity)
                copy(('vector3(%.2f, %.2f, %.2f)'):format(c.x, c.y, c.z), 'Coordonnées copiées.')
            end },
        { name = 'lunatic:vec4', menuName = DEV_MENU, icon = 'fa-solid fa-compass', label = 'Copier vector4', distance = DISTANCE,
            canInteract = devAllowed,
            onSelect = function(data)
                local c = GetEntityCoords(data.entity)
                copy(('vector4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, GetEntityHeading(data.entity)), 'Coordonnées et heading copiés.')
            end },
        { name = 'lunatic:model', menuName = DEV_MENU, icon = 'fa-solid fa-cube', label = 'Copier le modèle', distance = DISTANCE,
            canInteract = devAllowed,
            onSelect = function(data)
                copy(modelText(data.entity), 'Modèle copié.')
            end },
        { name = 'lunatic:info', menuName = DEV_MENU, icon = 'fa-solid fa-circle-info', label = 'Infos complètes', distance = DISTANCE,
            canInteract = devAllowed,
            onSelect = function(data)
                local info = DevEntityInfo(data.entity)
                SendNUIMessage({ action = 'devEntity', entity = info })
                print(('[lunatic_admin] Entité : %s'):format(json.encode(info)))
                ESX.ShowNotification('Infos envoyées au panel (page Développeur) et à la console F8.', 'success')
            end },
        { name = 'lunatic:dfreeze', menuName = DEV_MENU, icon = 'fa-solid fa-lock', label = 'Geler / dégeler', distance = DISTANCE,
            canInteract = function(entity)
                return devAllowed() and not (GetEntityType(entity) == 1 and IsPedAPlayer(entity))
            end,
            onSelect = function(data)
                local frozen = IsEntityPositionFrozen(data.entity)
                entityOperation(data.entity, frozen and 'unfreeze' or 'freeze', frozen and 'Entité dégelée.' or 'Entité gelée.')
            end },
        { name = 'lunatic:ddelete', menuName = DEV_MENU, icon = 'fa-solid fa-trash', label = 'Supprimer l\'entité', distance = DISTANCE,
            canInteract = function(entity)
                return devAllowed() and not (GetEntityType(entity) == 1 and IsPedAPlayer(entity))
            end,
            onSelect = function(data)
                entityOperation(data.entity, 'delete', 'Entité supprimée.')
            end },
    }

    -- PNJ et objets : le menu Dév s'ouvre directement
    if top then
        table.insert(options, 1, { name = 'lunatic:dev', icon = 'fa-solid fa-code', label = 'Dév', openMenu = DEV_MENU, distance = DISTANCE,
            canInteract = devAllowed })
    end

    return options
end

---------------------------------------------------------------------
-- Enregistrement dans ox_target
---------------------------------------------------------------------

local function register()
    local target = exports.ox_target
    local players = playerOptions()
    local vehicles = vehicleOptions()

    for _, option in ipairs(devOptions(false)) do
        players[#players + 1] = option
    end

    for _, option in ipairs(devOptions(false)) do
        vehicles[#vehicles + 1] = option
    end

    target:addGlobalPlayer(players)
    target:addGlobalVehicle(vehicles)
    target:addGlobalPed(devOptions(true))
    target:addGlobalObject(devOptions(true))
end

CreateThread(function()
    if GetResourceState('ox_target') == 'started' then
        register()
    end
end)

-- ox_target (re)démarré après nous
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'ox_target' then
        register()
    end
end)
