-- Illégal, étape 1 : crews (tuile Crews). Un crew a un type (Mafia, MC, Organisation, Gang), des rangs,
-- des membres (un crew au plus par personnage) et de l'XP qui donne son level.
-- Indépendant du métier ESX. Le crew de chaque joueur connecté est dans son statebag « crew ».
-- Le jeu (menu /crew de lunatic_illegal) passe par les exports en bas de fichier.

Crews = {}

local TYPES = {}

for _, entry in ipairs(Config.CrewTypes) do
    TYPES[entry.id] = entry.label
end

---@type table<number, table> crews par id
local crews = {}
---@type table<string, { crew: number, rank: number, joined: number }> membres par identifiant ESX
local members = {}

local function levelOf(xp)
    local level = 1

    for index, needed in ipairs(Config.CrewLevels) do
        if xp >= needed then
            level = index
        end
    end

    return level
end

local function rankLabel(crew, rank)
    for _, entry in ipairs(crew.ranks) do
        if entry.rank == rank then
            return entry.label
        end
    end

    return ('Rang %d'):format(rank)
end

local function topRank(crew)
    local top = 0

    for _, entry in ipairs(crew.ranks) do
        top = math.max(top, entry.rank)
    end

    return top
end

-- Statebag du joueur connecté (lu par les autres scripts : Player(src).state.crew)
local function publishPlayer(identifier)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)

    if not xPlayer then
        return
    end

    local member = members[identifier]
    local crew = member and crews[member.crew]

    Player(xPlayer.source).state:set('crew', crew and {
        id = crew.id, slug = crew.slug, label = crew.label, type = crew.type, color = crew.color,
        rank = member.rank, rankLabel = rankLabel(crew, member.rank), leader = member.rank == topRank(crew), level = levelOf(crew.xp),
    } or nil, true)
end

local function publishCrew(crewId)
    for identifier, member in pairs(members) do
        if member.crew == crewId then
            publishPlayer(identifier)
        end
    end
end

AddEventHandler('esx:playerLoaded', function(_, xPlayer)
    if xPlayer and xPlayer.identifier then
        publishPlayer(xPlayer.identifier)
    end
end)

local function load()
    crews, members = {}, {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_crews`') or {}) do
        crews[tonumber(row.id)] = {
            id = tonumber(row.id), slug = row.slug, label = row.label, type = row.type, color = row.color, logo = row.logo or '',
            xp = tonumber(row.xp) or 0, createdBy = row.created_by, createdAt = tonumber(row.created_at), ranks = {},
        }
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_crew_ranks` ORDER BY `rank`') or {}) do
        local crew = crews[tonumber(row.crew_id)]

        if crew then
            crew.ranks[#crew.ranks + 1] = { rank = tonumber(row.rank), label = row.label }
        end
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_crew_members`') or {}) do
        if crews[tonumber(row.crew_id)] then
            members[row.identifier] = { crew = tonumber(row.crew_id), rank = tonumber(row.rank), joined = tonumber(row.joined_at) }
        end
    end
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_crews` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `slug` VARCHAR(30) NOT NULL,
            `label` VARCHAR(60) NOT NULL,
            `type` VARCHAR(20) NOT NULL,
            `color` VARCHAR(7) NOT NULL DEFAULT '#9650ff',
            `logo` VARCHAR(255) NOT NULL DEFAULT '',
            `xp` INT NOT NULL DEFAULT 0,
            `created_by` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_lunatic_crews_slug` (`slug`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_crew_ranks` (
            `crew_id` INT NOT NULL,
            `rank` INT NOT NULL,
            `label` VARCHAR(40) NOT NULL,
            PRIMARY KEY (`crew_id`, `rank`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Un personnage appartient au plus à un crew (clé primaire sur l'identifiant)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_crew_members` (
            `identifier` VARCHAR(60) NOT NULL,
            `crew_id` INT NOT NULL,
            `rank` INT NOT NULL DEFAULT 0,
            `joined_at` BIGINT NOT NULL,
            PRIMARY KEY (`identifier`),
            KEY `idx_lunatic_crew_members_crew` (`crew_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    load()

    for identifier in pairs(members) do
        publishPlayer(identifier)
    end
end)

---------------------------------------------------------------------
-- Opérations communes (panel et exports pour le jeu)
---------------------------------------------------------------------

-- Ajoute, déplace ou retire (crewId = nil) un membre
---@return boolean ok, string|nil error
function Crews.setMember(identifier, crewId, rank)
    if type(identifier) ~= 'string' or not identifier:match('^%x+$') then
        return false, 'Joueur introuvable.'
    end

    if crewId == nil then
        MySQL.update.await('DELETE FROM `lunatic_crew_members` WHERE `identifier` = ?', { identifier })
        members[identifier] = nil
        publishPlayer(identifier)
        return true
    end

    local crew = crews[crewId]

    if not crew then
        return false, 'Crew introuvable.'
    end

    rank = tonumber(rank) or 0
    local valid = false

    for _, entry in ipairs(crew.ranks) do
        if entry.rank == rank then
            valid = true
        end
    end

    if not valid then
        return false, 'Rang inconnu.'
    end

    local current = members[identifier]
    local joined = current and current.crew == crewId and current.joined or os.time()

    MySQL.query.await('INSERT INTO `lunatic_crew_members` (`identifier`, `crew_id`, `rank`, `joined_at`) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE `crew_id` = VALUES(`crew_id`), `rank` = VALUES(`rank`), `joined_at` = VALUES(`joined_at`)', {
        identifier, crewId, rank, joined,
    })

    members[identifier] = { crew = crewId, rank = rank, joined = joined }
    publishPlayer(identifier)
    return true
end

function Crews.addXp(crewId, amount)
    local crew = crews[crewId]
    amount = math.floor(tonumber(amount) or 0)

    if not crew or amount == 0 then
        return false
    end

    crew.xp = math.max(0, crew.xp + amount)
    MySQL.update.await('UPDATE `lunatic_crews` SET `xp` = ? WHERE `id` = ?', { crew.xp, crew.id })
    publishCrew(crew.id)
    return true
end

local function nameOf(identifier)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)

    if xPlayer then
        return xPlayer.getName(), xPlayer.source
    end

    local row = MySQL.single.await('SELECT `firstname`, `lastname` FROM `users` WHERE `identifier` = ?', { identifier })
    return row and row.firstname and ('%s %s'):format(row.firstname, row.lastname or '') or identifier, nil
end

-- Vue complète d'un crew (panel et menu /crew)
-- Nombre de crews par type (les laboratoires sont réservés à un type de crew)
function Crews.countByType()
    local counts = {}

    for _, crew in pairs(crews) do
        counts[crew.type] = (counts[crew.type] or 0) + 1
    end

    return counts
end

-- Infos courtes d'un crew (territoires), nil s'il n'existe plus
function Crews.basic(crewId)
    local crew = crews[tonumber(crewId) or -1]
    return crew and { id = crew.id, label = crew.label, color = crew.color, type = crew.type } or nil
end

-- Joueurs connectés membres du crew (notifications)
function Crews.onlineSources(crewId)
    local list = {}

    for identifier, member in pairs(members) do
        if member.crew == crewId then
            local xPlayer = ESX.GetPlayerFromIdentifier(identifier)

            if xPlayer then
                list[#list + 1] = xPlayer.source
            end
        end
    end

    return list
end

function Crews.view(crewId)
    local crew = crews[crewId]

    if not crew then
        return nil
    end

    local list = {}

    for identifier, member in pairs(members) do
        if member.crew == crewId then
            local name, online = nameOf(identifier)
            list[#list + 1] = { identifier = identifier, name = name, online = online, rank = member.rank, rankLabel = rankLabel(crew, member.rank), joined = member.joined }
        end
    end

    table.sort(list, function(a, b)
        if a.rank ~= b.rank then
            return a.rank > b.rank
        end

        return a.name < b.name
    end)

    local nextLevel = Config.CrewLevels[levelOf(crew.xp) + 1]

    return {
        id = crew.id, slug = crew.slug, label = crew.label, type = crew.type, typeLabel = TYPES[crew.type] or crew.type, color = crew.color, logo = crew.logo,
        xp = crew.xp, level = levelOf(crew.xp), nextLevelXp = nextLevel, ranks = crew.ranks, topRank = topRank(crew), members = list,
        createdBy = crew.createdBy, createdAt = crew.createdAt,
    }
end

exports('getCrewOf', function(identifier)
    local member = members[identifier]
    return member and { crew = member.crew, rank = member.rank } or nil
end)

exports('getCrewView', Crews.view)
exports('setCrewMember', Crews.setMember)
exports('addCrewXp', Crews.addXp)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les crews.")
end

local function cleanText(value, min, max)
    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length >= min and length <= max and text or nil
end

local function crewFor(actor, id)
    if not Ranks.hasPermission(actor, 'crews.manage') then
        return nil, denied()
    end

    local crew = crews[tonumber(id) or -1]

    if not crew then
        return nil, Panel.fail('Crew introuvable.')
    end

    return crew
end

Panel.actions['crews.list'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'crews.manage') then
        return denied()
    end

    local counts, leaders = {}, {}

    for _, member in pairs(members) do
        counts[member.crew] = (counts[member.crew] or 0) + 1

        if crews[member.crew] and member.rank == topRank(crews[member.crew]) then
            leaders[member.crew] = true
        end
    end

    local list = {}

    for _, crew in pairs(crews) do
        list[#list + 1] = { id = crew.id, label = crew.label, type = crew.type, typeLabel = TYPES[crew.type] or crew.type, color = crew.color, level = levelOf(crew.xp), members = counts[crew.id] or 0, leader = leaders[crew.id] == true }
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return { ok = true, silent = true, crews = list, types = Config.CrewTypes }
end

Panel.actions['crews.info'] = function(_, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    return { ok = true, silent = true, crew = Crews.view(crew.id), types = Config.CrewTypes }
end

Panel.actions['crews.create'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'crews.manage') then
        return denied()
    end

    local label = cleanText(data.label, 2, 60)
    local slug = type(data.slug) == 'string' and data.slug:lower() or ''

    if not label then
        return Panel.fail('Le nom doit faire entre 2 et 60 caractères.')
    end

    if not slug:match('^[a-z0-9_]+$') or #slug < 2 or #slug > 30 then
        return Panel.fail('Clé invalide : 2 à 30 caractères, minuscules, chiffres et _.')
    end

    if not TYPES[data.type] then
        return Panel.fail('Type de crew inconnu.')
    end

    if (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `lunatic_crews` WHERE `slug` = ?', { slug })) or 0) > 0 then
        return Panel.fail('Un crew utilise déjà cette clé.')
    end

    local id = MySQL.insert.await('INSERT INTO `lunatic_crews` (`slug`, `label`, `type`, `created_by`, `created_at`) VALUES (?, ?, ?, ?, ?)', {
        slug, label, data.type, Staff.displayName(src), os.time(),
    })

    local queries = {}

    for index, rankName in ipairs(Config.CrewDefaultRanks) do
        queries[#queries + 1] = { query = 'INSERT INTO `lunatic_crew_ranks` (`crew_id`, `rank`, `label`) VALUES (?, ?, ?)', values = { id, index - 1, rankName } }
    end

    MySQL.transaction.await(queries)
    load()
    Logs.add(src, 'crews.create', nil, { id = id, label = label, type = data.type })

    return { ok = true, silent = true, id = id }
end

Panel.actions['crews.save'] = function(src, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    local label = cleanText(data.label, 2, 60)
    local color = type(data.color) == 'string' and data.color:match('^#%x%x%x%x%x%x$') and data.color:lower()
    local logo = data.logo == '' and '' or (type(data.logo) == 'string' and #data.logo <= 255 and data.logo:match('^https?://%S+$'))

    if not label or not color or not logo then
        return Panel.fail('Nom (2-60), couleur ou logo (adresse http(s)) invalide.')
    end

    if not TYPES[data.type] then
        return Panel.fail('Type de crew inconnu.')
    end

    MySQL.update.await('UPDATE `lunatic_crews` SET `label` = ?, `type` = ?, `color` = ?, `logo` = ? WHERE `id` = ?', { label, data.type, color, logo, crew.id })
    crew.label, crew.type, crew.color, crew.logo = label, data.type, color, logo
    publishCrew(crew.id)
    Logs.add(src, 'crews.save', nil, { id = crew.id, label = label, type = data.type })

    return { ok = true, silent = true }
end

Panel.actions['crews.delete'] = function(src, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    local former = {}

    for identifier, member in pairs(members) do
        if member.crew == crew.id then
            former[#former + 1] = identifier
        end
    end

    MySQL.transaction.await({
        { query = 'DELETE FROM `lunatic_crew_members` WHERE `crew_id` = ?', values = { crew.id } },
        { query = 'DELETE FROM `lunatic_crew_ranks` WHERE `crew_id` = ?', values = { crew.id } },
        { query = 'DELETE FROM `lunatic_crews` WHERE `id` = ?', values = { crew.id } },
    })

    load()

    for _, identifier in ipairs(former) do
        publishPlayer(identifier)
    end

    Logs.add(src, 'crews.delete', nil, { id = crew.id, label = crew.label, members = #former })
    return { ok = true, silent = true }
end

-- Rangs : renommer, ajouter au-dessus, retirer le plus haut s'il est vide
Panel.actions['crews.rank'] = function(src, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    if data.operation == 'rename' then
        local label = cleanText(data.label, 1, 40)
        local rank = tonumber(data.rank)

        if not label or not rank then
            return Panel.fail('Nom de rang invalide (1 à 40 caractères).')
        end

        MySQL.update.await('UPDATE `lunatic_crew_ranks` SET `label` = ? WHERE `crew_id` = ? AND `rank` = ?', { label, crew.id, rank })
    elseif data.operation == 'add' then
        local label = cleanText(data.label, 1, 40)

        if not label then
            return Panel.fail('Nom de rang invalide (1 à 40 caractères).')
        end

        if #crew.ranks >= 10 then
            return Panel.fail('Maximum 10 rangs par crew.')
        end

        MySQL.insert.await('INSERT INTO `lunatic_crew_ranks` (`crew_id`, `rank`, `label`) VALUES (?, ?, ?)', { crew.id, topRank(crew) + 1, label })
    elseif data.operation == 'remove' then
        local top = topRank(crew)

        if #crew.ranks <= 1 then
            return Panel.fail('Un crew garde au moins un rang.')
        end

        for _, member in pairs(members) do
            if member.crew == crew.id and member.rank == top then
                return Panel.fail('Le rang le plus haut a encore des membres.')
            end
        end

        MySQL.update.await('DELETE FROM `lunatic_crew_ranks` WHERE `crew_id` = ? AND `rank` = ?', { crew.id, top })
    else
        return Panel.fail('Opération inconnue.')
    end

    load()
    publishCrew(crew.id)
    return { ok = true, silent = true }
end

-- Membres : ajout par ID en jeu ou nom RP (comme les structures), changement de rang, retrait
Panel.actions['crews.addMember'] = function(src, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    local identifier = type(data.identifier) == 'string' and data.identifier:gsub('^license:', '') or nil
    local query = type(data.query) == 'string' and data.query:match('^%s*(.-)%s*$') or ''

    if not identifier then
        local serverId = tonumber(query)

        if serverId then
            local xPlayer = ESX.GetPlayerFromId(serverId)

            if not xPlayer then
                return Panel.fail(("Aucun joueur connecté avec l'ID %d."):format(serverId))
            end

            identifier = xPlayer.identifier
        else
            if (utf8.len(query) or 0) < 2 then
                return Panel.fail('Indiquez un ID en jeu ou au moins 2 lettres du nom RP.')
            end

            local rows = MySQL.query.await([[
                SELECT `identifier`, `firstname`, `lastname` FROM `users`
                WHERE CONCAT(`firstname`, ' ', `lastname`) LIKE ? ORDER BY `lastname` LIMIT 10
            ]], { '%' .. query:gsub('[%%_\\]', '\\%0') .. '%' }) or {}

            if #rows == 0 then
                return Panel.fail('Aucun personnage ne correspond.')
            end

            if #rows > 1 then
                local candidates = {}

                for _, row in ipairs(rows) do
                    local member = members[row.identifier]
                    candidates[#candidates + 1] = {
                        identifier = row.identifier, name = ('%s %s'):format(row.firstname or '?', row.lastname or ''),
                        job = member and crews[member.crew] and ('crew ' .. crews[member.crew].label) or 'sans crew',
                    }
                end

                return { ok = true, silent = true, candidates = candidates }
            end

            identifier = rows[1].identifier
        end
    end

    local ok, failure = Crews.setMember(identifier, crew.id, 0)

    if not ok then
        return Panel.fail(failure)
    end

    local name = nameOf(identifier)
    Logs.add(src, 'crews.member', name, { id = crew.id, label = crew.label, operation = 'add' })

    return { ok = true, silent = true, name = name }
end

Panel.actions['crews.setMember'] = function(src, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    local identifier = type(data.identifier) == 'string' and data.identifier or ''
    local member = members[identifier]

    if not member or member.crew ~= crew.id then
        return Panel.fail("Ce personnage ne fait plus partie du crew.")
    end

    local ok, failure

    if data.remove == true then
        ok, failure = Crews.setMember(identifier, nil)
    else
        ok, failure = Crews.setMember(identifier, crew.id, tonumber(data.rank))
    end

    if not ok then
        return Panel.fail(failure)
    end

    Logs.add(src, 'crews.member', (nameOf(identifier)), { id = crew.id, label = crew.label, operation = data.remove == true and 'remove' or ('rang ' .. tostring(data.rank)) })
    return { ok = true, silent = true }
end

Panel.actions['crews.xp'] = function(src, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    local amount = tonumber(data.amount)

    if not amount or amount ~= math.floor(amount) or amount == 0 or math.abs(amount) > 1000000 then
        return Panel.fail('Montant d\'XP invalide (entier non nul).')
    end

    Crews.addXp(crew.id, amount)
    Logs.add(src, 'crews.xp', nil, { id = crew.id, label = crew.label, amount = amount })

    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Crews chargé.')
