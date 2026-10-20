-- Ouverture du panel et relais entre l'interface web et le serveur.
-- Le client ne décide de rien : il transmet les demandes et affiche ce que le serveur renvoie.

local isOpen = false

local function close()
    if not isOpen then
        return
    end

    isOpen = false
    -- Un avertissement affiché garde la souris (client/sanctions.lua)
    SetNuiFocus(WarningOpen == true, WarningOpen == true)
    SendNUIMessage({ action = 'close' })
end

-- Utilisé par client/players.lua (le panel se ferme pendant l'observation d'un joueur)
ClosePanel = close
IsPanelOpen = function()
    return isOpen
end

-- Touche liée à la commande (F10 par défaut, ou celle choisie par le joueur) :
-- l'interface a le focus clavier, c'est donc elle qui referme le panel avec cette touche
local function toggleKey()
    local button = GetControlInstructionalButton(0, joaat(Config.Command) | 0x80000000, true)

    if type(button) == 'string' and button:sub(1, 2) == 't_' then
        return button:sub(3)
    end

    return Config.DefaultKey
end

-- Portrait du personnage (tête en jeu) pour la pastille du panel, refait à chaque ouverture
local headshot

function SendHeadshot()
    local handle = RegisterPedheadshotTransparent(PlayerPedId())
    local timeout = GetGameTimer() + 3000

    while (not IsPedheadshotReady(handle) or not IsPedheadshotValid(handle)) and GetGameTimer() < timeout do
        Wait(50)
    end

    if not IsPedheadshotReady(handle) or not IsPedheadshotValid(handle) then
        UnregisterPedheadshot(handle)
        return
    end

    local txd = GetPedheadshotTxdString(handle)
    SendNUIMessage({ action = 'headshot', url = ('https://nui-img/%s/%s'):format(txd, txd) })

    -- L'ancien portrait n'est libéré qu'une fois le nouveau affiché
    if headshot then
        UnregisterPedheadshot(headshot)
    end

    headshot = handle
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
    SendNUIMessage({ action = 'open', state = state, toggleKey = toggleKey() })
    CreateThread(SendHeadshot)
end

-- Menu contextuel : ouvre le panel sur la fiche d'un joueur
function OpenPanelOnPlayer(serverId)
    open()

    if isOpen then
        SendNUIMessage({ action = 'focusPlayer', serverId = serverId })
    end
end

RegisterCommand(Config.Command, open, false)
RegisterKeyMapping(Config.Command, 'Ouvrir le panel staff', 'keyboard', Config.DefaultKey)

RegisterNUICallback('close', function(_, cb)
    close()
    cb(1)
end)

-- Rafraîchissement périodique de la page Joueurs
RegisterNUICallback('refresh', function(_, cb)
    if not isOpen then
        return cb(false)
    end

    cb(lib.callback.await('lunatic_admin:open', false) or false)
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
