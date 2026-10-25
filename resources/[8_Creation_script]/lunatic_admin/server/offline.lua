-- Lot F : joueurs hors ligne. Recherche dans la table users d'ESX, fiche et actions directement en base.
-- Un joueur connecté est refusé ici (ESX réécrirait ses données à la sauvegarde) : on passe par sa fiche en ligne.

local ACCOUNTS = {
    money = { label = 'liquide', permission = 'economy.money' },
    bank = { label = 'banque', permission = 'economy.money' },
    black_money = { label = 'argent sale', permission = 'economy.black_money' },
}

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

-- Identifiant ESX (table users) = licence Rockstar sans le préfixe « license: »
local function cleanIdentifier(value)
    if type(value) ~= 'string' then
        return nil
    end

    local identifier = value:gsub('^license:', '')
    return identifier:match('^%x+$') and #identifier <= 60 and identifier or nil
end

local function licenseOf(identifier)
    return 'license:' .. identifier
end

local function rpName(row)
    if row.firstname and row.firstname ~= '' then
        return ('%s %s'):format(row.firstname, row.lastname or '')
    end

    return 'Sans identité'
end

local function cleanReason(value, min)
    if type(value) ~= 'string' then
        return nil
    end

    local reason = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(reason)

    if not length or length < (min or Config.SanctionReasonMin) or length > Config.SanctionReasonMax then
        return nil
    end

    return reason
end

-- Vérifications communes : permission « hors ligne » + permission de l'action, joueur existant, déconnecté, non protégé
---@return string|nil identifier, table|nil row, table|nil error
local function offlineTarget(actor, data, permission)
    if not Ranks.hasPermission(actor, 'players.offline') then
        return nil, nil, Panel.fail("Vous n'avez pas la permission d'agir sur les joueurs hors ligne.")
    end

    if permission and not Ranks.hasPermission(actor, permission) then
        return nil, nil, denied()
    end

    local identifier = cleanIdentifier(data.identifier)

    if not identifier then
        return nil, nil, Panel.fail('Joueur introuvable.')
    end

    local row = MySQL.single.await('SELECT `identifier`, `firstname`, `lastname`, `accounts`, `job`, `job_grade` FROM `users` WHERE `identifier` = ?', { identifier })

    if not row then
        return nil, nil, Panel.fail('Joueur introuvable en base.')
    end

    if Staff.sourceOf(licenseOf(identifier)) then
        return nil, nil, Panel.fail('Ce joueur est connecté : utilisez sa fiche dans « En ligne ».')
    end

    local member = Staff.get(licenseOf(identifier))
    local rank = member and Ranks.get(member.rankId)

    if rank and rank.level >= actor.level then
        return nil, nil, Panel.fail('Ce membre du staff a un rang égal ou supérieur au vôtre.')
    end

    return identifier, row
end

local function decodeAccounts(raw)
    local ok, accounts = pcall(json.decode, raw or '{}')
    return ok and type(accounts) == 'table' and accounts or {}
end

local function formatMoney(amount)
    local text = tostring(math.floor(amount)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', '')
    return text .. ' ' .. (GlobalState.lunaticCurrency or '$')
end

---------------------------------------------------------------------
-- Recherche et fiche
---------------------------------------------------------------------

Panel.actions['offline.search'] = function(_, actor, data)
    if not Ranks.hasPermission(actor, 'players.offline') then
        return denied()
    end

    local query = type(data.query) == 'string' and data.query:match('^%s*(.-)%s*$') or ''

    if utf8.len(query) == nil or utf8.len(query) < 2 then
        return { ok = true, silent = true, players = {} }
    end

    local like = '%' .. query:sub(1, 60):gsub('[%%_\\]', '\\%0') .. '%'
    local identifierLike = '%' .. query:gsub('^license:', ''):sub(1, 60):gsub('[%%_\\]', '\\%0') .. '%'

    local rows = MySQL.query.await([[
        SELECT `identifier`, `firstname`, `lastname`, UNIX_TIMESTAMP(`last_seen`) AS `last_seen`
        FROM `users`
        WHERE CONCAT_WS(' ', `firstname`, `lastname`) LIKE ? OR `identifier` LIKE ?
        ORDER BY `last_seen` DESC
        LIMIT 30
    ]], { like, identifierLike }) or {}

    local list = {}

    for _, row in ipairs(rows) do
        list[#list + 1] = {
            identifier = row.identifier,
            name = rpName(row),
            lastSeen = tonumber(row.last_seen),
            online = Staff.sourceOf(licenseOf(row.identifier)),
        }
    end

    return { ok = true, silent = true, players = list }
end

Panel.actions['offline.info'] = function(_, actor, data)
    if not Ranks.hasPermission(actor, 'players.offline') then
        return denied()
    end

    local identifier = cleanIdentifier(data.identifier)
    local row = identifier and MySQL.single.await([[
        SELECT `identifier`, `firstname`, `lastname`, `dateofbirth`, `sex`, `height`, `accounts`, `job`, `job_grade`,
               UNIX_TIMESTAMP(`last_seen`) AS `last_seen`, UNIX_TIMESTAMP(`created_at`) AS `created_at`
        FROM `users` WHERE `identifier` = ?
    ]], { identifier })

    if not row then
        return Panel.fail('Joueur introuvable en base.')
    end

    local license = licenseOf(identifier)
    local accounts = decodeAccounts(row.accounts)
    local jobs = ESX.GetJobs()
    local job = jobs[row.job]
    local grade = job and job.grades and job.grades[tostring(row.job_grade)]
    local member = Staff.get(license)
    local rank = member and Ranks.get(member.rankId)

    return {
        ok = true,
        silent = true,
        info = {
            identifier = identifier,
            license = license,
            name = rpName(row),
            hasIdentity = row.firstname ~= nil and row.firstname ~= '',
            dateofbirth = row.dateofbirth,
            sex = row.sex,
            height = row.height,
            money = tonumber(accounts.money) or 0,
            bank = tonumber(accounts.bank) or 0,
            blackMoney = tonumber(accounts.black_money) or 0,
            job = { name = row.job, label = job and job.label or row.job, grade = grade and grade.label or tostring(row.job_grade), level = tonumber(row.job_grade) },
            lastSeen = tonumber(row.last_seen),
            createdAt = tonumber(row.created_at),
            online = Staff.sourceOf(license),
            rank = rank and { name = rank.name, color = rank.color } or nil,
            protected = rank ~= nil and rank.level >= actor.level,
            licenses = Panel.licensesOf and Panel.licensesOf(identifier) or {},
            premium = Panel.premiumOf and Panel.premiumOf(license) or nil,
            credits = Panel.creditsOf and Panel.creditsOf(license) or nil,
            profile = Accounts.profile(license, identifier),
        },
    }
end

---------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------

Panel.actions['offline.money'] = function(src, actor, data)
    local account = type(data.account) == 'string' and ACCOUNTS[data.account]

    if not account then
        return Panel.fail('Compte inconnu.')
    end

    local identifier, row, err = offlineTarget(actor, data, account.permission)

    if not identifier then
        return err
    end

    local operation = data.operation

    if operation ~= 'add' and operation ~= 'remove' and operation ~= 'set' then
        return Panel.fail('Opération inconnue.')
    end

    local max = not actor.owner and Config.MaxMoneyAction or nil
    local amount = tonumber(data.amount)

    if not amount or amount ~= math.floor(amount) or amount < (operation == 'set' and 0 or 1) or (max and amount > max) then
        return Panel.fail(max and ('Montant invalide (maximum %s par opération).'):format(formatMoney(max)) or 'Montant invalide.')
    end

    local reason = cleanReason(data.reason, Config.EconomyReasonMin)

    if not reason then
        return Panel.fail('La raison est obligatoire (3 caractères minimum).')
    end

    local accounts = decodeAccounts(row.accounts)
    local before = tonumber(accounts[data.account]) or 0
    local after

    if operation == 'add' then
        after = before + amount
    elseif operation == 'remove' then
        if amount > before then
            return Panel.fail(("Le joueur n'a que %s en %s."):format(formatMoney(before), account.label))
        end

        after = before - amount
    else
        after = amount
    end

    accounts[data.account] = after
    MySQL.update.await('UPDATE `users` SET `accounts` = ? WHERE `identifier` = ?', { json.encode(accounts), identifier })

    Logs.add(src, 'economy.money', rpName(row) .. ' (hors ligne)', {
        identifier = identifier, account = data.account, operation = operation, amount = amount, before = before, after = after, reason = reason,
    })

    return { ok = true, silent = true, before = before, after = after }
end

Panel.actions['offline.setJob'] = function(src, actor, data)
    local identifier, row, err = offlineTarget(actor, data, 'economy.job')

    if not identifier then
        return err
    end

    local job, grade = type(data.job) == 'string' and data.job, tonumber(data.grade)

    if not job or not grade or not ESX.DoesJobExist(job, grade) then
        return Panel.fail('Métier ou grade inconnu.')
    end

    MySQL.update.await('UPDATE `users` SET `job` = ?, `job_grade` = ? WHERE `identifier` = ?', { job, grade, identifier })
    Logs.add(src, 'economy.setJob', rpName(row) .. ' (hors ligne)', {
        identifier = identifier, before = ('%s (%s)'):format(row.job, row.job_grade), after = ('%s (%s)'):format(job, grade),
    })

    return { ok = true, silent = true }
end

Panel.actions['offline.license'] = function(src, actor, data)
    local identifier, row, err = offlineTarget(actor, data, 'players.licenses')

    if not identifier then
        return err
    end

    local valid = false

    for _, entry in ipairs(Panel.licensesOf and Panel.licensesOf(identifier) or {}) do
        if entry.type == data.type then
            valid = true
        end
    end

    if not valid then
        return Panel.fail('Permis inconnu.')
    end

    if data.owned == true then
        local exists = MySQL.scalar.await('SELECT COUNT(*) FROM `user_licenses` WHERE `owner` = ? AND `type` = ?', { identifier, data.type })

        if (tonumber(exists) or 0) == 0 then
            MySQL.insert.await('INSERT INTO `user_licenses` (`type`, `owner`) VALUES (?, ?)', { data.type, identifier })
        end
    else
        MySQL.update.await('DELETE FROM `user_licenses` WHERE `owner` = ? AND `type` = ?', { identifier, data.type })
    end

    Logs.add(src, data.owned == true and 'license.give' or 'license.remove', rpName(row) .. ' (hors ligne)', { identifier = identifier, license = data.type })
    return { ok = true, silent = true }
end

-- Efface l'identité et l'apparence : lunatic_creator ouvrira la création de personnage à la prochaine connexion
Panel.actions['offline.recreate'] = function(src, actor, data)
    local identifier, row, err = offlineTarget(actor, data, 'players.recreate')

    if not identifier then
        return err
    end

    local reason = cleanReason(data.reason)

    if not reason then
        return Panel.fail('La raison est obligatoire (3 caractères minimum).')
    end

    MySQL.update.await('UPDATE `users` SET `firstname` = NULL, `lastname` = NULL, `dateofbirth` = NULL, `sex` = NULL, `height` = NULL, `skin` = NULL WHERE `identifier` = ?', { identifier })
    Logs.add(src, 'player.recreate', rpName(row) .. ' (hors ligne)', { identifier = identifier, reason = reason })

    return { ok = true, silent = true }
end

Panel.actions['offline.wipe'] = function(src, actor, data)
    local identifier, row, err = offlineTarget(actor, data, 'players.wipe')

    if not identifier then
        return err
    end

    local name = rpName(row)

    if type(data.confirm) ~= 'string' or data.confirm:lower():match('^%s*(.-)%s*$') ~= name:lower() then
        return Panel.fail('Le nom tapé ne correspond pas : wipe annulé.')
    end

    local reason = cleanReason(data.reason)

    if not reason then
        return Panel.fail('La raison est obligatoire (3 caractères minimum).')
    end

    -- État avant wipe, gardé dans les logs
    local snapshot = { accounts = decodeAccounts(row.accounts), job = ('%s (%s)'):format(row.job, row.job_grade), vehicles = {}, licenses = {} }

    for _, vehicle in ipairs(MySQL.query.await('SELECT `plate` FROM `owned_vehicles` WHERE `owner` = ?', { identifier }) or {}) do
        snapshot.vehicles[#snapshot.vehicles + 1] = vehicle.plate
    end

    for _, license in ipairs(MySQL.query.await('SELECT `type` FROM `user_licenses` WHERE `owner` = ?', { identifier }) or {}) do
        snapshot.licenses[#snapshot.licenses + 1] = license.type
    end

    snapshot.inventory = MySQL.scalar.await('SELECT `inventory` FROM `users` WHERE `identifier` = ?', { identifier })

    local starting = ESX.GetConfig('StartingAccountMoney') or {}
    local accounts = { money = starting.money or 0, bank = starting.bank or 0, black_money = starting.black_money or 0 }

    MySQL.update.await([[
        UPDATE `users` SET `accounts` = ?, `inventory` = '[]', `loadout` = '[]', `job` = 'unemployed', `job_grade` = 0,
            `firstname` = NULL, `lastname` = NULL, `dateofbirth` = NULL, `sex` = NULL, `height` = NULL, `skin` = NULL
        WHERE `identifier` = ?
    ]], { json.encode(accounts), identifier })
    MySQL.update.await('DELETE FROM `owned_vehicles` WHERE `owner` = ?', { identifier })
    MySQL.update.await('DELETE FROM `user_licenses` WHERE `owner` = ?', { identifier })

    Logs.add(src, 'player.wipe', name .. ' (hors ligne)', { identifier = identifier, reason = reason, before = snapshot })
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Joueurs hors ligne chargé.')
