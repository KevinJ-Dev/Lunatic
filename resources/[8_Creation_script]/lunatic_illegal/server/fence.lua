-- Recelleur côté jeu : revente des objets du catalogue (GlobalState.lunaticFence, géré dans le panel).
-- Le serveur vérifie la distance au PNJ et la quantité possédée avant de payer.

local ox = exports.ox_inventory

local function fail(message)
    return { ok = false, error = message }
end

local function locationNear(src, locationId)
    local fence = GlobalState.lunaticFence or {}

    for _, location in ipairs(fence.locations or {}) do
        if location.id == tonumber(locationId) then
            local ped = GetPlayerPed(src)

            if ped and ped ~= 0 and #(GetEntityCoords(ped) - vector3(location.x, location.y, location.z)) <= Config.FenceDistance + 2.0 then
                return location
            end

            return nil
        end
    end
end

local function canUse(src)
    return not Config.FenceCrewOnly or CrewOf(src) ~= nil
end

lib.callback.register('lunatic_illegal:fenceOpen', function(src, locationId)
    if not locationNear(src, locationId) then
        return fail('Vous êtes trop loin.')
    end

    if not canUse(src) then
        return fail("Le recelleur ne traite qu'avec les crews.")
    end

    local offers = {}

    for _, entry in ipairs((GlobalState.lunaticFence or {}).items or {}) do
        local count = ox:GetItemCount(src, entry.item) or 0

        if count > 0 then
            local item = ox:Items(entry.item)
            offers[#offers + 1] = { id = entry.id, item = entry.item, label = item and item.label or entry.item, price = entry.price, category = entry.category, count = count }
        end
    end

    -- Tablette chiffrée à vendre aux membres de crew (déjà liée à leur crew)
    local tablet = CrewOf(src) and Config.TabletPrice > 0 and { price = Config.TabletPrice } or nil

    return { ok = true, offers = offers, tablet = tablet }
end)

lib.callback.register('lunatic_illegal:fenceTablet', function(src, locationId)
    if not locationNear(src, locationId) then
        return fail('Vous êtes trop loin.')
    end

    local crew = CrewOf(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not crew or not xPlayer or Config.TabletPrice <= 0 then
        return fail("Le recelleur ne vend ses tablettes qu'aux crews.")
    end

    local account = xPlayer.getAccount(Config.TabletAccount)

    if not account or account.money < Config.TabletPrice then
        return fail("Vous n'avez pas assez d'argent sale.")
    end

    if not ox:CanCarryItem(src, Config.TabletItem, 1) then
        return fail("Vous n'avez pas assez de place.")
    end

    xPlayer.removeAccountMoney(Config.TabletAccount, Config.TabletPrice, 'Recelleur : tablette')
    ox:AddItem(src, Config.TabletItem, 1, { crew = crew.id })

    return { ok = true }
end)

lib.callback.register('lunatic_illegal:fenceSell', function(src, locationId, itemId, quantity)
    if not locationNear(src, locationId) then
        return fail('Vous êtes trop loin.')
    end

    if not canUse(src) then
        return fail("Le recelleur ne traite qu'avec les crews.")
    end

    local entry

    for _, candidate in ipairs((GlobalState.lunaticFence or {}).items or {}) do
        if candidate.id == tonumber(itemId) then
            entry = candidate
        end
    end

    quantity = tonumber(quantity)

    if not entry or not quantity or quantity ~= math.floor(quantity) or quantity < 1 then
        return fail('Quantité invalide.')
    end

    if (ox:GetItemCount(src, entry.item) or 0) < quantity then
        return fail("Vous n'avez pas autant d'objets.")
    end

    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not ox:RemoveItem(src, entry.item, quantity) then
        return fail('Revente impossible.')
    end

    local total = entry.price * quantity

    if total > 0 then
        xPlayer.addAccountMoney(Config.FenceAccount, total, 'Recelleur')
    end

    local item = ox:Items(entry.item)
    GameLog('illegal', 'info', src, 'illegal.fence_sell', item and item.label or entry.item, { quantity = quantity, total = total })
    return { ok = true, total = total, quantity = quantity, label = item and item.label or entry.item }
end)
