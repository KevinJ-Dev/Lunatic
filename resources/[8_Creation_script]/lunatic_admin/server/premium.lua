-- Lot G : abonnements Premium / Premium+ et crédits boutique.
-- Les autres scripts lisent l'abonnement par export (serveur) ou par l'état du joueur (client : LocalPlayer.state.premium).

---@type table<string, {tier:string, expires:number|nil}> abonnements actifs par licence
local premiums = {}

local now = Util.now

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

local function isExpired(entry)
    return entry.expires ~= nil and entry.expires <= now()
end

-- Publie l'abonnement dans l'état du joueur connecté (lisible par les scripts clients)
local function publish(license)
    local src = Staff.sourceOf(license)

    if src then
        local entry = premiums[license]
        Player(src).state:set('premium', entry and entry.tier or nil, true)
    end
end

local function expire(license)
    premiums[license] = nil
    MySQL.update('DELETE FROM `lunatic_admin_premium` WHERE `license` = ?', { license })
    publish(license)

    local src = Staff.sourceOf(license)

    if src then
        Panel.notify(src, 'Votre abonnement est arrivé à expiration.', 'info')
    end
end

table.insert(Panel.readyHooks, function()
    for _, row in ipairs(MySQL.query.await('SELECT `license`, `tier`, `expires_at` FROM `lunatic_admin_premium`') or {}) do
        premiums[row.license] = { tier = row.tier, expires = tonumber(row.expires_at) }
    end

    for license, entry in pairs(premiums) do
        if isExpired(entry) then
            expire(license)
        else
            publish(license)
        end
    end
end)

-- Expirations vérifiées chaque minute
CreateThread(function()
    while true do
        Wait(60000)

        for license, entry in pairs(premiums) do
            if isExpired(entry) then
                expire(license)
            end
        end
    end
end)

-- À l'arrivée d'un joueur, son abonnement est publié
AddEventHandler('esx:playerLoaded', function(playerId)
    local license = GetPlayerIdentifierByType(tonumber(playerId), 'license')

    if license and premiums[license] then
        publish(license)
    end
end)

---------------------------------------------------------------------
-- Lecture (fiches et exports)
---------------------------------------------------------------------

---@return {tier:string, label:string, color:string, expires:number|nil}|nil
function Panel.premiumOf(license)
    local entry = premiums[license]

    if not entry or isExpired(entry) then
        return nil
    end

    local tier = Config.PremiumTiers[entry.tier] or { label = entry.tier, color = '#9650ff' }
    return { tier = entry.tier, label = tier.label, color = tier.color, expires = entry.expires }
end

function Panel.creditsOf(license)
    return tonumber(MySQL.scalar.await('SELECT `balance` FROM `lunatic_admin_credits` WHERE `license` = ?', { license })) or 0
end

-- exports.lunatic_admin:getPremium(source) -> { tier, label, expires } ou nil
exports('getPremium', function(src)
    local license = GetPlayerIdentifierByType(tonumber(src), 'license')
    return license and Panel.premiumOf(license) or nil
end)

-- exports.lunatic_admin:isPremium(source, 'premium_plus') : Premium+ inclut Premium
exports('isPremium', function(src, minimum)
    local license = GetPlayerIdentifierByType(tonumber(src), 'license')
    local premium = license and Panel.premiumOf(license)

    if not premium then
        return false
    end

    return minimum ~= 'premium_plus' or premium.tier == 'premium_plus'
end)

-- exports.lunatic_admin:getCredits(source)
exports('getCredits', function(src)
    local license = GetPlayerIdentifierByType(tonumber(src), 'license')
    return license and Panel.creditsOf(license) or 0
end)

---------------------------------------------------------------------
-- Cible : joueur connecté (serverId) ou trouvé hors ligne (identifier)
---------------------------------------------------------------------

---@return string|nil license, string|nil name, table|nil error
local function targetOf(src, actor, data)
    local license, name

    if tonumber(data.serverId) then
        local target = tonumber(data.serverId)

        if not GetPlayerName(target) then
            return nil, nil, Panel.fail("Ce joueur n'est plus connecté.")
        end

        license, name = GetPlayerIdentifierByType(target, 'license'), Staff.displayName(target)
    elseif type(data.identifier) == 'string' then
        if not Ranks.hasPermission(actor, 'players.offline') then
            return nil, nil, Panel.fail("Vous n'avez pas la permission d'agir sur les joueurs hors ligne.")
        end

        local identifier = data.identifier:gsub('^license:', '')
        local row = identifier:match('^%x+$') and MySQL.single.await('SELECT `firstname`, `lastname` FROM `users` WHERE `identifier` = ?', { identifier })

        if not row then
            return nil, nil, Panel.fail('Joueur introuvable en base.')
        end

        license = 'license:' .. identifier
        name = row.firstname and ('%s %s'):format(row.firstname, row.lastname or '') or identifier
    else
        return nil, nil, Panel.fail('Joueur introuvable.')
    end

    if not license then
        return nil, nil, Panel.fail('Licence introuvable.')
    end

    return license, name
end

local function cleanReason(value)
    if type(value) ~= 'string' then
        return nil
    end

    local reason = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(reason)

    return length and length >= 3 and length <= 200 and reason or nil
end

---------------------------------------------------------------------
-- Actions : abonnements
---------------------------------------------------------------------

Panel.actions['premium.set'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'premium.manage') then
        return denied()
    end

    local license, name, err = targetOf(src, actor, data)

    if not license then
        return err
    end

    if type(data.tier) ~= 'string' or not Config.PremiumTiers[data.tier] then
        return Panel.fail('Abonnement inconnu.')
    end

    local expires

    if data.days ~= 'lifetime' then
        local days = tonumber(data.days)

        if not days or days ~= math.floor(days) or days < 1 or days > Config.PremiumMaxDays then
            return Panel.fail(('Durée invalide : de 1 à %d jours, ou à vie.'):format(Config.PremiumMaxDays))
        end

        -- Même abonnement encore actif : la durée s'ajoute à ce qu'il reste
        local current = premiums[license]
        local base = (current and current.tier == data.tier and current.expires and current.expires > now()) and current.expires or now()
        expires = base + days * 86400
    end

    premiums[license] = { tier = data.tier, expires = expires }
    MySQL.query.await([[
        INSERT INTO `lunatic_admin_premium` (`license`, `tier`, `expires_at`, `granted_by`, `granted_at`) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `tier` = VALUES(`tier`), `expires_at` = VALUES(`expires_at`), `granted_by` = VALUES(`granted_by`), `granted_at` = VALUES(`granted_at`)
    ]], { license, data.tier, expires, Staff.displayName(src), now() })

    publish(license)

    local label = Config.PremiumTiers[data.tier].label
    local target = Staff.sourceOf(license)

    if target then
        Panel.notify(target, expires and ('Vous êtes %s jusqu\'au %s.'):format(label, os.date('%d/%m/%Y', expires)) or ('Vous êtes %s à vie.'):format(label), 'success')
    end

    Logs.add(src, 'premium.set', name, { license = license, tier = data.tier, days = data.days, expires = expires })
    return { ok = true, silent = true }
end

Panel.actions['premium.remove'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'premium.manage') then
        return denied()
    end

    local license, name, err = targetOf(src, actor, data)

    if not license then
        return err
    end

    local current = premiums[license]

    if not current then
        return Panel.fail("Ce joueur n'a pas d'abonnement.")
    end

    premiums[license] = nil
    MySQL.update.await('DELETE FROM `lunatic_admin_premium` WHERE `license` = ?', { license })
    publish(license)

    local target = Staff.sourceOf(license)

    if target then
        Panel.notify(target, 'Votre abonnement a été retiré par le staff.', 'error')
    end

    Logs.add(src, 'premium.remove', name, { license = license, tier = current.tier })
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Actions : crédits boutique
---------------------------------------------------------------------

-- Ajoute (montant positif) ou retire (négatif) des crédits ; le solde ne descend jamais sous zéro
local function changeCredits(license, amount, reason, staffName)
    local balance = Panel.creditsOf(license)
    local after = balance + amount

    if after < 0 then
        return nil, balance
    end

    MySQL.query.await('INSERT INTO `lunatic_admin_credits` (`license`, `balance`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `balance` = VALUES(`balance`)', { license, after })
    MySQL.insert.await('INSERT INTO `lunatic_admin_credit_log` (`license`, `amount`, `balance_after`, `reason`, `staff_name`, `created_at`) VALUES (?, ?, ?, ?, ?, ?)', {
        license, amount, after, reason, staffName, now(),
    })

    return after, balance
end

-- Boutique (lunatic_store) : exports.lunatic_admin:removeCredits(source, montant, raison) -> true si le solde suffisait.
-- Débit en une seule requête (solde vérifié par la base) : deux achats simultanés ne peuvent pas passer sous zéro.
exports('removeCredits', function(src, amount, reason)
    local license = GetPlayerIdentifierByType(tonumber(src), 'license')
    amount = tonumber(amount)

    if not license or not amount or amount <= 0 then
        return false
    end

    amount = math.floor(amount)
    local affected = MySQL.update.await('UPDATE `lunatic_admin_credits` SET `balance` = `balance` - ? WHERE `license` = ? AND `balance` >= ?', { amount, license, amount })

    if affected ~= 1 then
        return false
    end

    MySQL.insert.await('INSERT INTO `lunatic_admin_credit_log` (`license`, `amount`, `balance_after`, `reason`, `staff_name`, `created_at`) VALUES (?, ?, ?, ?, ?, ?)', {
        license, -amount, Panel.creditsOf(license), tostring(reason or 'Achat boutique'), 'Boutique', now(),
    })

    return true
end)

-- Remboursement d'un achat qui n'a pas pu être livré
exports('addCredits', function(src, amount, reason)
    local license = GetPlayerIdentifierByType(tonumber(src), 'license')
    amount = tonumber(amount)

    if not license or not amount or amount <= 0 then
        return false
    end

    return changeCredits(license, math.floor(amount), tostring(reason or 'Remboursement boutique'), 'Boutique') ~= nil
end)

-- Abonnement acheté en boutique : les jours s'ajoutent si le même abonnement est actif
---@return boolean ok, string|nil error
exports('grantPremium', function(src, tier, days)
    local license = GetPlayerIdentifierByType(tonumber(src), 'license')
    days = tonumber(days)

    if not license or not Config.PremiumTiers[tier] or not days or days < 1 then
        return false, 'Abonnement invalide.'
    end

    local current = premiums[license]

    if current and not isExpired(current) and current.tier ~= tier and current.tier == 'premium_plus' then
        return false, 'Vous avez déjà Premium+ : attendez sa fin pour prendre Premium.'
    end

    if current and not isExpired(current) and current.tier == tier and not current.expires then
        return false, ('Vous êtes déjà %s à vie.'):format(Config.PremiumTiers[tier].label)
    end

    local base = (current and current.tier == tier and current.expires and current.expires > now()) and current.expires or now()
    local expires = base + math.floor(days) * 86400

    premiums[license] = { tier = tier, expires = expires }
    MySQL.query.await([[
        INSERT INTO `lunatic_admin_premium` (`license`, `tier`, `expires_at`, `granted_by`, `granted_at`) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `tier` = VALUES(`tier`), `expires_at` = VALUES(`expires_at`), `granted_by` = VALUES(`granted_by`), `granted_at` = VALUES(`granted_at`)
    ]], { license, tier, expires, 'Boutique', now() })

    publish(license)
    return true, nil, expires
end)

Panel.actions['credits.change'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'shop.manage') then
        return denied()
    end

    local license, name, err = targetOf(src, actor, data)

    if not license then
        return err
    end

    local amount = tonumber(data.amount)

    if not amount or amount ~= math.floor(amount) or amount == 0 or math.abs(amount) > Config.CreditsMaxAction then
        return Panel.fail(('Montant invalide (1 à %d %s).'):format(Config.CreditsMaxAction, Shop.creditsName()))
    end

    local reason = cleanReason(data.reason)

    if not reason then
        return Panel.fail('La raison est obligatoire (3 caractères minimum).')
    end

    local after, before = changeCredits(license, amount, reason, Staff.displayName(src))

    if not after then
        return Panel.fail(('Solde insuffisant : le joueur n\'a que %d %s.'):format(before, Shop.creditsName()))
    end

    local target = Staff.sourceOf(license)

    if target then
        Panel.notify(target, ('Crédits boutique : %s%d (solde : %d).'):format(amount > 0 and '+' or '', amount, after), 'info')
    end

    Logs.add(src, 'credits.change', name, { license = license, amount = amount, before = before, after = after, reason = reason })
    return { ok = true, silent = true, before = before, after = after }
end

Panel.actions['credits.history'] = function(_, actor, data)
    if not Ranks.hasPermission(actor, 'shop.manage') then
        return denied()
    end

    if type(data.license) ~= 'string' then
        return Panel.fail('Joueur introuvable.')
    end

    local rows = MySQL.query.await('SELECT `amount`, `balance_after`, `reason`, `staff_name`, `created_at` FROM `lunatic_admin_credit_log` WHERE `license` = ? ORDER BY `id` DESC LIMIT 15', { data.license }) or {}
    local list = {}

    for _, row in ipairs(rows) do
        list[#list + 1] = { amount = row.amount, after = row.balance_after, reason = row.reason, staff = row.staff_name, created = tonumber(row.created_at) }
    end

    return { ok = true, silent = true, history = list }
end

print('[lunatic_admin] Module Premium et boutique chargé.')
