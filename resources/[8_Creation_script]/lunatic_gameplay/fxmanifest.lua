fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_gameplay'
author 'Lunatic RP'
description "Systèmes de gameplay réglés dans le panel staff (tuile Fonctionnalités) : mort et respawn, carburant, effets, arme dans le dos, zones sécurisées, anti-AFK, carte d'identité, menu véhicule et actions RP (lunatic_context) ; récoltes, ascenseurs, objets de soin et zone AFK (tuile Autres)"
version '0.1.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
    'shared/documents.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/common.lua',
    'server/death.lua',
    'server/fuel.lua',
    'server/effects.lua',
    'server/misc.lua',
    'server/idcard.lua',
    'server/harvest.lua',
    'server/elevators.lua',
    'server/healitems.lua',
    'server/afkzone.lua',
    'server/contextmenu.lua',
}

client_scripts {
    'client/common.lua',
    'client/death.lua',
    'client/fuel.lua',
    'client/effects.lua',
    'client/misc.lua',
    'client/idcard.lua',
    'client/harvest.lua',
    'client/elevators.lua',
    'client/healitems.lua',
    'client/afkzone.lua',
    'client/vehiclemenu.lua',
    'client/contextmenu.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/fuel.js',
    'html/fonts/*.woff2',
}

dependencies {
    'es_extended',
    'oxmysql',
    'ox_lib',
    'ox_inventory',
}
