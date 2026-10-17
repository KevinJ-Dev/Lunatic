--[[
    nc_pommes - NightCraft Studio
    Farm de pommes : recolte -> pressage en jus -> vente
    Tout ce qui se regle est dans ce fichier.
]]

Config = {}

-- Job requis pour farmer.
--   false                  = ouvert a tout le monde
--   'fermier'              = un seul job
--   { 'fermier', 'autre' } = plusieurs jobs
Config.Job = false

-- Touche d'interaction (38 = E). Liste : https://docs.fivem.net/docs/game-references/controls/
Config.InteractKey = 38

-- Distance max (en metres) toleree par le serveur entre le joueur et le point.
-- Sert d'anti-triche : inutile d'y toucher sauf si tu agrandis les zones.
Config.MaxDistance = 6.0

-- true = active la commande /pommepos qui copie ta position (vec3) dans le presse-papier,
-- pratique pour ajouter des arbres. A remettre sur false en production.
Config.Debug = false

-- Noms des items dans ox_inventory (voir install/items.lua)
Config.Items = {
    apple = 'pomme',
    juice = 'jus_pomme',
}

-- Marqueurs au sol
Config.Marker = {
    enabled      = true,
    type         = 2,      -- https://docs.fivem.net/docs/game-references/markers/
    scale        = 0.35,
    drawDistance = 20.0,   -- distance a partir de laquelle le marqueur s'affiche
    interact     = 1.6,    -- distance a laquelle le [E] apparait
    color        = { r = 220, g = 50,  b = 50,  a = 200 },  -- arbre plein / point actif
    emptyColor   = { r = 130, g = 130, b = 130, a = 140 },  -- arbre vide
}

---------------------------------------------------------------------------
-- 1) RECOLTE
---------------------------------------------------------------------------
Config.Harvest = {
    duration = 6000,   -- temps de cueillette (ms)
    min      = 2,      -- pommes minimum par arbre
    max      = 6,      -- pommes maximum par arbre
    respawn  = 90,     -- secondes avant qu'un arbre redonne des pommes (commun a tous les joueurs)

    anim = { dict = 'amb@prop_human_movie_bulb@idle_a', clip = 'idle_a' },

    blip = {
        enabled = true,
        coords  = vec3(2339.31, 4755.60, 34.04),
        sprite  = 1,       -- https://docs.fivem.net/docs/game-references/blips/
        color   = 1,
        scale   = 0.8,
        label   = 'Verger de pommes',
    },

    -- Un point = un arbre. Verger de Grapeseed.
    -- Mets-toi au pied d'un arbre, fais /pommepos (Config.Debug = true) et colle la ligne ici.
    trees = {
        vec3(2325.66, 4761.76, 35.34),
        vec3(2327.44, 4770.81, 35.38),
        vec3(2324.56, 4746.98, 35.33),
        vec3(2343.48, 4755.61, 34.04),
        vec3(2339.31, 4767.11, 34.08),
        vec3(2339.34, 4741.35, 35.09),
        vec3(2353.48, 4760.34, 34.53),
    },
}

---------------------------------------------------------------------------
-- 2) PRESSAGE (pommes -> jus de pomme)
---------------------------------------------------------------------------
Config.Process = {
    coords = vec3(2064.21, 4819.52, 41.45),

    input           = 3,      -- pommes consommees...
    output          = 1,      -- ...pour ce nombre de jus
    durationPerUnit = 2500,   -- ms par pressage
    maxBatch        = 20,     -- nombre max de pressages lances d'un coup

    anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },

    blip = {
        enabled = true,
        sprite  = 478,
        color   = 5,
        scale   = 0.8,
        label   = 'Pressoir a pommes',
    },
}

---------------------------------------------------------------------------
-- 3) VENTE
---------------------------------------------------------------------------
Config.Sell = {
    coords  = vec4(2564.36, 4680.37, 33.08, 0.0),   -- x, y, z, orientation du PNJ
    account = 'money',                               -- 'money', 'bank' ou 'black_money'

    ped = {
        model    = 'a_m_m_farmer_01',
        scenario = 'WORLD_HUMAN_CLIPBOARD',
    },

    -- Prix a l'unite. Le jus rapporte plus que les pommes brutes (3 pommes = 18$, 1 jus = 28$).
    items = {
        { item = 'pomme',     price = 6  },
        { item = 'jus_pomme', price = 28 },
    },

    blip = {
        enabled = true,
        sprite  = 108,
        color   = 2,
        scale   = 0.8,
        label   = 'Grossiste en fruits',
    },
}

---------------------------------------------------------------------------
-- TEXTES
---------------------------------------------------------------------------
Config.Locale = {
    title             = 'Verger',

    prompt_harvest    = '[E] Cueillir des pommes',
    prompt_empty      = 'Cet arbre n\'a plus de pommes',
    prompt_process    = '[E] Presser des pommes',
    prompt_sell       = '[E] Parler au grossiste',

    progress_harvest  = 'Cueillette en cours...',
    progress_process  = 'Pressage en cours...',

    harvest_done      = 'Tu as cueilli %sx pomme(s).',
    process_done      = 'Tu as presse %sx jus de pomme.',
    sold              = 'Tu as vendu %sx %s pour %s$.',

    cancelled         = 'Action annulee.',
    no_job            = 'Tu n\'as pas le metier requis.',
    tree_empty        = 'Cet arbre n\'a plus de pommes, reviens plus tard.',
    tree_busy         = 'Quelqu\'un cueille deja sur cet arbre.',
    inventory_full    = 'Tu n\'as plus de place sur toi.',
    not_enough_apples = 'Il te faut au moins %s pommes pour un pressage.',
    nothing_to_sell   = 'Tu n\'as rien a vendre.',
    not_enough_items  = 'Tu n\'en as pas assez sur toi.',

    process_title     = 'Pressoir',
    process_amount    = 'Nombre de jus a presser',
    sell_title        = 'Grossiste en fruits',
    sell_amount       = 'Quantite a vendre',
    sell_line         = '%s$ l\'unite - tu en as %s',
}

---------------------------------------------------------------------------
-- Fonctions partagees (ne pas modifier)
---------------------------------------------------------------------------
function Locale(key, ...)
    local text = Config.Locale[key] or key
    if select('#', ...) > 0 then
        return text:format(...)
    end
    return text
end

function IsJobAllowed(jobName)
    if not Config.Job then return true end
    if not jobName then return false end

    if type(Config.Job) == 'table' then
        for i = 1, #Config.Job do
            if Config.Job[i] == jobName then return true end
        end
        return false
    end

    return Config.Job == jobName
end
