fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_admin'
author 'Lunatic RP'
description 'Panel staff : rangs, permissions, staff, joueurs, sanctions, outils et économie'
version '0.5.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
    'shared/permissions.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/db.lua',
    'server/logs.lua',
    'server/ranks.lua',
    'server/staff.lua',
    'server/main.lua',
    'server/players.lua',
    'server/sanctions.lua',
    'server/tools.lua',
    'server/economy.lua',
}

client_scripts {
    'client/main.lua',
    'client/players.lua',
    'client/sanctions.lua',
    'client/tools.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/sanctions.js',
    'web/tools.js',
    'web/economy.js',
    'web/logo.png',
    'web/fonts/*.woff2',
}

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
}
