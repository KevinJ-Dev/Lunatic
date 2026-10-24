-- Boutique des joueurs, côté client : ouverture (/boutique ou F1), achats envoyés au serveur, notification de la boutique.

local opened = false

local function close()
    opened = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function open()
    if opened then
        return close()
    end

    local data = lib.callback.await('lunatic_store:open', false)

    if not data then
        return
    end

    opened = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end

RegisterCommand(Config.Command, open, false)
RegisterKeyMapping(Config.Command, 'Ouvrir la boutique', 'keyboard', Config.OpenKey)

RegisterNUICallback('close', function(_, cb)
    close()
    cb({})
end)

RegisterNUICallback('buy', function(request, cb)
    cb(lib.callback.await('lunatic_store:buy', false, request) or { ok = false, error = 'Pas de réponse du serveur.' })
end)

-- Le serveur fait vérifier les modèles de véhicules au client (le serveur ne les connaît pas)
local VEHICLE_TYPES = { [8] = 'bike', [13] = 'bike', [14] = 'boat', [15] = 'heli', [16] = 'plane', [21] = 'train' }

lib.callback.register('lunatic_store:vehicleModel', function(model)
    model = type(model) == 'string' and model:lower() or ''
    local hash = joaat(model)

    if model == '' or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return { ok = false }
    end

    return { ok = true, type = VEHICLE_TYPES[GetVehicleClassFromName(hash)] or 'car' }
end)

---------------------------------------------------------------------
-- Notification de la boutique (tuile Boutique : statut, compte à rebours, couleur, image)
---------------------------------------------------------------------

local shownFor = nil

local function showNotification(settings)
    local n = settings and settings.notification

    if type(n) ~= 'table' or not n.live or shownFor == n.startedAt then
        return
    end

    shownFor = n.startedAt
    SendNUIMessage({
        action = 'notify', duration = Config.NotificationSeconds * 1000,
        notification = { title = n.title, text = n.text, color = n.color, image = n.image ~= '' and n.image or nil, endsAt = n.endsAt, key = Config.OpenKey },
    })
end

AddStateBagChangeHandler('lunaticShop', 'global', function(_, _, value)
    showNotification(value)
end)

-- À l'arrivée en jeu
AddEventHandler('esx:playerLoaded', function()
    SetTimeout(8000, function()
        showNotification(GlobalState.lunaticShop)
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and opened then
        SetNuiFocus(false, false)
    end
end)
