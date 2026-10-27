fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_creator'
author 'Lunatic RP'
description "Création de personnage : identité (remplace esx_identity), héritage, apparence, visage, vêtements, lieu d'apparition, mugshot"
version '0.2.0'

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
}

-- illenium-appearance n'est pas une dépendance déclarée : sinon chaque « ensure illenium-appearance » arrêterait cette
-- resource sans la relancer. Elle doit simplement démarrer avant (dossier [5_Standalone]).

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
    'shared/spawns.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/identity.lua',
    'server/main.lua',
    'server/photos.lua',
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
    'html/thumbs/*',
    'html/clothes/**/*',
}
