-- Lot K : outils développeur. Liste des resources (démarrer, arrêter, redémarrer), infos de l'entité visée
-- et affichage de debug (activés par le serveur après vérification de la permission dev.manage).

local MODES = { entity = true, debug = true }
local RESOURCE_NAME = GetCurrentResourceName()

local protected = {}

for _, name in ipairs(Config.DevProtectedResources) do
    protected[name] = true
end

---@type table<number, table<string, true>> modes développeur actifs par membre du staff
local active = {}

AddEventHandler('playerDropped', function()
    active[source] = nil
end)

local function setMode(src, mode, enabled)
    active[src] = active[src] or {}
    active[src][mode] = enabled or nil

    if not next(active[src]) then
        active[src] = nil
    end

    TriggerClientEvent('lunatic_admin:devMode', src, mode, enabled)
end

local function denied()
    return Panel.fail("Vous n'avez pas la permission Gestion Développeur.")
end

-- « refresh » est une commande console : elle demande une autorisation ACE dans la configuration du serveur
local function canRefresh()
    return IsPrincipalAceAllowed('resource.' .. RESOURCE_NAME, 'command.refresh')
end

table.insert(Panel.stateHooks, function(state, src, rank)
    if not Ranks.hasPermission(rank, 'dev.manage') then
        return
    end

    local modes = {}

    for mode in pairs(active[src] or {}) do
        modes[mode] = true
    end

    state.dev = { modes = modes, canRefresh = canRefresh(), resourceName = RESOURCE_NAME }
end)

-- Permission retirée : les modes sont coupés
CreateThread(function()
    while true do
        Wait(5000)

        for src, modes in pairs(active) do
            if not Staff.can(src, 'dev.manage') then
                for mode in pairs(modes) do
                    setMode(src, mode, false)
                end

                Panel.notify(src, 'Outils développeur désactivés : vous n’avez plus la permission.', 'error')
            end
        end
    end
end)

---------------------------------------------------------------------
-- Modes : infos entité, affichage de debug
---------------------------------------------------------------------

Panel.actions['dev.toggle'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'dev.manage') then
        return denied()
    end

    local mode = type(data.mode) == 'string' and data.mode

    if not mode or not MODES[mode] then
        return Panel.fail('Outil inconnu.')
    end

    setMode(src, mode, data.enabled == true)
    return { ok = true, silent = true, modes = (function()
        local modes = {}

        for m in pairs(active[src] or {}) do
            modes[m] = true
        end

        return modes
    end)() }
end

---------------------------------------------------------------------
-- Resources
---------------------------------------------------------------------

local function metadata(name, key)
    local value = GetResourceMetadata(name, key, 0)
    return type(value) == 'string' and value ~= '' and value:sub(1, 120) or nil
end

Panel.actions['dev.resources'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'dev.manage') then
        return denied()
    end

    local list = {}

    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)

        if name and name ~= '_cfx_internal' then
            list[#list + 1] = {
                name = name,
                state = GetResourceState(name),
                version = metadata(name, 'version'),
                author = metadata(name, 'author'),
                description = metadata(name, 'description'),
                protected = protected[name] == true,
            }
        end
    end

    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return { ok = true, silent = true, resources = list, canRefresh = canRefresh() }
end

Panel.actions['dev.resource'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'dev.manage') then
        return denied()
    end

    local name = type(data.name) == 'string' and data.name or ''
    local operation = data.operation

    if not name:match('^[%w%-_%.]+$') or GetResourceState(name) == 'missing' then
        return Panel.fail('Resource introuvable.')
    end

    if operation ~= 'start' and operation ~= 'stop' and operation ~= 'restart' then
        return Panel.fail('Opération inconnue.')
    end

    if operation ~= 'start' and protected[name] then
        return Panel.fail(('« %s » est protégée : arrêtez ou redémarrez-la depuis la console du serveur.'):format(name))
    end

    local before = GetResourceState(name)
    local ok = true

    if operation == 'stop' or operation == 'restart' then
        if before == 'started' or before == 'starting' then
            StopResource(name)
        end
    end

    if operation == 'start' or operation == 'restart' then
        ok = StartResource(name)
    end

    local after = GetResourceState(name)
    Logs.add(src, 'dev.resource', nil, { name = name, operation = operation, before = before, after = after })
    print(('[lunatic_admin] %s : %s %s (%s -> %s)'):format(Staff.displayName(src), operation, name, before, after))

    if not ok and operation ~= 'stop' then
        return Panel.fail(('Démarrage de « %s » impossible : voir la console du serveur.'):format(name))
    end

    -- (pas de clé « state » : le panel la prendrait pour son propre état)
    return { ok = true, silent = true, resourceState = after }
end

-- Recherche des nouvelles resources (après un envoi de fichiers) : commande « refresh »
Panel.actions['dev.refresh'] = function(src, actor)
    if not Ranks.hasPermission(actor, 'dev.manage') then
        return denied()
    end

    if not canRefresh() then
        return Panel.fail(("Ajoutez dans server.cfg : add_ace resource.%s command.refresh allow"):format(RESOURCE_NAME))
    end

    ExecuteCommand('refresh')
    Logs.add(src, 'dev.refresh', nil, nil)

    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Développeur chargé.')
