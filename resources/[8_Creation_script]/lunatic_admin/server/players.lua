-- Lot 2 : joueurs connectés (liste, fiche) et actions du staff sur eux.
-- Chaque action vérifie la permission, la cible, et protège les membres du staff de rang égal ou supérieur.

---@type table<number, true> joueurs figés
local frozen = {}
---@type table<number, vector3> position d'un joueur avant d'être ramené
local returnPoints = {}
---@type table<number, {target:number, bucket:number}> staff en train d'observer
local spectating = {}

AddEventHandler('playerDropped', function()
    local src = source
    frozen[src], returnPoints[src], spectating[src] = nil, nil, nil
end)

---------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------

local function rankBadge(src)
    local rank = Staff.rankOf(src)
    return rank and { name = rank.name, color = rank.color } or nil
end

local function jobOf(xPlayer)
    local job = xPlayer and xPlayer.getJob()
    return job and { name = job.name, label = job.label, grade = job.grade_label, level = job.grade } or nil
end

local function pedCoords(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end

    return GetEntityCoords(ped)
end

-- La cible d'une action : un joueur connecté
local function targetOf(data)
    local target = tonumber(data.serverId)

    if target and GetPlayerName(target) then
        return target
    end
end

-- Un membre du staff de rang égal ou supérieur est protégé
local function isProtected(actor, target)
    local rank = Staff.rankOf(target)
    return rank ~= nil and rank.level >= actor.level
end

---@param options {notSelf?:boolean, protect?:boolean}
---@return number|nil target, table|nil error
local function check(src, actor, data, permission, options)
    if not Ranks.hasPermission(actor, permission) then
        return nil, Panel.fail("Vous n'avez pas la permission.")
    end

    local target = targetOf(data)

    if not target then
        return nil, Panel.fail("Ce joueur n'est plus connecté.")
    end

    if options.notSelf and target == src then
        return nil, Panel.fail('Action impossible sur vous-même.')
    end

    if options.protect and target ~= src and isProtected(actor, target) then
        return nil, Panel.fail('Ce membre du staff a un rang égal ou supérieur au vôtre.')
    end

    return target
end

local function cleanReason(value)
    if type(value) ~= 'string' then
        return nil
    end

    local reason = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(reason)

    if not length or length < Config.KickReasonMin or length > Config.KickReasonMax then
        return nil
    end

    return reason
end

local function ok()
    return { ok = true, silent = true }
end

---------------------------------------------------------------------
-- Liste des joueurs, ajoutée à l'état du panel
---------------------------------------------------------------------

table.insert(Panel.stateHooks, function(state, _, rank)
    if not Ranks.hasPermission(rank, 'players.view') then
        return
    end

    local list = {}

    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        local job = jobOf(ESX.GetPlayerFromId(target))

        list[#list + 1] = {
            serverId = target,
            name = Staff.displayName(target),
            job = job and job.label or nil,
            ping = GetPlayerPing(target),
            rank = rankBadge(target),
            frozen = frozen[target] == true,
        }
    end

    table.sort(list, function(a, b) return a.serverId < b.serverId end)
    state.players = list
end)

---------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------

-- Fiche détaillée d'un joueur
Panel.actions['player.info'] = function(src, actor, data)
    local target, err = check(src, actor, data, 'players.view', {})

    if not target then
        return err
    end

    local xPlayer = ESX.GetPlayerFromId(target)
    local ped = GetPlayerPed(target)

    local info = {
        serverId = target,
        name = Staff.displayName(target),
        pseudo = GetPlayerName(target),
        license = GetPlayerIdentifierByType(target, 'license'),
        ping = GetPlayerPing(target),
        rank = rankBadge(target),
        frozen = frozen[target] == true,
        canReturn = returnPoints[target] ~= nil,
        isSelf = target == src,
        protected = target ~= src and isProtected(actor, target),
    }

    if ped and ped ~= 0 then
        info.health = GetEntityHealth(ped)
        info.maxHealth = GetEntityMaxHealth(ped)
        info.armor = GetPedArmour(ped)
    end

    if xPlayer then
        local money, bank, black = xPlayer.getAccount('money'), xPlayer.getAccount('bank'), xPlayer.getAccount('black_money')

        info.job = jobOf(xPlayer)
        info.money = money and money.money or nil
        info.bank = bank and bank.money or nil
        info.blackMoney = black and black.money or nil
        info.dateofbirth = xPlayer.get('dateofbirth')
        info.sex = xPlayer.get('sex')
        info.height = xPlayer.get('height')
    end

    return { ok = true, silent = true, info = info }
end

Panel.actions['player.goto'] = function(src, actor, data)
    local target, err = check(src, actor, data, 'players.goto', { notSelf = true })

    if not target then
        return err
    end

    local coords = pedCoords(target)

    if not coords then
        return Panel.fail("Ce joueur n'est pas encore apparu.")
    end

    SetPlayerRoutingBucket(src, GetPlayerRoutingBucket(target))
    TriggerClientEvent('lunatic_admin:teleport', src, coords + vector3(1.0, 0.0, 0.0))
    Logs.add(src, 'player.goto', Staff.displayName(target), { serverId = target })

    return ok()
end

Panel.actions['player.bring'] = function(src, actor, data)
    local target, err = check(src, actor, data, 'players.bring', { notSelf = true, protect = true })

    if not target then
        return err
    end

    local from, to = pedCoords(target), pedCoords(src)

    if not from or not to then
        return Panel.fail("Position introuvable (joueur pas encore apparu).")
    end

    returnPoints[target] = from
    SetPlayerRoutingBucket(target, GetPlayerRoutingBucket(src))
    TriggerClientEvent('lunatic_admin:teleport', target, to + vector3(1.0, 0.0, 0.0))
    Panel.notify(target, 'Vous avez été téléporté par le staff.', 'info')
    Logs.add(src, 'player.bring', Staff.displayName(target), { serverId = target })

    return ok()
end

Panel.actions['player.return'] = function(src, actor, data)
    local target, err = check(src, actor, data, 'players.bring', { notSelf = true, protect = true })

    if not target then
        return err
    end

    local point = returnPoints[target]

    if not point then
        return Panel.fail("Aucune position enregistrée : ce joueur n'a pas été ramené.")
    end

    returnPoints[target] = nil
    TriggerClientEvent('lunatic_admin:teleport', target, point)
    Panel.notify(target, 'Vous avez été renvoyé à votre position.', 'info')
    Logs.add(src, 'player.return', Staff.displayName(target), { serverId = target })

    return ok()
end

Panel.actions['player.spectate'] = function(src, actor, data)
    local target, err = check(src, actor, data, 'players.spectate', { notSelf = true })

    if not target then
        return err
    end

    local coords = pedCoords(target)

    if not coords then
        return Panel.fail("Ce joueur n'est pas encore apparu.")
    end

    -- On rejoint l'instance de la cible le temps de l'observation
    if not spectating[src] then
        spectating[src] = { target = target, bucket = GetPlayerRoutingBucket(src) }
    else
        spectating[src].target = target
    end

    SetPlayerRoutingBucket(src, GetPlayerRoutingBucket(target))
    TriggerClientEvent('lunatic_admin:spectate', src, target, coords, Staff.displayName(target))
    Logs.add(src, 'player.spectate', Staff.displayName(target), { serverId = target })

    return ok()
end

-- Fin d'observation (envoyée par le client) : retour dans son instance d'origine
RegisterNetEvent('lunatic_admin:spectateEnd', function()
    local src = source
    local session = spectating[src]

    if session then
        spectating[src] = nil
        SetPlayerRoutingBucket(src, session.bucket)
    end
end)

Panel.actions['player.freeze'] = function(src, actor, data)
    local target, err = check(src, actor, data, 'players.freeze', { notSelf = true, protect = true })

    if not target then
        return err
    end

    local state = not frozen[target]
    frozen[target] = state or nil

    TriggerClientEvent('lunatic_admin:freeze', target, state)
    Panel.notify(target, state and 'Vous avez été figé par le staff.' or 'Vous pouvez de nouveau bouger.', 'info')
    Logs.add(src, state and 'player.freeze' or 'player.unfreeze', Staff.displayName(target), { serverId = target })

    -- La liste des autres panels affiche l'état figé
    return { ok = true }
end

Panel.actions['player.heal'] = function(src, actor, data)
    local target, err = check(src, actor, data, 'players.heal', {})

    if not target then
        return err
    end

    TriggerClientEvent('lunatic_admin:heal', target)

    if target ~= src then
        Panel.notify(target, 'Vous avez été soigné par le staff.', 'success')
    end

    Logs.add(src, 'player.heal', Staff.displayName(target), { serverId = target })
    return ok()
end

Panel.actions['player.revive'] = function(src, actor, data)
    local target, err = check(src, actor, data, 'players.heal', {})

    if not target then
        return err
    end

    TriggerClientEvent('lunatic_admin:revive', target)

    if target ~= src then
        Panel.notify(target, 'Vous avez été réanimé par le staff.', 'success')
    end

    Logs.add(src, 'player.revive', Staff.displayName(target), { serverId = target })
    return ok()
end

Panel.actions['player.feed'] = function(src, actor, data)
    local target, err = check(src, actor, data, 'players.heal', {})

    if not target then
        return err
    end

    TriggerClientEvent('lunatic_admin:feed', target)

    if target ~= src then
        Panel.notify(target, 'Le staff vous a rassasié et désaltéré.', 'success')
    end

    Logs.add(src, 'player.feed', Staff.displayName(target), { serverId = target })
    return ok()
end

Panel.actions['player.kick'] = function(src, actor, data)
    local target, err = check(src, actor, data, 'players.kick', { notSelf = true, protect = true })

    if not target then
        return err
    end

    local reason = cleanReason(data.reason)

    if not reason then
        return Panel.fail(('La raison doit faire entre %d et %d caractères.'):format(Config.KickReasonMin, Config.KickReasonMax))
    end

    local name = Staff.displayName(target)
    Logs.add(src, 'player.kick', name, { serverId = target, license = GetPlayerIdentifierByType(target, 'license'), reason = reason })
    DropPlayer(target, ('Expulsé par le staff : %s'):format(reason))

    return { ok = true }
end

print('[lunatic_admin] Module Joueurs chargé.')
