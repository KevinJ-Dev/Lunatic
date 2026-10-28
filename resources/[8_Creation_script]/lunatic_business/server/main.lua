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

-- Journal du panel staff (tuile Logs) ; sans effet si lunatic_admin est arrêté
function GameLog(category, level, src, action, target, details)
    pcall(function() exports.lunatic_admin:log(category, level, src, action, target, details) end)
end

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

    GameLog('companies', 'info', src, 'company.grade', jobLabel(point.job), { identifier = identifier, grade = ESX.GetJobs()[point.job].grades[tostring(grade)].label })
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

    GameLog('companies', 'warn', src, 'company.fire', jobLabel(point.job), { identifier = identifier })
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
    GameLog('companies', 'success', src, 'company.recruit', jobLabel(point.job), { name = target.getName() })

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

    GameLog('companies', 'info', src, operation == 'deposit' and 'company.deposit' or 'company.withdraw', jobLabel(point.job), { amount = amount })
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

    notify(src, reached > 0 and "Vous avez sonné. Quelqu'un va venir." or "Personne n'est disponible pour le moment.", reached > 0 and 'success' or 'info')
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

---------------------------------------------------------------------
-- Catalogues des structures : équipement (membres, payé par la société), craft (membres)
-- Les catalogues viennent de lunatic_admin (GlobalState.lunaticCatalogs) : les prix ne viennent jamais du client.
---------------------------------------------------------------------

local function findLine(job, catalogId, lineId)
    local catalog = (GlobalState.lunaticCatalogs or {})[tostring(catalogId)]

    if not catalog or not catalog.jobs or not catalog.jobs[job] then
        return nil
    end

    for _, line in ipairs(catalog.lines or {}) do
        if line.id == tonumber(lineId) then
            return catalog, line
        end
    end
end

local function itemLabel(name)
    local item = ox:Items(name)
    return item and item.label or name
end

lib.callback.register('lunatic_business:buy', function(src, pointId, catalogId, lineId, quantity)
    local point = points[tonumber(pointId) or -1]

    if not point or (point.type ~= 'catalog' and point.type ~= 'armory') then
        return fail('Point introuvable.')
    end

    if distanceTo(src, point) > Config.ActionDistance then
        return fail('Vous êtes trop loin.')
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local catalog, line = findLine(point.job, catalogId, lineId)

    if not xPlayer or not line then
        return fail('Article introuvable.')
    end

    quantity = tonumber(quantity)

    if not quantity or quantity ~= math.floor(quantity) or quantity < 1 or quantity > Config.MaxPurchase then
        return fail(('Quantité invalide (1 à %d).'):format(Config.MaxPurchase))
    end

    local job = xPlayer.getJob()

    if catalog.kind ~= 'equipment' then
        return fail('Article introuvable.')
    end

    if job.name ~= point.job or tonumber(job.grade) < (line.minGrade or 0) then
        return fail("Votre grade ne permet pas de prendre cet équipement.")
    end

    local amount = line.count * quantity
    local total = line.price * quantity
    local label = itemLabel(line.item)

    if not ox:CanCarryItem(src, line.item, amount) then
        return fail("Vous n'avez pas assez de place.")
    end

    if total > 0 and not Account.remove(point.job, total, ('Équipement : %d × %s'):format(amount, label), xPlayer.getName()) then
        return fail('Le compte de la société est insuffisant.')
    end

    if not ox:AddItem(src, line.item, amount) then
        if total > 0 then
            Account.add(point.job, total, 'Remboursement équipement', xPlayer.getName())
        end

        return fail("L'objet n'a pas pu être ajouté à votre inventaire.")
    end

    return { ok = true, amount = amount, label = label, total = total }
end)

-- Craft en deux temps : début (vérifications, heure de départ), puis fin après la durée de la recette
local crafting = {}

AddEventHandler('playerDropped', function()
    crafting[source] = nil
end)

local function craftCheck(src, pointId, catalogId, lineId)
    local xPlayer, point, err = check(src, pointId, 'craft')

    if not xPlayer then
        return nil, err
    end

    local catalog, line = findLine(point.job, catalogId, lineId)

    if not line or catalog.kind ~= 'craft' then
        return nil, 'Recette introuvable.'
    end

    if tonumber(xPlayer.getJob().grade) < (line.minGrade or 0) then
        return nil, 'Votre grade ne permet pas cette recette.'
    end

    for _, ingredient in ipairs(line.ingredients or {}) do
        if (ox:GetItemCount(src, ingredient.item) or 0) < ingredient.count then
            return nil, ('Il vous manque : %d × %s.'):format(ingredient.count, itemLabel(ingredient.item))
        end
    end

    if not ox:CanCarryItem(src, line.item, line.count) then
        return nil, "Vous n'avez pas assez de place."
    end

    return line
end

lib.callback.register('lunatic_business:craftStart', function(src, pointId, catalogId, lineId)
    local line, err = craftCheck(src, pointId, catalogId, lineId)

    if not line then
        return fail(err)
    end

    crafting[src] = { pointId = pointId, catalogId = catalogId, lineId = lineId, at = GetGameTimer(), duration = line.duration }
    return { ok = true, duration = line.duration, label = itemLabel(line.item) }
end)

lib.callback.register('lunatic_business:craftFinish', function(src, pointId, catalogId, lineId)
    local pending = crafting[src]
    crafting[src] = nil

    if not pending or pending.pointId ~= pointId or pending.catalogId ~= catalogId or pending.lineId ~= lineId then
        return fail('Fabrication interrompue.')
    end

    -- Marge d'une seconde et demie pour la latence réseau
    if GetGameTimer() - pending.at < pending.duration * 1000 - 1500 then
        return fail('Fabrication trop rapide.')
    end

    local line, err = craftCheck(src, pointId, catalogId, lineId)

    if not line then
        return fail(err)
    end

    for _, ingredient in ipairs(line.ingredients or {}) do
        ox:RemoveItem(src, ingredient.item, ingredient.count)
    end

    ox:AddItem(src, line.item, line.count)
    return { ok = true, amount = line.count, label = itemLabel(line.item) }
end)

RegisterNetEvent('lunatic_business:craftCancel', function()
    crafting[source] = nil
end)

---------------------------------------------------------------------
-- Magasins automatiques (tuile Catalogues de lunatic_admin) : enregistrés dans ox_inventory,
-- qui gère l'interface, le paiement en liquide, les permis et la distance (10 m autour de l'emplacement)
---------------------------------------------------------------------

local registeredShops = {}

local function shopType(slug)
    return ('lunatic_%s'):format(slug)
end

local function registerShops(list)
    local seen = {}

    for _, shop in ipairs(type(list) == 'table' and list or {}) do
        if shop.kind == 'items' then
            local inventory, locations, groups = {}, {}, nil

            for _, entry in ipairs(shop.items or {}) do
                inventory[#inventory + 1] = { name = entry.item, price = entry.price, license = entry.license }
            end

            for _, location in ipairs(shop.locations or {}) do
                locations[#locations + 1] = vector3(location.x, location.y, location.z)
            end

            if shop.jobs and #shop.jobs > 0 then
                groups = {}

                for _, job in ipairs(shop.jobs) do
                    groups[job] = 0
                end
            end

            ox:RegisterShop(shopType(shop.slug), { name = shop.label, inventory = inventory, locations = locations, groups = groups })
            seen[shop.slug] = true
        end
    end

    -- Magasin supprimé ou renommé : enregistré vide, il ne s'ouvre plus
    for slug in pairs(registeredShops) do
        if not seen[slug] then
            ox:RegisterShop(shopType(slug), { name = slug, inventory = {}, locations = {} })
        end
    end

    registeredShops = seen
end

AddEventHandler('lunatic_admin:shopsChanged', registerShops)

---------------------------------------------------------------------
-- Location de véhicules (agences de la tuile Catalogues) : un véhicule à la fois par joueur
---------------------------------------------------------------------

---@type table<number, table> location en cours par joueur
local rentals = {}

---@return table|nil shop, table|nil location, table|nil xPlayer, string|nil error
local function shopAt(src, slug, index, kind)
    local shop

    for _, entry in ipairs(GlobalState.lunaticShops or {}) do
        if entry.slug == slug then
            shop = entry
        end
    end

    local location = shop and shop.locations and shop.locations[tonumber(index) or -1]

    if not location or shop.kind ~= kind then
        return nil, nil, nil, 'Magasin introuvable.'
    end

    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer then
        return nil, nil, nil, 'Personnage non chargé.'
    end

    if shop.jobs and #shop.jobs > 0 then
        local allowed = false

        for _, job in ipairs(shop.jobs) do
            if xPlayer.getJob().name == job then
                allowed = true
            end
        end

        if not allowed then
            return nil, nil, nil, 'Agence réservée.'
        end
    end

    if distanceTo(src, location) > Config.ActionDistance + 2.0 then
        return nil, nil, nil, 'Vous êtes trop loin.'
    end

    return shop, location, xPlayer
end

---------------------------------------------------------------------
-- Magasins d'articles (LTD, Ammunation…) : interface Lunatic au lieu de celle d'ox_inventory. Tout est revérifié ici :
-- articles et prix du panel, quantités, permis, place dans l'inventaire, solde.
---------------------------------------------------------------------

local licenseLabels = {}
local storeBusy = {}

local function licenseLabel(kind)
    if licenseLabels[kind] == nil then
        licenseLabels[kind] = MySQL.scalar.await('SELECT `label` FROM `licenses` WHERE `type` = ?', { kind }) or kind
    end

    return licenseLabels[kind]
end

local function licensesOf(identifier)
    local owned = {}

    for _, row in ipairs(MySQL.query.await('SELECT `type` FROM `user_licenses` WHERE `owner` = ?', { identifier }) or {}) do
        owned[row.type] = true
    end

    return owned
end

local function accounts(xPlayer)
    return xPlayer.getAccount('money').money, xPlayer.getAccount('bank').money
end

lib.callback.register('lunatic_business:storeOpen', function(src, slug, index)
    local shop, _, xPlayer, err = shopAt(src, slug, index, 'items')

    if not shop then
        return fail(err)
    end

    local owned = licensesOf(xPlayer.identifier)
    local items = {}

    for _, entry in ipairs(shop.items or {}) do
        local item = ox:Items(entry.item)

        if item then
            items[#items + 1] = {
                item = entry.item, label = item.label, price = entry.price, weight = item.weight or 0, description = item.description,
                license = entry.license and licenseLabel(entry.license) or nil, locked = entry.license ~= nil and not owned[entry.license],
            }
        end
    end

    local cash, bank = accounts(xPlayer)
    return { ok = true, label = shop.label, category = shop.category, header = shop.header, items = items, cash = cash, bank = bank, max = Config.MaxPurchase }
end)

-- cart = { [article] = quantité }, account = 'money' (liquide) ou 'bank' (carte)
lib.callback.register('lunatic_business:storeBuy', function(src, slug, index, cart, account)
    if storeBusy[src] then
        return fail('Patientez un instant.')
    end

    local shop, _, xPlayer, err = shopAt(src, slug, index, 'items')

    if not shop then
        return fail(err)
    end

    if type(cart) ~= 'table' then
        return fail('Panier invalide.')
    end

    local entries, lines, total, weight, owned = {}, {}, 0, 0, nil

    for _, entry in ipairs(shop.items or {}) do
        entries[entry.item] = entry
    end

    for name, amount in pairs(cart) do
        local entry = type(name) == 'string' and entries[name]
        local item = entry and ox:Items(name)
        amount = tonumber(amount)

        if not item or not amount or amount ~= math.floor(amount) or amount < 1 or amount > Config.MaxPurchase or #lines >= Config.MaxCartLines then
            return fail('Panier invalide.')
        end

        if entry.license then
            owned = owned or licensesOf(xPlayer.identifier)

            if not owned[entry.license] then
                return fail(('%s : permis requis (%s).'):format(item.label, licenseLabel(entry.license)))
            end
        end

        lines[#lines + 1] = { item = name, count = amount, label = item.label, price = entry.price * amount }
        total = total + entry.price * amount
        weight = weight + (item.weight or 0) * amount
    end

    if #lines == 0 then
        return fail('Panier vide.')
    end

    for _, line in ipairs(lines) do
        if not ox:CanCarryItem(src, line.item, line.count) then
            return fail(('Pas assez de place pour %s.'):format(line.label))
        end
    end

    if not ox:CanCarryWeight(src, weight) then
        return fail('Votre inventaire est trop lourd pour tout prendre.')
    end

    account = account == 'bank' and 'bank' or 'money'

    if xPlayer.getAccount(account).money < total then
        return fail(account == 'bank' and 'Solde bancaire insuffisant.' or "Vous n'avez pas assez de liquide.")
    end

    storeBusy[src] = true
    xPlayer.removeAccountMoney(account, total, ('Achat : %s'):format(shop.label))

    -- Article refusé par l'inventaire malgré les vérifications : remboursé
    local refund, labels = 0, {}

    for _, line in ipairs(lines) do
        if ox:AddItem(src, line.item, line.count) then
            labels[#labels + 1] = ('%s x%d'):format(line.label, line.count)
        else
            refund = refund + line.price
        end
    end

    if refund > 0 then
        xPlayer.addAccountMoney(account, refund, ('Remboursement : %s'):format(shop.label))
    end

    storeBusy[src] = nil
    GameLog('economy', 'info', src, 'shop.buy', shop.label, { total = total - refund, items = table.concat(labels, ', '), account = account })

    local cash, bank = accounts(xPlayer)
    return { ok = true, total = total - refund, refunded = refund > 0, cash = cash, bank = bank }
end)

AddEventHandler('playerDropped', function()
    storeBusy[source] = nil
end)

local function rentalInfo(rental)
    return rental and { label = rental.label, plate = rental.plate, remaining = math.max(0, rental.expiresAt - os.time()) } or nil
end

---------------------------------------------------------------------
-- Grossistes : les joueurs revendent leurs récoltes et produits (prix fixés dans le panel)
---------------------------------------------------------------------

lib.callback.register('lunatic_business:buybackOpen', function(src, slug, index)
    local shop, _, _, err = shopAt(src, slug, index, 'buyback')

    if not shop then
        return fail(err)
    end

    local offers = {}

    for _, entry in ipairs(shop.items or {}) do
        local count = ox:GetItemCount(src, entry.item) or 0
        local item = ox:Items(entry.item)

        offers[#offers + 1] = { item = entry.item, label = item and item.label or entry.item, price = entry.price, count = count }
    end

    return { ok = true, label = shop.label, offers = offers }
end)

lib.callback.register('lunatic_business:buybackSell', function(src, slug, index, itemName, quantity)
    local shop, _, xPlayer, err = shopAt(src, slug, index, 'buyback')

    if not shop then
        return fail(err)
    end

    local entry

    for _, candidate in ipairs(shop.items or {}) do
        if candidate.item == itemName then
            entry = candidate
        end
    end

    quantity = tonumber(quantity)

    if not entry or not quantity or quantity ~= math.floor(quantity) or quantity < 1 or quantity > Config.BuybackMax then
        return fail('Quantité invalide.')
    end

    if (ox:GetItemCount(src, entry.item) or 0) < quantity then
        return fail("Vous n'en avez pas autant.")
    end

    if not ox:RemoveItem(src, entry.item, quantity) then
        return fail('Revente impossible.')
    end

    local total = entry.price * quantity

    if total > 0 then
        xPlayer.addAccountMoney(Config.BuybackAccount, total, ('Revente : %s (%s)'):format(entry.item, shop.label))
    end

    local item = ox:Items(entry.item)
    return { ok = true, quantity = quantity, total = total, label = item and item.label or entry.item }
end)

-- Vitrine d'aperçu commune à la location et à la vente : celle du panel, sinon celle de la config
local function showroomSpot()
    return GlobalState.lunaticRentalShowroom or {
        x = Config.RentalShowroom.x, y = Config.RentalShowroom.y, z = Config.RentalShowroom.z, h = Config.RentalShowroom.w,
    }
end

lib.callback.register('lunatic_business:rentalOpen', function(src, slug, index)
    local shop, location, xPlayer, err = shopAt(src, slug, index, 'rental')

    if not shop then
        return fail(err)
    end

    return {
        ok = true, label = shop.label, header = shop.header, vehicles = shop.vehicles or {}, active = rentalInfo(rentals[src]),
        cash = xPlayer.getAccount('money').money, bank = xPlayer.getAccount('bank').money,
        maxPeriods = shop.maxPeriods or 4, showroom = location.showroom or showroomSpot(),
    }
end)

-- Vendeurs en service : joueurs connectés avec le job lié au magasin (sans compter except)
local function sellersOnline(job, except)
    if not job or job == '' then
        return {}
    end

    local list = {}

    for _, xSeller in pairs(ESX.GetExtendedPlayers('job', job)) do
        if xSeller.source ~= except then
            list[#list + 1] = xSeller
        end
    end

    return list
end

-- Clients possibles d'un vendeur : joueurs proches (lui compris, pour s'acheter un véhicule)
local function nearbyClients(src)
    local origin = GetEntityCoords(GetPlayerPed(src))
    local list = {}

    for _, xTarget in pairs(ESX.GetExtendedPlayers()) do
        local ped = GetPlayerPed(xTarget.source)

        if ped ~= 0 and #(GetEntityCoords(ped) - origin) <= Config.SaleClientDistance then
            list[#list + 1] = { id = xTarget.source, name = xTarget.source == src and 'Moi-même' or xTarget.getName() }
        end
    end

    table.sort(list, function(a, b) return a.id == src or (b.id ~= src and a.name < b.name) end)
    return list
end

-- Vente de véhicules (concessionnaire, Vespucci Bike) : vitrine sur place de l'emplacement, sinon la commune ; sans durée.
-- mode = 'seller' (employé : propose la vente), 'request' (un vendeur est en service : le client le demande) ou 'free'
lib.callback.register('lunatic_business:saleOpen', function(src, slug, index)
    local shop, location, xPlayer, err = shopAt(src, slug, index, 'vehicles')

    if not shop then
        return fail(err)
    end

    local seller = shop.accountJob ~= '' and xPlayer.getJob().name == shop.accountJob
    local mode = seller and 'seller' or #sellersOnline(shop.accountJob, src) > 0 and 'request' or 'free'

    return {
        ok = true, sale = true, label = shop.label, header = shop.header, vehicles = shop.vehicles or {}, mode = mode,
        clients = seller and nearbyClients(src) or nil,
        cash = xPlayer.getAccount('money').money, bank = xPlayer.getAccount('bank').money, showroom = location.showroom or showroomSpot(),
    }
end)

-- Sortie des véhicules : celle définie dans le panel, sinon 4 m devant le comptoir
local function spawnOf(location)
    if location.spawn then
        return location.spawn
    end

    local heading = math.rad(location.h or 0.0)
    return { x = location.x - math.sin(heading) * 4.0, y = location.y + math.cos(heading) * 4.0, z = location.z + 0.5, h = location.h or 0.0 }
end

lib.callback.register('lunatic_business:rent', function(src, slug, index, vehicleId, account, periods)
    local shop, location, xPlayer, err = shopAt(src, slug, index, 'rental')

    if not shop then
        return fail(err)
    end

    if rentals[src] then
        return fail("Vous avez déjà une location en cours : rendez-la d'abord.")
    end

    local offer

    for _, vehicle in ipairs(shop.vehicles or {}) do
        if vehicle.id == tonumber(vehicleId) then
            offer = vehicle
        end
    end

    if not offer then
        return fail('Véhicule introuvable.')
    end

    periods = math.tointeger(tonumber(periods) or 1)

    if not periods or periods < 1 or periods > (shop.maxPeriods or 4) then
        return fail(('Durée invalide : de 1 à %d périodes.'):format(shop.maxPeriods or 4))
    end

    local price, duration = offer.price * periods, offer.duration * periods

    local spawn = spawnOf(location)
    local spawnCoords = vector3(spawn.x, spawn.y, spawn.z)

    for _, vehicle in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(vehicle) - spawnCoords) < 3.0 then
            return fail('La sortie est encombrée : dégagez-la puis réessayez.')
        end
    end

    account = account == 'bank' and 'bank' or 'money'

    if price > 0 then
        local balance = xPlayer.getAccount(account)

        if not balance or balance.money < price then
            return fail(account == 'bank' and 'Solde bancaire insuffisant.' or "Vous n'avez pas assez de liquide.")
        end

        xPlayer.removeAccountMoney(account, price, ('Location : %s (%s, %d min)'):format(offer.label, shop.label, duration))
    end

    local vehicle = CreateVehicleServerSetter(joaat(offer.model), offer.type or 'automobile', spawn.x, spawn.y, spawn.z, spawn.h or 0.0)
    local timeout = GetGameTimer() + 3000

    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        if price > 0 then
            xPlayer.addAccountMoney(account, price, 'Remboursement location')
        end

        return fail("Le véhicule n'a pas pu sortir. Vous avez été remboursé.")
    end

    local plate = ('LOC%05d'):format(math.random(0, 99999))
    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(vehicle, plate)
    TaskWarpPedIntoVehicle(GetPlayerPed(src), vehicle, -1)

    rentals[src] = { vehicle = vehicle, plate = plate, label = offer.label, location = location, expiresAt = os.time() + duration * 60, warned = {} }
    TriggerClientEvent('lunatic_business:rentalTimer', src, { label = offer.label, remaining = duration * 60 })
    GameLog('vehicles', 'info', src, 'vehicle.rent', offer.label, { plate = plate, price = price, duration = duration, periods = periods })
    return { ok = true, label = offer.label, plate = plate, duration = duration, price = price, account = account }
end)

-- Vente : plaque libre de 8 caractères (3 lettres, un espace, 4 chiffres), comme les véhicules donnés par le staff
local PLATE_LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
local GARAGE_TYPES = { boat = 'boat', submarine = 'boat', heli = 'aircraft', plane = 'aircraft' }
local saleBusy = {}

local function newPlate()
    for _ = 1, 20 do
        local letters = ''

        for _ = 1, 3 do
            local i = math.random(1, #PLATE_LETTERS)
            letters = letters .. PLATE_LETTERS:sub(i, i)
        end

        local plate = ('%s %04d'):format(letters, math.random(0, 9999))

        if (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `owned_vehicles` WHERE `plate` = ?', { plate })) or 0) == 0 then
            return plate
        end
    end
end

-- Couleur GTA choisie (0-160), nil = celle d'origine du modèle
local function colorOf(value)
    value = tonumber(value)
    return value and value == math.floor(value) and value >= 0 and value <= 160 and value or nil
end

local function offerOf(shop, vehicleId)
    for _, vehicle in ipairs(shop.vehicles or {}) do
        if vehicle.id == tonumber(vehicleId) then
            return vehicle
        end
    end
end

-- Livraison d'un véhicule payé : sortie libre, paiement, garage du joueur (owned_vehicles, sorti), véhicule posé à la
-- sortie du magasin avec le joueur au volant ; share = part du prix (%) pour le compte de la société liée
local function deliverVehicle(src, xPlayer, shop, location, offer, account, primary, secondary, share)
    local spawn = spawnOf(location)
    local spawnCoords = vector3(spawn.x, spawn.y, spawn.z)

    for _, vehicle in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(vehicle) - spawnCoords) < 3.0 then
            return fail('La sortie est encombrée : dégagez-la puis réessayez.')
        end
    end

    account = account == 'bank' and 'bank' or 'money'
    local price = offer.price

    if price > 0 and xPlayer.getAccount(account).money < price then
        return fail(account == 'bank' and 'Solde bancaire insuffisant.' or "Vous n'avez pas assez de liquide.")
    end

    local plate = newPlate()

    if not plate then
        return fail('Aucune plaque libre, réessayez.')
    end

    saleBusy[src] = true

    if price > 0 then
        xPlayer.removeAccountMoney(account, price, ('Achat : %s (%s)'):format(offer.label, shop.label))
    end

    local vehicle = CreateVehicleServerSetter(joaat(offer.model), offer.type or 'automobile', spawn.x, spawn.y, spawn.z, spawn.h or 0.0)
    local timeout = GetGameTimer() + 3000

    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        if price > 0 then
            xPlayer.addAccountMoney(account, price, 'Remboursement achat de véhicule')
        end

        saleBusy[src] = nil
        return fail("Le véhicule n'a pas pu sortir. Vous avez été remboursé.")
    end

    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(vehicle, plate)

    -- Couleurs choisies : posées par le jeu du client (au volant) et gardées avec le véhicule
    local props = { model = joaat(offer.model), plate = plate, fuelLevel = 100.0 }
    primary, secondary = colorOf(primary), colorOf(secondary)
    props.color1, props.color2 = primary, secondary

    MySQL.insert.await('INSERT INTO `owned_vehicles` (`owner`, `plate`, `vehicle`, `type`, `stored`) VALUES (?, ?, ?, ?, 0)', {
        xPlayer.identifier, plate, json.encode(props), GARAGE_TYPES[offer.type] or 'car',
    })
    TaskWarpPedIntoVehicle(GetPlayerPed(src), vehicle, -1)
    saleBusy[src] = nil

    local amount = 0

    if price > 0 and shop.accountJob and shop.accountJob ~= '' then
        amount = math.floor(price * math.max(0, math.min(100, share or 0)) / 100)

        if amount > 0 then
            Account.add(shop.accountJob, amount, ('Vente %s (%s)'):format(offer.label, plate), xPlayer.getName())
        end
    end

    GameLog('vehicles', 'success', src, 'vehicle.buy', offer.label, { plate = plate, price = price, shop = shop.label, account = account, company = amount })
    return { ok = true, label = offer.label, plate = plate, price = price, account = account, netId = NetworkGetNetworkIdFromEntity(vehicle), primary = primary, secondary = secondary }
end

-- Achat libre (aucun vendeur en service) : la part réglée dans le panel va au compte de la société, le reste disparaît
lib.callback.register('lunatic_business:saleBuy', function(src, slug, index, vehicleId, account, primary, secondary)
    if saleBusy[src] then
        return fail('Patientez un instant.')
    end

    local shop, location, xPlayer, err = shopAt(src, slug, index, 'vehicles')

    if not shop then
        return fail(err)
    end

    if #sellersOnline(shop.accountJob, src) > 0 then
        return fail('Un vendeur est en service : demandez-le pour acheter.')
    end

    local offer = offerOf(shop, vehicleId)

    if not offer then
        return fail('Véhicule introuvable.')
    end

    return deliverVehicle(src, xPlayer, shop, location, offer, account, primary, secondary, shop.companyShare or 0)
end)

---------------------------------------------------------------------
-- Vente par un vendeur : le client le demande, le vendeur propose (véhicule, couleurs, client proche), le client
-- accepte et paie ; tout le prix va au compte de la société
---------------------------------------------------------------------

local offers = {}   -- client -> { seller, slug, index, vehicleId, primary, secondary, expires }
local requests = {} -- client -> dernière demande (os.time)

lib.callback.register('lunatic_business:saleRequest', function(src, slug, index)
    local shop, _, xPlayer, err = shopAt(src, slug, index, 'vehicles')

    if not shop then
        return fail(err)
    end

    if (requests[src] or 0) > os.time() - Config.SaleRequestCooldown then
        return fail('Vous avez déjà demandé un vendeur : patientez un peu.')
    end

    local sellers = sellersOnline(shop.accountJob, src)

    if #sellers == 0 then
        return fail("Aucun vendeur en service : vous pouvez acheter directement.")
    end

    requests[src] = os.time()

    for _, xSeller in ipairs(sellers) do
        notify(xSeller.source, ('%s demande un vendeur à %s.'):format(xPlayer.getName(), shop.label), 'info')
    end

    return { ok = true, count = #sellers }
end)

lib.callback.register('lunatic_business:saleOffer', function(src, slug, index, vehicleId, client, primary, secondary)
    local shop, _, xSeller, err = shopAt(src, slug, index, 'vehicles')

    if not shop then
        return fail(err)
    end

    if shop.accountJob == '' or xSeller.getJob().name ~= shop.accountJob then
        return fail('Réservé aux vendeurs de la concession.')
    end

    local offer = offerOf(shop, vehicleId)
    client = tonumber(client)
    local xClient = client and ESX.GetPlayerFromId(client)

    if not offer then
        return fail('Véhicule introuvable.')
    end

    if not xClient or #(GetEntityCoords(GetPlayerPed(client)) - GetEntityCoords(GetPlayerPed(src))) > Config.SaleClientDistance then
        return fail('Le client doit être à côté de vous.')
    end

    if offers[client] and offers[client].expires > os.time() then
        return fail('Ce client a déjà une offre en attente.')
    end

    offers[client] = {
        seller = src, slug = slug, index = index, vehicleId = offer.id, primary = colorOf(primary), secondary = colorOf(secondary),
        expires = os.time() + Config.SaleOfferTime,
    }

    TriggerClientEvent('lunatic_business:saleOffer', client, {
        label = offer.label, price = offer.price, seller = client == src and 'vous-même' or xSeller.getName(), shop = shop.label, seconds = Config.SaleOfferTime,
    })

    return { ok = true, client = client == src and 'vous-même' or xClient.getName(), label = offer.label }
end)

-- Réponse du client : account = 'money' / 'bank', ou nil pour refuser
lib.callback.register('lunatic_business:saleAnswer', function(src, account)
    local pending = offers[src]
    offers[src] = nil

    if not pending or pending.expires < os.time() then
        return fail("L'offre a expiré.")
    end

    if not account then
        notify(pending.seller, 'Le client a refusé votre offre.', 'error')
        return { ok = true, refused = true }
    end

    if saleBusy[src] then
        return fail('Patientez un instant.')
    end

    -- Le vendeur doit toujours être au comptoir, toujours vendeur, et le client à côté de lui
    local shop, location, xSeller = shopAt(pending.seller, pending.slug, pending.index, 'vehicles')
    local xPlayer = ESX.GetPlayerFromId(src)

    if not shop or not xPlayer or xSeller.getJob().name ~= shop.accountJob then
        return fail("Le vendeur n'est plus au comptoir.")
    end

    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(pending.seller))) > Config.SaleClientDistance then
        return fail('Restez à côté du vendeur pour payer.')
    end

    local offer = offerOf(shop, pending.vehicleId)

    if not offer then
        return fail("Ce véhicule n'est plus en vente.")
    end

    local result = deliverVehicle(src, xPlayer, shop, location, offer, account, pending.primary, pending.secondary, 100)

    notify(pending.seller, result.ok and ('Vente conclue : %s (%s) pour %s.'):format(offer.label, result.plate, xPlayer.getName())
        or ('Vente non conclue : %s'):format(result.error), result.ok and 'success' or 'error')
    return result
end)

AddEventHandler('playerDropped', function()
    offers[source] = nil
    requests[source] = nil
end)

---------------------------------------------------------------------
-- Essai routier : le client conduit le véhicule seul, dans une instance à part, pendant Config.TestDriveTime.
-- Fin à l'heure, trop loin, en descendant du véhicule ou à la déconnexion ; il est ramené au comptoir.
---------------------------------------------------------------------

local tests = {} -- joueur -> { vehicle, previous, back, origin, endsAt, label }

local function endTest(src, message)
    local test = tests[src]

    if not test then
        return
    end

    tests[src] = nil

    if DoesEntityExist(test.vehicle) then
        DeleteEntity(test.vehicle)
    end

    if GetPlayerPed(src) ~= 0 then
        SetPlayerRoutingBucket(src, test.previous)
    end

    TriggerClientEvent('lunatic_business:testEnded', src, test.back, message)
end

lib.callback.register('lunatic_business:testDrive', function(src, slug, index, vehicleId)
    if tests[src] then
        return fail('Un essai est déjà en cours.')
    end

    if rentals[src] then
        return fail("Rendez d'abord votre location.")
    end

    local shop, location, _, err = shopAt(src, slug, index, 'vehicles')

    if not shop then
        return fail(err)
    end

    local offer

    for _, vehicle in ipairs(shop.vehicles or {}) do
        if vehicle.id == tonumber(vehicleId) then
            offer = vehicle
        end
    end

    if not offer then
        return fail('Véhicule introuvable.')
    end

    local spawn = spawnOf(location)
    local bucket = Config.TestDriveBucket + src
    local previous = GetPlayerRoutingBucket(src)
    SetRoutingBucketPopulationEnabled(bucket, false)
    SetPlayerRoutingBucket(src, bucket)

    local vehicle = CreateVehicleServerSetter(joaat(offer.model), offer.type or 'automobile', spawn.x, spawn.y, spawn.z, spawn.h or 0.0)
    local timeout = GetGameTimer() + 3000

    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        SetPlayerRoutingBucket(src, previous)
        return fail("Le véhicule d'essai n'a pas pu sortir.")
    end

    SetEntityRoutingBucket(vehicle, bucket)
    SetVehicleNumberPlateText(vehicle, 'ESSAI')
    TaskWarpPedIntoVehicle(GetPlayerPed(src), vehicle, -1)

    tests[src] = {
        vehicle = vehicle, previous = previous, origin = vector3(spawn.x, spawn.y, spawn.z), endsAt = os.time() + Config.TestDriveTime, label = offer.label,
        radius = Config.TestDriveRadiusByType[offer.type] or Config.TestDriveRadius,
        back = { x = location.x, y = location.y, z = location.z, h = location.h or 0.0 },
    }

    GameLog('vehicles', 'info', src, 'vehicle.test_drive', offer.label, { shop = shop.label })
    return { ok = true, label = offer.label, seconds = Config.TestDriveTime, netId = NetworkGetNetworkIdFromEntity(vehicle) }
end)

RegisterNetEvent('lunatic_business:testEnd', function()
    endTest(source, "Essai terminé : le véhicule est rendu.")
end)

CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()

        for src, test in pairs(tests) do
            local ped = GetPlayerPed(src)

            if now >= test.endsAt then
                endTest(src, "Fin de l'essai : le véhicule est rendu.")
            elseif ped ~= 0 and #(GetEntityCoords(ped) - test.origin) > test.radius then
                endTest(src, 'Trop loin de la concession : essai terminé.')
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local test = tests[source]

    if test then
        tests[source] = nil

        if DoesEntityExist(test.vehicle) then
            DeleteEntity(test.vehicle)
        end
    end
end)

AddEventHandler('playerDropped', function()
    saleBusy[source] = nil
end)

lib.callback.register('lunatic_business:rentReturn', function(src, slug, index)
    local shop, location, _, err = shopAt(src, slug, index, 'rental')

    if not shop then
        return fail(err)
    end

    local rental = rentals[src]

    if not rental then
        return fail("Vous n'avez pas de location en cours.")
    end

    if DoesEntityExist(rental.vehicle) then
        if #(GetEntityCoords(rental.vehicle) - vector3(location.x, location.y, location.z)) > Config.RentalReturnDistance then
            return fail('Ramenez le véhicule près du comptoir pour le rendre.')
        end

        DeleteEntity(rental.vehicle)
    end

    rentals[src] = nil
    TriggerClientEvent('lunatic_business:rentalTimer', src, nil)
    GameLog('vehicles', 'info', src, 'vehicle.rent_return', rental.label, { plate = rental.plate })
    return { ok = true, label = rental.label }
end)

local function hasOccupant(vehicle)
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(vehicle, seat)

        if ped and ped ~= 0 then
            return true
        end
    end

    return false
end

-- Fin des locations : avertissements, puis véhicule repris dès qu'il est vide (ou de force après Config.RentalGrace)
CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()

        for src, rental in pairs(rentals) do
            local remaining = rental.expiresAt - now

            if not DoesEntityExist(rental.vehicle) then
                rentals[src] = nil
                TriggerClientEvent('lunatic_business:rentalTimer', src, nil)
                notify(src, ('Votre location (%s) est terminée : le véhicule a disparu.'):format(rental.label), 'info')
            elseif remaining > 0 then
                for _, mark in ipairs(Config.RentalWarnings) do
                    if remaining <= mark and not rental.warned[mark] then
                        rental.warned[mark] = true
                        notify(src, ('Location %s : il reste %d minute%s.'):format(rental.label, math.ceil(remaining / 60), remaining > 60 and 's' or ''), 'info')
                    end
                end
            elseif not hasOccupant(rental.vehicle) or remaining <= -Config.RentalGrace then
                DeleteEntity(rental.vehicle)
                rentals[src] = nil
                TriggerClientEvent('lunatic_business:rentalTimer', src, nil)
                notify(src, ("Location terminée : %s a été repris par l'agence."):format(rental.label), 'info')
            elseif not rental.warned.ended then
                rental.warned.ended = true
                notify(src, ('Location terminée : rendez %s, il sera repris dans %d minutes.'):format(rental.label, math.ceil(Config.RentalGrace / 60)), 'error')
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local rental = rentals[source]

    if rental and DoesEntityExist(rental.vehicle) then
        DeleteEntity(rental.vehicle)
    end

    rentals[source] = nil
end)

CreateThread(function()
    while GetResourceState('ox_inventory') ~= 'started' do
        Wait(500)
    end

    registerShops(GlobalState.lunaticShops)
end)

---------------------------------------------------------------------
-- Garages : véhicules de service de la structure (parc réglé dans le panel)
---------------------------------------------------------------------

local serviceVehicles = {} -- joueur -> { vehicle, label, job }

local function fleetFor(xPlayer, point)
    local found, list = pcall(function() return exports.lunatic_admin:getStructureVehicles(point.job) end)
    local category = point.data and point.data.vehicle or 'car'
    local grade = tonumber(xPlayer.getJob().grade) or 0
    local allowed = {}

    for _, vehicle in ipairs(found and list or {}) do
        if vehicle.category == category and vehicle.minGrade <= grade then
            allowed[#allowed + 1] = vehicle
        end
    end

    return allowed
end

local function serviceVehicleOf(src)
    local entry = serviceVehicles[src]

    if entry and not DoesEntityExist(entry.vehicle) then
        serviceVehicles[src] = nil
        return nil
    end

    return entry
end

lib.callback.register('lunatic_business:garage', function(src, pointId)
    local xPlayer, point, err = check(src, pointId, 'garage')

    if not xPlayer then
        return fail(err)
    end

    local out = serviceVehicleOf(src)
    return { ok = true, label = jobLabel(point.job), vehicles = fleetFor(xPlayer, point), out = out and out.label or nil }
end)

lib.callback.register('lunatic_business:garageTake', function(src, pointId, vehicleId)
    local xPlayer, point, err = check(src, pointId, 'garage')

    if not xPlayer then
        return fail(err)
    end

    if serviceVehicleOf(src) then
        return fail("Vous avez déjà un véhicule de service : rangez-le d'abord.")
    end

    local offer

    for _, vehicle in ipairs(fleetFor(xPlayer, point)) do
        if vehicle.id == tonumber(vehicleId) then
            offer = vehicle
        end
    end

    if not offer then
        return fail('Véhicule indisponible pour votre grade.')
    end

    local spawn = spawnOf(point)
    local spawnCoords = vector3(spawn.x, spawn.y, spawn.z)

    for _, vehicle in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(vehicle) - spawnCoords) < 3.0 then
            return fail('La sortie est encombrée : dégagez-la puis réessayez.')
        end
    end

    local vehicle = CreateVehicleServerSetter(joaat(offer.model), offer.vtype or 'automobile', spawn.x, spawn.y, spawn.z, spawn.h or 0.0)
    local timeout = GetGameTimer() + 3000

    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return fail(("Le véhicule n'a pas pu sortir (modèle %s introuvable ?)."):format(offer.model))
    end

    -- Plaque de la structure : 4 premières lettres du métier et un numéro
    local prefix = point.job:upper():gsub('[^%w]', ''):sub(1, 4)
    local plate = ('%s%04d'):format(prefix, math.random(0, 9999))
    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(src))
    SetVehicleNumberPlateText(vehicle, plate)
    TaskWarpPedIntoVehicle(GetPlayerPed(src), vehicle, -1)

    serviceVehicles[src] = { vehicle = vehicle, label = offer.label, job = point.job }
    GameLog('vehicles', 'info', src, 'vehicle.service_out', offer.label, { plate = plate, job = point.job })
    return { ok = true, label = offer.label, plate = plate }
end)

lib.callback.register('lunatic_business:garageStore', function(src, pointId)
    local point = points[tonumber(pointId) or -1]
    local entry = serviceVehicleOf(src)

    if not point or point.type ~= 'garage' then
        return fail('Garage introuvable.')
    end

    if not entry then
        return fail("Vous n'avez pas de véhicule de service sorti.")
    end

    if #(GetEntityCoords(entry.vehicle) - vector3(point.x, point.y, point.z)) > Config.GarageReturnDistance then
        return fail('Ramenez le véhicule près du garage pour le ranger.')
    end

    DeleteEntity(entry.vehicle)
    serviceVehicles[src] = nil
    GameLog('vehicles', 'info', src, 'vehicle.service_in', entry.label, { job = entry.job })
    return { ok = true, label = entry.label }
end)

-- Déconnexion : le véhicule de service est repris
AddEventHandler('playerDropped', function()
    local entry = serviceVehicles[source]
    serviceVehicles[source] = nil

    if entry and DoesEntityExist(entry.vehicle) then
        DeleteEntity(entry.vehicle)
    end
end)

print('[lunatic_business] Démarré.')
