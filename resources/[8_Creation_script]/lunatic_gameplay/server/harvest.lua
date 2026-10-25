-- Récoltes et transformations (réglées dans le panel : tuile Autres → Récoltes, GlobalState.lunaticHarvest).
-- Le serveur vérifie tout : présence au point, métier, outil, limite par heure (× limite farm des abonnés),
-- place dans l'inventaire, durée écoulée, objets à transformer.

local ox = exports.ox_inventory
local busy = {}   -- joueur -> { id, at } action en cours
local counts = {} -- licence -> point -> { start, amount } (fenêtre d'une heure)

local function pointOf(id)
    for _, point in ipairs(GlobalState.lunaticHarvest or {}) do
        if point.id == id then
            return point
        end
    end
end

local function atPoint(src, point)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z)) <= point.radius + 2.0
end

local function hasJob(src, point)
    local job = point.data.job

    if not job or job == '' then
        return true
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer ~= nil and xPlayer.getJob().name == job
end

-- Limite par heure, multipliée par la « limite farm » de l'abonnement (tuile Boutique)
local function remaining(src, point)
    local limit = tonumber(point.data.limit) or 0

    if limit <= 0 then
        return math.huge
    end

    local tier = Player(src).state.premium
    local shop = GlobalState.lunaticShop
    local multiplier = tier and shop and shop.tiers and shop.tiers[tier] and tonumber(shop.tiers[tier].farmMultiplier) or 1
    local license = GetPlayerIdentifierByType(src, 'license') or tostring(src)
    local entry = counts[license] and counts[license][point.id]

    if not entry or os.time() - entry.start >= 3600 then
        return math.floor(limit * multiplier)
    end

    return math.max(0, math.floor(limit * multiplier) - entry.amount)
end

local function count(src, point, amount)
    local license = GetPlayerIdentifierByType(src, 'license') or tostring(src)
    counts[license] = counts[license] or {}
    local entry = counts[license][point.id]

    if not entry or os.time() - entry.start >= 3600 then
        entry = { start = os.time(), amount = 0 }
        counts[license][point.id] = entry
    end

    entry.amount = entry.amount + amount
end

local function check(src, point)
    if not point then
        return "Ce point n'est plus actif."
    end

    if not atPoint(src, point) then
        return 'Vous êtes trop loin.'
    end

    if not hasJob(src, point) then
        return 'Réservé à un métier.'
    end

    local data = point.data

    if point.kind == 'harvest' then
        if data.tool and data.tool ~= '' and (ox:Search(src, 'count', data.tool) or 0) < 1 then
            local tool = ox:Items(data.tool)
            return ('Il vous faut : %s.'):format(tool and tool.label or data.tool)
        end

        if remaining(src, point) <= 0 then
            return "Vous avez assez récolté ici pour l'heure : revenez plus tard."
        end

        if not ox:CanCarryItem(src, data.item, data.max) then
            return 'Votre inventaire est plein.'
        end
    else
        for _, entry in ipairs(data.inputs or {}) do
            if (ox:Search(src, 'count', entry.item) or 0) < entry.count then
                local item = ox:Items(entry.item)
                return ('Il vous faut %d × %s.'):format(entry.count, item and item.label or entry.item)
            end
        end

        if not ox:CanCarryItem(src, data.item, data.count) then
            return 'Votre inventaire est plein.'
        end
    end
end

lib.callback.register('lunatic_gameplay:harvestStart', function(src, id)
    local point = pointOf(tonumber(id))

    if busy[src] then
        return { ok = false, error = 'Action déjà en cours.' }
    end

    local err = check(src, point)

    if err then
        return { ok = false, error = err }
    end

    busy[src] = { id = point.id, at = GetGameTimer() + point.data.duration * 1000 - 750 }
    return { ok = true, duration = point.data.duration, kind = point.kind }
end)

lib.callback.register('lunatic_gameplay:harvestFinish', function(src, cancelled)
    local action = busy[src]
    busy[src] = nil

    if cancelled or not action then
        return { ok = false }
    end

    if GetGameTimer() < action.at then
        return { ok = false, error = 'Trop rapide.' }
    end

    local point = pointOf(action.id)
    local err = check(src, point)

    if err then
        return { ok = false, error = err }
    end

    local data = point.data

    if point.kind == 'harvest' then
        local amount = math.min(math.random(data.min, data.max), remaining(src, point))

        if amount <= 0 or not ox:AddItem(src, data.item, amount) then
            return { ok = false, error = 'Récolte impossible.' }
        end

        count(src, point, amount)
        local item = ox:Items(data.item)
        return { ok = true, message = ('+%d %s'):format(amount, item and item.label or data.item) }
    end

    for _, entry in ipairs(data.inputs) do
        if not ox:RemoveItem(src, entry.item, entry.count) then
            return { ok = false, error = 'Objets manquants.' }
        end
    end

    ox:AddItem(src, data.item, data.count)
    local item = ox:Items(data.item)
    GameLog('inventory', 'info', src, 'harvest.process', point.label, { item = data.item, count = data.count })
    return { ok = true, message = ('+%d %s'):format(data.count, item and item.label or data.item) }
end)

AddEventHandler('playerDropped', function()
    busy[source] = nil
end)
