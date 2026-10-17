-- Client du tchat : ouverture, envoi et relais des événements de la resource "chat" de FiveM vers l'interface

local isOpen = false
local paused = false

local function ui(data)
    SendNUIMessage(data)
end

local function closeChat()
    if not isOpen then
        return
    end

    isOpen = false
    SetNuiFocus(false, false)
    ui({ type = 'close' })
end

local function openChat()
    if isOpen or IsPauseMenuActive() then
        return
    end

    isOpen = true
    SetNuiFocus(true, false)
    ui({ type = 'open' })
    TriggerServerEvent('lunatic_chat:requestAccess')
end

RegisterCommand('lunatic_chat_open', openChat, false)
RegisterKeyMapping('lunatic_chat_open', 'Ouvrir le tchat', 'keyboard', Config.OpenKey)

---------------------------------------------------------------------
-- Interface
---------------------------------------------------------------------

-- Suggestions de nos commandes ; "access" = accès staff requis pour les voir
local suggestions = {
    { name = '/hrp', help = 'Message hors RP aux joueurs proches', params = { { name = 'message' } } },
    { name = '/me', help = 'Action de votre personnage (texte au-dessus de la tête)', params = { { name = 'action' } } },
    { name = '/do', help = 'Description de la scène (texte au-dessus de la tête)', params = { { name = 'description' } } },
    { name = '/sc', help = 'Tchat staff privé', params = { { name = 'message' } }, access = 'staff' },
    { name = '/annonce', help = 'Annonce à tout le serveur', params = { { name = 'message' } }, access = 'announce' },
    { name = '/vidertchat', help = 'Vider le tchat de tous les joueurs', access = 'clear' },
    { name = '/staff', help = 'Ouvrir le panel staff', access = 'panel' },
}

RegisterNUICallback('ready', function(_, cb)
    ui({ type = 'config', maxLength = Config.MaxLength })
    ui({ type = 'suggestions', list = suggestions })
    cb(1)
end)

RegisterNUICallback('close', function(_, cb)
    closeChat()
    cb(1)
end)

RegisterNUICallback('send', function(data, cb)
    cb(1)
    closeChat()

    local text = type(data) == 'table' and data.text

    if type(text) ~= 'string' then
        return
    end

    text = text:match('^%s*(.-)%s*$')

    if text:sub(1, 1) == '/' then
        local command = text:sub(2)

        if command ~= '' then
            ExecuteCommand(command)
        end
    elseif text ~= '' then
        TriggerServerEvent('lunatic_chat:say', text)
    end
end)

-- Masque le tchat dans le menu pause
CreateThread(function()
    while true do
        local inPause = IsPauseMenuActive()

        if inPause ~= paused then
            paused = inPause
            ui({ type = 'visible', visible = not inPause })

            if inPause then
                closeChat()
            end
        end

        Wait(250)
    end
end)

---------------------------------------------------------------------
-- Messages du tchat Lunatic
---------------------------------------------------------------------

RegisterNetEvent('lunatic_chat:message', function(message)
    ui({ type = 'message', message = message })
end)

RegisterNetEvent('lunatic_chat:access', function(flags)
    ui({ type = 'access', flags = flags })
end)

---------------------------------------------------------------------
-- Compatibilité avec la resource "chat" de FiveM (ESX, ox_lib, autres scripts)
---------------------------------------------------------------------

RegisterNetEvent('chat:addMessage', function(message)
    ui({ type = 'legacy', message = message })
end)

RegisterNetEvent('chatMessage', function(author, color, text)
    ui({ type = 'legacy', message = { color = color, args = { author, text } } })
end)

RegisterNetEvent('chat:addTemplate', function(id, html)
    ui({ type = 'template', id = id, html = html })
end)

RegisterNetEvent('chat:addSuggestion', function(name, help, params)
    ui({ type = 'suggestions', list = { { name = name, help = help, params = params } } })
end)

RegisterNetEvent('chat:addSuggestions', function(list)
    ui({ type = 'suggestions', list = list })
end)

RegisterNetEvent('chat:removeSuggestion', function(name)
    ui({ type = 'removeSuggestion', name = name })
end)

RegisterNetEvent('chat:clear', function()
    ui({ type = 'clear' })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and isOpen then
        SetNuiFocus(false, false)
    end
end)
