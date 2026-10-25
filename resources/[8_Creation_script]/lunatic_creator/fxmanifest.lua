fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_creator'
author 'Lunatic RP'
description "Création de personnage : identité, héritage, apparence, visage (puis vêtements, lieu d'apparition, mugshot)"
version '0.1.0'

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
    'illenium-appearance',
}

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
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
}
