-- Events à zone (tuile Events → Zone Events), enregistrés en base : un event se charge et se décharge à tout moment,
-- et reste chargé après un reboot tant que sa durée n'est pas écoulée.
-- Event chargé : quand un joueur entre dans sa zone, le serveur l'inscrit (limite de joueurs) et pose ses règles
-- dans l'état du joueur (Player(src).state.lunaticEvent), lu par les scripts du jeu : invincibilité, pas de coma,
-- respawn, faim et soif, heure, musique. Le serveur revérifie la position des participants : sortir de la zone,
-- ou décharger l'event, retire tout.

EventZones = {}

local LIMITS = { label = 60, description = 300, players = 500, duration = 1440, radiusMin = 10, radiusMax = 1000, audio = 255 }
local RULES = { 'noKO', 'godmode', 'vehicleGodmode', 'policeCalls', 'respawn', 'noNeeds' }

---@type table<number, table> events par id
local events = {}
---@type table<number, table<number, boolean>> participants par event
local participants = {}
---@type table<number, number> joueur -> event
local playerEvent = {}
local fullNotified = {}

local function now()
    return os.time()
end

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les events.")
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

local function whole(value, min, max)
    value = tonumber(value)

    if not value or value ~= math.floor(value) or value < min or value > max then
        return nil
    end

    return value
end

local function fromRow(row)
    local ok, rules = pcall(json.decode, row.rules or '{}')
    rules = ok and type(rules) == 'table' and rules or {}

    return {
        id = tonumber(row.id),
        label = row.label,
        description = row.description or '',
        maxPlayers = tonumber(row.max_players) or 0,
        duration = tonumber(row.duration) or 60,
        x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
        radius = tonumber(row.radius) or 100,
        rules = rules,
        hour = tonumber(row.hour),
        audio = row.audio or '',
        volume = tonumber(row.volume) or 50,
        loadedAt = tonumber(row.loaded_at),
        createdBy = row.created_by,
    }
end

local function countOf(id)
    local count = 0

    for _ in pairs(participants[id] or {}) do
        count = count + 1
    end

    return count
end

-- Règles posées dans l'état du joueur (lues par les clients)
local function stateOf(event)
    local rules = event.rules

    return {
        id = event.id, label = event.label,
        x = event.x, y = event.y, z = event.z, radius = event.radius,
        noKO = rules.noKO == true, godmode = rules.godmode == true, vehicleGodmode = rules.vehicleGodmode == true,
        noPolice = rules.policeCalls == false, respawn = rules.respawn == true, noNeeds = rules.noNeeds == true,
        hour = event.hour, audio = event.audio ~= '' and event.audio or nil, volume = event.volume,
    }
end

-- Zones des events chargés : les clients détectent l'entrée et préviennent le serveur
local function publish()
    local list = {}

    for _, event in pairs(events) do
        if event.loadedAt and event.x then
            list[#list + 1] = { id = event.id, label = event.label, x = event.x, y = event.y, radius = event.radius }
        end
    end

    GlobalState.lunaticEventZones = list
end

local function leave(src, silent)
    local id = playerEvent[src]

    if not id then
        return
    end

    playerEvent[src] = nil

    if participants[id] then
        participants[id][src] = nil
    end

    if GetPlayerPing(src) > 0 then
        Player(src).state:set('lunaticEvent', nil, true)

        if not silent then
            TriggerClientEvent('esx:showNotification', src, ('Vous quittez la zone de « %s ».'):format(events[id] and events[id].label or "l'event"), 'info')
        end
    end
end

local function join(src, event)
    participants[event.id] = participants[event.id] or {}
    participants[event.id][src] = true
    playerEvent[src] = event.id
    fullNotified[src] = nil
    Player(src).state:set('lunaticEvent', stateOf(event), true)
    TriggerClientEvent('esx:showNotification', src, ('Vous entrez dans la zone de « %s ».'):format(event.label), 'success')
end

local function unload(event)
    for src in pairs(participants[event.id] or {}) do
        leave(src, true)
        TriggerClientEvent('esx:showNotification', src, ("L'event « %s » est terminé."):format(event.label), 'info')
    end

    participants[event.id] = nil
    event.loadedAt = nil
    MySQL.update.await('UPDATE `lunatic_event_zones` SET `loaded_at` = NULL WHERE `id` = ?', { event.id })
    publish()
end

-- Règles modifiées pendant que l'event est chargé : appliquées tout de suite aux participants
local function refreshParticipants(event)
    for src in pairs(participants[event.id] or {}) do
        Player(src).state:set('lunaticEvent', stateOf(event), true)
    end
end

local function load()
    events = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_event_zones`') or {}) do
        local event = fromRow(row)
        events[event.id] = event
    end

    publish()
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_event_zones` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `label` VARCHAR(60) NOT NULL,
            `description` VARCHAR(300) NOT NULL DEFAULT '',
            `max_players` INT NOT NULL DEFAULT 0,
            `duration` INT NOT NULL DEFAULT 60,
            `x` DOUBLE NULL DEFAULT NULL,
            `y` DOUBLE NULL DEFAULT NULL,
            `z` DOUBLE NULL DEFAULT NULL,
            `radius` INT NOT NULL DEFAULT 100,
            `rules` TEXT NULL,
            `hour` TINYINT NULL DEFAULT NULL,
            `audio` VARCHAR(255) NOT NULL DEFAULT '',
            `volume` TINYINT NOT NULL DEFAULT 50,
            `loaded_at` BIGINT NULL DEFAULT NULL,
            `created_by` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            `updated_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    load()

    -- Redémarrage de la ressource : les joueurs déjà dans une zone se réinscrivent d'eux-mêmes (le client renvoie l'entrée)
    for _, id in ipairs(GetPlayers()) do
        Player(tonumber(id)).state:set('lunaticEvent', nil, true)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local id = playerEvent[src]
    playerEvent[src] = nil
    fullNotified[src] = nil

    if id and participants[id] then
        participants[id][src] = nil
    end
end)

local function distance2D(src, event)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return math.huge
    end

    local coords = GetEntityCoords(ped)
    return #(vector2(coords.x, coords.y) - vector2(event.x, event.y))
end

-- Le client signale l'entrée : le serveur vérifie la position et la limite de joueurs
RegisterNetEvent('lunatic_admin:eventEnter', function(id)
    local src = source
    local event = events[tonumber(id) or -1]

    if not event or not event.loadedAt or not event.x or playerEvent[src] == event.id then
        return
    end

    if distance2D(src, event) > event.radius + 15.0 then
        return
    end

    if playerEvent[src] then
        leave(src, true)
    end

    if event.maxPlayers > 0 and countOf(event.id) >= event.maxPlayers then
        if not fullNotified[src] then
            fullNotified[src] = true
            TriggerClientEvent('esx:showNotification', src, ('« %s » est complet (%d joueurs).'):format(event.label, event.maxPlayers), 'error')
        end

        return
    end

    join(src, event)
end)

RegisterNetEvent('lunatic_admin:eventLeave', function()
    leave(source)
end)

-- Contrôle du serveur : participants sortis de la zone, durée écoulée
CreateThread(function()
    while true do
        Wait(3000)
        local t = now()

        for _, event in pairs(events) do
            if event.loadedAt then
                if event.duration > 0 and t >= event.loadedAt + event.duration * 60 then
                    unload(event)
                    Logs.event('staff', 'info', nil, 'eventZones.expired', event.label, { id = event.id })
                else
                    for src in pairs(participants[event.id] or {}) do
                        if distance2D(src, event) > event.radius + 30.0 then
                            leave(src)
                        end
                    end
                end
            end
        end
    end
end)

---@param src number
---@return table|nil event dans lequel se trouve le joueur (règles comprises)
function EventZones.of(src)
    local id = playerEvent[src]
    return id and events[id] and stateOf(events[id]) or nil
end

exports('getPlayerEvent', function(src)
    return EventZones.of(src)
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function eventFor(actor, id)
    if not Ranks.hasPermission(actor, 'events.manage') then
        return nil, denied()
    end

    local event = events[tonumber(id) or -1]

    if not event then
        return nil, Panel.fail('Event introuvable.')
    end

    return event
end

local function view(event)
    return {
        id = event.id, label = event.label, description = event.description, maxPlayers = event.maxPlayers, duration = event.duration,
        x = event.x, y = event.y, z = event.z, radius = event.radius, rules = event.rules, hour = event.hour,
        audio = event.audio, volume = event.volume, loaded = event.loadedAt ~= nil, loadedAt = event.loadedAt,
        players = countOf(event.id), createdBy = event.createdBy,
    }
end

Panel.actions['eventZones.list'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'events.manage') then
        return denied()
    end

    local list = {}

    for _, event in pairs(events) do
        list[#list + 1] = view(event)
    end

    table.sort(list, function(a, b) return a.id < b.id end)
    return { ok = true, silent = true, events = list }
end

-- Lien audio direct (.mp3, .ogg, .wav…) en https, lu par la page du jeu
local function cleanAudio(value)
    local url = cleanText(value, 0, LIMITS.audio)

    if not url or url == '' then
        return url
    end

    return url:match('^https://[%w%-%.]+%.%a+/.*') and url or nil
end

---@return table|nil fields, table|nil error
local function readFields(data)
    local label = cleanText(data.label, 3, LIMITS.label)

    if not label then
        return nil, Panel.fail(('Le nom doit faire entre 3 et %d caractères.'):format(LIMITS.label))
    end

    local description = cleanText(data.description, 0, LIMITS.description)

    if not description then
        return nil, Panel.fail(('La description fait %d caractères au maximum.'):format(LIMITS.description))
    end

    local maxPlayers = whole(data.maxPlayers, 0, LIMITS.players)
    local duration = whole(data.duration, 0, LIMITS.duration)
    local radius = whole(data.radius, LIMITS.radiusMin, LIMITS.radiusMax)
    local volume = whole(data.volume, 0, 100)

    if not maxPlayers then
        return nil, Panel.fail(('Joueurs max : un nombre entier entre 0 et %d (0 = illimité).'):format(LIMITS.players))
    end

    if not duration then
        return nil, Panel.fail(('Durée : un nombre entier de minutes entre 0 et %d (0 = sans limite).'):format(LIMITS.duration))
    end

    if not radius then
        return nil, Panel.fail(('Rayon de la zone : entre %d et %d mètres.'):format(LIMITS.radiusMin, LIMITS.radiusMax))
    end

    if not volume then
        return nil, Panel.fail('Volume : entre 0 et 100.')
    end

    local hour = nil

    if data.hour ~= nil then
        hour = whole(data.hour, 0, 23)

        if not hour then
            return nil, Panel.fail("Heure de l'event : entre 0 et 23.")
        end
    end

    local audio = cleanAudio(data.audio)

    if not audio then
        return nil, Panel.fail('Musique : un lien https direct vers un fichier audio (.mp3, .ogg, .wav).')
    end

    local x, y, z = nil, nil, nil

    if data.x ~= nil then
        x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)

        if not x or not y or x < -5000 or x > 5000 or y < -5000 or y > 9000 or (z and (z < -300 or z > 3000)) then
            return nil, Panel.fail('Position de la zone invalide.')
        end
    end

    local rules = {}

    for _, key in ipairs(RULES) do
        rules[key] = type(data.rules) == 'table' and data.rules[key] == true
    end

    return {
        label = label, description = description, maxPlayers = maxPlayers, duration = duration, radius = radius,
        volume = volume, hour = hour, audio = audio, x = x, y = y, z = z, rules = rules,
    }
end

Panel.actions['eventZones.save'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'events.manage') then
        return denied()
    end

    local fields, err = readFields(data)

    if not fields then
        return err
    end

    local id = tonumber(data.id)
    local event = id and events[id]

    if id and not event then
        return Panel.fail('Event introuvable.')
    end

    local total = 0

    for _ in pairs(events) do
        total = total + 1
    end

    if not event and total >= 100 then
        return Panel.fail('100 events au maximum.')
    end

    -- Valeurs NULL (heure, position) écrites à part : pas de nil au milieu des paramètres
    if event then
        MySQL.update.await('UPDATE `lunatic_event_zones` SET `label` = ?, `description` = ?, `max_players` = ?, `duration` = ?, `radius` = ?, `rules` = ?, `audio` = ?, `volume` = ?, `updated_at` = ? WHERE `id` = ?', {
            fields.label, fields.description, fields.maxPlayers, fields.duration, fields.radius, json.encode(fields.rules), fields.audio, fields.volume, now(), id,
        })
    else
        id = MySQL.insert.await('INSERT INTO `lunatic_event_zones` (`label`, `description`, `max_players`, `duration`, `radius`, `rules`, `audio`, `volume`, `created_by`, `created_at`, `updated_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            fields.label, fields.description, fields.maxPlayers, fields.duration, fields.radius, json.encode(fields.rules), fields.audio, fields.volume, Staff.displayName(src), now(), now(),
        })

        if not id then
            return Panel.fail('Enregistrement impossible (voir la console du serveur).')
        end
    end

    if fields.hour then
        MySQL.update.await('UPDATE `lunatic_event_zones` SET `hour` = ? WHERE `id` = ?', { fields.hour, id })
    else
        MySQL.update.await('UPDATE `lunatic_event_zones` SET `hour` = NULL WHERE `id` = ?', { id })
    end

    if fields.x then
        MySQL.update.await('UPDATE `lunatic_event_zones` SET `x` = ?, `y` = ?, `z` = ? WHERE `id` = ?', { fields.x, fields.y, fields.z or -200.0, id })
    end

    local row = MySQL.single.await('SELECT * FROM `lunatic_event_zones` WHERE `id` = ?', { id })
    events[id] = fromRow(row)
    refreshParticipants(events[id])
    publish()

    Logs.add(src, event and 'eventZones.update' or 'eventZones.create', fields.label, { id = id })
    return { ok = true, silent = true, id = id }
end

Panel.actions['eventZones.duplicate'] = function(src, actor, data)
    local event, err = eventFor(actor, data.id)

    if not event then
        return err
    end

    local label = (event.label .. ' (copie)'):sub(1, LIMITS.label)
    local id = MySQL.insert.await('INSERT INTO `lunatic_event_zones` (`label`, `description`, `max_players`, `duration`, `radius`, `rules`, `audio`, `volume`, `created_by`, `created_at`, `updated_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        label, event.description, event.maxPlayers, event.duration, event.radius, json.encode(event.rules), event.audio, event.volume, Staff.displayName(src), now(), now(),
    })

    if not id then
        return Panel.fail('Copie impossible (voir la console du serveur).')
    end

    if event.hour then
        MySQL.update.await('UPDATE `lunatic_event_zones` SET `hour` = ? WHERE `id` = ?', { event.hour, id })
    end

    if event.x then
        MySQL.update.await('UPDATE `lunatic_event_zones` SET `x` = ?, `y` = ?, `z` = ? WHERE `id` = ?', { event.x, event.y, event.z or -200.0, id })
    end

    events[id] = fromRow(MySQL.single.await('SELECT * FROM `lunatic_event_zones` WHERE `id` = ?', { id }))
    Logs.add(src, 'eventZones.duplicate', label, { id = id, from = event.id })
    return { ok = true, silent = true, id = id }
end

Panel.actions['eventZones.delete'] = function(src, actor, data)
    local event, err = eventFor(actor, data.id)

    if not event then
        return err
    end

    if event.loadedAt then
        unload(event)
    end

    MySQL.update.await('DELETE FROM `lunatic_event_zones` WHERE `id` = ?', { event.id })
    events[event.id] = nil
    publish()

    Logs.add(src, 'eventZones.delete', event.label, { id = event.id })
    return { ok = true, silent = true }
end

Panel.actions['eventZones.load'] = function(src, actor, data)
    local event, err = eventFor(actor, data.id)

    if not event then
        return err
    end

    if not event.x then
        return Panel.fail("Placez d'abord la zone de l'event sur la carte.")
    end

    if event.loadedAt then
        unload(event)
        Logs.add(src, 'eventZones.unload', event.label, { id = event.id })
        return { ok = true, silent = true, loaded = false }
    end

    event.loadedAt = now()
    MySQL.update.await('UPDATE `lunatic_event_zones` SET `loaded_at` = ? WHERE `id` = ?', { event.loadedAt, event.id })
    publish()

    Logs.add(src, 'eventZones.load', event.label, { id = event.id, duration = event.duration })
    return { ok = true, silent = true, loaded = true }
end

Panel.actions['eventZones.tp'] = function(src, actor, data)
    local event, err = eventFor(actor, data.id)

    if not event then
        return err
    end

    if not event.x then
        return Panel.fail("La zone de l'event n'est pas encore placée.")
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(event.x, event.y, (event.z or -200.0) + (event.z and event.z > -100 and 1.0 or 0.0)))
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Events à zone chargé.')
