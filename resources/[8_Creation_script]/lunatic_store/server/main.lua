-- Boutique des joueurs : tout est vérifié ici (catégorie ouverte, produit en vente, prix, place dans l'inventaire),
-- les crédits sont débités par lunatic_admin (débit atomique), puis le produit est livré ; une livraison ratée
-- est remboursée. Chaque achat est enregistré (transactions de la tuile Boutique) et journalisé (logs Économie).

local admin = exports.lunatic_admin
local ox = exports.ox_inventory
local busy = {}

local function shop()
    return GlobalState.lunaticShop or {}
end

local function open(category)
    local categories = shop().categories
    return type(categories) == 'table' and categories[category] == true
end

local function creditsName()
    local credits = shop().credits
    return credits and credits.name ~= '' and credits.name or 'crédits'
end

AddEventHandler('playerDropped', function()
    busy[source] = nil
end)

---------------------------------------------------------------------
-- Ouverture : réglages publics, solde, abonnement, catalogues ouverts
---------------------------------------------------------------------

local function tiers()
    local list = {}
    local settings = shop().tiers or {}
    local allowances = GlobalState.lunaticEconomy and GlobalState.lunaticEconomy.allowances or {}

    for tier, info in pairs(Config.Tiers) do
        local perks = settings[tier] or {}
        list[tier] = {
            label = info.label, color = info.color, open = open(tier), price = tonumber(perks.priceCredits) or 0, priceEuro = tonumber(perks.priceEuro) or 0,
            salaryMultiplier = tonumber(perks.salaryMultiplier) or 1, allowance = tonumber(allowances[tier]) or 0, characters = perks.characters,
            garageSlots = perks.garageSlots, farmMultiplier = perks.farmMultiplier, outfits = perks.outfits,
        }
    end

    return list
end

lib.callback.register('lunatic_store:open', function(src)
    local settings = shop()
    local banners = {}

    for _, banner in ipairs(settings.banners or {}) do
        if banner.active then
            banners[#banners + 1] = banner
        end
    end

    local catalogs = {}

    for _, kind in ipairs({ 'vehicles', 'packs', 'weapons' }) do
        catalogs[kind] = open(kind) and admin:getStoreCatalog(kind) or nil
    end

    -- Nom des objets des packs (affichés tels quels dans la boutique)
    for _, category in ipairs(catalogs.packs or {}) do
        for _, product in ipairs(category.products) do
            for _, entry in ipairs(product.data.items or {}) do
                local item = ox:Items(entry.item)
                entry.label = item and item.label or entry.item
            end
        end
    end

    return {
        credits = settings.credits, banners = banners, categories = settings.categories or {},
        balance = admin:getCredits(src), premium = admin:getPremium(src), tiers = tiers(), days = Config.PremiumDays,
        currency = GlobalState.lunaticCurrency or '$', catalogs = catalogs,
    }
end)

---------------------------------------------------------------------
-- Vérifications avant le débit
---------------------------------------------------------------------

-- Le serveur ne connaît pas les modèles du jeu : le client vérifie qu'il existe et donne son type
local function vehicleInfo(src, model)
    local ok, info = pcall(lib.callback.await, 'lunatic_store:vehicleModel', src, model)

    if not ok or type(info) ~= 'table' or not info.ok then
        return nil
    end

    return { hash = joaat(model), type = info.type }
end

local function canCarry(src, list)
    for _, entry in ipairs(list) do
        if not ox:CanCarryItem(src, entry.item, entry.count) then
            return false, ox:Items(entry.item) and ox:Items(entry.item).label or entry.item
        end
    end

    return true
end

---------------------------------------------------------------------
-- Achat
---------------------------------------------------------------------

local function fail(message)
    return { ok = false, error = message }
end

local function buy(src, request)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or type(request) ~= 'table' then
        return fail('Personnage introuvable.')
    end

    local category, label, price, deliver

    if request.kind == 'premium' then
        local tier = request.tier
        local info = Config.Tiers[tier] and tiers()[tier]

        if not info or not info.open or info.price <= 0 then
            return fail("Cet abonnement n'est pas en vente.")
        end

        category, label, price = tier, ('%s (%d jours)'):format(info.label, Config.PremiumDays), info.price
        deliver = function()
            local ok, err = admin:grantPremium(src, tier, Config.PremiumDays)
            return ok, err
        end
    elseif request.kind == 'vehicles' or request.kind == 'packs' or request.kind == 'weapons' then
        if not open(request.kind) then
            return fail("Cette catégorie n'est pas ouverte.")
        end

        local product = admin:getStoreProduct(tonumber(request.id))

        if not product or not product.active or product.kind ~= request.kind then
            return fail("Ce produit n'est plus en vente.")
        end

        category, label, price = product.kind, product.label, product.price
        local data = product.data

        if product.kind == 'vehicles' then
            local info = vehicleInfo(src, data.model)

            if not info then
                return fail("Ce véhicule n'existe pas en jeu : prévenez le staff.")
            end

            deliver = function()
                local plate = admin:giveOwnedVehicle(xPlayer.identifier, info.hash, info.type)
                return plate ~= nil, 'Aucune plaque libre, réessayez.', ('Véhicule livré au garage (plaque %s).'):format(plate)
            end
        elseif product.kind == 'weapons' then
            local item = ox:Items(data.item)
            local list = { { item = data.item, count = 1 } }

            if item and item.ammoname and (data.ammo or 0) > 0 then
                list[2] = { item = item.ammoname, count = data.ammo }
            end

            local ok, missing = canCarry(src, list)

            if not ok then
                return fail(('Pas assez de place dans votre inventaire (%s).'):format(missing))
            end

            deliver = function()
                for _, entry in ipairs(list) do
                    if not ox:AddItem(src, entry.item, entry.count) then
                        return false, 'Inventaire plein.'
                    end
                end

                return true
            end
        else
            local ok, missing = canCarry(src, data.items or {})

            if not ok then
                return fail(('Pas assez de place dans votre inventaire (%s).'):format(missing))
            end

            local vehicles = {}

            for _, vehicle in ipairs(data.vehicles or {}) do
                local info = vehicleInfo(src, vehicle.model)

                if not info then
                    return fail(("Le véhicule %s du pack n'existe pas en jeu : prévenez le staff."):format(vehicle.label or vehicle.model))
                end

                vehicles[#vehicles + 1] = info
            end

            deliver = function()
                if (data.cash or 0) > 0 then
                    xPlayer.addAccountMoney('money', data.cash, 'Boutique')
                end

                if (data.bank or 0) > 0 then
                    xPlayer.addAccountMoney('bank', data.bank, 'Boutique')
                end

                for _, entry in ipairs(data.items or {}) do
                    ox:AddItem(src, entry.item, entry.count)
                end

                for _, info in ipairs(vehicles) do
                    admin:giveOwnedVehicle(xPlayer.identifier, info.hash, info.type)
                end

                return true, nil, #vehicles > 0 and 'Véhicule(s) livré(s) au garage.' or nil
            end
        end
    else
        return fail('Achat inconnu.')
    end

    -- Débit, puis livraison (remboursée si elle échoue)
    if price > 0 and not admin:removeCredits(src, price, ('Boutique : %s'):format(label)) then
        return fail(('Solde insuffisant : il faut %d %s.'):format(price, creditsName()))
    end

    local delivered, err, note = deliver()

    if not delivered then
        if price > 0 then
            admin:addCredits(src, price, ('Remboursement : %s'):format(label))
        end

        return fail(err or 'Livraison impossible : vous avez été remboursé.')
    end

    admin:recordStorePurchase(src, category, label, price)
    admin:log('economy', 'info', src, 'store.purchase', label, { category = category, price = price })

    return { ok = true, message = ('Achat réussi : %s.%s'):format(label, note and (' ' .. note) or ''), balance = admin:getCredits(src), premium = admin:getPremium(src) }
end

lib.callback.register('lunatic_store:buy', function(src, request)
    if busy[src] then
        return fail('Un achat est déjà en cours.')
    end

    busy[src] = true
    local ok, result = pcall(buy, src, request)
    busy[src] = nil

    if not ok then
        print(('[lunatic_store] Erreur pendant un achat de %s : %s'):format(GetPlayerName(src) or src, result))
        return fail("Erreur pendant l'achat : prévenez le staff.")
    end

    return result
end)
