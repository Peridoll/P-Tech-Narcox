-- Lua 5.3+。FiveM/Qbox/ox_inventoryは下記スタブ。実機検証の代替ではない。
local function clone(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = clone(v) end
    return out
end
local count = 0
local function check(value, message)
    assert(value, message)
    count = count + 1
end
local root = 'resources/[ptech]/[narcox]/ptech_narcox_contracts/'
for _, file in ipairs({ 'fxmanifest.lua', 'config/config.lua', 'main/shared/contracts.lua', 'main/server/main.lua', 'main/client/main.lua' }) do
    check(loadfile(root .. file) ~= nil, 'Lua syntax: ' .. file)
end
dofile(root .. 'config/config.lua')
dofile(root .. 'main/shared/contracts.lua')
local baseline = clone(Config)
check(Contracts.validate(Config), 'sample config')
local p = { favor = {}, active = {} }
local cfg = clone(Config)
cfg.Jobs.advanced = clone(cfg.Jobs.dandelion)
cfg.Jobs.advanced.minFavor = 2
cfg.Npcs.flower_contact.jobs[2] = 'advanced'
check(#Contracts.candidates(cfg, p, 'flower_contact') == 1, 'locked tier excluded')
p.favor.flower_contact = 2
check(#Contracts.candidates(cfg, p, 'flower_contact') == 2, 'tier opens at threshold')
p.favor.someone_else = 999
p.favor.flower_contact = 0
check(#Contracts.candidates(cfg, p, 'flower_contact') == 1, 'favor isolated by NPC')
cfg.Jobs.dandelion.delivery = 'point'
cfg.Jobs.dandelion.points = { { x = 1, y = 2, z = 3, bucket = 4 }, { x = 5, y = 6, z = 7, bucket = 8 } }
check(Contracts.validate(cfg), 'random point config')
local generated = Contracts.generate(cfg, p, 'flower_contact', '1', function(a, b) return b end)
check(generated.target.x == 5 and generated.target.bucket == 8, 'random point and bucket selected together')
check(generated.quantity == cfg.Jobs.dandelion.quantity.max, 'random quantity bounded')
check(generated.reward == math.floor(generated.quantity * cfg.Jobs.dandelion.unitReward * cfg.Jobs.dandelion.rewardPercent.max / 100), 'quantity and random reward')
check(generated.remainingMs == cfg.Jobs.dandelion.durationSeconds.max * 1000, 'random time budget')
local invalid = clone(cfg)
invalid.Jobs.dandelion.durationSeconds.min = -1
check(not pcall(Contracts.validate, invalid), 'invalid config rejected')

local time, saved, failSaveAt, saveCalls, bankMode, removeCalls, failRemoveAt
local callbacks, events, threads, people, inventories, bank, locations, buckets, documents
local function boot(recover)
    Config = clone(baseline)
    Config.Enabled, Config.ActionIntervalMs = true, 1
    Config.Jobs.dandelion.quantity = { min = 2, max = 2 }
    Config.Jobs.dandelion.durationSeconds = { min = 30, max = 30 }
    Config.Jobs.dandelion.unitReward = 10
    Config.Jobs.dandelion.rewardPercent = { min = 100, max = 100 }
    time, saveCalls, removeCalls = 0, 0, 0
    failSaveAt, bankMode, failRemoveAt = nil, 'ok', nil
    callbacks, events, threads = {}, {}, {}
    if not recover then
        saved, documents = nil, {}
        people = { [1] = 'alice', [2] = 'bob' }
        inventories = {
            [1] = { [1] = { slot = 1, name = 'narcox_dandelion_flower', count = 20, metadata = { quality = 7 } } },
            [2] = { [1] = { slot = 1, name = 'narcox_dandelion_flower', count = 20, metadata = {} } }
        }
        bank, locations, buckets = {}, {}, { [1] = 0, [2] = 0 }
        locations[1], locations[2] = clone(Config.Npcs.flower_contact.coords), clone(Config.Npcs.flower_contact.coords)
    end
    json = {
        encode = function(value)
            local token = tostring(#documents + 1)
            documents[#documents + 1] = clone(value)
            return token
        end,
        decode = function(token) return clone(documents[tonumber(token)]) end
    }
    function GetCurrentResourceName() return 'ptech_narcox_contracts' end
    function LoadResourceFile() return saved end
    function SaveResourceFile(_, _, content)
        saveCalls = saveCalls + 1
        if saveCalls == failSaveAt then return false end
        saved = content
        return true
    end
    function GetGameTimer() return time end
    function GetPlayerPed(id) return people[id] and id or 0 end
    function GetEntityCoords(id) return locations[id] end
    function GetPlayerRoutingBucket(id) return buckets[id] end
    function TriggerClientEvent() end
    function GetPlayers()
        local result = {}
        for id in pairs(people) do result[#result + 1] = tostring(id) end
        return result
    end
    function AddEventHandler(name, callback) events[name] = callback end
    function RegisterNetEvent(name, callback) events[name] = callback end
    function CreateThread(callback) threads[#threads + 1] = coroutine.create(callback) end
    function Wait() coroutine.yield() end
    lib = { callback = { register = function(name, callback) callbacks[name] = callback end } }
    exports = {
        qbx_core = {
            GetPlayer = function(_, id) return people[id] and { PlayerData = { citizenid = people[id] } } end,
            AddMoney = function(_, id, account, amount)
                assert(account == 'bank', 'must use bank, not cash')
                if bankMode == 'reject' then return false end
                bank[people[id]] = (bank[people[id]] or 0) + amount
                if bankMode == 'throw_after_payment' then error('simulated uncertain bank result') end
                if bankMode == 'reenter' then
                    local result = callbacks['ptech_narcox_contracts:deliver'](id, '1')
                    check(not result.ok, 'reentrant payment blocked')
                end
                return true
            end
        },
        ox_inventory = {
            Items = function() return true end,
            CanCarryItem = function() return true end,
            Search = function(_, id, mode, item)
                assert(mode == 'slots')
                local result = {}
                for _, slot in pairs(inventories[id]) do
                    if slot.name == item then result[#result + 1] = clone(slot) end
                end
                return result
            end,
            RemoveItem = function(_, id, item, amount, metadata, slotId)
                removeCalls = removeCalls + 1
                if removeCalls == failRemoveAt then return false end
                local slot = inventories[id][slotId]
                if not slot or slot.name ~= item or slot.count < amount then return false end
                slot.count = slot.count - amount
                return true
            end,
            AddItem = function(_, id, item, amount, metadata)
                local nextSlot = 1
                while inventories[id][nextSlot] do nextSlot = nextSlot + 1 end
                inventories[id][nextSlot] = { slot = nextSlot, name = item, count = amount, metadata = clone(metadata) }
                return true
            end
        }
    }
    dofile(root .. 'main/server/main.lua')
    for _, thread in ipairs(threads) do assert(coroutine.resume(thread)) end
end

local function call(action, player, value)
    time = time + 2
    return callbacks['ptech_narcox_contracts:' .. action](player or 1, value)
end
local function accept(id) return call('accept', id or 1, 'flower_contact') end
local function items(id)
    local total = 0
    for _, slot in pairs(inventories[id or 1]) do total = total + slot.count end
    return total
end
local function poll(milliseconds)
    time = time + milliseconds
    for _, thread in ipairs(threads) do assert(coroutine.resume(thread)) end
end

boot()
check(accept().ok and accept().ok, 'multiple contracts from same NPC')
check(#call('state').state.active == 2, 'two independent contracts')
check(not call('deliver', 2, '1').ok, 'another owner cannot deliver')
check(not call('cancel', 2, '1').ok, 'another owner cannot cancel')
locations[1].x = 10000
check(not call('deliver', 1, '1').ok and not accept().ok, 'server distance check')
locations[1] = clone(Config.Npcs.flower_contact.coords)
buckets[1] = 5
check(not call('deliver', 1, '1').ok and not accept().ok, 'server bucket check')
buckets[1] = 0
check(not call('deliver', 1, {}).ok and not call('accept', 1, {}).ok, 'malformed identifiers rejected')
bankMode = 'reenter'
check(call('deliver', 1, '1').ok, 'deliver existing stock')
check(items() == 18 and bank.alice == 20, 'consume exact quantity and bank payout')
check(not call('deliver', 1, '1').ok and bank.alice == 20, 'repeat delivery never pays twice')
check(call('cancel', 1, '2').ok and call('state').state.favor.flower_contact == 0, 'success +1 and cancellation -1')
check(not call('cancel', 1, '2').ok and call('state').state.favor.flower_contact == 0, 'cancel penalty only once')

boot()
accept()
poll(31000)
check(#call('state').state.active == 0 and call('state').state.favor.flower_contact == -1, 'online expiry fails')
poll(31000)
check(call('state').state.favor.flower_contact == -1, 'expiry penalty only once')

boot()
accept()
poll(5000)
source = 1
events['playerDropped']()
people[1] = nil
poll(100000)
people[1] = 'alice'
local paused = call('state').state.active[1].remainingMs
check(paused > 24000 and paused <= 25000, 'logout pauses remaining time')
events.onResourceStop('ptech_narcox_contracts')
boot(true)
poll(100000)
local resumed = call('state').state.active[1].remainingMs
check(math.abs(resumed - paused) <= 5, 'server restart pauses remaining time')

boot()
accept()
bankMode = 'reject'
check(not call('deliver', 1, '1').ok and items() == 20 and not bank.alice, 'rejected payout restores items')
local metadataRestored = false
for slotId, slot in pairs(inventories[1]) do
    if slotId ~= 1 and slot.metadata.quality == 7 then metadataRestored = true end
end
check(metadataRestored and call('state').state.active[1].status == 'active', 'metadata restored and contract retryable')

boot()
inventories[1][1].count = 1
inventories[1][2] = { slot = 2, name = 'narcox_dandelion_flower', count = 1, metadata = { quality = 9 } }
accept()
failRemoveAt = 2
check(not call('deliver', 1, '1').ok and items() == 2 and not bank.alice, 'partial removal restored without payout')

boot()
accept()
inventories[1][1].count = 1
check(not call('deliver', 1, '1').ok and items() == 1 and not bank.alice, 'insufficient items do not pay')

boot()
accept()
failSaveAt = saveCalls + 1
check(not call('deliver', 1, '1').ok and items() == 20 and not bank.alice, 'intent save failure prevents inventory mutation')

boot()
accept()
failSaveAt = saveCalls + 5 -- prepared, removed, attempting, paid, final
check(not call('deliver', 1, '1').ok and bank.alice == 20, 'final save failure after bank payout')
boot(true)
check(not call('deliver', 1, '1').ok and bank.alice == 20, 'restart never replays recorded payout')

boot()
accept()
bankMode = 'throw_after_payment'
check(not call('deliver', 1, '1').ok and bank.alice == 20, 'uncertain bank outcome stops processing')
boot(true)
check(not call('deliver', 1, '1').ok and bank.alice == 20, 'uncertain payout is not automatically retried')

boot()
accept()
Config.Enabled = false
check(not accept().ok, 'disabled demo never accepts')
poll(40000)
check(#call('state').state.active == 1, 'disabled resource pauses active contracts')
saved = 'not valid data'
boot(true)
check(not accept().ok, 'corrupt persistence fails closed')

-- クライアントのメニューと案内の寿命だけをスタブで確認。描画は実機で確認する。
boot()
accept()
local contexts, commands, removedBlips = {}, {}, 0
lib.callback.await = function(name, _, value)
    time = time + 2
    return callbacks[name](1, value)
end
lib.notify = function() end
lib.registerContext = function(context) contexts[context.id] = context end
lib.showContext = function() end
lib.hideContext = function() end
lib.alertDialog = function() return 'confirm' end
function RegisterCommand(name, callback) commands[name] = callback end
function AddBlipForCoord() return 42 end
function SetBlipSprite() end
function SetBlipColour() end
function SetBlipRoute() end
function BeginTextCommandSetBlipName() end
function AddTextComponentString() end
function EndTextCommandSetBlipName() end
function RemoveBlip(handle)
    assert(type(handle) == 'number', 'must pass numeric handle')
    removedBlips = removedBlips + 1
end
dofile(root .. 'main/client/main.lua')
commands[Config.Command]()
check(contexts.narcox_contracts.options[1].title:find('#1', 1, true), 'client contract list')
contexts.narcox_contracts.options[1].onSelect()
check(contexts.narcox_contract_detail.options[1].title:find('2', 1, true), 'client detail quantity')
contexts.narcox_contract_detail.options[2].onSelect()
call('cancel', 1, '1')
commands[Config.Command]()
check(removedBlips == 1, 'finished contract removes route with correct blip handle')

print(('Contracts: %d assertions passed (mocked APIs; FiveM unverified)'):format(count))
