-- Documents : carte d'identité et permis de conduire, objets utilisables (regarder, montrer aux joueurs proches).
-- Carte retirée à un guichet de documents (poste de police : première gratuite, puis duplicata payant) ou remise à la
-- connexion ; permis remis à la réussite du premier examen (lunatic_driving), duplicata au guichet. Réglages du panel :
-- Fonctionnalités → Carte d'identité. Identité ESX, nationalité (lunatic_creator), photo (tuile Images).

local ox = exports.ox_inventory
local lastShow = {} -- joueur -> dernier « montrer » (anti-spam)

MySQL.ready(function()
    -- Première carte remise (gratuite) : les suivantes sont des duplicatas
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_documents` (
            `identifier` VARCHAR(60) NOT NULL,
            `idcard_at` BIGINT NULL DEFAULT NULL,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await('ALTER TABLE `lunatic_documents` ADD COLUMN IF NOT EXISTS `license_at` BIGINT NULL DEFAULT NULL')
end)

-- Documents gérés : objet, colonne de première remise, réglage du prix du duplicata
local DOCUMENTS = {
    idcard = { item = Config.IdCardItem, column = 'idcard_at', price = 'duplicatePrice', label = "carte d'identité" },
    license = { item = Config.DriverLicenseItem, column = 'license_at', price = 'licensePrice', label = 'permis de conduire' },
}

local function settings()
    return FeaturesOf('idcard')
end

-- Export d'une autre ressource Lunatic si elle tourne, sinon nil
local function external(resource, name, ...)
    if GetResourceState(resource) ~= 'started' then
        return nil
    end

    local args = { ... }
    local ok, value = pcall(function()
        local api = exports[resource]
        return api[name](api, table.unpack(args))
    end)

    return ok and value or nil
end

local function identityOf(xPlayer)
    local name = xPlayer.getName() or ''
    local first, last = xPlayer.get('firstName'), xPlayer.get('lastName')
    local hash = xPlayer.identifier:match('(%x+)$') or ''

    return {
        firstName = first or name:match('^(%S+)') or '', lastName = last or name:match('%s(.+)$') or '',
        dateofbirth = xPlayer.get('dateofbirth') or '', sex = xPlayer.get('sex') or '', height = xPlayer.get('height') or '',
        nationality = external('lunatic_creator', 'getNationality', xPlayer.identifier) or '',
        number = ('%09d'):format(tonumber(hash:sub(1, 7), 16) or 0):sub(1, 9),
        photo = external('lunatic_admin', 'getMugshot', xPlayer.identifier),
    }
end

local function hasItem(src, kind)
    return (ox:Search(src, 'count', DOCUMENTS[kind].item) or 0) > 0
end

local function hasCard(src)
    return hasItem(src, 'idcard')
end

local function issuedAt(identifier, kind)
    return MySQL.scalar.await(('SELECT `%s` FROM `lunatic_documents` WHERE `identifier` = ?'):format(DOCUMENTS[kind or 'idcard'].column), { identifier })
end

local function markIssued(identifier, kind)
    local column = DOCUMENTS[kind or 'idcard'].column
    MySQL.query.await(('INSERT INTO `lunatic_documents` (`identifier`, `%s`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `%s` = VALUES(`%s`)'):format(column, column, column), { identifier, os.time() })
end

-- Prix d'un document : le premier est gratuit (si réglé), ensuite c'est un duplicata
local function documentPrice(identifier, kind)
    local s = settings()

    if not issuedAt(identifier, kind) and s.firstFree ~= false then
        return 0
    end

    return tonumber(s[DOCUMENTS[kind].price]) or 50
end

-- Catégories de permis obtenues (permis ESX de user_licenses), dans l'ordre de la config
local function licenseCategories(identifier)
    local owned = {}

    for _, row in ipairs(MySQL.query.await('SELECT `type` FROM `user_licenses` WHERE `owner` = ?', { identifier }) or {}) do
        owned[row.type] = true
    end

    local list, any = {}, false

    for _, category in ipairs(Config.DriverLicenseCategories) do
        list[#list + 1] = { code = category.code, label = category.label, kind = category.kind, owned = owned[category.type] == true }
        any = any or owned[category.type] == true
    end

    return list, any
end

-- Document à afficher : identité, date de remise (émission, expiration) et, pour le permis, ses catégories
local function documentOf(xPlayer, kind)
    local data = identityOf(xPlayer)
    data.issued = tonumber(issuedAt(xPlayer.identifier, kind))

    if kind == 'license' then
        data.kind = 'license'
        data.categories = licenseCategories(xPlayer.identifier)
    end

    return data
end

exports('getDefaultOffices', function()
    return Config.DocumentOffices
end)

-- Guichet où se trouve le joueur (le serveur vérifie la distance)
local function officeAt(src, index)
    local office = DocumentOffices()[tonumber(index) or 0]
    local ped = GetPlayerPed(src)

    if not office or ped == 0 or #(GetEntityCoords(ped) - vector3(office.x, office.y, office.z)) > Config.OfficeDistance + 1.0 then
        return nil
    end

    return office
end

ESX.RegisterUsableItem(Config.IdCardItem, function(source)
    TriggerClientEvent('lunatic_gameplay:idcardMenu', source)
end)

lib.callback.register('lunatic_gameplay:idcard', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not hasCard(src) then
        return nil
    end

    return documentOf(xPlayer, 'idcard')
end)

-- Montrer sa carte ou son permis : tous les joueurs proches (même instance) le voient
RegisterNetEvent('lunatic_gameplay:idcardShow', function(kind)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    local now = os.time()
    kind = kind == 'license' and 'license' or 'idcard'

    if not xPlayer or not hasItem(src, kind) or (lastShow[src] or 0) > now - 3 then
        return
    end

    lastShow[src] = now
    local origin = GetEntityCoords(GetPlayerPed(src))
    local radius = tonumber(settings().showRadius) or 3.0
    local bucket = GetPlayerRoutingBucket(src)
    local identity = documentOf(xPlayer, kind)
    local count = 0

    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        local ped = target ~= src and GetPlayerPed(target) or 0

        if ped ~= 0 and GetPlayerRoutingBucket(target) == bucket and #(GetEntityCoords(ped) - origin) <= radius then
            TriggerClientEvent('lunatic_gameplay:idcardDisplay', target, identity)
            count = count + 1
        end
    end

    if count == 0 then
        return Notify(src, 'Personne à côté de vous.', 'error')
    end

    Notify(src, ('Vous montrez votre %s (%d personne%s).'):format(DOCUMENTS[kind].label, count, count > 1 and 's' or ''), 'info')
end)

-- Menu contextuel : montrer sa carte ou son permis à un joueur précis, à côté
RegisterNetEvent('lunatic_gameplay:idcardShowTo', function(kind, target)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    local now = os.time()
    kind = kind == 'license' and 'license' or 'idcard'
    target = tonumber(target)

    if not xPlayer or not target or target == src or not hasItem(src, kind) or (lastShow[src] or 0) > now - 3 then
        return
    end

    lastShow[src] = now
    local ped, targetPed = GetPlayerPed(src), GetPlayerPed(target)
    local radius = tonumber(settings().showRadius) or 3.0

    if targetPed == 0 or GetPlayerRoutingBucket(target) ~= GetPlayerRoutingBucket(src) or #(GetEntityCoords(targetPed) - GetEntityCoords(ped)) > radius then
        return Notify(src, 'Personne trop loin.', 'error')
    end

    TriggerClientEvent('lunatic_gameplay:idcardDisplay', target, documentOf(xPlayer, kind))
    Notify(src, ('Vous montrez votre %s.'):format(DOCUMENTS[kind].label), 'info')
end)

-- Guichet : état de la carte du joueur et prix
lib.callback.register('lunatic_gameplay:officeInfo', function(src, index)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not officeAt(src, index) then
        return nil
    end

    local _, anyLicense = licenseCategories(xPlayer.identifier)

    return {
        hasCard = hasCard(src), identity = xPlayer.get('firstName') ~= nil, price = documentPrice(xPlayer.identifier, 'idcard'),
        hasLicense = hasItem(src, 'license'), anyLicense = anyLicense, licensePrice = documentPrice(xPlayer.identifier, 'license'),
        cash = xPlayer.getAccount('money').money, bank = xPlayer.getAccount('bank').money,
    }
end)

-- Guichet : retrait d'un document (premier gratuit, duplicata payé en liquide ou par carte)
lib.callback.register('lunatic_gameplay:officeDocument', function(src, index, kind, account)
    local xPlayer = ESX.GetPlayerFromId(src)
    local office = officeAt(src, index)
    local document = DOCUMENTS[kind]

    if not xPlayer or not office or not document then
        return { error = 'Vous êtes trop loin du guichet.' }
    end

    if not xPlayer.get('firstName') then
        return { error = "Vous n'avez pas encore d'identité." }
    end

    if kind == 'license' and not select(2, licenseCategories(xPlayer.identifier)) then
        return { error = "Vous n'avez aucun permis : passez-le à l'auto-école." }
    end

    if hasItem(src, kind) then
        return { error = ('Vous avez déjà votre %s sur vous.'):format(document.label) }
    end

    -- Objet absent d'ox_inventory (data/items.lua pas encore chargé) : ce n'est pas une question de place
    if not ox:Items(document.item) then
        return { error = 'Document indisponible pour le moment : prévenez le staff.' }
    end

    -- Les documents ne pèsent rien : seul un emplacement libre est nécessaire
    if not ox:CanCarryItem(src, document.item, 1) then
        return { error = "Vous n'avez plus d'emplacement libre dans votre inventaire." }
    end

    local price = documentPrice(xPlayer.identifier, kind)
    account = account == 'bank' and 'bank' or 'money'

    if price > 0 then
        if xPlayer.getAccount(account).money < price then
            return { error = account == 'bank' and 'Solde bancaire insuffisant.' or "Vous n'avez pas assez de liquide." }
        end

        xPlayer.removeAccountMoney(account, price, ('Duplicata : %s'):format(document.label))
    end

    ox:AddItem(src, document.item, 1)
    markIssued(xPlayer.identifier, kind)
    GameLog('players', 'info', src, 'player.document', office.label, { document = kind, price = price })

    return { ok = true, price = price, label = document.label }
end)

-- Permis de conduire : objet utilisable, regarder ou montrer comme la carte
ESX.RegisterUsableItem(Config.DriverLicenseItem, function(source)
    TriggerClientEvent('lunatic_gameplay:licenseMenu', source)
end)

lib.callback.register('lunatic_gameplay:license', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not hasItem(src, 'license') then
        return nil
    end

    return documentOf(xPlayer, 'license')
end)

-- Premier permis obtenu à l'auto-école (lunatic_driving) : l'objet est remis gratuitement s'il ne l'a pas
AddEventHandler('lunatic_driving:licenseGranted', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or hasItem(src, 'license') then
        return
    end

    if ox:AddItem(src, Config.DriverLicenseItem, 1) then
        markIssued(xPlayer.identifier, 'license')
        Notify(src, 'Félicitations : voici votre permis de conduire (inventaire).', 'success')
    end
end)

-- Arrivée en ville : carte remise automatiquement, ou point GPS vers le guichet tant qu'elle n'a jamais été retirée
local function checkDelivery(playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)

    if not xPlayer or not xPlayer.get('firstName') or Player(playerId).state.lunaticCreating then
        return
    end

    local s = settings()

    if s.delivery == 'auto' then
        if not hasCard(playerId) then
            ox:AddItem(playerId, Config.IdCardItem, 1)
            markIssued(xPlayer.identifier)
        end

        return
    end

    if s.guide ~= false and not hasCard(playerId) and not issuedAt(xPlayer.identifier) then
        TriggerClientEvent('lunatic_gameplay:officeGuide', playerId)
    end
end

AddEventHandler('esx:playerLoaded', function(playerId)
    SetTimeout(5000, function() checkDelivery(playerId) end)
end)

-- Fin de la création de personnage (lunatic_creator) : après l'arrivée en ville
RegisterNetEvent('lunatic_creator:leave', function()
    local src = source
    SetTimeout(12000, function() checkDelivery(src) end)
end)

AddEventHandler('playerDropped', function()
    lastShow[source] = nil
end)
