fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_business'
author 'Lunatic RP'
description "Entreprises et services publics en jeu : points d'interaction, coffres, gestion, compte de société, vestiaire"
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

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'lunatic_admin',
}
