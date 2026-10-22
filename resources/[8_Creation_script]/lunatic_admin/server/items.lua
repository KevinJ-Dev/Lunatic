-- Tuile Items : création et modification des objets d'ox_inventory depuis le panel.
-- Les objets du panel sont en base (lunatic_items) et écrits dans ox_inventory/data/lunatic_items.lua, que
-- data/items.lua fusionne au démarrage d'ox_inventory : une modification s'applique en jeu au prochain redémarrage
-- du serveur (ox_inventory ne sait pas charger un objet en cours de route). Les données en base serviront aussi
-- à un futur inventaire maison.

ItemsCatalog = {}

local ox = exports.ox_inventory

local CATEGORIES = {
    { id = 'consumable', label = 'Consommables', editable = true },
    { id = 'object', label = 'Objets', editable = true },
    { id = 'drug', label = 'Drogues', editable = true },
    { id = 'weapon', label = 'Armes', editable = false },
    { id = 'ammo', label = 'Munitions', editable = false },
}
local EDITABLE = { consumable = true, object = true, drug = true }

-- Animations et objets en main proposés pour les consommables
local ANIMS = {
    eat = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger_fp', label = 'Manger' },
    drink = { dict = 'mp_player_intdrink', clip = 'loop_bottle', label = 'Boire' },
    smoke = { dict = 'amb@world_human_aa_smoke@male@idle_a', clip = 'idle_c', label = 'Fumer' },
}
local PROPS = {
    burger = { model = 'prop_cs_burger_01', pos = { 0.02, 0.02, -0.02 }, rot = { 0.0, 0.0, 0.0 }, label = 'Burger' },
    can = { model = 'prop_ld_can_01', pos = { 0.01, 0.01, 0.06 }, rot = { 5.0, 5.0, -180.5 }, label = 'Canette' },
    bottle = { model = 'prop_ld_flow_bottle', pos = { 0.03, 0.03, 0.02 }, rot = { 0.0, 0.0, -1.5 }, label = "Bouteille d'eau" },
    beer = { model = 'prop_amb_beer_bottle', pos = { 0.0, 0.0, 0.05 }, rot = { 0.0, 0.0, 0.0 }, label = 'Bouteille de bière' },
    cocktail = { model = 'prop_cocktail', pos = { 0.0, 0.0, 0.05 }, rot = { 0.0, 0.0, 0.0 }, label = 'Cocktail' },
    coffee = { model = 'p_amb_coffeecup_01', pos = { 0.0, 0.0, 0.0 }, rot = { 0.0, 0.0, 0.0 }, label = 'Café' },
    donut = { model = 'prop_amb_donut', pos = { 0.013, 0.0, -0.01 }, rot = { 0.0, 0.0, 0.0 }, label = 'Donut' },
    sandwich = { model = 'prop_sandwich_01', pos = { 0.05, -0.02, -0.03 }, rot = { 0.0, 0.0, 0.0 }, label = 'Sandwich' },
    cigarette = { model = 'prop_cs_ciggy_01', pos = { 0.0, 0.0, 0.0 }, rot = { 0.0, 0.0, 0.0 }, label = 'Cigarette' },
}
-- Objets de base classés « consommables » tant qu'ils n'ont pas été rangés dans le panel
local FOOD = { burger = true, sprunk = true, water = true, pomme = true, jus_pomme = true, donut = true, fries = true, pizza_ham = true, pizza_ham_slice = true, lean = true, testburger = true }
local LIMITS = { label = 60, description = 200, weight = 1000000, price = 10000000, expiration = 8760, usetime = 30 }

local rows = {}     -- objets du panel (nom -> ligne)
local applied = {}  -- objet -> texte généré tel que chargé par ox_inventory au dernier démarrage
local permanentHook

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les items.")
end

local function whole(value, min, max)
    local n = tonumber(value)
    return n and n == math.floor(n) and n >= min and n <= max and math.floor(n) or nil
end

local function cleanText(value, min, max)
    if value == nil then
        value = ''
    end

    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length >= min and length <= max and text or nil
end

local function drugItems()
    local list = {}

    for _, drug in ipairs(GlobalState.lunaticDrugs or {}) do
        list[drug.item] = true
    end

    return list
end

-- Catégorie d'un objet : celle du panel, sinon devinée
local function categoryOf(name, item)
    if rows[name] then
        return rows[name].category
    end

    if name:match('^WEAPON_') or (item and item.weapon) then
        return 'weapon'
    end

    if name:match('^ammo%-') or name:match('^at_') then
        return name:match('^at_') and 'weapon' or 'ammo'
    end

    if drugItems()[name] then
        return 'drug'
    end

    return FOOD[name] and 'consumable' or 'object'
end

---------------------------------------------------------------------
-- Fichier lu par ox_inventory
---------------------------------------------------------------------

local function luaString(value)
    return (('%q'):format(value):gsub('\\\n', '\\n'))
end

local function vector(values)
    return ('vec3(%.3f, %.3f, %.3f)'):format(values[1], values[2], values[3])
end

-- Texte d'un objet dans data/lunatic_items.lua
local function chunk(row)
    local lines = {
        ('\t[%s] = {'):format(luaString(row.name)),
        ('\t\tlabel = %s,'):format(luaString(row.label)),
        ('\t\tweight = %d,'):format(row.weight),
        ('\t\tstack = %s,'):format(row.stack and 'true' or 'false'),
        ('\t\tclose = %s,'):format(row.close and 'true' or 'false'),
        ('\t\tdescription = %s,'):format(row.description ~= '' and luaString(row.description) or 'nil'),
        -- Expiration : l'objet se dégrade et ne s'utilise plus à 0 (minutes pour ox_inventory)
        ('\t\tdegrade = %s,'):format(row.expiration > 0 and tostring(row.expiration * 60) or 'false'),
    }

    local client = {}

    if row.image ~= '' then
        client[#client + 1] = ('image = %s'):format(luaString(row.image))
    end

    if row.category == 'consumable' or row.category == 'drug' then
        local status = {}

        if row.hunger > 0 then
            status[#status + 1] = ('hunger = %d'):format(row.hunger * 10000)
        end

        if row.thirst > 0 then
            status[#status + 1] = ('thirst = %d'):format(row.thirst * 10000)
        end

        client[#client + 1] = ('status = { %s }'):format(table.concat(status, ', '))

        local anim = ANIMS[row.anim]
        client[#client + 1] = anim and ('anim = { dict = %s, clip = %s }'):format(luaString(anim.dict), luaString(anim.clip)) or 'anim = false'

        local prop = PROPS[row.prop] or (row.prop ~= '' and { model = row.prop, pos = { 0.02, 0.02, -0.02 }, rot = { 0.0, 0.0, 0.0 } })
        client[#client + 1] = prop and ('prop = { model = %s, pos = %s, rot = %s }'):format(luaString(prop.model), vector(prop.pos), vector(prop.rot)) or 'prop = false'
        client[#client + 1] = ('usetime = %d'):format(row.usetime * 1000)
    end

    if #client > 0 then
        lines[#lines + 1] = ('\t\tclient = { %s },'):format(table.concat(client, ', '))
    end

    lines[#lines + 1] = ('\t\tlunatic = { category = %s, price = %d, premium = %s, permanent = %s },'):format(luaString(row.category), row.price, row.premium and 'true' or 'false', row.permanent and 'true' or 'false')
    lines[#lines + 1] = '\t},'

    return table.concat(lines, '\n')
end

local function chunks()
    local list = {}

    for name, row in pairs(rows) do
        list[name] = chunk(row)
    end

    return list
end

local function writeFile()
    local names = {}

    for name in pairs(rows) do
        names[#names + 1] = name
    end

    table.sort(names)

    local parts = { '-- Généré par lunatic_admin (tuile Items du panel staff). Ne pas modifier à la main : le panel réécrit ce fichier.', 'return {' }

    for _, name in ipairs(names) do
        parts[#parts + 1] = chunk(rows[name])
    end

    parts[#parts + 1] = '}'

    local text = table.concat(parts, '\n') .. '\n'

    -- Écriture vérifiée en relisant le fichier (le résultat de SaveResourceFile n'est pas fiable)
    SaveResourceFile('ox_inventory', 'data/lunatic_items.lua', text, -1)

    if LoadResourceFile('ox_inventory', 'data/lunatic_items.lua') == text then
        return true
    end

    -- Secours : copie dans lunatic_admin, que data/items.lua d'ox_inventory lit aussi
    SaveResourceFile(GetCurrentResourceName(), 'generated_items.lua', text, -1)

    if LoadResourceFile(GetCurrentResourceName(), 'generated_items.lua') == text then
        print("^3[lunatic_admin] Items : ox_inventory/data/lunatic_items.lua n'a pas pu être écrit, copie de secours dans lunatic_admin/generated_items.lua.^0")
        return true
    end

    print("^1[lunatic_admin] Items : impossible d'écrire le fichier des objets (ni dans ox_inventory/data, ni dans lunatic_admin). Vérifiez les droits d'écriture des dossiers sur l'hébergeur.^0")
    return false
end

-- Ce qu'ox_inventory a chargé : l'état de la base au démarrage du serveur (ou au redémarrage d'ox_inventory)
local function markApplied()
    applied = chunks()
    SetResourceKvp('items_applied', json.encode(applied))
end

local function pendingList()
    local list = {}
    local current = chunks()

    for name, text in pairs(current) do
        if applied[name] ~= text then
            list[#list + 1] = { name = name, label = rows[name].label, operation = applied[name] and 'modifié' or 'nouveau' }
        end
    end

    for name in pairs(applied) do
        if not current[name] then
            list[#list + 1] = { name = name, label = name, operation = 'supprimé' }
        end
    end

    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

---------------------------------------------------------------------
-- « Permanent » : l'objet ne quitte pas l'inventaire du joueur (ni jeté, ni donné, ni rangé)
---------------------------------------------------------------------

local function registerPermanentHook()
    if permanentHook then
        pcall(function() ox:removeHooks(permanentHook) end)
        permanentHook = nil
    end

    local filter, any = {}, false

    for name, row in pairs(rows) do
        if row.permanent then
            filter[name] = true
            any = true
        end
    end

    if not any then
        return
    end

    local found, id = pcall(function()
        return ox:registerHook('swapItems', function(payload)
            if payload.fromType == 'player' and (payload.toType ~= 'player' or payload.toInventory ~= payload.fromInventory) then
                TriggerClientEvent('esx:showNotification', payload.source, 'Cet objet ne peut pas quitter votre inventaire.', 'error')
                return false
            end
        end, { itemFilter = filter })
    end)

    permanentHook = found and id or nil
end

---------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------

local function load()
    rows = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_items`') or {}) do
        rows[row.name] = {
            name = row.name, category = row.category, label = row.label, weight = tonumber(row.weight) or 0, price = tonumber(row.price) or 0,
            image = row.image or '', prop = row.prop or '', anim = row.anim or '', premium = tonumber(row.premium) == 1, permanent = tonumber(row.permanent) == 1,
            hunger = tonumber(row.hunger) or 0, thirst = tonumber(row.thirst) or 0, expiration = tonumber(row.expiration) or 0, usetime = tonumber(row.usetime) or 3,
            description = row.description or '', stack = tonumber(row.stack) ~= 0, close = tonumber(row.close) ~= 0, created = tonumber(row.created) == 1,
        }
    end
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_items` (
            `name` VARCHAR(60) NOT NULL,
            `category` VARCHAR(20) NOT NULL DEFAULT 'object',
            `label` VARCHAR(60) NOT NULL,
            `weight` INT NOT NULL DEFAULT 0,
            `price` INT NOT NULL DEFAULT 0,
            `image` VARCHAR(255) NOT NULL DEFAULT '',
            `prop` VARCHAR(60) NOT NULL DEFAULT '',
            `anim` VARCHAR(20) NOT NULL DEFAULT '',
            `premium` TINYINT NOT NULL DEFAULT 0,
            `permanent` TINYINT NOT NULL DEFAULT 0,
            `hunger` INT NOT NULL DEFAULT 0,
            `thirst` INT NOT NULL DEFAULT 0,
            `expiration` INT NOT NULL DEFAULT 0,
            `usetime` INT NOT NULL DEFAULT 3,
            `description` VARCHAR(200) NOT NULL DEFAULT '',
            `stack` TINYINT NOT NULL DEFAULT 1,
            `close` TINYINT NOT NULL DEFAULT 1,
            `created` TINYINT NOT NULL DEFAULT 0,
            `updated_by` VARCHAR(80) NOT NULL DEFAULT '',
            `updated_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    load()

    -- Démarrage du serveur : ox_inventory vient de lire le fichier. Simple redémarrage du panel : on garde l'état connu.
    local saved = GetResourceKvpString('items_applied')

    if GetGameTimer() < 600000 or not saved then
        writeFile()
        markApplied()
    else
        local ok, value = pcall(json.decode, saved)
        applied = ok and type(value) == 'table' and value or {}
    end

    registerPermanentHook()
end)

-- ox_inventory relancé : il a relu le fichier
AddEventHandler('onResourceStart', function(resource)
    if resource == 'ox_inventory' then
        markApplied()
        SetTimeout(2000, registerPermanentHook)
    end
end)

-- Prix de base d'un objet (proposé par défaut dans les magasins)
function ItemsCatalog.price(name)
    local row = rows[name]
    return row and row.price or 0
end

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function guard(actor)
    return Ranks.hasPermission(actor, 'items.manage')
end

Panel.actions['items.list'] = function(_, actor)
    if not guard(actor) then
        return denied()
    end

    local list, seen = {}, {}
    local pending = {}

    for _, entry in ipairs(pendingList()) do
        pending[entry.name] = entry.operation
    end

    for name, item in pairs(ox:Items() or {}) do
        if name ~= 'cash' then
            local row = rows[name]
            seen[name] = true
            list[#list + 1] = {
                name = name, label = row and row.label or item.label or name, category = categoryOf(name, item),
                image = row and row.image or '', modified = row ~= nil, created = row and row.created or false, pending = pending[name],
            }
        end
    end

    -- Objets créés dans le panel, pas encore chargés par ox_inventory
    for name, row in pairs(rows) do
        if not seen[name] then
            list[#list + 1] = { name = name, label = row.label, category = row.category, image = row.image, modified = true, created = row.created, pending = pending[name] or 'nouveau' }
        end
    end

    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)

    local anims, props = {}, {}

    for id, anim in pairs(ANIMS) do
        anims[#anims + 1] = { id = id, label = anim.label }
    end

    for id, prop in pairs(PROPS) do
        props[#props + 1] = { id = id, label = prop.label, model = prop.model }
    end

    table.sort(anims, function(a, b) return a.label < b.label end)
    table.sort(props, function(a, b) return a.label < b.label end)

    return { ok = true, silent = true, items = list, categories = CATEGORIES, pending = pendingList(), anims = anims, props = props }
end

-- Fiche d'un objet : celle du panel, sinon les valeurs d'ox_inventory (le jeu du staff donne la partie client)
Panel.actions['items.info'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local name = type(data.name) == 'string' and data.name or ''
    local row = rows[name]

    if row then
        local copy = json.decode(json.encode(row))
        copy.loaded = ox:Items(name) ~= nil
        return { ok = true, silent = true, item = copy }
    end

    local item = ox:Items(name)

    if not item then
        return Panel.fail('Objet introuvable.')
    end

    local info = {
        name = name, category = categoryOf(name, item), label = item.label or name, weight = math.floor(tonumber(item.weight) or 0), price = 0,
        image = '', prop = '', anim = '', premium = false, permanent = false, hunger = 0, thirst = 0,
        expiration = item.degrade and math.floor(item.degrade / 60) or 0, usetime = 3, description = item.description or '',
        stack = item.stack ~= false, close = item.close ~= false, created = false, loaded = true, weapon = item.weapon == true,
    }

    -- Partie client (image, faim, soif, animation, objet en main) : lue dans le jeu du staff
    local ok, client = pcall(lib.callback.await, 'lunatic_admin:itemClientInfo', src, name)

    if ok and type(client) == 'table' then
        info.hunger = math.floor((client.hunger or 0) / 10000)
        info.thirst = math.floor((client.thirst or 0) / 10000)
        info.usetime = math.max(1, math.floor((client.usetime or 3000) / 1000))

        for id, anim in pairs(ANIMS) do
            if client.animDict == anim.dict then
                info.anim = id
            end
        end

        for id, prop in pairs(PROPS) do
            if client.propModel == prop.model or client.propModel == joaat(prop.model) or client.propName == id then
                info.prop = id
            end
        end
    end

    return { ok = true, silent = true, item = info }
end

local function readItem(data, existing)
    local name = type(data.name) == 'string' and data.name or ''
    local category = EDITABLE[data.category] and data.category or nil
    local label = cleanText(data.label, 1, LIMITS.label)
    local description = cleanText(data.description, 0, LIMITS.description)
    local image = cleanText(data.image, 0, 255)
    local prop = type(data.prop) == 'string' and data.prop or ''
    local anim = type(data.anim) == 'string' and data.anim or ''

    if not name:match('^[%w_%-]+$') or #name > 60 then
        return nil, 'ID invalide : lettres, chiffres, _ et - (60 max).'
    end

    if not category then
        return nil, 'Catégorie invalide.'
    end

    if not label or not description or not image then
        return nil, 'Label (60 max), description (200 max) ou image (255 max) invalide.'
    end

    if prop ~= '' and not PROPS[prop] and not prop:match('^[%w_]+$') then
        return nil, 'Objet en main invalide.'
    end

    if anim ~= '' and not ANIMS[anim] then
        return nil, 'Animation inconnue.'
    end

    local row = {
        name = name, category = category, label = label, description = description, image = image, prop = prop, anim = anim,
        weight = whole(data.weight, 0, LIMITS.weight), price = whole(data.price, 0, LIMITS.price),
        hunger = whole(data.hunger, 0, 100), thirst = whole(data.thirst, 0, 100),
        expiration = whole(data.expiration, 0, LIMITS.expiration), usetime = whole(data.usetime, 1, LIMITS.usetime),
        premium = data.premium == true, permanent = data.permanent == true, stack = data.stack ~= false, close = data.close ~= false,
        created = existing and existing.created or false,
    }

    if not row.weight or not row.price or not row.hunger or not row.thirst or not row.expiration or not row.usetime then
        return nil, ('Poids (0-%d g), prix, faim et soif (0-100 %%), expiration (0-%d h) ou durée (1-%d s) invalide.'):format(LIMITS.weight, LIMITS.expiration, LIMITS.usetime)
    end

    return row
end

local function store(src, row)
    MySQL.query.await([[
        INSERT INTO `lunatic_items` (`name`, `category`, `label`, `weight`, `price`, `image`, `prop`, `anim`, `premium`, `permanent`, `hunger`, `thirst`, `expiration`, `usetime`, `description`, `stack`, `close`, `created`, `updated_by`, `updated_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `category` = VALUES(`category`), `label` = VALUES(`label`), `weight` = VALUES(`weight`), `price` = VALUES(`price`),
            `image` = VALUES(`image`), `prop` = VALUES(`prop`), `anim` = VALUES(`anim`), `premium` = VALUES(`premium`), `permanent` = VALUES(`permanent`),
            `hunger` = VALUES(`hunger`), `thirst` = VALUES(`thirst`), `expiration` = VALUES(`expiration`), `usetime` = VALUES(`usetime`),
            `description` = VALUES(`description`), `stack` = VALUES(`stack`), `close` = VALUES(`close`), `updated_by` = VALUES(`updated_by`), `updated_at` = VALUES(`updated_at`)
    ]], {
        row.name, row.category, row.label, row.weight, row.price, row.image, row.prop, row.anim, row.premium and 1 or 0, row.permanent and 1 or 0,
        row.hunger, row.thirst, row.expiration, row.usetime, row.description, row.stack and 1 or 0, row.close and 1 or 0, row.created and 1 or 0,
        Staff.displayName(src), os.time(),
    })

    load()

    if not writeFile() then
        return Panel.fail("Enregistré, mais le fichier d'ox_inventory n'a pas pu être écrit (voir la console).")
    end

    registerPermanentHook()
    return nil
end

Panel.actions['items.save'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local name = type(data.name) == 'string' and data.name or ''
    local existing = rows[name]
    local creating = data.create == true

    if creating and (existing or ox:Items(name)) then
        return Panel.fail(('Un objet « %s » existe déjà.'):format(name))
    end

    if not creating and not existing and not ox:Items(name) then
        return Panel.fail('Objet introuvable.')
    end

    local row, err = readItem(data, existing)

    if not row then
        return Panel.fail(err)
    end

    row.created = creating or (existing and existing.created) or false

    local failure = store(src, row)

    if failure then
        return failure
    end

    Logs.add(src, 'items.save', nil, { item = name, label = row.label, operation = creating and 'add' or 'edit' })
    return { ok = true, silent = true }
end

Panel.actions['items.duplicate'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local target = type(data.target) == 'string' and data.target or ''

    if rows[target] or ox:Items(target) then
        return Panel.fail(('Un objet « %s » existe déjà.'):format(target))
    end

    local source = type(data.item) == 'table' and data.item or nil

    if not source then
        return Panel.fail('Objet à dupliquer introuvable.')
    end

    source.name = target
    local row, err = readItem(source, nil)

    if not row then
        return Panel.fail(err)
    end

    row.created = true

    local failure = store(src, row)

    if failure then
        return failure
    end

    Logs.add(src, 'items.save', nil, { item = target, label = row.label, operation = ('copie de %s'):format(tostring(data.name)) })
    return { ok = true, silent = true }
end

-- Objet créé dans le panel : supprimé. Objet de base : retour à sa définition d'origine (items.lua).
Panel.actions['items.delete'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local row = rows[type(data.name) == 'string' and data.name or '']

    if not row then
        return Panel.fail("Cet objet n'a pas été modifié dans le panel.")
    end

    MySQL.update.await('DELETE FROM `lunatic_items` WHERE `name` = ?', { row.name })
    load()
    writeFile()
    registerPermanentHook()
    Logs.add(src, 'items.delete', nil, { item = row.name, label = row.label, operation = row.created and 'delete' or 'reset' })

    return { ok = true, silent = true, created = row.created }
end

Panel.actions['items.give'] = function(src, actor, data)
    if not guard(actor) then
        return denied()
    end

    local name = type(data.name) == 'string' and data.name or ''
    local count = whole(data.count, 1, 10000)
    local target = tonumber(data.serverId)

    if not ox:Items(name) then
        return Panel.fail("Cet objet n'est pas encore en jeu : il le sera au prochain redémarrage du serveur.")
    end

    if not count then
        return Panel.fail('Quantité : de 1 à 10 000.')
    end

    if not target or not GetPlayerName(target) then
        return Panel.fail('Joueur introuvable.')
    end

    if not ox:CanCarryItem(target, name, count) then
        return Panel.fail("Le joueur n'a pas assez de place.")
    end

    ox:AddItem(target, name, count)
    Logs.add(src, 'items.give', target, { item = name, count = count })

    return { ok = true, silent = true }
end

print("[lunatic_admin] Module Items chargé.")
