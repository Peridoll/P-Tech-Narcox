-- ox_inventoryのserver.exportを使うため、使用と消費の成否はインベントリ側が検証する。
-- ストレス変更はサーバーのみ。クライアントから回復量を指定できない。
local active = {}

exports('admireFlower', function(event, item, inventory, slot, data)
    if not item or item.name ~= Config.Item or not inventory then return end
    local playerId = inventory.id
    if type(playerId) ~= 'number' then return end

    if event == 'usingItem' then
        -- 効果中の連続使用は消費前に拒否して、回復の重複を防ぐ。
        if active[playerId] then
            TriggerClientEvent('ox_lib:notify', playerId, {
                title = 'タンポポの花', description = 'まだ花の余韻に浸っています', type = 'error'
            })
            return false
        end
        return
    end

    if event ~= 'usedItem' or active[playerId] then return end
    local ticks = math.max(0, math.floor(tonumber(Config.AdmireTicks) or 0))
    local delay = math.max(1000, math.floor(tonumber(Config.AdmireIntervalMs) or 1000))
    local reduction = math.max(0, tonumber(Config.AdmireStressPerTick) or 0)
    if ticks == 0 or reduction == 0 then return end

    active[playerId] = true
    TriggerClientEvent('ox_lib:notify', playerId, {
        title = 'タンポポの花', description = '花を愛でて、ゆっくり心が落ち着いていく', type = 'success'
    })

    CreateThread(function()
        for _ = 1, ticks do
            Wait(delay)
            if not active[playerId] or not GetPlayerName(playerId) then break end
            local current = exports.qbx_core:GetMetadata(playerId, 'stress')
            if type(current) ~= 'number' then break end
            if current > 0 then
                exports.qbx_core:SetMetadata(playerId, 'stress', math.max(0, current - reduction))
            end
        end
        active[playerId] = nil
    end)
end)

AddEventHandler('playerDropped', function()
    active[source] = nil
end)
