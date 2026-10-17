-- Lot 3 : fenêtre d'avertissement en plein écran, à fermer avec « J'ai compris »

WarningOpen = false

RegisterNetEvent('lunatic_admin:warning', function(data)
    if type(data) ~= 'table' or type(data.reason) ~= 'string' then
        return
    end

    WarningOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'warning', warning = { id = data.id, reason = data.reason, date = data.date } })
end)

RegisterNUICallback('warningAck', function(_, cb)
    WarningOpen = false

    -- Le panel staff ouvert garde la souris
    if not IsPanelOpen() then
        SetNuiFocus(false, false)
    end

    cb(1)
end)
