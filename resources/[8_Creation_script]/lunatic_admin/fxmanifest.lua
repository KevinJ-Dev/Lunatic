fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_admin'
author 'Lunatic RP'
description 'Panel staff Lunatic : rangs, staff, joueurs, sanctions, outils, économie, logs et tableau de bord'
version '0.10.0'

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
    'server/history.lua',
    'server/jail.lua',
    'server/world.lua',
    'server/profile.lua',
    'server/offline.lua',
    'server/premium.lua',
    'server/global.lua',
    'server/poles.lua',
    'server/structures.lua',
    'server/structure_points.lua',
    'server/catalogs.lua',
    'server/shops.lua',
    'server/crews.lua',
    'server/fence.lua',
    'server/drugs.lua',
    'server/territories.lua',
    'server/workshops.lua',
    'server/market.lua',
    'server/events.lua',
    'server/dev.lua',
    'server/commands.lua',
    'server/context.lua',
}

client_scripts {
    'client/main.lua',
    'client/players.lua',
    'client/sanctions.lua',
    'client/tools.lua',
    'client/jail.lua',
    'client/events.lua',
    'client/dev.lua',
    'client/context.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/sanctions.js',
    'web/tools.js',
    'web/economy.js',
    'web/logs.js',
    'web/world.js',
    'web/offline.js',
    'web/premium.js',
    'web/global.js',
    'web/poles.js',
    'web/structures.js',
    'web/structure_catalogs.js',
    'web/shops.js',
    'web/crews.js',
    'web/illegal.js',
    'web/drugs.js',
    'web/territories.js',
    'web/workshops.js',
    'web/market.js',
    'web/events.js',
    'web/dev.js',
    'web/search.js',
    'web/help.js',
    'web/logo.png',
    'web/fonts/*.woff2',
}

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
}
