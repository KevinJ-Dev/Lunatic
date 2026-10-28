-- Reports (menu admin, doc Vision) : le joueur écrit /report <message> en jeu, le staff les traite dans la page Reports
-- du panel (prendre en charge, aller vers, ramener, fermer avec une réponse). Un report ouvert à la fois par joueur.
-- Table lunatic_reports ; les reports en cours et les 30 derniers fermés sont gardés en mémoire pour le panel.

Reports = {}

local MESSAGE_MIN, MESSAGE_MAX, ANSWER_MAX = 5, 300, 300
local COOLDOWN = 60 -- secondes entre deux reports d'un même joueur
local CLOSED_KEPT = 30

local list = {}     -- id -> report
local lastSent = {} -- license -> os.time du dernier report

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

    list = {}

    for _, row in ipairs(MySQL.query.await("SELECT * FROM `lunatic_reports` WHERE `status` <> 'closed'") or {}) do
        list[tonumber(row.id)] = fromRow(row)
    end

    for _, row in ipairs(MySQL.query.await("SELECT * FROM `lunatic_reports` WHERE `status` = 'closed' ORDER BY `id` DESC LIMIT ?", { CLOSED_KEPT }) or {}) do
        list[tonumber(row.id)] = fromRow(row)
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

-- Staff connectés pouvant traiter les reports (la partie « mode administration » filtrera ensuite)
local function staffToAlert()
    local targets = {}

    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)

        if Staff.can(src, 'reports.manage') then
            targets[#targets + 1] = src
        end
    end

    return targets
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
-- /report <message>
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

    for _, report in pairs(list) do
        if report.license == license and report.status ~= 'closed' then
            return Panel.notify(src, ('Votre report #%d est déjà en cours de traitement.'):format(report.id), 'error')
        end
    end

    if (lastSent[license] or 0) > os.time() - COOLDOWN then
        return Panel.notify(src, 'Patientez un peu avant de refaire un report.', 'error')
    end

    lastSent[license] = os.time()
    local name = playerName(src)
    local now = os.time()
    local id = MySQL.insert.await('INSERT INTO `lunatic_reports` (`reporter_license`, `reporter_name`, `message`, `created_at`) VALUES (?, ?, ?, ?)', {
        license, name:sub(1, 80), message, now,
    })

    if not id then
        return Panel.notify(src, 'Report impossible pour le moment, réessayez.', 'error')
    end

    list[id] = { id = id, license = license, name = name, message = message, status = 'open', created = now }
    Panel.notify(src, ('Report #%d envoyé au staff : restez disponible, un membre va vous répondre.'):format(id), 'success')

    for _, staff in ipairs(staffToAlert()) do
        Panel.notify(staff, ('Nouveau report #%d de %s : %s'):format(id, name, message), 'info')
    end

    Staff.broadcastRefresh()
end, false)

---------------------------------------------------------------------
-- Panel : liste (état du panel) et actions
---------------------------------------------------------------------

table.insert(Panel.stateHooks, function(state, _, rank)
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

Panel.actions['reports.take'] = function(src, actor, data)
    local report, err = reportFor(actor, data)

    if not report then
        return err
    end

    if report.status ~= 'open' then
        return Panel.fail(report.status == 'closed' and 'Ce report est déjà fermé.' or ('Ce report est déjà pris en charge par %s.'):format(report.staff or 'un autre staff'))
    end

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
    return { ok = true, message = ('Report #%d pris en charge.'):format(report.id) }
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
    return { ok = true, message = ('Report #%d fermé.'):format(report.id) }
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
