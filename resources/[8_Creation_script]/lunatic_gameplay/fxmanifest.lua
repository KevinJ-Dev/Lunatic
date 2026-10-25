fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_gameplay'
author 'Lunatic RP'
description "Systèmes de gameplay réglés dans le panel staff (tuile Fonctionnalités) : mort et respawn, carburant, effets, arme dans le dos, zones sécurisées, anti-AFK, carte d'identité ; récoltes, ascenseurs et objets de soin (tuile Autres)"
version '0.1.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    'server/common.lua',
    'server/death.lua',
    'server/fuel.lua',
    'server/effects.lua',
    'server/misc.lua',
    'server/idcard.lua',
    'server/harvest.lua',
    'server/elevators.lua',
    'server/healitems.lua',
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
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
}
