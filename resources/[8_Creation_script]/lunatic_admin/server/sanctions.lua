-- Lot 3 : avertissements et bans (vérifiés à la connexion), historique et révocation.
-- Un ban vise la licence, les autres identifiants (Discord, Steam, FiveM…) et les identifiants matériels du PC.

---@type table<number, table> id -> ban actif
local activeBans = {}
---@type table<string, number> identifiant ou token -> id du ban
local banIndex = {}
---@type table[] derniers joueurs partis, le plus récent en premier
local recent = {}
local loaded = false

local function now()
    return os.time()
end

local function decodeList(raw)
    local ok, list = pcall(json.decode, raw or '[]')
    return (ok and type(list) == 'table') and list or {}
end

local function formatDate(timestamp)
    return os.date('%d/%m/%Y à %H:%M', timestamp)
end

---------------------------------------------------------------------
-- Bans actifs en mémoire
---------------------------------------------------------------------

local function indexBan(ban)
    activeBans[ban.id] = ban
    banIndex[ban.license] = ban.id

    for _, id in ipairs(ban.identifiers) do
        banIndex[id] = ban.id
    end

    for _, token in ipairs(ban.tokens) do
        banIndex[token] = ban.id
    end
end

local function removeBan(id)
    activeBans[id] = nil
    banIndex = {}

    for _, ban in pairs(activeBans) do
        indexBan(ban)
    end
end

local function isActive(ban)
    return ban.expires == nil or ban.expires > now()
end

---@return table|nil ban actif correspondant à l'un des identifiants ou tokens
local function findBan(...)
    for _, list in ipairs({ ... }) do
        for _, key in ipairs(list) do
            local id = banIndex[key]
            local ban = id and activeBans[id]

            if ban then
                if isActive(ban) then
                    return ban
                end

                removeBan(ban.id) -- ban expiré
            end
        end
    end
end

table.insert(Panel.readyHooks, function()
    local rows = MySQL.query.await([[
        SELECT `id`, `license`, `name`, `identifiers`, `tokens`, `reason`, `created_at`, `expires_at`
        FROM `lunatic_admin_sanctions`
        WHERE `type` = 'ban' AND `revoked_at` IS NULL AND (`expires_at` IS NULL OR `expires_at` > ?)
    ]], { now() })

    for _, row in ipairs(rows or {}) do
        indexBan({
            id = row.id,
            license = row.license,
            name = row.name,
            identifiers = decodeList(row.identifiers),
            tokens = decodeList(row.tokens),
            reason = row.reason,
            created = tonumber(row.created_at),
            expires = tonumber(row.expires_at),
        })
    end

    loaded = true
    print(('[lunatic_admin] Module Sanctions chargé : %d ban(s) actif(s).'):format(#(rows or {})))
end)

-- Nombre de bans actifs (tableau de bord)
function Panel.countActiveBans()
    local count = 0

    for _, ban in pairs(activeBans) do
        if isActive(ban) then
            count = count + 1
        end
    end

    return count
end

---------------------------------------------------------------------
-- Identifiants d'un joueur (sans l'adresse IP, partagée entre plusieurs personnes)
---------------------------------------------------------------------

local function identifiersOf(src)
    local list = {}

    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if not id:find('^ip:') then
            list[#list + 1] = id
        end
    end

    return list
end

local function tokensOf(src)
    local list = {}

    for i = 0, GetNumPlayerTokens(src) - 1 do
        local token = GetPlayerToken(src, i)

        if token then
            list[#list + 1] = token
        end
    end

    return list
end

local function banMessage(ban)
    return ('Vous êtes banni de %s.\n\nRaison : %s\nFin : %s\nRéférence : #%d\n\nPour contester, contactez le staff en donnant la référence.'):format(
        Config.ServerName,
        ban.reason,
        ban.expires and formatDate(ban.expires) or 'définitif',
        ban.id
    )
end

---------------------------------------------------------------------
-- Vérification à la connexion
---------------------------------------------------------------------

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local src = source

    deferrals.defer()
    Wait(0)
    deferrals.update('Vérification des sanctions…')

    -- Juste après le démarrage du serveur, on attend le chargement des bans
    local timeout = GetGameTimer() + 10000

    while not loaded and GetGameTimer() < timeout do
        Wait(100)
    end

    local ban = findBan(identifiersOf(src), tokensOf(src))

    if ban then
        print(('[lunatic_admin] Connexion refusée à %s : ban #%d.'):format(GetPlayerName(src) or '?', ban.id))
        return deferrals.done(banMessage(ban))
    end

    deferrals.done()
end)

-- Mémorise les derniers joueurs partis pour pouvoir les bannir depuis le panel
AddEventHandler('playerDropped', function()
    local src = source
    local license = GetPlayerIdentifierByType(src, 'license')

    if not license then
        return
    end

    for i = #recent, 1, -1 do
        if recent[i].license == license then
            table.remove(recent, i)
        end
    end

    table.insert(recent, 1, {
        license = license,
        name = Staff.displayName(src),
        serverId = src,
        identifiers = identifiersOf(src),
        tokens = tokensOf(src),
        droppedAt = now(),
    })

    while #recent > Config.RecentDisconnects do
        table.remove(recent)
    end
end)

---------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------

local function cleanReason(value)
    if type(value) ~= 'string' then
        return nil
    end

    local reason = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(reason)

    if not length or length < Config.SanctionReasonMin or length > Config.SanctionReasonMax then
        return nil
    end

    return reason
end

local function reasonError()
    return Panel.fail(('La raison doit faire entre %d et %d caractères.'):format(Config.SanctionReasonMin, Config.SanctionReasonMax))
end

-- Un membre du staff de rang égal ou supérieur ne peut pas être sanctionné
local function isProtectedLicense(actor, license)
    local member = Staff.get(license)
    local rank = member and Ranks.get(member.rankId)

    return rank ~= nil and rank.level >= actor.level
end

---@return number|false|nil hours nombre d'heures, false = définitif, nil = invalide
---@return string|nil error
local function parseDuration(actor, value)
    if value == 'permanent' then
        if not Ranks.hasPermission(actor, 'sanctions.ban_permanent') then
            return nil, "Vous n'avez pas la permission de bannir définitivement."
        end

        return false
    end

    local hours = tonumber(value)

    if not hours or hours ~= math.floor(hours) or hours < 1 or hours > Config.BanMaxHours then
        return nil, ('Durée invalide : de 1 à %d heures.'):format(Config.BanMaxHours)
    end

    return math.floor(hours)
end

local function onlineTarget(target)
    return {
        license = GetPlayerIdentifierByType(target, 'license'),
        name = Staff.displayName(target),
        identifiers = identifiersOf(target),
        tokens = tokensOf(target),
    }
end

local function createSanction(kind, target, src, actor, reason, expires)
    local created = now()
    local sanction = {
        type = kind,
        license = target.license,
        name = target.name,
        identifiers = target.identifiers or {},
        tokens = target.tokens or {},
        reason = reason,
        created = created,
        expires = expires,
    }

    sanction.id = MySQL.insert.await([[
        INSERT INTO `lunatic_admin_sanctions`
            (`type`, `license`, `name`, `identifiers`, `tokens`, `reason`, `staff_license`, `staff_name`, `staff_level`, `created_at`, `expires_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        kind, sanction.license, sanction.name, json.encode(sanction.identifiers), json.encode(sanction.tokens), reason,
        src > 0 and Staff.licenseOf(src) or nil, src > 0 and Staff.displayName(src) or 'Console', actor and actor.level or Config.OwnerLevel,
        created, expires,
    })

    if kind == 'ban' then
        indexBan(sanction)
    end

    return sanction
end

-- Ligne de la base -> sanction envoyée au panel
local function publicSanction(row, src, actor)
    local expires = tonumber(row.expires_at)
    local revoked = row.revoked_at ~= nil
    local active, remaining

    if row.type == 'jail' then
        -- Une peine de prison est active tant qu'il lui reste du temps (server/jail.lua)
        remaining = Panel.jailRemaining and Panel.jailRemaining(row.id) or nil
        active = not revoked and remaining ~= nil
    else
        active = not revoked and (row.type == 'warn' or expires == nil or expires > now())
    end

    return {
        id = row.id,
        type = row.type,
        license = row.license,
        name = row.name,
        reason = row.reason,
        staff = row.staff_name,
        created = tonumber(row.created_at),
        expires = expires,
        remaining = remaining,
        active = active,
        revoked = revoked,
        revokedAt = tonumber(row.revoked_at),
        revokedBy = row.revoked_by,
        revokeReason = row.revoke_reason,
        canRevoke = active and Ranks.hasPermission(actor, 'sanctions.revoke')
            and (actor.owner or (tonumber(row.staff_level) or 0) < actor.level or (row.staff_license ~= nil and row.staff_license == Staff.licenseOf(src))),
    }
end

local SELECT_COLUMNS = [[
    SELECT `id`, `type`, `license`, `name`, `reason`, `staff_license`, `staff_name`, `staff_level`,
           `created_at`, `expires_at`, `revoked_at`, `revoked_by`, `revoke_reason`
    FROM `lunatic_admin_sanctions`
]]

---------------------------------------------------------------------
-- Joueurs récemment partis, ajoutés à l'état du panel
---------------------------------------------------------------------

table.insert(Panel.stateHooks, function(state, _, rank)
    if not Ranks.hasPermission(rank, 'sanctions.ban') then
        return
    end

    local list = {}

    for _, entry in ipairs(recent) do
        list[#list + 1] = {
            license = entry.license,
            name = entry.name,
            serverId = entry.serverId,
            droppedAt = entry.droppedAt,
            banned = findBan({ entry.license }) ~= nil,
        }
    end

    state.recent = list
end)

---------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------

Panel.actions['sanction.warn'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'sanctions.warn') then
        return Panel.fail("Vous n'avez pas la permission d'avertir.")
    end

    local target = tonumber(data.serverId)

    if not target or not GetPlayerName(target) then
        return Panel.fail("Ce joueur n'est plus connecté.")
    end

    local license = GetPlayerIdentifierByType(target, 'license')

    if target == src or isProtectedLicense(actor, license) then
        return Panel.fail(target == src and 'Action impossible sur vous-même.' or 'Ce membre du staff a un rang égal ou supérieur au vôtre.')
    end

    local reason = cleanReason(data.reason)

    if not reason then
        return reasonError()
    end

    local sanction = createSanction('warn', onlineTarget(target), src, actor, reason, nil)
    TriggerClientEvent('lunatic_admin:warning', target, { id = sanction.id, reason = reason, date = sanction.created })
    Logs.add(src, 'sanction.warn', sanction.name, { id = sanction.id, reason = reason })

    return { ok = true, silent = true, id = sanction.id }
end

Panel.actions['sanction.ban'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'sanctions.ban') then
        return Panel.fail("Vous n'avez pas la permission de bannir.")
    end

    -- Cible connectée (serverId) ou récemment partie (license)
    local online = tonumber(data.serverId)
    local target

    if online then
        if not GetPlayerName(online) then
            return Panel.fail("Ce joueur n'est plus connecté : utilisez la liste des déconnexions récentes.")
        end

        if online == src then
            return Panel.fail('Action impossible sur vous-même.')
        end

        target = onlineTarget(online)
    elseif type(data.license) == 'string' then
        for _, entry in ipairs(recent) do
            if entry.license == data.license then
                target = entry
                break
            end
        end

        if not target then
            return Panel.fail("Ce joueur n'est plus dans la liste des déconnexions récentes.")
        end

        if target.license == Staff.licenseOf(src) then
            return Panel.fail('Action impossible sur vous-même.')
        end
    elseif type(data.identifier) == 'string' then
        -- Joueur trouvé par la recherche hors ligne : seule sa licence est connue (pas de tokens matériels)
        if not Ranks.hasPermission(actor, 'players.offline') then
            return Panel.fail("Vous n'avez pas la permission d'agir sur les joueurs hors ligne.")
        end

        local identifier = data.identifier:gsub('^license:', '')
        local row = identifier:match('^%x+$') and MySQL.single.await('SELECT `firstname`, `lastname` FROM `users` WHERE `identifier` = ?', { identifier })

        if not row then
            return Panel.fail('Joueur introuvable en base.')
        end

        if Staff.sourceOf('license:' .. identifier) then
            return Panel.fail('Ce joueur est connecté : bannissez-le depuis sa fiche en ligne.')
        end

        target = {
            license = 'license:' .. identifier,
            name = row.firstname and ('%s %s'):format(row.firstname, row.lastname or '') or identifier,
            identifiers = {},
            tokens = {},
        }

        if target.license == Staff.licenseOf(src) then
            return Panel.fail('Action impossible sur vous-même.')
        end
    else
        return Panel.fail('Joueur introuvable.')
    end

    if isProtectedLicense(actor, target.license) then
        return Panel.fail('Ce membre du staff a un rang égal ou supérieur au vôtre.')
    end

    local existing = findBan({ target.license })

    if existing then
        return Panel.fail(('Ce joueur est déjà banni (référence #%d).'):format(existing.id))
    end

    local reason = cleanReason(data.reason)

    if not reason then
        return reasonError()
    end

    local hours, durationError = parseDuration(actor, data.duration)

    if hours == nil then
        return Panel.fail(durationError)
    end

    local expires = hours and (now() + hours * 3600) or nil
    local sanction = createSanction('ban', target, src, actor, reason, expires)

    Logs.add(src, 'sanction.ban', sanction.name, { id = sanction.id, reason = reason, hours = hours or 'permanent' })

    if online then
        DropPlayer(online, banMessage(sanction))
    end

    return { ok = true, id = sanction.id }
end

Panel.actions['sanction.revoke'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'sanctions.revoke') then
        return Panel.fail("Vous n'avez pas la permission de révoquer une sanction.")
    end

    local id = tonumber(data.id)
    local row = id and MySQL.single.await(SELECT_COLUMNS .. ' WHERE `id` = ?', { id })

    if not row then
        return Panel.fail('Sanction introuvable.')
    end

    local sanction = publicSanction(row, src, actor)

    if not sanction.canRevoke then
        return Panel.fail(sanction.active and 'Cette sanction a été donnée par un rang égal ou supérieur au vôtre.' or 'Cette sanction n’est plus active.')
    end

    local reason = cleanReason(data.reason)

    if not reason then
        return reasonError()
    end

    MySQL.update.await('UPDATE `lunatic_admin_sanctions` SET `revoked_at` = ?, `revoked_by` = ?, `revoke_reason` = ? WHERE `id` = ?', {
        now(), Staff.displayName(src), reason, id,
    })

    if row.type == 'ban' then
        removeBan(id)
    elseif row.type == 'jail' and Panel.releaseJailBySanction then
        Panel.releaseJailBySanction(id)
    end

    Logs.add(src, 'sanction.revoke', row.name, { id = id, type = row.type, reason = reason })

    return { ok = true, silent = true }
end

-- Liste filtrée de la page Sanctions
Panel.actions['sanctions.list'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'sanctions.view') then
        return Panel.fail("Vous n'avez pas la permission de voir les sanctions.")
    end

    local where, params = {}, {}

    if data.type == 'warn' or data.type == 'ban' or data.type == 'jail' then
        where[#where + 1] = '`type` = ?'
        params[#params + 1] = data.type
    end

    if data.status == 'active' then
        where[#where + 1] = "`revoked_at` IS NULL AND (`type` = 'warn'"
            .. " OR (`type` = 'ban' AND (`expires_at` IS NULL OR `expires_at` > ?))"
            .. " OR (`type` = 'jail' AND `id` IN (SELECT `sanction_id` FROM `lunatic_admin_jail`)))"
        params[#params + 1] = now()
    end

    local search = type(data.search) == 'string' and data.search:match('^%s*(.-)%s*$') or ''

    if search ~= '' then
        local reference = tonumber(search:match('^#?(%d+)$'))

        if reference then
            where[#where + 1] = '`id` = ?'
            params[#params + 1] = reference
        else
            where[#where + 1] = '`name` LIKE ?'
            params[#params + 1] = '%' .. search:sub(1, 60):gsub('[%%_\\]', '\\%0') .. '%'
        end
    end

    local query = SELECT_COLUMNS .. (#where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or '') .. ' ORDER BY `id` DESC LIMIT 100'
    local rows = MySQL.query.await(query, params)
    local list = {}

    for _, row in ipairs(rows or {}) do
        list[#list + 1] = publicSanction(row, src, actor)
    end

    return { ok = true, silent = true, sanctions = list }
end

-- Historique d'un joueur (fiche)
Panel.actions['sanctions.history'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'sanctions.view') then
        return Panel.fail("Vous n'avez pas la permission de voir les sanctions.")
    end

    if type(data.license) ~= 'string' then
        return Panel.fail('Joueur introuvable.')
    end

    local rows = MySQL.query.await(SELECT_COLUMNS .. ' WHERE `license` = ? ORDER BY `id` DESC LIMIT 30', { data.license })
    local list = {}

    for _, row in ipairs(rows or {}) do
        list[#list + 1] = publicSanction(row, src, actor)
    end

    return { ok = true, silent = true, sanctions = list }
end

-- Outils partagés avec server/jail.lua (chargé après ce fichier)
Panel.sanctions = {
    create = createSanction,
    onlineTarget = onlineTarget,
    cleanReason = cleanReason,
    isProtectedLicense = isProtectedLicense,
}

---------------------------------------------------------------------
-- Commande console de secours
---------------------------------------------------------------------

-- lunatic_admin_unban <référence> : lève un ban depuis la console de l'hébergeur
RegisterCommand('lunatic_admin_unban', function(src, args)
    if src ~= 0 then
        return
    end

    local id = tonumber((args[1] or ''):match('^#?(%d+)$'))

    if not id then
        return print('[lunatic_admin] Usage : lunatic_admin_unban <référence du ban, ex. 42>')
    end

    local affected = MySQL.update.await([[
        UPDATE `lunatic_admin_sanctions` SET `revoked_at` = ?, `revoked_by` = 'Console', `revoke_reason` = 'Levé depuis la console'
        WHERE `id` = ? AND `type` = 'ban' AND `revoked_at` IS NULL
    ]], { now(), id })

    if not affected or affected == 0 then
        return print(('[lunatic_admin] Aucun ban actif avec la référence #%d.'):format(id))
    end

    removeBan(id)
    Logs.add(0, 'sanction.revoke', ('#%d'):format(id), { id = id, reason = 'console' })
    print(('[lunatic_admin] Ban #%d levé.'):format(id))
end, true)
