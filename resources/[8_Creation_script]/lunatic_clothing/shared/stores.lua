-- Magasins et prix communs au client et au serveur : réglages du panel (GlobalState.lunaticClothing), sinon la config.

-- Magasins ouverts : ceux du panel s'il en a, sinon ceux de la config (tous ouverts, toutes les pages)
function ClothingStores()
    local saved = GlobalState.lunaticClothing
    local list = {}

    if type(saved) == 'table' and type(saved.stores) == 'table' and #saved.stores > 0 then
        for _, store in ipairs(saved.stores) do
            if store.enabled ~= false then
                list[#list + 1] = store
            end
        end

        return list
    end

    for _, store in ipairs(Config.Stores) do
        list[#list + 1] = store
    end

    return list
end

-- Catégorie par clé (jacket, pants…), avec son groupe
local categories = {}

for _, group in ipairs(Config.Groups) do
    for _, category in ipairs(group.categories) do
        categories[category.key] = category
    end
end

function ClothingCategory(key)
    return categories[key]
end

-- Prix d'une pièce : réglage du panel, sinon prix par défaut de la config
function ClothingPrice(key)
    local saved = GlobalState.lunaticClothing
    local price = type(saved) == 'table' and type(saved.prices) == 'table' and tonumber(saved.prices[key])

    if price then
        return math.max(0, math.floor(price))
    end

    return categories[key] and categories[key].price or 0
end

-- Page activée dans un magasin (toutes par défaut)
function ClothingPageOn(store, page)
    return type(store.pages) ~= 'table' or store.pages[page] ~= false
end
