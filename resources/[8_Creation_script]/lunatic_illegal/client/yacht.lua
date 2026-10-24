-- Braquage Yacht côté client : en approchant du yacht (150 m), le premier membre d'un crew éligible fait apparaître
-- les gardes armés (en réseau, hostiles aux joueurs). Au coffre : [E] le pirater (mini-jeu), puis le vider sans bouger.
-- Le serveur revérifie tout.

local cfg = { enabled = false, points = {} }
local busy = false
local promptText = nil
local asked = {} -- yachts dont l'approche a déjà été signalée (remis à zéro en s'éloignant)

local GUARDS = joaat('LUNATIC_YACHT_GUARDS')

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
    local result = lib.callback.await('lunatic_illegal:yachtConfig', false)

    if type(result) == 'table' then
        cfg = result
    end
end

CreateThread(function()
    Wait(3000)

    while true do
        loadConfig()
        Wait(60000)
    end
end)

RegisterNetEvent('lunatic_illegal:yachtConfigChanged', loadConfig)

local function hasTool()
    return not cfg.tool or cfg.tool == '' or (exports.ox_inventory:Search('count', cfg.tool) or 0) > 0
end

-- Gardes armés sur le pont, autour du coffre, hostiles aux joueurs
local function spawnGuards(point, settings)
    AddRelationshipGroup('LUNATIC_YACHT_GUARDS')
    SetRelationshipBetweenGroups(5, GUARDS, `PLAYER`)
    SetRelationshipBetweenGroups(5, `PLAYER`, GUARDS)

    local model = joaat(settings.model)

    if not pcall(lib.requestModel, model, 5000) then
        return
    end

    local netIds = {}

    for _ = 1, settings.count do
        local angle = math.random() * math.pi * 2
        local distance = math.random(3, 12)
        local x, y = point.x + math.cos(angle) * distance, point.y + math.sin(angle) * distance
        local found, ground = GetGroundZFor_3dCoord(x, y, point.z + 2.0, false)
        local z = found and math.abs(ground - point.z) < 4.0 and ground or point.z
        local ped = CreatePed(4, model, x, y, z, math.random(0, 359) + 0.0, true, true)

        SetEntityAsMissionEntity(ped, true, true)
        SetPedRelationshipGroupHash(ped, GUARDS)
        GiveWeaponToPed(ped, joaat(settings.weapon), 250, false, true)
        SetPedArmour(ped, 75)
        SetPedAccuracy(ped, 40)
        SetPedCombatAbility(ped, 2)
        SetPedCombatRange(ped, 1)
        SetPedCombatAttributes(ped, 46, true)
        SetPedFleeAttributes(ped, 0, false)
        SetPedDropsWeaponsWhenDead(ped, false)
        TaskCombatHatedTargetsAroundPed(ped, 100.0, 0)

        local netId = NetworkGetNetworkIdFromEntity(ped)
        SetNetworkIdCanMigrate(netId, true)
        netIds[#netIds + 1] = netId
    end

    SetModelAsNoLongerNeeded(model)
    TriggerServerEvent('lunatic_illegal:yachtGuardsSpawned', point.id, netIds)
end

local function openSafe(point)
    busy = true
    hidePrompt()

    local res = lib.callback.await('lunatic_illegal:yachtOpen', false, point.id)

    if not res or not res.ok then
        notify(res and res.error or 'Impossible pour le moment.', 'error')
        Wait(1000)
        busy = false
        return
    end

    local ped = PlayerPedId()
    TaskStartScenarioInPlace(ped, 'PROP_HUMAN_BUM_BIN', 0, true)

    local success = lib.skillCheck(DIFFICULTY[res.difficulty] or DIFFICULTY.hard, { 'e' })
    local hacked = lib.callback.await('lunatic_illegal:yachtHacked', false, success)

    if not hacked or not hacked.ok or hacked.failed then
        ClearPedTasks(ped)
        notify(hacked and hacked.broken and ('Piratage raté : %s a lâché.'):format(hacked.broken) or (hacked and hacked.error) or 'Piratage raté.', 'error')
        busy = false
        return
    end

    local done = lib.progressCircle({
        duration = hacked.duration * 1000,
        label = 'Vidage du coffre…',
        position = 'bottom',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    ClearPedTasks(ped)

    if not done then
        TriggerServerEvent('lunatic_illegal:yachtCancel')
        notify('Vous avez lâché le coffre.', 'error')
    else
        local result = lib.callback.await('lunatic_illegal:yachtFinish', false)

        if result and result.ok then
            notify(('Coffre vidé : %s en argent sale%s.'):format(result.reward, #result.loot > 0 and (', ' .. table.concat(result.loot, ', ')) or ''), 'success')
        else
            notify(result and result.error or 'Braquage raté.', 'error')
        end
    end

    busy = false
end

CreateThread(function()
    while true do
        local wait = 1000
        local prompt = nil

        if cfg.enabled and not busy then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)

            for _, point in ipairs(cfg.points or {}) do
                local distance = #(coords - vector3(point.x, point.y, point.z))

                -- Approche : le braquage commence, les gardes apparaissent (une fois par passage)
                if distance < 150.0 and not asked[point.id] then
                    asked[point.id] = true

                    CreateThread(function()
                        local res = lib.callback.await('lunatic_illegal:yachtApproach', false, point.id)

                        if res and res.ok and res.guards and res.guards.count > 0 then
                            spawnGuards(point, res.guards)
                        end
                    end)
                elseif distance > 300.0 then
                    asked[point.id] = nil
                end

                if distance < 20.0 then
                    wait = 0

                    if distance < 2.0 and hasTool() and not IsPedInAnyVehicle(ped, false) then
                        prompt = '[E] Pirater le coffre'

                        if IsControlJustPressed(0, 38) then
                            openSafe(point)
                        end
                    end
                end
            end
        end

        if prompt then
            showPrompt(prompt)
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
