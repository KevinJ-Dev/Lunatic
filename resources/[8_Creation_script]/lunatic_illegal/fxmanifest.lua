fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_illegal'
author 'Lunatic RP'
description 'Illégal : crews (menu /crew), puis drogues, territoires, craft d\'armes, missions'
version '0.3.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    'server/common.lua',
    'server/crews.lua',
    'server/fence.lua',
    'server/drugs.lua',
    'server/workshops.lua',
}

client_scripts {
    'client/crews.lua',
    'client/fence.lua',
    'client/drugs.lua',
    'client/territories.lua',
    'client/workshops.lua',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
}

-- lunatic_admin n'est pas une dépendance déclarée : sinon chaque « ensure lunatic_admin » arrêterait cette resource
-- sans la relancer. Ses exports et GlobalState sont lus au moment de servir, et ses événements resynchronisent au redémarrage.
