Config = {}

-- 配置・経済数値は合意済みの本番値ではなく動作確認用。
-- 導入時に確認・調整した後で有効にする。例示を本番仕様に固定しないためのスイッチ。
Config.Enabled = false
Config.StateFile = 'contracts_state.json'
Config.Command = 'narcoxcontracts'
Config.InteractDistance = 1.8
Config.ServerDistance = 3.0
Config.RenderDistance = 60.0
Config.ActionIntervalMs = 1000 -- 通信の連打防止。仕事のクールダウンではない。
Config.StateSaveIntervalMs = 10000 -- 残り時間を定期保存。期限の判定自体は毎秒。
Config.MaxActive = 0 -- 0: 件数制限なし。同じNPCからも複数受注可能。

-- 銀行振込は今回の明示指定。現金アイテム名を推測しない。
Config.PaymentReason = 'narcox-contract'

Config.Npcs = {
    flower_contact = {
        label = '植物の調達依頼人（仮）',
        model = 'a_m_m_farmer_01',
        coords = { x = 178.2, y = -916.7, z = 30.7, w = 90.0 },
        bucket = 0,
        jobs = { 'dandelion' }
    }
}

Config.Jobs = {
    dandelion = {
        label = 'タンポポの花の調達',
        item = 'narcox_dandelion_flower',
        itemLabel = 'タンポポの花',
        legal = true,
        -- 最初の依頼には好感度の下限を設けず、失敗後も再挑戦できる。
        -- 別の依頼に minFavor を設定すると、そのNPCの現在の好感度で開放を判定する。
        quantity = { min = 5, max = 10 },
        durationSeconds = { min = 600, max = 1200 },
        unitReward = 100,
        rewardPercent = { min = 90, max = 110 },
        successFavor = 1,
        failureFavor = 1,
        -- 初回調達は依頼主へ戻る。手持ちの花も納品できる（今回合意）。
        delivery = 'issuer'
        -- delivery = 'point' の依頼には下記形式の候補を設定できる。
        -- points = { { x = ..., y = ..., z = ..., bucket = 0 }, ... }
        -- 依頼ごとに候補から1か所を選ぶ。採取場所は制限しない。
    }
}

-- 乾燥・種子加工・販売の具体的な依頼と閾値は未合意のため登録しない。
-- 売人配置・発見・商品・市場は、この調達処理から独立した将来の機能として保留。
