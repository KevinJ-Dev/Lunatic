-- A coller dans ox_inventory/data/items.lua, a l'interieur du "return { ... }"

['pomme'] = {
    label = 'Pomme',
    weight = 150,
    stack = true,
    close = true,
    description = 'Une pomme fraiche du verger de Grapeseed.',
    client = {
        status = { hunger = 80000 },
        anim = 'eating',
        usetime = 2500,
        notification = 'Tu as mange une pomme.',
    },
},

['jus_pomme'] = {
    label = 'Jus de pomme',
    weight = 400,
    stack = true,
    close = true,
    description = 'Jus de pomme presse a la main.',
    client = {
        status = { thirst = 200000 },
        anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
        prop = { model = `prop_ld_flow_bottle`, pos = vec3(0.03, 0.03, 0.02), rot = vec3(0.0, 0.0, -1.5) },
        usetime = 2500,
        notification = 'Tu as bu un jus de pomme.',
    },
},
