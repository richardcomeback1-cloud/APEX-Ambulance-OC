fx_version 'adamant'
game 'gta5'
lua54 'yes'

shared_scripts {
    '@es_extended/imports.lua',
    '@ox_lib/init.lua',
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'@es_extended/locale.lua',
	'locales/th.lua',
	'config/config.lua',
	'config/config-item.lua',
	'config/config-billing.lua',
	'config/zones.lua',
	'server/main.lua',
}

client_scripts {
	'@es_extended/locale.lua',
	'locales/th.lua',
	'config/config.lua',
	'config/config-item.lua',
	'config/config-billing.lua',
	'config/zones.lua',
	'client/cam.lua',
	'client/main.lua',
	'client/job.lua',
}

dependencies {
	'es_extended',
    'ox_lib',
    'oxmysql',
    'APEX-Billing',
    'APEX-AllNotify',
    'APEX-BossAction',
}

ui_page "html/index.html"

files {
	'html/index.html',
	'html/js/script.js',
	'html/css/style.css',
	'html/js/iconify-icon.min.js',
    'html/js/materialize.min.js',
	'html/img/*.png',
	'html/*.ttf'
}
