-- Tuile Boutique (partie 1) : réglages de la boutique et des abonnements, statistiques, transactions.
--   - réglages en KVP 'shop', publiés dans GlobalState.lunaticShop (lus par la paie d'ESX et la future boutique joueur) ;
--   - l'aide de l'État des abonnements reste celle de la tuile Économie (même réglage, modifiable ici) ;
--   - avantages lus par les scripts : exports.lunatic_admin:getPremiumPerks(source).
-- Les achats (partie 3) s'enregistrent dans lunatic_shop_transactions (Shop.record).

Shop = {}

local TIERS = { 'premium', 'premium_plus' }
local CATEGORIES = { 'premium', 'premium_plus', 'vehicles', 'packs', 'weapons', 'credits' }

local DEFAULTS = {
    categories = { premium = true, premium_plus = true, vehicles = true, packs = true, weapons = true, credits = true },
    banners = {},
    notification = { enabled = false, title = 'Nouvelle offre', text = 'Découvrez les dernières nouveautés dans la boutique !', color = '#f2c26b', image = '', hours = 2, startedAt = 0 },
    credits = { name = 'Crédits', image = '' },
    tiers = {
        premium = { priceEuro = 10, priceCredits = 1000, includedCredits = 0, salaryMultiplier = 1.1, characters = 2, garageSlots = 5, farmMultiplier = 1.0, outfits = 10 },
        premium_plus = { priceEuro = 20, priceCredits = 2000, includedCredits = 0, salaryMultiplier = 1.25, characters = 3, garageSlots = 10, farmMultiplier = 1.25, outfits = 20 },
    },
}

-- Bornes des avantages (entiers, sauf les multiplicateurs)
local PERKS = {
    priceEuro = { 0, 1000 }, priceCredits = { 0, 10000000 }, includedCredits = { 0, 10000000 },
    salaryMultiplier = { 1, 5, true }, characters = { 1, 10 }, garageSlots = { 0, 100 }, farmMultiplier = { 1, 5, true }, outfits = { 0, 200 },
}

local LIMITS = { banners = 6, text = 120, title = 60, notification = 200, url = 255, hours = 168 }

local function copy(value)
    return json.decode(json.encode(value))
end

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer la boutique.")
end

local function now()
    return os.time()
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

local function cleanUrl(value)
    local url = cleanText(value, 0, LIMITS.url)

    if not url or url == '' then
        return url
    end

    return url:match('^https://[%w%-%.]+%.%a+/.*') and url or nil
end

local function cleanColor(value)
    return type(value) == 'string' and value:match('^#%x%x%x%x%x%x$') and value:lower() or nil
end

-- Garde les clés connues et complète les manquantes par les valeurs par défaut
local function merge(saved)
    local result = copy(DEFAULTS)

    if type(saved) ~= 'table' then
        return result
    end

    for _, key in ipairs(CATEGORIES) do
        if type(saved.categories) == 'table' and type(saved.categories[key]) == 'boolean' then
            result.categories[key] = saved.categories[key]
        end
    end

    if type(saved.banners) == 'table' then
        result.banners = saved.banners
    end

    for _, group in ipairs({ 'notification', 'credits' }) do
        if type(saved[group]) == 'table' then
            for key in pairs(result[group]) do
                if saved[group][key] ~= nil and type(saved[group][key]) == type(result[group][key]) then
                    result[group][key] = saved[group][key]
                end
            end
        end
    end

    for _, tier in ipairs(TIERS) do
        local perks = type(saved.tiers) == 'table' and saved.tiers[tier]

        if type(perks) == 'table' then
            for key in pairs(PERKS) do
                if tonumber(perks[key]) then
                    result.tiers[tier][key] = tonumber(perks[key])
                end
            end
        end
    end

    return result
end

local saved = GetResourceKvpString('shop')
local settings = merge(saved and json.decode(saved) or nil)

-- Notification de la boutique : visible pendant « hours » heures après son activation
local function notificationLive()
    local n = settings.notification
    return n.enabled and n.startedAt > 0 and now() < n.startedAt + n.hours * 3600
end

local function publish()
    local public = copy(settings)
    public.notification.live = notificationLive()
    public.notification.endsAt = public.notification.live and (settings.notification.startedAt + settings.notification.hours * 3600) or nil
    GlobalState.lunaticShop = public
end

publish()

local function store()
    SetResourceKvp('shop', json.encode(settings))
    publish()
end

-- Fin du compte à rebours de la notification
CreateThread(function()
    local wasLive = notificationLive()

    while true do
        Wait(30000)
        local live = notificationLive()

        if live ~= wasLive then
            wasLive = live
            publish()
        end
    end
end)

---@return string nom de la monnaie boutique (tuile Boutique)
function Shop.creditsName()
    return settings.credits.name ~= '' and settings.credits.name or Config.CreditsName
end

---------------------------------------------------------------------
-- Avantages des abonnements (lus par les autres scripts)
---------------------------------------------------------------------

---@return table|nil avantages de l'abonnement du joueur (nil sans abonnement)
function Shop.perksOf(src)
    local license = GetPlayerIdentifierByType(tonumber(src), 'license')
    local premium = license and Panel.premiumOf(license)

    if not premium then
        return nil
    end

    local perks = copy(settings.tiers[premium.tier] or {})
    perks.tier = premium.tier
    perks.allowance = Panel.allowances()[premium.tier] or 0
    return perks
end

exports('getPremiumPerks', function(src)
    return Shop.perksOf(src)
end)

---------------------------------------------------------------------
-- Transactions (achats en boutique, partie 3)
---------------------------------------------------------------------

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_shop_transactions` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `license` VARCHAR(60) NOT NULL,
            `name` VARCHAR(80) NOT NULL DEFAULT '',
            `category` VARCHAR(20) NOT NULL,
            `product` VARCHAR(80) NOT NULL,
            `amount` INT NOT NULL DEFAULT 0,
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_shop_transactions_category` (`category`),
            KEY `idx_lunatic_shop_transactions_license` (`license`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

---@param src number joueur
---@param category string premium | premium_plus | vehicles | packs | weapons | credits
---@param product string nom du produit
---@param amount number crédits dépensés
function Shop.record(src, category, product, amount)
    MySQL.insert('INSERT INTO `lunatic_shop_transactions` (`license`, `name`, `category`, `product`, `amount`, `created_at`) VALUES (?, ?, ?, ?, ?, ?)', {
        GetPlayerIdentifierByType(src, 'license') or '', Staff.displayName(src), category, product, math.floor(tonumber(amount) or 0), now(),
    })
end

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

Panel.actions['shop.info'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'shop.manage') then
        return denied()
    end

    local counts = {}

    for _, row in ipairs(MySQL.query.await('SELECT `category`, COUNT(*) AS `total` FROM `lunatic_shop_transactions` GROUP BY `category`') or {}) do
        counts[row.category] = tonumber(row.total)
    end

    local transactions = {}

    for _, row in ipairs(MySQL.query.await('SELECT `name`, `category`, `product`, `amount`, `created_at` FROM `lunatic_shop_transactions` ORDER BY `id` DESC LIMIT 200') or {}) do
        transactions[#transactions + 1] = { name = row.name, category = row.category, product = row.product, amount = tonumber(row.amount), created = tonumber(row.created_at) }
    end

    local view = copy(settings)
    view.notification.live = notificationLive()
    view.allowances = Panel.allowances()

    return {
        ok = true, silent = true, settings = view, transactions = transactions,
        stats = {
            credits = tonumber(MySQL.scalar.await('SELECT COALESCE(SUM(`balance`), 0) FROM `lunatic_admin_credits`')) or 0,
            subscriptions = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `lunatic_admin_premium` WHERE `expires_at` IS NULL OR `expires_at` > ?', { now() })) or 0,
            vehicles = counts.vehicles or 0,
            weapons = counts.weapons or 0,
        },
    }
end

local function readBanners(list)
    if type(list) ~= 'table' or #list > LIMITS.banners then
        return nil, ('%d bandeaux au maximum.'):format(LIMITS.banners)
    end

    local banners = {}

    for index, entry in ipairs(list) do
        local text = cleanText(entry.text, 1, LIMITS.text)
        local color = cleanColor(entry.color)
        local image = cleanUrl(entry.image)

        if not text then
            return nil, ('Bandeau n°%d : un texte de 1 à %d caractères.'):format(index, LIMITS.text)
        end

        if not color then
            return nil, ('Bandeau « %s » : couleur invalide.'):format(text)
        end

        if not image then
            return nil, ('Bandeau « %s » : image en lien https.'):format(text)
        end

        banners[#banners + 1] = { text = text, color = color, image = image, active = entry.active == true }
    end

    return banners
end

Panel.actions['shop.save'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'shop.manage') then
        return denied()
    end

    local updated = copy(settings)

    -- Catégories
    for _, key in ipairs(CATEGORIES) do
        if type(data.categories) == 'table' and type(data.categories[key]) == 'boolean' then
            updated.categories[key] = data.categories[key]
        end
    end

    -- Bandeaux
    local banners, err = readBanners(data.banners)

    if not banners then
        return Panel.fail(err)
    end

    updated.banners = banners

    -- Notification en jeu
    local n = type(data.notification) == 'table' and data.notification or {}
    local title = cleanText(n.title, 1, LIMITS.title)
    local text = cleanText(n.text, 0, LIMITS.notification)
    local color = cleanColor(n.color)
    local image = cleanUrl(n.image)
    local hours = tonumber(n.hours)

    if not title or not text then
        return Panel.fail(('Notification : titre de 1 à %d caractères, texte de %d au maximum.'):format(LIMITS.title, LIMITS.notification))
    end

    if not color or not image then
        return Panel.fail('Notification : couleur ou image (lien https) invalide.')
    end

    if not hours or hours ~= math.floor(hours) or hours < 1 or hours > LIMITS.hours then
        return Panel.fail(('Notification : durée de 1 à %d heures.'):format(LIMITS.hours))
    end

    local enabled = n.enabled == true
    -- Activée (ou durée changée) : le compte à rebours repart de maintenant
    local restart = enabled and (not settings.notification.enabled or hours ~= settings.notification.hours or not notificationLive())
    updated.notification = { enabled = enabled, title = title, text = text, color = color, image = image, hours = hours, startedAt = restart and now() or settings.notification.startedAt }

    -- Monnaie
    local credits = type(data.credits) == 'table' and data.credits or {}
    local name = cleanText(credits.name, 2, 20)
    local creditsImage = cleanUrl(credits.image)

    if not name or not creditsImage then
        return Panel.fail('Monnaie : nom de 2 à 20 caractères, image en lien https.')
    end

    updated.credits = { name = name, image = creditsImage }

    -- Abonnements
    for _, tier in ipairs(TIERS) do
        local perks = type(data.tiers) == 'table' and type(data.tiers[tier]) == 'table' and data.tiers[tier] or {}

        for key, bounds in pairs(PERKS) do
            local value = tonumber(perks[key])

            if not value or value < bounds[1] or value > bounds[2] or (not bounds[3] and value ~= math.floor(value)) then
                return Panel.fail(('%s : valeur invalide pour « %s » (%s à %s).'):format(Config.PremiumTiers[tier].label, key, bounds[1], bounds[2]))
            end

            updated.tiers[tier][key] = bounds[3] and math.floor(value * 100 + 0.5) / 100 or value
        end
    end

    -- Aide de l'État : réglage partagé avec la tuile Économie
    if type(data.allowances) == 'table' then
        local ok, message = Panel.setAllowances(data.allowances)

        if not ok then
            return Panel.fail(message)
        end
    end

    settings = updated
    store()

    Logs.add(src, 'shop.save', nil, { categories = settings.categories, banners = #settings.banners, notification = settings.notification.enabled })
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Boutique chargé.')
