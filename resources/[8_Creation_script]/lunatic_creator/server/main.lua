-- Création de personnage, côté serveur : instance privée pendant la création, lieu de naissance du personnage.
-- L'identité est enregistrée par esx_identity (mêmes vérifications qu'avant), l'apparence par illenium-appearance.

local creating = {}

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_character_info` (
            `identifier` VARCHAR(60) NOT NULL,
            `birthplace` VARCHAR(60) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

-- Instance privée : personne ne voit le personnage pendant sa création
RegisterNetEvent('lunatic_creator:enter', function()
    local src = source
    creating[src] = true
    SetPlayerRoutingBucket(src, 5000 + src)
    -- Lu par lunatic_admin : pas de photo automatique pendant la création
    Player(src).state:set('lunaticCreating', true, true)
end)

RegisterNetEvent('lunatic_creator:leave', function()
    local src = source

    if creating[src] then
        creating[src] = nil
        SetPlayerRoutingBucket(src, 0)
        Player(src).state:set('lunaticCreating', nil, true)
    end
end)

-- Photo d'identité de fin de création (enregistrée par lunatic_admin, tuile Images)
lib.callback.register('lunatic_creator:mugshot', function(src)
    if not creating[src] or GetResourceState('lunatic_admin') ~= 'started' then
        return false
    end

    local ok, done = pcall(function() return exports.lunatic_admin:requestMugshot(src) end)
    return ok and done == true
end)

AddEventHandler('playerDropped', function()
    creating[source] = nil
end)

local function cleanText(value, min, max)
    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length >= min and length <= max and text or nil
end

-- Lieu de naissance (esx_identity ne le garde pas)
lib.callback.register('lunatic_creator:saveInfo', function(src, data)
    local xPlayer = ESX.GetPlayerFromId(src)
    local birthplace = cleanText(type(data) == 'table' and data.birthplace or '', 0, 60)

    if not xPlayer or not creating[src] or not birthplace then
        return false
    end

    MySQL.query.await('INSERT INTO `lunatic_character_info` (`identifier`, `birthplace`, `created_at`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `birthplace` = VALUES(`birthplace`)', {
        xPlayer.getIdentifier(), birthplace, os.time(),
    })

    return true
end)

exports('getBirthplace', function(identifier)
    return MySQL.scalar.await('SELECT `birthplace` FROM `lunatic_character_info` WHERE `identifier` = ?', { identifier })
end)
