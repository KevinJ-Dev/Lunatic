-- Serveur du tchat : chaque message est nettoyé, limité et distribué ici.
-- Le client ne choisit jamais les destinataires.

local ready = false

---------------------------------------------------------------------
-- Base de données : historique des messages (modération)
---------------------------------------------------------------------

local function purgeLogs()
    MySQL.update('DELETE FROM `lunatic_chat_logs` WHERE `created_at` < (NOW() - INTERVAL ? DAY)', { Config.LogRetentionDays })
end

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_chat_logs` (
            `id` BIGINT NOT NULL AUTO_INCREMENT,
            `license` VARCHAR(60) NULL DEFAULT NULL,
            `name` VARCHAR(80) NOT NULL DEFAULT '',
            `channel` VARCHAR(16) NOT NULL,
            `message` TEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_chat_logs_created` (`created_at`),
            KEY `idx_lunatic_chat_logs_license` (`license`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    purgeLogs()
    ready = true
end)

-- Purge quotidienne de l'historique
CreateThread(function()
    while true do
        Wait(24 * 60 * 60 * 1000)

        if ready then
            purgeLogs()
        end
    end
end)

---------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------

local warnedMissingExport = false

local function can(src, permission)
    if src == 0 then
        return true -- console de l'hébergeur
    end

    if GetResourceState('lunatic_admin') ~= 'started' then
        return false
    end

    local ok, allowed = pcall(function()
        return exports.lunatic_admin:can(src, permission)
    end)

    -- Ancienne version de lunatic_admin (sans l'export "can") : les outils staff restent bloqués
    if not ok and not warnedMissingExport then
        warnedMissingExport = true
        print('^1[lunatic_chat] lunatic_admin ne fournit pas l\'export "can" : envoyez sa dernière version et redémarrez le serveur.^0')
    end

    return ok and allowed == true
end

local function rankOf(src)
    if src == 0 or GetResourceState('lunatic_admin') ~= 'started' then
        return nil
    end

    local ok, rank = pcall(function()
        return exports.lunatic_admin:getRank(src)
    end)

    return ok and rank and { name = rank.name, color = rank.color } or nil
end

-- "[12] Prénom Nom" (pseudo FiveM tant que l'identité n'est pas créée)
local function displayName(src)
    if src == 0 then
        return 'Console'
    end

    local state = Player(src).state
    local first, last = state.firstName, state.lastName
    local name

    if type(first) == 'string' and first ~= '' and type(last) == 'string' and last ~= '' then
        name = ('%s %s'):format(first, last)
    else
        name = GetPlayerName(src) or 'Inconnu'
    end

    return ('[%d] %s'):format(src, name)
end

-- Nettoie un texte venant d'un joueur : codes couleur (^1, ~r~), caractères de contrôle, espaces, longueur
---@return string|nil
local function clean(text, maxLength)
    if type(text) ~= 'string' then
        return nil
    end

    text = text:gsub('%^%d', ''):gsub('~', ''):gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')

    local length = utf8.len(text)

    if not length or length == 0 then
        return nil
    end

    if length > maxLength then
        text = text:sub(1, utf8.offset(text, maxLength + 1) - 1)
    end

    return text
end

-- Texte après le nom de la commande ("me sourit" -> "sourit")
local function argsOf(raw)
    return type(raw) == 'string' and raw:match('^%S+%s*(.*)$') or ''
end

local function send(target, message)
    TriggerClientEvent('lunatic_chat:message', target, message)
end

local function system(target, text, kind)
    if target == 0 then
        return print(('[lunatic_chat] %s'):format(text))
    end

    send(target, { kind = kind or 'system', text = text })
end

local function log(src, channel, message)
    if not ready then
        return
    end

    MySQL.insert('INSERT INTO `lunatic_chat_logs` (`license`, `name`, `channel`, `message`) VALUES (?, ?, ?, ?)', {
        src > 0 and GetPlayerIdentifierByType(src, 'license') or nil,
        displayName(src),
        channel,
        message,
    })
end

-- Anti-spam par joueur
local usage = {}

AddEventHandler('playerDropped', function()
    usage[source] = nil
end)

local function allowed(src)
    if src == 0 then
        return true
    end

    -- Tuile Fonctionnalités du panel : chat textuel désactivé (sauf pour le staff)
    local features = GlobalState.lunaticFeatures

    if features and features.toggles and features.toggles.chat == false and not rankOf(src) then
        system(src, 'Le chat textuel est désactivé sur le serveur.', 'error')
        return false
    end

    local now = GetGameTimer()
    local entry = usage[src]

    if not entry or now - entry.start > Config.RateLimit.windowMs then
        usage[src] = { start = now, count = 1, last = now }
        return true
    end

    if now - entry.last < Config.RateLimit.minIntervalMs or entry.count >= Config.RateLimit.max then
        system(src, 'Doucement : attendez un peu avant d’envoyer un autre message.', 'error')
        return false
    end

    entry.count = entry.count + 1
    entry.last = now
    return true
end

-- Joueurs proches (même instance / routing bucket), l'auteur compris
local function nearby(src, radius)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return { src }
    end

    local origin = GetEntityCoords(ped)
    local bucket = GetPlayerRoutingBucket(src)
    local list = {}

    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        local targetPed = GetPlayerPed(target)

        if target == src or (targetPed ~= 0 and GetPlayerRoutingBucket(target) == bucket and #(GetEntityCoords(targetPed) - origin) <= radius) then
            list[#list + 1] = target
        end
    end

    return list
end

---------------------------------------------------------------------
-- HRP local : message sans commande ou /hrp
---------------------------------------------------------------------

local function sendLocal(src, raw)
    local text = clean(raw, Config.MaxLength)

    if not text or not allowed(src) then
        return
    end

    local message = { kind = 'hrp', author = displayName(src), text = text }

    for _, target in ipairs(nearby(src, Config.LocalRadius)) do
        send(target, message)
    end

    log(src, 'hrp', text)
end

RegisterNetEvent('lunatic_chat:say', function(raw)
    local src = source

    if type(raw) ~= 'string' then
        return
    end

    -- Compatibilité : un script qui écoute "chatMessage" peut annuler le message
    TriggerEvent('chatMessage', src, displayName(src), raw)

    if WasEventCanceled() then
        return
    end

    sendLocal(src, raw)
end)

RegisterCommand('hrp', function(src, _, raw)
    if src == 0 then
        return
    end

    if not clean(argsOf(raw), Config.MaxLength) then
        return system(src, 'Utilisation : /hrp <message>', 'error')
    end

    sendLocal(src, argsOf(raw))
end, false)

---------------------------------------------------------------------
-- /me et /do : texte 3D au-dessus du personnage, pour les joueurs proches
---------------------------------------------------------------------

local function send3d(src, kind, raw)
    if src == 0 then
        return
    end

    local text = clean(raw, Config.Max3DLength)

    if not text then
        return system(src, ('Utilisation : /%s <texte>'):format(kind), 'error')
    end

    if not allowed(src) then
        return
    end

    for _, target in ipairs(nearby(src, Config.Radius3D)) do
        TriggerClientEvent('lunatic_chat:text3d', target, src, kind, text)
    end

    log(src, kind, text)
end

RegisterCommand('me', function(src, _, raw)
    send3d(src, 'me', argsOf(raw))
end, false)

RegisterCommand('do', function(src, _, raw)
    send3d(src, 'do', argsOf(raw))
end, false)

---------------------------------------------------------------------
-- Outils staff (permissions gérées dans le panel lunatic_admin)
---------------------------------------------------------------------

RegisterCommand('sc', function(src, _, raw)
    if not can(src, 'chat.staff') then
        return system(src, "Vous n'avez pas accès au tchat staff.", 'error')
    end

    local text = clean(argsOf(raw), Config.MaxLength)

    if not text then
        return system(src, 'Utilisation : /sc <message>', 'error')
    end

    if not allowed(src) then
        return
    end

    local message = { kind = 'staff', author = displayName(src), rank = rankOf(src), text = text }

    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)

        if can(target, 'chat.staff') then
            send(target, message)
        end
    end

    print(('[lunatic_chat] [STAFF] %s : %s'):format(message.author, text))
    log(src, 'staff', text)
end, false)

RegisterCommand('annonce', function(src, _, raw)
    if not can(src, 'chat.announce') then
        return system(src, "Vous n'avez pas la permission de faire une annonce.", 'error')
    end

    local text = clean(argsOf(raw), Config.MaxLength)

    if not text then
        return system(src, 'Utilisation : /annonce <message>', 'error')
    end

    if not allowed(src) then
        return
    end

    local rank = rankOf(src)
    send(-1, { kind = 'announce', author = displayName(src), rank = rank, text = text })
    print(('[lunatic_chat] [ANNONCE] %s : %s'):format(displayName(src), text))
    log(src, 'announce', text)
end, false)

-- Annonce signée « Modération » (l'auteur reste dans la console et l'historique)
RegisterCommand('annoncemodo', function(src, _, raw)
    if not can(src, 'chat.announce_mod') then
        return system(src, "Vous n'avez pas la permission de faire une annonce Modération.", 'error')
    end

    local text = clean(argsOf(raw), Config.MaxLength)

    if not text then
        return system(src, 'Utilisation : /annoncemodo <message>', 'error')
    end

    if not allowed(src) then
        return
    end

    send(-1, { kind = 'announce', tag = 'Modération', author = displayName(src), rank = rankOf(src), text = text })
    print(('[lunatic_chat] [ANNONCE MODÉRATION] %s : %s'):format(displayName(src), text))
    log(src, 'announce', '[Modération] ' .. text)
end, false)

RegisterCommand('vidertchat', function(src)
    if not can(src, 'chat.clear') then
        return system(src, "Vous n'avez pas la permission de vider le tchat.", 'error')
    end

    TriggerClientEvent('chat:clear', -1)
    system(-1, "Le tchat a été vidé par l'équipe staff.")
    print(('[lunatic_chat] Tchat vidé par %s'):format(displayName(src)))
    log(src, 'clear', '')
end, false)

-- Le client demande ses accès à chaque ouverture du tchat (suggestions des commandes staff)
RegisterNetEvent('lunatic_chat:requestAccess', function()
    local src = source

    TriggerClientEvent('lunatic_chat:access', src, {
        staff = can(src, 'chat.staff'),
        announce = can(src, 'chat.announce'),
        announceMod = can(src, 'chat.announce_mod'),
        crash = can(src, 'players.crash'),
        givecar = can(src, 'vehicles.give'),
        inventory = can(src, 'economy.items'),
        clear = can(src, 'chat.clear'),
        panel = can(src, 'panel.open'),
    })
end)

---------------------------------------------------------------------
-- Compatibilité avec la resource "chat" de FiveM
---------------------------------------------------------------------

-- exports.chat:addMessage(cible, message) : même format que l'événement chat:addMessage
exports('addMessage', function(target, message)
    TriggerClientEvent('chat:addMessage', target, message)
end)
