-- Point d'entrée serveur : chargement, état envoyé au panel et actions.
-- Toute action est revérifiée ici (permission + rang strictement supérieur) : le client n'est jamais cru.

local ready = false

---------------------------------------------------------------------
-- Démarrage
---------------------------------------------------------------------

MySQL.ready(function()
    DB.init()
    Ranks.load()
    Ranks.seed()
    Staff.load()

    for _, id in ipairs(GetPlayers()) do
        Staff.trackPlayer(tonumber(id))
    end

    ready = true
    print(('[lunatic_admin] Prêt : %d rangs, %d membres du staff.'):format(Ranks.count(), #Staff.all()))
end)

AddEventHandler('playerJoining', function()
    Staff.trackPlayer(source)
end)

AddEventHandler('playerDropped', function()
    Staff.untrackPlayer(source)
end)

---------------------------------------------------------------------
-- Outils de validation
---------------------------------------------------------------------

local function notify(src, message, kind)
    TriggerClientEvent('esx:showNotification', src, message, kind or 'info')
end

---@return string|nil nom nettoyé, ou nil s'il est invalide
local function cleanName(value)
    if type(value) ~= 'string' then
        return nil
    end

    local name = value:gsub('[%c<>]', ''):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(name)

    if not length or length < Config.RankNameMin or length > Config.RankNameMax then
        return nil
    end

    return name
end

local function cleanColor(value)
    if type(value) == 'string' and value:match('^#%x%x%x%x%x%x$') then
        return value:lower()
    end
end

local function cleanLevel(value)
    local level = tonumber(value)

    if not level or level ~= math.floor(level) or level < 1 or level >= Config.OwnerLevel then
        return nil
    end

    return math.floor(level)
end

-- Permissions demandées par le client, sous forme d'ensemble (inconnues ignorées)
local function requestedSet(value)
    local set = {}

    if type(value) == 'table' then
        for _, id in ipairs(value) do
            if type(id) == 'string' and Permissions.Known[id] then
                set[id] = true
            end
        end
    end

    return set
end

-- Un membre ne peut cocher / décocher que les permissions qu'il possède lui-même ;
-- les autres gardent leur état actuel sur le rang modifié.
local function mergePermissions(actorRank, current, requested)
    local result = {}

    for id in pairs(Permissions.Known) do
        if Ranks.hasPermission(actorRank, id) then
            result[id] = requested[id] or nil
        else
            result[id] = current[id] or nil
        end
    end

    return result
end

local function freeLevelBelow(level)
    for candidate = level - 1, 1, -1 do
        if not Ranks.isLevelTaken(candidate) then
            return candidate
        end
    end
end

---------------------------------------------------------------------
-- État envoyé au panel (filtré selon les permissions)
---------------------------------------------------------------------

local function publicRank(rank)
    return {
        id = rank.id,
        name = rank.name,
        color = rank.color,
        level = rank.level,
        owner = rank.owner,
        permissions = Ranks.permissionList(rank),
        members = Staff.countByRank(rank.id),
    }
end

---@return table|false
local function buildState(src)
    local rank = Staff.rankOf(src)

    if not Ranks.hasPermission(rank, 'panel.open') then
        return false
    end
    ---@cast rank StaffRank

    local state = {
        me = {
            serverId = src,
            license = Staff.licenseOf(src),
            name = Staff.displayName(src),
            rank = publicRank(rank),
            permissions = Ranks.permissionList(rank),
        },
        catalogue = { families = Permissions.Families, permissions = Permissions.List },
        ownerLevel = Config.OwnerLevel,
    }

    if Ranks.hasPermission(rank, 'ranks.view') or Ranks.hasPermission(rank, 'staff.view') then
        state.ranks = {}

        for _, r in ipairs(Ranks.all()) do
            local entry = publicRank(r)

            -- Sans ranks.view, on ne montre que le nom et la couleur (utile à la liste des membres)
            if not Ranks.hasPermission(rank, 'ranks.view') then
                entry.permissions = nil
            end

            state.ranks[#state.ranks + 1] = entry
        end
    end

    if Ranks.hasPermission(rank, 'staff.view') then
        state.staff = {}

        for _, member in ipairs(Staff.all()) do
            local online = Staff.sourceOf(member.license)

            -- Le nom RP peut avoir changé depuis l'ajout (identité créée ou modifiée)
            if online then
                Staff.refreshName(online)
            end

            state.staff[#state.staff + 1] = {
                license = member.license,
                name = member.name,
                rankId = member.rankId,
                online = online ~= nil,
                serverId = online,
                addedAt = member.addedAt,
            }
        end
    end

    if Ranks.hasPermission(rank, 'staff.manage') then
        state.candidates = Staff.candidates()
    end

    return state
end

lib.callback.register('lunatic_admin:open', function(src)
    if not ready then
        return false
    end

    return buildState(src)
end)

---------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------

local Actions = {}

local function fail(message)
    return { ok = false, error = message }
end

-- rank.save : création (sans id) ou modification d'un rang
Actions['rank.save'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'ranks.manage') then
        return fail("Vous n'avez pas la permission de gérer les rangs.")
    end

    local name = cleanName(data.name)
    local color = cleanColor(data.color)

    if not name then
        return fail(('Le nom doit faire entre %d et %d caractères.'):format(Config.RankNameMin, Config.RankNameMax))
    end

    if not color then
        return fail('Couleur invalide.')
    end

    local requested = requestedSet(data.permissions)

    -- Modification
    if data.id then
        local rank = Ranks.get(data.id)

        if not rank then
            return fail("Ce rang n'existe plus.")
        end

        -- Rang Fondateur : seul un Fondateur peut changer son nom et sa couleur
        if rank.owner then
            if not actor.owner then
                return fail('Seul un Fondateur peut modifier ce rang.')
            end

            Ranks.update(rank, { name = name, color = color, level = rank.level, permissions = rank.permissions })
            Logs.add(src, 'rank.update', name, { id = rank.id, color = color })
            return { ok = true, id = rank.id }
        end

        if rank.level >= actor.level then
            return fail('Vous ne pouvez modifier que les rangs inférieurs au vôtre.')
        end

        local level = cleanLevel(data.level)

        if not level or level >= actor.level then
            return fail(('Le niveau doit être compris entre 1 et %d.'):format(actor.level - 1))
        end

        if Ranks.isLevelTaken(level, rank.id) then
            return fail(('Le niveau %d est déjà utilisé par un autre rang.'):format(level))
        end

        local before = { name = rank.name, level = rank.level, permissions = Ranks.permissionList(rank) }
        Ranks.update(rank, { name = name, color = color, level = level, permissions = mergePermissions(actor, rank.permissions, requested) })
        Logs.add(src, 'rank.update', name, { id = rank.id, before = before, after = { name = name, level = level, permissions = Ranks.permissionList(rank) } })

        return { ok = true, id = rank.id }
    end

    -- Création
    if Ranks.count() >= Config.MaxRanks then
        return fail(('Nombre maximal de rangs atteint (%d).'):format(Config.MaxRanks))
    end

    local level = cleanLevel(data.level)

    if not level or level >= actor.level then
        return fail(('Le niveau doit être compris entre 1 et %d.'):format(actor.level - 1))
    end

    if Ranks.isLevelTaken(level) then
        return fail(('Le niveau %d est déjà utilisé par un autre rang.'):format(level))
    end

    local rank = Ranks.create({ name = name, color = color, level = level, permissions = mergePermissions(actor, {}, requested) })
    Logs.add(src, 'rank.create', name, { id = rank.id, level = level, permissions = Ranks.permissionList(rank) })

    return { ok = true, id = rank.id }
end

Actions['rank.duplicate'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'ranks.manage') then
        return fail("Vous n'avez pas la permission de gérer les rangs.")
    end

    local original = Ranks.get(data.id)

    if not original then
        return fail("Ce rang n'existe plus.")
    end

    if original.owner or original.level >= actor.level then
        return fail('Vous ne pouvez dupliquer que les rangs inférieurs au vôtre.')
    end

    if Ranks.count() >= Config.MaxRanks then
        return fail(('Nombre maximal de rangs atteint (%d).'):format(Config.MaxRanks))
    end

    local level = freeLevelBelow(original.level) or freeLevelBelow(actor.level)

    if not level then
        return fail('Aucun niveau libre sous le vôtre.')
    end

    local suffix = ' (copie)'
    local baseName = original.name

    while utf8.len(baseName .. suffix) > Config.RankNameMax do
        baseName = baseName:sub(1, utf8.offset(baseName, -1) - 1)
    end

    -- La copie ne garde que les permissions que le membre possède lui-même
    local rank = Ranks.create({ name = baseName .. suffix, color = original.color, level = level, permissions = mergePermissions(actor, {}, original.permissions) })
    Logs.add(src, 'rank.duplicate', rank.name, { from = original.id, id = rank.id, level = level })

    return { ok = true, id = rank.id }
end

Actions['rank.delete'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'ranks.manage') then
        return fail("Vous n'avez pas la permission de gérer les rangs.")
    end

    local rank = Ranks.get(data.id)

    if not rank then
        return fail("Ce rang n'existe plus.")
    end

    if rank.owner then
        return fail('Le rang Fondateur ne peut pas être supprimé.')
    end

    if rank.level >= actor.level then
        return fail('Vous ne pouvez supprimer que les rangs inférieurs au vôtre.')
    end

    local count = Staff.countByRank(rank.id)

    if count > 0 then
        return fail(('%d membre(s) ont encore ce rang : changez-leur de rang avant de le supprimer.'):format(count))
    end

    Ranks.delete(rank)
    Logs.add(src, 'rank.delete', rank.name, { id = rank.id, level = rank.level })

    return { ok = true }
end

Actions['staff.add'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'staff.manage') then
        return fail("Vous n'avez pas la permission de gérer le staff.")
    end

    local target = tonumber(data.serverId)
    local license = target and Staff.licenseOf(target)

    if not license then
        return fail("Ce joueur n'est plus connecté.")
    end

    if Staff.get(license) then
        return fail('Ce joueur fait déjà partie du staff.')
    end

    local rank = Ranks.get(data.rankId)

    if not rank or rank.level >= actor.level then
        return fail('Vous ne pouvez attribuer que des rangs inférieurs au vôtre.')
    end

    local name = Staff.displayName(target)
    Staff.set(license, rank.id, name, Staff.licenseOf(src))
    Logs.add(src, 'staff.add', name, { license = license, rank = rank.name })
    notify(target, ('Vous avez rejoint le staff en tant que %s.'):format(rank.name), 'success')

    return { ok = true }
end

Actions['staff.setRank'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'staff.manage') then
        return fail("Vous n'avez pas la permission de gérer le staff.")
    end

    local member = type(data.license) == 'string' and Staff.get(data.license)

    if not member then
        return fail("Ce membre ne fait plus partie du staff.")
    end

    local current = Ranks.get(member.rankId)

    if member.license == Staff.licenseOf(src) or (current and current.level >= actor.level) then
        return fail('Vous ne pouvez gérer que les membres de rang inférieur au vôtre.')
    end

    local rank = Ranks.get(data.rankId)

    if not rank or rank.level >= actor.level then
        return fail('Vous ne pouvez attribuer que des rangs inférieurs au vôtre.')
    end

    if rank.id == member.rankId then
        return { ok = true }
    end

    Staff.set(member.license, rank.id, member.name, nil)
    Logs.add(src, 'staff.setRank', member.name, { license = member.license, from = current and current.name, to = rank.name })

    local target = Staff.sourceOf(member.license)

    if target then
        notify(target, ('Votre rang staff est maintenant : %s.'):format(rank.name), 'info')
    end

    return { ok = true }
end

Actions['staff.remove'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'staff.manage') then
        return fail("Vous n'avez pas la permission de gérer le staff.")
    end

    local member = type(data.license) == 'string' and Staff.get(data.license)

    if not member then
        return fail("Ce membre ne fait plus partie du staff.")
    end

    local current = Ranks.get(member.rankId)

    if member.license == Staff.licenseOf(src) or (current and current.level >= actor.level) then
        return fail('Vous ne pouvez retirer que les membres de rang inférieur au vôtre.')
    end

    Staff.remove(member.license)
    Logs.add(src, 'staff.remove', member.name, { license = member.license, rank = current and current.name })

    local target = Staff.sourceOf(member.license)

    if target then
        notify(target, 'Vous ne faites plus partie du staff.', 'error')
        TriggerClientEvent('lunatic_admin:refresh', target)
    end

    return { ok = true }
end

-- Anti-spam par joueur
local usage = {}

AddEventHandler('playerDropped', function()
    usage[source] = nil
end)

local function rateLimited(src)
    local now = GetGameTimer()
    local entry = usage[src]

    if not entry or now - entry.start > Config.RateLimit.windowMs then
        usage[src] = { start = now, count = 1 }
        return false
    end

    entry.count = entry.count + 1
    return entry.count > Config.RateLimit.max
end

lib.callback.register('lunatic_admin:action', function(src, action, data)
    if not ready then
        return fail('Le panel est en cours de chargement, réessayez dans un instant.')
    end

    if rateLimited(src) then
        return fail('Trop d’actions en peu de temps, patientez quelques secondes.')
    end

    local handler = type(action) == 'string' and Actions[action]

    if not handler then
        return fail('Action inconnue.')
    end

    local actor = Staff.rankOf(src)

    if not Ranks.hasPermission(actor, 'panel.open') then
        return fail('Accès refusé.')
    end

    local ok, result = pcall(handler, src, actor, type(data) == 'table' and data or {})

    if not ok then
        print(('[lunatic_admin] Erreur dans %s : %s'):format(action, result))
        return fail('Erreur serveur, consultez la console.')
    end

    if result.ok then
        Staff.broadcastRefresh(src)
        result.state = buildState(src)
    end

    return result
end)

---------------------------------------------------------------------
-- Commandes console (jamais utilisables en jeu)
---------------------------------------------------------------------

-- Affiche les joueurs connectés (id, nom, rang) dans la console
local function printPlayers()
    local players = GetPlayers()

    if #players == 0 then
        return print('[lunatic_admin] Aucun joueur connecté.')
    end

    print('[lunatic_admin] Joueurs connectés :')

    for _, id in ipairs(players) do
        local src = tonumber(id)
        local rank = Staff.rankOf(src)
        print(('  ID %s  |  %s (%s)%s'):format(id, Staff.displayName(src), GetPlayerName(src) or '?', rank and ('  |  ' .. rank.name) or ''))
    end
end

-- lunatic_admin_founder <id> : nomme Fondateur un joueur connecté (sans id : liste les joueurs)
RegisterCommand('lunatic_admin_founder', function(src, args)
    if src ~= 0 then
        return
    end

    if not ready then
        return print('[lunatic_admin] Pas encore prêt, réessayez dans un instant.')
    end

    local target = tonumber(args[1])
    local license = target and Staff.licenseOf(target)

    if not license then
        printPlayers()
        return print('[lunatic_admin] Usage : lunatic_admin_founder <id du joueur connecté>')
    end

    local owner = Ranks.getOwnerRank()

    if not owner then
        return print('[lunatic_admin] Aucun rang Fondateur en base.')
    end

    local name = Staff.displayName(target)
    Staff.set(license, owner.id, name, nil)
    Logs.add(0, 'staff.founder', name, { license = license })
    Staff.broadcastRefresh()
    notify(target, ('Vous êtes maintenant %s.'):format(owner.name), 'success')
    print(('[lunatic_admin] %s est maintenant %s.'):format(name, owner.name))
end, true)

-- lunatic_admin_unstaff <id|licence> : retire n'importe quel membre (y compris un Fondateur)
RegisterCommand('lunatic_admin_unstaff', function(src, args)
    if src ~= 0 then
        return
    end

    if not ready then
        return print('[lunatic_admin] Pas encore prêt, réessayez dans un instant.')
    end

    local arg = args[1]
    local license = tonumber(arg) and Staff.licenseOf(tonumber(arg)) or arg
    local member = license and Staff.get(license)

    if not member then
        return print('[lunatic_admin] Usage : lunatic_admin_unstaff <id du joueur ou licence complète "license:...">')
    end

    Staff.remove(member.license)
    Logs.add(0, 'staff.remove', member.name, { license = member.license })

    local target = Staff.sourceOf(member.license)

    if target then
        notify(target, 'Vous ne faites plus partie du staff.', 'error')
        TriggerClientEvent('lunatic_admin:refresh', target)
    end

    Staff.broadcastRefresh()
    print(('[lunatic_admin] %s a été retiré du staff.'):format(member.name))
end, true)
