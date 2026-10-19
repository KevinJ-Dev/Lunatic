-- Recelleur côté jeu : PNJ posés aux emplacements du panel, [E] pour revendre (pas de blip).

local fence = { items = {}, locations = {} }
local peds = {}

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function money(amount)
    return ('%s $'):format(tostring(math.floor(amount or 0)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', ''))
end

local function clearPeds()
    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped) then
            DeletePed(ped)
        end
    end

    peds = {}
end

-- PNJ locaux (non synchronisés), immobiles et invulnérables
local function spawnPeds()
    clearPeds()

    for _, location in ipairs(fence.locations or {}) do
        local model = joaat(location.ped)

        if IsModelInCdimage(model) and pcall(lib.requestModel, model, 5000) then
            local ped = CreatePed(4, model, location.x, location.y, location.z, location.h or 0.0, false, true)
            SetEntityInvincible(ped, true)
            FreezeEntityPosition(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedCanRagdoll(ped, false)
            TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_SMOKING', 0, true)
            SetModelAsNoLongerNeeded(model)
            peds[#peds + 1] = ped
        end
    end
end

local function load(value)
    fence = type(value) == 'table' and value or { items = {}, locations = {} }
    CreateThread(spawnPeds)
end

AddStateBagChangeHandler('lunaticFence', 'global', function(_, _, value)
    load(value)
end)

CreateThread(function()
    load(GlobalState.lunaticFence)
end)

local function openFence(location)
    local data = lib.callback.await('lunatic_illegal:fenceOpen', false, location.id)

    if not data or not data.ok then
        return notify(data and data.error or 'Le recelleur ne répond pas.', 'error')
    end

    local options = {}

    for _, offer in ipairs(data.offers) do
        options[#options + 1] = {
            title = ('%s × %d'):format(offer.label, offer.count),
            description = ('%s l\'unité · %s'):format(money(offer.price), offer.category),
            image = ('nui://ox_inventory/web/images/%s.png'):format(offer.item),
            icon = 'sack-dollar',
            onSelect = function()
                local input = lib.inputDialog(offer.label, { { type = 'number', label = 'Quantité à revendre', default = offer.count, min = 1, max = offer.count, required = true } })

                if not input or not input[1] then
                    return openFence(location)
                end

                local result = lib.callback.await('lunatic_illegal:fenceSell', false, location.id, offer.id, math.floor(input[1]))

                if result and result.ok then
                    notify(('%d × %s revendu pour %s.'):format(result.quantity, result.label, money(result.total)), 'success')
                else
                    notify(result and result.error or 'Revente impossible.', 'error')
                end

                openFence(location)
            end,
        }
    end

    if #options == 0 then
        options[1] = { title = "Rien qui m'intéresse sur toi.", readOnly = true, icon = 'face-meh' }
    end

    lib.registerContext({ id = 'li_fence', title = 'Recelleur', options = options })
    lib.showContext('li_fence')
end

-- [E] près d'un recelleur
CreateThread(function()
    local shown = false

    while true do
        local sleep = 1000
        local coords = GetEntityCoords(PlayerPedId())
        local near

        for _, location in ipairs(fence.locations or {}) do
            local distance = #(coords - vector3(location.x, location.y, location.z))

            if distance < 10.0 then
                sleep = 0

                if distance < Config.FenceDistance then
                    near = location
                end
            end
        end

        if near then
            if not shown then
                shown = true
                lib.showTextUI('[E] Parler au recelleur')
            end

            if IsControlJustReleased(0, 38) and not IsPedInAnyVehicle(PlayerPedId(), false) then
                openFence(near)
            end
        elseif shown then
            shown = false
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clearPeds()
        lib.hideTextUI()
    end
end)
