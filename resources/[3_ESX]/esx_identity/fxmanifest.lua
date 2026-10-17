fx_version 'adamant'

game 'gta5'
description 'Création d\'identité du personnage : prénom, nom, sexe, taille et date de naissance (JJ/MM/AAAA).'
lua54 'yes'
version '1.15.2-fr'

shared_scripts {
	'@esx_lib/imports.lua',
	'@es_extended/imports.lua',
	'@es_extended/locale.lua',
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'locales/*.lua',
	'config.lua',
	'server/main.lua'
}

client_scripts {
	'locales/*.lua',
	'config.lua',
	'client/main.lua'
}

files {
	'html/index.html',
	'html/style.css',
	'html/script.js',
}

ui_page 'html/index.html'

dependency 'es_extended'
