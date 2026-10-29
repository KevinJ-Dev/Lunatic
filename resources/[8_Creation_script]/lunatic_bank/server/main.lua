-- Banque côté serveur : numéro de compte (IBAN) par personnage, historique des transactions, retrait, dépôt, virement.
-- L'argent reste celui d'ESX (compte « bank », liquide « money ») : cette ressource n'ajoute qu'un numéro et un historique.
-- Tout mouvement du compte bancaire est noté, même ceux des autres scripts (salaires, achats…), via les événements d'ESX.
-- Le client n'est jamais cru : agence ouverte, distance, montants et soldes sont revérifiés ici.

local internal = {}     -- joueur -> true pendant une opération de la banque (déjà notée, pas de doublon)
local sessions = {}     -- joueur -> index de l'agence ouverte
local lastTransfer = {} -- joueur -> dernier virement (anti-spam)

local IBAN_PATTERN = '^' .. Config.IbanPrefix .. '%d%d%d%d%d%d%d%d$'
local PERIODS = {
    week = { buckets = 7, size = 86400, format = '%d/%m' },
    month = { buckets = 4, size = 7 * 86400, format = '%d/%m' },
    year = { buckets = 12, size = 30 * 86400, format = '%m/%y' },
}

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
-- Session au guichet
---------------------------------------------------------------------

local function nearBank(src, index)
    local bank = Banks()[tonumber(index) or 0]
    local ped = GetPlayerPed(src)

    return bank and ped ~= 0 and #(GetEntityCoords(ped) - vector3(bank.x, bank.y, bank.z)) <= Config.ServerDistance and bank or nil
end

-- Joueur ESX si son guichet est toujours ouvert et à portée
local function sessionOf(src)
    local index = sessions[src]

    if not index or not nearBank(src, index) then
        sessions[src] = nil
        return nil
    end

    return ESX.GetPlayerFromId(src)
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
    local identifier = xPlayer.identifier
    local bank = Banks()[sessions[xPlayer.source]]

    return {
        bank = bank and bank.label or 'Banque',
        name = rpName(xPlayer),
        iban = ibanOf(identifier),
        balance = xPlayer.getAccount('bank').money,
        cash = xPlayer.getAccount('money').money,
        history = MySQL.query.await('SELECT `kind`, `amount`, `label`, `counterpart`, `message`, `created_at` AS `at` FROM `lunatic_bank_transactions` WHERE `identifier` = ? ORDER BY `id` DESC LIMIT ?',
            { identifier, Config.HistoryLimit }) or {},
        period = PERIODS[period] and period or 'week',
        chart = chartOf(identifier, period),
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

    sessions[src] = tonumber(index)
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

lib.callback.register('lunatic_bank:withdraw', function(src, data)
    local xPlayer = sessionOf(src)
    local amount = amountOf(type(data) == 'table' and data.amount)

    if not xPlayer then
        return fail('Guichet fermé.')
    elseif not amount then
        return fail(('Montant entre 1 et %d $.'):format(Config.MaxAmount))
    elseif xPlayer.getAccount('bank').money < amount then
        return fail('Solde insuffisant.')
    end

    local ok = quietly(src, function()
        if not xPlayer.removeAccountMoney('bank', amount, 'Retrait au guichet') then
            return false
        end

        if not xPlayer.addAccountMoney('money', amount, 'Retrait au guichet') then
            xPlayer.addAccountMoney('bank', amount, 'Retrait annulé')
            return false
        end

        return true
    end)

    if not ok then
        return fail('Retrait impossible (poches pleines ?).')
    end

    record(xPlayer.identifier, 'withdraw', -amount, 'Retrait au guichet')
    log(src, 'bank.withdraw', { amount = amount })
    return { ok = true, message = ('Retrait de %d $.'):format(amount), state = stateOf(xPlayer, data.period) }
end)

lib.callback.register('lunatic_bank:deposit', function(src, data)
    local xPlayer = sessionOf(src)
    local amount = amountOf(type(data) == 'table' and data.amount)

    if not xPlayer then
        return fail('Guichet fermé.')
    elseif not amount then
        return fail(('Montant entre 1 et %d $.'):format(Config.MaxAmount))
    elseif xPlayer.getAccount('money').money < amount then
        return fail("Vous n'avez pas assez de liquide.")
    end

    local ok = quietly(src, function()
        if not xPlayer.removeAccountMoney('money', amount, 'Dépôt au guichet') then
            return false
        end

        xPlayer.addAccountMoney('bank', amount, 'Dépôt au guichet')
        return true
    end)

    if not ok then
        return fail('Dépôt impossible.')
    end

    record(xPlayer.identifier, 'deposit', amount, 'Dépôt au guichet')
    log(src, 'bank.deposit', { amount = amount })
    return { ok = true, message = ('Dépôt de %d $.'):format(amount), state = stateOf(xPlayer, data.period) }
end)

lib.callback.register('lunatic_bank:transfer', function(src, data)
    local xPlayer = sessionOf(src)
    data = type(data) == 'table' and data or {}
    local amount = amountOf(data.amount)
    local iban = type(data.iban) == 'string' and data.iban:upper():gsub('%s', '') or ''
    local message = type(data.message) == 'string' and data.message:gsub('[%c<>]', ''):sub(1, 120) or ''
    local now = os.time()

    if not xPlayer then
        return fail('Guichet fermé.')
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
