-- Lot H : gestion globale du serveur (page Serveur) : redémarrage planifié, maintenance, actions de masse.

local ANNOUNCE_AT = { 900, 600, 300, 120, 60, 30, 10 } -- secondes restantes déclenchant une annonce

---@type {endsAt:number, reason:string, by:string, announced:table<number, true>}|nil
local restart
local maintenance = { enabled = false, message = 'Le serveur est en maintenance. Revenez un peu plus tard !' }

-- La maintenance survit aux redémarrages
local saved = GetResourceKvpString('maintenance')

if saved then
    local ok, data = pcall(json.decode, saved)

    if ok and type(data) == 'table' then
        maintenance.enabled = data.enabled == true
        maintenance.message = type(data.message) == 'string' and data.message or maintenance.message
    end
end

local now = Util.now

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer le serveur.")
end

-- Annonce à tout le serveur : bandeau du tchat Lunatic si présent, notification sinon
local function announce(text)
    if GetResourceState('lunatic_chat') == 'started' then
        TriggerClientEvent('lunatic_chat:message', -1, { kind = 'announce', text = text })
    end

    TriggerClientEvent('esx:showNotification', -1, text, 'info')
end

local function formatDelay(seconds)
    if seconds >= 60 then
        local minutes = math.floor(seconds / 60 + 0.5)
        return ('%d minute%s'):format(minutes, minutes > 1 and 's' or '')
    end

    return ('%d secondes'):format(seconds)
end

-- Expulse les joueurs (ESX sauvegarde chacun à sa déconnexion) ; keepStaff garde les membres du staff
local function dropAll(message, keepStaff)
    local count = 0

    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local license = Staff.licenseOf(src)

        if not (keepStaff and license and Staff.get(license)) then
            DropPlayer(src, message)
            count = count + 1
        end
    end

    return count
end

---------------------------------------------------------------------
-- Redémarrage planifié
---------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(1000)

        if restart then
            local remaining = restart.endsAt - now()

            for _, mark in ipairs(ANNOUNCE_AT) do
                if remaining <= mark and remaining > mark - 2 and not restart.announced[mark] then
                    restart.announced[mark] = true
                    announce(('Redémarrage du serveur dans %s%s. Mettez-vous en sécurité.'):format(formatDelay(mark), restart.reason ~= '' and (' (' .. restart.reason .. ')') or ''))
                end
            end

            if remaining <= 0 then
                local reason = restart.reason
                restart = nil
                print('[lunatic_admin] Redémarrage planifié : expulsion de tous les joueurs.')
                dropAll(('Redémarrage du serveur%s. Reconnectez-vous dans quelques minutes.'):format(reason ~= '' and (' : ' .. reason) or ''), false)
                Staff.broadcastRefresh()
            end
        end
    end
end)

---------------------------------------------------------------------
-- Maintenance : seul le staff peut se connecter
---------------------------------------------------------------------

AddEventHandler('playerConnecting', function(_, _, deferrals)
    if not maintenance.enabled then
        return
    end

    local src = source
    deferrals.defer()
    Wait(0)

    local license = GetPlayerIdentifierByType(src, 'license')

    if license and Staff.get(license) then
        deferrals.done()
    else
        deferrals.done(('🔧 %s'):format(maintenance.message))
    end
end)

---------------------------------------------------------------------
-- État de la page Serveur
---------------------------------------------------------------------

table.insert(Panel.stateHooks, function(state, _, rank)
    if not Ranks.hasPermission(rank, 'server.manage') then
        return
    end

    state.server = {
        maintenance = maintenance.enabled,
        maintenanceMessage = maintenance.message,
        -- Temps restant plutôt qu'une date : l'horloge du PC du joueur peut différer de celle du serveur
        restart = restart and { remaining = math.max(0, restart.endsAt - now()), reason = restart.reason, by = restart.by } or nil,
        players = #GetPlayers(),
    }
end)

---------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------

local cleanText = Util.cleanText

Panel.actions['server.restart'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'server.manage') then
        return denied()
    end

    if restart then
        return Panel.fail('Un redémarrage est déjà programmé : annulez-le d\'abord.')
    end

    local minutes = tonumber(data.minutes)

    if not minutes or minutes ~= math.floor(minutes) or minutes < 1 or minutes > 60 then
        return Panel.fail('Délai invalide : de 1 à 60 minutes.')
    end

    local reason = cleanText(data.reason or '', 0, 100) or ''

    restart = { endsAt = now() + minutes * 60, reason = reason, by = Staff.displayName(src), announced = {} }
    announce(('Redémarrage du serveur dans %s%s.'):format(formatDelay(minutes * 60), reason ~= '' and (' (' .. reason .. ')') or ''))
    -- Les annonces déjà dépassées par le délai choisi ne sont pas répétées
    for _, mark in ipairs(ANNOUNCE_AT) do
        if mark >= minutes * 60 then
            restart.announced[mark] = true
        end
    end

    Logs.add(src, 'server.restart', nil, { minutes = minutes, reason = reason })
    return { ok = true }
end

Panel.actions['server.cancelRestart'] = function(src, actor)
    if not Ranks.hasPermission(actor, 'server.manage') then
        return denied()
    end

    if not restart then
        return Panel.fail('Aucun redémarrage programmé.')
    end

    restart = nil
    announce('Le redémarrage prévu du serveur est annulé.')
    Logs.add(src, 'server.cancelRestart', nil, nil)
    return { ok = true }
end

Panel.actions['server.maintenance'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'server.manage') then
        return denied()
    end

    -- Sans nouveau message, on garde l'actuel ; un message fourni doit être valide
    local message = maintenance.message

    if data.message ~= nil then
        message = cleanText(data.message, 5, 200)
    end

    if not message then
        return Panel.fail('Le message doit faire entre 5 et 200 caractères.')
    end

    maintenance.enabled = data.enabled == true
    maintenance.message = message
    SetResourceKvp('maintenance', json.encode(maintenance))

    Logs.add(src, 'server.maintenance', nil, { enabled = maintenance.enabled, message = message })
    return { ok = true }
end

-- Soigne, réanime et nourrit tous les joueurs
Panel.actions['server.healAll'] = function(src, actor)
    if not Ranks.hasPermission(actor, 'server.manage') then
        return denied()
    end

    TriggerClientEvent('lunatic_admin:revive', -1)
    TriggerClientEvent('lunatic_admin:feed', -1)
    TriggerClientEvent('esx:showNotification', -1, 'Le staff a soigné tout le serveur.', 'success')
    Logs.add(src, 'server.healAll', nil, { players = #GetPlayers() })

    return { ok = true, silent = true, count = #GetPlayers() }
end

-- Téléporte tous les joueurs (sauf le staff qui lance l'action) à sa position
Panel.actions['server.bringAll'] = function(src, actor)
    if not Ranks.hasPermission(actor, 'server.manage') then
        return denied()
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return Panel.fail("Votre personnage n'est pas encore apparu.")
    end

    local origin = GetEntityCoords(ped)
    local bucket = GetPlayerRoutingBucket(src)
    local count = 0

    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)

        if target ~= src then
            -- Petit décalage en cercle pour ne pas empiler tout le monde au même point
            local angle = count * 0.6
            local radius = 1.5 + count * 0.15
            SetPlayerRoutingBucket(target, bucket)
            TriggerClientEvent('lunatic_admin:teleport', target, origin + vector3(math.cos(angle) * radius, math.sin(angle) * radius, 0.0))
            count = count + 1
        end
    end

    Logs.add(src, 'server.bringAll', nil, { count = count })
    return { ok = true, silent = true, count = count }
end

Panel.actions['server.kickAll'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'server.manage') then
        return denied()
    end

    local reason = cleanText(data.reason, 3, 120)

    if not reason then
        return Panel.fail('La raison doit faire entre 3 et 120 caractères.')
    end

    local count = dropAll(('Expulsion générale : %s'):format(reason), true)
    Logs.add(src, 'server.kickAll', nil, { count = count, reason = reason })

    return { ok = true, count = count }
end

print(('[lunatic_admin] Module Serveur chargé%s.'):format(maintenance.enabled and ' (MAINTENANCE ACTIVE)' or ''))
