-- Banque côté client : [E] au guichet des agences, interface (html/) et relais de ses demandes au serveur.
-- Blips des agences : tuile Blips du panel (lunatic_admin).

local opened = false
local shown = false

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function close()
    if not opened then
        return
    end

    opened = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerServerEvent('lunatic_bank:close')
end

local function open(index)
    local state = lib.callback.await('lunatic_bank:open', false, index)

    if not state or state.error then
        return notify(state and state.error or 'Banque indisponible.', 'error')
    end

    opened = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', state = state })
end

RegisterNUICallback('close', function(_, cb)
    cb({})
    close()
end)

-- Retrait, dépôt, virement, période du graphique : réponse du serveur renvoyée telle quelle à la page
for _, name in ipairs({ 'withdraw', 'deposit', 'transfer', 'chart' }) do
    RegisterNUICallback(name, function(data, cb)
        local payload = name == 'chart' and data.period or data
        local result = lib.callback.await('lunatic_bank:' .. name, false, payload) or { error = 'Banque indisponible.' }

        if result.error then
            notify(result.error, 'error')
        elseif result.message then
            notify(result.message, 'success')
        end

        cb(result)
    end)
end

-- Guichet : [E]
CreateThread(function()
    while true do
        local wait = 1000

        if not opened then
            local coords = GetEntityCoords(PlayerPedId())
            local near = nil

            for index, bank in ipairs(Banks()) do
                local distance = #(coords - vector3(bank.x, bank.y, bank.z))

                if distance < 15.0 then
                    wait = 250
                end

                if distance <= Config.Distance then
                    near = index
                    break
                end
            end

            if near then
                wait = 0
                local label = ('[E] %s'):format(Banks()[near].label)

                if shown ~= label then
                    shown = label
                    lib.showTextUI(label)
                end

                if IsControlJustReleased(0, 38) then
                    shown = false
                    lib.hideTextUI()
                    open(near)
                end
            elseif shown then
                shown = false
                lib.hideTextUI()
            end
        elseif shown then
            shown = false
            lib.hideTextUI()
        end

        Wait(wait)
    end
end)

-- Interface ouverte : fermée si le joueur s'éloigne ou tombe
CreateThread(function()
    while true do
        Wait(1000)

        if opened and (IsPedDeadOrDying(PlayerPedId(), true) or IsPauseMenuActive()) then
            close()
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if shown then
            lib.hideTextUI()
        end

        close()
    end
end)
