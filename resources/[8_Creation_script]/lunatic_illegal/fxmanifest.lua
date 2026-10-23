fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_illegal'
author 'Lunatic RP'
description 'Illégal : crews, recelleur, drogues, territoires, craft d\'armes, tablette et marché noir'
version '0.9.0'

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
    'server/tablet.lua',
    'server/contracts.lua',
    'server/heists.lua',
    'server/holdups.lua',
    'server/street.lua',
    'server/atm.lua',
}

client_scripts {
    'client/crews.lua',
    'client/fence.lua',
    'client/drugs.lua',
    'client/territories.lua',
    'client/workshops.lua',
    'client/tablet.lua',
    'client/contracts.lua',
    'client/heists.lua',
    'client/holdups.lua',
    'client/street.lua',
    'client/atm.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
}

-- lunatic_admin n'est pas une dépendance déclarée : sinon chaque « ensure lunatic_admin » arrêterait cette resource
-- sans la relancer. Ses exports et GlobalState sont lus au moment de servir, et ses événements resynchronisent au redémarrage.
