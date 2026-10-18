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

    -- Lot 3 : avertissements et bans. Dates en secondes Unix (os.time) pour éviter les écarts de fuseau horaire.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_admin_sanctions` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `type` VARCHAR(10) NOT NULL,
            `license` VARCHAR(60) NOT NULL,
            `name` VARCHAR(80) NOT NULL DEFAULT '',
            `identifiers` LONGTEXT NULL DEFAULT NULL,
            `tokens` LONGTEXT NULL DEFAULT NULL,
            `reason` VARCHAR(255) NOT NULL,
            `staff_license` VARCHAR(60) NULL DEFAULT NULL,
            `staff_name` VARCHAR(80) NOT NULL DEFAULT '',
            `staff_level` INT NOT NULL DEFAULT 0,
            `created_at` BIGINT NOT NULL,
            `expires_at` BIGINT NULL DEFAULT NULL,
            `revoked_at` BIGINT NULL DEFAULT NULL,
            `revoked_by` VARCHAR(80) NULL DEFAULT NULL,
            `revoke_reason` VARCHAR(255) NULL DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_admin_sanctions_license` (`license`),
            KEY `idx_lunatic_admin_sanctions_active` (`type`, `revoked_at`, `expires_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Abonnements Premium / Premium+ (expires_at NULL = à vie, secondes Unix sinon)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_admin_premium` (
            `license` VARCHAR(60) NOT NULL,
            `tier` VARCHAR(16) NOT NULL,
            `expires_at` BIGINT NULL DEFAULT NULL,
            `granted_by` VARCHAR(80) NOT NULL DEFAULT '',
            `granted_at` BIGINT NOT NULL,
            PRIMARY KEY (`license`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Crédits boutique : solde par joueur et historique des mouvements
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_admin_credits` (
            `license` VARCHAR(60) NOT NULL,
            `balance` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`license`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_admin_credit_log` (
            `id` BIGINT NOT NULL AUTO_INCREMENT,
            `license` VARCHAR(60) NOT NULL,
            `amount` INT NOT NULL,
            `balance_after` INT NOT NULL,
            `reason` VARCHAR(255) NOT NULL DEFAULT '',
            `staff_name` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_admin_credit_log_license` (`license`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Prison staff : temps restant (secondes) des peines en cours, décompté seulement joueur connecté
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_admin_jail` (
            `license` VARCHAR(60) NOT NULL,
            `sanction_id` INT NOT NULL,
            `remaining` INT NOT NULL,
            `reason` VARCHAR(255) NOT NULL DEFAULT '',
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`license`),
            KEY `idx_lunatic_admin_jail_sanction` (`sanction_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end
