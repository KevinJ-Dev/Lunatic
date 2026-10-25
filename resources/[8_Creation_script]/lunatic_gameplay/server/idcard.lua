-- Carte d'identité : objet utilisable (regarder, montrer aux joueurs proches), retirée à un guichet de documents
-- (poste de police : première carte gratuite, puis duplicata payant) ou remise à la connexion, selon le panel
-- (Fonctionnalités → Carte d'identité). Identité ESX, nationalité (lunatic_creator), photo (tuile Images).

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
end)

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
        model = settings().model or 'fr', photo = external('lunatic_admin', 'getMugshot', xPlayer.identifier),
    }
end

local function hasCard(src)
    return (ox:Search(src, 'count', Config.IdCardItem) or 0) > 0
end

local function issuedAt(identifier)
    return MySQL.scalar.await('SELECT `idcard_at` FROM `lunatic_documents` WHERE `identifier` = ?', { identifier })
end

local function markIssued(identifier)
    MySQL.query.await('INSERT INTO `lunatic_documents` (`identifier`, `idcard_at`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `idcard_at` = VALUES(`idcard_at`)', { identifier, os.time() })
end

-- Prix d'une carte : la première est gratuite (si réglé), ensuite c'est un duplicata
local function cardPrice(identifier)
    local s = settings()

    if not issuedAt(identifier) and s.firstFree ~= false then
        return 0
    end

    return tonumber(s.duplicatePrice) or 50
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

    return identityOf(xPlayer)
end)

-- Montrer sa carte : tous les joueurs proches (même instance) la voient
RegisterNetEvent('lunatic_gameplay:idcardShow', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    local now = os.time()

    if not xPlayer or not hasCard(src) or (lastShow[src] or 0) > now - 3 then
        return
    end

    lastShow[src] = now
    local origin = GetEntityCoords(GetPlayerPed(src))
    local radius = tonumber(settings().showRadius) or 3.0
    local bucket = GetPlayerRoutingBucket(src)
    local identity = identityOf(xPlayer)
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

    Notify(src, ("Vous montrez votre carte d'identité (%d personne%s)."):format(count, count > 1 and 's' or ''), 'info')
end)

-- Guichet : état de la carte du joueur et prix
lib.callback.register('lunatic_gameplay:officeInfo', function(src, index)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not officeAt(src, index) then
        return nil
    end

    return {
        hasCard = hasCard(src), identity = xPlayer.get('firstName') ~= nil, price = cardPrice(xPlayer.identifier),
        cash = xPlayer.getAccount('money').money, bank = xPlayer.getAccount('bank').money,
    }
end)

-- Guichet : retrait de la carte (première gratuite, duplicata payé en liquide ou par carte)
lib.callback.register('lunatic_gameplay:officeIdcard', function(src, index, account)
    local xPlayer = ESX.GetPlayerFromId(src)
    local office = officeAt(src, index)

    if not xPlayer or not office then
        return { error = 'Vous êtes trop loin du guichet.' }
    end

    if not xPlayer.get('firstName') then
        return { error = "Vous n'avez pas encore d'identité." }
    end

    if hasCard(src) then
        return { error = 'Vous avez déjà votre carte sur vous.' }
    end

    if not ox:CanCarryItem(src, Config.IdCardItem, 1) then
        return { error = "Vous n'avez pas de place dans votre inventaire." }
    end

    local price = cardPrice(xPlayer.identifier)
    account = account == 'bank' and 'bank' or 'money'

    if price > 0 then
        if xPlayer.getAccount(account).money < price then
            return { error = account == 'bank' and 'Solde bancaire insuffisant.' or "Vous n'avez pas assez de liquide." }
        end

        xPlayer.removeAccountMoney(account, price, "Duplicata de carte d'identité")
    end

    ox:AddItem(src, Config.IdCardItem, 1)
    markIssued(xPlayer.identifier)
    GameLog('players', 'info', src, 'player.idcard', office.label, { price = price })

    return { ok = true, price = price }
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
