-- Création des tables au démarrage (aucune requête SQL à importer à la main)

DB = {}

function DB.init()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_admin_ranks` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(32) NOT NULL,
            `color` VARCHAR(7) NOT NULL DEFAULT '#9650ff',
            `level` INT NOT NULL,
            `is_owner` TINYINT(1) NOT NULL DEFAULT 0,
            `permissions` LONGTEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_lunatic_admin_ranks_level` (`level`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_admin_staff` (
            `license` VARCHAR(60) NOT NULL,
            `rank_id` INT NOT NULL,
            `name` VARCHAR(64) NOT NULL DEFAULT '',
            `added_by` VARCHAR(60) NULL DEFAULT NULL,
            `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`license`),
            KEY `idx_lunatic_admin_staff_rank` (`rank_id`),
            CONSTRAINT `fk_lunatic_admin_staff_rank` FOREIGN KEY (`rank_id`)
                REFERENCES `lunatic_admin_ranks` (`id`) ON DELETE RESTRICT
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_admin_logs` (
            `id` BIGINT NOT NULL AUTO_INCREMENT,
            `actor_license` VARCHAR(60) NULL DEFAULT NULL,
            `actor_name` VARCHAR(64) NOT NULL DEFAULT '',
            `action` VARCHAR(48) NOT NULL,
            `target` VARCHAR(100) NULL DEFAULT NULL,
            `details` LONGTEXT NULL DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_admin_logs_created` (`created_at`),
            KEY `idx_lunatic_admin_logs_actor` (`actor_license`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end
