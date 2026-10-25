fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_driving'
author 'Lunatic RP'
description "Auto-école : code de la route et examens pratiques (réglés dans la tuile Autres de lunatic_admin)"
version '1.0.0'

dependencies {
    'es_extended',
    'oxmysql',
    'ox_lib',
}

-- lunatic_admin n'est pas une dépendance déclarée : sinon chaque « ensure lunatic_admin » arrêterait cette resource

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
