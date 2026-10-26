-- Tuile Autres → Magasins de vêtements (jeu : lunatic_clothing) : magasins (nom, enseigne, position, blip, pages
-- proposées à l'accueil) et prix d'une pièce par catégorie. KVP 'clothing_shops', publié dans GlobalState.lunaticClothing.
-- Sans magasin réglé ici, ceux de la config de lunatic_clothing servent.

local STORES_MAX, PRICE_MAX = 40, 100000
local PAGES = { 'catalogue', 'ready', 'outfits', 'favorites' }

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les magasins de vêtements.")
end

local function allowed(actor)
    return Ranks.hasPermission(actor, 'others.manage')
end

local saved = GetResourceKvpString('clothing_shops')
local settings = saved and json.decode(saved) or {}
settings.stores = type(settings.stores) == 'table' and settings.stores or {}
settings.prices = type(settings.prices) == 'table' and settings.prices or {}

local function publish()
    GlobalState.lunaticClothing = { stores = settings.stores, prices = settings.prices }
end

publish()

-- Enseignes, catégories, prix et magasins par défaut (lunatic_clothing), vides s'il ne tourne pas
local function defaults()
    if GetResourceState('lunatic_clothing') ~= 'started' then
        return { stores = {}, brands = {}, categories = {}, prices = {} }
    end

    local ok, value = pcall(function() return exports.lunatic_clothing:getDefaults() end)
    return ok and type(value) == 'table' and value or { stores = {}, brands = {}, categories = {}, prices = {} }
end

Panel.actions['clothing.get'] = function(_, actor)
    if not allowed(actor) then
        return denied()
    end

    return { ok = true, silent = true, stores = settings.stores, prices = settings.prices, defaults = defaults() }
end

Panel.actions['clothing.save'] = function(src, actor, data)
    if not allowed(actor) then
        return denied()
    end

    if type(data) ~= 'table' or type(data.stores) ~= 'table' or #data.stores > STORES_MAX then
        return Panel.fail(('Magasins : %d au maximum.'):format(STORES_MAX))
    end

    local base = defaults()
    local brands = {}

    for _, brand in ipairs(base.brands or {}) do
        brands[brand.key] = true
    end

    local stores, active = {}, 0

    for index, store in ipairs(data.stores) do
        local label = type(store) == 'table' and Util.cleanText(store.label, 2, 40)
        local coords = type(store) == 'table' and Util.position(store)

        if not label then
            return Panel.fail(('Magasin %d : nom de 2 à 40 caractères.'):format(index))
        elseif not coords then
            return Panel.fail(('Magasin %d : position invalide (« Définir position » en jeu).'):format(index))
        elseif not brands[store.brand] then
            return Panel.fail(('Magasin %d : enseigne inconnue.'):format(index))
        end

        local pages = {}

        for _, page in ipairs(PAGES) do
            pages[page] = type(store.pages) ~= 'table' or store.pages[page] ~= false
        end

        local enabled = store.enabled ~= false
        active = active + (enabled and 1 or 0)
        stores[#stores + 1] = {
            label = label, brand = store.brand, x = coords.x, y = coords.y, z = coords.z, h = coords.h,
            enabled = enabled, blip = store.blip == true, pages = pages,
        }
    end

    if #stores > 0 and active == 0 then
        return Panel.fail('Magasins : ouvrez-en au moins un.')
    end

    local prices = {}

    for _, category in ipairs(base.categories or {}) do
        local value = type(data.prices) == 'table' and data.prices[category.key]

        if value ~= nil then
            local price = Util.whole(value, 0, PRICE_MAX)

            if not price then
                return Panel.fail(('Prix « %s » : de 0 à %d.'):format(category.label, PRICE_MAX))
            end

            prices[category.key] = price
        end
    end

    settings = { stores = stores, prices = prices }
    SetResourceKvp('clothing_shops', json.encode(settings))
    publish()

    Logs.add(src, 'clothing.save', nil, { stores = #stores })
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Magasins de vêtements chargé.')
