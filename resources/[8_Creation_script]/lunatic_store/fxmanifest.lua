fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_store'
author 'Lunatic RP'
description 'Boutique des joueurs : abonnements, véhicules, packs et armes contre des crédits (réglée dans la tuile Boutique de lunatic_admin)'
version '1.0.0'

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'lunatic_admin',
}

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
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
