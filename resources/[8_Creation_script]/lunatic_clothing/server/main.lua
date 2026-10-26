-- Magasins de vêtements, côté serveur : achat du panier. Le prix est recalculé ici à partir de la tenue enregistrée
-- (users.skin, format illenium-appearance) : seules les pièces réellement changées sont payées puis enregistrées.

local MAX_DRAWABLE, MAX_TEXTURE = 3000, 255

local function log(src, action, target, details)
    if GetResourceState('lunatic_admin') == 'started' then
        pcall(function() exports.lunatic_admin:log('players', 'info', src, action, target, details) end)
    end
end

-- Défauts pour le panel (Autres → Magasins de vêtements)
exports('getDefaults', function()
    local brands, categories, prices = {}, {}, {}

    for _, key in ipairs(Config.BrandOrder) do
        local brand = Config.Brands[key]
        brands[#brands + 1] = { key = key, label = brand.label, color = brand.color }
    end

    for _, group in ipairs(Config.Groups) do
        for _, category in ipairs(group.categories) do
            categories[#categories + 1] = { key = category.key, label = category.label, group = group.label }
            prices[category.key] = category.price
        end
    end

    return { stores = Config.Stores, brands = brands, categories = categories, prices = prices, pages = Config.Pages }
end)

local function storeNear(src, index)
    local store = ClothingStores()[tonumber(index) or 0]
    local ped = GetPlayerPed(src)

    if not store or ped == 0 or #(GetEntityCoords(ped) - vector3(store.x, store.y, store.z)) > Config.StoreDistance + 3.0 then
        return nil
    end

    return store
end

local function whole(value, min, max)
    value = tonumber(value)

    if not value or value ~= math.floor(value) or value < min or value > max then
        return nil
    end

    return value
end

-- Tenue enregistrée : pièces indexées par composant et par accessoire
local function savedSkin(identifier)
    local raw = MySQL.scalar.await('SELECT `skin` FROM `users` WHERE `identifier` = ?', { identifier })
    local skin = raw and json.decode(raw)

    if type(skin) ~= 'table' then
        return nil
    end

    skin.components = type(skin.components) == 'table' and skin.components or {}
    skin.props = type(skin.props) == 'table' and skin.props or {}
    return skin
end

local function findPiece(list, field, id)
    for _, piece in ipairs(list) do
        if tonumber(piece[field]) == id then
            return piece
        end
    end

    return nil
end

-- Achat : changes = { [clé de catégorie] = { drawable, texture } }, seulement les pièces modifiées en magasin
lib.callback.register('lunatic_clothing:buy', function(src, index, changes, account)
    local xPlayer = ESX.GetPlayerFromId(src)
    local store = storeNear(src, index)

    if not xPlayer or not store then
        return { ok = false, error = 'Vous êtes trop loin du magasin.' }
    end

    if type(changes) ~= 'table' then
        return { ok = false, error = 'Panier invalide.' }
    end

    local skin = savedSkin(xPlayer.identifier)

    if not skin then
        return { ok = false, error = "Votre tenue n'a pas pu être lue : prévenez le staff." }
    end

    local bought, total = {}, 0

    for key, value in pairs(changes) do
        local category = type(key) == 'string' and ClothingCategory(key)
        local prop = category and category.kind == 'prop'
        local drawable = category and type(value) == 'table' and whole(value[1], prop and -1 or 0, MAX_DRAWABLE)
        local texture = drawable and whole(value[2] or 0, 0, MAX_TEXTURE)

        if not texture then
            return { ok = false, error = 'Panier invalide.' }
        end

        local list, field = prop and skin.props or skin.components, prop and 'prop_id' or 'component_id'
        local piece = findPiece(list, field, category.id)

        local same = piece and tonumber(piece.drawable) == drawable and (drawable < 0 or tonumber(piece.texture) == texture)

        if not same then
            bought[#bought + 1] = { list = list, field = field, id = category.id, drawable = drawable, texture = drawable < 0 and -1 or texture, label = category.label }
            -- Retirer un accessoire est gratuit
            total = total + (drawable < 0 and 0 or ClothingPrice(key))
        end
    end

    if #bought == 0 then
        return { ok = true, total = 0, count = 0 }
    end

    account = account == 'bank' and 'bank' or 'money'

    if total > 0 then
        if xPlayer.getAccount(account).money < total then
            return { ok = false, error = account == 'bank' and 'Solde bancaire insuffisant.' or "Vous n'avez pas assez de liquide." }
        end

        xPlayer.removeAccountMoney(account, total, ('Vêtements : %s'):format(store.label))
    end

    local labels = {}

    for _, entry in ipairs(bought) do
        local piece = findPiece(entry.list, entry.field, entry.id)

        if not piece then
            piece = { [entry.field] = entry.id }
            entry.list[#entry.list + 1] = piece
        end

        piece.drawable, piece.texture = entry.drawable, entry.texture
        labels[#labels + 1] = entry.label
    end

    MySQL.update.await('UPDATE `users` SET `skin` = ? WHERE `identifier` = ?', { json.encode(skin), xPlayer.identifier })
    log(src, 'clothing.buy', store.label, { total = total, account = account, items = table.concat(labels, ', ') })

    return { ok = true, total = total, count = #bought }
end)
