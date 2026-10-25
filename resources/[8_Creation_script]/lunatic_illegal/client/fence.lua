-- Recelleur côté jeu : PNJ posés aux emplacements du panel, [E] pour revendre.
-- Rayon du [E] et blip (caché par défaut) réglés par emplacement dans la tuile Interactions.

local fence = { items = {}, locations = {} }
local peds = {}

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function money(amount)
    return ('%s %s'):format(tostring(math.floor(amount or 0)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', ''), GlobalState.lunaticCurrency or '$')
end

local function deletePed(id)
    local ped = peds[id]

    if ped and DoesEntityExist(ped) then
        DeleteEntity(ped)
    end

    peds[id] = nil
end

local function clearPeds()
    for id in pairs(peds) do
        deletePed(id)
    end
end

-- PNJ local (non synchronisé), immobile et invulnérable. Marqué « entité de mission » :
-- sans ça, le jeu supprime de lui-même les PNJ ordinaires.
local function createPed(location)
    local model = joaat(location.ped)

    if not IsModelInCdimage(model) or not IsModelAPed(model) then
        print(("[lunatic_illegal] Recelleur %d : le modèle « %s » n'existe pas."):format(location.id, location.ped))
        return
    end

    RequestModel(model)
    local timeout = GetGameTimer() + 10000

    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        Wait(50)
    end

    if not HasModelLoaded(model) then
        print(('[lunatic_illegal] Recelleur %d : le modèle « %s » ne se charge pas.'):format(location.id, location.ped))
        return
    end

    -- L'emplacement est enregistré au sol : c'est la position des pieds du PNJ
    local ped = CreatePed(4, model, location.x, location.y, location.z, location.h or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)

    if not ped or ped == 0 then
        print(('[lunatic_illegal] Recelleur %d : création du PNJ impossible.'):format(location.id))
        return
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityHeading(ped, location.h or 0.0)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_SMOKING', 0, true)
    peds[location.id] = ped
end

local blips = {}

local function refreshBlips()
    for _, blip in ipairs(blips) do
        RemoveBlip(blip)
    end

    blips = {}

    for _, location in ipairs(fence.locations or {}) do
        if location.showBlip then
            local blip = AddBlipForCoord(location.x, location.y, location.z)
            SetBlipSprite(blip, 500)
            SetBlipColour(blip, 1)
            SetBlipScale(blip, 0.7)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName('Recelleur')
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end
    end
end

local function load(value)
    fence = type(value) == 'table' and value or { items = {}, locations = {} }
    refreshBlips()
    -- Les PNJ sont recréés (position ou modèle peut-être changés) par la boucle ci-dessous
    clearPeds()
    print(('[lunatic_illegal] Recelleur : %d emplacement(s), %d objet(s) au catalogue.'):format(#(fence.locations or {}), #(fence.items or {})))
end

-- PNJ créés seulement à moins de 80 m du joueur, supprimés au-delà
CreateThread(function()
    while true do
        local coords = GetEntityCoords(PlayerPedId())
        local wanted = {}

        for _, location in ipairs(fence.locations or {}) do
            if #(coords - vector3(location.x, location.y, location.z)) < 80.0 then
                wanted[location.id] = true

                if not peds[location.id] or not DoesEntityExist(peds[location.id]) then
                    createPed(location)
                end
            end
        end

        for id in pairs(peds) do
            if not wanted[id] then
                deletePed(id)
            end
        end

        Wait(2000)
    end
end)

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
            description = ("%s l'unité · %s"):format(money(offer.price), offer.category),
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

    -- Membres de crew : une tablette chiffrée de rechange
    if data.tablet then
        table.insert(options, 1, {
            title = 'Acheter une tablette chiffrée',
            description = ("%s en argent sale · elle ne s'allumera que pour votre crew"):format(money(data.tablet.price)),
            image = 'nui://ox_inventory/web/images/crew_tablet.png',
            icon = 'tablet-screen-button',
            onSelect = function()
                local result = lib.callback.await('lunatic_illegal:fenceTablet', false, location.id)

                if result and result.ok then
                    notify('Tablette chiffrée achetée.', 'success')
                else
                    notify(result and result.error or 'Achat impossible.', 'error')
                end

                openFence(location)
            end,
        })
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

                if distance < (tonumber(location.radius) or Config.FenceDistance) then
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

        for _, blip in ipairs(blips) do
            RemoveBlip(blip)
        end
    end
end)
