fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_bank'
author 'Lunatic RP'
description "Banque : numéro de compte (IBAN LN), historique des transactions, analyse, retrait, dépôt et virement au guichet des agences"
version '0.1.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
    'shared/banks.lua',
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

-- lunatic_admin n'est pas une dépendance déclarée : ses exports (logs) et GlobalState (agences) sont lus au moment de servir.
