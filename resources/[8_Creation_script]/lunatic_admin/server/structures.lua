-- Lot E1 : entreprises et services publics. Une structure = un métier ESX (grades, salaires, membres)
-- + une fiche (type, lead, couleur, logo, icône radiale, bannière) + le temps de jeu de ses membres.
-- Les grades et les membres passent par les actions du Pôle emploi (server/poles.lua), autorisées ici par la tuile de la structure.

Structures = {}

local KINDS = {
    company = { permission = 'companies.manage', label = 'entreprise' },
    public = { permission = 'publics.manage', label = 'service public' },
}

---@type table<string, table> fiche par nom de métier
local byJob = {}

local function now()
    return os.time()
end

-- Permission de la tuile qui gère ce métier (nil si le métier n'a pas de fiche)
function Structures.permissionFor(jobName)
    local structure = byJob[jobName]
    return structure and KINDS[structure.kind].permission or nil
end

function Structures.get(jobName)
    return byJob[jobName]
end

exports('getStructure', function(jobName)
    return byJob[jobName]
end)

local function typesOf(kind)
    local types = {}

    for _, entry in ipairs(Config.StructureTypes[kind] or {}) do
        types[entry.id] = entry.label
    end

    return types
end

local function toStructure(row)
    return {
        job = row.job,
        kind = row.kind,
        type = row.type,
        lead = row.lead,
        color = row.color,
        logo = row.logo or '',
        radialIcon = row.radial_icon or '',
        banner = row.banner or '',
        createdBy = row.created_by,
        createdAt = tonumber(row.created_at),
    }
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_structures` (
            `job` VARCHAR(50) NOT NULL,
            `kind` VARCHAR(10) NOT NULL,
            `type` VARCHAR(20) NOT NULL,
            `lead` VARCHAR(60) NULL DEFAULT NULL,
            `color` VARCHAR(7) NOT NULL DEFAULT '#9650ff',
            `logo` VARCHAR(255) NOT NULL DEFAULT '',
            `radial_icon` VARCHAR(60) NOT NULL DEFAULT '',
            `banner` VARCHAR(255) NOT NULL DEFAULT '',
            `created_by` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`job`),
            KEY `idx_lunatic_structures_kind` (`kind`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Minutes passées connecté avec le métier de la structure
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_structure_playtime` (
            `job` VARCHAR(50) NOT NULL,
            `identifier` VARCHAR(60) NOT NULL,
            `minutes` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`job`, `identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_structures`') or {}) do
        byJob[row.job] = toStructure(row)
    end
end)

-- Temps de jeu : +1 minute par membre connecté, chaque minute
CreateThread(function()
    while true do
        Wait(60000)

        local placeholders, values = {}, {}

        for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
            local job = xPlayer.getJob()

            if job and byJob[job.name] then
                placeholders[#placeholders + 1] = '(?, ?, 1)'
                values[#values + 1] = job.name
                values[#values + 1] = xPlayer.identifier
            end
        end

        if #placeholders > 0 then
            MySQL.query(('INSERT INTO `lunatic_structure_playtime` (`job`, `identifier`, `minutes`) VALUES %s ON DUPLICATE KEY UPDATE `minutes` = `minutes` + 1')
                :format(table.concat(placeholders, ', ')), values)
        end
    end
end)

---------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

local function cleanText(value, min, max)
    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length >= min and length <= max and text or nil
end

-- '' ou une adresse http(s) de 255 caractères maximum
local function cleanUrl(value)
    if value == nil or value == '' then
        return ''
    end

    if type(value) ~= 'string' or #value > 255 or not value:match('^https?://[%w%-%._~:/%?#%[%]@!%$&\'%(%)%*%+,;=%%]+$') then
        return nil
    end

    return value
end

-- Fiche + contrôle de la permission de sa tuile
---@return table|nil structure, table|nil error
local function structureFor(actor, jobName)
    local structure = type(jobName) == 'string' and byJob[jobName]

    if not structure then
        return nil, Panel.fail('Structure introuvable.')
    end

    if not Ranks.hasPermission(actor, KINDS[structure.kind].permission) then
        return nil, denied()
    end

    return structure
end

local function membersCount()
    local totals, online = {}, {}

    for _, row in ipairs(MySQL.query.await('SELECT `job`, COUNT(*) AS `n` FROM `users` GROUP BY `job`') or {}) do
        totals[row.job] = tonumber(row.n) or 0
    end

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local job = xPlayer.getJob()

        if job then
            online[job.name] = (online[job.name] or 0) + 1
        end
    end

    return totals, online
end

local function nameOf(identifier)
    if not identifier then
        return nil
    end

    local src = Staff.sourceOf('license:' .. identifier)

    if src then
        return Staff.displayName(src)
    end

    local row = MySQL.single.await('SELECT `firstname`, `lastname` FROM `users` WHERE `identifier` = ?', { identifier })
    return row and row.firstname and ('%s %s'):format(row.firstname, row.lastname or '') or identifier
end

---------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------

Panel.actions['structures.list'] = function(_, actor, data)
    local kind = KINDS[data.kind] and data.kind

    if not kind then
        return Panel.fail('Catégorie inconnue.')
    end

    if not Ranks.hasPermission(actor, KINDS[kind].permission) then
        return denied()
    end

    local jobs = ESX.GetJobs()
    local totals, online = membersCount()
    local types = typesOf(kind)
    local list, orphans = {}, {}

    for name, structure in pairs(byJob) do
        local job = jobs[name]

        if structure.kind == kind and job then
            local grades = 0

            for _ in pairs(job.grades or {}) do
                grades = grades + 1
            end

            list[#list + 1] = {
                job = name, label = job.label, type = structure.type, typeLabel = types[structure.type] or structure.type,
                color = structure.color, logo = structure.logo, grades = grades, online = online[name] or 0, total = totals[name] or 0,
            }
        end
    end

    -- Métiers du Pôle emploi qui peuvent recevoir une fiche
    for name, job in pairs(jobs) do
        if not byJob[name] and name ~= 'unemployed' then
            orphans[#orphans + 1] = { name = name, label = job.label }
        end
    end

    table.sort(list, function(a, b) return (a.label or a.job) < (b.label or b.job) end)
    table.sort(orphans, function(a, b) return (a.label or a.name) < (b.label or b.name) end)

    return { ok = true, silent = true, structures = list, orphans = orphans, types = Config.StructureTypes[kind] }
end

Panel.actions['structures.info'] = function(src, actor, data)
    local structure, err = structureFor(actor, data.job)

    if not structure then
        return err
    end

    -- Grades et membres : même lecture que le Pôle emploi
    local result = Panel.actions['poles.info'](src, actor, { job = structure.job })

    if not result.ok then
        return result
    end

    local playtime = {}

    for _, row in ipairs(MySQL.query.await('SELECT `identifier`, `minutes` FROM `lunatic_structure_playtime` WHERE `job` = ?', { structure.job }) or {}) do
        playtime[row.identifier] = tonumber(row.minutes) or 0
    end

    for _, member in ipairs(result.job.members) do
        member.playtime = playtime[member.identifier] or 0
    end

    local info = result.job
    info.structure = structure
    info.points = StructurePoints.ofJob(structure.job)
    info.catalogs = Catalogs.ofJob(structure.job)
    info.allCatalogs = Catalogs.all()
    info.pointTypes = {}

    for _, entry in ipairs(Config.StructurePointTypes) do
        if entry.kinds == 'both' or entry.kinds == structure.kind then
            info.pointTypes[#info.pointTypes + 1] = entry
        end
    end

    -- Compte de société (resource lunatic_business)
    if GetResourceState('lunatic_business') == 'started' then
        info.account = {
            balance = exports.lunatic_business:getBalance(structure.job),
            history = exports.lunatic_business:getHistory(structure.job, 30),
        }
    end
    info.typeLabel = typesOf(structure.kind)[structure.type] or structure.type
    info.leadName = nameOf(structure.lead)

    return { ok = true, silent = true, job = info, types = Config.StructureTypes[structure.kind] }
end

---------------------------------------------------------------------
-- Création, fiche, suppression
---------------------------------------------------------------------

-- Le membre du staff prend le métier de la structure (grade le plus bas, modifiable ensuite)
Panel.actions['structures.join'] = function(src, actor, data)
    local structure, err = structureFor(actor, data.job)

    if not structure then
        return err
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local job = ESX.GetJobs()[structure.job]

    if not xPlayer or not job then
        return Panel.fail("Votre personnage n'est pas chargé.")
    end

    local lowest

    for _, grade in pairs(job.grades or {}) do
        local number = tonumber(grade.grade)

        if not lowest or number < lowest then
            lowest = number
        end
    end

    return Panel.actions['poles.setMember'](src, actor, { job = structure.job, identifier = xPlayer.identifier, grade = lowest or 0 })
end

Panel.actions['structures.create'] = function(src, actor, data)
    local kind = KINDS[data.kind] and data.kind

    if not kind then
        return Panel.fail('Catégorie inconnue.')
    end

    if not Ranks.hasPermission(actor, KINDS[kind].permission) then
        return denied()
    end

    if not typesOf(kind)[data.type] then
        return Panel.fail('Type inconnu.')
    end

    local jobName

    if data.mode == 'existing' then
        -- Un métier du Pôle emploi reçoit une fiche (il quitte alors le Pôle emploi)
        jobName = type(data.job) == 'string' and data.job or ''
        local job = ESX.GetJobs()[jobName]

        if not job or jobName == 'unemployed' then
            return Panel.fail('Métier introuvable.')
        end

        if byJob[jobName] then
            return Panel.fail('Ce métier a déjà une fiche.')
        end

        MySQL.update.await('UPDATE `jobs` SET `whitelisted` = 1 WHERE `name` = ?', { jobName })
        ESX.RefreshJob(jobName)
    else
        -- Nouveau métier : jamais proposé au pôle emploi (liste blanche)
        local created = Poles.createJob(src, { name = data.name, label = data.label, grades = data.grades, whitelisted = true })

        if not created.ok then
            return created
        end

        jobName = created.name
    end

    MySQL.insert.await('INSERT INTO `lunatic_structures` (`job`, `kind`, `type`, `created_by`, `created_at`) VALUES (?, ?, ?, ?, ?)', {
        jobName, kind, data.type, Staff.displayName(src), now(),
    })

    byJob[jobName] = toStructure(MySQL.single.await('SELECT * FROM `lunatic_structures` WHERE `job` = ?', { jobName }))
    Logs.add(src, 'structures.create', nil, { job = jobName, kind = kind, type = data.type, mode = data.mode == 'existing' and 'existing' or 'new' })

    return { ok = true, silent = true, job = jobName }
end

Panel.actions['structures.save'] = function(src, actor, data)
    local structure, err = structureFor(actor, data.job)

    if not structure then
        return err
    end

    local label = cleanText(data.label, 2, 50)

    if not label then
        return Panel.fail('Le label doit faire entre 2 et 50 caractères.')
    end

    if not typesOf(structure.kind)[data.type] then
        return Panel.fail('Type inconnu.')
    end

    -- Lead (services publics) : un identifiant ESX ou rien
    local lead = nil

    if structure.kind == 'public' and type(data.lead) == 'string' and data.lead ~= '' then
        lead = data.lead:gsub('^license:', '')

        if not lead:match('^%x+$') or #lead > 60 then
            return Panel.fail('Lead invalide.')
        end
    end

    local color = structure.color

    if structure.kind == 'company' then
        color = type(data.color) == 'string' and data.color:match('^#%x%x%x%x%x%x$') and data.color:lower()

        if not color then
            return Panel.fail('Couleur invalide.')
        end
    end

    local logo, banner = cleanUrl(data.logo), cleanUrl(data.banner)

    if not logo or not banner then
        return Panel.fail('Logo et bannière : adresse http(s) valide de 255 caractères maximum, ou vide.')
    end

    local radialIcon = type(data.radialIcon) == 'string' and data.radialIcon:match('^%s*([%w%- ]*)%s*$')

    if not radialIcon or #radialIcon > 60 then
        return Panel.fail("Icône radiale : nom d'icône de 60 caractères maximum (ex. fa-solid fa-utensils).")
    end

    MySQL.update.await('UPDATE `lunatic_structures` SET `type` = ?, `lead` = ?, `color` = ?, `logo` = ?, `radial_icon` = ?, `banner` = ? WHERE `job` = ?', {
        data.type, lead or '', color, logo, radialIcon, banner, structure.job,
    })

    if lead == nil then
        MySQL.update.await('UPDATE `lunatic_structures` SET `lead` = NULL WHERE `job` = ?', { structure.job })
    end

    local job = ESX.GetJobs()[structure.job]

    if job and job.label ~= label then
        MySQL.update.await('UPDATE `jobs` SET `label` = ? WHERE `name` = ?', { label, structure.job })
        ESX.RefreshJob(structure.job)
    end

    byJob[structure.job] = toStructure(MySQL.single.await('SELECT * FROM `lunatic_structures` WHERE `job` = ?', { structure.job }))
    Logs.add(src, 'structures.save', nil, { job = structure.job, label = label, type = data.type })

    return { ok = true, silent = true }
end

-- Supprime la fiche et le métier ESX (refusé tant qu'il reste des membres)
Panel.actions['structures.delete'] = function(src, actor, data)
    local structure, err = structureFor(actor, data.job)

    if not structure then
        return err
    end

    local result = Panel.actions['poles.delete'](src, actor, { job = structure.job })

    if not result.ok then
        return result
    end

    MySQL.update.await('DELETE FROM `lunatic_structures` WHERE `job` = ?', { structure.job })
    MySQL.update.await('DELETE FROM `lunatic_structure_playtime` WHERE `job` = ?', { structure.job })
    byJob[structure.job] = nil
    StructurePoints.deleteJob(structure.job)
    Catalogs.deleteJob(structure.job)
    Logs.add(src, 'structures.delete', nil, { job = structure.job, kind = structure.kind })

    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Compte de société : ajout ou retrait par le staff, avec motif
---------------------------------------------------------------------

Panel.actions['structures.account'] = function(src, actor, data)
    local structure, err = structureFor(actor, data.job)

    if not structure then
        return err
    end

    if GetResourceState('lunatic_business') ~= 'started' then
        return Panel.fail("La resource lunatic_business n'est pas démarrée.")
    end

    local amount = tonumber(data.amount)

    if not amount or amount ~= math.floor(amount) or amount == 0 or math.abs(amount) > Config.StructureAccountMaxAction then
        return Panel.fail(('Montant invalide : nombre entier non nul, %d au maximum.'):format(Config.StructureAccountMaxAction))
    end

    local reason = cleanText(data.reason, 3, 120)

    if not reason then
        return Panel.fail('Le motif doit faire entre 3 et 120 caractères.')
    end

    local actorName = ('Staff : %s'):format(Staff.displayName(src))
    local ok

    if amount > 0 then
        ok = exports.lunatic_business:addMoney(structure.job, amount, reason, actorName)
    else
        ok = exports.lunatic_business:removeMoney(structure.job, -amount, reason, actorName)
    end

    if not ok then
        return Panel.fail(amount > 0 and 'Opération impossible.' or 'Solde insuffisant.')
    end

    Logs.add(src, 'structures.account', nil, { job = structure.job, amount = amount, reason = reason })
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Membres : ajout par ID en jeu ou par nom RP
---------------------------------------------------------------------

Panel.actions['structures.addMember'] = function(src, actor, data)
    local structure, err = structureFor(actor, data.job)

    if not structure then
        return err
    end

    local identifier = type(data.identifier) == 'string' and data.identifier:gsub('^license:', '') or nil
    local query = type(data.query) == 'string' and data.query:match('^%s*(.-)%s*$') or ''

    if not identifier then
        local serverId = tonumber(query)

        if serverId then
            local xPlayer = ESX.GetPlayerFromId(serverId)

            if not xPlayer then
                return Panel.fail(("Aucun joueur connecté avec l'ID %d."):format(serverId))
            end

            identifier = xPlayer.identifier
        else
            if utf8.len(query) == nil or utf8.len(query) < 2 then
                return Panel.fail('Indiquez un ID en jeu ou au moins 2 lettres du nom RP.')
            end

            local like = '%' .. query:gsub('[%%_\\]', '\\%0') .. '%'
            local rows = MySQL.query.await([[
                SELECT `identifier`, `firstname`, `lastname`, `job` FROM `users`
                WHERE CONCAT(`firstname`, ' ', `lastname`) LIKE ? ORDER BY `lastname` LIMIT 10
            ]], { like }) or {}

            if #rows == 0 then
                return Panel.fail('Aucun personnage ne correspond.')
            end

            if #rows > 1 then
                local candidates = {}
                local jobs = ESX.GetJobs()

                for _, row in ipairs(rows) do
                    candidates[#candidates + 1] = {
                        identifier = row.identifier,
                        name = ('%s %s'):format(row.firstname or '?', row.lastname or ''),
                        job = jobs[row.job] and jobs[row.job].label or row.job,
                    }
                end

                return { ok = true, silent = true, candidates = candidates }
            end

            identifier = rows[1].identifier
        end
    end

    -- Grade le plus bas = embauche
    local lowest

    for _, grade in pairs(ESX.GetJobs()[structure.job].grades or {}) do
        local number = tonumber(grade.grade)

        if not lowest or number < lowest then
            lowest = number
        end
    end

    local result = Panel.actions['poles.setMember'](src, actor, { job = structure.job, identifier = identifier, grade = lowest or 0 })

    if result.ok then
        result.name = nameOf(identifier)
    end

    return result
end

print('[lunatic_admin] Module Entreprises et services publics chargé.')
