-- Banque côté client : [E] au guichet des agences et devant les distributeurs, interface (html/) et relais de ses
-- demandes au serveur. Blips des agences : tuile Blips du panel (lunatic_admin).

local opened = nil -- 'bank' ou 'atm'
local shown = false
local atmHashes = {}

for _, model in ipairs(Config.AtmModels) do
    atmHashes[#atmHashes + 1] = joaat(model)
end

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function close()
    if not opened then
        return
    end

    if opened == 'atm' then
        ClearPedTasks(PlayerPedId())
    end

    opened = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    TriggerServerEvent('lunatic_bank:close')
end

local function show(kind, state)
    if not state or state.error then
        return notify(state and state.error or 'Banque indisponible.', 'error')
    end

    opened = kind
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', state = state })
end

local function openBank(index)
    show('bank', lib.callback.await('lunatic_bank:open', false, index))
end

local function openAtm(atm)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local state = lib.callback.await('lunatic_bank:openAtm', false, { x = coords.x, y = coords.y, z = coords.z })

    if state and not state.error then
        TaskTurnPedToFaceEntity(ped, atm, 600)
        Wait(600)
        TaskStartScenarioInPlace(ped, 'PROP_HUMAN_ATM', 0, true)
    end

    show('atm', state)
end

RegisterNUICallback('close', function(_, cb)
    cb({})
    close()
end)

-- Retrait, dépôt, virement, changement de compte ou de période : réponse du serveur renvoyée telle quelle à la page
for _, name in ipairs({ 'withdraw', 'deposit', 'transfer', 'state' }) do
    RegisterNUICallback(name, function(data, cb)
        local result = lib.callback.await('lunatic_bank:' .. name, false, data) or { error = 'Banque indisponible.' }

        if result.error then
            notify(result.error, 'error')
        elseif result.message then
            notify(result.message, 'success')
        end

        cb(result)
    end)
end

local function nearestAtm(coords)
    for _, hash in ipairs(atmHashes) do
        local object = GetClosestObjectOfType(coords.x, coords.y, coords.z, Config.AtmDistance, hash, false, false, false)

        if object ~= 0 then
            return object
        end
    end
end

local function prompt(label)
    if shown ~= label then
        shown = label
        lib.showTextUI(label)
    end
end

local function hidePrompt()
    if shown then
        shown = false
        lib.hideTextUI()
    end
end

-- Piratage possible (lunatic_illegal) : son message reprend déjà « [E] Distributeur »
local function hackPromptShown()
    if GetResourceState('lunatic_illegal') ~= 'started' then
        return false
    end

    local ok, value = pcall(function() return exports.lunatic_illegal:atmPromptShown() end)
    return ok and value == true
end

-- Guichet ou distributeur : [E]
CreateThread(function()
    while true do
        local wait = 500
        local ped = PlayerPedId()

        if not opened and not IsPedInAnyVehicle(ped, false) and not IsPedDeadOrDying(ped, true) then
            local coords = GetEntityCoords(ped)
            local bankIndex, atm = nil, nil

            for index, bank in ipairs(Banks()) do
                local distance = #(coords - vector3(bank.x, bank.y, bank.z))

                if distance < 15.0 then
                    wait = 250
                end

                if distance <= Config.Distance then
                    bankIndex = index
                    break
                end
            end

            if not bankIndex then
                atm = nearestAtm(coords)
            end

            if bankIndex or atm then
                wait = 0

                if bankIndex then
                    prompt(('[E] %s'):format(Banks()[bankIndex].label))
                elseif hackPromptShown() then
                    shown = false
                else
                    prompt('[E] Distributeur')
                end

                if IsControlJustReleased(0, 38) then
                    hidePrompt()

                    if bankIndex then
                        openBank(bankIndex)
                    else
                        openAtm(atm)
                    end
                end
            else
                hidePrompt()
            end
        else
            hidePrompt()
        end

        Wait(wait)
    end
end)

-- Interface ouverte : fermée si le joueur tombe ou ouvre le menu pause
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
        hidePrompt()
        close()
    end
end)
