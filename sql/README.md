# Mises à jour de la base de données

Chaque fichier est une mise à niveau à importer **une seule fois**, dans l'ordre des dates, via phpMyAdmin (onglet SQL ou Importer).

Avant chaque import : éteindre le serveur FiveM et exporter une sauvegarde de la base.

| Fichier | Contenu | Importé |
|---|---|---|
| `2026-10-17_esx_1.16.2.sql` | Alignement sur le schéma ESX 1.16.2 (`users.last_property`, clé unique `user_licenses`) | à faire |

Les tables de nos scripts (`lunatic_admin_*`, etc.) sont créées automatiquement au démarrage de la resource : rien à importer pour elles.

Les sauvegardes complètes (`.sql` exportés de phpMyAdmin) restent dans `Lunatic_sauvegardes`, jamais dans ce dépôt : elles contiennent les données des joueurs.
