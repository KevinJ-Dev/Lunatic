fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'novyra_spawn'
author 'Novyra Studio'
description 'Écran d\'entrée en ville cinématique pour ESX'
version '1.0.0'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/script.js',
    'ui/img/*',
    'ui/fonts/*',
}

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

dependency 'es_extended'
