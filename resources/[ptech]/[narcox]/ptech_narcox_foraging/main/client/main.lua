local active, props = {}, {}
local targetKey, collecting, promptVisible = nil, false, false
local model = joaat(Config.PropModel)

local function keyFor(areaId, slot)
    return ('%s:%s'):format(areaId, slot)
end

local function clearPrompt()
    if promptVisible then lib.hideTextUI() promptVisible = false end
    targetKey = nil
end

local function removeProp(key)
    local object = props[key]
    if object and DoesEntityExist(object) then DeleteEntity(object) end
    props[key] = nil
end

local function setState(data)
    if type(data) ~= 'table' then return end
    local replacement = {}
    for areaId, slots in pairs(data) do
        local area = Config.Areas[areaId]
        if area and type(slots) == 'table' then
            for slotStr, pointIndex in pairs(slots) do
                local slot = tonumber(slotStr)
                local index = tonumber(pointIndex)
                local point = index and area.points[index]
                if slot and point then
                    local key = keyFor(areaId, slot)
                    replacement[key] = {areaId = areaId, slot = slot, pointIndex = index, coords = point}
                end
            end
        end
    end
    for key, old in pairs(active) do
        if not replacement[key] or replacement[key].pointIndex ~= old.pointIndex then removeProp(key) end
    end
    active = replacement
    if targetKey and not active[targetKey] then clearPrompt() end
end

RegisterNetEvent('ptech_narcox_foraging:sync', setState)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
    Wait(1500)
    setState(lib.callback.await('ptech_narcox_foraging:getState', false))
end)

local function ensureModel()
    if HasModelLoaded(model) then return true end
    if not IsModelInCdimage(model) or not IsModelValid(model) then return false end
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(model)
end

local modelWarned = false
CreateThread(function()
    while true do
        Wait(1500)
        local playerPos = GetEntityCoords(PlayerPedId())
        for key, entry in pairs(active) do
            local d = #(playerPos - entry.coords)
            if d <= Config.RenderDistance and not props[key] then
                if ensureModel() then
                    local c = entry.coords
                    local obj = CreateObjectNoOffset(model, c.x, c.y, c.z + Config.PropZOffset, false, false, false)
                    if obj ~= 0 then
                        SetEntityAsMissionEntity(obj, true, true)
                        FreezeEntityPosition(obj, true)
                        SetEntityCollision(obj, false, false)
                        props[key] = obj
                    end
                elseif not modelWarned then
                    modelWarned = true
                    print(('[Narcox] Unknown prop model: %s'):format(Config.PropModel))
                end
            elseif d > Config.DespawnDistance and props[key] then
                removeProp(key)
            end
        end
        for key in pairs(props) do
            if not active[key] then removeProp(key) end
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 500
        if not collecting then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local closestKey, closestEntry, nearest = nil, nil, Config.InteractDistance
            if not IsPedInAnyVehicle(ped, false) then
                for key, entry in pairs(active) do
                    if props[key] then
                        local dist = #(pos - entry.coords)
                        if dist <= nearest then
                            nearest = dist
                            closestKey, closestEntry = key, entry
                        end
                    end
                end
            end
            if closestKey ~= targetKey then
                clearPrompt()
                if closestKey then
                    targetKey = closestKey
                    lib.showTextUI('[E] タンポポを摘む', {icon = 'seedling'})
                    promptVisible = true
                end
            end
            if closestEntry then
                sleep = 0
                if IsControlJustPressed(0, 38) then
                    collecting = true
                    clearPrompt()
                    local completed = lib.progressCircle({
                        duration = Config.HarvestDurationMs,
                        label = 'タンポポを摘んでいます',
                        position = 'bottom',
                        canCancel = true,
                        disable = {move = true, car = true, combat = true},
                        anim = {dict = 'amb@world_human_gardener_plant@male@base', clip = 'base'}
                    })
                    if completed then
                        local ok, message = lib.callback.await('ptech_narcox_foraging:harvest', false,
                            closestEntry.areaId, closestEntry.slot, closestEntry.pointIndex)
                        lib.notify({title = 'タンポポ', description = message or '処理に失敗しました',
                            type = ok and 'success' or 'error'})
                    end
                    collecting = false
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearPrompt()
    for key in pairs(props) do removeProp(key) end
    if HasModelLoaded(model) then SetModelAsNoLongerNeeded(model) end
end)
