local resource = GetCurrentResourceName()
local state = { version = 1, nextId = 1, players = {} }
local sessions, attempts = {}, {}
local locked, halted = false, false

local function log(message)
    print(('[%s] %s'):format(resource, message))
end

local function save()
    if halted then return false end
    local ok, written = pcall(function()
        return SaveResourceFile(resource, Config.StateFile, json.encode(state), -1)
    end)
    if not ok or not written then
        halted = true
        log('保存失敗。所持品・振込の再実行を防ぐため、処理を停止しました。保存先を確認してください。')
        return false
    end
    return true
end

local function load()
    Contracts.validate(Config)
    local raw = LoadResourceFile(resource, Config.StateFile)
    if not raw then return end
    -- 壊れた保存を空データで上書きしない。進行中の契約はConfigと独立して検証する。
    local ok, decoded = pcall(function()
        local data = json.decode(raw)
        assert(type(data) == 'table' and data.version == 1 and type(data.players) == 'table')
        assert(type(data.nextId) == 'number' and data.nextId >= 1 and data.nextId % 1 == 0)
        local ids = {}
        for citizenid, player in pairs(data.players) do
            assert(type(citizenid) == 'string' and type(player) == 'table')
            assert(type(player.favor) == 'table' and type(player.active) == 'table')
            for npcId, favor in pairs(player.favor) do
                assert(type(npcId) == 'string' and type(favor) == 'number' and favor % 1 == 0)
            end
            for id, c in pairs(player.active) do
                assert(type(id) == 'string' and c.id == id and not ids[id])
                local number = tonumber(id)
                assert(number and number >= 1 and number < data.nextId and number % 1 == 0)
                ids[id] = true
                for _, key in ipairs({ 'npcId', 'npcLabel', 'jobId', 'label', 'item', 'itemLabel' }) do
                    assert(type(c[key]) == 'string')
                end
                for _, key in ipairs({ 'quantity', 'reward', 'successFavor', 'failureFavor', 'remainingMs' }) do
                    assert(type(c[key]) == 'number' and c[key] >= 0 and c[key] < math.huge and c[key] % 1 == 0)
                end
                assert(c.quantity >= 1 and c.reward >= 1)
                assert(type(c.target) == 'table')
                for _, key in ipairs({ 'x', 'y', 'z', 'bucket' }) do
                    local n = c.target[key]
                    assert(type(n) == 'number' and n == n and math.abs(n) < math.huge)
                end
                assert(c.target.bucket >= 0 and c.target.bucket % 1 == 0)
                assert(c.status == 'active' or c.status == 'processing')
                if c.status == 'processing' then
                    log(('未確定の納品を検出: citizenid=%s contract=%s。自動再実行せず要確認。'):format(citizenid, id))
                end
            end
        end
        return data
    end)
    if not ok then
        halted = true
        log('保存データが不正です。上書きせず停止しました: ' .. tostring(decoded))
        return
    end
    state = decoded
end

local initialized, initError = pcall(load)
if not initialized then halted = true log('設定または読込に失敗: ' .. tostring(initError)) end

local function identity(source)
    local player = exports.qbx_core:GetPlayer(source)
    local citizenid = player and player.PlayerData and player.PlayerData.citizenid
    return type(citizenid) == 'string' and citizenid or nil
end

local function playerState(citizenid)
    if not state.players[citizenid] then
        state.players[citizenid] = { favor = {}, active = {} }
    end
    return state.players[citizenid]
end

local function elapsed(now, previous)
    local value = now - previous
    if value < 0 then value = value + 4294967296.0 end -- GetGameTimerの周回
    return value
end

local function tickSession(source, now)
    local session = sessions[source]
    if not session then return false end
    local player = state.players[session.citizenid]
    local finishAt = session.ending or now
    local delta = elapsed(finishAt, session.last)
    session.last = finishAt
    local changed = player and Contracts.count(player) > 0 and delta > 0
    if player and changed and Config.Enabled then
        local failures = Contracts.advance(player, delta)
        if failures > 0 and not session.ending then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'Narcox Contracts', type = 'error',
                description = ('%d件の依頼が期限切れになり、依頼人の好感度が下がりました'):format(failures)
            })
        end
    end
    if session.ending then sessions[source] = nil end
    return changed
end

local function watch(source, citizenid)
    local now = GetGameTimer()
    local old = sessions[source]
    if old and (old.citizenid ~= citizenid or old.ending) then
        -- 通常はUnloadイベントで時刻を確定。取り逃した切替は課金せず停止する。
        if old.ending then tickSession(source, now) end
        sessions[source] = nil
    elseif old then
        tickSession(source, now)
    end
    if not sessions[source] then sessions[source] = { citizenid = citizenid, last = now } end
end

local function near(source, target)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or GetPlayerRoutingBucket(source) ~= target.bucket then return false end
    local pos = GetEntityCoords(ped)
    local dx, dy, dz = pos.x - target.x, pos.y - target.y, pos.z - target.z
    return dx * dx + dy * dy + dz * dz <= Config.ServerDistance * Config.ServerDistance
end

local function snapshot(player)
    local active = {}
    for _, c in pairs(player.active) do
        active[#active + 1] = {
            id = c.id, npcId = c.npcId, npcLabel = c.npcLabel, label = c.label,
            itemLabel = c.itemLabel, quantity = c.quantity, reward = c.reward,
            remainingMs = c.remainingMs, target = c.target, status = c.status, legal = c.legal
        }
    end
    table.sort(active, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
    return { active = active, favor = player.favor, enabled = Config.Enabled, halted = halted }
end

local function response(ok, message, player)
    return { ok = ok, message = message, state = player and snapshot(player) or nil }
end

local function accept(source, player, npcId)
    if type(npcId) ~= 'string' then return false, '依頼人が不正です' end
    local npc = Config.Npcs[npcId]
    if not npc or not near(source, { x = npc.coords.x, y = npc.coords.y, z = npc.coords.z, bucket = npc.bucket }) then
        return false, '依頼人の近くで操作してください'
    end
    if Config.MaxActive > 0 and Contracts.count(player) >= Config.MaxActive then
        return false, '同時受注数の上限に達しています'
    end
    local id = tostring(state.nextId)
    local contract = Contracts.generate(Config, player, npcId, id)
    if not contract then return false, '今の好感度で受けられる依頼がありません' end
    if not exports.ox_inventory:Items(contract.item) then return false, '依頼品のアイテム定義がありません' end
    state.nextId = state.nextId + 1
    player.active[id] = contract
    if not save() then return false, '保存できませんでした。管理者に連絡してください' end
    return true, ('%sを受注しました'):format(contract.label)
end

local function cancel(player, contract)
    Contracts.finish(player, contract, false)
    if not save() then return false, '保存できませんでした。管理者に連絡してください' end
    return true, '依頼をキャンセルしました。期限切れと同じ好感度低下が適用されました'
end

local function deliver(source, citizenid, player, contract)
    if not near(source, contract.target) then return false, '納品場所の近くで操作してください' end
    -- スロットとメタデータを保存してから減らす。振込拒否時は同じ品を返す。
    local slots = exports.ox_inventory:Search(source, 'slots', contract.item) or {}
    local transfer, needed = {}, contract.quantity
    for _, slot in pairs(slots) do
        local count = math.min(needed, slot.count)
        if count > 0 then
            transfer[#transfer + 1] = {
                slot = slot.slot, count = count,
                metadata = json.decode(json.encode(slot.metadata or {})), removed = false
            }
            needed = needed - count
        end
        if needed == 0 then break end
    end
    if needed > 0 then return false, '依頼品が不足しています' end
    contract.status, contract.transfer, contract.payment = 'processing', transfer, 'not_attempted'
    if not save() then return false, '納品の準備を保存できませんでした' end

    local function rollback()
        -- 再接続などでsourceが別キャラクターになっていれば触らず、記録を残す。
        if identity(source) ~= citizenid then return false end
        for _, part in ipairs(transfer) do
            if part.removed and not part.restored then
                if not exports.ox_inventory:CanCarryItem(source, contract.item, part.count, part.metadata) then return false end
                local restored = exports.ox_inventory:AddItem(source, contract.item, part.count, part.metadata)
                if not restored then return false end
                part.restored = true
                if not save() then return false end
            end
        end
        contract.status, contract.transfer, contract.payment = 'active', nil, nil
        return save()
    end

    for _, part in ipairs(transfer) do
        if identity(source) ~= citizenid then return false, '接続状態が変わりました。管理者に連絡してください' end
        local removed = exports.ox_inventory:RemoveItem(source, contract.item, part.count, part.metadata, part.slot, false, true)
        if not removed then
            local restored = rollback()
            return false, restored and '所持品が変わったため納品を中止しました' or '納品の復旧が必要です。管理者に連絡してください'
        end
        part.removed = true
        if not save() then return false, '納品の記録保存に失敗しました。管理者に連絡してください' end
    end
    if identity(source) ~= citizenid then return false, '接続状態が変わりました。管理者に連絡してください' end
    contract.payment = 'attempting'
    if not save() then return false, '振込前の記録保存に失敗しました。管理者に連絡してください' end
    local paid = exports.qbx_core:AddMoney(source, 'bank', contract.reward, Config.PaymentReason .. ':' .. contract.id)
    if not paid then
        contract.payment = 'rejected'
        local restored = rollback()
        return false, restored and '振込できなかったため依頼品を返しました' or '振込・返却の確認が必要です。管理者に連絡してください'
    end
    contract.payment = 'paid'
    -- 外部APIとJSONの完全な原子性はない。支払い後の保存失敗時も再支払いしない。
    if not save() then return false, '振込済みですが保存に失敗しました。管理者に連絡してください' end
    Contracts.finish(player, contract, true)
    if not save() then return false, '振込済みですが完了保存に失敗しました。管理者に連絡してください' end
    return true, ('$%dを銀行口座へ振り込みました'):format(contract.reward)
end

local function handle(source, action, value)
    if halted then return response(false, '保存状態を確認中です。管理者に連絡してください') end
    if locked then return response(false, '処理中です。少し待ってください') end
    local now = GetGameTimer()
    local lane = action == 'state' and 'read' or 'write'
    attempts[source] = attempts[source] or {}
    if attempts[source][lane] and elapsed(now, attempts[source][lane]) < Config.ActionIntervalMs then
        return response(false, '少し待ってから操作してください')
    end
    attempts[source][lane] = now
    locked = true
    local ok, result = xpcall(function()
        local citizenid = identity(source)
        if not citizenid then return response(false, 'キャラクターを確認できません') end
        local player = playerState(citizenid)
        watch(source, citizenid)
        if action == 'state' then return response(true, nil, player) end
        if not Config.Enabled then return response(false, 'Contractsは導入設定の確認待ちです', player) end
        local success, message
        if action == 'accept' then
            success, message = accept(source, player, value)
        else
            local c = type(value) == 'string' and player.active[value]
            if not c then return response(false, 'その依頼は終了したか、存在しません', player) end
            if c.status ~= 'active' then return response(false, '納品記録の確認が必要です。管理者に連絡してください', player) end
            if action == 'cancel' then success, message = cancel(player, c)
            elseif action == 'deliver' then success, message = deliver(source, citizenid, player, c)
            else return response(false, '不正な操作です', player) end
        end
        return response(success, message, player)
    end, debug.traceback)
    locked = false
    if not ok then
        halted = true
        log('予期しないエラー。二重処理を防ぐため停止しました: ' .. tostring(result))
        return response(false, '処理を停止しました。管理者に連絡してください')
    end
    if result.state then result.state.bucket = GetPlayerRoutingBucket(source) end
    return result
end

for _, action in ipairs({ 'state', 'accept', 'cancel', 'deliver' }) do
    lib.callback.register('ptech_narcox_contracts:' .. action, function(source, value)
        return handle(source, action, value)
    end)
end

local function endSession(source)
    if sessions[source] then sessions[source].ending = GetGameTimer() end
    attempts[source] = nil
    if not locked and not halted then
        if tickSession(source, GetGameTimer()) then save() end
    end
end

AddEventHandler('playerDropped', function() endSession(source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(playerId) endSession(playerId) end)
-- 重複通知でも残り時間をリセットしない。本人・現在のキャラクターは毎回Coreで確認。
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    if locked or halted then return end
    local citizenid = identity(source)
    if citizenid then watch(source, citizenid) end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resource or halted then return end
    if locked then log('処理中に停止しました。保存済みのprocessing契約を確認してください。') return end
    for playerId in pairs(sessions) do tickSession(playerId, GetGameTimer()) end
    save()
end)

CreateThread(function()
    local lastSave = GetGameTimer()
    while true do
        Wait(1000)
        if not locked and not halted then
            local now, changed = GetGameTimer(), false
            for _, value in ipairs(GetPlayers()) do
                local playerId = tonumber(value)
                local citizenid = identity(playerId)
                if citizenid and not sessions[playerId] then
                    sessions[playerId] = { citizenid = citizenid, last = now }
                end
            end
            for playerId, session in pairs(sessions) do
                if session.ending or identity(playerId) == session.citizenid then
                    if tickSession(playerId, now) then changed = true end
                else
                    sessions[playerId] = nil
                end
            end
            if elapsed(now, lastSave) >= Config.StateSaveIntervalMs then
                -- 定期保存は残り時間のチェックポイント。停止中・オフラインには進めない。
                if changed or next(state.players) then save() end
                lastSave = now
            end
        end
    end
end)
