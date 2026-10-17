-- Membres du staff (identifiés par leur licence Rockstar) et joueurs connectés

Staff = {}

---@class StaffMember
---@field license string
---@field rankId number
---@field name string
---@field addedAt number|string|nil

---@type table<string, StaffMember>
local members = {}
---@type table<number, string> source -> licence des joueurs connectés
local licenseBySource = {}

-- Identifiant ESX (table users) d'une licence : la licence sans le préfixe "license:"
local function esxIdentifier(license)
    return (license:gsub('^license:', ''))
end

local function rpName(firstname, lastname)
    if type(firstname) == 'string' and firstname ~= '' and type(lastname) == 'string' and lastname ~= '' then
        return ('%s %s'):format(firstname, lastname)
    end
end

-- Nom RP (prénom nom) d'un joueur connecté, ou son pseudo FiveM s'il n'a pas encore créé son identité
function Staff.displayName(src)
    local state = Player(src).state

    return rpName(state.firstName, state.lastName) or GetPlayerName(src) or ('Joueur ' .. src)
end

local function saveName(member, name)
    if name and member.name ~= name then
        member.name = name
        MySQL.update('UPDATE `lunatic_admin_staff` SET `name` = ? WHERE `license` = ?', { name, member.license })
    end
end

function Staff.load()
    members = {}

    local rows = MySQL.query.await('SELECT `license`, `rank_id`, `name`, `added_at` FROM `lunatic_admin_staff`')
    local identifiers = {}

    for _, row in ipairs(rows or {}) do
        members[row.license] = { license = row.license, rankId = row.rank_id, name = row.name, addedAt = row.added_at }
        identifiers[#identifiers + 1] = esxIdentifier(row.license)
    end

    -- Remplace les noms enregistrés par le nom RP du personnage (table users d'ESX)
    if #identifiers > 0 then
        local users = MySQL.query.await('SELECT `identifier`, `firstname`, `lastname` FROM `users` WHERE `identifier` IN (?)', { identifiers })

        for _, user in ipairs(users or {}) do
            local member = members['license:' .. user.identifier]

            if member then
                saveName(member, rpName(user.firstname, user.lastname))
            end
        end
    end
end

-- Met à jour le nom RP d'un membre connecté (appelé à l'ouverture du panel)
function Staff.refreshName(src)
    local license = licenseBySource[src]
    local member = license and members[license]

    if not member then
        return
    end

    -- Tant que l'identité n'est pas chargée, on garde le nom déjà enregistré
    local state = Player(src).state
    local name = rpName(state.firstName, state.lastName)

    if name or member.name == '' then
        saveName(member, name or Staff.displayName(src))
    end
end

---@return string|nil
function Staff.licenseOf(src)
    return licenseBySource[src]
end

---@return number|nil source si le joueur est connecté
function Staff.sourceOf(license)
    for src, lic in pairs(licenseBySource) do
        if lic == license then
            return src
        end
    end
end

function Staff.trackPlayer(src)
    local license = GetPlayerIdentifierByType(src, 'license')

    if not license then
        return
    end

    licenseBySource[src] = license
end

function Staff.untrackPlayer(src)
    licenseBySource[src] = nil
end

---@return StaffMember|nil
function Staff.get(license)
    return members[license]
end

---@return StaffRank|nil rang du joueur connecté, nil s'il n'est pas staff
function Staff.rankOf(src)
    local license = licenseBySource[src]
    local member = license and members[license]

    return member and Ranks.get(member.rankId) or nil
end

function Staff.can(src, permission)
    return Ranks.hasPermission(Staff.rankOf(src), permission)
end

---@return StaffMember[]
function Staff.all()
    local list = {}

    for _, member in pairs(members) do
        list[#list + 1] = member
    end

    return list
end

function Staff.countByRank(rankId)
    local n = 0

    for _, member in pairs(members) do
        if member.rankId == rankId then
            n = n + 1
        end
    end

    return n
end

---@param addedBy string|nil licence de celui qui ajoute (nil = console)
function Staff.set(license, rankId, name, addedBy)
    MySQL.query.await([[
        INSERT INTO `lunatic_admin_staff` (`license`, `rank_id`, `name`, `added_by`) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `rank_id` = VALUES(`rank_id`), `name` = VALUES(`name`)
    ]], { license, rankId, name, addedBy })

    local member = members[license]

    if member then
        member.rankId, member.name = rankId, name
    else
        members[license] = { license = license, rankId = rankId, name = name, addedAt = os.time() * 1000 }
    end
end

function Staff.remove(license)
    MySQL.update.await('DELETE FROM `lunatic_admin_staff` WHERE `license` = ?', { license })
    members[license] = nil
end

-- Prévient les membres connectés que les rangs ou le staff ont changé :
-- leur panel se recharge (ou se ferme s'ils ont perdu l'accès)
---@param except number|nil source à ne pas prévenir (l'auteur reçoit déjà le nouvel état)
function Staff.broadcastRefresh(except)
    for src, license in pairs(licenseBySource) do
        if members[license] and src ~= except then
            TriggerClientEvent('lunatic_admin:refresh', src)
        end
    end
end

-- Liste des joueurs connectés qui ne sont pas staff (pour l'ajout d'un membre)
function Staff.candidates()
    local list = {}

    for src, license in pairs(licenseBySource) do
        if not members[license] then
            list[#list + 1] = { serverId = src, name = Staff.displayName(src) }
        end
    end

    table.sort(list, function(a, b) return a.serverId < b.serverId end)
    return list
end
