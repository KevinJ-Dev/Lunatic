fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Novyra Studio'
description 'Loading screen Novyra Studio (ESX)'
version '2.0.0'

loadscreen 'web/index.html'
loadscreen_manual_shutdown 'yes'
loadscreen_cursor 'no'

client_script 'client/main.lua'

files {
    'web/index.html',
    'web/style.css',
    'web/script.js',
    'web/logo.png'
}
