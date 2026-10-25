-- Récoltes et transformations, côté client (provisoire, en attendant la passe « full ox » des interactions) :
-- blips, marqueur au sol, [E] puis barre de progression ox_lib ; le serveur valide et donne les objets.

local blips = {}
local working = false

local BLIP = { harvest = { sprite = 285, color = 2 }, process = { sprite = 566, color = 3 } }

local function clearBlips()
    for _, blip in ipairs(blips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    blips = {}
end

local function drawBlips(list)
    clearBlips()

    for _, point in ipairs(type(list) == 'table' and list or {}) do
        if point.blip then
            local style = BLIP[point.kind] or BLIP.harvest
            local blip = AddBlipForCoord(point.x + 0.0, point.y + 0.0, point.z + 0.0)
            SetBlipSprite(blip, style.sprite)
            SetBlipColour(blip, style.color)
            SetBlipScale(blip, 0.7)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(point.label)
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end
    end
end

AddStateBagChangeHandler('lunaticHarvest', 'global', function(_, _, value)
    drawBlips(value)
end)

local function work(point)
    working = true
    local start = lib.callback.await('lunatic_gameplay:harvestStart', false, point.id)

    if not start or not start.ok then
        working = false
        return Notify(start and start.error or 'Impossible ici.', 'error')
    end

    local done = lib.progressBar({
        duration = start.duration * 1000,
        label = start.kind == 'harvest' and ('Récolte : %s'):format(point.label) or ('Transformation : %s'):format(point.label),
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = start.kind == 'harvest' and { scenario = 'WORLD_HUMAN_GARDENER_PLANT' } or { dict = 'mini@repair', clip = 'fixing_a_ped' },
    })

    ClearPedTasks(PlayerPedId())
    local result = lib.callback.await('lunatic_gameplay:harvestFinish', false, not done)
    working = false

    if not done then
        return Notify('Action annulée.', 'info')
    end

    if result and result.ok then
        Notify(result.message, 'success')
    else
        Notify(result and result.error or 'Échec.', 'error')
    end
end

CreateThread(function()
    drawBlips(GlobalState.lunaticHarvest)

    while true do
        local list = GlobalState.lunaticHarvest
        local wait = 1000

        if type(list) == 'table' and not working then
            local coords = GetEntityCoords(PlayerPedId())

            for _, point in ipairs(list) do
                local distance = #(coords - vector3(point.x, point.y, point.z))

                if distance < 25.0 then
                    wait = 0
                    DrawMarker(1, point.x, point.y, point.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, point.radius * 2.0, point.radius * 2.0, 0.4,
                        point.kind == 'harvest' and 95 or 107, point.kind == 'harvest' and 211 or 184, point.kind == 'harvest' and 160 or 242, 90, false, false, 2, false, nil, nil, false)

                    if distance <= point.radius then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName(('~INPUT_CONTEXT~ %s'):format(point.kind == 'harvest' and ('Récolter (%s)'):format(point.label) or ('Transformer (%s)'):format(point.label)))
                        EndTextCommandDisplayHelp(0, false, true, -1)

                        if IsControlJustReleased(0, 38) and not IsPedInAnyVehicle(PlayerPedId(), false) then
                            CreateThread(function() work(point) end)
                        end
                    end
                end
            end
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clearBlips()
    end
end)
