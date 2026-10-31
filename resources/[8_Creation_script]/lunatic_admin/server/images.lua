-- Tuile Images : catalogue central des visuels du serveur, et mugshots des personnages.
-- Deux sortes d'images :
--   - emplacements prévus par nos scripts (SLOTS) : seule l'URL change, « Supprimer » remet l'image d'origine ;
--   - images ajoutées par le staff : réutilisables dans les fiches (logos, bannières), supprimables.
-- Diffusé dans GlobalState.lunaticImages (clé -> URL) : appliqué en direct par le panel, lunatic_creator et lunatic_illegal.
-- Mugshots : photo du visage prise par le client du joueur (client/mugshots.lua), enregistrée en base (table lunatic_mugshots).

-- size : taille conseillée des images ajoutées dans la catégorie (le double de l'affichage, pour rester net)
local CATEGORIES = {
    { id = 'logo', label = 'Logo', size = '256 × 256 px, PNG transparent' },
    { id = 'banner', label = 'Bannière', size = '800 × 240 px (format 10:3)' },
    { id = 'header', label = 'Headers', size = '800 × 240 px (format 10:3)' },
    { id = 'notification', label = 'Notifications', size = '128 × 128 px, PNG transparent' },
    { id = 'character', label = 'Création perso', size = '1200 × 300 px (format 4:1)' },
    { id = 'interim', label = 'Job Center', size = '800 × 300 px (image), 128 × 128 px (logo)' },
    { id = 'other', label = 'Autres', size = 'Libre' },
}

local SLOTS = {
    { key = 'panel_logo', category = 'logo', label = 'Logo du panel staff', description = 'Barre du haut et pastille du panel réduit', default = 'nui://lunatic_admin/web/logo.png', size = '256 × 256 px, PNG transparent' },
    { key = 'creator_logo', category = 'character', label = 'Logo du créateur de personnage', description = 'En haut du panneau de création (lunatic_creator) ; masquable dans Autres > Création perso', default = 'nui://lunatic_creator/html/logo.png', size = '512 × 160 px, PNG transparent' },
    { key = 'creator_banner', category = 'character', label = 'Bannière du créateur de personnage', description = 'Fond du haut du panneau de création (vide : pas de bannière)', default = '', size = '1200 × 300 px (format 4:1)' },
    { key = 'tablet_logo', category = 'header', label = 'Logo de la tablette illégale', description = 'En haut à gauche de la tablette des crews (vide : pas de logo)', default = '', size = '256 × 256 px, PNG transparent' },
    { key = 'fuel_banner', category = 'banner', label = 'Bannière de la pompe à essence', description = 'En-tête du panneau des pompes à essence (vide : LTD rouge)', default = '', size = '680 × 180 px (format 4:1)' },
    { key = 'quick_banner', category = 'banner', label = 'Bannière du menu rapide staff', description = 'En-tête du menu rapide (F9) et de ses fenêtres de saisie (vide : dégradé violet)', default = '', size = '680 × 180 px (format 4:1)' },
    -- Job Center (lunatic_interim) : bannière du panneau, puis image et logo de chaque métier d'intérim
    { key = 'jobcenter_banner', category = 'interim', label = 'Bannière du Job Center', description = 'En-tête du panneau du Job Center (vide : bandeau Job Center / Intérim)', default = '', size = '800 × 190 px' },
    { key = 'interim_canadair', category = 'interim', label = "Job Center : Pilote de Canadair", description = 'Image de la fiche du métier (vide : couleur du métier)', default = '', size = '800 × 300 px' },
    { key = 'interim_logo_canadair', category = 'interim', label = "Job Center : logo Pilote de Canadair", description = 'Logo dans la grille du Job Center (vide : initiales sur la couleur du métier)', default = '', size = '128 × 128 px, PNG transparent' },
    { key = 'interim_pilot', category = 'interim', label = "Job Center : Pilote d'avion", description = 'Image de la fiche du métier (vide : couleur du métier)', default = '', size = '800 × 300 px' },
    { key = 'interim_logo_pilot', category = 'interim', label = "Job Center : logo Pilote d'avion", description = 'Logo dans la grille du Job Center (vide : initiales sur la couleur du métier)', default = '', size = '128 × 128 px, PNG transparent' },
    { key = 'interim_garbage', category = 'interim', label = "Job Center : Éboueur", description = 'Image de la fiche du métier (vide : couleur du métier)', default = '', size = '800 × 300 px' },
    { key = 'interim_logo_garbage', category = 'interim', label = "Job Center : logo Éboueur", description = 'Logo dans la grille du Job Center (vide : initiales sur la couleur du métier)', default = '', size = '128 × 128 px, PNG transparent' },
    { key = 'interim_miner', category = 'interim', label = "Job Center : Mineur", description = 'Image de la fiche du métier (vide : couleur du métier)', default = '', size = '800 × 300 px' },
    { key = 'interim_logo_miner', category = 'interim', label = "Job Center : logo Mineur", description = 'Logo dans la grille du Job Center (vide : initiales sur la couleur du métier)', default = '', size = '128 × 128 px, PNG transparent' },
    { key = 'interim_delivery', category = 'interim', label = "Job Center : Livreur", description = 'Image de la fiche du métier (vide : couleur du métier)', default = '', size = '800 × 300 px' },
    { key = 'interim_logo_delivery', category = 'interim', label = "Job Center : logo Livreur", description = 'Logo dans la grille du Job Center (vide : initiales sur la couleur du métier)', default = '', size = '128 × 128 px, PNG transparent' },
    { key = 'interim_hunter', category = 'interim', label = "Job Center : Chasseur", description = 'Image de la fiche du métier (vide : couleur du métier)', default = '', size = '800 × 300 px' },
    { key = 'interim_logo_hunter', category = 'interim', label = "Job Center : logo Chasseur", description = 'Logo dans la grille du Job Center (vide : initiales sur la couleur du métier)', default = '', size = '128 × 128 px, PNG transparent' },
    { key = 'interim_fuel', category = 'interim', label = "Job Center : Pompiste", description = 'Image de la fiche du métier (vide : couleur du métier)', default = '', size = '800 × 300 px' },
    { key = 'interim_logo_fuel', category = 'interim', label = "Job Center : logo Pompiste", description = 'Logo dans la grille du Job Center (vide : initiales sur la couleur du métier)', default = '', size = '128 × 128 px, PNG transparent' },
    { key = 'interim_gopostal', category = 'interim', label = "Job Center : Facteur (GoPostal)", description = 'Image de la fiche du métier (vide : couleur du métier)', default = '', size = '800 × 300 px' },
    { key = 'interim_logo_gopostal', category = 'interim', label = "Job Center : logo Facteur (GoPostal)", description = 'Logo dans la grille du Job Center (vide : initiales sur la couleur du métier)', default = '', size = '128 × 128 px, PNG transparent' },
    { key = 'interim_tram', category = 'interim', label = "Job Center : Conducteur de tramway", description = 'Image de la fiche du métier (vide : couleur du métier)', default = '', size = '800 × 300 px' },
    { key = 'interim_logo_tram', category = 'interim', label = "Job Center : logo Conducteur de tramway", description = 'Logo dans la grille du Job Center (vide : initiales sur la couleur du métier)', default = '', size = '128 × 128 px, PNG transparent' },
    { key = 'interim_train', category = 'interim', label = "Job Center : Conducteur de train", description = 'Image de la fiche du métier (vide : couleur du métier)', default = '', size = '800 × 300 px' },
    { key = 'interim_logo_train', category = 'interim', label = "Job Center : logo Conducteur de train", description = 'Logo dans la grille du Job Center (vide : initiales sur la couleur du métier)', default = '', size = '128 × 128 px, PNG transparent' },
    { key = 'interim_fisher', category = 'interim', label = "Job Center : Pêcheur", description = 'Image de la fiche du métier (vide : couleur du métier)', default = '', size = '800 × 300 px' },
    { key = 'interim_logo_fisher', category = 'interim', label = "Job Center : logo Pêcheur", description = 'Logo dans la grille du Job Center (vide : initiales sur la couleur du métier)', default = '', size = '128 × 128 px, PNG transparent' },
}

local MUGSHOT_MAX = 200000          -- taille maximale d'une photo encodée (caractères)
local MUGSHOT_PAGE = 48
local MUGSHOT_DELAY = 20000         -- délai après le chargement du personnage avant la photo automatique
local MUGSHOT_REQUEST_TIMEOUT = 60  -- secondes pendant lesquelles une photo demandée est acceptée

---@type table<string, table> images enregistrées par clé
local stored = {}
local slotByKey = {}

for index, slot in ipairs(SLOTS) do
    slot.order = index
    slotByKey[slot.key] = slot
end

local categoryIds = {}

for _, category in ipairs(CATEGORIES) do
    categoryIds[category.id] = true
end

local now = Util.now

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

local function publish()
    local map = {}

    for _, slot in ipairs(SLOTS) do
        local entry = stored[slot.key]
        map[slot.key] = entry and entry.url ~= '' and entry.url or slot.default
    end

    for key, entry in pairs(stored) do
        if not slotByKey[key] then
            map[key] = entry.url
        end
    end

    GlobalState.lunaticImages = map
end

exports('getImage', function(key)
    return (GlobalState.lunaticImages or {})[key]
end)

-- URL des images pour le panel (logo du panel)
table.insert(Panel.stateHooks, function(state)
    state.images = GlobalState.lunaticImages
end)

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_images` (
            `key` VARCHAR(60) NOT NULL,
            `category` VARCHAR(20) NOT NULL,
            `label` VARCHAR(60) NOT NULL,
            `description` VARCHAR(150) NOT NULL DEFAULT '',
            `url` VARCHAR(500) NOT NULL DEFAULT '',
            `updated_by` VARCHAR(80) NOT NULL DEFAULT '',
            `updated_at` BIGINT NOT NULL,
            PRIMARY KEY (`key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_mugshots` (
            `identifier` VARCHAR(60) NOT NULL,
            `image` MEDIUMTEXT NOT NULL,
            `updated_at` BIGINT NOT NULL,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_images`') or {}) do
        stored[row.key] = { key = row.key, category = row.category, label = row.label, description = row.description, url = row.url, updatedBy = row.updated_by, updatedAt = tonumber(row.updated_at) }
    end

    publish()
end)

publish()

---------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------

local cleanText = Util.cleanText

-- Adresse http(s) d'une image, 500 caractères maximum
local function cleanUrl(value)
    if type(value) ~= 'string' or #value > 500 or not value:match("^https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+$") then
        return nil
    end

    return value
end

local function newKey()
    local key

    repeat
        key = ('img_%d_%d'):format(now(), math.random(1000, 9999))
    until not stored[key] and not slotByKey[key]

    return key
end

local function entryOf(key)
    local slot = slotByKey[key]
    local entry = stored[key]

    if slot then
        return {
            key = key, slot = true, category = slot.category, label = slot.label, description = slot.description, size = slot.size,
            url = entry and entry.url ~= '' and entry.url or slot.default, default = slot.default, changed = entry ~= nil,
            updatedBy = entry and entry.updatedBy or nil, updatedAt = entry and entry.updatedAt or nil, order = slot.order,
        }
    end

    return entry and {
        key = key, slot = false, category = entry.category, label = entry.label, description = entry.description, url = entry.url,
        updatedBy = entry.updatedBy, updatedAt = entry.updatedAt, order = 1000,
    } or nil
end

---------------------------------------------------------------------
-- Catalogue
---------------------------------------------------------------------

local function mugshotCount()
    local row = MySQL.single.await('SELECT COUNT(*) AS `total` FROM `lunatic_mugshots`')
    return row and tonumber(row.total) or 0
end

Panel.actions['images.list'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'images.manage') then
        return denied()
    end

    local list = {}

    for _, slot in ipairs(SLOTS) do
        list[#list + 1] = entryOf(slot.key)
    end

    for key in pairs(stored) do
        if not slotByKey[key] then
            list[#list + 1] = entryOf(key)
        end
    end

    table.sort(list, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end

        return a.label:lower() < b.label:lower()
    end)

    return { ok = true, silent = true, categories = CATEGORIES, images = list, mugshots = mugshotCount() }
end

-- Images à choisir dans les fiches (logos, bannières) : tout membre du panel
Panel.actions['images.choices'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'panel.open') then
        return denied()
    end

    local list = {}

    for key, url in pairs(GlobalState.lunaticImages or {}) do
        local entry = entryOf(key)

        if entry and url:match('^https?://') then
            list[#list + 1] = { key = key, label = entry.label, category = entry.category, url = url }
        end
    end

    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    return { ok = true, silent = true, images = list, categories = CATEGORIES }
end

Panel.actions['images.save'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'images.manage') then
        return denied()
    end

    local url = cleanUrl(data.url)

    if not url then
        return Panel.fail("L'URL doit commencer par http:// ou https:// (500 caractères maximum).")
    end

    local key = data.key
    local slot = type(key) == 'string' and slotByKey[key]
    local label, description, category

    if slot then
        label, description, category = slot.label, slot.description, slot.category
    else
        if key ~= nil and not stored[key] then
            return Panel.fail('Image introuvable.')
        end

        label = cleanText(data.label, 1, 60)
        description = cleanText(data.description or '', 0, 150)
        category = categoryIds[data.category] and data.category

        if not label then
            return Panel.fail("Le nom doit faire entre 1 et 60 caractères.")
        end

        if not description then
            return Panel.fail('La description fait 150 caractères maximum.')
        end

        if not category then
            return Panel.fail('Catégorie inconnue.')
        end

        key = key or newKey()
    end

    local before = entryOf(key)
    local by = Staff.displayName(src)

    MySQL.query.await([[
        INSERT INTO `lunatic_images` (`key`, `category`, `label`, `description`, `url`, `updated_by`, `updated_at`) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `category` = VALUES(`category`), `label` = VALUES(`label`), `description` = VALUES(`description`),
            `url` = VALUES(`url`), `updated_by` = VALUES(`updated_by`), `updated_at` = VALUES(`updated_at`)
    ]], { key, category, label, description, url, by, now() })

    stored[key] = { key = key, category = category, label = label, description = description, url = url, updatedBy = by, updatedAt = now() }
    publish()
    Logs.add(src, 'images.save', nil, { key = key, label = label, before = before and before.url or nil, after = url })

    return { ok = true, key = key }
end

-- Image ajoutée : supprimée ; emplacement d'un script : image d'origine
Panel.actions['images.delete'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'images.manage') then
        return denied()
    end

    local key = data.key
    local entry = type(key) == 'string' and entryOf(key)

    if not entry then
        return Panel.fail('Image introuvable.')
    end

    if not stored[key] then
        return { ok = true }
    end

    MySQL.update.await('DELETE FROM `lunatic_images` WHERE `key` = ?', { key })
    stored[key] = nil
    publish()
    Logs.add(src, 'images.delete', nil, { key = key, label = entry.label, url = entry.url, reset = entry.slot })

    return { ok = true }
end

---------------------------------------------------------------------
-- Mugshots
---------------------------------------------------------------------

---@type table<number, number> joueurs à qui une photo a été demandée (source -> date limite)
local requested = {}

local function requestMugshot(target)
    requested[target] = now() + MUGSHOT_REQUEST_TIMEOUT
    TriggerClientEvent('lunatic_admin:takeMugshot', target)
end

-- Création de personnage (lunatic_creator) : la photo est prise à la fin de la création, avant l'arrivée en ville
exports('requestMugshot', function(target)
    target = tonumber(target)

    if target and GetPlayerName(target) then
        requestMugshot(target)
        return true
    end

    return false
end)

-- Photo automatique à la première connexion d'un personnage (sans photo en base)
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local identifier = xPlayer and xPlayer.identifier

    if not identifier then
        return
    end

    local exists = MySQL.scalar.await('SELECT 1 FROM `lunatic_mugshots` WHERE `identifier` = ?', { identifier })

    if exists then
        return
    end

    SetTimeout(MUGSHOT_DELAY, function()
        local current = ESX.GetPlayerFromId(playerId)

        -- En pleine création de personnage : la photo sera demandée par lunatic_creator à la fin
        if current and current.identifier == identifier and not Player(playerId).state.lunaticCreating then
            requestMugshot(playerId)
        end
    end)
end)

RegisterNetEvent('lunatic_admin:mugshot', function(image)
    local src = source
    local deadline = requested[src]
    requested[src] = nil

    -- Seulement une photo demandée par le serveur, au bon format et de taille raisonnable
    if not deadline or deadline < now() then
        return
    end

    if type(image) ~= 'string' or #image > MUGSHOT_MAX or not image:match('^data:image/[%a]+;base64,[%w%+/=]+$') then
        return
    end

    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer then
        return
    end

    MySQL.query.await('INSERT INTO `lunatic_mugshots` (`identifier`, `image`, `updated_at`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `image` = VALUES(`image`), `updated_at` = VALUES(`updated_at`)',
        { xPlayer.identifier, image, now() })
end)

-- Le navigateur du jeu a refusé de convertir le portrait : visible dans la console serveur
RegisterNetEvent('lunatic_admin:mugshotFailed', function(reason)
    local src = source

    if not requested[src] then
        return
    end

    requested[src] = nil
    print(('^3[lunatic_admin] Mugshot impossible pour %s : %s^0'):format(GetPlayerName(src) or src, type(reason) == 'string' and reason:sub(1, 120) or 'raison inconnue'))
end)

AddEventHandler('playerDropped', function()
    requested[source] = nil
end)

-- Liste paginée (onglet Mugshots) avec le nom RP
Panel.actions['mugshots.list'] = function(_, actor, data)
    if not Ranks.hasPermission(actor, 'images.manage') then
        return denied()
    end

    local offset = math.max(0, math.floor(tonumber(data.offset) or 0))
    local search = type(data.search) == 'string' and data.search:gsub('[%%_]', ''):sub(1, 40) or ''
    local where, values = '', {}

    if search ~= '' then
        where = "WHERE CONCAT(IFNULL(u.`firstname`, ''), ' ', IFNULL(u.`lastname`, '')) LIKE ? OR m.`identifier` LIKE ?"
        values = { '%' .. search .. '%', '%' .. search .. '%' }
    end

    local total = MySQL.scalar.await(('SELECT COUNT(*) FROM `lunatic_mugshots` m LEFT JOIN `users` u ON u.`identifier` = m.`identifier` %s'):format(where), values)
    values[#values + 1] = MUGSHOT_PAGE
    values[#values + 1] = offset

    local rows = MySQL.query.await(([[
        SELECT m.`identifier`, m.`image`, m.`updated_at`, u.`firstname`, u.`lastname`
        FROM `lunatic_mugshots` m LEFT JOIN `users` u ON u.`identifier` = m.`identifier`
        %s ORDER BY m.`updated_at` DESC LIMIT ? OFFSET ?
    ]]):format(where), values) or {}

    local online = {}

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        online[xPlayer.identifier] = xPlayer.source
    end

    local list = {}

    for _, row in ipairs(rows) do
        local name = ('%s %s'):format(row.firstname or '', row.lastname or ''):match('^%s*(.-)%s*$')
        list[#list + 1] = { identifier = row.identifier, name = name ~= '' and name or row.identifier, image = row.image, updatedAt = tonumber(row.updated_at), online = online[row.identifier] }
    end

    return { ok = true, silent = true, mugshots = list, total = tonumber(total) or 0, offset = offset, pageSize = MUGSHOT_PAGE }
end

-- Photo d'un personnage pour les autres ressources (carte d'identité de lunatic_gameplay)
exports('getMugshot', function(identifier)
    if type(identifier) ~= 'string' then
        return nil
    end

    return MySQL.scalar.await('SELECT `image` FROM `lunatic_mugshots` WHERE `identifier` = ?', { identifier })
end)

-- Photos de quelques personnages (fiche joueur, liste des joueurs)
Panel.actions['mugshots.get'] = function(_, actor, data)
    if not Ranks.hasPermission(actor, 'players.view') and not Ranks.hasPermission(actor, 'images.manage') then
        return denied()
    end

    local identifiers = {}

    for _, identifier in ipairs(type(data.identifiers) == 'table' and data.identifiers or {}) do
        if type(identifier) == 'string' and #identifier <= 60 and #identifiers < 64 then
            identifiers[#identifiers + 1] = identifier
        end
    end

    local images = {}

    if #identifiers > 0 then
        local placeholders = ('?, '):rep(#identifiers):sub(1, -3)

        for _, row in ipairs(MySQL.query.await(('SELECT `identifier`, `image` FROM `lunatic_mugshots` WHERE `identifier` IN (%s)'):format(placeholders), identifiers) or {}) do
            images[row.identifier] = row.image
        end
    end

    return { ok = true, silent = true, images = images }
end

-- Refaire la photo d'un personnage connecté
Panel.actions['mugshots.retake'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'images.manage') then
        return denied()
    end

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        if xPlayer.identifier == data.identifier then
            requestMugshot(xPlayer.source)
            Logs.add(src, 'mugshots.retake', xPlayer.name, { identifier = xPlayer.identifier })
            return { ok = true, message = 'Photo demandée : elle sera à jour dans quelques secondes.' }
        end
    end

    return Panel.fail("Ce personnage n'est pas connecté : la photo se refait quand il est en jeu.")
end

-- Refaire la photo de tous les joueurs connectés (une demande toutes les demi-secondes)
Panel.actions['mugshots.retakeAll'] = function(src, actor)
    if not Ranks.hasPermission(actor, 'images.manage') then
        return denied()
    end

    local players = {}

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        players[#players + 1] = xPlayer
    end

    CreateThread(function()
        for _, xPlayer in ipairs(players) do
            if GetPlayerName(xPlayer.source) then
                requestMugshot(xPlayer.source)
                Wait(500)
            end
        end
    end)

    Logs.add(src, 'mugshots.retake', nil, { all = true, count = #players })
    return { ok = true, message = ('Photos demandées pour %d joueur(s) connecté(s).'):format(#players) }
end
