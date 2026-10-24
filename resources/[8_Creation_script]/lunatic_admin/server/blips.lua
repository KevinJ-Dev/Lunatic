-- Tuile Blips : icônes de la carte du jeu (nom, sprite, couleur, taille, position, affichage), appliquées en jeu
-- tout de suite (GlobalState.lunaticBlips, lu par client/blips.lua). Les blips des magasins (tuile Catalogues) sont
-- affichés avec les autres et leur nom, icône, couleur et taille se modifient ici ; leur position reste celle des
-- emplacements du magasin. Au premier démarrage : lieux publics de base et magasins d'illenium-appearance.

local LIMITS = { blips = 500 }

-- Lieux publics de base (placés de mémoire : à corriger avec « Déplacer » si besoin) :
-- { nom, sprite, couleur, x, y, z }
local BASE = {
    { 'Commissariat de Mission Row', 60, 29, 425.1, -979.5, 30.7 }, { 'Commissariat de Vespucci', 60, 29, -1108.4, -845.5, 19.3 },
    { 'Commissariat de La Mesa', 60, 29, 826.8, -1290.0, 28.2 }, { 'Commissariat de Rockford Hills', 60, 29, -561.6, -131.5, 38.4 },
    { 'Bureau du shérif de Davis', 60, 29, 363.8, -1597.5, 29.3 }, { 'Bureau du shérif de Sandy Shores', 60, 29, 1853.2, 3686.6, 34.3 },
    { 'Bureau du shérif de Paleto Bay', 60, 29, -448.4, 6012.6, 31.7 },
    { 'Hôpital Pillbox Hill', 61, 1, 298.6, -584.6, 43.3 }, { 'Hôpital Central Los Santos', 61, 1, 340.0, -1396.0, 32.5 },
    { 'Hôpital Mount Zonah', 61, 1, -449.0, -340.0, 34.5 }, { 'Hôpital de Sandy Shores', 61, 1, 1839.0, 3672.9, 34.3 },
    { 'Hôpital de Paleto Bay', 61, 1, -247.6, 6331.2, 32.4 },
    { 'Caserne de pompiers de El Burro', 436, 1, 1193.0, -1460.0, 34.8 }, { 'Caserne de pompiers de Davis', 436, 1, 199.8, -1643.9, 29.8 },
    { 'Banque Fleeca', 108, 2, 149.9, -1040.5, 29.4 }, { 'Banque Fleeca', 108, 2, 314.2, -278.6, 54.2 },
    { 'Banque Fleeca', 108, 2, -350.9, -49.9, 49.0 }, { 'Banque Fleeca', 108, 2, -1213.0, -330.9, 37.8 },
    { 'Banque Fleeca', 108, 2, -2962.6, 482.6, 15.7 }, { 'Banque Fleeca', 108, 2, 1175.0, 2706.6, 38.1 },
    { 'Pacific Standard', 108, 2, 241.7, 220.7, 106.3 }, { 'Blaine County Savings', 108, 2, -112.2, 6469.3, 31.6 },
    { 'Station-service', 361, 4, 49.4, 2778.8, 58.0 }, { 'Station-service', 361, 4, 263.9, 2606.5, 44.9 },
    { 'Station-service', 361, 4, 1039.9, 2671.1, 39.5 }, { 'Station-service', 361, 4, 1207.3, 2660.2, 37.9 },
    { 'Station-service', 361, 4, 2539.7, 2594.2, 37.9 }, { 'Station-service', 361, 4, 2679.9, 3263.9, 55.2 },
    { 'Station-service', 361, 4, 2005.1, 3773.9, 32.4 }, { 'Station-service', 361, 4, 1687.2, 4929.4, 42.1 },
    { 'Station-service', 361, 4, 1701.3, 6416.0, 32.8 }, { 'Station-service', 361, 4, 179.9, 6602.8, 31.9 },
    { 'Station-service', 361, 4, -94.5, 6419.6, 31.5 }, { 'Station-service', 361, 4, -2554.9, 2334.4, 33.1 },
    { 'Station-service', 361, 4, -1800.4, 803.7, 138.7 }, { 'Station-service', 361, 4, -1437.6, -276.7, 46.2 },
    { 'Station-service', 361, 4, -2096.2, -320.3, 13.2 }, { 'Station-service', 361, 4, -724.6, -935.2, 19.2 },
    { 'Station-service', 361, 4, -526.0, -1211.0, 18.2 }, { 'Station-service', 361, 4, -70.2, -1761.8, 29.5 },
    { 'Station-service', 361, 4, 265.6, -1261.3, 29.3 }, { 'Station-service', 361, 4, 819.7, -1028.8, 26.4 },
    { 'Station-service', 361, 4, 1208.9, -1402.6, 35.2 }, { 'Station-service', 361, 4, 1181.4, -330.8, 69.3 },
    { 'Station-service', 361, 4, 620.8, 269.1, 103.1 }, { 'Station-service', 361, 4, 2581.3, 362.0, 108.5 },
    { 'Station-service', 361, 4, 176.6, -1562.0, 29.3 }, { 'Station-service', 361, 4, -319.3, -1471.7, 30.5 },
    { 'Los Santos Customs', 72, 0, -337.0, -136.0, 39.0 }, { 'Los Santos Customs', 72, 0, 731.8, -1088.9, 22.2 },
    { 'Los Santos Customs', 72, 0, -1155.5, -2007.2, 13.2 }, { 'Los Santos Customs', 72, 0, 1175.0, 2640.0, 37.8 },
    { "Beeker's Garage", 72, 0, 110.0, 6626.6, 31.8 },
    { 'Station de lavage', 100, 3, 26.6, -1392.0, 29.4 }, { 'Station de lavage', 100, 3, 167.1, -1719.4, 29.3 },
    { 'Station de lavage', 100, 3, -699.6, -932.7, 19.0 },
    { 'Parking public', 357, 3, 215.8, -810.1, 30.7 }, { 'Parking public', 357, 3, 1737.6, 3710.2, 34.1 },
    { 'Parking public', 357, 3, 105.4, 6613.6, 32.4 },
    { 'Fourrière', 68, 47, 401.0, -1632.0, 29.3 },
    { 'Concession Premium Deluxe', 326, 3, -56.5, -1096.6, 26.4 },
    { 'Aéroport international de Los Santos', 90, 3, -1037.0, -2737.0, 20.2 },
    { 'Mairie', 419, 0, -544.9, -204.4, 38.2 }, { 'Pôle emploi', 407, 27, -268.0, -957.0, 31.2 },
    { 'Prison de Bolingbroke', 188, 1, 1854.0, 2622.0, 45.6 },
    { 'Bahama Mamas', 93, 27, -1388.0, -618.0, 30.8 }, { 'Vanilla Unicorn', 121, 27, 129.0, -1300.0, 29.2 },
    { 'Tequi-la-la', 93, 27, -565.0, 280.0, 82.9 },
}

-- Magasins d'illenium-appearance (positions exactes de sa config ; ses propres blips sont coupés) : { type, x, y, z }
local ILLENIUM_STYLE = {
    clothing = { 'Magasin de vêtements', 366, 47, 0.5 },
    barber = { 'Coiffeur', 71, 0, 0.5 },
    tattoo = { 'Salon de tatouage', 75, 4, 0.5 },
}
local ILLENIUM = {
    { 'clothing', 1693.2, 4828.11, 42.07 }, { 'clothing', -705.5, -149.22, 37.42 }, { 'clothing', -1192.61, -768.4, 17.32 },
    { 'clothing', 425.91, -801.03, 29.49 }, { 'clothing', -168.73, -301.41, 39.73 }, { 'clothing', 75.39, -1398.28, 29.38 },
    { 'clothing', -827.39, -1075.93, 11.33 }, { 'clothing', -1445.86, -240.78, 49.82 }, { 'clothing', 9.22, 6515.74, 31.88 },
    { 'clothing', 615.35, 2762.72, 42.09 }, { 'clothing', 1191.61, 2710.91, 38.22 }, { 'clothing', -3171.32, 1043.56, 20.86 },
    { 'clothing', -1105.52, 2707.79, 19.11 }, { 'clothing', -1119.24, -1440.6, 5.23 }, { 'clothing', 124.82, -224.36, 54.56 },
    { 'barber', -814.22, -183.7, 37.57 }, { 'barber', 136.78, -1708.4, 29.29 }, { 'barber', -1282.57, -1116.84, 6.99 },
    { 'barber', 1931.41, 3729.73, 32.84 }, { 'barber', 1212.8, -472.9, 65.2 }, { 'barber', -32.9, -152.3, 56.1 },
    { 'barber', -278.1, 6228.5, 30.7 },
    { 'tattoo', 1322.6, -1651.9, 51.2 }, { 'tattoo', -1154.01, -1425.31, 4.95 }, { 'tattoo', 322.62, 180.34, 103.59 },
    { 'tattoo', -3169.52, 1074.86, 20.83 }, { 'tattoo', 1864.1, 3747.91, 33.03 }, { 'tattoo', -294.24, 6200.12, 31.49 },
}

local blips = {}

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les blips.")
end

local function guard(actor)
    return Ranks.hasPermission(actor, 'blips.manage')
end

local function whole(value, min, max)
    local n = tonumber(value)
    return n and n == math.floor(n) and n >= min and n <= max and math.floor(n) or nil
end

local function cleanText(value, max)
    local text = type(value) == 'string' and value:gsub('[%c<>]', ''):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    return #text >= 1 and #text <= max and text or nil
end

local function positionOf(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z }
end

-- Blips actifs pour les joueurs (et ceux des magasins restent publiés par la tuile Catalogues)
local function publish()
    local list = {}

    for _, blip in ipairs(blips) do
        if blip.active then
            list[#list + 1] = { id = blip.id, label = blip.label, sprite = blip.sprite, color = blip.color, scale = blip.scale, x = blip.x, y = blip.y, z = blip.z, short = blip.short }
        end
    end

    GlobalState.lunaticBlips = list
end

local function load()
    blips = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_blips` ORDER BY `label`, `id`') or {}) do
        blips[#blips + 1] = {
            id = tonumber(row.id), label = row.label, sprite = tonumber(row.sprite), color = tonumber(row.color), scale = tonumber(row.scale),
            x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
            -- TINYINT : nombre (TINYINT(1) serait renvoyé en booléen par oxmysql)
            short = tonumber(row.short_range) == 1, active = tonumber(row.active) == 1,
        }
    end

    publish()
end

local function findBlip(id)
    for _, blip in ipairs(blips) do
        if blip.id == tonumber(id) then
            return blip
        end
    end
end

local function insert(label, sprite, color, scale, x, y, z)
    MySQL.insert.await('INSERT INTO `lunatic_blips` (`label`, `sprite`, `color`, `scale`, `x`, `y`, `z`, `short_range`, `active`) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1)', {
        label, sprite, color, scale, x, y, z,
    })
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_blips` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `label` VARCHAR(60) NOT NULL,
            `sprite` INT NOT NULL DEFAULT 1,
            `color` INT NOT NULL DEFAULT 0,
            `scale` DOUBLE NOT NULL DEFAULT 0.8,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL DEFAULT 0,
            `short_range` TINYINT NOT NULL DEFAULT 1,
            `active` TINYINT NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Premier démarrage : lieux publics de base et magasins d'illenium-appearance
    if not GetResourceKvpString('blips_seeded') then
        SetResourceKvp('blips_seeded', '1')

        for _, entry in ipairs(BASE) do
            insert(entry[1], entry[2], entry[3], 0.8, entry[4], entry[5], entry[6])
        end

        for _, entry in ipairs(ILLENIUM) do
            local style = ILLENIUM_STYLE[entry[1]]
            insert(style[1], style[2], style[3], style[4], entry[2], entry[3], entry[4])
        end
    end

    load()
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

Panel.actions['blips.list'] = function(_, actor)
    if not guard(actor) then
        return denied()
    end

    return { ok = true, silent = true, blips = blips, shops = Shops.blipList(), canShops = Ranks.hasPermission(actor, 'catalogs.manage') }
end

-- Réglages communs d'un blip (nom, sprite, couleur, taille) ; nil + message si invalide
local function readStyle(data)
    local label = cleanText(data.label, 60)
    local sprite = whole(data.sprite, 0, 1000)
    local color = whole(data.color, 0, 100)
    local scale = tonumber(data.scale)

    if not label then
        return nil, 'Le nom doit faire entre 1 et 60 caractères.'
    end

    if not sprite or not color then
        return nil, 'Sprite ou couleur invalide.'
    end

    if not scale or scale < 0.1 or scale > 3.0 then
        return nil, 'Taille : entre 0,1 et 3.'
    end

    return { label = label, sprite = sprite, color = color, scale = math.floor(scale * 100 + 0.5) / 100 }
end

Panel.actions['blips.save'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local style, err = readStyle(data)

    if not style then
        return Panel.fail(err)
    end

    -- Position : cliquée sur la carte, sinon celle du staff (création)
    local placed = nil

    if data.x ~= nil or data.y ~= nil then
        local x, y = tonumber(data.x), tonumber(data.y)

        if not x or not y or x < -5000 or x > 5000 or y < -5000 or y > 9000 then
            return Panel.fail('Position sur la carte invalide.')
        end

        placed = { x = x, y = y, z = 0.0 }
    end

    local short = data.short ~= false
    local active = data.active ~= false
    local id = nil

    if data.id then
        local blip = findBlip(data.id)

        if not blip then
            return Panel.fail('Blip introuvable.')
        end

        MySQL.update.await('UPDATE `lunatic_blips` SET `label` = ?, `sprite` = ?, `color` = ?, `scale` = ?, `short_range` = ?, `active` = ? WHERE `id` = ?', {
            style.label, style.sprite, style.color, style.scale, short and 1 or 0, active and 1 or 0, blip.id,
        })

        if placed then
            MySQL.update.await('UPDATE `lunatic_blips` SET `x` = ?, `y` = ?, `z` = ? WHERE `id` = ?', { placed.x, placed.y, blip.z, blip.id })
        end

        id = blip.id
    else
        if #blips >= LIMITS.blips then
            return Panel.fail(('Maximum %d blips.'):format(LIMITS.blips))
        end

        local position = placed or positionOf(src)

        if not position then
            return Panel.fail('Position introuvable.')
        end

        id = MySQL.insert.await('INSERT INTO `lunatic_blips` (`label`, `sprite`, `color`, `scale`, `x`, `y`, `z`, `short_range`, `active`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            style.label, style.sprite, style.color, style.scale, position.x, position.y, position.z, short and 1 or 0, active and 1 or 0,
        })
    end

    load()
    Logs.add(src, 'blips.save', nil, { label = style.label, operation = data.id and 'edit' or 'add' })

    return { ok = true, silent = true, id = id }
end

-- Blip replacé à la position du staff
Panel.actions['blips.move'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local blip = findBlip(data.id)
    local position = positionOf(src)

    if not blip or not position then
        return Panel.fail(blip and 'Position introuvable.' or 'Blip introuvable.')
    end

    MySQL.update.await('UPDATE `lunatic_blips` SET `x` = ?, `y` = ?, `z` = ? WHERE `id` = ?', { position.x, position.y, position.z, blip.id })
    load()
    Logs.add(src, 'blips.save', nil, { label = blip.label, operation = 'move' })

    return { ok = true, silent = true }
end

Panel.actions['blips.tp'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local blip = findBlip(data.id)

    if not blip then
        return Panel.fail('Blip introuvable.')
    end

    -- Hauteur inconnue (placé sur la carte) : le client cherche le sol
    TriggerClientEvent('lunatic_admin:teleport', src, vector3(blip.x, blip.y, blip.z ~= 0.0 and blip.z + 1.0 or -200.0))
    return { ok = true, silent = true }
end

Panel.actions['blips.delete'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local blip = findBlip(data.id)

    if not blip then
        return Panel.fail('Blip introuvable.')
    end

    MySQL.update.await('DELETE FROM `lunatic_blips` WHERE `id` = ?', { blip.id })
    load()
    Logs.add(src, 'blips.save', nil, { label = blip.label, operation = 'delete' })

    return { ok = true, silent = true }
end

-- Blip d'un magasin (tuile Catalogues) : nom, icône, couleur, taille pour tous ses emplacements
Panel.actions['blips.saveShop'] = function(src, actor, data)
    if not guard(actor) or not Ranks.hasPermission(actor, 'catalogs.manage') then
        return Panel.fail("Il faut aussi la permission Catalogues pour modifier le blip d'un magasin.")
    end

    local style, err = readStyle(data)

    if not style then
        return Panel.fail(err)
    end

    if not Shops.setBlip(data.shop, style) then
        return Panel.fail('Magasin introuvable.')
    end

    Logs.add(src, 'blips.save', nil, { label = style.label, operation = 'shop' })
    return { ok = true, silent = true }
end
