-- Tablette des crews : ouverte depuis l'objet « Tablette » de l'inventaire (export openTablet, voir ox_inventory/data/items.lua).
-- Onglets Crew, Territoires, Marché noir ; récupération des commandes du marché noir aux points de livraison.

local open = false
local prop
local orders = {} -- commandes du crew en attente (points de livraison des commandes prêtes)

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

---------------------------------------------------------------------
-- Animation : tablette en main
---------------------------------------------------------------------

local function startAnimation()
    local ped = PlayerPedId()
    local dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base'

    lib.requestAnimDict(dict)
    lib.requestModel(`prop_cs_tablet`)

    prop = CreateObject(`prop_cs_tablet`, GetEntityCoords(ped), true, true, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 60309), 0.03, 0.002, -0.0, 10.0, 160.0, 0.0, true, false, false, false, 2, true)
    SetModelAsNoLongerNeeded(`prop_cs_tablet`)
    TaskPlayAnim(ped, dict, 'base', 3.0, 3.0, -1, 49, 0, false, false, false)
end

local function stopAnimation()
    ClearPedSecondaryTask(PlayerPedId())

    if prop and DoesEntityExist(prop) then
        DeleteEntity(prop)
    end

    prop = nil
end

local function closeTablet()
    if not open then
        return
    end

    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeTablet' })
    stopAnimation()
end

-- Appelé par ox_inventory quand le joueur utilise l'objet « Tablette » : le serveur vérifie que la tablette
-- appartient au crew du joueur (une tablette neuve s'initialise pour son crew à la première ouverture)
exports('openTablet', function(_, slot)
    if open then
        return
    end

    local result = lib.callback.await('lunatic_illegal:tabletOpen', false, slot and slot.slot)

    if not result or not result.ok then
        return notify(result and result.error or 'La tablette ne répond pas.', 'error')
    end

    if result.bound then
        notify('Tablette initialisée : elle ne fonctionnera que pour votre crew.', 'success')
    end

    if IsPedInAnyVehicle(PlayerPedId(), false) == false then
        startAnimation()
    end

    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openTablet', currency = GlobalState.lunaticCurrency or '$' })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        closeTablet()
    end
end)

---------------------------------------------------------------------
-- Rappels de l'interface
---------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    closeTablet()
end)

RegisterNUICallback('load', function(_, cb)
    local crew = lib.callback.await('lunatic_illegal:crew', false)

    if not crew or not crew.ok or not crew.crew then
        cb({ ok = false, error = crew and crew.error or "Vous ne faites plus partie d'un crew." })
        return closeTablet()
    end

    local territories = lib.callback.await('lunatic_illegal:territories', false)
    local market = lib.callback.await('lunatic_illegal:market', false)
    local contracts = lib.callback.await('lunatic_illegal:contracts', false)

    -- Vol sur commande : nom du véhicule tel qu'affiché dans le jeu
    local function vehicleLabel(model)
        local name = GetDisplayNameFromVehicleModel(joaat(model))
        local text = GetLabelText(name)
        return text ~= 'NULL' and text or model
    end

    if contracts and contracts.ok then
        for _, offer in ipairs(contracts.offers or {}) do
            if offer.type == 'theft' and offer.model then
                offer.title = ('Vol sur commande : %s'):format(vehicleLabel(offer.model))
            end
        end

        if contracts.active and contracts.active.model then
            contracts.active.title = ('Vol sur commande : %s'):format(vehicleLabel(contracts.active.model))
        end
    end

    if market and market.ok then
        orders = market.orders or {}
    end

    cb({ ok = true, crew = crew.crew, me = crew.me, territories = territories and territories.territories or {}, market = market, contracts = contracts })
end)

RegisterNUICallback('contractAccept', function(data, cb)
    local result = lib.callback.await('lunatic_illegal:contractAccept', false, data.offerId)

    if result and result.ok and result.contract then
        SetNewWaypoint(result.contract.objective.x + 0.0, result.contract.objective.y + 0.0)
    end

    cb(result or { ok = false })
end)

RegisterNUICallback('contractAbandon', function(_, cb)
    cb(lib.callback.await('lunatic_illegal:contractAbandon', false) or { ok = false })
end)

RegisterNUICallback('buy', function(data, cb)
    local result = lib.callback.await('lunatic_illegal:marketBuy', false, data.itemId, data.count)
    cb(result or { ok = false })
end)

RegisterNUICallback('gps', function(data, cb)
    SetNewWaypoint(tonumber(data.x) + 0.0, tonumber(data.y) + 0.0)
    cb({ ok = true })
end)

RegisterNUICallback('nearby', function(_, cb)
    local list = {}

    for _, nearby in ipairs(lib.getNearbyPlayers(GetEntityCoords(PlayerPedId()), Config.InviteDistance, false)) do
        local serverId = GetPlayerServerId(nearby.id)
        local state = Player(serverId).state
        local name = state.firstName and ('%s %s'):format(state.firstName, state.lastName or '') or GetPlayerName(nearby.id)
        list[#list + 1] = { id = serverId, name = name, inCrew = state.crew ~= nil }
    end

    cb({ ok = true, players = list })
end)

RegisterNUICallback('invite', function(data, cb)
    cb(lib.callback.await('lunatic_illegal:invite', false, data.serverId) or { ok = false })
end)

RegisterNUICallback('setRank', function(data, cb)
    cb(lib.callback.await('lunatic_illegal:setRank', false, data.identifier, data.rank) or { ok = false })
end)

RegisterNUICallback('kick', function(data, cb)
    cb(lib.callback.await('lunatic_illegal:kick', false, data.identifier) or { ok = false })
end)

RegisterNUICallback('leave', function(_, cb)
    cb(lib.callback.await('lunatic_illegal:leave', false) or { ok = false })
end)

---------------------------------------------------------------------
-- Points de livraison : marqueur et [E] quand une commande du crew est prête
---------------------------------------------------------------------

-- Les commandes passées par les autres membres arrivent par ce rafraîchissement
CreateThread(function()
    while true do
        if LocalPlayer.state.crew then
            local result = lib.callback.await('lunatic_illegal:marketOrders', false)
            orders = type(result) == 'table' and result or {}
        else
            orders = {}
        end

        Wait(Config.MarketRefresh * 1000)
    end
end)

local collecting = false

local function collect(order)
    collecting = true

    local done = lib.progressBar({
        duration = 4000,
        label = 'Récupération du colis',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'anim@heists@box_carry@', clip = 'idle' },
    })

    if done then
        local result = lib.callback.await('lunatic_illegal:marketCollect', false, order.id)

        if result and result.ok then
            notify(('Colis récupéré : %d × %s.'):format(result.count, result.label), 'success')
            orders = lib.callback.await('lunatic_illegal:marketOrders', false) or {}
        else
            notify(result and result.error or 'Récupération impossible.', 'error')
        end
    end

    collecting = false
end

CreateThread(function()
    local shown

    while true do
        local sleep = 1000
        local text, action

        if not collecting and next(orders) then
            local coords = GetEntityCoords(PlayerPedId())

            for _, order in ipairs(orders) do
                if order.ready and order.dropoff then
                    local point = vector3(order.dropoff.x, order.dropoff.y, order.dropoff.z)
                    local distance = #(coords - point)

                    if distance < 40.0 then
                        sleep = 0
                        DrawMarker(2, point.x, point.y, point.z + 0.6, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.35, 0.35, 0.35, 242, 194, 107, 180, true, true, 2, false, nil, nil, false)

                        if distance < Config.MarketPickupDistance then
                            text, action = ('[E] Récupérer la commande : %d × %s'):format(order.count, order.label), function() collect(order) end
                        end
                    end
                end
            end
        end

        if text then
            if shown ~= text then
                shown = text
                lib.showTextUI(text)
            end

            if IsControlJustReleased(0, 38) then
                lib.hideTextUI()
                shown = nil
                CreateThread(action)
            end
        elseif shown then
            shown = nil
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)

-- Commande arrivée : message à tous les membres connectés, point GPS pour celui qui l'a passée
RegisterNetEvent('lunatic_illegal:orderReady', function(order)
    notify(('Livraison arrivée : %d × %s au point « %s ». À récupérer dans les %d min.'):format(order.count, order.label, order.dropoff.label, math.floor(order.expiresIn / 60)), 'success')

    if order.buyer then
        SetNewWaypoint(order.dropoff.x + 0.0, order.dropoff.y + 0.0)
        notify('Point de livraison ajouté à votre GPS.', 'info')
    end

    orders = lib.callback.await('lunatic_illegal:marketOrders', false) or orders

    if open then
        SendNUIMessage({ action = 'refresh' })
    end
end)

-- Alerte police : récupération d'un colis suspect
RegisterNetEvent('lunatic_illegal:marketAlert', function(alert)
    notify('Signalement : échange de colis suspect dans le secteur indiqué sur la carte.', 'error')
    local area = AddBlipForRadius(alert.x + 0.0, alert.y + 0.0, 0.0, 90.0)
    SetBlipColour(area, 1)
    SetBlipAlpha(area, 120)
    local center = AddBlipForCoord(alert.x + 0.0, alert.y + 0.0, 0.0)
    SetBlipSprite(center, 478)
    SetBlipColour(center, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Colis suspect')
    EndTextCommandSetBlipName(center)

    SetTimeout(Config.AlertDuration * 1000, function()
        RemoveBlip(area)
        RemoveBlip(center)
    end)
end)
