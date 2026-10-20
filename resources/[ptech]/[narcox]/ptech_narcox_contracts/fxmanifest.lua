fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'P-Tech'
description 'Narcox NPC procurement contracts'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'main/shared/contracts.lua'
}
server_scripts { 'main/server/main.lua' }
client_scripts { 'main/client/main.lua' }
dependencies { '/onesync', 'ox_lib', 'ox_inventory', 'qbx_core' }
