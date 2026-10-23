-- Rangs du staff : cache mémoire synchronisé avec la table lunatic_admin_ranks

Ranks = {}

---@class StaffRank
---@field id number
---@field name string
---@field color string
---@field level number
---@field owner boolean
---@field permissions table<string, true>

---@type table<number, StaffRank>
local byId = {}

local function decodePermissions(raw)
    local set = {}
    local ok, list = pcall(json.decode, raw or '[]')

    if ok and type(list) == 'table' then
        for _, id in ipairs(list) do
            if Permissions.Known[id] then
                set[id] = true
            end
        end
    end

    return set
end

local function encodePermissions(set)
    local list = {}

    for id in pairs(set) do
        list[#list + 1] = id
    end

    table.sort(list)
    return json.encode(list)
end

local function fromRow(row)
    return {
        id = row.id,
        name = row.name,
        color = row.color,
        level = row.level,
        owner = row.is_owner == 1 or row.is_owner == true,
        discord = row.discord_role or '',
        permissions = decodePermissions(row.permissions),
    }
end

function Ranks.load()
    byId = {}

    local rows = MySQL.query.await('SELECT `id`, `name`, `color`, `level`, `is_owner`, `permissions`, `discord_role` FROM `lunatic_admin_ranks`')

    for _, row in ipairs(rows or {}) do
        byId[row.id] = fromRow(row)
    end
end

-- Crée les rangs par défaut si la table est vide
function Ranks.seed()
    if next(byId) then
        return
    end

    for _, def in ipairs(Config.DefaultRanks) do
        local set = {}

        for _, id in ipairs(def.permissions or {}) do
            if Permissions.Known[id] then
                set[id] = true
            end
        end

        local id = MySQL.insert.await('INSERT INTO `lunatic_admin_ranks` (`name`, `color`, `level`, `is_owner`, `permissions`) VALUES (?, ?, ?, ?, ?)', {
            def.name, def.color, def.level, def.owner and 1 or 0, encodePermissions(set),
        })

        byId[id] = { id = id, name = def.name, color = def.color, level = def.level, owner = def.owner == true, discord = '', permissions = set }
    end

    print(('[lunatic_admin] %d rangs par défaut créés.'):format(#Config.DefaultRanks))
end

---@return StaffRank|nil
function Ranks.get(id)
    return byId[tonumber(id) or -1]
end

---@return StaffRank[] rangs triés du plus haut au plus bas
function Ranks.all()
    local list = {}

    for _, rank in pairs(byId) do
        list[#list + 1] = rank
    end

    table.sort(list, function(a, b) return a.level > b.level end)
    return list
end

function Ranks.count()
    local n = 0

    for _ in pairs(byId) do
        n = n + 1
    end

    return n
end

---@return StaffRank|nil
function Ranks.getOwnerRank()
    for _, rank in pairs(byId) do
        if rank.owner then
            return rank
        end
    end
end

---@param rank StaffRank|nil
function Ranks.hasPermission(rank, permission)
    if not rank then
        return false
    end

    return rank.owner or rank.permissions[permission] == true
end

function Ranks.isLevelTaken(level, exceptId)
    for id, rank in pairs(byId) do
        if rank.level == level and id ~= exceptId then
            return true
        end
    end

    return false
end

-- Liste des permissions effectives (le Fondateur les a toutes)
---@param rank StaffRank
function Ranks.permissionList(rank)
    local list = {}

    for _, perm in ipairs(Permissions.List) do
        if Ranks.hasPermission(rank, perm.id) then
            list[#list + 1] = perm.id
        end
    end

    return list
end

---@param data {name:string, color:string, level:number, permissions:table<string, true>}
---@return StaffRank
function Ranks.create(data)
    local id = MySQL.insert.await('INSERT INTO `lunatic_admin_ranks` (`name`, `color`, `level`, `is_owner`, `permissions`, `discord_role`) VALUES (?, ?, ?, 0, ?, ?)', {
        data.name, data.color, data.level, encodePermissions(data.permissions), data.discord or '',
    })

    byId[id] = { id = id, name = data.name, color = data.color, level = data.level, owner = false, discord = data.discord or '', permissions = data.permissions }
    return byId[id]
end

---@param rank StaffRank
---@param data {name:string, color:string, level:number, permissions:table<string, true>}
function Ranks.update(rank, data)
    local discord = data.discord or rank.discord or ''

    MySQL.update.await('UPDATE `lunatic_admin_ranks` SET `name` = ?, `color` = ?, `level` = ?, `permissions` = ?, `discord_role` = ? WHERE `id` = ?', {
        data.name, data.color, data.level, encodePermissions(data.permissions), discord, rank.id,
    })

    rank.name, rank.color, rank.level, rank.permissions, rank.discord = data.name, data.color, data.level, data.permissions, discord
end

---@param rank StaffRank
function Ranks.delete(rank)
    MySQL.update.await('DELETE FROM `lunatic_admin_ranks` WHERE `id` = ?', { rank.id })
    byId[rank.id] = nil
end
