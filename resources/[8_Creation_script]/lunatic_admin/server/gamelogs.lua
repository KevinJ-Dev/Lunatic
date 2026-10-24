-- Tuile Logs : événements de jeu enregistrés sans toucher aux autres ressources
-- (connexions, argent ESX, échanges d'objets ox_inventory, changements de métier). Les ressources Lunatic écrivent
-- le reste par l'export « log » (véhicules, sociétés, illégal…).

---------------------------------------------------------------------
-- Joueurs
---------------------------------------------------------------------

AddEventHandler('playerJoining', function()
    local src = source
    Logs.event('players', 'info', src, 'player.connect', nil, { name = GetPlayerName(src) })
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    Logs.event('players', 'info', src, 'player.disconnect', nil, { reason = type(reason) == 'string' and reason:sub(1, 120) or nil })
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local job = xPlayer and xPlayer.getJob()
    Logs.event('players', 'success', playerId, 'player.loaded', nil, { job = job and job.label or nil })
end)

---------------------------------------------------------------------
-- Économie : mouvements d'argent ESX (au-dessus d'un seuil, pour ne pas noyer le journal)
---------------------------------------------------------------------

local function moneyLog(operation)
    return function(src, account, amount, reason)
        amount = tonumber(amount) or 0

        if amount < Config.LogMoneyMin then
            return
        end

        Logs.event('economy', amount >= Config.LogMoneyAlert and 'warn' or 'info', src, operation, nil, {
            account = account, amount = amount, reason = type(reason) == 'string' and reason ~= '' and reason:sub(1, 80) or nil,
        })
    end
end

AddEventHandler('esx:addAccountMoney', moneyLog('money.add'))
AddEventHandler('esx:removeAccountMoney', moneyLog('money.remove'))
AddEventHandler('esx:setAccountMoney', moneyLog('money.set'))

---------------------------------------------------------------------
-- Métiers
---------------------------------------------------------------------

AddEventHandler('esx:setJob', function(src, job, lastJob)
    if not job or not lastJob or (job.name == lastJob.name and job.grade == lastJob.grade) then
        return
    end

    Logs.event('companies', 'info', src, 'job.change', job.label, {
        from = ('%s · %s'):format(lastJob.label or lastJob.name, lastJob.grade_label or lastJob.grade),
        to = ('%s · %s'):format(job.label or job.name, job.grade_label or job.grade),
    })
end)

---------------------------------------------------------------------
-- Inventaire : objets donnés à un joueur, jetés au sol, ramassés
---------------------------------------------------------------------

CreateThread(function()
    while GetResourceState('ox_inventory') ~= 'started' do
        Wait(1000)
    end

    local ox = exports.ox_inventory

    ox:registerHook('swapItems', function(payload)
        local from, to = payload.fromType, payload.toType
        local item = type(payload.fromSlot) == 'table' and payload.fromSlot or {}
        local action

        if from == 'player' and to == 'player' and payload.fromInventory ~= payload.toInventory then
            action = 'item.give'
        elseif from == 'player' and to == 'drop' then
            action = 'item.drop'
        elseif from == 'drop' and to == 'player' then
            action = 'item.pickup'
        end

        if action then
            local target = action == 'item.give' and tonumber(payload.toInventory) or nil
            Logs.event('inventory', 'info', tonumber(payload.source), action, target and Staff.displayName(target) or nil, {
                item = item.name, label = item.label, count = payload.count,
            })
        end

        return true
    end, {})
end)
