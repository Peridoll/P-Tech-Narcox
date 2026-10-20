-- 純粋な生成・状態更新だけを置く。所持品、振込、距離、本人確認はサーバーの責務。
Contracts = {}

local function integer(value, minimum)
    return type(value) == 'number' and value == value and value < math.huge
        and value % 1 == 0 and value >= minimum
end

local function range(value, minimum)
    return type(value) == 'table' and integer(value.min, minimum)
        and integer(value.max, value.min)
end

local function coords(value)
    if type(value) ~= 'table' then return false end
    for _, key in ipairs({ 'x', 'y', 'z' }) do
        local n = value[key]
        if type(n) ~= 'number' or n ~= n or math.abs(n) == math.huge then return false end
    end
    return true
end

function Contracts.validate(config)
    assert(type(config.Enabled) == 'boolean', 'Enabled must be boolean')
    assert(type(config.StateFile) == 'string' and config.StateFile:match('^[%w_-]+%.json$'), 'invalid StateFile')
    assert(type(config.Command) == 'string' and config.Command:match('^[%w_-]+$'), 'invalid command')
    assert(integer(config.MaxActive, 0), 'invalid MaxActive')
    assert(integer(config.ActionIntervalMs, 1) and integer(config.StateSaveIntervalMs, 1), 'invalid interval')
    assert(type(config.PaymentReason) == 'string', 'invalid payment reason')
    assert(type(config.InteractDistance) == 'number' and config.InteractDistance > 0, 'invalid interaction distance')
    assert(type(config.ServerDistance) == 'number' and config.ServerDistance >= config.InteractDistance, 'invalid server distance')
    assert(type(config.RenderDistance) == 'number' and config.RenderDistance > config.ServerDistance, 'invalid render distance')
    for id, job in pairs(config.Jobs) do
        assert(type(id) == 'string' and type(job.label) == 'string', 'invalid job')
        assert(type(job.item) == 'string' and type(job.itemLabel) == 'string', 'invalid item')
        assert(job.minFavor == nil or (type(job.minFavor) == 'number' and integer(math.abs(job.minFavor), 0)), 'invalid minFavor')
        assert(range(job.quantity, 1) and range(job.durationSeconds, 1), 'invalid quantity or duration')
        assert(integer(job.unitReward, 1) and range(job.rewardPercent, 1), 'invalid reward')
        assert(math.floor(job.quantity.min * job.unitReward * job.rewardPercent.min / 100) >= 1, 'reward too small')
        assert(job.quantity.max * job.unitReward * job.rewardPercent.max / 100 <= 2147483647, 'reward too large')
        assert(integer(job.successFavor, 0) and integer(job.failureFavor, 0), 'invalid favor')
        assert(job.delivery == 'issuer' or job.delivery == 'point', 'invalid delivery')
        if job.delivery == 'point' then
            assert(type(job.points) == 'table' and #job.points > 0, 'delivery points required')
            for _, point in ipairs(job.points) do
                assert(coords(point) and integer(point.bucket, 0), 'invalid point')
            end
        end
    end
    for id, npc in pairs(config.Npcs) do
        assert(type(id) == 'string' and type(npc.label) == 'string' and type(npc.model) == 'string', 'invalid NPC')
        assert(coords(npc.coords) and type(npc.coords.w) == 'number' and integer(npc.bucket, 0), 'invalid NPC placement')
        assert(type(npc.jobs) == 'table' and #npc.jobs > 0, 'NPC jobs required')
        for _, jobId in ipairs(npc.jobs) do assert(config.Jobs[jobId], 'unknown NPC job: ' .. tostring(jobId)) end
    end
    return true
end

function Contracts.candidates(config, player, npcId)
    local choices, npc = {}, config.Npcs[npcId]
    if not npc then return choices end
    for _, jobId in ipairs(npc.jobs) do
        local job = config.Jobs[jobId]
        if job.enabled ~= false and (job.minFavor == nil or (player.favor[npcId] or 0) >= job.minFavor) then
            choices[#choices + 1] = jobId
        end
    end
    return choices
end

function Contracts.generate(config, player, npcId, id, random)
    random = random or math.random
    local choices = Contracts.candidates(config, player, npcId)
    if #choices == 0 then return nil end
    local jobId = choices[random(1, #choices)]
    local npc, job = config.Npcs[npcId], config.Jobs[jobId]
    local quantity = random(job.quantity.min, job.quantity.max)
    local percent = random(job.rewardPercent.min, job.rewardPercent.max)
    local point = npc.coords
    local bucket = npc.bucket
    if job.delivery == 'point' then
        point = job.points[random(1, #job.points)]
        bucket = point.bucket
    end
    -- 受注時の条件を保存する。後からConfigを調整しても進行中の契約を変えない。
    return {
        id = id, npcId = npcId, npcLabel = npc.label, jobId = jobId,
        label = job.label, item = job.item, itemLabel = job.itemLabel,
        quantity = quantity, reward = math.floor(quantity * job.unitReward * percent / 100),
        remainingMs = random(job.durationSeconds.min, job.durationSeconds.max) * 1000,
        successFavor = job.successFavor, failureFavor = job.failureFavor,
        target = { x = point.x, y = point.y, z = point.z, bucket = bucket },
        status = 'active', legal = job.legal == true
    }
end

function Contracts.finish(player, contract, success)
    assert(contract.status == 'active' or contract.status == 'processing', 'contract already finished')
    contract.status = success and 'completed' or 'failed'
    player.favor[contract.npcId] = (player.favor[contract.npcId] or 0)
        + (success and contract.successFavor or -contract.failureFavor)
    player.active[contract.id] = nil
end

function Contracts.advance(player, elapsedMs)
    local expired = {}
    for _, contract in pairs(player.active) do
        if contract.status == 'active' then
            contract.remainingMs = math.max(0, contract.remainingMs - elapsedMs)
            if contract.remainingMs == 0 then expired[#expired + 1] = contract end
        end
    end
    for _, contract in ipairs(expired) do Contracts.finish(player, contract, false) end
    return #expired
end

function Contracts.count(player)
    local count = 0
    for _ in pairs(player.active) do count = count + 1 end
    return count
end
