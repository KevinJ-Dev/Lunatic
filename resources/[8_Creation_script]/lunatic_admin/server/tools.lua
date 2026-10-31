-- Lot 4 : outils staff (modes, téléportation au marqueur, véhicules).
-- Le serveur autorise chaque outil, retient les modes actifs et les coupe si la permission disparaît.

local MODES = { noclip = true, invisible = true, godmode = true, ghost = true, names = true, coords = true }
local LOGGED_MODES = { noclip = true, invisible = true, godmode = true, ghost = true }
local VEHICLE_TYPES = { automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true }

---@type table<number, table<string, true>> modes actifs par membre du staff
local active = {}

AddEventHandler('playerDropped', function()
    active[source] = nil
end)

local function setMode(src, mode, enabled)
    active[src] = active[src] or {}
    active[src][mode] = enabled or nil

    if not next(active[src]) then
        active[src] = nil
    end

    TriggerClientEvent('lunatic_admin:tool', src, mode, enabled)
end

-- Pour les autres fichiers du panel (mode administration : noms et ID au-dessus des têtes)
Panel.setToolMode = setMode

local function modesOf(src)
    local modes = {}

    for mode in pairs(active[src] or {}) do
        modes[mode] = true
    end

    return modes
end

Panel.toolModesOf = modesOf

-- Modes actifs envoyés au panel (interrupteurs de la page Outils)
table.insert(Panel.stateHooks, function(state, src)
    state.tools = modesOf(src)
end)

-- Un membre qui perd une permission (rang modifié, retiré du staff) perd l'outil aussitôt
CreateThread(function()
    while true do
        Wait(5000)

        for src, modes in pairs(active) do
            for mode in pairs(modes) do
                if not Staff.can(src, 'tools.' .. mode) then
                    setMode(src, mode, false)
                    Panel.notify(src, 'Outil désactivé : vous n’avez plus la permission.', 'error')
                end
            end
        end
    end
end)

local function denied()
    return Panel.fail("Vous n'avez pas la permission d'utiliser cet outil.")
end

---------------------------------------------------------------------
-- Modes : noclip, invisibilité, invincibilité, noms, coordonnées
---------------------------------------------------------------------

Panel.actions['tool.toggle'] = function(src, actor, data)
    local mode = type(data.tool) == 'string' and data.tool

    if not mode or not MODES[mode] then
        return Panel.fail('Outil inconnu.')
    end

    if not Ranks.hasPermission(actor, 'tools.' .. mode) then
        return denied()
    end

    local enabled = data.enabled == true
    setMode(src, mode, enabled)

    if LOGGED_MODES[mode] then
        Logs.add(src, ('tool.%s.%s'):format(mode, enabled and 'on' or 'off'), nil, nil)
    end

    return { ok = true, silent = true, tools = modesOf(src) }
end

Panel.actions['tool.tpm'] = function(src, actor)
    if not Ranks.hasPermission(actor, 'tools.tpm') then
        return denied()
    end

    TriggerClientEvent('lunatic_admin:tpm', src)
    return { ok = true, silent = true }
end

-- /tpm d'ESX remplacé : il suit la permission « TP au marqueur » des rangs du panel au lieu des groupes ESX.
-- ESX.RegisterCommand sait remplacer une commande ; ouverte à tous les groupes, c'est le rang qui décide.
local function registerTpm()
    ESX.RegisterCommand('tpm', { 'user', 'admin', 'owner' }, function(xPlayer)
        local src = xPlayer and xPlayer.source

        if not src then
            return
        end

        local actor = Staff.rankOf(src)

        if not actor or not Ranks.hasPermission(actor, 'tools.tpm') then
            return Panel.notify(src, "Vous n'avez pas la permission (TP au marqueur).", 'error')
        end

        TriggerClientEvent('lunatic_admin:tpm', src)
    end, false, { help = 'Se téléporter au marqueur de la carte (staff)' })
end

CreateThread(registerTpm)

-- es_extended redémarré : il a remis son /tpm
AddEventHandler('onResourceStart', function(resource)
    if resource == 'es_extended' then
        SetTimeout(2000, registerTpm)
    end
end)

-- Couleurs de rang des membres connectés (noms au-dessus des têtes)
lib.callback.register('lunatic_admin:staffColors', function(src)
    if not Staff.can(src, 'tools.names') then
        return {}
    end

    local colors = {}

    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        local rank = Staff.rankOf(target)

        if rank then
            colors[tostring(target)] = rank.color
        end
    end

    return colors
end)

---------------------------------------------------------------------
-- Véhicules
---------------------------------------------------------------------

-- Le client a vérifié que le modèle existe et donne son type ; le serveur crée le véhicule
Panel.actions['vehicle.spawn'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'tools.vehicles') then
        return denied()
    end

    local model = type(data.model) == 'string' and data.model:lower()
    local vehicleType = type(data.type) == 'string' and data.type

    if not model or not model:match('^[%w_]+$') or #model > 32 then
        return Panel.fail('Nom de modèle invalide.')
    end

    if not vehicleType or not VEHICLE_TYPES[vehicleType] then
        return Panel.fail('Type de véhicule invalide.')
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return Panel.fail("Votre personnage n'est pas encore apparu.")
    end

    local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local vehicle = CreateVehicleServerSetter(joaat(model), vehicleType, coords.x, coords.y, coords.z + 0.5, heading)
    local timeout = GetGameTimer() + 3000

    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return Panel.fail("Le véhicule n'a pas pu être créé.")
    end

    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(vehicle, Config.VehiclePlate)
    Logs.add(src, 'vehicle.spawn', model, nil)

    return { ok = true, silent = true, netId = NetworkGetNetworkIdFromEntity(vehicle) }
end

local function currentVehicle(src)
    local ped = GetPlayerPed(src)
    local vehicle = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0

    return vehicle ~= 0 and vehicle or nil
end

Panel.actions['vehicle.repair'] = function(src, actor)
    if not Ranks.hasPermission(actor, 'tools.vehicles') then
        return denied()
    end

    if not currentVehicle(src) then
        return Panel.fail("Vous n'êtes pas dans un véhicule.")
    end

    TriggerClientEvent('lunatic_admin:vehicleFix', src)
    return { ok = true, silent = true }
end

Panel.actions['vehicle.flip'] = function(src, actor)
    if not Ranks.hasPermission(actor, 'tools.vehicles') then
        return denied()
    end

    if not currentVehicle(src) then
        return Panel.fail("Vous n'êtes pas dans un véhicule.")
    end

    TriggerClientEvent('lunatic_admin:vehicleFlip', src)
    return { ok = true, silent = true }
end

local function hasOccupant(vehicle)
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(vehicle, seat)

        if ped and ped ~= 0 and IsPedAPlayer(ped) then
            return true
        end
    end

    return false
end

-- radius = 0 : son propre véhicule ; sinon les véhicules vides dans le rayon
Panel.actions['vehicle.delete'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'tools.vehicles') then
        return denied()
    end

    local radius = tonumber(data.radius) or 0

    if radius <= 0 then
        local vehicle = currentVehicle(src)

        if not vehicle then
            return Panel.fail("Vous n'êtes pas dans un véhicule.")
        end

        DeleteEntity(vehicle)
        Logs.add(src, 'vehicle.delete', 'véhicule actuel', nil)
        return { ok = true, silent = true, count = 1 }
    end

    radius = math.min(radius, Config.VehicleDeleteMaxRadius)

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return Panel.fail("Votre personnage n'est pas encore apparu.")
    end

    local origin = GetEntityCoords(ped)
    local bucket = GetPlayerRoutingBucket(src)
    local count = 0

    for _, vehicle in ipairs(GetAllVehicles()) do
        if GetEntityRoutingBucket(vehicle) == bucket
            and #(GetEntityCoords(vehicle) - origin) <= radius
            and not hasOccupant(vehicle) then
            DeleteEntity(vehicle)
            count = count + 1
        end
    end

    Logs.add(src, 'vehicle.delete', ('%d véhicule(s) dans %d m'):format(count, radius), nil)
    return { ok = true, silent = true, count = count }
end

print('[lunatic_admin] Module Outils chargé.')
