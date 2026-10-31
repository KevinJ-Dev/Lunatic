fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_interim'
author 'Lunatic RP'
description "Job Center et métiers d'intérim (doc Vision « Jobs de farm ») : fiche des métiers, tenue de travail, accepter / quitter ; missions payées à la mission"
version '0.1.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
    'shared/centers.lua',
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
    'illenium-appearance',
}

-- lunatic_admin n'est pas une dépendance déclarée : ses exports (logs, permissions) et GlobalState (Job Centers, images)
-- sont lus au moment de servir.
