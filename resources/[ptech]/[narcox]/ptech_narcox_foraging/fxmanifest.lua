fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'P-Tech'
description 'Narcox wild dandelion foraging MVP'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua'
}
client_scripts { 'main/client/main.lua' }
server_scripts { 'main/server/main.lua', 'main/server/admire.lua' }
dependencies { 'ox_lib', 'ox_inventory', 'qbx_core' }
