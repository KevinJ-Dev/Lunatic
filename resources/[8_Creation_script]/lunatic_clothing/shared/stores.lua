-- Réglages communs au client et au serveur : ceux du panel (GlobalState.lunaticClothing), sinon la config.

local function saved()
    local value = GlobalState.lunaticClothing
    return type(value) == 'table' and value or {}
end

-- Zone du magasin complétée des valeurs par défaut (rayon, marqueur, PNJ)
local function withDefaults(store)
    local copy = {}

    for key, value in pairs(store) do
        copy[key] = value
    end

    copy.radius = tonumber(store.radius) or Config.StoreDefaults.radius
    copy.marker = store.marker == nil and Config.StoreDefaults.marker or store.marker == true
    copy.ped = type(store.ped) == 'string' and store.ped or Config.StoreDefaults.ped
    return copy
end

-- Magasins ouverts : ceux du panel s'il en a, sinon ceux de la config
function ClothingStores()
    local list = {}
    local stores = type(saved().stores) == 'table' and #saved().stores > 0 and saved().stores or Config.Stores

    for _, store in ipairs(stores) do
        if store.enabled ~= false then
            list[#list + 1] = withDefaults(store)
        end
    end

    return list
end

-- Enseigne par clé : celles du panel s'il en a, sinon celles de la config
function ClothingBrand(key)
    local brands = saved().brands

    if type(brands) == 'table' and #brands > 0 then
        for _, brand in ipairs(brands) do
            if brand.key == key then
                return brand
            end
        end

        return brands[1]
    end

    local brand = Config.Brands[key] and key or Config.BrandOrder[1]
    local entry = Config.Brands[brand]
    return {
        key = brand, label = entry.label, color = entry.color, image = entry.image or '', showText = entry.showText ~= false,
        blip = entry.blip, coef = entry.coef or 1.0, exclude = entry.exclude or {}, textColor = entry.textColor, flat = entry.flat == true,
        kind = entry.kind or 'clothing',
    }
end

-- Type d'une enseigne : 'clothing' (vêtements), 'barber' ou 'tattoo'
function ClothingBrandKind(brand)
    local kind = type(brand) == 'table' and brand.kind
    return (kind == 'barber' or kind == 'tattoo') and kind or 'clothing'
end

-- Groupes de la barre du bas d'un type d'enseigne
function ClothingGroupsOf(kind)
    return kind == 'barber' and Config.BarberGroups or kind == 'tattoo' and Config.TattooGroups or Config.Groups
end

-- Tatouages du jeu par zone GTA : liste d'illenium-appearance (shared/tattoos.lua) lue sans la copier
local tattooList, tattooIndex = nil, nil

function ClothingTattoos()
    if tattooList then
        return tattooList
    end

    local raw = LoadResourceFile('illenium-appearance', 'shared/tattoos.lua')
    local env = { Config = {} }
    local chunk = raw and load(raw, '@illenium-appearance/shared/tattoos.lua', 't', env)

    if not chunk or not pcall(chunk) or type(env.Config.Tattoos) ~= 'table' then
        return {}
    end

    tattooList, tattooIndex = env.Config.Tattoos, {}

    for zone, list in pairs(tattooList) do
        tattooIndex[zone] = {}

        for _, tattoo in ipairs(list) do
            tattooIndex[zone][tattoo.name] = tattoo
        end
    end

    return tattooList
end

-- Tatouage par zone et nom (ex. ZONE_TORSO, TAT_AR_000)
function ClothingTattoo(zone, name)
    ClothingTattoos()
    return tattooIndex and tattooIndex[zone] and tattooIndex[zone][name] or nil
end

local categories = {}

-- Catégorie vendue par l'enseigne (et de son type : un barbier ne vend pas de vêtements)
function ClothingBrandSells(brand, key)
    local category = categories[key]
    return category ~= nil and (category.shop or 'clothing') == ClothingBrandKind(brand)
        and (type(brand.exclude) ~= 'table' or brand.exclude[key] ~= true)
end

-- Prix d'une pièce dans une enseigne : prix de la fiche (ou de la catégorie) multiplié par le coefficient de l'enseigne
function ClothingBrandPrice(brand, base)
    return math.max(0, math.floor((tonumber(base) or 0) * (tonumber(brand.coef) or 1.0) + 0.5))
end

-- Catégorie par clé (jacket, pants… ; hair, beard… chez le barbier, marquées shop = 'barber')
for _, group in ipairs(Config.Groups) do
    for _, category in ipairs(group.categories) do
        categories[category.key] = category
    end
end

for _, kind in ipairs({ 'barber', 'tattoo' }) do
    for _, group in ipairs(ClothingGroupsOf(kind)) do
        for _, category in ipairs(group.categories) do
            category.shop = kind
            categories[category.key] = category
        end
    end
end

function ClothingCategory(key)
    return categories[key]
end

-- Prix d'une pièce : réglage du panel, sinon prix par défaut de la config
function ClothingPrice(key)
    local price = type(saved().prices) == 'table' and tonumber(saved().prices[key])

    if price then
        return math.max(0, math.floor(price))
    end

    return categories[key] and categories[key].price or 0
end

-- Page activée dans un magasin (toutes par défaut)
function ClothingPageOn(store, page)
    return type(store.pages) ~= 'table' or store.pages[page] ~= false
end

-- Tenues prêt-à-porter créées par le staff
function ClothingReady()
    return type(saved().ready) == 'table' and saved().ready or {}
end

-- Tenue vendue dans cette enseigne (aucune enseigne cochée : partout)
function ClothingReadyIn(outfit, brand)
    return type(outfit.brands) ~= 'table' or next(outfit.brands) == nil or outfit.brands[brand] == true
end

function ClothingMaxOutfits()
    return tonumber(saved().maxOutfits) or Config.MaxOutfits
end
