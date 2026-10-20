-- ox_inventory/data/items.lua の return { ... } に追記
['narcox_dandelion_flower'] = {
    label = 'タンポポの花',
    weight = 25,
    stack = true,
    close = true,
    consume = 1, -- ox_inventoryの使用成功時に花を1個消費
    client = {
        usetime = 2200,
        anim = { dict = 'amb@world_human_stand_mobile@male@text@base', clip = 'base' },
        disable = { combat = true },
    },
    server = { export = 'ptech_narcox_foraging.admireFlower' },
    description = '道端で摘んだ、見慣れた名前の不思議な花。',
},
