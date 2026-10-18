-- lunatic_business : côté serveur des points d'interaction placés depuis le panel (lunatic_admin).
-- Tout ce qui vient du client est revérifié : métier, grade, distance au point.

local ox = exports.ox_inventory

---@type table<number, table> points par id (copie de GlobalState.lunaticStructurePoints)
local points = {}

local MODELS = { [`mp_m_freemode_01`] = 'm', [`mp_f_freemode_01`] = 'f' }

---------------------------------------------------------------------
-- Base de données
---------------------------------------------------------------------

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_business_accounts` (
            `job` VARCHAR(50) NOT NULL,
            `balance` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`job`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_business_account_log` (
            `id` BIGINT NOT NULL AUTO_INCREMENT,
            `job` VARCHAR(50) NOT NULL,
            `amount` BIGINT NOT NULL,
            `balance_after` BIGINT NOT NULL,
            `reason` VARCHAR(160) NOT NULL DEFAULT '',
            `actor` VARCHAR(100) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_lunatic_business_account_log_job` (`job`, `id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Tenues du vestiaire : une par grade et par modèle (homme / femme)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_business_outfits` (
            `job` VARCHAR(50) NOT NULL,
            `grade` INT NOT NULL,
            `model` CHAR(1) NOT NULL,
            `outfit` LONGTEXT NOT NULL,
            PRIMARY KEY (`job`, `grade`, `model`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

---------------------------------------------------------------------
-- Compte de société
---------------------------------------------------------------------

local Account = {}

function Account.balance(job)
    return tonumber(MySQL.scalar.await('SELECT `balance` FROM `lunatic_business_accounts` WHERE `job` = ?', { job })) or 0
end

local function log(job, amount, reason, actor)
    MySQL.insert.await('INSERT INTO `lunatic_business_account_log` (`job`, `amount`, `balance_after`, `reason`, `actor`, `created_at`) VALUES (?, ?, ?, ?, ?, ?)', {
        job, amount, Account.balance(job), tostring(reason or ''):sub(1, 160), tostring(actor or ''):sub(1, 100), os.time(),
    })
end

---@return boolean
function Account.add(job, amount, reason, actor)
    amount = math.floor(tonumber(amount) or 0)

    if type(job) ~= 'string' or amount <= 0 then
        return false
    end

    MySQL.query.await('INSERT INTO `lunatic_business_accounts` (`job`, `balance`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `balance` = `balance` + VALUES(`balance`)', { job, amount })
    log(job, amount, reason, actor)
    return true
end

-- Retrait atomique : refusé si le solde est insuffisant
---@return boolean
function Account.remove(job, amount, reason, actor)
    amount = math.floor(tonumber(amount) or 0)

    if type(job) ~= 'string' or amount <= 0 then
        return false
    end

    local changed = MySQL.update.await('UPDATE `lunatic_business_accounts` SET `balance` = `balance` - ? WHERE `job` = ? AND `balance` >= ?', { amount, job, amount })

    if (tonumber(changed) or 0) == 0 then
        return false
    end

    log(job, -amount, reason, actor)
    return true
end

function Account.history(job, limit)
    local rows = MySQL.query.await('SELECT `amount`, `balance_after`, `reason`, `actor`, `created_at` FROM `lunatic_business_account_log` WHERE `job` = ? ORDER BY `id` DESC LIMIT ?', {
        job, math.min(tonumber(limit) or Config.HistorySize, 100),
    }) or {}

    local list = {}

    for _, row in ipairs(rows) do
        list[#list + 1] = { amount = tonumber(row.amount), balance = tonumber(row.balance_after), reason = row.reason, actor = row.actor, created = tonumber(row.created_at) }
    end

    return list
end

exports('getBalance', Account.balance)
exports('addMoney', Account.add)
exports('removeMoney', Account.remove)
exports('getHistory', Account.history)

---------------------------------------------------------------------
-- Points et coffres
---------------------------------------------------------------------

local function jobLabel(job)
    local data = ESX.GetJobs()[job]
    return data and data.label or job
end

-- Coffres ox_inventory : réservés au métier de la structure (groups), Stockage = un par point, Casier = personnel
local function registerStashes()
    local lockers = {}

    for _, point in pairs(points) do
        if point.type == 'storage' then
            ox:RegisterStash(('lb_storage_%d'):format(point.id), ('%s · %s'):format(jobLabel(point.job), point.label),
                Config.StorageSlots, Config.StorageWeight, nil, { [point.job] = 0 }, vector3(point.x, point.y, point.z))
        elseif point.type == 'locker' then
            lockers[point.job] = true
        end
    end

    for job in pairs(lockers) do
        ox:RegisterStash(('lb_locker_%s'):format(job), ('Casier · %s'):format(jobLabel(job)), Config.LockerSlots, Config.LockerWeight, true, { [job] = 0 })
    end
end

local function setPoints(list)
    points = {}

    for _, point in ipairs(type(list) == 'table' and list or {}) do
        points[point.id] = point
    end

    registerStashes()
end

AddEventHandler('lunatic_admin:structurePointsChanged', setPoints)

CreateThread(function()
    -- Après un redémarrage de cette resource seule : la liste est déjà dans GlobalState
    while GetResourceState('ox_inventory') ~= 'started' do
        Wait(500)
    end

    setPoints(GlobalState.lunaticStructurePoints)
end)

---------------------------------------------------------------------
-- Contrôles communs
---------------------------------------------------------------------

local function distanceTo(src, point)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return math.huge
    end

    return #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z))
end

-- Point du bon type, joueur à côté ; membre de la structure (et patron si boss = true)
---@return table|nil xPlayer, table|nil point, string|nil error
local function check(src, pointId, typeId, options)
    options = options or {}
    local point = points[tonumber(pointId) or -1]

    if not point or point.type ~= typeId then
        return nil, nil, 'Point introuvable.'
    end

    if distanceTo(src, point) > Config.ActionDistance then
        return nil, nil, 'Vous êtes trop loin.'
    end

    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer then
        return nil, nil, 'Personnage non chargé.'
    end

    if options.member ~= false then
        local job = xPlayer.getJob()

        if job.name ~= point.job then
            return nil, nil, "Vous ne faites pas partie de cette structure."
        end

        if options.boss and job.grade_name ~= 'boss' then
            return nil, nil, 'Réservé au patron.'
        end
    end

    return xPlayer, point
end

local function fail(message)
    return { ok = false, error = message }
end

local function sortedGrades(job)
    local list = {}

    for _, grade in pairs((ESX.GetJobs()[job] or {}).grades or {}) do
        list[#list + 1] = { grade = tonumber(grade.grade), label = grade.label, name = grade.name }
    end

    table.sort(list, function(a, b) return a.grade < b.grade end)
    return list
end

local function notify(target, message, kind)
    TriggerClientEvent('esx:showNotification', target, message, kind or 'info')
end

---------------------------------------------------------------------
-- Gestion (patron)
---------------------------------------------------------------------

local function members(job)
    local online, list = {}, {}

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local current = xPlayer.getJob()

        if current and current.name == job then
            online[xPlayer.identifier] = xPlayer
        end
    end

    local playtime = {}

    for _, row in ipairs(MySQL.query.await('SELECT `identifier`, `minutes` FROM `lunatic_structure_playtime` WHERE `job` = ?', { job }) or {}) do
        playtime[row.identifier] = tonumber(row.minutes)
    end

    for _, row in ipairs(MySQL.query.await('SELECT `identifier`, `firstname`, `lastname`, `job_grade` FROM `users` WHERE `job` = ? LIMIT 300', { job }) or {}) do
        if not online[row.identifier] then
            list[#list + 1] = { identifier = row.identifier, name = ('%s %s'):format(row.firstname or '?', row.lastname or ''), grade = tonumber(row.job_grade), playtime = playtime[row.identifier] or 0 }
        end
    end

    for identifier, xPlayer in pairs(online) do
        list[#list + 1] = { identifier = identifier, name = xPlayer.getName(), grade = tonumber(xPlayer.getJob().grade), online = xPlayer.source, playtime = playtime[identifier] or 0 }
    end

    table.sort(list, function(a, b)
        if a.grade ~= b.grade then
            return a.grade > b.grade
        end

        return a.name < b.name
    end)

    return list
end

lib.callback.register('lunatic_business:management', function(src, pointId)
    local xPlayer, point, err = check(src, pointId, 'management', { boss = true })

    if not xPlayer then
        return fail(err)
    end

    return {
        ok = true,
        label = jobLabel(point.job),
        grades = sortedGrades(point.job),
        members = members(point.job),
        balance = Account.balance(point.job),
        me = xPlayer.identifier,
    }
end)

-- Membre de la structure (connecté ou non) : source si connecté
local function memberOf(job, identifier)
    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        if xPlayer.identifier == identifier then
            return xPlayer.getJob().name == job and xPlayer or nil, true
        end
    end

    local row = MySQL.single.await('SELECT `job`, `job_grade` FROM `users` WHERE `identifier` = ?', { identifier })
    return row and row.job == job and row or nil, false
end

local function applyJob(target, identifier, job, grade)
    if target and target.setJob then
        target.setJob(job, grade)
    else
        MySQL.update.await('UPDATE `users` SET `job` = ?, `job_grade` = ? WHERE `identifier` = ?', { job, grade, identifier })
    end
end

lib.callback.register('lunatic_business:setGrade', function(src, pointId, identifier, grade)
    local xPlayer, point, err = check(src, pointId, 'management', { boss = true })

    if not xPlayer then
        return fail(err)
    end

    if type(identifier) ~= 'string' or identifier == xPlayer.identifier then
        return fail('Vous ne pouvez pas changer votre propre grade.')
    end

    grade = tonumber(grade)
    local bossGrade = tonumber(xPlayer.getJob().grade)

    -- Le patron ne nomme pas un autre patron : grades strictement inférieurs au sien
    if not grade or grade >= bossGrade or not ESX.DoesJobExist(point.job, grade) then
        return fail('Grade invalide.')
    end

    local target = memberOf(point.job, identifier)

    if not target then
        return fail("Cette personne ne fait plus partie de la structure.")
    end

    if (tonumber(target.job_grade) or (target.getJob and tonumber(target.getJob().grade))) >= bossGrade then
        return fail('Vous ne pouvez pas modifier un autre patron.')
    end

    applyJob(target, identifier, point.job, grade)

    if target.source then
        notify(target.source, ('Votre grade a changé : %s.'):format(ESX.GetJobs()[point.job].grades[tostring(grade)].label), 'info')
    end

    return { ok = true }
end)

lib.callback.register('lunatic_business:fire', function(src, pointId, identifier)
    local xPlayer, point, err = check(src, pointId, 'management', { boss = true })

    if not xPlayer then
        return fail(err)
    end

    if type(identifier) ~= 'string' or identifier == xPlayer.identifier then
        return fail('Vous ne pouvez pas vous renvoyer vous-même.')
    end

    local target = memberOf(point.job, identifier)

    if not target then
        return fail("Cette personne ne fait plus partie de la structure.")
    end

    if (tonumber(target.job_grade) or (target.getJob and tonumber(target.getJob().grade))) >= tonumber(xPlayer.getJob().grade) then
        return fail('Vous ne pouvez pas renvoyer un autre patron.')
    end

    applyJob(target, identifier, 'unemployed', 0)

    if target.source then
        notify(target.source, ('Vous avez été renvoyé de %s.'):format(jobLabel(point.job)), 'error')
    end

    return { ok = true }
end)

lib.callback.register('lunatic_business:recruit', function(src, pointId, targetId)
    local xPlayer, point, err = check(src, pointId, 'management', { boss = true })

    if not xPlayer then
        return fail(err)
    end

    local target = ESX.GetPlayerFromId(tonumber(targetId) or -1)

    if not target or target.source == src then
        return fail('Joueur introuvable.')
    end

    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target.source))) > Config.RecruitDistance + 1.0 then
        return fail('Ce joueur est trop loin.')
    end

    if target.getJob().name == point.job then
        return fail('Ce joueur fait déjà partie de la structure.')
    end

    local grades = sortedGrades(point.job)
    target.setJob(point.job, grades[1] and grades[1].grade or 0)
    notify(target.source, ('Vous avez été recruté chez %s.'):format(jobLabel(point.job)), 'success')

    return { ok = true, name = target.getName() }
end)

-- Dépôt (liquide du patron -> compte) ou retrait (compte -> liquide du patron)
lib.callback.register('lunatic_business:account', function(src, pointId, operation, amount)
    local xPlayer, point, err = check(src, pointId, 'management', { boss = true })

    if not xPlayer then
        return fail(err)
    end

    amount = tonumber(amount)

    if not amount or amount ~= math.floor(amount) or amount <= 0 or amount > Config.AccountMaxAction then
        return fail('Montant invalide.')
    end

    local actor = xPlayer.getName()

    if operation == 'deposit' then
        if xPlayer.getMoney() < amount then
            return fail("Vous n'avez pas assez de liquide.")
        end

        xPlayer.removeMoney(amount, ('Dépôt sur le compte %s'):format(point.job))
        Account.add(point.job, amount, 'Dépôt', actor)
    elseif operation == 'withdraw' then
        if not Account.remove(point.job, amount, 'Retrait', actor) then
            return fail('Solde insuffisant.')
        end

        xPlayer.addMoney(amount, ('Retrait du compte %s'):format(point.job))
    else
        return fail('Opération inconnue.')
    end

    return { ok = true, balance = Account.balance(point.job) }
end)

lib.callback.register('lunatic_business:history', function(src, pointId)
    local xPlayer, point, err = check(src, pointId, 'management', { boss = true })

    if not xPlayer then
        return fail(err)
    end

    return { ok = true, history = Account.history(point.job, Config.HistorySize) }
end)

---------------------------------------------------------------------
-- Vestiaire
---------------------------------------------------------------------

lib.callback.register('lunatic_business:outfits', function(src, pointId)
    local xPlayer, point, err = check(src, pointId, 'wardrobe')

    if not xPlayer then
        return fail(err)
    end

    local model = MODELS[GetEntityModel(GetPlayerPed(src))]
    local job = xPlayer.getJob()
    local grades = sortedGrades(point.job)
    local labels = {}

    for _, grade in ipairs(grades) do
        labels[grade.grade] = grade.label
    end

    -- Un membre voit les tenues de son grade et des grades inférieurs
    local outfits = {}

    for _, row in ipairs(MySQL.query.await('SELECT `grade`, `model`, `outfit` FROM `lunatic_business_outfits` WHERE `job` = ? ORDER BY `grade`', { point.job }) or {}) do
        local grade = tonumber(row.grade)

        if row.model == model and (grade <= tonumber(job.grade) or job.grade_name == 'boss') then
            outfits[#outfits + 1] = { grade = grade, label = labels[grade] or ('Grade %d'):format(grade), outfit = json.decode(row.outfit) }
        end
    end

    return { ok = true, model = model, isBoss = job.grade_name == 'boss', grades = grades, outfits = outfits }
end)

lib.callback.register('lunatic_business:saveOutfit', function(src, pointId, grade, outfit)
    local xPlayer, point, err = check(src, pointId, 'wardrobe', { boss = true })

    if not xPlayer then
        return fail(err)
    end

    local model = MODELS[GetEntityModel(GetPlayerPed(src))]
    grade = tonumber(grade)

    if not model then
        return fail('Tenues réservées aux personnages homme ou femme du jeu (freemode).')
    end

    if not grade or not ESX.DoesJobExist(point.job, grade) then
        return fail('Grade invalide.')
    end

    if type(outfit) ~= 'table' or type(outfit.components) ~= 'table' or type(outfit.props) ~= 'table' then
        return fail('Tenue invalide.')
    end

    local encoded = json.encode({ components = outfit.components, props = outfit.props })

    if #encoded > 20000 then
        return fail('Tenue invalide.')
    end

    MySQL.query.await('INSERT INTO `lunatic_business_outfits` (`job`, `grade`, `model`, `outfit`) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE `outfit` = VALUES(`outfit`)', {
        point.job, grade, model, encoded,
    })

    return { ok = true }
end)

lib.callback.register('lunatic_business:deleteOutfit', function(src, pointId, grade)
    local xPlayer, point, err = check(src, pointId, 'wardrobe', { boss = true })

    if not xPlayer then
        return fail(err)
    end

    local model = MODELS[GetEntityModel(GetPlayerPed(src))]
    MySQL.update.await('DELETE FROM `lunatic_business_outfits` WHERE `job` = ? AND `grade` = ? AND `model` = ?', { point.job, tonumber(grade) or -1, model or '' })

    return { ok = true }
end)

---------------------------------------------------------------------
-- Sonnette et point Custom
---------------------------------------------------------------------

local lastRing = {}

AddEventHandler('playerDropped', function()
    lastRing[source] = nil
end)

RegisterNetEvent('lunatic_business:ring', function(pointId)
    local src = source
    local xPlayer, point = check(src, pointId, 'doorbell', { member = false })

    if not xPlayer then
        return
    end

    if lastRing[src] and os.time() - lastRing[src] < Config.DoorbellCooldown then
        return notify(src, 'Patientez un peu avant de sonner à nouveau.', 'error')
    end

    lastRing[src] = os.time()
    local reached = 0

    for _, member in pairs(ESX.GetExtendedPlayers()) do
        if member.getJob().name == point.job then
            reached = reached + 1
            TriggerClientEvent('lunatic_business:ringed', member.source, { label = point.label, job = jobLabel(point.job), x = point.x, y = point.y, name = xPlayer.getName() })
        end
    end

    notify(src, reached > 0 and 'Vous avez sonné. Quelqu\'un va venir.' or "Personne n'est disponible pour le moment.", reached > 0 and 'success' or 'info')
end)

-- Point Custom : n'importe quel script peut écouter AddEventHandler('lunatic_business:custom', function(src, point) ... end)
-- (événement réseau distinct de l'événement public, sinon TriggerEvent le redéclencherait)
RegisterNetEvent('lunatic_business:useCustom', function(pointId)
    local src = source
    local xPlayer, point = check(src, pointId, 'custom')

    if xPlayer then
        TriggerEvent('lunatic_business:custom', src, point)
    end
end)

print('[lunatic_business] Démarré.')
