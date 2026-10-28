-- Menu rapide du staff (menu admin, doc Vision) : une touche (F9 par défaut, réglable dans les touches de FiveM) ouvre
-- une petite liste à gauche : mode administration, reports, joueurs, staff, joueurs hors ligne, outils, gestion.
-- Chaque entrée ouvre la bonne page du panel ; le serveur donne les chiffres et les droits, et revérifie tout.

local quickOpen = false

local function closeQuick()
    if not quickOpen then
        return
    end

    quickOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'quickClose' })
end

local function showQuick()
    local data = lib.callback.await('lunatic_admin:quick', false)

    if not data then
        quickOpen = false
        return ESX.ShowNotification("Vous n'avez pas accès au menu staff.", 'error')
    end

    quickOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'quick', data = data })
end

RegisterCommand('staffmenu', function()
    if IsPanelOpen() then
        return
    end

    if quickOpen then
        return closeQuick()
    end

    CreateThread(showQuick)
end, false)
RegisterKeyMapping('staffmenu', 'Staff : menu rapide (administration)', 'keyboard', Config.QuickMenuKey)

RegisterNUICallback('quickClose', function(_, cb)
    cb({})
    closeQuick()
end)

-- Entrée choisie : mode administration (bascule, le menu reste ouvert) ou page du panel
RegisterNUICallback('quickAction', function(data, cb)
    cb({})

    if not quickOpen or type(data.id) ~= 'string' then
        return
    end

    if data.id == 'adminMode' then
        lib.callback.await('lunatic_admin:action', false, 'adminmode.toggle', {})
        return showQuick()
    end

    closeQuick()
    OpenPanelOn(data.id)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        closeQuick()
    end
end)
