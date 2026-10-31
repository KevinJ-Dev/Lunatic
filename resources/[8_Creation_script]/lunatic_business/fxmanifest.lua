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

-- Interface des agences de location (aperçu 3D, durée, paiement) et des magasins d'articles (catalogue, panier)
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/store.js',
    'html/wardrobe.js',
    'html/garage.js',
    'html/craft.js',
    'html/fonts/*.woff2',
}

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
}

-- lunatic_admin n'est pas une dépendance déclarée : sinon chaque « ensure lunatic_admin » arrêterait cette resource
-- sans la relancer. Ses exports et GlobalState sont lus au moment de servir, et ses événements resynchronisent au redémarrage.
