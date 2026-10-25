-- Illégal, étape 1 : crews (tuile Crews). Un crew a un type (Mafia, MC, Organisation, Gang), des rangs,
-- des membres (un crew au plus par personnage) et de l'XP qui donne son level.
-- Indépendant du métier ESX. Le crew de chaque joueur connecté est dans son statebag « crew ».
-- Le jeu (tablette de lunatic_illegal) passe par les exports en bas de fichier.

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
        id = crew.id, slug = crew.slug, label = crew.label, type = crew.type, color = crew.color, lab = Crews.labOf(crew),
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
            motto = row.motto or '', lab = row.lab or '',
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

    -- Devise (slogan) et laboratoire ('' = celui du type, 'none' = aucun, sinon un type de crew)
    MySQL.query.await("ALTER TABLE `lunatic_crews` ADD COLUMN IF NOT EXISTS `motto` VARCHAR(80) NOT NULL DEFAULT '', ADD COLUMN IF NOT EXISTS `lab` VARCHAR(20) NOT NULL DEFAULT ''")

    -- Demandes faites en jeu (commande /crew) : rejoindre un crew ou en créer un
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_crew_requests` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(60) NOT NULL,
            `name` VARCHAR(80) NOT NULL,
            `kind` VARCHAR(10) NOT NULL,
            `crew_id` INT NULL DEFAULT NULL,
            `label` VARCHAR(60) NOT NULL DEFAULT '',
            `type` VARCHAR(20) NOT NULL DEFAULT '',
            `message` VARCHAR(255) NOT NULL DEFAULT '',
            `status` VARCHAR(10) NOT NULL DEFAULT 'pending',
            `handled_by` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            `handled_at` BIGINT NULL DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_crew_requests_status` (`status`, `created_at`),
            KEY `idx_lunatic_crew_requests_identifier` (`identifier`)
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

-- Vue complète d'un crew (panel et tablette)
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
        motto = crew.motto, lab = crew.lab, levels = Config.CrewLevels,
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

-- Laboratoire de drogue accessible : celui du type par défaut, un autre type, ou aucun
function Crews.labOf(crew)
    if crew.lab == 'none' then
        return nil
    end

    if crew.lab ~= '' and TYPES[crew.lab] then
        return crew.lab
    end

    return crew.type ~= 'independent' and crew.type or nil
end

-- Crew réel d'un joueur connecté (lunatic_illegal) : à utiliser côté serveur à la place du statebag « crew »,
-- qu'un client peut modifier de son côté
function Crews.ofPlayer(src)
    local xPlayer = ESX.GetPlayerFromId(tonumber(src) or -1)
    local member = xPlayer and members[xPlayer.identifier]
    local crew = member and crews[member.crew]

    if not crew then
        return nil
    end

    return { id = crew.id, label = crew.label, type = crew.type, lab = Crews.labOf(crew), level = levelOf(crew.xp), rank = member.rank, leader = member.rank == topRank(crew) }
end

exports('getPlayerCrew', Crews.ofPlayer)
exports('getCrewOnline', Crews.onlineSources)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les crews.")
end

local cleanText = Util.cleanText

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
    local requests = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM `lunatic_crew_requests` WHERE `status` = 'pending'")) or 0
    return { ok = true, silent = true, crews = list, types = Config.CrewTypes, requests = requests }
end

Panel.actions['crews.info'] = function(_, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    return { ok = true, silent = true, crew = Crews.view(crew.id), types = Config.CrewTypes }
end

-- Crée un crew avec les rangs par défaut ; renvoie son id
function Crews.create(label, slug, crewType, by)
    local id = MySQL.insert.await('INSERT INTO `lunatic_crews` (`slug`, `label`, `type`, `created_by`, `created_at`) VALUES (?, ?, ?, ?, ?)', {
        slug, label, crewType, by, os.time(),
    })

    local queries = {}

    for index, rankName in ipairs(Config.CrewDefaultRanks) do
        queries[#queries + 1] = { query = 'INSERT INTO `lunatic_crew_ranks` (`crew_id`, `rank`, `label`) VALUES (?, ?, ?)', values = { id, index - 1, rankName } }
    end

    MySQL.transaction.await(queries)
    load()
    return id
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

    local id = Crews.create(label, slug, data.type, Staff.displayName(src))
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

    local motto = cleanText(data.motto or '', 0, 80)
    local lab = data.lab == '' and '' or data.lab == 'none' and 'none' or (TYPES[data.lab] and data.lab)
    local xp = tonumber(data.xp)

    if not motto then
        return Panel.fail('La devise fait 80 caractères maximum.')
    end

    if not lab then
        return Panel.fail('Laboratoire inconnu.')
    end

    if not xp or xp ~= math.floor(xp) or xp < 0 or xp > 10000000 then
        return Panel.fail("XP invalide : nombre entier de 0 à 10 000 000.")
    end

    local before = { label = crew.label, type = crew.type, xp = crew.xp, lab = crew.lab }

    MySQL.update.await('UPDATE `lunatic_crews` SET `label` = ?, `type` = ?, `color` = ?, `logo` = ?, `motto` = ?, `lab` = ?, `xp` = ? WHERE `id` = ?', { label, data.type, color, logo, motto, lab, xp, crew.id })
    crew.label, crew.type, crew.color, crew.logo, crew.motto, crew.lab, crew.xp = label, data.type, color, logo, motto, lab, xp

    -- Chef choisi parmi les membres : il passe au rang le plus haut, l'ancien chef descend d'un rang
    if type(data.leader) == 'string' and data.leader ~= '' then
        local member = members[data.leader]

        if not member or member.crew ~= crew.id then
            return Panel.fail("Le chef choisi ne fait pas partie du crew.")
        end

        local top = topRank(crew)

        if member.rank ~= top then
            local below = nil

            for _, entry in ipairs(crew.ranks) do
                if entry.rank < top and (not below or entry.rank > below) then
                    below = entry.rank
                end
            end

            for identifier, other in pairs(members) do
                if other.crew == crew.id and other.rank == top and identifier ~= data.leader and below then
                    Crews.setMember(identifier, crew.id, below)
                end
            end

            Crews.setMember(data.leader, crew.id, top)
        end
    end

    publishCrew(crew.id)
    Logs.add(src, 'crews.save', nil, { id = crew.id, label = label, type = data.type, before = before, xp = xp, lab = lab })

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

    for _, hook in ipairs(Crews.deleteHooks) do
        hook(crew.id)
    end

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
        return Panel.fail("Montant d'XP invalide (entier non nul).")
    end

    Crews.addXp(crew.id, amount)
    Logs.add(src, 'crews.xp', nil, { id = crew.id, label = crew.label, amount = amount })

    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Rejoindre, wipe, influence, territoires
---------------------------------------------------------------------

local function lowestRank(crew)
    local low

    for _, entry in ipairs(crew.ranks) do
        if not low or entry.rank < low then
            low = entry.rank
        end
    end

    return low or 0
end

-- Le membre du staff rejoint le crew avec son personnage (rang le plus bas, modifiable ensuite)
Panel.actions['crews.join'] = function(src, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer then
        return Panel.fail("Votre personnage n'est pas chargé.")
    end

    local ok, failure = Crews.setMember(xPlayer.identifier, crew.id, lowestRank(crew))

    if not ok then
        return Panel.fail(failure)
    end

    Logs.add(src, 'crews.member', xPlayer.getName(), { id = crew.id, label = crew.label, operation = 'rejoint (staff)' })
    return { ok = true, silent = true }
end

-- Fonctions appelées par le wipe (coffres des positions et des planques, partie infrastructure)
Crews.wipeHooks = {}
-- Fonctions appelées à la suppression d'un crew (positions et planques)
Crews.deleteHooks = {}

local function clearInfluence(crewId)
    MySQL.update.await('DELETE FROM `lunatic_crew_influence` WHERE `crew_id` = ?', { crewId })

    if Territories and Territories.recompute then
        Territories.recompute()
    end
end

-- Remet le crew à zéro : XP, influence, coffres ; membres retirés si demandé
Panel.actions['crews.wipe'] = function(src, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    crew.xp = 0
    MySQL.update.await('UPDATE `lunatic_crews` SET `xp` = 0 WHERE `id` = ?', { crew.id })
    clearInfluence(crew.id)

    for _, hook in ipairs(Crews.wipeHooks) do
        hook(crew.id)
    end

    local removed = 0

    if data.members == true then
        for identifier, member in pairs(members) do
            if member.crew == crew.id then
                Crews.setMember(identifier, nil)
                removed = removed + 1
            end
        end
    end

    publishCrew(crew.id)
    Logs.add(src, 'crews.wipe', nil, { id = crew.id, label = crew.label, members = removed })
    return { ok = true, silent = true }
end

-- Efface l'influence du crew dans toutes les zones
Panel.actions['crews.resetInfluence'] = function(src, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    clearInfluence(crew.id)
    Logs.add(src, 'crews.influence', nil, { id = crew.id, label = crew.label })
    return { ok = true, silent = true }
end

-- Zones où le crew a de l'influence ou qu'il tient
Panel.actions['crews.territories'] = function(_, actor, data)
    local crew, err = crewFor(actor, data.id)

    if not crew then
        return err
    end

    local list = {}

    for _, t in ipairs(Territories and Territories.forCrew and Territories.forCrew(crew.id) or {}) do
        if t.owned or (t.influence or 0) > 0 then
            list[#list + 1] = t
        end
    end

    return { ok = true, silent = true, territories = list }
end

---------------------------------------------------------------------
-- Demandes de crew (commande /crew en jeu, lunatic_illegal)
---------------------------------------------------------------------

local ACCENTS = { ['à'] = 'a', ['â'] = 'a', ['ä'] = 'a', ['ç'] = 'c', ['é'] = 'e', ['è'] = 'e', ['ê'] = 'e', ['ë'] = 'e',
    ['î'] = 'i', ['ï'] = 'i', ['ô'] = 'o', ['ö'] = 'o', ['ù'] = 'u', ['û'] = 'u', ['ü'] = 'u', ['ÿ'] = 'y', ['œ'] = 'oe' }

-- Clé interne libre à partir du nom (« Les Ballas » -> « les_ballas », puis « les_ballas_2 »…)
local function freeSlug(label)
    local base = label:lower()

    for accent, plain in pairs(ACCENTS) do
        base = base:gsub(accent, plain)
    end

    base = base:gsub('[^a-z0-9]+', '_'):gsub('^_+', ''):gsub('_+$', ''):sub(1, 26)

    if #base < 2 then
        base = 'crew'
    end

    local slug, index = base, 1

    while (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `lunatic_crews` WHERE `slug` = ?', { slug })) or 0) > 0 do
        index = index + 1
        slug = ('%s_%d'):format(base, index)
    end

    return slug
end

-- Ce que le formulaire en jeu propose
exports('getCrewRequestOptions', function()
    local list = {}

    for _, crew in pairs(crews) do
        list[#list + 1] = { id = crew.id, label = crew.label, typeLabel = TYPES[crew.type] or crew.type }
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return { crews = list, types = Config.CrewTypes, messageMax = Config.CrewRequestMessageMax }
end)

-- Nouvelle demande d'un joueur connecté ; renvoie ok, message d'erreur
exports('createCrewRequest', function(src, data)
    local xPlayer = ESX.GetPlayerFromId(tonumber(src) or -1)

    if not xPlayer or type(data) ~= 'table' then
        return false, 'Personnage introuvable.'
    end

    if members[xPlayer.identifier] then
        return false, "Vous faites déjà partie d'un crew."
    end

    if (tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM `lunatic_crew_requests` WHERE `identifier` = ? AND `status` = 'pending'", { xPlayer.identifier })) or 0) > 0 then
        return false, 'Vous avez déjà une demande en attente.'
    end

    local message = cleanText(data.message or '', 0, Config.CrewRequestMessageMax)

    if not message then
        return false, ('La motivation fait %d caractères maximum.'):format(Config.CrewRequestMessageMax)
    end

    local crewId, label, crewType = nil, '', ''

    if data.kind == 'join' then
        local crew = crews[tonumber(data.crew) or -1]

        if not crew then
            return false, 'Crew introuvable.'
        end

        crewId, label, crewType = crew.id, crew.label, crew.type
    elseif data.kind == 'create' then
        label = cleanText(data.label, 2, 60)
        crewType = TYPES[data.type] and data.type

        if not label then
            return false, 'Le nom du crew doit faire entre 2 et 60 caractères.'
        end

        if not crewType then
            return false, 'Type de crew inconnu.'
        end
    else
        return false, 'Demande inconnue.'
    end

    MySQL.insert.await('INSERT INTO `lunatic_crew_requests` (`identifier`, `name`, `kind`, `crew_id`, `label`, `type`, `message`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        xPlayer.identifier, xPlayer.getName(), data.kind, crewId, label, crewType, message, os.time(),
    })

    return true
end)

local function requestOf(row)
    return {
        id = tonumber(row.id), identifier = row.identifier, name = row.name, kind = row.kind, crewId = tonumber(row.crew_id), label = row.label,
        type = row.type, typeLabel = TYPES[row.type] or row.type, message = row.message, status = row.status, handledBy = row.handled_by,
        createdAt = tonumber(row.created_at), handledAt = tonumber(row.handled_at),
        member = members[row.identifier] and crews[members[row.identifier].crew] and crews[members[row.identifier].crew].label or nil,
    }
end

Panel.actions['crews.requests'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'crews.manage') then
        return denied()
    end

    local pending, handled = {}, {}

    for _, row in ipairs(MySQL.query.await("SELECT * FROM `lunatic_crew_requests` WHERE `status` = 'pending' ORDER BY `created_at`") or {}) do
        pending[#pending + 1] = requestOf(row)
    end

    for _, row in ipairs(MySQL.query.await("SELECT * FROM `lunatic_crew_requests` WHERE `status` <> 'pending' ORDER BY `handled_at` DESC LIMIT 20") or {}) do
        handled[#handled + 1] = requestOf(row)
    end

    return { ok = true, silent = true, pending = pending, handled = handled }
end

Panel.actions['crews.handleRequest'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'crews.manage') then
        return denied()
    end

    local row = MySQL.single.await("SELECT * FROM `lunatic_crew_requests` WHERE `id` = ? AND `status` = 'pending'", { tonumber(data.id) or -1 })

    if not row then
        return Panel.fail('Demande introuvable ou déjà traitée.')
    end

    local accept = data.accept == true
    local crewId

    if accept then
        if members[row.identifier] then
            return Panel.fail("Ce personnage fait déjà partie d'un crew : refusez la demande.")
        end

        if row.kind == 'join' then
            local crew = crews[tonumber(row.crew_id) or -1]

            if not crew then
                return Panel.fail("Ce crew n'existe plus : refusez la demande.")
            end

            crewId = crew.id
            local ok, failure = Crews.setMember(row.identifier, crew.id, lowestRank(crew))

            if not ok then
                return Panel.fail(failure)
            end
        else
            if not TYPES[row.type] then
                return Panel.fail('Type de crew inconnu : refusez la demande.')
            end

            crewId = Crews.create(row.label, freeSlug(row.label), row.type, Staff.displayName(src))
            local ok, failure = Crews.setMember(row.identifier, crewId, topRank(crews[crewId]))

            if not ok then
                return Panel.fail(failure)
            end
        end
    end

    MySQL.update.await('UPDATE `lunatic_crew_requests` SET `status` = ?, `handled_by` = ?, `handled_at` = ? WHERE `id` = ?', {
        accept and 'accepted' or 'refused', Staff.displayName(src), os.time(), row.id,
    })

    -- Réponse au joueur s'il est connecté
    local xPlayer = ESX.GetPlayerFromIdentifier(row.identifier)

    if xPlayer then
        local text = accept
            and (row.kind == 'join' and ('Demande acceptée : bienvenue dans %s.'):format(row.label) or ('Demande acceptée : le crew %s est créé, vous en êtes le chef.'):format(row.label))
            or ('Votre demande de crew (%s) a été refusée.'):format(row.label)
        xPlayer.showNotification(text, accept and 'success' or 'error')
    end

    Logs.add(src, 'crews.request', row.name, { kind = row.kind, label = row.label, accept = accept, id = crewId })
    return { ok = true, silent = true, crewId = crewId }
end

print('[lunatic_admin] Module Crews chargé.')
