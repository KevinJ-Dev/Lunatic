-- Banque côté serveur : numéro de compte (IBAN) par personnage, historique des transactions, retrait, dépôt, virement.
-- L'argent reste celui d'ESX (compte « bank », liquide « money ») : cette ressource n'ajoute qu'un numéro et un historique.
-- Tout mouvement du compte bancaire est noté, même ceux des autres scripts (salaires, achats…), via les événements d'ESX.
-- Carte selon l'abonnement (lunatic_admin) : verte, jaune (VIP), noire (VIP+), avec ses plafonds sur 24 h glissantes.
-- Guichet des agences : tout ; distributeur : retrait et dépôt.
-- Le client n'est jamais cru : guichet ou distributeur ouvert, distance, montants, plafonds et soldes sont revérifiés ici.

local internal = {}     -- joueur -> true pendant une opération de la banque (déjà notée, pas de doublon)
local sessions = {}     -- joueur -> { bank = index } ou { atm = vector3 }
local lastTransfer = {} -- joueur -> dernier virement (anti-spam)

local IBAN_PATTERN = '^' .. Config.IbanPrefix .. '%d%d%d%d%d%d%d%d$'
local DAY = 86400
local ATM_DISTANCE = 3.0
local PERIODS = {
    week = { buckets = 7, size = DAY, format = '%d/%m' },
    month = { buckets = 4, size = 7 * DAY, format = '%d/%m' },
    year = { buckets = 12, size = 30 * DAY, format = '%m/%y' },
}
local CARDS = {
    standard = { label = 'Carte verte', color = 'green' },
    premium = { label = 'Carte jaune', color = 'gold' },
    premium_plus = { label = 'Carte noire', color = 'black' },
}
-- Plafond -> groupe des réglages de l'économie (panel : Économie → Autre → Banque)
local LIMIT_GROUPS = { withdraw = 'bankWithdraw', deposit = 'bank', transfer = 'bankTransfer' }

---------------------------------------------------------------------
-- Base de données
---------------------------------------------------------------------

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_bank_accounts` (
            `identifier` VARCHAR(64) NOT NULL,
            `iban` VARCHAR(16) NOT NULL,
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`identifier`),
            UNIQUE KEY `uniq_lunatic_bank_accounts_iban` (`iban`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- amount : positif = crédit, négatif = débit
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_bank_transactions` (
            `id` BIGINT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(64) NOT NULL,
            `kind` VARCHAR(16) NOT NULL,
            `amount` BIGINT NOT NULL,
            `label` VARCHAR(80) NOT NULL,
            `counterpart` VARCHAR(16) NULL,
            `message` VARCHAR(120) NULL,
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_bank_transactions_owner` (`identifier`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

local function record(identifier, kind, amount, label, counterpart, message)
    MySQL.insert('INSERT INTO `lunatic_bank_transactions` (`identifier`, `kind`, `amount`, `label`, `counterpart`, `message`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { identifier, kind, amount, label:sub(1, 80), counterpart, message, os.time() })
end

-- IBAN du personnage, créé à la première demande
local function ibanOf(identifier)
    local iban = MySQL.scalar.await('SELECT `iban` FROM `lunatic_bank_accounts` WHERE `identifier` = ?', { identifier })

    for _ = 1, 20 do
        if iban then
            return iban
        end

        local candidate = ('%s%08d'):format(Config.IbanPrefix, math.random(0, 99999999))
        MySQL.update.await('INSERT IGNORE INTO `lunatic_bank_accounts` (`identifier`, `iban`, `created_at`) VALUES (?, ?, ?)', { identifier, candidate, os.time() })
        -- Numéro déjà pris : nouvel essai ; compte créé entre-temps : on relit
        iban = MySQL.scalar.await('SELECT `iban` FROM `lunatic_bank_accounts` WHERE `identifier` = ?', { identifier })
    end
end

---------------------------------------------------------------------
-- Mouvements des autres scripts (salaires, achats, amendes…)
---------------------------------------------------------------------

local function reasonLabel(reason, fallback)
    if type(reason) ~= 'string' or reason == '' or reason == 'Unknown' then
        return fallback
    end

    return reason
end

local function onAccountChange(src, account, money, reason, sign)
    if account ~= 'bank' or internal[src] then
        return
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    money = math.floor(tonumber(money) or 0)

    if xPlayer and money > 0 then
        record(xPlayer.identifier, sign > 0 and 'credit' or 'debit', sign * money, reasonLabel(reason, sign > 0 and 'Crédit' or 'Débit'))
    end
end

AddEventHandler('esx:addAccountMoney', function(src, account, money, reason)
    onAccountChange(src, account, money, reason, 1)
end)

AddEventHandler('esx:removeAccountMoney', function(src, account, money, reason)
    onAccountChange(src, account, money, reason, -1)
end)

---------------------------------------------------------------------
-- Carte et plafonds
---------------------------------------------------------------------

-- Abonnement du joueur (lunatic_admin) : standard, premium ou premium_plus
local function tierOf(src)
    local ok, premium = pcall(function() return exports.lunatic_admin:getPremium(src) end)
    local tier = ok and type(premium) == 'table' and premium.tier or nil
    return CARDS[tier] and tier or 'standard'
end

-- Plafond sur 24 h réglé dans le panel, sinon celui de la config
local function limitOf(tier, kind)
    local economy = GlobalState.lunaticEconomy
    local group = type(economy) == 'table' and economy[LIMIT_GROUPS[kind]]
    local value = type(group) == 'table' and tonumber(group[tier]) or nil
    return math.floor(value or Config.Limits[kind][tier])
end

-- Retraits, dépôts et virements émis des dernières 24 h
local function usedOf(identifier)
    local rows = MySQL.query.await([[
        SELECT `kind`, SUM(ABS(`amount`)) AS `total` FROM `lunatic_bank_transactions`
        WHERE `identifier` = ? AND `created_at` > ? AND `kind` IN ('withdraw', 'deposit', 'transfer_out') GROUP BY `kind`
    ]], { identifier, os.time() - DAY }) or {}
    local used = { withdraw = 0, deposit = 0, transfer = 0 }

    for _, row in ipairs(rows) do
        used[row.kind == 'transfer_out' and 'transfer' or row.kind] = tonumber(row.total) or 0
    end

    return used
end

local function cardOf(src, identifier)
    local tier = tierOf(src)
    local used = usedOf(identifier)
    local limits = {}

    for kind in pairs(LIMIT_GROUPS) do
        limits[kind] = { used = used[kind], max = limitOf(tier, kind) }
    end

    return { tier = tier, label = CARDS[tier].label, color = CARDS[tier].color, limits = limits }
end

-- Message d'erreur si l'opération dépasse le plafond de la carte
local function overLimit(src, identifier, kind, amount)
    local card = cardOf(src, identifier)
    local limit = card.limits[kind]

    if limit.used + amount > limit.max then
        return ('Plafond de votre %s : encore %d $ possibles sur 24 h.'):format(card.label:lower(), math.max(0, limit.max - limit.used))
    end
end

---------------------------------------------------------------------
-- Session au guichet ou au distributeur
---------------------------------------------------------------------

local function nearBank(src, index)
    local bank = Banks()[tonumber(index) or 0]
    local ped = GetPlayerPed(src)

    return bank and ped ~= 0 and #(GetEntityCoords(ped) - vector3(bank.x, bank.y, bank.z)) <= Config.ServerDistance and bank or nil
end

local function nearPoint(src, point)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - point) <= ATM_DISTANCE
end

-- Joueur ESX et session si le guichet ou le distributeur est toujours ouvert et à portée
local function sessionOf(src)
    local session = sessions[src]
    local valid = session and (session.atm and nearPoint(src, session.atm) or session.bank and nearBank(src, session.bank))

    if not valid then
        sessions[src] = nil
        return nil
    end

    return ESX.GetPlayerFromId(src), session
end

local function rpName(xPlayer)
    local first, last = xPlayer.get('firstName'), xPlayer.get('lastName')

    if type(first) == 'string' and first ~= '' and type(last) == 'string' and last ~= '' then
        return ('%s %s'):format(first, last)
    end

    return xPlayer.getName()
end

local function nameOf(identifier)
    local row = MySQL.single.await('SELECT `firstname`, `lastname` FROM `users` WHERE `identifier` = ?', { identifier })
    return row and row.firstname and ('%s %s'):format(row.firstname, row.lastname or '') or 'Titulaire inconnu'
end

-- Crédits et débits par période glissante (le plus récent à droite)
local function chartOf(identifier, period)
    local spec = PERIODS[period] or PERIODS.week
    local now = os.time()
    local rows = MySQL.query.await([[
        SELECT FLOOR((? - `created_at`) / ?) AS `bucket`, SUM(GREATEST(`amount`, 0)) AS `credit`, SUM(GREATEST(-`amount`, 0)) AS `debit`
        FROM `lunatic_bank_transactions` WHERE `identifier` = ? AND `created_at` > ? GROUP BY `bucket`
    ]], { now, spec.size, identifier, now - spec.buckets * spec.size }) or {}

    local byBucket = {}

    for _, row in ipairs(rows) do
        byBucket[tonumber(row.bucket)] = row
    end

    local bars = {}

    for bucket = spec.buckets - 1, 0, -1 do
        local row = byBucket[bucket]
        bars[#bars + 1] = {
            label = os.date(spec.format, now - bucket * spec.size),
            credit = row and tonumber(row.credit) or 0,
            debit = row and tonumber(row.debit) or 0,
        }
    end

    return bars
end

local function stateOf(xPlayer, period)
    local src = xPlayer.source
    local identifier = xPlayer.identifier
    local session = sessions[src] or {}
    local bank = session.bank and Banks()[session.bank]
    local atm = session.atm ~= nil

    return {
        atm = atm,
        bank = atm and 'Distributeur' or bank and bank.label or 'Banque',
        name = rpName(xPlayer),
        iban = ibanOf(identifier),
        balance = xPlayer.getAccount('bank').money,
        cash = xPlayer.getAccount('money').money,
        card = cardOf(src, identifier),
        -- Le distributeur n'affiche que le compte : pas d'historique ni d'analyse à charger
        history = not atm and MySQL.query.await('SELECT `kind`, `amount`, `label`, `counterpart`, `message`, `created_at` AS `at` FROM `lunatic_bank_transactions` WHERE `identifier` = ? ORDER BY `id` DESC LIMIT ?',
            { identifier, Config.HistoryLimit }) or {},
        period = PERIODS[period] and period or 'week',
        chart = not atm and chartOf(identifier, period) or {},
        shortcuts = Config.Shortcuts,
        max = Config.MaxAmount,
    }
end

local function log(src, action, details)
    pcall(function() exports.lunatic_admin:log('economy', 'info', src, action, nil, details) end)
end

local function amountOf(value)
    local amount = math.floor(tonumber(value) or 0)
    return amount >= 1 and amount <= Config.MaxAmount and amount or nil
end

local function fail(message)
    return { error = message }
end

lib.callback.register('lunatic_bank:open', function(src, index)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not nearBank(src, index) then
        return fail('Trop loin du guichet.')
    end

    sessions[src] = { bank = tonumber(index) }
    return stateOf(xPlayer, 'week')
end)

-- Distributeur : le serveur ne voit pas les objets de la carte, il vérifie que le joueur est bien à l'endroit indiqué
lib.callback.register('lunatic_bank:openAtm', function(src, coords)
    local xPlayer = ESX.GetPlayerFromId(src)
    local x, y, z = type(coords) == 'table' and tonumber(coords.x), type(coords) == 'table' and tonumber(coords.y), type(coords) == 'table' and tonumber(coords.z)

    if not xPlayer or not x or not y or not z or not nearPoint(src, vector3(x, y, z)) then
        return fail('Trop loin du distributeur.')
    end

    sessions[src] = { atm = vector3(x, y, z) }
    return stateOf(xPlayer, 'week')
end)

RegisterNetEvent('lunatic_bank:close', function()
    sessions[source] = nil
end)

lib.callback.register('lunatic_bank:chart', function(src, period)
    local xPlayer = sessionOf(src)
    return xPlayer and { period = PERIODS[period] and period or 'week', chart = chartOf(xPlayer.identifier, period) } or fail('Guichet fermé.')
end)

---------------------------------------------------------------------
-- Opérations
---------------------------------------------------------------------

-- Opération de la banque : les événements d'ESX qu'elle déclenche ne sont pas notés une seconde fois
local function quietly(src, fn)
    internal[src] = true
    local ok, result = pcall(fn)
    internal[src] = nil
    return ok and result
end

local function placeOf(session)
    return session.atm and 'au distributeur' or 'au guichet'
end

lib.callback.register('lunatic_bank:withdraw', function(src, data)
    local xPlayer, session = sessionOf(src)
    local amount = amountOf(type(data) == 'table' and data.amount)

    if not xPlayer then
        return fail('Guichet fermé.')
    elseif not amount then
        return fail(('Montant entre 1 et %d $.'):format(Config.MaxAmount))
    elseif xPlayer.getAccount('bank').money < amount then
        return fail('Solde insuffisant.')
    end

    local limit = overLimit(src, xPlayer.identifier, 'withdraw', amount)

    if limit then
        return fail(limit)
    end

    local label = ('Retrait %s'):format(placeOf(session))
    local ok = quietly(src, function()
        if not xPlayer.removeAccountMoney('bank', amount, label) then
            return false
        end

        if not xPlayer.addAccountMoney('money', amount, label) then
            xPlayer.addAccountMoney('bank', amount, 'Retrait annulé')
            return false
        end

        return true
    end)

    if not ok then
        return fail('Retrait impossible (poches pleines ?).')
    end

    record(xPlayer.identifier, 'withdraw', -amount, label)
    log(src, 'bank.withdraw', { amount = amount, atm = session.atm ~= nil })
    return { ok = true, message = ('Retrait de %d $.'):format(amount), state = stateOf(xPlayer, data.period) }
end)

lib.callback.register('lunatic_bank:deposit', function(src, data)
    local xPlayer, session = sessionOf(src)
    local amount = amountOf(type(data) == 'table' and data.amount)

    if not xPlayer then
        return fail('Guichet fermé.')
    elseif not amount then
        return fail(('Montant entre 1 et %d $.'):format(Config.MaxAmount))
    elseif xPlayer.getAccount('money').money < amount then
        return fail("Vous n'avez pas assez de liquide.")
    end

    local limit = overLimit(src, xPlayer.identifier, 'deposit', amount)

    if limit then
        return fail(limit)
    end

    local label = ('Dépôt %s'):format(placeOf(session))
    local ok = quietly(src, function()
        if not xPlayer.removeAccountMoney('money', amount, label) then
            return false
        end

        xPlayer.addAccountMoney('bank', amount, label)
        return true
    end)

    if not ok then
        return fail('Dépôt impossible.')
    end

    record(xPlayer.identifier, 'deposit', amount, label)
    log(src, 'bank.deposit', { amount = amount, atm = session.atm ~= nil })
    return { ok = true, message = ('Dépôt de %d $.'):format(amount), state = stateOf(xPlayer, data.period) }
end)

lib.callback.register('lunatic_bank:transfer', function(src, data)
    local xPlayer, session = sessionOf(src)
    data = type(data) == 'table' and data or {}
    local amount = amountOf(data.amount)
    local iban = type(data.iban) == 'string' and data.iban:upper():gsub('%s', '') or ''
    local message = type(data.message) == 'string' and data.message:gsub('[%c<>]', ''):sub(1, 120) or ''
    local now = os.time()

    if not xPlayer or session.atm then
        return fail("Les virements se font au guichet d'une agence.")
    elseif not iban:match(IBAN_PATTERN) then
        return fail(('IBAN invalide (%s suivi de 8 chiffres).'):format(Config.IbanPrefix))
    elseif not amount then
        return fail(('Montant entre 1 et %d $.'):format(Config.MaxAmount))
    elseif (lastTransfer[src] or 0) > now - Config.TransferCooldown then
        return fail('Patientez un instant entre deux virements.')
    end

    lastTransfer[src] = now
    local target = MySQL.scalar.await('SELECT `identifier` FROM `lunatic_bank_accounts` WHERE `iban` = ?', { iban })

    if not target then
        return fail('Aucun compte avec cet IBAN.')
    elseif target == xPlayer.identifier then
        return fail('Vous ne pouvez pas vous faire un virement à vous-même.')
    elseif xPlayer.getAccount('bank').money < amount then
        return fail('Solde insuffisant.')
    end

    local limit = overLimit(src, xPlayer.identifier, 'transfer', amount)

    if limit then
        return fail(limit)
    end

    if not quietly(src, function() return xPlayer.removeAccountMoney('bank', amount, 'Virement émis') end) then
        return fail('Virement impossible.')
    end

    local senderName, senderIban = rpName(xPlayer), ibanOf(xPlayer.identifier)
    local receiver = ESX.GetPlayerFromIdentifier(target)
    local receiverName

    if receiver then
        receiverName = rpName(receiver)
        quietly(receiver.source, function() return receiver.addAccountMoney('bank', amount, 'Virement reçu') end)
        TriggerClientEvent('esx:showNotification', receiver.source, ('Virement reçu : %d $ de %s.'):format(amount, senderName), 'success')
    else
        -- Destinataire hors ligne : son compte ESX est modifié directement en base
        receiverName = nameOf(target)
        local changed = MySQL.update.await("UPDATE `users` SET `accounts` = JSON_SET(`accounts`, '$.bank', COALESCE(JSON_EXTRACT(`accounts`, '$.bank'), 0) + ?) WHERE `identifier` = ?", { amount, target })

        if not changed or changed == 0 then
            quietly(src, function() return xPlayer.addAccountMoney('bank', amount, 'Virement annulé') end)
            return fail('Compte du destinataire introuvable.')
        end
    end

    record(xPlayer.identifier, 'transfer_out', -amount, ('Virement à %s'):format(receiverName), iban, message ~= '' and message or nil)
    record(target, 'transfer_in', amount, ('Virement de %s'):format(senderName), senderIban, message ~= '' and message or nil)
    log(src, 'bank.transfer', { amount = amount, iban = iban, to = receiverName })

    return { ok = true, message = ('Virement de %d $ envoyé à %s.'):format(amount, receiverName), state = stateOf(xPlayer, data.period) }
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
    lastTransfer[source] = nil
end)

-- Pour d'autres scripts (téléphone, factures…) : IBAN d'un joueur connecté
exports('getIban', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and ibanOf(xPlayer.identifier) or nil
end)

-- Agences par défaut, pour la page « Banques » du panel
exports('getDefaultBanks', function()
    return Config.Banks
end)
