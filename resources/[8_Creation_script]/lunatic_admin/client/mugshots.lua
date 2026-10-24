-- Mugshot : photo du visage demandée par le serveur (première connexion du personnage, ou « Refaire » dans la tuile Images).
-- Le portrait GTA (nui-img) est converti en image par la page du panel (chargée pour tous les joueurs, même fermée),
-- puis envoyé au serveur qui l'enregistre en base.

local capturing = false
local pending -- portrait en cours de conversion

local function release()
    if pending then
        UnregisterPedheadshot(pending)
        pending = nil
    end

    capturing = false
end

RegisterNetEvent('lunatic_admin:takeMugshot', function()
    if capturing then
        return
    end

    capturing = true
    local ped = PlayerPedId()
    local handle = RegisterPedheadshot(ped)
    local timeout = GetGameTimer() + 5000

    while (not IsPedheadshotReady(handle) or not IsPedheadshotValid(handle)) and GetGameTimer() < timeout do
        Wait(50)
    end

    if not IsPedheadshotReady(handle) or not IsPedheadshotValid(handle) then
        UnregisterPedheadshot(handle)
        capturing = false
        TriggerServerEvent('lunatic_admin:mugshotFailed', 'portrait GTA indisponible')
        return
    end

    pending = handle
    local txd = GetPedheadshotTxdString(handle)
    SendNUIMessage({ action = 'mugshotCapture', url = ('https://nui-img/%s/%s'):format(txd, txd) })

    -- Sans réponse de la page : on libère le portrait
    SetTimeout(10000, function()
        if pending == handle then
            release()
        end
    end)
end)

RegisterNUICallback('mugshotData', function(data, cb)
    cb({ ok = true })

    if not pending then
        return
    end

    release()

    if type(data.image) == 'string' then
        -- Envoi étalé : quelques dizaines de Ko sans bloquer le réseau
        TriggerLatentServerEvent('lunatic_admin:mugshot', 20000, data.image)
    else
        print(('^3[lunatic_admin] Mugshot : conversion impossible (%s).^0'):format(type(data.error) == 'string' and data.error or 'inconnue'))
        TriggerServerEvent('lunatic_admin:mugshotFailed', type(data.error) == 'string' and data.error or 'conversion impossible')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        release()
    end
end)
