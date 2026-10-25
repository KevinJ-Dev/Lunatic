-- Lot J : planning d'events. Création, modification et annulation depuis le panel, annonces automatiques
-- (rappel puis début), point sur la carte des joueurs, commandes /events et /eventgps.
-- Les dates sont en secondes Unix : le tchat les affiche à l'heure du PC de chaque joueur (jeton {date:...}).

local REMINDER = Config.EventReminderMinutes * 60
local START_GRACE = 600 -- un event dont le début est raté de plus de 10 min (serveur éteint) n'est pas annoncé
local BLIP_AFTER = Config.EventBlipMinutes * 60

---@type table<number, table> events programmés ou en cours (gardés jusqu'à la fin de leur point sur la carte)
local active = {}
local lastBlips = nil

local now = Util.now

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les events.")
end

local cleanText = Util.cleanTextOrEmpty

local function toEvent(row)
    return {
        id = tonumber(row.id),
        title = row.title,
        description = row.description or '',
        place = row.place or '',
        coords = row.x and { x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z) } or nil,
        startsAt = tonumber(row.starts_at),
        status = row.status,
        reminded = row.reminded == true or row.reminded == 1,
        createdBy = row.created_by,
    }
end

---------------------------------------------------------------------
-- Annonces et points sur la carte
---------------------------------------------------------------------

-- {date:123} : remplacé par le tchat Lunatic par la date locale du joueur ; heure du serveur sinon
local function dateToken(timestamp)
    return ('{date:%d}'):format(timestamp)
end

local function plain(text)
    return (text:gsub('{date:(%d+)}', function(ts)
        return os.date('%d/%m à %H:%M', tonumber(ts))
    end))
end

local function announce(text, target)
    target = target or -1

    if GetResourceState('lunatic_chat') == 'started' then
        TriggerClientEvent('lunatic_chat:message', target, { kind = 'announce', tag = 'Event', text = text })
    else
        TriggerClientEvent('esx:showNotification', target, plain(text), 'info')
    end
end

local function where(event)
    return event.place ~= '' and (' · ' .. event.place) or ''
end

-- Points visibles du rappel jusqu'à la fin de la fenêtre après le début
local function publishBlips()
    local blips = {}
    local t = now()

    for _, event in pairs(active) do
        if event.coords and event.status ~= 'cancelled' and t >= event.startsAt - REMINDER and t <= event.startsAt + BLIP_AFTER then
            blips[#blips + 1] = { id = event.id, title = event.title, x = event.coords.x, y = event.coords.y, z = event.coords.z }
        end
    end

    local signature = json.encode(blips)

    if signature ~= lastBlips then
        lastBlips = signature
        GlobalState.lunaticEventBlips = blips
    end
end

local function loadActive()
    local rows = MySQL.query.await("SELECT * FROM `lunatic_admin_events` WHERE `status` IN ('scheduled', 'started') AND `starts_at` >= ?", { now() - BLIP_AFTER }) or {}
    active = {}

    for _, row in ipairs(rows) do
        local event = toEvent(row)
        active[event.id] = event
    end

    publishBlips()
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_admin_events` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `title` VARCHAR(80) NOT NULL,
            `description` VARCHAR(500) NOT NULL DEFAULT '',
            `place` VARCHAR(80) NOT NULL DEFAULT '',
            `x` DOUBLE NULL DEFAULT NULL,
            `y` DOUBLE NULL DEFAULT NULL,
            `z` DOUBLE NULL DEFAULT NULL,
            `starts_at` BIGINT NOT NULL,
            `status` VARCHAR(10) NOT NULL DEFAULT 'scheduled',
            `reminded` TINYINT(1) NOT NULL DEFAULT 0,
            `created_by` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_admin_events_start` (`status`, `starts_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Events restés ouverts pendant que le serveur était éteint : clos sans annonce
    MySQL.update.await("UPDATE `lunatic_admin_events` SET `status` = 'done' WHERE `status` IN ('scheduled', 'started') AND `starts_at` < ?", { now() - BLIP_AFTER })
    loadActive()
end)

-- Rappel et début : vérifiés toutes les 10 secondes
CreateThread(function()
    while true do
        Wait(10000)
        local t = now()

        for id, event in pairs(active) do
            if event.status == 'scheduled' and not event.reminded and t >= event.startsAt - REMINDER and t < event.startsAt then
                event.reminded = true
                MySQL.update('UPDATE `lunatic_admin_events` SET `reminded` = 1 WHERE `id` = ?', { id })
                announce(('Rappel : « %s » commence dans %d minutes (%s)%s.%s'):format(event.title, math.max(1, math.floor((event.startsAt - t) / 60 + 0.5)),
                    dateToken(event.startsAt), where(event), event.coords and ' Un point est ajouté sur votre carte (/eventgps pour l\'itinéraire).' or ''))
            end

            if event.status == 'scheduled' and t >= event.startsAt then
                event.status = 'started'
                MySQL.update("UPDATE `lunatic_admin_events` SET `status` = 'started' WHERE `id` = ?", { id })

                if t - event.startsAt <= START_GRACE then
                    announce(('« %s » commence maintenant%s !%s'):format(event.title, where(event), event.coords and ' Tapez /eventgps pour vous y rendre.' or ''))
                end
            end

            if t > event.startsAt + BLIP_AFTER then
                active[id] = nil
                MySQL.update("UPDATE `lunatic_admin_events` SET `status` = 'done' WHERE `id` = ? AND `status` = 'started'", { id })
            end
        end

        publishBlips()
    end
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

-- Champs communs à la création et à la modification
---@return table|nil fields, table|nil error
local function readFields(data)
    local title = cleanText(data.title, 3, 80)

    if not title then
        return nil, Panel.fail('Le titre doit faire entre 3 et 80 caractères.')
    end

    local description = cleanText(data.description, 0, 500)

    if not description then
        return nil, Panel.fail('La description fait 500 caractères au maximum.')
    end

    local place = cleanText(data.place, 0, 80)

    if not place then
        return nil, Panel.fail('Le lieu fait 80 caractères au maximum.')
    end

    local startsAt = tonumber(data.startsAt)

    if not startsAt or startsAt ~= math.floor(startsAt) or startsAt < now() + 60 or startsAt > now() + 366 * 86400 then
        return nil, Panel.fail("La date doit être dans le futur (au moins 1 minute) et dans moins d'un an.")
    end

    local coords = nil

    if type(data.coords) == 'table' then
        local x, y, z = tonumber(data.coords.x), tonumber(data.coords.y), tonumber(data.coords.z)

        if not x or not y or not z or math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 5000 then
            return nil, Panel.fail('Position invalide.')
        end

        coords = { x = x, y = y, z = z }
    end

    return { title = title, description = description, place = place, startsAt = startsAt, coords = coords }
end

Panel.actions['events.list'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'events.manage') then
        return denied()
    end

    local rows = MySQL.query.await('SELECT * FROM `lunatic_admin_events` WHERE `starts_at` >= ? ORDER BY `starts_at` DESC LIMIT 100', { now() - 30 * 86400 }) or {}
    local list = {}

    for _, row in ipairs(rows) do
        list[#list + 1] = toEvent(row)
    end

    return { ok = true, silent = true, events = list, reminder = Config.EventReminderMinutes }
end

Panel.actions['events.create'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'events.manage') then
        return denied()
    end

    local fields, err = readFields(data)

    if not fields then
        return err
    end

    -- Pas de valeur nil au milieu des paramètres SQL : la position est écrite à part
    local id = MySQL.insert.await('INSERT INTO `lunatic_admin_events` (`title`, `description`, `place`, `starts_at`, `reminded`, `created_by`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        fields.title, fields.description, fields.place, fields.startsAt,
        -- Event dans moins de 15 min : pas de rappel séparé
        fields.startsAt - now() <= REMINDER and 1 or 0,
        Staff.displayName(src), now(),
    })

    if not id then
        return Panel.fail('Enregistrement impossible (voir la console du serveur).')
    end

    if fields.coords then
        MySQL.update.await('UPDATE `lunatic_admin_events` SET `x` = ?, `y` = ?, `z` = ? WHERE `id` = ?', { fields.coords.x, fields.coords.y, fields.coords.z, id })
    end

    loadActive()

    if data.announce == true then
        announce(('Nouvel event : « %s » le %s%s.%s'):format(fields.title, dateToken(fields.startsAt), where(fields),
            fields.description ~= '' and (' ' .. fields.description) or ''))
    end

    Logs.add(src, 'events.create', nil, { id = id, title = fields.title, startsAt = fields.startsAt, place = fields.place })
    return { ok = true, silent = true, id = id }
end

Panel.actions['events.update'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'events.manage') then
        return denied()
    end

    local id = tonumber(data.id)
    local row = id and MySQL.single.await('SELECT * FROM `lunatic_admin_events` WHERE `id` = ?', { id })

    if not row or row.status ~= 'scheduled' then
        return Panel.fail("Seul un event programmé (pas encore commencé) peut être modifié.")
    end

    local fields, err = readFields(data)

    if not fields then
        return err
    end

    local before = toEvent(row)
    -- Nouvelle date : le rappel est de nouveau prévu (sauf si l'event est dans moins de 15 min)
    local reminded = before.reminded and fields.startsAt == before.startsAt or fields.startsAt - now() <= REMINDER

    MySQL.update.await('UPDATE `lunatic_admin_events` SET `title` = ?, `description` = ?, `place` = ?, `starts_at` = ?, `reminded` = ? WHERE `id` = ?', {
        fields.title, fields.description, fields.place, fields.startsAt, reminded and 1 or 0, id,
    })

    if fields.coords then
        MySQL.update.await('UPDATE `lunatic_admin_events` SET `x` = ?, `y` = ?, `z` = ? WHERE `id` = ?', { fields.coords.x, fields.coords.y, fields.coords.z, id })
    else
        MySQL.update.await('UPDATE `lunatic_admin_events` SET `x` = NULL, `y` = NULL, `z` = NULL WHERE `id` = ?', { id })
    end

    loadActive()

    if data.announce == true then
        announce(('Event modifié : « %s » le %s%s.'):format(fields.title, dateToken(fields.startsAt), where(fields)))
    end

    Logs.add(src, 'events.update', nil, { id = id, title = fields.title, startsAt = fields.startsAt, before = before.startsAt })
    return { ok = true, silent = true }
end

Panel.actions['events.cancel'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'events.manage') then
        return denied()
    end

    local id = tonumber(data.id)
    local row = id and MySQL.single.await('SELECT * FROM `lunatic_admin_events` WHERE `id` = ?', { id })

    if not row or (row.status ~= 'scheduled' and row.status ~= 'started') then
        return Panel.fail('Event introuvable, déjà annulé ou terminé.')
    end

    -- Un event en cours est « terminé », un event à venir est « annulé »
    local event = toEvent(row)
    MySQL.update.await('UPDATE `lunatic_admin_events` SET `status` = ? WHERE `id` = ?', { event.status == 'started' and 'done' or 'cancelled', id })
    loadActive()

    if data.announce ~= false then
        announce(event.status == 'started'
            and ('L\'event « %s » est terminé. Merci à tous !'):format(event.title)
            or ('L\'event « %s » prévu le %s est annulé.'):format(event.title, dateToken(event.startsAt)))
    end

    Logs.add(src, event.status == 'started' and 'events.finish' or 'events.cancel', nil, { id = id, title = event.title, startsAt = event.startsAt })
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Commandes joueurs
---------------------------------------------------------------------

local function upcoming()
    local list = {}

    for _, event in pairs(active) do
        if event.status ~= 'cancelled' then
            list[#list + 1] = event
        end
    end

    table.sort(list, function(a, b) return a.startsAt < b.startsAt end)
    return list
end

RegisterCommand('events', function(src)
    if src == 0 then
        return
    end

    local list = MySQL.query.await("SELECT * FROM `lunatic_admin_events` WHERE `status` IN ('scheduled', 'started') AND `starts_at` >= ? ORDER BY `starts_at` LIMIT 5", { now() - BLIP_AFTER }) or {}

    if #list == 0 then
        return announce('Aucun event prévu pour le moment.', src)
    end

    for _, row in ipairs(list) do
        local event = toEvent(row)
        local text = event.status == 'started' and ('En cours : « %s »%s.') or ('« %s » le %s%s.')

        if event.status == 'started' then
            text = text:format(event.title, where(event))
        else
            text = text:format(event.title, dateToken(event.startsAt), where(event))
        end

        announce(text .. (event.description ~= '' and (' ' .. event.description) or ''), src)
    end
end, false)

RegisterCommand('eventgps', function(src)
    if src == 0 then
        return
    end

    for _, event in ipairs(upcoming()) do
        if event.coords then
            TriggerClientEvent('lunatic_admin:eventWaypoint', src, event.coords, event.title)
            return
        end
    end

    TriggerClientEvent('esx:showNotification', src, "Aucun event avec un lieu sur la carte pour l'instant.", 'info')
end, false)

print('[lunatic_admin] Module Events chargé.')
