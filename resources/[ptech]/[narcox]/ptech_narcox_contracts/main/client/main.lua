local data, receivedAt, busy = nil, 0, false
local peds, route = {}, nil
local showContracts, showContract

local function notify(message, success)
    if message then lib.notify({ title = 'Narcox Contracts', description = message, type = success and 'success' or 'error' }) end
end

local function clearRoute()
    if route then RemoveBlip(route.handle) route = nil end
end

local function update(value)
    if not value then return end
    data, receivedAt = value, GetGameTimer()
    if route then
        local found = false
        for _, c in ipairs(data.active) do if c.id == route.contractId then found = true break end end
        if not found then clearRoute() end
    end
end

local function request(action, value, silent)
    if busy then return nil end
    busy = true
    local ok, result = pcall(lib.callback.await, 'ptech_narcox_contracts:' .. action, false, value)
    busy = false
    if not ok or type(result) ~= 'table' then
        if not silent then notify('サーバーに接続できませんでした', false) end
        return nil
    end
    update(result.state)
    if not silent then notify(result.message, result.ok) end
    return result
end

local function remaining(c)
    local milliseconds = math.max(0, c.remainingMs - math.max(0, GetGameTimer() - receivedAt))
    return ('%d分%02d秒'):format(math.floor(milliseconds / 60000), math.floor(milliseconds / 1000) % 60)
end

showContract = function(id)
    if not data then return end
    local contract
    for _, c in ipairs(data.active) do if c.id == id then contract = c break end end
    if not contract then return end
    local c = contract
    lib.registerContext({
        id = 'narcox_contract_detail', title = c.label .. ' #' .. c.id,
        menu = 'narcox_contracts',
        options = {
            {
                title = ('%s × %d'):format(c.itemLabel, c.quantity),
                description = ('依頼人: %s / 残り: %s / 報酬: $%d（銀行振込）'):format(c.npcLabel, remaining(c), c.reward),
                readOnly = true
            },
            {
                title = '納品先を案内する', disabled = c.status ~= 'active',
                onSelect = function()
                    clearRoute()
                    local blip = AddBlipForCoord(c.target.x, c.target.y, c.target.z)
                    SetBlipSprite(blip, 1)
                    SetBlipColour(blip, 2)
                    SetBlipRoute(blip, true)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString(c.label .. ' 納品先')
                    EndTextCommandSetBlipName(blip)
                    route = { handle = blip, contractId = c.id }
                    notify('納品先をマップに表示しました', true)
                end
            },
            {
                title = '納品する', description = '指定数量を渡し、銀行口座へ即時振込を受けます',
                disabled = c.status ~= 'active',
                onSelect = function() request('deliver', c.id) showContracts() end
            },
            {
                title = 'キャンセルする', description = '期限切れと同じく、この依頼人の好感度が下がります',
                disabled = c.status ~= 'active',
                onSelect = function()
                    local choice = lib.alertDialog({ header = '依頼のキャンセル', content = '好感度が下がります。キャンセルしますか？', cancel = true })
                    if choice == 'confirm' then request('cancel', c.id) showContracts() end
                end
            },
            { title = c.status == 'processing' and '納品記録の確認が必要です。管理者に連絡してください' or (c.legal and '合法の調達依頼' or '依頼内容を確認してください'), readOnly = true }
        }
    })
    lib.showContext('narcox_contract_detail')
end

showContracts = function()
    local options = {}
    if data then
        for _, c in ipairs(data.active) do
            local id = c.id
            options[#options + 1] = {
                title = c.label .. ' #' .. id,
                description = ('%s / %d個 / 残り%s / $%d'):format(c.npcLabel, c.quantity, remaining(c), c.reward),
                onSelect = function() showContract(id) end
            }
        end
        for npcId, favor in pairs(data.favor) do
            options[#options + 1] = { title = ((Config.Npcs[npcId] and Config.Npcs[npcId].label) or npcId) .. ' 好感度: ' .. favor, readOnly = true }
        end
    end
    if #options == 0 then options[1] = { title = '受注中の依頼はありません', readOnly = true } end
    options[#options + 1] = { title = 'マップの案内を消す', onSelect = clearRoute }
    lib.registerContext({ id = 'narcox_contracts', title = '受注中の依頼と好感度', options = options })
    lib.showContext('narcox_contracts')
end

local function npcMenu(npcId)
    local npc = Config.Npcs[npcId]
    lib.registerContext({
        id = 'narcox_contact', title = npc.label,
        options = {
            {
                title = '依頼を受け取る',
                description = '押すとランダムな依頼をそのまま受注します。キャンセル・期限切れは好感度低下。',
                onSelect = function()
                    local result = request('accept', npcId)
                    if result then showContracts() end
                end
            },
            { title = '受注中の依頼と好感度', onSelect = function() request('state') showContracts() end }
        }
    })
    lib.showContext('narcox_contact')
end

RegisterCommand(Config.Command, function()
    local result = request('state')
    if result and result.ok then showContracts() end
end, false)

local function cleanup()
    for id, ped in pairs(peds) do if DoesEntityExist(ped) then DeleteEntity(ped) end peds[id] = nil end
    clearRoute()
    data = nil
    lib.hideContext()
end

RegisterNetEvent('QBCore:Client:OnPlayerUnload', cleanup)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() request('state', nil, true) end)
AddEventHandler('onResourceStop', function(name) if name == GetCurrentResourceName() then cleanup() end end)

CreateThread(function()
    while true do
        if Config.Enabled then request('state', nil, true) end
        Wait(10000)
    end
end)

CreateThread(function()
    if not Config.Enabled then return end
    while true do
        local position, closest, distance = GetEntityCoords(PlayerPedId()), nil, Config.InteractDistance
        for id, npc in pairs(Config.Npcs) do
            local target = vec3(npc.coords.x, npc.coords.y, npc.coords.z)
            local d = #(position - target)
            if data and npc.bucket == data.bucket and d <= Config.RenderDistance then
                if not peds[id] then
                    local model = joaat(npc.model)
                    if IsModelInCdimage(model) and IsModelAPed(model) then
                        local ok = pcall(lib.requestModel, model, 5000)
                        if ok then
                            local ped = CreatePed(4, model, target.x, target.y, target.z - 1.0, npc.coords.w, false, false)
                            if ped ~= 0 then
                                SetEntityInvincible(ped, true)
                                FreezeEntityPosition(ped, true)
                                SetBlockingOfNonTemporaryEvents(ped, true)
                                peds[id] = ped
                            end
                            SetModelAsNoLongerNeeded(model)
                        end
                    end
                end
                if peds[id] and d < distance then closest, distance = id, d end
            elseif peds[id] then
                DeleteEntity(peds[id])
                peds[id] = nil
            end
        end
        if closest then
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ 依頼人に話しかける')
            EndTextCommandDisplayHelp(0, false, true, -1)
            if IsControlJustReleased(0, 38) then npcMenu(closest) end
            Wait(0)
        else Wait(500) end
    end
end)
