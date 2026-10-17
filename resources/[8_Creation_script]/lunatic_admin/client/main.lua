-- Ouverture du panel et relais entre l'interface web et le serveur.
-- Le client ne décide de rien : il transmet les demandes et affiche ce que le serveur renvoie.

local isOpen = false

local function close()
    if not isOpen then
        return
    end

    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function open()
    if isOpen then
        return
    end

    local state = lib.callback.await('lunatic_admin:open', false)

    if not state then
        ESX.ShowNotification("Vous n'avez pas accès au panel staff.", 'error')
        return
    end

    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', state = state })
end

RegisterCommand(Config.Command, open, false)
RegisterKeyMapping(Config.Command, 'Ouvrir le panel staff', 'keyboard', Config.DefaultKey)

RegisterNUICallback('close', function(_, cb)
    close()
    cb(1)
end)

RegisterNUICallback('action', function(data, cb)
    if not isOpen or type(data) ~= 'table' then
        return cb({ ok = false, error = 'Panel fermé.' })
    end

    local result = lib.callback.await('lunatic_admin:action', false, data.action, data.payload)

    if result and result.ok and result.state == false then
        -- L'auteur vient de perdre l'accès au panel
        cb(result)
        close()
        return
    end

    cb(result or { ok = false, error = 'Pas de réponse du serveur.' })
end)

-- Les rangs ou le staff ont changé : on recharge le panel s'il est ouvert
RegisterNetEvent('lunatic_admin:refresh', function()
    if not isOpen then
        return
    end

    local state = lib.callback.await('lunatic_admin:open', false)

    if not state then
        close()
        return
    end

    SendNUIMessage({ action = 'state', state = state })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == cache.resource and isOpen then
        SetNuiFocus(false, false)
    end
end)
