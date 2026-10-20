fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_chat'
author 'Lunatic RP'
description 'Tchat Lunatic : HRP local, /me et /do en texte 3D, outils staff'
version '0.3.0'

-- Remplace la resource "chat" de FiveM : ESX, ox_lib et les autres scripts y envoient leurs messages
provide 'chat'

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/text3d.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/fonts/*.woff2',
}

dependencies {
    'oxmysql',
}

-- lunatic_admin n'est pas une dépendance déclarée : sinon chaque « ensure lunatic_admin » arrêterait cette resource
-- sans la relancer. Ses exports et GlobalState sont lus au moment de servir, et ses événements resynchronisent au redémarrage.
