-- Lot 5 : argent, métier et inventaire des joueurs connectés.
-- Toutes les opérations passent par ESX et ox_inventory côté serveur, avec l'ancienne et la nouvelle valeur dans les logs.

local ACCOUNTS = {
    money = { label = 'liquide', permission = 'economy.money' },
    bank = { label = 'banque', permission = 'economy.money' },
    black_money = { label = 'argent sale', permission = 'economy.black_money' },
}

local ox = exports.ox_inventory

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

-- Cible connectée, non protégée (le staff de rang égal ou supérieur l'est ; soi-même est autorisé)
---@return number|nil target, table|nil xPlayer, table|nil error
local function targetOf(src, actor, data)
    local target = tonumber(data.serverId)

    if not target or not GetPlayerName(target) then
        return nil, nil, Panel.fail("Ce joueur n'est plus connecté.")
    end

    if target ~= src then
        local rank = Staff.rankOf(target)

        if rank and rank.level >= actor.level then
            return nil, nil, Panel.fail('Ce membre du staff a un rang égal ou supérieur au vôtre.')
        end
    end

    local xPlayer = ESX.GetPlayerFromId(target)

    if not xPlayer then
        return nil, nil, Panel.fail("Ce joueur n'a pas encore chargé son personnage.")
    end

    return target, xPlayer
end

local function cleanReason(value)
    if type(value) ~= 'string' then
        return nil
    end

    local reason = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(reason)

    if not length or length < Config.EconomyReasonMin or length > Config.SanctionReasonMax then
        return nil
    end

    return reason
end

local function reasonError()
    return Panel.fail(('La raison doit faire entre %d et %d caractères.'):format(Config.EconomyReasonMin, Config.SanctionReasonMax))
end

local function wholeNumber(value, min, max)
    local number = tonumber(value)

    if not number or number ~= math.floor(number) or number < min or (max and number > max) then
        return nil
    end

    return math.floor(number)
end

local function formatMoney(amount)
    local text = tostring(math.floor(amount)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', '')
    return text .. ' $'
end

---------------------------------------------------------------------
-- Argent
---------------------------------------------------------------------

Panel.actions['economy.money'] = function(src, actor, data)
    local account = type(data.account) == 'string' and ACCOUNTS[data.account]

    if not account then
        return Panel.fail('Compte inconnu.')
    end

    if not Ranks.hasPermission(actor, account.permission) then
        return denied()
    end

    local target, xPlayer, err = targetOf(src, actor, data)

    if not target then
        return err
    end

    local operation = data.operation

    if operation ~= 'add' and operation ~= 'remove' and operation ~= 'set' then
        return Panel.fail('Opération inconnue.')
    end

    -- Garde-fou contre les fautes de frappe (le Fondateur n'a pas de limite)
    local max = not actor.owner and Config.MaxMoneyAction or nil
    local amount = wholeNumber(data.amount, operation == 'set' and 0 or 1, max)

    if not amount then
        return Panel.fail(max and ('Montant invalide (maximum %s par opération).'):format(formatMoney(max)) or 'Montant invalide.')
    end

    local reason = cleanReason(data.reason)

    if not reason then
        return reasonError()
    end

    local current = xPlayer.getAccount(data.account)

    if not current then
        return Panel.fail("Ce compte n'existe pas pour ce joueur.")
    end

    local before = current.money
    local logReason = ('Panel staff : %s'):format(reason)

    if operation == 'add' then
        xPlayer.addAccountMoney(data.account, amount, logReason)
    elseif operation == 'remove' then
        if amount > before then
            return Panel.fail(('Le joueur n\'a que %s en %s.'):format(formatMoney(before), account.label))
        end

        xPlayer.removeAccountMoney(data.account, amount, logReason)
    else
        xPlayer.setAccountMoney(data.account, amount, logReason)
    end

    local after = xPlayer.getAccount(data.account).money

    Logs.add(src, 'economy.money', Staff.displayName(target), {
        serverId = target, account = data.account, operation = operation, amount = amount, before = before, after = after, reason = reason,
    })

    if target ~= src then
        Panel.notify(target, ('Votre compte %s a été modifié par le staff : %s.'):format(account.label, formatMoney(after)), 'info')
    end

    return { ok = true, silent = true, before = before, after = after }
end

---------------------------------------------------------------------
-- Métier
---------------------------------------------------------------------

-- Liste des métiers et grades (pour les menus déroulants)
Panel.actions['economy.jobs'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'economy.job') then
        return denied()
    end

    local jobs = {}

    for name, job in pairs(ESX.GetJobs()) do
        local grades = {}

        for _, grade in pairs(job.grades or {}) do
            grades[#grades + 1] = { grade = tonumber(grade.grade), label = grade.label }
        end

        table.sort(grades, function(a, b) return a.grade < b.grade end)
        jobs[#jobs + 1] = { name = name, label = job.label, grades = grades }
    end

    table.sort(jobs, function(a, b) return a.label < b.label end)
    return { ok = true, silent = true, jobs = jobs }
end

Panel.actions['economy.setJob'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'economy.job') then
        return denied()
    end

    local target, xPlayer, err = targetOf(src, actor, data)

    if not target then
        return err
    end

    local job, grade = type(data.job) == 'string' and data.job, tonumber(data.grade)

    if not job or not grade or not ESX.DoesJobExist(job, grade) then
        return Panel.fail('Métier ou grade inconnu.')
    end

    local before = xPlayer.getJob()
    xPlayer.setJob(job, grade)
    local after = xPlayer.getJob()

    Logs.add(src, 'economy.setJob', Staff.displayName(target), {
        serverId = target, before = before and ('%s (%s)'):format(before.name, before.grade), after = ('%s (%s)'):format(job, grade),
    })

    if target ~= src then
        Panel.notify(target, ('Votre métier a été changé par le staff : %s - %s.'):format(after.label, after.grade_label), 'info')
    end

    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Inventaire (ox_inventory)
---------------------------------------------------------------------

-- Catalogue des objets du serveur (recherche « donner un objet »)
Panel.actions['economy.itemList'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'economy.items') then
        return denied()
    end

    local list = {}

    for name, item in pairs(ox:Items() or {}) do
        list[#list + 1] = { name = name, label = item.label or name }
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return { ok = true, silent = true, items = list }
end

Panel.actions['economy.inventory'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'economy.items') then
        return denied()
    end

    local target, _, err = targetOf(src, actor, data)

    if not target then
        return err
    end

    -- GetInventoryItems renvoie seulement les emplacements (GetInventory renvoie un objet complet,
    -- plus fragile à transmettre entre deux resources)
    local ok, slots = pcall(function()
        return ox:GetInventoryItems(target)
    end)

    if not ok or type(slots) ~= 'table' then
        print(("[lunatic_admin] Lecture de l'inventaire impossible : %s"):format(tostring(slots)))
        return Panel.fail("Inventaire introuvable (voir la console du serveur).")
    end

    local items, weight = {}, 0

    for _, slot in pairs(slots) do
        if type(slot) == 'table' and slot.name then
            items[#items + 1] = {
                name = slot.name,
                label = slot.label or slot.name,
                count = slot.count,
                weight = slot.weight,
                slot = slot.slot,
            }
            weight = weight + (tonumber(slot.weight) or 0)
        end
    end

    table.sort(items, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return { ok = true, silent = true, items = items, weight = weight, maxWeight = GetConvarInt('inventory:weight', 30000) }
end

-- Ouvre le vrai inventaire ox_inventory du joueur chez le membre du staff (lecture seule, comme /viewinv)
Panel.actions['economy.inspect'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'economy.items') then
        return denied()
    end

    local target, _, err = targetOf(src, actor, data)

    if not target then
        return err
    end

    if target == src then
        return Panel.fail('Ouvrez votre propre inventaire avec la touche habituelle.')
    end

    ox:InspectInventory(src, target)
    Logs.add(src, 'economy.inspect', Staff.displayName(target), { serverId = target })

    return { ok = true, silent = true }
end

Panel.actions['economy.giveItem'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'economy.items') then
        return denied()
    end

    local target, _, err = targetOf(src, actor, data)

    if not target then
        return err
    end

    local item = type(data.item) == 'string' and data.item
    local definition = item and ox:Items(item)

    if not definition then
        return Panel.fail('Objet inconnu.')
    end

    local count = wholeNumber(data.count, 1, Config.MaxItemCount)

    if not count then
        return Panel.fail(('Quantité invalide (1 à %d).'):format(Config.MaxItemCount))
    end

    if not ox:CanCarryItem(target, item, count) then
        return Panel.fail("Le joueur n'a pas la place de porter ces objets.")
    end

    local success, response = ox:AddItem(target, item, count)

    if not success then
        return Panel.fail(('Impossible de donner l\'objet (%s).'):format(tostring(response)))
    end

    Logs.add(src, 'economy.giveItem', Staff.displayName(target), { serverId = target, item = item, count = count })

    if target ~= src then
        Panel.notify(target, ('Le staff vous a donné %dx %s.'):format(count, definition.label or item), 'info')
    end

    return { ok = true, silent = true }
end

Panel.actions['economy.removeItem'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'economy.items') then
        return denied()
    end

    local target, _, err = targetOf(src, actor, data)

    if not target then
        return err
    end

    local item = type(data.item) == 'string' and data.item

    if not item or not ox:Items(item) then
        return Panel.fail('Objet inconnu.')
    end

    local owned = ox:GetItemCount(target, item) or 0

    if owned <= 0 then
        return Panel.fail("Le joueur n'a pas cet objet.")
    end

    local count = data.count == 'all' and owned or wholeNumber(data.count, 1, owned)

    if not count then
        return Panel.fail(('Quantité invalide (le joueur en a %d).'):format(owned))
    end

    if not ox:RemoveItem(target, item, count) then
        return Panel.fail("Impossible de retirer l'objet.")
    end

    Logs.add(src, 'economy.removeItem', Staff.displayName(target), { serverId = target, item = item, count = count, before = owned })
    return { ok = true, silent = true }
end

Panel.actions['economy.clearInventory'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'economy.clear') then
        return denied()
    end

    local target, _, err = targetOf(src, actor, data)

    if not target then
        return err
    end

    local reason = cleanReason(data.reason)

    if not reason then
        return reasonError()
    end

    -- Trace de ce qui est supprimé, pour pouvoir le rendre en cas d'erreur
    local removed = {}

    for _, slot in pairs((ox:GetInventory(target) or {}).items or {}) do
        if type(slot) == 'table' and slot.name then
            removed[#removed + 1] = ('%dx %s'):format(slot.count or 0, slot.name)
        end
    end

    ox:ClearInventory(target)
    Logs.add(src, 'economy.clearInventory', Staff.displayName(target), { serverId = target, reason = reason, removed = removed })

    if target ~= src then
        Panel.notify(target, 'Votre inventaire a été vidé par le staff.', 'error')
    end

    return { ok = true, silent = true, removed = #removed }
end

print('[lunatic_admin] Module Économie chargé.')
