-- Création de personnage, côté serveur : instance privée pendant la création, nationalité du personnage.
-- L'identité est enregistrée par esx_identity (mêmes vérifications qu'avant), l'apparence par illenium-appearance.

local creating = {}

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_character_info` (
            `identifier` VARCHAR(60) NOT NULL,
            `nationality` VARCHAR(40) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Table créée avant la nationalité : on ajoute la colonne
    local hasColumn = MySQL.scalar.await("SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'lunatic_character_info' AND COLUMN_NAME = 'nationality'")

    if tonumber(hasColumn) == 0 then
        MySQL.query.await("ALTER TABLE `lunatic_character_info` ADD COLUMN `nationality` VARCHAR(40) NOT NULL DEFAULT ''")
    end
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

local nationalities = {}
for _, name in ipairs(Config.Nationalities) do
    nationalities[name] = true
end

-- Nationalité (esx_identity ne la garde pas) : uniquement une valeur de la liste
lib.callback.register('lunatic_creator:saveInfo', function(src, data)
    local xPlayer = ESX.GetPlayerFromId(src)
    local nationality = type(data) == 'table' and data.nationality

    if not xPlayer or not creating[src] or type(nationality) ~= 'string' or not nationalities[nationality] then
        return false
    end

    MySQL.query.await('INSERT INTO `lunatic_character_info` (`identifier`, `nationality`, `created_at`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `nationality` = VALUES(`nationality`)', {
        xPlayer.getIdentifier(), nationality, os.time(),
    })

    return true
end)

exports('getNationality', function(identifier)
    return MySQL.scalar.await('SELECT `nationality` FROM `lunatic_character_info` WHERE `identifier` = ?', { identifier })
end)
