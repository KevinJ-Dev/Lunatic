fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_characters'
author 'Lunatic RP'
description "Sélection de personnage : plusieurs personnages par compte (ESX en mode multi-personnages), emplacements selon l'abonnement"
version '0.1.0'

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
}

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/migration.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/logo.png',
    'html/fonts/*.woff2',
}
