-- Reports (menu admin, doc Vision) : le joueur écrit /report <message> en jeu, le staff les traite dans la page Reports
-- du panel (prendre en charge, discuter, aller vers, ramener, fermer avec une réponse). Un report ouvert à la fois par
-- joueur : un nouveau /report pendant qu'il est ouvert ajoute un message à la discussion.
-- Alertes (nouveau report, message du joueur, rappel) : seulement aux staff en mode administration (server/adminmode.lua).
-- Tables lunatic_reports et lunatic_report_messages ; les reports en cours et les 30 derniers fermés sont en mémoire.

Reports = {}

local MESSAGE_MIN, MESSAGE_MAX, ANSWER_MAX = 5, 300, 300
local COOLDOWN = 60          -- secondes entre deux nouveaux reports d'un même joueur
local REPLY_COOLDOWN = 5     -- secondes entre deux messages d'un joueur dans son report
local CLOSED_KEPT = 30
local MESSAGES_KEPT = 40     -- messages gardés par report pour le panel
local REMINDER = 300         -- rappel des reports en attente aux staff en mode administration (secondes)

local list = {}     -- id -> report
local lastSent = {} -- license -> os.time du dernier report
local lastReply = {} -- license -> os.time du dernier message

local function licenseOf(src)
    return GetPlayerIdentifierByType(src, 'license')
end

-- Joueur connecté pour une licence (le reporter peut s'être reconnecté avec un autre id)
local function sourceOf(license)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)

        if licenseOf(src) == license then
            return src
        end
    end
end

local function playerName(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.getName() or GetPlayerName(src) or ('Joueur %d'):format(src)
end

local function cleanText(value, max)
    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('[<>]', ''):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)
    return length and length <= max and text or nil
end

local function fromRow(row)
    return {
        id = tonumber(row.id), license = row.reporter_license, name = row.reporter_name, message = row.message, status = row.status,
        staff = row.staff_name ~= '' and row.staff_name or nil, staffLicense = row.staff_license ~= '' and row.staff_license or nil,
        answer = row.answer ~= '' and row.answer or nil, created = tonumber(row.created_at), taken = tonumber(row.taken_at), closed = tonumber(row.closed_at),
        messages = {},
    }
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_reports` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `reporter_license` VARCHAR(60) NOT NULL,
            `reporter_name` VARCHAR(80) NOT NULL,
            `message` VARCHAR(400) NOT NULL,
            `status` VARCHAR(10) NOT NULL DEFAULT 'open',
            `staff_license` VARCHAR(60) NOT NULL DEFAULT '',
            `staff_name` VARCHAR(80) NOT NULL DEFAULT '',
            `answer` VARCHAR(400) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            `taken_at` BIGINT NULL DEFAULT NULL,
            `closed_at` BIGINT NULL DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_reports_status` (`status`),
            KEY `idx_lunatic_reports_reporter` (`reporter_license`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_report_messages` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `report_id` INT NOT NULL,
            `author` VARCHAR(10) NOT NULL,
            `name` VARCHAR(80) NOT NULL,
            `message` VARCHAR(400) NOT NULL,
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_report_messages_report` (`report_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    list = {}

    for _, row in ipairs(MySQL.query.await("SELECT * FROM `lunatic_reports` WHERE `status` <> 'closed'") or {}) do
        list[tonumber(row.id)] = fromRow(row)
    end

    for _, row in ipairs(MySQL.query.await("SELECT * FROM `lunatic_reports` WHERE `status` = 'closed' ORDER BY `id` DESC LIMIT ?", { CLOSED_KEPT }) or {}) do
        list[tonumber(row.id)] = fromRow(row)
    end

    local ids = {}

    for id in pairs(list) do
        ids[#ids + 1] = id
    end

    if #ids > 0 then
        local rows = MySQL.query.await(('SELECT * FROM `lunatic_report_messages` WHERE `report_id` IN (%s) ORDER BY `id`'):format(('?,'):rep(#ids):sub(1, -2)), ids) or {}

        for _, row in ipairs(rows) do
            local report = list[tonumber(row.report_id)]

            if report then
                report.messages[#report.messages + 1] = { author = row.author, name = row.name, text = row.message, created = tonumber(row.created_at) }

                if #report.messages > MESSAGES_KEPT then
                    table.remove(report.messages, 1)
                end
            end
        end
    end
end)

-- Fermés en trop retirés de la mémoire (ils restent en base)
local function trimClosed()
    local closed = {}

    for id, report in pairs(list) do
        if report.status == 'closed' then
            closed[#closed + 1] = id
        end
    end

    table.sort(closed, function(a, b) return a > b end)

    for index = CLOSED_KEPT + 1, #closed do
        list[closed[index]] = nil
    end
end

-- Staff à prévenir : connectés, autorisés à traiter les reports et en mode administration (pas pendant leur RP)
local function alert(text)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)

        if AdminMode.isOn(src) and Staff.can(src, 'reports.manage') then
            Panel.notify(src, text, 'info')
        end
    end
end

-- Message du staff envoyé au joueur : dans le tchat (lunatic_chat) et en notification
local function tellPlayer(report, staffName, text)
    local target = sourceOf(report.license)

    if not target then
        return false
    end

    TriggerClientEvent('lunatic_chat:message', target, { kind = 'staff', author = ('Report #%d · %s'):format(report.id, staffName), text = text })
    Panel.notify(target, ('Report #%d · %s : %s'):format(report.id, staffName, text), 'info')
    return true
end

local function addMessage(report, author, name, text)
    local now = os.time()
    MySQL.insert.await('INSERT INTO `lunatic_report_messages` (`report_id`, `author`, `name`, `message`, `created_at`) VALUES (?, ?, ?, ?, ?)', {
        report.id, author, name:sub(1, 80), text, now,
    })
    report.messages[#report.messages + 1] = { author = author, name = name, text = text, created = now }

    if #report.messages > MESSAGES_KEPT then
        table.remove(report.messages, 1)
    end
end

-- Reports en cours pour le menu rapide (en attente d'abord), avec leur discussion
function Reports.activeList()
    local active = {}

    for _, report in pairs(list) do
        if report.status ~= 'closed' then
            local online = sourceOf(report.license)
            active[#active + 1] = {
                id = report.id, name = report.name, message = report.message, status = report.status, staff = report.staff,
                online = online ~= nil, serverId = online, messages = report.messages,
            }
        end
    end

    table.sort(active, function(a, b)
        if a.status ~= b.status then
            return a.status == 'open'
        end

        return a.id < b.id
    end)

    return active
end

function Reports.pendingCount()
    local count = 0

    for _, report in pairs(list) do
        if report.status == 'open' then
            count = count + 1
        end
    end

    return count
end

---------------------------------------------------------------------
-- /report <message> : nouveau report, ou message ajouté au report en cours
---------------------------------------------------------------------

RegisterCommand('report', function(src, args)
    if src == 0 then
        return
    end

    local license = licenseOf(src)
    local message = cleanText(table.concat(args, ' '), MESSAGE_MAX)

    if not license then
        return
    end

    if not message or utf8.len(message) < MESSAGE_MIN then
        return Panel.notify(src, ('Utilisation : /report <message> (de %d à %d caractères).'):format(MESSAGE_MIN, MESSAGE_MAX), 'error')
    end

    local name = playerName(src)

    -- Report en cours : le message rejoint sa discussion
    for _, report in pairs(list) do
        if report.license == license and report.status ~= 'closed' then
            if (lastReply[license] or 0) > os.time() - REPLY_COOLDOWN then
                return Panel.notify(src, 'Patientez quelques secondes entre deux messages.', 'error')
            end

            lastReply[license] = os.time()
            addMessage(report, 'player', name, message)
            Panel.notify(src, ('Message ajouté à votre report #%d.'):format(report.id), 'success')
            alert(('Report #%d · %s : %s'):format(report.id, name, message))
            Staff.broadcastRefresh()
            return
        end
    end

    if (lastSent[license] or 0) > os.time() - COOLDOWN then
        return Panel.notify(src, 'Patientez un peu avant de refaire un report.', 'error')
    end

    lastSent[license] = os.time()
    local now = os.time()
    local id = MySQL.insert.await('INSERT INTO `lunatic_reports` (`reporter_license`, `reporter_name`, `message`, `created_at`) VALUES (?, ?, ?, ?)', {
        license, name:sub(1, 80), message, now,
    })

    if not id then
        return Panel.notify(src, 'Report impossible pour le moment, réessayez.', 'error')
    end

    list[id] = { id = id, license = license, name = name, message = message, status = 'open', created = now, messages = {} }
    Panel.notify(src, ('Report #%d envoyé au staff. Pour lui écrire ensuite : /report <message>.'):format(id), 'success')
    alert(('Nouveau report #%d de %s : %s'):format(id, name, message))
    Staff.broadcastRefresh()
end, false)

-- Rappel régulier des reports en attente aux staff en mode administration
CreateThread(function()
    while true do
        Wait(REMINDER * 1000)
        local pending = Reports.pendingCount()

        if pending > 0 then
            alert(('%d report%s en attente : page Reports du panel.'):format(pending, pending > 1 and 's' or ''))
        end
    end
end)

---------------------------------------------------------------------
-- Panel : liste (état du panel) et actions
---------------------------------------------------------------------

table.insert(Panel.stateHooks, function(state, _, rank)
    state.reportsPending = Reports.pendingCount()

    if not Ranks.hasPermission(rank, 'reports.manage') then
        return
    end

    local reports = {}

    for _, report in pairs(list) do
        local online = sourceOf(report.license)
        reports[#reports + 1] = {
            id = report.id, name = report.name, message = report.message, status = report.status, staff = report.staff,
            mine = report.staffLicense ~= nil and report.staffLicense == state.me.license, answer = report.answer,
            created = report.created, taken = report.taken, closed = report.closed, online = online ~= nil, serverId = online,
            messages = report.messages,
        }
    end

    table.sort(reports, function(a, b) return a.id > b.id end)
    state.reports = reports
end)

local function reportFor(actor, data)
    if not Ranks.hasPermission(actor, 'reports.manage') then
        return nil, Panel.fail("Vous n'avez pas la permission de traiter les reports.")
    end

    local report = list[tonumber(data.id) or -1]

    if not report then
        return nil, Panel.fail('Report introuvable.')
    end

    return report
end

-- Prise en charge (aussi au premier message du staff)
local function take(src, report)
    local now = os.time()
    report.status, report.staff, report.staffLicense, report.taken = 'taken', Staff.displayName(src), Staff.licenseOf(src), now
    MySQL.update.await("UPDATE `lunatic_reports` SET `status` = 'taken', `staff_license` = ?, `staff_name` = ?, `taken_at` = ? WHERE `id` = ?", {
        report.staffLicense or '', (report.staff or ''):sub(1, 80), now, report.id,
    })

    local reporter = sourceOf(report.license)

    if reporter then
        Panel.notify(reporter, ('Votre report #%d est pris en charge par %s.'):format(report.id, report.staff), 'success')
    end

    Logs.add(src, 'reports.take', report.name, { report = report.id })
end

Panel.actions['reports.take'] = function(src, actor, data)
    local report, err = reportFor(actor, data)

    if not report then
        return err
    end

    if report.status ~= 'open' then
        return Panel.fail(report.status == 'closed' and 'Ce report est déjà fermé.' or ('Ce report est déjà pris en charge par %s.'):format(report.staff or 'un autre staff'))
    end

    take(src, report)
    return { ok = true }
end

-- Discussion : message du staff au joueur
Panel.actions['reports.message'] = function(src, actor, data)
    local report, err = reportFor(actor, data)

    if not report then
        return err
    end

    if report.status == 'closed' then
        return Panel.fail('Ce report est fermé.')
    end

    local text = cleanText(data.text, MESSAGE_MAX)

    if not text or text == '' then
        return Panel.fail(('Message : de 1 à %d caractères.'):format(MESSAGE_MAX))
    end

    if report.status == 'open' then
        take(src, report)
    end

    local name = Staff.displayName(src)
    addMessage(report, 'staff', name, text)
    local delivered = tellPlayer(report, name, text)

    return { ok = true, delivered = delivered }
end

Panel.actions['reports.close'] = function(src, actor, data)
    local report, err = reportFor(actor, data)

    if not report then
        return err
    end

    if report.status == 'closed' then
        return Panel.fail('Ce report est déjà fermé.')
    end

    local answer = data.answer == nil and '' or cleanText(data.answer, ANSWER_MAX)

    if not answer then
        return Panel.fail(('Réponse : %d caractères au maximum.'):format(ANSWER_MAX))
    end

    local now = os.time()
    report.status, report.closed, report.answer = 'closed', now, answer ~= '' and answer or nil
    report.staff = report.staff or Staff.displayName(src)
    report.staffLicense = report.staffLicense or Staff.licenseOf(src)
    MySQL.update.await("UPDATE `lunatic_reports` SET `status` = 'closed', `staff_license` = ?, `staff_name` = ?, `answer` = ?, `closed_at` = ? WHERE `id` = ?", {
        report.staffLicense or '', (report.staff or ''):sub(1, 80), answer, now, report.id,
    })

    local reporter = sourceOf(report.license)

    if reporter then
        Panel.notify(reporter, answer ~= '' and ('Report #%d fermé par le staff : %s'):format(report.id, answer) or ('Votre report #%d a été traité et fermé.'):format(report.id), 'info')
    end

    trimClosed()
    Logs.add(src, 'reports.close', report.name, { report = report.id, answer = answer ~= '' and answer or nil })
    return { ok = true }
end

-- Aller vers / ramener l'auteur : actions de la fiche joueur (mêmes permissions et protections)
local function playerAction(action)
    return function(src, actor, data)
        local report, err = reportFor(actor, data)

        if not report then
            return err
        end

        local target = sourceOf(report.license)

        if not target then
            return Panel.fail("L'auteur du report n'est plus connecté.")
        end

        return Panel.actions[action](src, actor, { serverId = target })
    end
end

Panel.actions['reports.goto'] = playerAction('player.goto')
Panel.actions['reports.bring'] = playerAction('player.bring')

AddEventHandler('playerDropped', function()
    local license = licenseOf(source)

    if license then
        lastReply[license] = nil
    end
end)
