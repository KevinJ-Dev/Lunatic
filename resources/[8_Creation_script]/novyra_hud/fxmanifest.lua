fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'novyra_hud'
author 'NightCraft Studio'
description 'HUD statuts minimaliste (vie, armure, faim, soif, endurance, oxygene) pour ESX'
version '1.3.1'

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

dependencies {
    'es_extended',
}
