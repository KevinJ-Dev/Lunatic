-- Gestion des personnages par le staff (exports appelés par lunatic_admin, qui vérifie les permissions) :
-- liste d'un compte, emplacements en plus, archivage et récupération d'un personnage.
-- Archiver = renommer « charN:<licence> » en « archT:<licence> » dans toutes les tables (rien n'est effacé) ;
-- récupérer = l'inverse vers un emplacement libre. Tout se fait dans une transaction.

local function bareLicense(license)
    return (tostring(license or ''):gsub('^license:', ''))
end

-- Colonnes `identifier` / `owner` des tables qui référencent un personnage (hors users), lues une fois
local columns = nil

local function identifierColumns()
    if not columns then
        columns = MySQL.query.await([[
            SELECT `TABLE_NAME` AS `tbl`, `COLUMN_NAME` AS `col` FROM information_schema.COLUMNS
            WHERE `TABLE_SCHEMA` = DATABASE() AND `COLUMN_NAME` IN ('identifier', 'owner') AND `TABLE_NAME` <> 'users'
              AND `DATA_TYPE` IN ('varchar', 'char', 'text', 'mediumtext', 'longtext')
        ]]) or {}
    end

    return columns
end

local function renameCharacter(from, to)
    local queries = {}

    for _, column in ipairs(identifierColumns()) do
        queries[#queries + 1] = { query = ('UPDATE `%s` SET `%s` = ? WHERE `%s` = ?'):format(column.tbl, column.col, column.col), values = { to, from } }
    end

    queries[#queries + 1] = { query = 'UPDATE `users` SET `identifier` = ? WHERE `identifier` = ?', values = { to, from } }
    return MySQL.transaction.await(queries)
end

local function exists(identifier)
    return MySQL.scalar.await('SELECT 1 FROM `users` WHERE `identifier` = ?', { identifier }) ~= nil
end

-- exports.lunatic_characters:getCharacters('license:…') -> { characters, archived, extra, max }
exports('getCharacters', function(license)
    local bare = bareLicense(license)

    if not bare:match('^%x+$') then
        return nil
    end

    local rows = MySQL.query.await([[
        SELECT `identifier`, `firstname`, `lastname`, `job`, `job_grade`, UNIX_TIMESTAMP(`last_seen`) AS `last_seen`
        FROM `users` WHERE SUBSTRING_INDEX(`identifier`, ':', -1) = ?
    ]], { bare }) or {}

    local jobs = ESX.GetJobs() or {}
    local result = { characters = {}, archived = {}, max = Config.Slots.max }

    for _, row in ipairs(rows) do
        local job = jobs[row.job]
        local character = {
            identifier = row.identifier,
            name = row.firstname and row.firstname ~= '' and ('%s %s'):format(row.firstname, row.lastname or '') or nil,
            job = job and job.label or row.job,
            lastSeen = tonumber(row.last_seen),
            online = ESX.GetPlayerFromIdentifier(row.identifier) ~= nil,
        }
        local slot = tonumber(row.identifier:match('^char(%d+):'))
        local archivedAt = tonumber(row.identifier:match('^arch(%d+):'))

        if slot then
            character.slot = slot
            result.characters[#result.characters + 1] = character
        elseif archivedAt then
            character.archivedAt = archivedAt
            result.archived[#result.archived + 1] = character
        end
    end

    table.sort(result.characters, function(a, b) return a.slot < b.slot end)
    table.sort(result.archived, function(a, b) return a.archivedAt > b.archivedAt end)
    result.extra = tonumber(MySQL.scalar.await('SELECT `extra` FROM `lunatic_character_slots` WHERE `license` = ?', { bare })) or 0
    return result
end)

-- Emplacements ajoutés à la main (en plus de ceux de l'abonnement)
exports('setExtraSlots', function(license, extra)
    local bare = bareLicense(license)
    extra = math.tointeger(tonumber(extra))

    if not bare:match('^%x+$') or not extra or extra < 0 or extra > Config.Slots.max then
        return false, ('Emplacements en plus : de 0 à %d.'):format(Config.Slots.max)
    end

    MySQL.query.await('INSERT INTO `lunatic_character_slots` (`license`, `extra`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `extra` = VALUES(`extra`)', { bare, extra })
    return true
end)

-- Archive un personnage (hors ligne) : il disparaît de la sélection, toutes ses données sont gardées
exports('archiveCharacter', function(identifier)
    local slot, bare = tostring(identifier):match('^char(%d+):(%x+)$')

    if not slot then
        return false, 'Personnage introuvable.'
    end

    if ESX.GetPlayerFromIdentifier(identifier) then
        return false, 'Ce personnage est en jeu : le joueur doit changer de personnage ou se déconnecter.'
    end

    if not exists(identifier) then
        return false, 'Personnage introuvable en base.'
    end

    local archived = ('arch%d:%s'):format(os.time(), bare)

    if not renameCharacter(identifier, archived) then
        return false, "L'archivage a échoué (voir la console)."
    end

    return true, archived
end)

-- Récupère un personnage archivé dans un emplacement libre du même compte
exports('restoreCharacter', function(identifier, slot)
    local bare = tostring(identifier):match('^arch%d+:(%x+)$')
    slot = math.tointeger(tonumber(slot))

    if not bare then
        return false, 'Personnage archivé introuvable.'
    end

    if not slot or slot < 1 or slot > Config.Slots.max then
        return false, ('Emplacement invalide (1 à %d).'):format(Config.Slots.max)
    end

    local target = ('char%d:%s'):format(slot, bare)

    if exists(target) then
        return false, ("L'emplacement %d est déjà occupé."):format(slot)
    end

    if not exists(identifier) then
        return false, 'Personnage archivé introuvable en base.'
    end

    if not renameCharacter(identifier, target) then
        return false, 'La récupération a échoué (voir la console).'
    end

    return true, target
end)
