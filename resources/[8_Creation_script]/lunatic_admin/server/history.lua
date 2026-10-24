-- Lot 6 : consultation des logs (actions du staff, tchat) et chiffres du tableau de bord.

local PERIODS = { today = 1, week = 7, month = 30 }
local CHAT_CHANNELS = { hrp = true, me = true, ['do'] = true, staff = true, announce = true, clear = true }

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

local function decodeDetails(raw)
    if type(raw) ~= 'string' or raw == '' then
        return nil
    end

    local ok, value = pcall(json.decode, raw)
    return ok and value or nil
end

local function likePattern(text)
    return '%' .. text:sub(1, 60):gsub('[%%_\\]', '\\%0') .. '%'
end

local function cleanSearch(value)
    return type(value) == 'string' and value:match('^%s*(.-)%s*$') or ''
end

---------------------------------------------------------------------
-- Purge des vieux logs
---------------------------------------------------------------------

local function purge()
    MySQL.update('DELETE FROM `lunatic_admin_logs` WHERE `created_at` < (NOW() - INTERVAL ? DAY)', { Config.LogRetentionDays })
end

table.insert(Panel.readyHooks, purge)

CreateThread(function()
    while true do
        Wait(24 * 60 * 60 * 1000)
        purge()
    end
end)

---------------------------------------------------------------------
-- Actions du staff
---------------------------------------------------------------------

local function publicLog(row)
    return {
        id = row.id,
        category = row.category,
        level = row.level,
        actor = row.actor_name,
        actorLicense = row.actor_license,
        serverId = tonumber(row.server_id),
        action = row.action,
        target = row.target,
        details = decodeDetails(row.details),
        created = tonumber(row.created),
    }
end

local LOG_COLUMNS = 'SELECT `id`, `category`, `level`, `actor_license`, `actor_name`, `server_id`, `action`, `target`, `details`, UNIX_TIMESTAMP(`created_at`) AS `created` FROM `lunatic_admin_logs`'

-- Filtres communs (catégorie, niveau, membre, période, recherche) ; sans le niveau pour les compteurs
local function filters(data, withLevel, withCategory)
    local where, params = {}, {}

    if withCategory and Logs.CATEGORIES[data.category] then
        where[#where + 1] = '`category` = ?'
        params[#params + 1] = data.category
    end

    if withLevel and Logs.LEVELS[data.level] then
        where[#where + 1] = '`level` = ?'
        params[#params + 1] = data.level
    end

    if type(data.staff) == 'string' and data.staff ~= '' then
        where[#where + 1] = '`actor_license` = ?'
        params[#params + 1] = data.staff
    end

    local days = PERIODS[data.period]

    if days then
        where[#where + 1] = '`created_at` >= (NOW() - INTERVAL ? DAY)'
        params[#params + 1] = days
    end

    local search = cleanSearch(data.search)

    if search ~= '' then
        local pattern = likePattern(search)
        where[#where + 1] = '(`target` LIKE ? OR `actor_name` LIKE ? OR `action` LIKE ? OR `details` LIKE ? OR `server_id` = ?)'
        params[#params + 1] = pattern
        params[#params + 1] = pattern
        params[#params + 1] = pattern
        params[#params + 1] = pattern
        params[#params + 1] = tonumber(search) or -1
    end

    return where, params
end

local function whereSql(where)
    return #where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or ''
end

Panel.actions['logs.list'] = function(_, actor, data)
    if not Ranks.hasPermission(actor, 'logs.view') then
        return denied()
    end

    local where, params = filters(data, true, true)
    local before = tonumber(data.before)

    if before then
        where[#where + 1] = '`id` < ?'
        params[#params + 1] = before
    end

    params[#params + 1] = Config.LogsPageSize
    local rows = MySQL.query.await(LOG_COLUMNS .. whereSql(where) .. ' ORDER BY `id` DESC LIMIT ?', params) or {}
    local list = {}

    for _, row in ipairs(rows) do
        list[#list + 1] = publicLog(row)
    end

    -- Compteurs : par niveau (catégorie choisie) et par catégorie (niveau choisi), sur la même période et recherche
    local levels, categories = {}, {}

    if not before then
        local w1, p1 = filters(data, false, true)

        for _, row in ipairs(MySQL.query.await('SELECT `level`, COUNT(*) AS `n` FROM `lunatic_admin_logs`' .. whereSql(w1) .. ' GROUP BY `level`', p1) or {}) do
            levels[row.level] = tonumber(row.n)
        end

        local w2, p2 = filters(data, true, false)

        for _, row in ipairs(MySQL.query.await('SELECT `category`, COUNT(*) AS `n` FROM `lunatic_admin_logs`' .. whereSql(w2) .. ' GROUP BY `category`', p2) or {}) do
            categories[row.category] = tonumber(row.n)
        end
    end

    -- Membres du staff pour le filtre « par membre »
    local staff = {}

    for _, member in ipairs(Staff.all()) do
        staff[#staff + 1] = { license = member.license, name = member.name }
    end

    table.sort(staff, function(a, b) return a.name < b.name end)

    return { ok = true, silent = true, logs = list, staff = staff, more = #rows == Config.LogsPageSize, levels = levels, categories = categories }
end

---------------------------------------------------------------------
-- Historique du tchat (table de lunatic_chat)
---------------------------------------------------------------------

Panel.actions['logs.chat'] = function(_, actor, data)
    if not Ranks.hasPermission(actor, 'logs.chat') then
        return denied()
    end

    local where, params = {}, {}

    if type(data.channel) == 'string' and CHAT_CHANNELS[data.channel] then
        where[#where + 1] = '`channel` = ?'
        params[#params + 1] = data.channel
    end

    local days = PERIODS[data.period]

    if days then
        where[#where + 1] = '`created_at` >= (NOW() - INTERVAL ? DAY)'
        params[#params + 1] = days
    end

    local search = cleanSearch(data.search)

    if search ~= '' then
        local pattern = likePattern(search)
        where[#where + 1] = '(`name` LIKE ? OR `message` LIKE ?)'
        params[#params + 1] = pattern
        params[#params + 1] = pattern
    end

    local before = tonumber(data.before)

    if before then
        where[#where + 1] = '`id` < ?'
        params[#params + 1] = before
    end

    local query = 'SELECT `id`, `name`, `channel`, `message`, UNIX_TIMESTAMP(`created_at`) AS `created` FROM `lunatic_chat_logs`'
        .. (#where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or '') .. ' ORDER BY `id` DESC LIMIT ?'
    params[#params + 1] = Config.LogsPageSize

    -- La table n'existe que si lunatic_chat a déjà démarré une fois
    local ok, rows = pcall(MySQL.query.await, query, params)

    if not ok then
        return Panel.fail("L'historique du tchat est indisponible (lunatic_chat n'a jamais démarré ?).")
    end

    local list = {}

    for _, row in ipairs(rows or {}) do
        list[#list + 1] = { id = row.id, name = row.name, channel = row.channel, message = row.message, created = tonumber(row.created) }
    end

    return { ok = true, silent = true, messages = list, more = #list == Config.LogsPageSize }
end

---------------------------------------------------------------------
-- Tableau de bord
---------------------------------------------------------------------

---@type {t:number, n:number}[] nombre de joueurs relevé régulièrement (24 h glissantes)
local samples = {}

local function sample()
    samples[#samples + 1] = { t = os.time(), n = #GetPlayers() }

    local oldest = os.time() - 24 * 3600

    while samples[1] and samples[1].t < oldest do
        table.remove(samples, 1)
    end
end

CreateThread(function()
    while true do
        sample()
        Wait(Config.DashboardSampleMinutes * 60 * 1000)
    end
end)

-- Chiffres coûteux (requêtes SQL) gardés en cache quelques secondes, partagés entre les membres
local cache = { expires = 0 }

local function cachedStats()
    if GetGameTimer() < cache.expires then
        return cache
    end

    local since = os.time() - 24 * 3600

    cache.warns24h = MySQL.scalar.await("SELECT COUNT(*) FROM `lunatic_admin_sanctions` WHERE `type` = 'warn' AND `revoked_at` IS NULL AND `created_at` >= ?", { since }) or 0
    cache.bans24h = MySQL.scalar.await("SELECT COUNT(*) FROM `lunatic_admin_sanctions` WHERE `type` = 'ban' AND `created_at` >= ?", { since }) or 0

    local rows = MySQL.query.await(LOG_COLUMNS .. " WHERE `category` = 'staff' ORDER BY `id` DESC LIMIT 8") or {}
    cache.recent = {}

    for _, row in ipairs(rows) do
        cache.recent[#cache.recent + 1] = publicLog(row)
    end

    cache.expires = GetGameTimer() + 15000
    return cache
end

table.insert(Panel.stateHooks, function(state, _, rank)
    local staffOnline = {}

    for _, member in ipairs(Staff.all()) do
        local online = Staff.sourceOf(member.license)
        local memberRank = Ranks.get(member.rankId)

        if online and memberRank then
            staffOnline[#staffOnline + 1] = { serverId = online, name = member.name, rank = { name = memberRank.name, color = memberRank.color }, level = memberRank.level }
        end
    end

    table.sort(staffOnline, function(a, b) return a.level > b.level end)

    local dashboard = {
        players = #GetPlayers(),
        maxPlayers = GetConvarInt('sv_maxclients', 48),
        history = samples,
        staff = Ranks.hasPermission(rank, 'staff.online') and staffOnline or nil,
    }

    local wantsSanctions = Ranks.hasPermission(rank, 'sanctions.view')
    local wantsLogs = Ranks.hasPermission(rank, 'logs.view')

    if wantsSanctions or wantsLogs then
        local stats = cachedStats()

        if wantsSanctions then
            dashboard.sanctions = { activeBans = Panel.countActiveBans and Panel.countActiveBans() or 0, warns24h = stats.warns24h, bans24h = stats.bans24h }
        end

        if wantsLogs then
            dashboard.recent = stats.recent
        end
    end

    state.dashboard = dashboard
end)

print('[lunatic_admin] Module Logs et tableau de bord chargé.')
