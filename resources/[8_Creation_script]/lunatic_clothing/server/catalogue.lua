-- Catalogue des vêtements : fiche de chaque pièce (nom, prix, image, bannie) par sexe, catégorie et modèle, table
-- lunatic_clothing_items. Gestion par le staff en jeu (session ouverte par lunatic_admin après vérification de la
-- permission) : fiches, prix par défaut d'une catégorie, photo prise avec screenshot-basic (html/clothes/).

local RESOURCE = GetCurrentResourceName()
local SESSION_SECONDS = 2 * 60 * 60
local IMAGE_MAX = 300000 -- taille maximale d'une photo encodée (caractères)
local PRICE_MAX = 1000000

local sessions = {} -- [source] = fin de la session (os.time)
local items = { male = {}, female = {} } -- items[sexe][catégorie]["modèle"] = { label, price, banned, image }
local version = 0

local function publishVersion()
    version = version + 1
    GlobalState.lunaticClothingVersion = version
end

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_clothing_items` (
            `sex` VARCHAR(6) NOT NULL,
            `category` VARCHAR(20) NOT NULL,
            `drawable` INT NOT NULL,
            `label` VARCHAR(40) NULL DEFAULT NULL,
            `price` INT NULL DEFAULT NULL,
            `banned` TINYINT(1) NOT NULL DEFAULT 0,
            `image` VARCHAR(300) NULL DEFAULT NULL,
            PRIMARY KEY (`sex`, `category`, `drawable`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_clothing_items`') or {}) do
        local bag = items[row.sex]

        if bag and ClothingCategory(row.category) then
            bag[row.category] = bag[row.category] or {}
            bag[row.category][tostring(row.drawable)] = { label = row.label, price = row.price, banned = row.banned == 1 or row.banned == true, image = row.image }
        end
    end

    publishVersion()
end)

-- Fiche d'une pièce (nil si aucune)
function ClothingItem(sex, key, drawable)
    local bag = items[sex] and items[sex][key]
    return bag and bag[tostring(drawable)] or nil
end

-- Prix de base d'une pièce : celui de sa fiche, sinon celui de la catégorie
function ClothingPieceBase(sex, key, drawable)
    local item = ClothingItem(sex, key, drawable)
    return item and item.price or ClothingPrice(key)
end

lib.callback.register('lunatic_clothing:catalogue', function(_, sex)
    return { version = version, items = items[sex == 'female' and 'female' or 'male'] }
end)

---------------------------------------------------------------------
-- Session du staff
---------------------------------------------------------------------

-- exports.lunatic_clothing:startCatalogueSession(source) : appelé par lunatic_admin après vérification de la permission
exports('startCatalogueSession', function(src)
    src = tonumber(src)

    if not src or not GetPlayerName(src) then
        return false
    end

    sessions[src] = os.time() + SESSION_SECONDS
    TriggerClientEvent('lunatic_clothing:catalogueTool', src, GetResourceState('screenshot-basic') == 'started')
    return true
end)

local function staff(src)
    return (sessions[src] or 0) > os.time()
end

RegisterNetEvent('lunatic_clothing:catalogueClosed', function()
    sessions[source] = nil
end)

local function cleanText(value, max)
    if value == nil or value == '' then
        return ''
    end

    if type(value) ~= 'string' then
        return nil
    end

    value = value:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return #value <= max and value or nil
end

local function validPiece(sex, key, drawable)
    local category = type(key) == 'string' and ClothingCategory(key)
    drawable = math.tointeger(tonumber(drawable))
    return (sex == 'male' or sex == 'female') and category and drawable and drawable >= 0 and drawable <= 3000, drawable
end

local function storeItem(sex, key, drawable, item)
    local empty = not item.label and not item.price and not item.banned and not item.image
    items[sex][key] = items[sex][key] or {}

    if empty then
        items[sex][key][tostring(drawable)] = nil
        MySQL.query.await('DELETE FROM `lunatic_clothing_items` WHERE `sex` = ? AND `category` = ? AND `drawable` = ?', { sex, key, drawable })
    else
        items[sex][key][tostring(drawable)] = item
        MySQL.query.await([[
            INSERT INTO `lunatic_clothing_items` (`sex`, `category`, `drawable`, `label`, `price`, `banned`, `image`) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `price` = VALUES(`price`), `banned` = VALUES(`banned`), `image` = VALUES(`image`)
        ]], { sex, key, drawable, item.label, item.price, item.banned and 1 or 0, item.image })
    end

    publishVersion()
end

-- Fiche modifiée : nom, prix (vide = prix de la catégorie), bannie (cachée des magasins), image (lien ou photo)
lib.callback.register('lunatic_clothing:saveItem', function(src, sex, key, drawable, data)
    local ok
    ok, drawable = validPiece(sex, key, drawable)

    if not staff(src) then
        return { ok = false, error = 'Session expirée : rouvrez la gestion depuis le panel.' }
    end

    if not ok or type(data) ~= 'table' then
        return { ok = false, error = 'Pièce invalide.' }
    end

    local label, image = cleanText(data.label, 40), cleanText(data.image, 300)
    local price = data.price

    if price == '' or price == nil then
        price = nil
    else
        price = math.tointeger(tonumber(price))

        if not price or price < 0 or price > PRICE_MAX then
            return { ok = false, error = ('Prix : de 0 à %d (vide : prix de la catégorie).'):format(PRICE_MAX) }
        end
    end

    if not label then
        return { ok = false, error = 'Nom : 40 caractères au maximum.' }
    end

    if not image or image:find('[%s"()]') or image:find("'") then
        return { ok = false, error = 'Image : lien https sans espace (ou vide).' }
    end

    local item = { label = label ~= '' and label or nil, price = price, banned = data.banned == true, image = image ~= '' and image or nil }
    storeItem(sex, key, drawable, item)
    return { ok = true, item = item }
end)

-- Prix par défaut d'une catégorie (enregistré par lunatic_admin, comme dans le panel)
lib.callback.register('lunatic_clothing:setDefaultPrice', function(src, key, price)
    price = math.tointeger(tonumber(price))

    if not staff(src) or not ClothingCategory(key) or not price or price < 0 or price > PRICE_MAX then
        return { ok = false, error = 'Prix invalide.' }
    end

    local ok, saved = pcall(function() return exports.lunatic_admin:setClothingPrice(key, price) end)
    return { ok = ok and saved == true, error = (not ok or saved ~= true) and 'Panel indisponible.' or nil }
end)

---------------------------------------------------------------------
-- Photos (screenshot-basic, recadrées par la page) : html/clothes/sexe-catégorie-modèle.webp
---------------------------------------------------------------------

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64_VALUE = {}

for i = 1, #B64 do
    B64_VALUE[B64:byte(i)] = i - 1
end

-- Repris de lunatic_creator (server/photos.lua)
local function decodeBase64(data)
    local out, bits, value = {}, 0, 0

    for i = 1, #data do
        local digit = B64_VALUE[data:byte(i)]

        if digit then
            value = (value << 6) | digit
            bits = bits + 6

            if bits >= 8 then
                bits = bits - 8
                out[#out + 1] = string.char((value >> bits) & 0xFF)
                value = value & ((1 << bits) - 1)
            end
        end
    end

    return table.concat(out)
end

RegisterNetEvent('lunatic_clothing:photo', function(sex, key, drawable, image)
    local src = source
    local ok
    ok, drawable = validPiece(sex, key, drawable)
    local encoded = ok and staff(src) and type(image) == 'string' and #image <= IMAGE_MAX and image:match('^data:image/webp;base64,([%w%+/=]+)$')

    if not encoded then
        return TriggerClientEvent('lunatic_clothing:captured', src, false)
    end

    local bytes = decodeBase64(encoded)
    local path = ('clothes/%s-%s-%d.webp'):format(sex, key, drawable)

    if not SaveResourceFile(RESOURCE, 'html/' .. path, bytes, #bytes) then
        return TriggerClientEvent('lunatic_clothing:captured', src, false)
    end

    local item = ClothingItem(sex, key, drawable) or {}
    item.image = path
    storeItem(sex, key, drawable, item)
    TriggerClientEvent('lunatic_clothing:captured', src, true, path)
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
end)
