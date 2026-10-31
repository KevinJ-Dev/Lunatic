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

-- Fiches d'un sexe, envoyées en événement latent (la liste grossit vite après une série de photos)
RegisterNetEvent('lunatic_clothing:catalogue', function(sex)
    sex = sex == 'female' and 'female' or 'male'
    TriggerLatentClientEvent('lunatic_clothing:catalogue', source, 200000, sex, items[sex])
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

-- exports.lunatic_clothing:startStaffDressing(source, persist, back) : habillage libre homme / femme, ouvert par le staff
-- (lunatic_admin : fiche joueur → Apparence, persist = true ; lunatic_interim : tenues d'intérim, back = 'interim').
-- persist : à la validation, l'apparence d'avant est sauvegardée (5 dernières par personnage) puis remplacée.
local BACKUPS = 5
local dressing = {} -- joueur -> true pendant un habillage staff à enregistrer

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_clothing_backups` (
            `id` BIGINT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(64) NOT NULL,
            `skin` LONGTEXT NOT NULL,
            `saved_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_clothing_backups_owner` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

exports('startStaffDressing', function(src, persist, back)
    src = tonumber(src)

    if not src or not GetPlayerName(src) then
        return false
    end

    dressing[src] = persist == true or nil
    TriggerClientEvent('lunatic_clothing:staffDressing', src, persist == true, type(back) == 'string' and back or nil)
    return true
end)

-- Validation d'un habillage staff à enregistrer : sauvegarde de l'apparence d'avant, puis la nouvelle (comme illenium-appearance)
lib.callback.register('lunatic_clothing:staffSave', function(src, appearance)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not dressing[src] or not xPlayer then
        return { ok = false, error = 'Habillage non autorisé.' }
    elseif type(appearance) ~= 'table' or (appearance.model ~= 'mp_m_freemode_01' and appearance.model ~= 'mp_f_freemode_01') then
        return { ok = false, error = 'Apparence invalide.' }
    end

    dressing[src] = nil
    local identifier = xPlayer.identifier
    local previous = MySQL.scalar.await('SELECT `skin` FROM `users` WHERE `identifier` = ?', { identifier })

    if previous and previous ~= '' then
        MySQL.insert.await('INSERT INTO `lunatic_clothing_backups` (`identifier`, `skin`, `saved_at`) VALUES (?, ?, ?)', { identifier, previous, os.time() })
        MySQL.update.await([[
            DELETE FROM `lunatic_clothing_backups` WHERE `identifier` = ? AND `id` NOT IN (
                SELECT `id` FROM (SELECT `id` FROM `lunatic_clothing_backups` WHERE `identifier` = ? ORDER BY `id` DESC LIMIT ?) AS `kept`)
        ]], { identifier, identifier, BACKUPS })
    end

    MySQL.update.await('UPDATE `users` SET `skin` = ? WHERE `identifier` = ?', { json.encode(appearance), identifier })
    return { ok = true }
end)

-- exports.lunatic_clothing:restorePreviousAppearance(source) : remet la dernière apparence sauvegardée (et la retire)
exports('restorePreviousAppearance', function(src)
    local xPlayer = ESX.GetPlayerFromId(tonumber(src) or 0)

    if not xPlayer then
        return false, "Ce joueur n'est plus connecté."
    end

    local row = MySQL.single.await('SELECT `id`, `skin` FROM `lunatic_clothing_backups` WHERE `identifier` = ? ORDER BY `id` DESC LIMIT 1', { xPlayer.identifier })

    if not row then
        return false, 'Aucune apparence précédente sauvegardée.'
    end

    MySQL.update.await('UPDATE `users` SET `skin` = ? WHERE `identifier` = ?', { row.skin, xPlayer.identifier })
    MySQL.update.await('DELETE FROM `lunatic_clothing_backups` WHERE `id` = ?', { row.id })
    TriggerClientEvent('illenium-appearance:client:reloadSkin', xPlayer.source, true)
    return true
end)

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

-- quiet = photo d'une série : le catalogue n'est republié qu'à la fin (lunatic_clothing:photosDone)
local function storeItem(sex, key, drawable, item, quiet)
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

    if not quiet then
        publishVersion()
    end
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

local imageCache = {} -- chemin -> image en data URI (false : fichier absent)

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

RegisterNetEvent('lunatic_clothing:photo', function(sex, key, drawable, image, batch)
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
    imageCache[path] = nil
    storeItem(sex, key, drawable, item, batch == true)
    TriggerClientEvent('lunatic_clothing:captured', src, true, path)
end)

-- Photos prises depuis le démarrage de la ressource : leurs fichiers ne sont pas encore chez les joueurs (envoyés au
-- prochain « ensure »), la page les demande donc ici. Lues sur le disque, encodées en base64, gardées en mémoire.
local function encodeBase64(data)
    local out = {}

    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = (a << 16) | ((b or 0) << 8) | (c or 0)
        out[#out + 1] = B64:sub((n >> 18) + 1, (n >> 18) + 1) .. B64:sub(((n >> 12) & 63) + 1, ((n >> 12) & 63) + 1)
            .. (b and B64:sub(((n >> 6) & 63) + 1, ((n >> 6) & 63) + 1) or '=') .. (c and B64:sub((n & 63) + 1, (n & 63) + 1) or '=')
    end

    return table.concat(out)
end

-- Envoi en événement latent (débit limité) : des dizaines d'images en événements normaux saturent la file réseau du
-- joueur (« Reliable network event overflow »). Le client n'en demande qu'une à la fois.
local IMAGE_BPS = 200000
local imageRequests = {} -- joueur -> { seconde, nombre }

RegisterNetEvent('lunatic_clothing:image', function(path)
    local src = source

    if type(path) ~= 'string' or not path:match('^clothes/[%w_%-]+%.webp$') then
        return
    end

    local now = os.time()
    local count = imageRequests[src]

    if not count or count[1] ~= now then
        count = { now, 0 }
        imageRequests[src] = count
    end

    count[2] = count[2] + 1

    if count[2] > 20 then
        return
    end

    if imageCache[path] == nil then
        local data = LoadResourceFile(RESOURCE, 'html/' .. path)
        imageCache[path] = data and ('data:image/webp;base64,' .. encodeBase64(data)) or false
    end

    TriggerLatentClientEvent('lunatic_clothing:image', src, IMAGE_BPS, path, imageCache[path] or false)
end)

RegisterNetEvent('lunatic_clothing:photosDone', function()
    if staff(source) then
        publishVersion()
    end
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
    imageRequests[source] = nil
    dressing[source] = nil
end)
