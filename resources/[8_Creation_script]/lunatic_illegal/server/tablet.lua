-- Tablette des crews côté serveur : marché noir (catalogue, commandes, récupération).
-- La logique et les données sont dans lunatic_admin (server/market.lua) ; ici on vérifie la tablette et on relaie.

local ox = exports.ox_inventory
local admin = exports.lunatic_admin

local function fail(message)
    return { ok = false, error = message }
end

-- Il faut avoir sur soi une tablette de son crew pour consulter le marché et commander (HasCrewTablet, server/common.lua)
local hasTablet = HasCrewTablet

-- Ouverture : la tablette s'initialise pour le crew du premier membre qui l'allume ; ensuite elle reste
-- verrouillée pour tout autre joueur (volée, perdue, saisie par la police). Le crew n'est jamais affiché.
lib.callback.register('lunatic_illegal:tabletOpen', function(src, slotId)
    local item = tonumber(slotId) and ox:GetSlot(src, tonumber(slotId))

    if not item or item.name ~= Config.TabletItem then
        return fail('Tablette introuvable.')
    end

    local crew = CrewOf(src)
    local metadata = item.metadata or {}

    if not crew then
        return fail("Écran verrouillé : la tablette ne s'ouvre pas pour vous.")
    end

    if metadata.crew == nil then
        metadata.crew = crew.id
        ox:SetMetadata(src, item.slot, metadata)
        return { ok = true, bound = true }
    end

    if metadata.crew ~= crew.id then
        return fail("Écran verrouillé : la tablette ne s'ouvre pas pour vous.")
    end

    return { ok = true }
end)

local function call(fn)
    local found, result = pcall(fn)
    return found and result or fail('Marché noir indisponible pour le moment.')
end

lib.callback.register('lunatic_illegal:market', function(src)
    if not hasTablet(src) then
        return fail("Il vous faut une tablette de votre crew sur vous.")
    end

    return call(function() return admin:marketCatalog(src) end)
end)

lib.callback.register('lunatic_illegal:marketBuy', function(src, itemId, quantity)
    if not hasTablet(src) then
        return fail("Il vous faut une tablette de votre crew sur vous.")
    end

    return call(function() return admin:marketBuy(src, itemId, quantity) end)
end)

lib.callback.register('lunatic_illegal:marketOrders', function(src)
    local found, list = pcall(function() return admin:marketOrders(src) end)
    return found and list or {}
end)

-- Policiers en service : joueurs connectés dont le métier est une structure de type Police
local function policePlayers()
    local list = {}

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local found, structure = pcall(function() return admin:getStructure(xPlayer.getJob().name) end)

        if found and structure and structure.kind == 'public' and structure.type == 'police' then
            list[#list + 1] = xPlayer.source
        end
    end

    return list
end

lib.callback.register('lunatic_illegal:marketCollect', function(src, orderId)
    local result = call(function() return admin:marketCollect(src, orderId) end)

    if result.ok and math.random() < Config.MarketAlertChance then
        for _, officer in ipairs(policePlayers()) do
            TriggerClientEvent('lunatic_illegal:marketAlert', officer, { x = result.x + math.random(-50, 50), y = result.y + math.random(-50, 50) })
        end
    end

    return result
end)
