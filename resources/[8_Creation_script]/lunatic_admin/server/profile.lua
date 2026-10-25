-- Lot E : permis, copie d'apparence et wipe complet d'un joueur connecté.

---@type {type:string, label:string}[] catalogue des permis (table licenses d'ESX)
local catalogue = {}

-- Rechargé aussi quand un module ajoute des permis (auto-école : avion, hélicoptère)
function Panel.reloadLicenses()
    local rows = MySQL.query.await('SELECT `type`, `label` FROM `licenses` ORDER BY `type`') or {}
    catalogue = {}

    for _, row in ipairs(rows) do
        catalogue[#catalogue + 1] = { type = row.type, label = Config.LicenseLabels[row.type] or row.label }
    end
end

table.insert(Panel.readyHooks, Panel.reloadLicenses)

---@return {type:string, label:string}[] catalogue des permis (auto-école)
function Panel.licenseCatalogue()
    return catalogue
end

local function knownLicense(licenseType)
    for _, entry in ipairs(catalogue) do
        if entry.type == licenseType then
            return entry
        end
    end
end

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

-- Cible connectée avec personnage chargé, staff de rang égal ou supérieur protégé (soi-même autorisé si allowSelf)
local function targetOf(src, actor, data, allowSelf)
    local target = tonumber(data.serverId)

    if not target or not GetPlayerName(target) then
        return nil, nil, Panel.fail("Ce joueur n'est plus connecté.")
    end

    if target == src and not allowSelf then
        return nil, nil, Panel.fail('Action impossible sur vous-même.')
    end

    if target ~= src then
        local rank = Staff.rankOf(target)

        if rank and rank.level >= actor.level then
            return nil, nil, Panel.fail('Ce membre du staff a un rang égal ou supérieur au vôtre.')
        end
    end

    local xPlayer = ESX.GetPlayerFromId(target)

    if not xPlayer then
        return nil, nil, Panel.fail("Ce joueur n'a pas encore chargé son personnage.")
    end

    return target, xPlayer
end

---------------------------------------------------------------------
-- Permis
---------------------------------------------------------------------

-- Permis du joueur pour sa fiche : tout le catalogue, avec owned = true pour ceux qu'il possède
function Panel.licensesOf(identifier)
    local owned = {}

    for _, row in ipairs(MySQL.query.await('SELECT `type` FROM `user_licenses` WHERE `owner` = ?', { identifier }) or {}) do
        owned[row.type] = true
    end

    local list = {}

    for _, entry in ipairs(catalogue) do
        list[#list + 1] = { type = entry.type, label = entry.label, owned = owned[entry.type] == true }
    end

    return list
end

Panel.actions['license.set'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'players.licenses') then
        return denied()
    end

    local target, xPlayer, err = targetOf(src, actor, data, true)

    if not target then
        return err
    end

    local entry = type(data.type) == 'string' and knownLicense(data.type)

    if not entry then
        return Panel.fail('Permis inconnu.')
    end

    local identifier = xPlayer.getIdentifier()
    local give = data.owned == true

    if give then
        local exists = MySQL.scalar.await('SELECT COUNT(*) FROM `user_licenses` WHERE `owner` = ? AND `type` = ?', { identifier, entry.type })

        if (tonumber(exists) or 0) == 0 then
            MySQL.insert.await('INSERT INTO `user_licenses` (`type`, `owner`) VALUES (?, ?)', { entry.type, identifier })
        end
    else
        MySQL.update.await('DELETE FROM `user_licenses` WHERE `owner` = ? AND `type` = ?', { identifier, entry.type })
    end

    if target ~= src then
        Panel.notify(target, ('%s : %s par le staff.'):format(entry.label, give and 'obtenu' or 'retiré'), give and 'success' or 'error')
    end

    Logs.add(src, give and 'license.give' or 'license.remove', Staff.displayName(target), { serverId = target, license = entry.type })
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Apparence : copier celle d'un joueur sur soi (non enregistrée)
---------------------------------------------------------------------

local function skinOf(identifier)
    local raw = MySQL.scalar.await('SELECT `skin` FROM `users` WHERE `identifier` = ?', { identifier })
    local ok, skin = pcall(json.decode, raw or '')

    return ok and type(skin) == 'table' and skin or nil
end

Panel.actions['player.copyAppearance'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'players.copy_appearance') then
        return denied()
    end

    -- La copie ne modifie que le membre du staff : pas de protection de rang sur la cible
    local target = tonumber(data.serverId)
    local xTarget = target and ESX.GetPlayerFromId(target)

    if not xTarget then
        return Panel.fail("Ce joueur n'est plus connecté.")
    end

    if target == src then
        return Panel.fail('Vous avez déjà votre propre apparence.')
    end

    local skin = skinOf(xTarget.getIdentifier())

    if not skin or not skin.model then
        return Panel.fail("Ce joueur n'a pas encore d'apparence enregistrée.")
    end

    -- illenium-appearance applique l'apparence reçue (compatibilité skinchanger d'ESX)
    TriggerClientEvent('skinchanger:loadSkin', src, skin)
    Logs.add(src, 'player.copyAppearance', Staff.displayName(target), { serverId = target })

    return { ok = true, silent = true }
end

Panel.actions['player.restoreAppearance'] = function(src, actor)
    if not Ranks.hasPermission(actor, 'players.copy_appearance') then
        return denied()
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local skin = xPlayer and skinOf(xPlayer.getIdentifier())

    if not skin or not skin.model then
        return Panel.fail('Apparence enregistrée introuvable.')
    end

    TriggerClientEvent('skinchanger:loadSkin', src, skin)
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Wipe complet
---------------------------------------------------------------------

Panel.actions['player.wipe'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'players.wipe') then
        return denied()
    end

    local target, xPlayer, err = targetOf(src, actor, data, false)

    if not target then
        return err
    end

    local name = Staff.displayName(target)

    -- Le nom doit être retapé exactement (sans le « [ID] ») pour confirmer
    if type(data.confirm) ~= 'string' or data.confirm:lower():gsub('^%s+', ''):gsub('%s+$', '') ~= name:lower() then
        return Panel.fail('Le nom tapé ne correspond pas : wipe annulé.')
    end

    local reason = type(data.reason) == 'string' and data.reason:gsub('%c', ' '):match('^%s*(.-)%s*$') or ''

    if utf8.len(reason) == nil or utf8.len(reason) < Config.SanctionReasonMin then
        return Panel.fail(('La raison doit faire au moins %d caractères.'):format(Config.SanctionReasonMin))
    end

    if GetResourceState('lunatic_creator') ~= 'started' then
        return Panel.fail("lunatic_creator n'est pas démarré.")
    end

    local identifier = xPlayer.getIdentifier()

    -- État complet avant wipe, gardé dans les logs pour pouvoir le restaurer à la main en cas d'erreur
    local snapshot = { accounts = {}, items = {}, vehicles = {}, licenses = {} }

    for _, account in ipairs({ 'money', 'bank', 'black_money' }) do
        local current = xPlayer.getAccount(account)
        snapshot.accounts[account] = current and current.money or 0
    end

    local job = xPlayer.getJob()
    snapshot.job = job and ('%s (%s)'):format(job.name, job.grade) or nil

    for _, slot in pairs(exports.ox_inventory:GetInventoryItems(target) or {}) do
        if type(slot) == 'table' and slot.name then
            snapshot.items[#snapshot.items + 1] = ('%dx %s'):format(slot.count or 0, slot.name)
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT `plate` FROM `owned_vehicles` WHERE `owner` = ?', { identifier }) or {}) do
        snapshot.vehicles[#snapshot.vehicles + 1] = row.plate
    end

    for _, row in ipairs(MySQL.query.await('SELECT `type` FROM `user_licenses` WHERE `owner` = ?', { identifier }) or {}) do
        snapshot.licenses[#snapshot.licenses + 1] = row.type
    end

    -- Remise à zéro : argent de départ d'ESX, inventaire vide, chômeur, sans véhicule ni permis
    local starting = ESX.GetConfig('StartingAccountMoney') or {}

    for _, account in ipairs({ 'money', 'bank', 'black_money' }) do
        xPlayer.setAccountMoney(account, starting[account] or 0, 'Wipe staff')
    end

    exports.ox_inventory:ClearInventory(target)
    xPlayer.setJob('unemployed', 0)
    MySQL.update.await('DELETE FROM `owned_vehicles` WHERE `owner` = ?', { identifier })
    MySQL.update.await('DELETE FROM `user_licenses` WHERE `owner` = ?', { identifier })

    -- Identité et apparence effacées, retour à la création de personnage
    local ok, done = pcall(function()
        return exports.lunatic_creator:resetIdentity(target)
    end)

    Logs.add(src, 'player.wipe', name, { serverId = target, reason = reason, before = snapshot })

    if not ok or not done then
        print(('[lunatic_admin] Wipe : resetIdentity a échoué : %s'):format(tostring(done)))
        return Panel.fail("Argent, inventaire, métier, véhicules et permis effacés, mais l'identité n'a pas pu être réinitialisée (voir la console).")
    end

    Panel.notify(target, 'Votre personnage a été réinitialisé par le staff : créez-en un nouveau.', 'error')
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Profil (permis, apparence, wipe) chargé.')
