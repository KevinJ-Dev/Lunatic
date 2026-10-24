-- Journal du serveur (tuile Logs) : actions du staff et événements de jeu, rangés par catégorie et par niveau.
-- Catégories : players, economy, inventory, vehicles, staff, companies, illegal, anticheat (le chat a sa propre table).
-- Niveaux : info, warn, error, success. Les autres ressources écrivent par l'export « log ».

Logs = {}

Logs.CATEGORIES = { players = true, economy = true, inventory = true, vehicles = true, staff = true, companies = true, illegal = true, anticheat = true }
Logs.LEVELS = { info = true, warn = true, error = true, success = true }

-- Actions du staff plus surveillées
local STAFF_LEVELS = { ['sanction.'] = 'warn', ['economy.money'] = 'warn', ['player.kill'] = 'warn', ['player.crash'] = 'warn', ['player.wipe'] = 'warn' }

local function staffLevel(action)
    for prefix, level in pairs(STAFF_LEVELS) do
        if action:sub(1, #prefix) == prefix then
            return level
        end
    end

    return 'info'
end

local function write(category, level, license, name, serverId, action, target, details)
    MySQL.insert('INSERT INTO `lunatic_admin_logs` (`category`, `level`, `actor_license`, `actor_name`, `server_id`, `action`, `target`, `details`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        category, level, license, (name or ''):sub(1, 64), serverId, action:sub(1, 48), target and tostring(target):sub(1, 100) or nil, details and json.encode(details) or nil,
    })
end

local function identityOf(src)
    if src and src > 0 and GetPlayerName(src) then
        return GetPlayerIdentifierByType(src, 'license'), Staff.displayName(src), src
    end

    return nil, 'Console', nil
end

-- Action du staff (catégorie Staff)
---@param actor number|nil source du joueur, nil ou 0 pour la console
---@param action string identifiant court de l'action (ex : rank.create)
---@param target string|nil cible lisible (nom de rang, nom de joueur…)
---@param details table|nil données complémentaires
function Logs.add(actor, action, target, details)
    local license, name, serverId = identityOf(actor)
    write('staff', staffLevel(action), license, name, serverId, action, target, details)
    print(('[lunatic_admin] %s : %s%s'):format(name, action, target and (' -> ' .. target) or ''))
end

-- Événement de jeu
---@param category string catégorie (Logs.CATEGORIES)
---@param level string info, warn, error ou success
---@param src number|nil joueur concerné
function Logs.event(category, level, src, action, target, details)
    if not Logs.CATEGORIES[category] or type(action) ~= 'string' then
        return
    end

    local license, name, serverId = identityOf(src)
    write(category, Logs.LEVELS[level] and level or 'info', license, name, serverId, action, target, type(details) == 'table' and details or nil)
end

-- Pour les autres ressources : exports.lunatic_admin:log('illegal', 'warn', source, 'holdup.success', nil, { amount = 1200 })
exports('log', function(category, level, src, action, target, details)
    Logs.event(category, level, tonumber(src), action, target, details)
end)
