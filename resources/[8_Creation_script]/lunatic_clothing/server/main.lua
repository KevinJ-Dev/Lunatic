-- Magasins de vêtements et barbiers, côté serveur. Tout part de la tenue enregistrée (users.skin, format illenium-appearance) :
--   - panier : seules les pièces réellement changées sont payées puis enregistrées (coupe et pilosité chez le barbier) ;
--   - prêt-à-porter : tenue du staff payée à son prix ;
--   - mes tenues : copie des pièces déjà enregistrées (donc payées), remise gratuitement ;
--   - favoris : liste de pièces par sexe.

local MAX_DRAWABLE, MAX_TEXTURE, MAX_COLOR, MAX_OPACITY = 3000, 255, 63, 10
local lastAction = {} -- joueur -> dernière action (anti-spam)
local lastFavorites = {} -- joueur -> dernier enregistrement des favoris

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_outfits` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(60) NOT NULL,
            `label` VARCHAR(40) NOT NULL,
            `sex` VARCHAR(6) NOT NULL,
            `pieces` LONGTEXT NOT NULL,
            `created` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            INDEX `identifier` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_clothing_favorites` (
            `identifier` VARCHAR(60) NOT NULL,
            `favorites` LONGTEXT NOT NULL,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

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
        brands[#brands + 1] = {
            key = key, label = brand.label, color = brand.color, image = brand.image or '', showText = brand.showText ~= false,
            blip = brand.blip, coef = brand.coef or 1.0, exclude = brand.exclude or {}, textColor = brand.textColor or '', flat = brand.flat == true,
            kind = brand.kind or 'clothing',
        }
    end

    for _, kind in ipairs({ 'clothing', 'barber' }) do
        for _, group in ipairs(ClothingGroupsOf(kind)) do
            for _, category in ipairs(group.categories) do
                categories[#categories + 1] = { key = category.key, label = category.label, group = group.label, kind = category.kind, shop = kind }
                prices[category.key] = category.price
            end
        end
    end

    return {
        stores = Config.Stores, brands = brands, categories = categories, prices = prices, pages = Config.Pages,
        storeDefaults = Config.StoreDefaults, maxOutfits = Config.MaxOutfits, screenshot = GetResourceState('screenshot-basic') == 'started',
    }
end)

local function storeNear(src, index)
    local store = ClothingStores()[tonumber(index) or 0]
    local ped = GetPlayerPed(src)

    if not store or ped == 0 or #(GetEntityCoords(ped) - vector3(store.x, store.y, store.z)) > store.radius + 3.0 then
        return nil
    end

    return store
end

local function busy(src)
    local now = GetGameTimer()

    if (lastAction[src] or 0) > now - 700 then
        return true
    end

    lastAction[src] = now
    return false
end

local function whole(value, min, max)
    value = tonumber(value)

    if not value or value ~= math.floor(value) or value < min or value > max then
        return nil
    end

    return value
end

local function cleanLabel(value)
    if type(value) ~= 'string' then
        return nil
    end

    value = value:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return #value >= 2 and #value <= 30 and value or nil
end

---------------------------------------------------------------------
-- Tenue enregistrée
---------------------------------------------------------------------

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

local function writeSkin(identifier, skin)
    MySQL.update.await('UPDATE `users` SET `skin` = ? WHERE `identifier` = ?', { json.encode(skin), identifier })
end

local function sexOfSkin(skin)
    return skin.model == 'mp_f_freemode_01' and 'female' or 'male'
end

local function findPiece(list, field, id)
    for _, piece in ipairs(list) do
        if tonumber(piece[field]) == id then
            return piece
        end
    end

    return nil
end

local function slotOf(skin, category)
    if category.kind == 'prop' then
        return skin.props, 'prop_id'
    end

    return skin.components, 'component_id'
end

-- Pièce valide : { modèle, couleur } (-1 = aucun accessoire) ; coupe { modèle, variante, couleur, reflets } ;
-- calque du visage { style, opacité 0-10, couleur }
local function readPiece(category, value)
    if type(value) ~= 'table' then
        return nil
    end

    if category.kind == 'hair' then
        local piece = { whole(value[1], 0, MAX_DRAWABLE), whole(value[2] or 0, 0, MAX_TEXTURE), whole(value[3] or 0, 0, MAX_COLOR), whole(value[4] or 0, 0, MAX_COLOR) }
        return piece[1] and piece[2] and piece[3] and piece[4] and piece or nil
    end

    if category.kind == 'overlay' then
        local piece = { whole(value[1], 0, MAX_DRAWABLE), whole(value[2] or 0, 0, MAX_OPACITY), whole(value[3] or 0, 0, MAX_COLOR) }
        return piece[1] and piece[2] and piece[3] and piece or nil
    end

    local drawable = whole(value[1], category.kind == 'prop' and -1 or 0, MAX_DRAWABLE)
    local texture = drawable and whole(value[2] or 0, 0, MAX_TEXTURE)
    return texture and { drawable, drawable < 0 and 0 or texture } or nil
end

-- Pièce « aucune » : accessoire retiré, calque à opacité nulle (rasé)
local function isNone(category, piece)
    return (category.kind == 'prop' and piece[1] < 0) or (category.kind == 'overlay' and piece[2] == 0)
end

-- Coupe et calques du visage dans le skin illenium-appearance
local function hairOf(skin)
    local hair = type(skin.hair) == 'table' and skin.hair or {}
    return { tonumber(hair.style) or 0, tonumber(hair.texture) or 0, tonumber(hair.color) or 0, tonumber(hair.highlight) or 0 }
end

local function overlayOf(skin, category)
    local overlays = type(skin.headOverlays) == 'table' and skin.headOverlays or {}
    local overlay = type(overlays[category.name]) == 'table' and overlays[category.name] or {}
    return { tonumber(overlay.style) or 0, math.floor((tonumber(overlay.opacity) or 0) * 10 + 0.5), tonumber(overlay.color) or 0 }
end

-- Pièces d'une tenue (clé de catégorie -> pièce), invalides ignorées
local function readPieces(pieces)
    local list = {}

    for key, value in pairs(type(pieces) == 'table' and pieces or {}) do
        local category = type(key) == 'string' and ClothingCategory(key)
        local piece = category and readPiece(category, value)

        if piece then
            list[key] = piece
        end
    end

    return list
end

-- Pièces portées d'après la tenue enregistrée
local function piecesOfSkin(skin)
    local pieces = {}

    for _, group in ipairs(Config.Groups) do
        for _, category in ipairs(group.categories) do
            local list, field = slotOf(skin, category)
            local piece = findPiece(list, field, category.id)

            if piece then
                pieces[category.key] = { tonumber(piece.drawable) or 0, math.max(0, tonumber(piece.texture) or 0) }
            end
        end
    end

    return pieces
end

local function samePiece(skin, category, piece)
    if category.kind == 'hair' or category.kind == 'overlay' then
        local current = category.kind == 'hair' and hairOf(skin) or overlayOf(skin, category)

        if isNone(category, piece) or isNone(category, current) then
            return isNone(category, piece) and isNone(category, current)
        end

        for index, value in ipairs(piece) do
            if current[index] ~= value then
                return false
            end
        end

        return true
    end

    local list, field = slotOf(skin, category)
    local current = findPiece(list, field, category.id)
    return current and tonumber(current.drawable) == piece[1] and (piece[1] < 0 or tonumber(current.texture) == piece[2])
end

local function setPiece(skin, category, piece)
    if category.kind == 'hair' then
        skin.hair = { style = piece[1], texture = piece[2], color = piece[3], highlight = piece[4] }
        return
    end

    if category.kind == 'overlay' then
        skin.headOverlays = type(skin.headOverlays) == 'table' and skin.headOverlays or {}
        skin.headOverlays[category.name] = { style = piece[1], opacity = piece[2] / 10, color = piece[3], secondColor = piece[3] }
        return
    end

    local list, field = slotOf(skin, category)
    local current = findPiece(list, field, category.id)

    if not current then
        current = { [field] = category.id }
        list[#list + 1] = current
    end

    current.drawable, current.texture = piece[1], piece[1] < 0 and -1 or piece[2]
end

local function pay(xPlayer, account, total, label)
    account = account == 'bank' and 'bank' or 'money'

    if total <= 0 then
        return true
    end

    if xPlayer.getAccount(account).money < total then
        return false, account == 'bank' and 'Solde bancaire insuffisant.' or "Vous n'avez pas assez de liquide."
    end

    xPlayer.removeAccountMoney(account, total, label)
    return true
end

-- Joueur dans un magasin, tenue lue : renvoie xPlayer, magasin, tenue ou un message d'erreur
local function context(src, index)
    local xPlayer = ESX.GetPlayerFromId(src)
    local store = storeNear(src, index)

    if not xPlayer or not store then
        return nil, 'Vous êtes trop loin du magasin.'
    end

    local skin = savedSkin(xPlayer.identifier)

    if not skin then
        return nil, "Votre tenue n'a pas pu être lue : prévenez le staff."
    end

    return xPlayer, store, skin
end

---------------------------------------------------------------------
-- Panier
---------------------------------------------------------------------

-- changes = { [clé de catégorie] = { modèle, couleur } }, seulement les pièces modifiées en magasin
lib.callback.register('lunatic_clothing:buy', function(src, index, changes, account)
    if busy(src) then
        return { ok = false, error = 'Patientez un instant.' }
    end

    local xPlayer, store, skin = context(src, index)

    if not xPlayer then
        return { ok = false, error = store }
    end

    local bought, total = {}, 0
    local brand, sex = ClothingBrand(store.brand), sexOfSkin(skin)

    for key, value in pairs(type(changes) == 'table' and changes or {}) do
        local category = type(key) == 'string' and ClothingCategory(key)
        local piece = category and readPiece(category, value)

        if not piece then
            return { ok = false, error = 'Panier invalide.' }
        end

        if not samePiece(skin, category, piece) then
            local none = isNone(category, piece)
            local item = not none and ClothingItem(sex, key, piece[1])

            if not ClothingBrandSells(brand, key) or (item and item.banned) then
                return { ok = false, error = ('« %s » : pièce indisponible dans ce magasin.'):format(category.label) }
            end

            bought[#bought + 1] = { category = category, piece = piece }
            -- Retirer un accessoire ou tout raser est gratuit ; sinon prix de la fiche (ou de la catégorie) selon l'enseigne
            total = total + (none and 0 or ClothingBrandPrice(brand, ClothingPieceBase(sex, key, piece[1])))
        end
    end

    if #bought == 0 then
        return { ok = true, total = 0, count = 0 }
    end

    local paid, err = pay(xPlayer, account, total, ('%s : %s'):format(ClothingBrandKind(brand) == 'barber' and 'Barbier' or 'Vêtements', store.label))

    if not paid then
        return { ok = false, error = err }
    end

    local labels = {}

    for _, entry in ipairs(bought) do
        setPiece(skin, entry.category, entry.piece)
        labels[#labels + 1] = entry.category.label
    end

    writeSkin(xPlayer.identifier, skin)
    log(src, 'clothing.buy', store.label, { total = total, items = table.concat(labels, ', ') })
    return { ok = true, total = total, count = #bought }
end)

---------------------------------------------------------------------
-- Prêt-à-porter
---------------------------------------------------------------------

lib.callback.register('lunatic_clothing:buyReady', function(src, index, id, account)
    if busy(src) then
        return { ok = false, error = 'Patientez un instant.' }
    end

    local xPlayer, store, skin = context(src, index)

    if not xPlayer then
        return { ok = false, error = store }
    end

    local outfit

    for _, entry in ipairs(ClothingReady()) do
        if entry.id == id then
            outfit = entry
        end
    end

    if not outfit or not ClothingReadyIn(outfit, store.brand) or ClothingBrandKind(ClothingBrand(store.brand)) ~= 'clothing' then
        return { ok = false, error = "Cette tenue n'est pas vendue ici." }
    end

    if outfit.sex ~= sexOfSkin(skin) then
        return { ok = false, error = "Cette tenue n'est pas faite pour votre personnage." }
    end

    local price = math.max(0, math.floor(tonumber(outfit.price) or 0))
    local paid, err = pay(xPlayer, account, price, ('Tenue %s : %s'):format(outfit.label, store.label))

    if not paid then
        return { ok = false, error = err }
    end

    local pieces = readPieces(outfit.pieces)

    for key, piece in pairs(pieces) do
        setPiece(skin, ClothingCategory(key), piece)
    end

    writeSkin(xPlayer.identifier, skin)
    log(src, 'clothing.ready', store.label, { outfit = outfit.label, price = price })
    return { ok = true, price = price, pieces = pieces }
end)

---------------------------------------------------------------------
-- Mes tenues
---------------------------------------------------------------------

local function outfitsOf(identifier)
    local rows = MySQL.query.await('SELECT `id`, `label`, `sex` FROM `lunatic_outfits` WHERE `identifier` = ? ORDER BY `id`', { identifier }) or {}
    return rows
end

local function favoritesOf(identifier)
    local raw = MySQL.scalar.await('SELECT `favorites` FROM `lunatic_clothing_favorites` WHERE `identifier` = ?', { identifier })
    local value = raw and json.decode(raw)
    return type(value) == 'table' and value or {}
end

-- À l'ouverture du magasin : tenues enregistrées, favoris, limite
lib.callback.register('lunatic_clothing:profile', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer then
        return nil
    end

    return { outfits = outfitsOf(xPlayer.identifier), favorites = favoritesOf(xPlayer.identifier), max = ClothingMaxOutfits() }
end)

-- Enregistre la tenue telle qu'elle est en base : les pièces essayées mais pas payées n'y sont pas
lib.callback.register('lunatic_clothing:saveOutfit', function(src, index, label)
    if busy(src) then
        return { ok = false, error = 'Patientez un instant.' }
    end

    local xPlayer, store, skin = context(src, index)
    label = cleanLabel(label)

    if not xPlayer then
        return { ok = false, error = store }
    end

    if not label then
        return { ok = false, error = 'Nom de la tenue : de 2 à 30 caractères.' }
    end

    local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `lunatic_outfits` WHERE `identifier` = ?', { xPlayer.identifier })) or 0

    if count >= ClothingMaxOutfits() then
        return { ok = false, error = ('%d tenues au maximum : supprimez-en une.'):format(ClothingMaxOutfits()) }
    end

    MySQL.insert.await('INSERT INTO `lunatic_outfits` (`identifier`, `label`, `sex`, `pieces`, `created`) VALUES (?, ?, ?, ?, ?)', {
        xPlayer.identifier, label, sexOfSkin(skin), json.encode(piecesOfSkin(skin)), os.time(),
    })

    return { ok = true, outfits = outfitsOf(xPlayer.identifier) }
end)

lib.callback.register('lunatic_clothing:wearOutfit', function(src, index, id)
    if busy(src) then
        return { ok = false, error = 'Patientez un instant.' }
    end

    local xPlayer, store, skin = context(src, index)

    if not xPlayer then
        return { ok = false, error = store }
    end

    local row = MySQL.single.await('SELECT `sex`, `pieces` FROM `lunatic_outfits` WHERE `id` = ? AND `identifier` = ?', { tonumber(id) or 0, xPlayer.identifier })

    if not row then
        return { ok = false, error = 'Tenue introuvable.' }
    end

    if row.sex ~= sexOfSkin(skin) then
        return { ok = false, error = "Cette tenue n'est pas faite pour votre personnage actuel." }
    end

    local pieces = readPieces(json.decode(row.pieces))

    for key, piece in pairs(pieces) do
        setPiece(skin, ClothingCategory(key), piece)
    end

    writeSkin(xPlayer.identifier, skin)
    return { ok = true, pieces = pieces }
end)

lib.callback.register('lunatic_clothing:renameOutfit', function(src, id, label)
    local xPlayer = ESX.GetPlayerFromId(src)
    label = cleanLabel(label)

    if not xPlayer or not label then
        return { ok = false, error = 'Nom de la tenue : de 2 à 30 caractères.' }
    end

    MySQL.update.await('UPDATE `lunatic_outfits` SET `label` = ? WHERE `id` = ? AND `identifier` = ?', { label, tonumber(id) or 0, xPlayer.identifier })
    return { ok = true, outfits = outfitsOf(xPlayer.identifier) }
end)

lib.callback.register('lunatic_clothing:deleteOutfit', function(src, id)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer then
        return { ok = false }
    end

    MySQL.query.await('DELETE FROM `lunatic_outfits` WHERE `id` = ? AND `identifier` = ?', { tonumber(id) or 0, xPlayer.identifier })
    return { ok = true, outfits = outfitsOf(xPlayer.identifier) }
end)

---------------------------------------------------------------------
-- Favoris : { male = { "clé:modèle:couleur", … }, female = { … } }
---------------------------------------------------------------------

RegisterNetEvent('lunatic_clothing:favorites', function(favorites)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)

    local now = GetGameTimer()

    if not xPlayer or type(favorites) ~= 'table' or (lastFavorites[src] or 0) > now - 1000 then
        return
    end

    lastFavorites[src] = now

    local clean = {}

    for _, sex in ipairs({ 'male', 'female' }) do
        clean[sex] = {}

        for _, entry in ipairs(type(favorites[sex]) == 'table' and favorites[sex] or {}) do
            local key, drawable, texture = tostring(entry):match('^([%a_]+):(%-?%d+):(%d+)$')

            if key and ClothingCategory(key) and #clean[sex] < Config.MaxFavorites then
                clean[sex][#clean[sex] + 1] = ('%s:%d:%d'):format(key, tonumber(drawable), tonumber(texture))
            end
        end
    end

    MySQL.query.await('INSERT INTO `lunatic_clothing_favorites` (`identifier`, `favorites`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `favorites` = VALUES(`favorites`)', {
        xPlayer.identifier, json.encode(clean),
    })
end)

AddEventHandler('playerDropped', function()
    lastAction[source] = nil
    lastFavorites[source] = nil
end)
