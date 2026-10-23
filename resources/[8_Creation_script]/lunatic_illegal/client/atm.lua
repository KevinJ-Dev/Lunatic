-- Braquage ATM côté client : devant un distributeur, avec l'outil demandé sur soi, [E] le pirate.
-- Mini-jeu ox_lib selon la difficulté réglée, puis les billets sortent (cercle de progression, sans bouger).
-- Le serveur revérifie tout et paie.

local cfg = { enabled = false, tool = '' }
local busy = false
local promptText = nil

local DIFFICULTY = {
    easy = { 'easy', 'easy' },
    medium = { 'easy', 'medium', 'medium' },
    hard = { 'medium', 'hard', 'hard' },
}

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function showPrompt(text)
    if promptText ~= text then
        promptText = text
        lib.showTextUI(text)
    end
end

local function hidePrompt()
    if promptText then
        promptText = nil
        lib.hideTextUI()
    end
end

local function loadConfig()
    local result = lib.callback.await('lunatic_illegal:atmConfig', false)

    if type(result) == 'table' then
        cfg = result
    end
end

-- Au démarrage puis chaque minute (au cas où le panel n'était pas encore prêt), et à chaque changement dans le panel
CreateThread(function()
    Wait(3000)

    while true do
        loadConfig()
        Wait(60000)
    end
end)

RegisterNetEvent('lunatic_illegal:atmConfigChanged', loadConfig)

local hashes = {}

for _, model in ipairs(Config.AtmModels) do
    hashes[#hashes + 1] = joaat(model)
end

-- Distributeur le plus proche (à moins de 2 m)
local function nearestAtm(coords)
    for _, hash in ipairs(hashes) do
        local object = GetClosestObjectOfType(coords.x, coords.y, coords.z, 2.0, hash, false, false, false)

        if object ~= 0 then
            return object
        end
    end
end

local function hasTool()
    return cfg.tool == '' or (exports.ox_inventory:Search('count', cfg.tool) or 0) > 0
end

local function hackAtm(atm)
    busy = true
    hidePrompt()

    local ped = PlayerPedId()
    local coords = GetEntityCoords(atm)
    local res = lib.callback.await('lunatic_illegal:atmStart', false, coords)

    if not res or not res.ok then
        notify(res and res.error or 'Impossible pour le moment.', 'error')
        Wait(1000)
        busy = false
        return
    end

    TaskTurnPedToFaceEntity(ped, atm, 800)
    Wait(800)
    TaskStartScenarioInPlace(ped, 'PROP_HUMAN_ATM', 0, true)

    local success = lib.skillCheck(DIFFICULTY[res.difficulty] or DIFFICULTY.medium, { 'e' })
    local hacked = lib.callback.await('lunatic_illegal:atmHacked', false, success)

    if not hacked or not hacked.ok then
        ClearPedTasks(ped)
        notify(hacked and hacked.error or 'Piratage interrompu.', 'error')
        busy = false
        return
    end

    if hacked.failed then
        ClearPedTasks(ped)
        notify(hacked.broken and ('Piratage raté : %s a lâché.'):format(hacked.broken) or 'Piratage raté.', 'error')
        Wait(1000)
        busy = false
        return
    end

    -- Les billets sortent : ne pas bouger jusqu'au bout
    local done = lib.progressCircle({
        duration = hacked.duration * 1000,
        label = 'Les billets sortent…',
        position = 'bottom',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    ClearPedTasks(ped)

    if not done then
        TriggerServerEvent('lunatic_illegal:atmCancel')
        notify('Vous êtes parti : les billets sont restés dans la machine.', 'error')
    else
        local result = lib.callback.await('lunatic_illegal:atmFinish', false)

        if result and result.ok then
            notify(('Distributeur vidé : %s en argent sale%s.'):format(result.reward, #result.loot > 0 and (', ' .. table.concat(result.loot, ', ')) or ''), 'success')
        else
            notify(result and result.error or 'Piratage raté.', 'error')
        end
    end

    Wait(1000)
    busy = false
end

CreateThread(function()
    while true do
        local wait = 500
        local atm = nil

        if cfg.enabled and not busy then
            local ped = PlayerPedId()

            if not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
                atm = nearestAtm(GetEntityCoords(ped))
            end
        end

        if atm and hasTool() then
            showPrompt('[E] Pirater le distributeur')
            local untilAt = GetGameTimer() + 500

            while GetGameTimer() < untilAt and not busy do
                if IsControlJustPressed(0, 38) then
                    hackAtm(atm)
                    break
                end

                Wait(0)
            end

            wait = 0
        else
            hidePrompt()
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        hidePrompt()
    end
end)
