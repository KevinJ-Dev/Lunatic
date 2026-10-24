-- Events à zone (tuile Events → Zone Events), enregistrés en base : un event se charge et se décharge à tout moment,
-- et reste chargé après un reboot tant que sa durée n'est pas écoulée.
-- Event chargé : quand un joueur entre dans sa zone, le serveur l'inscrit (limite de joueurs) et pose ses règles
-- dans l'état du joueur (Player(src).state.lunaticEvent), lu par les scripts du jeu : invincibilité, pas de coma,
-- respawn, faim et soif, heure, musique. Le serveur revérifie la position des participants : sortir de la zone,
-- ou décharger l'event, retire tout.
-- Contenu (partie 2) : objets temporaires donnés à l'entrée et repris à la sortie (marqués metadata.event, ni donnés
-- ni jetés), tenues homme / femme appliquées dans la zone, points de TP, véhicules posés au chargement.

EventZones = {}

local LIMITS = { label = 60, description = 300, players = 500, duration = 1440, radiusMin = 10, radiusMax = 1000, audio = 255, items = 20, tp = 10, vehicles = 20 }
local RULES = { 'noKO', 'godmode', 'vehicleGodmode', 'policeCalls', 'respawn', 'noNeeds' }
local VEHICLE_TYPES = { automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true }

local ox = exports.ox_inventory

---@type table<number, table> events par id
local events = {}
---@type table<number, number[]> véhicules posés par event (entités)
local spawned = {}
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
    local okContent, content = pcall(json.decode, row.content or '{}')
    content = okContent and type(content) == 'table' and content or {}

    return {
        content = {
            items = type(content.items) == 'table' and content.items or {},
            outfits = type(content.outfits) == 'table' and content.outfits or {},
            tp = type(content.tp) == 'table' and content.tp or {},
            vehicles = type(content.vehicles) == 'table' and content.vehicles or {},
        },
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
        outfits = event.content.outfits, tp = event.content.tp,
    }
end

---------------------------------------------------------------------
-- Objets temporaires et véhicules
---------------------------------------------------------------------

-- Retire les objets d'event du joueur (d'un event précis, ou tous)
local function purgeItems(src, eventId)
    for _, slot in pairs(ox:GetInventoryItems(src) or {}) do
        local meta = slot.metadata

        if type(meta) == 'table' and meta.event and (not eventId or meta.event == eventId) then
            ox:RemoveItem(src, slot.name, slot.count, nil, slot.slot)
        end
    end
end

local function giveItems(src, event)
    for _, entry in ipairs(event.content.items) do
        local item = ox:Items(entry.item)

        if item then
            ox:AddItem(src, entry.item, entry.count, {
                event = event.id,
                label = ('[Event] %s'):format(item.label or entry.item),
                description = ("Objet de l'event « %s » : repris à la sortie de la zone."):format(event.label),
            })
        end
    end
end

local function despawnVehicles(id)
    for _, vehicle in ipairs(spawned[id] or {}) do
        if DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end
    end

    spawned[id] = nil
end

local function spawnVehicles(event)
    despawnVehicles(event.id)
    spawned[event.id] = {}

    for _, entry in ipairs(event.content.vehicles) do
        local vehicle = CreateVehicleServerSetter(joaat(entry.model), entry.type, entry.x + 0.0, entry.y + 0.0, entry.z + 0.0, (entry.h or 0.0) + 0.0)
        local timeout = GetGameTimer() + 2000

        while vehicle ~= 0 and not DoesEntityExist(vehicle) and GetGameTimer() < timeout do
            Wait(0)
        end

        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            SetVehicleNumberPlateText(vehicle, 'EVENT')
            Entity(vehicle).state:set('fuel', 100.0, true)
            Entity(vehicle).state:set('eventVehicle', event.id, true)
            spawned[event.id][#spawned[event.id] + 1] = vehicle
        else
            print(('[lunatic_admin] Event « %s » : véhicule %s impossible à créer (modèle inconnu ?).'):format(event.label, entry.model))
        end
    end
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
        purgeItems(src, id)

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
    giveItems(src, event)
    TriggerClientEvent('esx:showNotification', src, ('Vous entrez dans la zone de « %s ».'):format(event.label), 'success')
end

local function unload(event)
    for src in pairs(participants[event.id] or {}) do
        leave(src, true)
        TriggerClientEvent('esx:showNotification', src, ("L'event « %s » est terminé."):format(event.label), 'info')
    end

    participants[event.id] = nil
    despawnVehicles(event.id)
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

    MySQL.query.await('ALTER TABLE `lunatic_event_zones` ADD COLUMN IF NOT EXISTS `content` TEXT NULL')

    load()

    -- Redémarrage de la ressource : les joueurs déjà dans une zone se réinscrivent d'eux-mêmes (le client renvoie
    -- l'entrée) ; leurs objets d'event sont repris puis redonnés à l'entrée
    for _, id in ipairs(GetPlayers()) do
        Player(tonumber(id)).state:set('lunaticEvent', nil, true)
        purgeItems(tonumber(id))
    end

    for _, event in pairs(events) do
        if event.loadedAt then
            spawnVehicles(event)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for id in pairs(spawned) do
            despawnVehicles(id)
        end
    end
end)

-- Objets d'event restés dans l'inventaire (déconnexion dans la zone) : repris au chargement du personnage
AddEventHandler('esx:playerLoaded', function(src)
    -- ox_inventory charge l'inventaire sur le même événement : on attend qu'il soit prêt
    SetTimeout(5000, function()
        if not playerEvent[src] and GetPlayerPing(src) > 0 then
            purgeItems(src)
        end
    end)
end)

-- Objets d'event : ni donnés, ni jetés, ni rangés ailleurs que dans l'inventaire du joueur
CreateThread(function()
    while GetResourceState('ox_inventory') ~= 'started' do
        Wait(1000)
    end

    ox:registerHook('swapItems', function(payload)
        local item = type(payload.fromSlot) == 'table' and payload.fromSlot or {}

        if type(item.metadata) == 'table' and item.metadata.event and payload.fromInventory ~= payload.toInventory then
            TriggerClientEvent('esx:showNotification', payload.source, "Objet d'event : il reste dans votre inventaire.", 'error')
            return false
        end

        return true
    end, {})
end)

-- Points de TP : le serveur vérifie que le joueur est dans l'event et au point de départ
RegisterNetEvent('lunatic_admin:eventTp', function(index)
    local src = source
    local id = playerEvent[src]
    local event = id and events[id]
    local point = event and event.content.tp[tonumber(index) or -1]

    if not point then
        return
    end

    local ped = GetPlayerPed(src)

    if ped == 0 or #(GetEntityCoords(ped) - vector3(point.from.x, point.from.y, point.from.z)) > 4.0 then
        return
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(point.to.x, point.to.y, point.to.z))
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
        players = countOf(event.id), createdBy = event.createdBy, content = event.content,
        spawned = #(spawned[event.id] or {}),
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

local function position(value, heading)
    if type(value) ~= 'table' then
        return nil
    end

    local x, y, z, h = tonumber(value.x), tonumber(value.y), tonumber(value.z), tonumber(value.h) or 0.0

    if not x or not y or not z or x < -5000 or x > 5000 or y < -5000 or y > 9000 or z < -300 or z > 3000 then
        return nil
    end

    local point = { x = math.floor(x * 100 + 0.5) / 100, y = math.floor(y * 100 + 0.5) / 100, z = math.floor(z * 100 + 0.5) / 100 }

    if heading then
        point.h = math.floor((h % 360) * 10 + 0.5) / 10
    end

    return point
end

-- Tenue capturée sur le personnage du staff (illenium-appearance) : vêtements et accessoires seulement
local function readOutfit(value)
    if value == nil then
        return nil, true
    end

    if type(value) ~= 'table' or type(value.components) ~= 'table' or type(value.props) ~= 'table' or #value.components > 12 or #value.props > 8 then
        return nil, false
    end

    local outfit = { components = {}, props = {} }

    for _, c in ipairs(value.components) do
        local id, drawable, texture = whole(c.component_id, 0, 11), whole(c.drawable, -1, 5000), whole(c.texture, 0, 255)

        if not id or not drawable or not texture then
            return nil, false
        end

        outfit.components[#outfit.components + 1] = { component_id = id, drawable = drawable, texture = texture }
    end

    for _, p in ipairs(value.props) do
        local id, drawable, texture = whole(p.prop_id, 0, 7), whole(p.drawable, -1, 5000), whole(p.texture, -1, 255)

        if not id or not drawable or not texture then
            return nil, false
        end

        outfit.props[#outfit.props + 1] = { prop_id = id, drawable = drawable, texture = texture }
    end

    return outfit, true
end

-- Contenu de l'event : objets, tenues, points de TP, véhicules
---@return table|nil content, string|nil error
local function readContent(data)
    local content = { items = {}, outfits = {}, tp = {}, vehicles = {} }

    local items = type(data.items) == 'table' and data.items or {}

    if #items > LIMITS.items then
        return nil, ('%d objets au maximum.'):format(LIMITS.items)
    end

    for _, entry in ipairs(items) do
        local count = whole(entry.count, 1, 1000)

        if type(entry.item) ~= 'string' or not ox:Items(entry.item) then
            return nil, ('Objet inconnu : %s.'):format(tostring(entry.item))
        end

        if not count then
            return nil, ('Quantité de %s : entre 1 et 1000.'):format(entry.item)
        end

        content.items[#content.items + 1] = { item = entry.item, count = count }
    end

    for _, sex in ipairs({ 'male', 'female' }) do
        local outfit, valid = readOutfit(type(data.outfits) == 'table' and data.outfits[sex] or nil)

        if not valid then
            return nil, 'Tenue invalide : capturez-la de nouveau.'
        end

        content.outfits[sex] = outfit
    end

    local tp = type(data.tp) == 'table' and data.tp or {}

    if #tp > LIMITS.tp then
        return nil, ('%d points de TP au maximum.'):format(LIMITS.tp)
    end

    for index, entry in ipairs(tp) do
        local label = cleanText(entry.label, 1, 40)
        local from, to = position(entry.from, false), position(entry.to, true)

        if not label then
            return nil, ('Point de TP n°%d : un nom de 1 à 40 caractères.'):format(index)
        end

        if not from or not to then
            return nil, ("Point de TP « %s » : définissez le départ et l'arrivée."):format(label)
        end

        content.tp[#content.tp + 1] = { label = label, from = from, to = to }
    end

    local vehicles = type(data.vehicles) == 'table' and data.vehicles or {}

    if #vehicles > LIMITS.vehicles then
        return nil, ('%d véhicules au maximum.'):format(LIMITS.vehicles)
    end

    for index, entry in ipairs(vehicles) do
        local model = type(entry.model) == 'string' and entry.model:lower():match('^[%w_]+$')
        local spot = position(entry, true)

        if not model or #model > 30 then
            return nil, ('Véhicule n°%d : nom de modèle invalide (ex. adder).'):format(index)
        end

        if VEHICLE_TYPES[entry.type] ~= true then
            return nil, ('Véhicule %s : type invalide.'):format(model)
        end

        if not spot then
            return nil, ('Véhicule %s : définissez sa position.'):format(model)
        end

        content.vehicles[#content.vehicles + 1] = { model = model, type = entry.type, x = spot.x, y = spot.y, z = spot.z, h = spot.h }
    end

    return content
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

    local content, contentError = readContent(type(data.content) == 'table' and data.content or {})

    if not content then
        return nil, Panel.fail(contentError)
    end

    return {
        label = label, description = description, maxPlayers = maxPlayers, duration = duration, radius = radius,
        volume = volume, hour = hour, audio = audio, x = x, y = y, z = z, rules = rules, content = content,
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

    MySQL.update.await('UPDATE `lunatic_event_zones` SET `content` = ? WHERE `id` = ?', { json.encode(fields.content), id })

    local row = MySQL.single.await('SELECT * FROM `lunatic_event_zones` WHERE `id` = ?', { id })
    local wasLoaded = event and event.loadedAt
    events[id] = fromRow(row)
    refreshParticipants(events[id])
    publish()

    -- Event chargé : les véhicules sont reposés tels qu'enregistrés (les objets valent pour les prochaines entrées)
    if wasLoaded then
        spawnVehicles(events[id])
    end

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

    MySQL.update.await('UPDATE `lunatic_event_zones` SET `content` = ? WHERE `id` = ?', { json.encode(event.content), id })
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
    spawnVehicles(event)

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
