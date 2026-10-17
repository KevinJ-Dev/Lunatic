-- Mise à niveau de la base vers le schéma ESX Legacy 1.16.2
-- À importer une fois dans phpMyAdmin (onglet SQL ou Importer), serveur FiveM ÉTEINT, après une sauvegarde.
-- Les autres changements d'ESX 1.16 (colonne users.ssn, jobs.type, index) sont déjà faits
-- automatiquement par es_extended au démarrage.
-- Le script peut être relancé sans risque (IF EXISTS / IF NOT EXISTS, syntaxe MariaDB).

-- users.last_property : varchar(255) -> longtext (les propriétés stockées peuvent dépasser 255 caractères)
ALTER TABLE `users` MODIFY `last_property` LONGTEXT DEFAULT NULL;

-- user_licenses : une même licence ne peut plus être donnée deux fois au même joueur
-- (l'ancien index simple sur owner est remplacé par une clé unique owner + type)
DELETE ul1 FROM `user_licenses` ul1
    JOIN `user_licenses` ul2 ON ul1.`owner` = ul2.`owner` AND ul1.`type` = ul2.`type` AND ul1.`id` > ul2.`id`;

ALTER TABLE `user_licenses`
    DROP INDEX IF EXISTS `esx_user_licenses_owner`,
    ADD UNIQUE KEY IF NOT EXISTS `uq_user_licenses_owner_type` (`owner`, `type`);
