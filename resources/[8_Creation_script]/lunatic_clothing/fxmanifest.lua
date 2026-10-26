fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_clothing'
author 'Lunatic RP'
description "Magasins de vêtements (Binco, Suburban, Ponsonbys…) : catalogue avec images, essayage en direct, panier payé en liquide ou par carte. Magasins et prix réglés dans le panel (Autres → Magasins de vêtements)"
version '1.0.0'

dependencies {
    'es_extended',
    'oxmysql',
    'ox_lib',
    'illenium-appearance',
}

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
    'shared/stores.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
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
    'html/fonts/*.woff2',
}
