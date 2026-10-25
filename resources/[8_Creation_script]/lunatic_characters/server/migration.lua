-- Passage au mode multi-personnages : les personnages créés avant (identifiant = licence sans préfixe)
-- deviennent le personnage de l'emplacement 1 (« char1:<licence> »), dans toutes les tables qui les référencent.
-- Fait une seule fois (KVP), dans une transaction : tout est migré ou rien ne l'est.
-- Seules les colonnes `identifier` et `owner` égales à l'identifiant exact d'un joueur sont modifiées.

Migration = { done = false }

local KVP = 'migration_char1'

MySQL.ready(function()
    -- Emplacements ajoutés à la main par le staff (panel), en plus de ceux de l'abonnement
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_character_slots` (
            `license` VARCHAR(60) NOT NULL,
            `extra` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`license`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    if GetResourceKvpInt(KVP) == 1 then
        Migration.done = true
        return
    end

    local rows = MySQL.query.await("SELECT `identifier` FROM `users` WHERE `identifier` NOT LIKE 'char%:%'") or {}
    local identifiers = {}

    for _, row in ipairs(rows) do
        identifiers[#identifiers + 1] = row.identifier
    end

    if #identifiers == 0 then
        SetResourceKvpInt(KVP, 1)
        Migration.done = true
        return
    end

    local columns = MySQL.query.await([[
        SELECT `TABLE_NAME` AS `tbl`, `COLUMN_NAME` AS `col` FROM information_schema.COLUMNS
        WHERE `TABLE_SCHEMA` = DATABASE() AND `COLUMN_NAME` IN ('identifier', 'owner') AND `TABLE_NAME` <> 'users'
          AND `DATA_TYPE` IN ('varchar', 'char', 'text', 'mediumtext', 'longtext')
    ]]) or {}

    local queries, touched = {}, {}

    for _, column in ipairs(columns) do
        queries[#queries + 1] = {
            query = ("UPDATE `%s` SET `%s` = CONCAT('char1:', `%s`) WHERE `%s` IN (?)"):format(column.tbl, column.col, column.col, column.col),
            values = { identifiers },
        }
        touched[#touched + 1] = ('%s.%s'):format(column.tbl, column.col)
    end

    -- La table users en dernier
    queries[#queries + 1] = { query = "UPDATE `users` SET `identifier` = CONCAT('char1:', `identifier`) WHERE `identifier` IN (?)", values = { identifiers } }

    print(("^3[lunatic_characters] Migration : %d personnage(s) vers l'emplacement 1, %d colonne(s) concernée(s)…^0"):format(#identifiers, #touched))

    if not MySQL.transaction.await(queries) then
        print("^1[lunatic_characters] Migration échouée : rien n'a été modifié. Connexions refusées tant que ce n'est pas réglé (voir les erreurs oxmysql).^0")
        return
    end

    SetResourceKvpInt(KVP, 1)
    Migration.done = true
    print(('^2[lunatic_characters] Migration terminée. Colonnes mises à jour : %s^0'):format(table.concat(touched, ', ')))
end)
