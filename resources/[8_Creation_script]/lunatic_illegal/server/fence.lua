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
    return not Config.FenceCrewOnly or Player(src).state.crew ~= nil
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

    return { ok = true, offers = offers }
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
    return { ok = true, total = total, quantity = quantity, label = item and item.label or entry.item }
end)
