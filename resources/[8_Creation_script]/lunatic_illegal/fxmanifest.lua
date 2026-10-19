fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lunatic_illegal'
author 'Lunatic RP'
description 'Illégal : crews (menu /crew), puis drogues, territoires, craft d\'armes, missions'
version '0.1.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
    'config.lua',
}

server_script 'server/crews.lua'
client_script 'client/crews.lua'

dependencies {
    'es_extended',
    'ox_lib',
    'lunatic_admin',
}
