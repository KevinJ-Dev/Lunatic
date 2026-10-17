-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2022-2026 ESX Framework

fx_version 'cerulean'

game 'gta5'
author 'ESX-Framework'
description 'Création d\'identité du personnage : prénom, nom, sexe, taille et date de naissance (JJ/MM/AAAA).'
lua54 'yes'
version '1.16.2-fr'

shared_scripts {
    '@esx_lib/imports.lua',
    '@es_extended/imports.lua',
    '@es_extended/locale.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@esx_lib/imports/catalog/bootstrap.lua',
    'locales/*.lua',
    'config.lua',
    'server/main.lua',
}

client_scripts {
    'locales/*.lua',
    'config.lua',
    'client/main.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

ui_page 'html/index.html'

dependency 'es_extended'
