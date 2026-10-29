fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_context'
author 'Lunatic RP'
description "Menu contextuel (doc Vision) : Alt gauche maintenu + clic droit sur un personnage, un véhicule, un objet ou le sol ; les autres scripts y ajoutent leurs entrées (exports.lunatic_context:register)"
version '0.1.0'

client_script 'client/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/fonts/*.woff2',
}
