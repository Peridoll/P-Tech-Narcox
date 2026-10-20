Config = {}

Config.Item = 'narcox_dandelion_flower'
Config.ItemCount = 1
-- 愛でた後に、1秒ごとにストレスを1ポイントずつ減らす（即時回復なし）
Config.AdmireTicks = 5
Config.AdmireIntervalMs = 1000
Config.AdmireStressPerTick = 1
Config.RespawnSeconds = 20 * 60
Config.HarvestDurationMs = 2500
Config.InteractDistance = 1.5
Config.ServerDistance = 3.0
Config.RenderDistance = 38.0
Config.DespawnDistance = 48.0
Config.PropModel = 'prop_plant_fern_02a' -- 仮の植物モデル
Config.PropZOffset = -0.15
Config.StateFile = 'plant_state.json'

-- 候補座標は導入マップに合わせて手動調整すること。
-- maxActive 本をランダムに選び、採取後は候補の別地点へ再出現する。
Config.Areas = {
    legion_park = {
        label = 'レギオン広場（サンプル）',
        maxActive = 5,
        points = {
            vec3(191.2, -931.2, 30.7),
            vec3(197.8, -927.5, 30.7),
            vec3(205.0, -919.0, 30.7),
            vec3(210.1, -911.5, 30.7),
            vec3(218.4, -903.8, 30.7),
            vec3(225.3, -899.2, 30.7),
            vec3(214.8, -893.5, 30.7),
            vec3(205.3, -901.0, 30.7),
            vec3(195.0, -906.6, 30.7),
            vec3(184.5, -914.0, 30.7),
        }
    }
}
