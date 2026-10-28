fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_garage'
author 'Lunatic RP'
description "Garage public et fourrière : véhicules des joueurs rangés, sortis et récupérés aux emplacements de la tuile Catalogues (lunatic_admin)"
version '0.1.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_script 'client/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/fonts/*.woff2',
}

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
}

-- lunatic_admin et lunatic_business ne sont pas des dépendances déclarées : sinon chaque « ensure » de l'un d'eux
-- arrêterait cette resource sans la relancer. Les emplacements sont lus dans GlobalState.lunaticShops au moment de servir.
