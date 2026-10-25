-- Comptes des joueurs (tuile Joueurs) : Discord, première et dernière connexion, temps de jeu total (à la minute).
-- Sert aussi au profil de la fiche (warns, crew, service, ban, personnages liés, véhicules, planques) et aux logs du joueur.

Accounts = {}

local playtime = {} -- licence -> minutes (joueurs connectés, pour la liste)

local now = Util.now

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_player_accounts` (
            `license` VARCHAR(60) NOT NULL,
            `discord` VARCHAR(30) NULL DEFAULT NULL,
            `name` VARCHAR(80) NOT NULL DEFAULT '',
            `first_seen` BIGINT NOT NULL,
            `last_seen` BIGINT NOT NULL,
            `playtime` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`license`),
            KEY `idx_lunatic_player_accounts_discord` (`discord`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Joueurs déjà connectés (redémarrage de la ressource)
    for _, id in ipairs(GetPlayers()) do
        Accounts.touch(tonumber(id))
    end
end)

function Accounts.touch(src)
    local license = GetPlayerIdentifierByType(src, 'license')

    if not license then
        return
    end

    local discord = GetPlayerIdentifierByType(src, 'discord')
    discord = discord and discord:gsub('^discord:', '') or nil

    MySQL.query.await([[
        INSERT INTO `lunatic_player_accounts` (`license`, `discord`, `name`, `first_seen`, `last_seen`) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `discord` = COALESCE(VALUES(`discord`), `discord`), `name` = VALUES(`name`), `last_seen` = VALUES(`last_seen`)
    ]], { license, discord, (GetPlayerName(src) or ''):sub(1, 80), now(), now() })

    playtime[license] = tonumber(MySQL.scalar.await('SELECT `playtime` FROM `lunatic_player_accounts` WHERE `license` = ?', { license })) or 0
end

AddEventHandler('playerJoining', function()
    local src = source
    CreateThread(function() Accounts.touch(src) end)
end)

AddEventHandler('playerDropped', function()
    local license = GetPlayerIdentifierByType(source, 'license')

    if license then
        MySQL.update('UPDATE `lunatic_player_accounts` SET `last_seen` = ? WHERE `license` = ?', { now(), license })
        playtime[license] = nil
    end
end)

-- Temps de jeu : +1 minute par joueur connecté, chaque minute
CreateThread(function()
    while true do
        Wait(60000)
        local licenses = {}

        for _, id in ipairs(GetPlayers()) do
            local license = GetPlayerIdentifierByType(tonumber(id), 'license')

            if license then
                licenses[#licenses + 1] = license
                playtime[license] = (playtime[license] or 0) + 1
            end
        end

        if #licenses > 0 then
            MySQL.update(('UPDATE `lunatic_player_accounts` SET `playtime` = `playtime` + 1, `last_seen` = ? WHERE `license` IN (%s)'):format(('?, '):rep(#licenses):sub(1, -3)),
                { now(), table.unpack(licenses) })
        end
    end
end)

function Accounts.playtimeOf(license)
    return license and playtime[license] or nil
end

---------------------------------------------------------------------
-- Profil de la fiche joueur (connecté ou non)
---------------------------------------------------------------------

---@param license string licence FiveM (« license:… »)
---@param identifier string|nil identifiant ESX du personnage
function Accounts.profile(license, identifier)
    local profile = { vehicles = {}, instances = {}, linked = {} }
    local row = MySQL.single.await('SELECT * FROM `lunatic_player_accounts` WHERE `license` = ?', { license })

    if row then
        profile.discord = row.discord
        profile.firstSeen = tonumber(row.first_seen)
        profile.lastSeen = tonumber(row.last_seen)
        profile.playtime = tonumber(row.playtime) or 0

        -- Personnages liés : autres comptes FiveM avec le même Discord
        if row.discord then
            for _, other in ipairs(MySQL.query.await('SELECT `license`, `name`, `last_seen` FROM `lunatic_player_accounts` WHERE `discord` = ? AND `license` <> ? ORDER BY `last_seen` DESC LIMIT 10', { row.discord, license }) or {}) do
                local id = other.license:gsub('^license:', '')
                local user = MySQL.single.await('SELECT `firstname`, `lastname` FROM `users` WHERE `identifier` = ?', { id })
                profile.linked[#profile.linked + 1] = {
                    identifier = id, license = other.license, lastSeen = tonumber(other.last_seen),
                    name = user and user.firstname and ('%s %s'):format(user.firstname, user.lastname or '') or other.name,
                }
            end
        end
    end

    profile.warns = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM `lunatic_admin_sanctions` WHERE `license` = ? AND `type` = 'warn' AND `revoked_at` IS NULL", { license })) or 0
    profile.banned = (tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM `lunatic_admin_sanctions` WHERE `license` = ? AND `type` = 'ban' AND `revoked_at` IS NULL AND (`expires_at` IS NULL OR `expires_at` > ?)", { license, now() })) or 0) > 0

    if identifier then
        local member = Crews and Crews.view and exports.lunatic_admin:getCrewOf(identifier)
        local crew = member and Crews.view(member.crew)

        if crew then
            local rankLabel

            for _, entry in ipairs(crew.ranks) do
                if entry.rank == member.rank then
                    rankLabel = entry.label
                end
            end

            profile.crew = { id = crew.id, label = crew.label, rank = rankLabel, color = crew.color }

            -- Planques du crew (en attendant les logements des joueurs)
            for _, point in ipairs(CrewPoints and CrewPoints.list(crew.id) or {}) do
                if point.kind == 'property' then
                    profile.instances[#profile.instances + 1] = { label = point.label, kind = 'Planque du crew', x = point.x, y = point.y }
                end
            end
        end

        -- Véhicules possédés (table ESX owned_vehicles, si elle existe)
        local ok, rows = pcall(MySQL.query.await, 'SELECT `plate`, `vehicle`, `type`, `stored` FROM `owned_vehicles` WHERE `owner` = ? LIMIT 50', { identifier })

        for _, vehicle in ipairs(ok and rows or {}) do
            local decoded = vehicle.vehicle and json.decode(vehicle.vehicle) or {}
            profile.vehicles[#profile.vehicles + 1] = { plate = vehicle.plate, model = decoded.model, type = vehicle.type, stored = tonumber(vehicle.stored) == 1 }
        end
    end

    return profile
end

-- Joueurs bannis (filtre de la liste)
Panel.actions['players.banned'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'players.offline') and not Ranks.hasPermission(actor, 'sanctions.view') then
        return Panel.fail("Vous n'avez pas la permission.")
    end

    local list = {}

    for _, row in ipairs(MySQL.query.await("SELECT `license`, `name`, `reason`, `expires_at` FROM `lunatic_admin_sanctions` WHERE `type` = 'ban' AND `revoked_at` IS NULL AND (`expires_at` IS NULL OR `expires_at` > ?) ORDER BY `created_at` DESC LIMIT 100", { now() }) or {}) do
        list[#list + 1] = { license = row.license, identifier = row.license:gsub('^license:', ''), name = row.name, reason = row.reason, expires = tonumber(row.expires_at) }
    end

    return { ok = true, silent = true, players = list }
end

-- Logs du joueur (colonne Logs serveur de la fiche)
Panel.actions['logs.player'] = function(_, actor, data)
    if not Ranks.hasPermission(actor, 'logs.view') then
        return Panel.fail("Vous n'avez pas la permission.")
    end

    if type(data.license) ~= 'string' or data.license == '' then
        return Panel.fail('Joueur introuvable.')
    end

    local rows = MySQL.query.await([[
        SELECT `id`, `category`, `level`, `actor_license`, `actor_name`, `server_id`, `action`, `target`, `details`, UNIX_TIMESTAMP(`created_at`) AS `created`
        FROM `lunatic_admin_logs` WHERE `actor_license` = ? ORDER BY `id` DESC LIMIT 60
    ]], { data.license }) or {}

    local list = {}

    for _, row in ipairs(rows) do
        local ok, details = pcall(json.decode, row.details or 'null')
        list[#list + 1] = {
            id = row.id, category = row.category, level = row.level, actor = row.actor_name, actorLicense = row.actor_license, serverId = tonumber(row.server_id),
            action = row.action, target = row.target, details = ok and details or nil, created = tonumber(row.created),
        }
    end

    return { ok = true, silent = true, logs = list }
end
