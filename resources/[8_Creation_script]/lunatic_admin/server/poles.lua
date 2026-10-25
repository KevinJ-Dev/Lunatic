-- Lot I : Pôle emploi = métiers ESX (tables jobs et job_grades). Liste, grades et salaires, membres, création et suppression.
-- Les métiers d'une entreprise ou d'un service public (server/structures.lua) n'apparaissent pas dans sa liste,
-- mais leurs grades et membres passent par les mêmes actions, autorisées par la permission de leur tuile.
-- Après chaque modification, ESX.RefreshJob recharge le métier et met à jour les joueurs connectés qui l'ont.
-- Le grade le plus haut d'un métier porte toujours le nom technique « boss » (repère ESX des patrons d'entreprise).

local UNEMPLOYED = 'unemployed'

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer ce métier.")
end

local cleanText = Util.cleanText

local function cleanSalary(value)
    local salary = tonumber(value)

    if not salary or salary ~= math.floor(salary) or salary < 0 or salary > Config.PolesMaxSalary then
        return nil
    end

    return math.floor(salary)
end

local function salaryError()
    return Panel.fail(('Salaire invalide : nombre entier de 0 à %d.'):format(Config.PolesMaxSalary))
end

-- Nom technique d'un grade à partir de son libellé (« Chef d'équipe » -> « chef_d_equipe »)
local ACCENTS = { ['à'] = 'a', ['â'] = 'a', ['ä'] = 'a', ['ç'] = 'c', ['é'] = 'e', ['è'] = 'e', ['ê'] = 'e', ['ë'] = 'e',
    ['î'] = 'i', ['ï'] = 'i', ['ô'] = 'o', ['ö'] = 'o', ['ù'] = 'u', ['û'] = 'u', ['ü'] = 'u', ['ÿ'] = 'y', ['œ'] = 'oe' }

local function slug(label, fallback)
    local text = label:lower()

    for accent, plain in pairs(ACCENTS) do
        text = text:gsub(accent, plain)
    end

    text = text:gsub('[^a-z0-9]+', '_'):gsub('^_+', ''):gsub('_+$', ''):sub(1, 40)
    return text ~= '' and text or fallback
end

local function gradeName(label, grade, isTop)
    return isTop and 'boss' or slug(label, 'grade_' .. grade)
end

local function getJob(name)
    if type(name) ~= 'string' then
        return nil
    end

    return ESX.GetJobs()[name]
end

local function sortedGrades(job)
    local grades = {}

    for _, grade in pairs(job.grades or {}) do
        grades[#grades + 1] = grade
    end

    table.sort(grades, function(a, b) return tonumber(a.grade) < tonumber(b.grade) end)
    return grades
end

-- Joueurs connectés ayant ce métier (identifiant ESX -> { source, grade })
local function onlineMembers(jobName)
    local members = {}

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local job = xPlayer.getJob()

        if job and job.name == jobName then
            members[xPlayer.identifier] = { source = xPlayer.source, grade = tonumber(job.grade) }
        end
    end

    return members
end

-- Nombre de membres (en base + connectés pas encore sauvegardés), éventuellement pour un seul grade
local function countMembers(jobName, grade)
    local online = onlineMembers(jobName)
    local rows = MySQL.query.await('SELECT `identifier`, `job_grade` FROM `users` WHERE `job` = ?', { jobName }) or {}
    local count = 0

    for _, row in ipairs(rows) do
        -- Un joueur connecté compte avec son métier actuel, pas celui de la base
        if not online[row.identifier] and (grade == nil or tonumber(row.job_grade) == grade) then
            count = count + 1
        end
    end

    for _, member in pairs(online) do
        if grade == nil or member.grade == grade then
            count = count + 1
        end
    end

    return count
end

local function refresh(jobName)
    ESX.RefreshJob(jobName)
end

-- Pôle emploi, ou tuile Entreprises / Services publics pour le métier d'une structure
local function canManage(actor, jobName)
    if Ranks.hasPermission(actor, 'poles.manage') then
        return true
    end

    local permission = Structures and type(jobName) == 'string' and Structures.permissionFor(jobName)
    return permission and Ranks.hasPermission(actor, permission) or false
end

Poles = { canManage = canManage }

---------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------

Panel.actions['poles.list'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'poles.manage') then
        return denied()
    end

    local totals = {}

    for _, row in ipairs(MySQL.query.await('SELECT `job`, COUNT(*) AS `n` FROM `users` GROUP BY `job`') or {}) do
        totals[row.job] = tonumber(row.n) or 0
    end

    local online = {}

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local job = xPlayer.getJob()

        if job then
            online[job.name] = (online[job.name] or 0) + 1
        end
    end

    local jobs = {}

    for name, job in pairs(ESX.GetJobs()) do
        if not (Structures and Structures.get(name)) then
            jobs[#jobs + 1] = {
                name = name,
                label = job.label,
                grades = #sortedGrades(job),
                online = online[name] or 0,
                total = totals[name] or 0,
                whitelisted = job.whitelisted == true or job.whitelisted == 1,
                protected = name == UNEMPLOYED,
            }
        end
    end

    table.sort(jobs, function(a, b) return (a.label or a.name) < (b.label or b.name) end)
    return { ok = true, silent = true, jobs = jobs }
end

Panel.actions['poles.info'] = function(src, actor, data)
    if not canManage(actor, data.job) then
        return denied()
    end

    local job = getJob(data.job)

    if not job then
        return Panel.fail('Métier introuvable.')
    end

    local online = onlineMembers(job.name)
    local myLicense = Staff.licenseOf(src)
    local perGrade = {}
    local members = {}

    -- Les chômeurs ne sont pas listés : ce serait tout le serveur
    if job.name ~= UNEMPLOYED then
        local rows = MySQL.query.await('SELECT `identifier`, `firstname`, `lastname`, `job_grade` FROM `users` WHERE `job` = ? LIMIT 500', { job.name }) or {}

        for _, row in ipairs(rows) do
            if not online[row.identifier] then
                local grade = tonumber(row.job_grade)
                members[#members + 1] = {
                    identifier = row.identifier,
                    name = row.firstname and row.firstname ~= '' and ('%s %s'):format(row.firstname, row.lastname or '') or 'Sans identité',
                    grade = grade,
                }
            end
        end

        for identifier, member in pairs(online) do
            members[#members + 1] = { identifier = identifier, name = Staff.displayName(member.source), grade = member.grade, online = member.source }
        end

        for _, member in ipairs(members) do
            perGrade[member.grade] = (perGrade[member.grade] or 0) + 1

            -- Membre du staff de rang égal ou supérieur : non modifiable (soi-même autorisé)
            local staff = Staff.get('license:' .. member.identifier)
            local rank = staff and Ranks.get(staff.rankId)
            member.protected = rank ~= nil and rank.level >= actor.level and 'license:' .. member.identifier ~= myLicense
        end

        table.sort(members, function(a, b)
            if a.grade ~= b.grade then
                return a.grade > b.grade
            end

            return a.name < b.name
        end)
    end

    local grades = {}

    for _, grade in ipairs(sortedGrades(job)) do
        local number = tonumber(grade.grade)
        grades[#grades + 1] = { grade = number, name = grade.name, label = grade.label, salary = tonumber(grade.salary) or 0, members = perGrade[number] or 0 }
    end

    return { ok = true, silent = true, job = {
        name = job.name,
        label = job.label,
        whitelisted = job.whitelisted == true or job.whitelisted == 1,
        protected = job.name == UNEMPLOYED,
        grades = grades,
        members = members,
        membersHidden = job.name == UNEMPLOYED,
    } }
end

---------------------------------------------------------------------
-- Métiers
---------------------------------------------------------------------

-- Création d'un métier (aussi utilisée par server/structures.lua, qui vérifie sa propre permission)
local function createJob(src, data)
    local name = type(data.name) == 'string' and data.name:lower() or ''

    if not name:match('^[a-z][a-z0-9_]+$') or #name > 30 then
        return Panel.fail('Nom technique invalide : 2 à 30 caractères, minuscules, chiffres et _ (commence par une lettre).')
    end

    local label = cleanText(data.label, 2, 50)

    if not label then
        return Panel.fail('Le nom affiché doit faire entre 2 et 50 caractères.')
    end

    if type(data.grades) ~= 'table' or #data.grades < 1 or #data.grades > Config.PolesMaxGrades then
        return Panel.fail(('Il faut entre 1 et %d grades.'):format(Config.PolesMaxGrades))
    end

    local exists = MySQL.scalar.await('SELECT COUNT(*) FROM `jobs` WHERE `name` = ?', { name })

    if (tonumber(exists) or 0) > 0 or getJob(name) then
        return Panel.fail('Un métier porte déjà ce nom technique.')
    end

    local queries = {
        { query = 'INSERT INTO `jobs` (`name`, `label`, `whitelisted`) VALUES (?, ?, ?)', values = { name, label, data.whitelisted == true and 1 or 0 } },
    }

    for index, entry in ipairs(data.grades) do
        local gradeLabel = type(entry) == 'table' and cleanText(entry.label, 1, 50)

        if not gradeLabel then
            return Panel.fail(('Grade %d : le nom doit faire entre 1 et 50 caractères.'):format(index))
        end

        local salary = cleanSalary(entry.salary)

        if not salary then
            return salaryError()
        end

        local grade = index - 1
        queries[#queries + 1] = {
            query = "INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`) VALUES (?, ?, ?, ?, ?, '{}', '{}')",
            values = { name, grade, gradeName(gradeLabel, grade, index == #data.grades), gradeLabel, salary },
        }
    end

    if not MySQL.transaction.await(queries) then
        return Panel.fail("Création impossible (voir la console du serveur).")
    end

    refresh(name)
    Logs.add(src, 'poles.create', nil, { job = name, label = label, grades = #data.grades })

    return { ok = true, silent = true, name = name }
end

Poles.createJob = createJob

Panel.actions['poles.create'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'poles.manage') then
        return denied()
    end

    return createJob(src, data)
end

Panel.actions['poles.rename'] = function(src, actor, data)
    if not canManage(actor, data.job) then
        return denied()
    end

    local job = getJob(data.job)

    if not job then
        return Panel.fail('Métier introuvable.')
    end

    local label = cleanText(data.label, 2, 50)

    if not label then
        return Panel.fail('Le nom affiché doit faire entre 2 et 50 caractères.')
    end

    MySQL.update.await('UPDATE `jobs` SET `label` = ? WHERE `name` = ?', { label, job.name })
    refresh(job.name)
    Logs.add(src, 'poles.rename', nil, { job = job.name, before = job.label, after = label })

    return { ok = true, silent = true }
end

-- Liste blanche ESX : le métier n'apparaît pas au pôle emploi (recrutement par le patron ou le staff seulement)
Panel.actions['poles.whitelist'] = function(src, actor, data)
    if not canManage(actor, data.job) then
        return denied()
    end

    local job = getJob(data.job)

    if not job then
        return Panel.fail('Métier introuvable.')
    end

    MySQL.update.await('UPDATE `jobs` SET `whitelisted` = ? WHERE `name` = ?', { data.enabled == true and 1 or 0, job.name })
    refresh(job.name)
    Logs.add(src, 'poles.whitelist', nil, { job = job.name, enabled = data.enabled == true })

    return { ok = true, silent = true }
end

Panel.actions['poles.delete'] = function(src, actor, data)
    if not canManage(actor, data.job) then
        return denied()
    end

    local job = getJob(data.job)

    if not job then
        return Panel.fail('Métier introuvable.')
    end

    if job.name == UNEMPLOYED then
        return Panel.fail('Le métier « sans emploi » est indispensable à ESX.')
    end

    local members = countMembers(job.name)

    if members > 0 then
        return Panel.fail(("Ce métier a encore %d membre(s) : renvoyez-les d'abord."):format(members))
    end

    MySQL.transaction.await({
        { query = 'DELETE FROM `job_grades` WHERE `job_name` = ?', values = { job.name } },
        { query = 'DELETE FROM `jobs` WHERE `name` = ?', values = { job.name } },
    })

    refresh(job.name)
    Logs.add(src, 'poles.delete', nil, { job = job.name, label = job.label })

    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Grades
---------------------------------------------------------------------

Panel.actions['poles.setGrade'] = function(src, actor, data)
    if not canManage(actor, data.job) then
        return denied()
    end

    local job = getJob(data.job)
    local grade = tonumber(data.grade)
    local current = job and grade and job.grades[tostring(grade)]

    if not current then
        return Panel.fail('Grade introuvable.')
    end

    local label = cleanText(data.label, 1, 50)

    if not label then
        return Panel.fail('Le nom du grade doit faire entre 1 et 50 caractères.')
    end

    local salary = cleanSalary(data.salary)

    if not salary then
        return salaryError()
    end

    -- Le nom technique suit le libellé, sauf pour le grade le plus haut (boss) et le chômeur
    local grades = sortedGrades(job)
    local isTop = tonumber(grades[#grades].grade) == grade
    local technical = job.name == UNEMPLOYED and current.name or gradeName(label, grade, isTop)

    MySQL.update.await('UPDATE `job_grades` SET `label` = ?, `salary` = ?, `name` = ? WHERE `job_name` = ? AND `grade` = ?', { label, salary, technical, job.name, grade })
    refresh(job.name)
    Logs.add(src, 'poles.grade', nil, {
        job = job.name, grade = grade, label = label, before = tonumber(current.salary) or 0, after = salary,
    })

    return { ok = true, silent = true }
end

-- Ajoute un grade au-dessus des autres : il devient le patron (boss)
Panel.actions['poles.addGrade'] = function(src, actor, data)
    if not canManage(actor, data.job) then
        return denied()
    end

    local job = getJob(data.job)

    if not job then
        return Panel.fail('Métier introuvable.')
    end

    if job.name == UNEMPLOYED then
        return Panel.fail('Le métier « sans emploi » garde un seul grade.')
    end

    local grades = sortedGrades(job)

    if #grades >= Config.PolesMaxGrades then
        return Panel.fail(('Maximum %d grades par métier.'):format(Config.PolesMaxGrades))
    end

    local label = cleanText(data.label, 1, 50)

    if not label then
        return Panel.fail('Le nom du grade doit faire entre 1 et 50 caractères.')
    end

    local salary = cleanSalary(data.salary)

    if not salary then
        return salaryError()
    end

    local top = grades[#grades]
    local grade = tonumber(top.grade) + 1

    MySQL.transaction.await({
        { query = 'UPDATE `job_grades` SET `name` = ? WHERE `job_name` = ? AND `grade` = ?', values = { gradeName(top.label, tonumber(top.grade), false), job.name, tonumber(top.grade) } },
        { query = "INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`) VALUES (?, ?, 'boss', ?, ?, '{}', '{}')", values = { job.name, grade, label, salary } },
    })

    refresh(job.name)
    Logs.add(src, 'poles.addGrade', nil, { job = job.name, grade = grade, label = label, salary = salary })

    return { ok = true, silent = true }
end

-- Supprime le grade le plus haut s'il n'a aucun membre ; le grade en dessous devient le patron
Panel.actions['poles.removeGrade'] = function(src, actor, data)
    if not canManage(actor, data.job) then
        return denied()
    end

    local job = getJob(data.job)

    if not job then
        return Panel.fail('Métier introuvable.')
    end

    local grades = sortedGrades(job)

    if #grades <= 1 then
        return Panel.fail('Un métier garde au moins un grade.')
    end

    local top = grades[#grades]
    local grade = tonumber(top.grade)
    local members = countMembers(job.name, grade)

    if members > 0 then
        return Panel.fail(('Le grade « %s » a encore %d membre(s).'):format(top.label, members))
    end

    local below = grades[#grades - 1]

    MySQL.transaction.await({
        { query = 'DELETE FROM `job_grades` WHERE `job_name` = ? AND `grade` = ?', values = { job.name, grade } },
        { query = "UPDATE `job_grades` SET `name` = 'boss' WHERE `job_name` = ? AND `grade` = ?", values = { job.name, tonumber(below.grade) } },
    })

    refresh(job.name)
    Logs.add(src, 'poles.removeGrade', nil, { job = job.name, grade = grade, label = top.label })

    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Membres (connectés ou non)
---------------------------------------------------------------------

-- Cible par identifiant ESX ; refuse un membre du staff de rang égal ou supérieur (soi-même autorisé)
---@return string|nil identifier, number|nil source, string|nil name, table|nil error
local function memberTarget(src, actor, data)
    local identifier = type(data.identifier) == 'string' and data.identifier:gsub('^license:', '') or nil

    if not identifier or not identifier:match('^%x+$') or #identifier > 60 then
        return nil, nil, nil, Panel.fail('Joueur introuvable.')
    end

    local target = Staff.sourceOf('license:' .. identifier)

    if target ~= src then
        local staff = Staff.get('license:' .. identifier)
        local rank = staff and Ranks.get(staff.rankId)

        if rank and rank.level >= actor.level then
            return nil, nil, nil, Panel.fail('Ce membre du staff a un rang égal ou supérieur au vôtre.')
        end
    end

    if target then
        return identifier, target, Staff.displayName(target)
    end

    local row = MySQL.single.await('SELECT `firstname`, `lastname` FROM `users` WHERE `identifier` = ?', { identifier })

    if not row then
        return nil, nil, nil, Panel.fail('Joueur introuvable en base.')
    end

    return identifier, nil, ('%s %s (hors ligne)'):format(row.firstname or '?', row.lastname or '')
end

local function applyJob(identifier, target, jobName, grade)
    if target then
        local xPlayer = ESX.GetPlayerFromId(target)

        if not xPlayer then
            return false
        end

        xPlayer.setJob(jobName, grade)
    else
        MySQL.update.await('UPDATE `users` SET `job` = ?, `job_grade` = ? WHERE `identifier` = ?', { jobName, grade, identifier })
    end

    return true
end

Panel.actions['poles.setMember'] = function(src, actor, data)
    if not canManage(actor, data.job) then
        return denied()
    end

    local job = getJob(data.job)
    local grade = tonumber(data.grade)

    if not job or not grade or not ESX.DoesJobExist(job.name, grade) then
        return Panel.fail('Métier ou grade inconnu.')
    end

    local identifier, target, name, err = memberTarget(src, actor, data)

    if not identifier then
        return err
    end

    if not applyJob(identifier, target, job.name, grade) then
        return Panel.fail("Ce joueur n'a pas encore chargé son personnage.")
    end

    local gradeLabel = job.grades[tostring(grade)].label
    Logs.add(src, 'poles.member', name, { identifier = identifier, job = job.name, grade = grade, gradeLabel = gradeLabel })

    if target and target ~= src then
        Panel.notify(target, ('Votre poste a été changé par le staff : %s - %s.'):format(job.label, gradeLabel), 'info')
    end

    return { ok = true, silent = true }
end

Panel.actions['poles.fire'] = function(src, actor, data)
    if not canManage(actor, data.job) then
        return denied()
    end

    local job = getJob(data.job)

    if not job or job.name == UNEMPLOYED then
        return Panel.fail('Métier introuvable.')
    end

    local identifier, target, name, err = memberTarget(src, actor, data)

    if not identifier then
        return err
    end

    if not applyJob(identifier, target, UNEMPLOYED, 0) then
        return Panel.fail("Ce joueur n'a pas encore chargé son personnage.")
    end

    Logs.add(src, 'poles.fire', name, { identifier = identifier, job = job.name })

    if target and target ~= src then
        Panel.notify(target, ('Vous avez été renvoyé du poste %s par le staff.'):format(job.label), 'info')
    end

    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Pôles chargé.')
