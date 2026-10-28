-- Lot M : menu contextuel staff avec la resource ContextMenu (Kiminaze, dans [0_Libs]).
-- Maintenir Alt gauche, clic droit sur un joueur (soi-même compris), un véhicule, un PNJ ou un objet, clic gauche pour choisir.
-- Les options visibles dépendent des droits envoyés par le serveur (server/context.lua), qui revérifie chaque action.

local RESOURCE = 'ContextMenu'

---@type table<string, true> droits du menu
local flags = {}

RegisterNetEvent('lunatic_admin:contextFlags', function(value)
    flags = type(value) == 'table' and value or {}
    print(('[lunatic_admin] Menu contextuel : droits reçus (staff %s, dév %s).'):format(flags.use and 'oui' or 'non', flags.dev and 'oui' or 'non'))
end)

CreateThread(function()
    TriggerServerEvent('lunatic_admin:contextFlagsRequest')
end)

local function ask(action, payload)
    return lib.callback.await('lunatic_admin:action', false, action, payload or {})
end

local function done(result, okMessage)
    if result and result.ok then
        if okMessage or result.message then
            ESX.ShowNotification(okMessage or result.message, 'success')
        end

        return true
    end

    ESX.ShowNotification(result and result.error or 'Action impossible.', 'error')
    return false
end

local function allowed(key)
    return flags.use == true and flags[key] == true
end

-- Les actions du menu tournent hors de la boucle d'affichage de ContextMenu (les appels serveur attendent une réponse)
local function async(func)
    return function()
        CreateThread(func)
    end
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
-- Joueurs (soi-même compris)
---------------------------------------------------------------------

local function playerName(serverId)
    local state = Player(serverId).state

    if state.firstName and state.lastName then
        return ('[%d] %s %s'):format(serverId, state.firstName, state.lastName)
    end

    return ('[%d] %s'):format(serverId, GetPlayerName(GetPlayerFromServerId(serverId)) or '?')
end

local function playerMenu(ECM, ped)
    local player = NetworkGetPlayerIndexFromPed(ped)
    local serverId = player ~= -1 and GetPlayerServerId(player) or nil

    if not serverId or not flags.use then
        return
    end

    local isSelf = ped == PlayerPedId()
    local run = function(action, okMessage)
        return async(function()
            done(ask(action, { serverId = serverId }), okMessage)
        end)
    end

    ECM:AddTextItem(0, isSelf and ('%s (vous)'):format(playerName(serverId)) or playerName(serverId))

    if allowed('view') then
        ECM:AddItem(0, 'Ouvrir la fiche', async(function()
            OpenPanelOnPlayer(serverId)
        end))
    end

    if not isSelf and allowed('teleport') then
        ECM:AddItem(0, 'Aller vers', run('player.goto', nil))
    end

    if not isSelf and allowed('bring') then
        ECM:AddItem(0, 'Ramener', run('player.bring', 'Joueur ramené.'))
    end

    if not isSelf and allowed('freeze') then
        ECM:AddItem(0, 'Figer / libérer', run('player.freeze', 'Joueur figé ou libéré.'))
    end

    if allowed('heal') then
        ECM:AddItem(0, 'Soigner', run('player.heal', 'Joueur soigné.'))
        ECM:AddItem(0, 'Réanimer', run('player.revive', 'Joueur réanimé.'))
    end

    if not isSelf and allowed('spectate') then
        ECM:AddItem(0, 'Observer', run('player.spectate', nil))
    end

    if not isSelf and allowed('items') then
        ECM:AddItem(0, 'Inventaire', run('inventory.open', nil))
    end
end

---------------------------------------------------------------------
-- Véhicules
---------------------------------------------------------------------

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

local function vehicleMenu(ECM, vehicle)
    if not allowed('vehicles') then
        return
    end

    local run = function(operation, apply, okMessage)
        return async(function()
            local netId = netIdOf(vehicle)

            if not netId then
                return ESX.ShowNotification('Véhicule non synchronisé : action impossible.', 'error')
            end

            local result = ask('context.vehicle', { netId = netId, operation = operation })

            if done(result, okMessage) and apply and DoesEntityExist(vehicle) then
                apply(vehicle, result)
            end
        end)
    end

    local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)):lower()
    ECM:AddTextItem(0, ('%s · %s'):format(model, GetVehicleNumberPlateText(vehicle)))
    ECM:AddItem(0, 'Réparer', run('repair', repair, 'Véhicule réparé.'))
    ECM:AddItem(0, 'Retourner', run('flip', flip, 'Véhicule retourné.'))
    ECM:AddItem(0, 'Monter dedans', run('enter', enter, nil))
    ECM:AddItem(0, 'Propriétaire', run('owner', showOwner, nil))
    ECM:AddItem(0, 'Mettre en fourrière', run('impound', nil, nil))
    ECM:AddItem(0, 'Supprimer', run('delete', nil, 'Véhicule supprimé.'))
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

    if not done(result, okMessage) or not isLocal or not DoesEntityExist(entity) then
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

-- menuId : 0 pour le menu principal (PNJ, objets), sinon un sous-menu « Dév »
local function devItems(ECM, menuId, entity)
    local isPlayer = GetEntityType(entity) == 1 and IsPedAPlayer(entity)

    ECM:AddItem(menuId, 'Copier vector3', function()
        local c = GetEntityCoords(entity)
        copy(('vector3(%.2f, %.2f, %.2f)'):format(c.x, c.y, c.z), 'Coordonnées copiées.')
    end)

    ECM:AddItem(menuId, 'Copier vector4', function()
        local c = GetEntityCoords(entity)
        copy(('vector4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, GetEntityHeading(entity)), 'Coordonnées et heading copiés.')
    end)

    ECM:AddItem(menuId, 'Copier le modèle', function()
        copy(modelText(entity), 'Modèle copié.')
    end)

    ECM:AddItem(menuId, 'Infos complètes', function()
        local info = DevEntityInfo(entity)
        SendNUIMessage({ action = 'devEntity', entity = info })
        print(('[lunatic_admin] Entité : %s'):format(json.encode(info)))
        ESX.ShowNotification('Infos envoyées au panel (page Développeur) et à la console F8.', 'success')
    end)

    if not isPlayer then
        ECM:AddItem(menuId, 'Geler / dégeler', async(function()
            local frozen = IsEntityPositionFrozen(entity)
            entityOperation(entity, frozen and 'unfreeze' or 'freeze', frozen and 'Entité dégelée.' or 'Entité gelée.')
        end))

        ECM:AddItem(menuId, "Supprimer l'entité", async(function()
            entityOperation(entity, 'delete', 'Entité supprimée.')
        end))
    end
end

---------------------------------------------------------------------
-- Enregistrement dans ContextMenu
---------------------------------------------------------------------

local function build(_, _, _, entity)
    if not (flags.use or flags.dev) or not entity or entity == 0 or not DoesEntityExist(entity) then
        return
    end

    local ECM = exports[RESOURCE]
    local kind = GetEntityType(entity)
    local isPlayer = kind == 1 and IsPedAPlayer(entity)

    if isPlayer then
        playerMenu(ECM, entity)
    elseif kind == 2 then
        vehicleMenu(ECM, entity)
    end

    if flags.dev then
        -- Joueurs et véhicules : sous-menu ; PNJ et objets : directement dans le menu
        if isPlayer or kind == 2 then
            local devMenu = ECM:AddSubmenu(0, 'Dév')
            devItems(ECM, devMenu, entity)
        else
            ECM:AddTextItem(0, kind == 1 and 'PNJ' or 'Objet')
            devItems(ECM, 0, entity)
        end
    end
end

local function register()
    local ok, err = pcall(function()
        exports[RESOURCE]:Register(build)
    end)

    print(ok and '[lunatic_admin] Menu contextuel enregistré dans ContextMenu (Alt gauche + clic droit).'
        or ('[lunatic_admin] Menu contextuel : enregistrement impossible : %s'):format(err))
end

CreateThread(function()
    local state = GetResourceState(RESOURCE)

    if state == 'started' then
        register()
    else
        print(("[lunatic_admin] Menu contextuel : la resource %s n'est pas démarrée (état : %s)."):format(RESOURCE, state))
    end
end)

-- ContextMenu (re)démarré après nous
AddEventHandler('onClientResourceStart', function(resource)
    if resource == RESOURCE then
        register()
    end
end)
