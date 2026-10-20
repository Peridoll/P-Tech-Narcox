local state, lastAttempt, busy = {}, {}, {}
local itemValidated = false

local function saveState()
    local out = {}
    for areaId, entries in pairs(state) do
        out[areaId] = {}
        for slot, entry in ipairs(entries) do
            out[areaId][slot] = {
                point = entry.point, previousPoint = entry.previousPoint, readyAt = entry.readyAt
            }
        end
    end
    SaveResourceFile(GetCurrentResourceName(), Config.StateFile, json.encode(out), -1)
end

local function choosePoint(area, entries, previousPoint)
    local candidates, preferred = {}, {}
    for index = 1, #area.points do
        local occupied = false
        for _, entry in ipairs(entries) do
            if entry.point == index then occupied = true break end
        end
        if not occupied then
            candidates[#candidates + 1] = index
            if index ~= previousPoint then preferred[#preferred + 1] = index end
        end
    end
    local pool = #preferred > 0 and preferred or candidates
    if #pool == 0 then return nil end
    return pool[math.random(#pool)]
end

local function snapshot()
    local result = {}
    for areaId, entries in pairs(state) do
        result[areaId] = {}
        for slot, entry in ipairs(entries) do
            if entry.point then result[areaId][slot] = entry.point end
        end
    end
    return result
end

local function publish()
    TriggerClientEvent('ptech_narcox_foraging:sync', -1, snapshot())
end

local function initialize()
    local stored = {}
    local saved = LoadResourceFile(GetCurrentResourceName(), Config.StateFile)
    if saved then
        local ok, decoded = pcall(json.decode, saved)
        if ok and type(decoded) == 'table' then stored = decoded end
    end
    local now = os.time()
    for areaId, area in pairs(Config.Areas) do
        local entries = {}
        state[areaId] = entries
        local count = math.min(math.max(0, math.floor(area.maxActive or 0)), #area.points)
        for slot = 1, count do
            local old = stored[areaId] and stored[areaId][slot]
            local entry = {point = nil, previousPoint = nil, readyAt = 0}
            if type(old) == 'table' then
                local p = tonumber(old.point)
                local previous = tonumber(old.previousPoint)
                if previous and previous >= 1 and previous <= #area.points then
                    entry.previousPoint = previous
                end
                entry.readyAt = tonumber(old.readyAt) or 0
                if p and p >= 1 and p <= #area.points and p % 1 == 0 then
                    local occupied = false
                    for _, earlier in ipairs(entries) do
                        if earlier.point == p then occupied = true break end
                    end
                    if not occupied then entry.point = p end
                end
            end
            if not entry.point and entry.readyAt <= now then
                entry.point = choosePoint(area, entries, entry.previousPoint)
                entry.readyAt = 0
            end
            entries[slot] = entry
        end
    end
    saveState()
end

lib.callback.register('ptech_narcox_foraging:getState', function(source)
    return snapshot()
end)

lib.callback.register('ptech_narcox_foraging:harvest', function(source, areaId, slot, expectedPoint)
    local nowMs = GetGameTimer()
    if busy[source] or (lastAttempt[source] and nowMs - lastAttempt[source] < 600) then
        return false, '連続して採取できません'
    end
    lastAttempt[source] = nowMs
    if type(areaId) ~= 'string' or type(slot) ~= 'number' or type(expectedPoint) ~= 'number' then
        return false, '不正な採取地点です'
    end
    local area, entries = Config.Areas[areaId], state[areaId]
    local entry = entries and entries[slot]
    if not area or not entry or not entry.point or entry.point ~= expectedPoint then
        return false, 'すでに採取されています'
    end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false, 'プレイヤーを確認できません' end
    if GetVehiclePedIsIn(ped, false) ~= 0 then return false, '車両から降りてください' end
    local pos = GetEntityCoords(ped)
    local flower = area.points[entry.point]
    if #(pos - flower) > Config.ServerDistance then return false, '花から離れすぎています' end
    if not itemValidated then
        if not exports.ox_inventory:Items(Config.Item) then
            return false, 'アイテム定義が見つかりません。サーバー管理者に連絡してください'
        end
        itemValidated = true
    end
    if not exports.ox_inventory:CanCarryItem(source, Config.Item, Config.ItemCount) then
        return false, '所持品に空きがありません'
    end
    busy[source] = true
    local ok, reason = exports.ox_inventory:AddItem(source, Config.Item, Config.ItemCount)
    if not ok then
        busy[source] = nil
        return false, '取得できませんでした: ' .. tostring(reason)
    end
    entry.previousPoint = entry.point
    entry.point = nil
    entry.readyAt = os.time() + Config.RespawnSeconds
    saveState()
    publish()
    busy[source] = nil
    return true, 'タンポポの花を摘みました'
end)

AddEventHandler('playerDropped', function()
    busy[source] = nil
    lastAttempt[source] = nil
end)

CreateThread(function()
    math.randomseed(os.time())
    initialize()
    while true do
        Wait(10000)
        local changed, now = false, os.time()
        for areaId, entries in pairs(state) do
            local area = Config.Areas[areaId]
            for _, entry in ipairs(entries) do
                if not entry.point and entry.readyAt <= now then
                    entry.point = choosePoint(area, entries, entry.previousPoint)
                    if entry.point then
                        entry.readyAt = 0
                        changed = true
                    end
                end
            end
        end
        if changed then saveState() publish() end
    end
end)
