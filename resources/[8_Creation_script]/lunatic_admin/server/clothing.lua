-- Tuile Autres → Magasins de vêtements (jeu : lunatic_clothing) : enseignes (bannière du menu), magasins (nom, enseigne,
-- zone, marqueur, PNJ, blip, pages de l'accueil), prix d'une pièce par catégorie, tenues prêt-à-porter et nombre de
-- tenues enregistrables. KVP 'clothing_shops', publié dans GlobalState.lunaticClothing.
-- Sans magasin ni enseigne réglés ici, ceux de la config de lunatic_clothing servent.

local STORES_MAX, BRANDS_MAX, READY_MAX, PRICE_MAX = 40, 20, 60, 1000000
local PAGES = { 'catalogue', 'ready', 'outfits', 'favorites' }

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les magasins de vêtements.")
end

local function allowed(actor)
    return Ranks.hasPermission(actor, 'others.manage')
end

local saved = GetResourceKvpString('clothing_shops')
local settings = saved and json.decode(saved) or {}

local function publish()
    GlobalState.lunaticClothing = {
        stores = settings.stores or {}, prices = settings.prices or {}, brands = settings.brands or {},
        ready = settings.ready or {}, maxOutfits = settings.maxOutfits,
    }
end

publish()

-- Enseignes, catégories, prix et magasins par défaut (lunatic_clothing), vides s'il ne tourne pas
local function defaults()
    local empty = { stores = {}, brands = {}, categories = {}, prices = {}, storeDefaults = {}, maxOutfits = 10 }

    if GetResourceState('lunatic_clothing') ~= 'started' then
        return empty
    end

    local ok, value = pcall(function() return exports.lunatic_clothing:getDefaults() end)
    return ok and type(value) == 'table' and value or empty
end

-- Enseignes ajoutées plus tard à la config de lunatic_clothing (ex. Vangelico) : ajoutées une seule fois aux enseignes
-- déjà enregistrées, avec leurs magasins. Une enseigne supprimée ensuite ne revient pas (settings.offered).
local ORIGINAL_BRANDS = { 'binco', 'suburban', 'ponsonbys', 'discount' }

local function offerNewBrands()
    if type(settings.brands) ~= 'table' or #settings.brands == 0 then
        return
    end

    local base = defaults()

    if not base.brands or #base.brands == 0 then
        return
    end

    if type(settings.offered) ~= 'table' then
        settings.offered = {}

        for _, key in ipairs(ORIGINAL_BRANDS) do
            settings.offered[key] = true
        end
    end

    local present, changed = {}, false

    for _, brand in ipairs(settings.brands) do
        present[brand.key] = true
        settings.offered[brand.key] = true
    end

    for _, brand in ipairs(base.brands) do
        if not settings.offered[brand.key] then
            settings.offered[brand.key] = true
            changed = true

            if not present[brand.key] then
                settings.brands[#settings.brands + 1] = brand

                if type(settings.stores) == 'table' and #settings.stores > 0 then
                    for _, store in ipairs(base.stores or {}) do
                        if store.brand == brand.key then
                            settings.stores[#settings.stores + 1] = store
                        end
                    end
                end
            end
        end
    end

    if changed then
        SetResourceKvp('clothing_shops', json.encode(settings))
        publish()
    end
end

CreateThread(function()
    local timeout = GetGameTimer() + 120000

    while GetResourceState('lunatic_clothing') ~= 'started' and GetGameTimer() < timeout do
        Wait(2000)
    end

    Wait(1000)
    offerNewBrands()
end)

Panel.actions['clothing.get'] = function(_, actor)
    if not allowed(actor) then
        return denied()
    end

    offerNewBrands()

    return {
        ok = true, silent = true, stores = settings.stores or {}, prices = settings.prices or {}, brands = settings.brands or {},
        ready = settings.ready or {}, maxOutfits = settings.maxOutfits, defaults = defaults(),
    }
end

-- Tenue portée par le staff (pour le prêt-à-porter)
Panel.actions['clothing.capture'] = function(src, actor)
    if not allowed(actor) then
        return denied()
    end

    if GetResourceState('lunatic_clothing') ~= 'started' then
        return Panel.fail('lunatic_clothing ne tourne pas.')
    end

    local outfit = lib.callback.await('lunatic_clothing:capture', src)

    if type(outfit) ~= 'table' or type(outfit.pieces) ~= 'table' then
        return Panel.fail('Tenue illisible.')
    end

    return { ok = true, silent = true, sex = outfit.sex == 'female' and 'female' or 'male', pieces = outfit.pieces }
end

local function readBrands(list, categories)
    if type(list) ~= 'table' or #list > BRANDS_MAX then
        return nil, ('Enseignes : %d au maximum.'):format(BRANDS_MAX)
    end

    local brands, keys = {}, {}

    for index, brand in ipairs(list) do
        local key = type(brand) == 'table' and type(brand.key) == 'string' and brand.key:match('^[%l%d_]+$')
        local label = type(brand) == 'table' and Util.cleanText(brand.label, 1, 30)
        local color = type(brand) == 'table' and type(brand.color) == 'string' and brand.color:match('^#%x%x%x%x%x%x$')
        local image = type(brand) == 'table' and Util.cleanTextOrEmpty(brand.image, 0, 300)
        local blip = type(brand) == 'table' and Util.whole(brand.blip or 0, 0, 85)
        local coef = type(brand) == 'table' and tonumber(brand.coef or 1)
        local rawColor = type(brand) == 'table' and brand.textColor or nil
        local textColor = (rawColor == nil or rawColor == '') and '' or type(rawColor) == 'string' and rawColor:match('^#%x%x%x%x%x%x$')

        if not key or #key > 20 or keys[key] then
            return nil, ('Enseigne %d : identifiant invalide ou en double.'):format(index)
        elseif not label then
            return nil, ('Enseigne %d : nom de 1 à 30 caractères.'):format(index)
        elseif not color then
            return nil, ('Enseigne %d : couleur invalide (ex. #f7931e).'):format(index)
        elseif not image or image:find('[%s"()]') or image:find("'") then
            return nil, ('Enseigne %d : image invalide (lien https ou clé de la tuile Images).'):format(index)
        elseif not blip then
            return nil, ('Enseigne %d : couleur de blip de 0 à 85.'):format(index)
        elseif not coef or coef < 0.1 or coef > 10 then
            return nil, ('Enseigne %d : coefficient de prix de 0,1 à 10.'):format(index)
        elseif not textColor then
            return nil, ('Enseigne %d : couleur du nom invalide (ex. #d9b45a, vide : blanc).'):format(index)
        end

        -- Catégories non vendues (clés connues seulement)
        local exclude = {}

        for category, off in pairs(type(brand.exclude) == 'table' and brand.exclude or {}) do
            if off == true and categories[category] then
                exclude[category] = true
            end
        end

        keys[key] = true
        brands[#brands + 1] = {
            key = key, label = label, color = color, image = image, showText = brand.showText ~= false, blip = blip,
            coef = math.floor(coef * 100 + 0.5) / 100, exclude = exclude, textColor = textColor, flat = brand.flat == true,
            kind = brand.kind == 'barber' and 'barber' or 'clothing',
        }
    end

    return brands, keys
end

local function readStores(list, brandKeys)
    if type(list) ~= 'table' or #list > STORES_MAX then
        return nil, ('Magasins : %d au maximum.'):format(STORES_MAX)
    end

    local stores, active = {}, 0

    for index, store in ipairs(list) do
        local label = type(store) == 'table' and Util.cleanText(store.label, 2, 40)
        local coords = type(store) == 'table' and Util.position(store)
        local radius = type(store) == 'table' and tonumber(store.radius)
        local ped = type(store) == 'table' and Util.cleanTextOrEmpty(store.ped, 0, 40)

        if not label then
            return nil, ('Magasin %d : nom de 2 à 40 caractères.'):format(index)
        elseif not coords then
            return nil, ('Magasin %d : position invalide (« Définir position » en jeu).'):format(index)
        elseif not brandKeys[store.brand] then
            return nil, ('Magasin %d : enseigne inconnue.'):format(index)
        elseif not radius or radius < 1 or radius > 30 then
            return nil, ('Magasin %d : rayon de la zone de 1 à 30 m.'):format(index)
        elseif not ped or (ped ~= '' and not ped:match('^[%w_]+$')) then
            return nil, ('Magasin %d : modèle de PNJ invalide (ex. s_f_y_shop_mid, vide pour aucun).'):format(index)
        end

        local pages = {}

        for _, page in ipairs(PAGES) do
            pages[page] = type(store.pages) ~= 'table' or store.pages[page] ~= false
        end

        local enabled = store.enabled ~= false
        active = active + (enabled and 1 or 0)
        stores[#stores + 1] = {
            label = label, brand = store.brand, x = coords.x, y = coords.y, z = coords.z, h = coords.h, enabled = enabled,
            blip = store.blip == true, radius = math.floor(radius * 2 + 0.5) / 2, marker = store.marker ~= false, ped = ped, pages = pages,
        }
    end

    if #stores > 0 and active == 0 then
        return nil, 'Magasins : ouvrez-en au moins un.'
    end

    return stores
end

-- Pièces d'une tenue : { clé de catégorie = { modèle, couleur } }
local function readPieces(pieces, categories)
    local list, count = {}, 0

    for key, value in pairs(type(pieces) == 'table' and pieces or {}) do
        local category = categories[key]
        local drawable = category and type(value) == 'table' and Util.whole(value[1], category.kind == 'prop' and -1 or 0, 3000)
        local texture = drawable and Util.whole(value[2] or 0, 0, 255)

        if texture then
            list[key] = { drawable, texture }
            count = count + 1
        end
    end

    return count > 0 and list or nil
end

local function readReady(list, brandKeys, categories)
    if type(list) ~= 'table' or #list > READY_MAX then
        return nil, ('Prêt-à-porter : %d tenues au maximum.'):format(READY_MAX)
    end

    local ready = {}

    for index, outfit in ipairs(list) do
        local label = type(outfit) == 'table' and Util.cleanText(outfit.label, 2, 30)
        local price = type(outfit) == 'table' and Util.whole(outfit.price, 0, PRICE_MAX)
        local pieces = type(outfit) == 'table' and readPieces(outfit.pieces, categories)
        local id = type(outfit) == 'table' and type(outfit.id) == 'string' and outfit.id:match('^[%w_]+$')

        if not label then
            return nil, ('Tenue %d : nom de 2 à 30 caractères.'):format(index)
        elseif not price then
            return nil, ('Tenue « %s » : prix de 0 à %d.'):format(label, PRICE_MAX)
        elseif not pieces or not id then
            return nil, ('Tenue « %s » : pièces illisibles, reprenez la tenue.'):format(label)
        end

        local brands = {}

        for key, on in pairs(type(outfit.brands) == 'table' and outfit.brands or {}) do
            if on == true and brandKeys[key] then
                brands[key] = true
            end
        end

        ready[#ready + 1] = { id = id, label = label, price = price, sex = outfit.sex == 'female' and 'female' or 'male', brands = brands, pieces = pieces }
    end

    return ready
end

-- Gestion du catalogue en jeu (lunatic_clothing) : fiches des pièces, prix par défaut, photos
Panel.actions['clothing.catalogue'] = function(src, actor)
    if not allowed(actor) then
        return denied()
    end

    local ok, started = pcall(function() return exports.lunatic_clothing:startCatalogueSession(src) end)

    if not ok or not started then
        return Panel.fail('lunatic_clothing ne tourne pas.')
    end

    return { ok = true, silent = true }
end

-- Prix par défaut d'une catégorie modifié depuis la gestion du catalogue (lunatic_clothing a vérifié la session)
exports('setClothingPrice', function(key, price)
    price = Util.whole(price, 0, PRICE_MAX)

    if type(key) ~= 'string' or not key:match('^[%l_]+$') or not price then
        return false
    end

    settings.prices = settings.prices or {}
    settings.prices[key] = price
    SetResourceKvp('clothing_shops', json.encode(settings))
    publish()
    return true
end)

Panel.actions['clothing.save'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    if type(data) ~= 'table' then
        return Panel.fail('Réglages invalides.')
    end

    local base = defaults()
    local categories = {}

    for _, category in ipairs(base.categories or {}) do
        categories[category.key] = category
    end

    local brands, brandKeys = readBrands(data.brands, categories)

    if not brands then
        return Panel.fail(brandKeys)
    end

    if #brands == 0 then
        return Panel.fail('Gardez au moins une enseigne.')
    end

    local stores, storeError = readStores(data.stores, brandKeys)

    if not stores then
        return Panel.fail(storeError)
    end

    local ready, readyError = readReady(data.ready, brandKeys, categories)

    if not ready then
        return Panel.fail(readyError)
    end

    local prices = {}

    for key, category in pairs(categories) do
        local value = type(data.prices) == 'table' and data.prices[key]

        if value ~= nil then
            local price = Util.whole(value, 0, PRICE_MAX)

            if not price then
                return Panel.fail(('Prix « %s » : de 0 à %d.'):format(category.label, PRICE_MAX))
            end

            prices[key] = price
        end
    end

    local maxOutfits = Util.whole(data.maxOutfits, 0, 50)

    if not maxOutfits then
        return Panel.fail('Mes tenues : de 0 à 50 par personnage.')
    end

    settings = { stores = stores, prices = prices, brands = brands, ready = ready, maxOutfits = maxOutfits, offered = settings.offered }
    SetResourceKvp('clothing_shops', json.encode(settings))
    publish()

    Logs.add(src, 'clothing.save', nil, { stores = #stores, brands = #brands, ready = #ready })
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Magasins de vêtements chargé.')
