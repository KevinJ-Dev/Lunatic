-- Menu rapide du staff : sous-menus d'un joueur connecté, organisés comme l'onglet Joueurs du panel, sa fiche affichée
-- à côté du menu. Chaque action passe par l'action du panel correspondante (mêmes permissions et protections).
-- ctx (client/quickmenu.lua) : can, ask, run, input, reasonRows, closeQuick, back.

-- Fiche à jour du joueur (affichée par la page à côté du menu)
local function loadInfo(ctx, id)
    local result = ctx.ask('player.info', { serverId = id })
    return result and result.ok and result.info or nil
end

local function moneyText(value)
    return value and ('%s %s'):format(value, GlobalState.lunaticCurrency or '$') or '—'
end

-- Entrée bloquée avec sa raison (permission, soi-même, rang protégé)
local function blocked(ctx, info, permission, options)
    options = options or {}

    if not ctx.can(permission) then
        return 'Permission manquante.'
    elseif options.notSelf and info.isSelf then
        return 'Impossible sur vous-même.'
    elseif options.protect and info.protected then
        return 'Rang égal ou supérieur au vôtre.'
    end

    return options.extra
end

local function entry(ctx, info, label, permission, options, fn)
    local reason = blocked(ctx, info, permission, options)
    return { label = label, disabled = reason ~= nil, desc = reason or (options and options.desc), onSelect = fn }
end

---------------------------------------------------------------------
-- Sous-menus
---------------------------------------------------------------------

local function actionsMenu(ctx, player)
    return function()
        local info = loadInfo(ctx, player.id)

        if not info then
            return { title = 'Joueur déconnecté', items = { { label = "Ce joueur n'est plus connecté.", info = true } } }
        end

        local target = { serverId = info.serverId }
        local items = {
            { label = 'Déplacement', info = true },
            entry(ctx, info, 'Aller vers', 'players.goto', { notSelf = true }, function() ctx.run('player.goto', target, nil) end),
            entry(ctx, info, 'Ramener', 'players.bring', { notSelf = true, protect = true }, function() ctx.run('player.bring', target, 'Joueur ramené.') end),
            entry(ctx, info, 'Renvoyer à sa place', 'players.bring', { notSelf = true, protect = true, extra = not info.canReturn and "Le joueur n'a pas été ramené." or nil },
                function() ctx.run('player.return', target, 'Joueur renvoyé à sa position.') end),
            { label = 'Surveillance', info = true },
            entry(ctx, info, 'Observer', 'players.spectate', { notSelf = true }, function() ctx.closeQuick() ctx.run('player.spectate', target, nil) end),
            entry(ctx, info, info.frozen and 'Libérer' or 'Figer', 'players.freeze', { notSelf = true, protect = true },
                function() ctx.run('player.freeze', target, info.frozen and 'Joueur libéré.' or 'Joueur figé.') end),
            { label = 'Soins', info = true },
            entry(ctx, info, 'Soigner', 'players.heal', {}, function() ctx.run('player.heal', target, 'Joueur soigné.') end),
            entry(ctx, info, 'Réanimer', 'players.heal', {}, function() ctx.run('player.revive', target, 'Joueur réanimé.') end),
            entry(ctx, info, 'Nourrir', 'players.heal', {}, function() ctx.run('player.feed', target, 'Faim et soif remplies.') end),
        }

        return { title = 'Actions', items = items, sheet = info }
    end
end

local function characterMenu(ctx, player)
    return function()
        local info = loadInfo(ctx, player.id)

        if not info then
            return { title = 'Joueur déconnecté', items = { { label = "Ce joueur n'est plus connecté.", info = true } } }
        end

        local target = { serverId = info.serverId }
        local items = {
            entry(ctx, info, 'Menu apparence', 'players.appearance', { protect = true }, function()
                if ctx.run('player.appearance', target, info.isSelf and nil or "Menu d'apparence ouvert chez le joueur.") and info.isSelf then
                    ctx.closeQuick()
                end
            end),
            info.isSelf and entry(ctx, info, 'Rétablir mon apparence', 'players.copy_appearance', {}, function() ctx.run('player.restoreAppearance', target, 'Votre apparence est rétablie.') end)
                or entry(ctx, info, "Copier l'apparence sur moi", 'players.copy_appearance', {}, function() ctx.run('player.copyAppearance', target, 'Apparence copiée sur vous (non enregistrée).') end),
            entry(ctx, info, 'Donner un véhicule', 'vehicles.give', {}, function()
                local values = ctx.input(('Véhicule pour %s'):format(info.name), { { type = 'input', label = 'Modèle (ex. sultan)', required = true, min = 2, max = 32 } })
                if values then ctx.run('vehicle.give', { serverId = info.serverId, model = values[1]:lower() }, 'Véhicule ajouté à son garage.') end
            end),
            entry(ctx, info, 'Recréer le personnage', 'players.recreate', { protect = true, desc = 'Le joueur repasse par la création de personnage.' }, function()
                local values = ctx.input(('Recréer %s'):format(info.name), ctx.reasonRows())
                if values then ctx.run('player.recreate', { serverId = info.serverId, reason = values[1] }, 'Le joueur repasse par la création de personnage.') end
            end),
            entry(ctx, info, 'Wipe', 'players.wipe', { notSelf = true, protect = true, desc = 'Tout est réinitialisé (argent, inventaire, métier, véhicules, permis, identité).' }, function()
                local values = ctx.input(('Wipe de %s'):format(info.name), ctx.reasonRows({ { type = 'input', label = ('Tapez « %s » pour confirmer'):format(info.name), required = true } }))
                if values then ctx.run('player.wipe', { serverId = info.serverId, confirm = values[1], reason = values[2] }, 'Joueur wipe.') end
            end),
        }

        return { title = 'Personnage', items = items, sheet = info }
    end
end

local function historyMenu(ctx, info)
    return function()
        local result = ctx.ask('sanctions.history', { license = info.license })
        local items = {}
        local TYPES = { warn = 'Warn', ban = 'Ban', jail = 'Prison', kick = 'Kick' }

        for _, sanction in ipairs(result and result.sanctions or {}) do
            local label = ('#%d · %s · %s'):format(sanction.id, TYPES[sanction.type] or sanction.type, sanction.reason or '')

            if sanction.canRevoke and sanction.active then
                items[#items + 1] = { label = label, right = 'révoquer', desc = ('Par %s'):format(sanction.staff or '?'), onSelect = function()
                    local values = ctx.input(('Révoquer la sanction #%d'):format(sanction.id), ctx.reasonRows())
                    if values then ctx.run('sanction.revoke', { id = sanction.id, reason = values[1] }, 'Sanction révoquée.') end
                end }
            else
                items[#items + 1] = { label = label, right = sanction.active and 'active' or nil, info = true }
            end
        end

        if #items == 0 then
            items[1] = { label = 'Aucune sanction', info = true }
        end

        return { title = 'Historique des sanctions', items = items, sheet = info }
    end
end

local function sanctionsMenu(ctx, player)
    return function()
        local info = loadInfo(ctx, player.id)

        if not info then
            return { title = 'Joueur déconnecté', items = { { label = "Ce joueur n'est plus connecté.", info = true } } }
        end

        local id = info.serverId
        local items = {
            entry(ctx, info, 'Avertir', 'sanctions.warn', { notSelf = true, protect = true }, function()
                local values = ctx.input(('Avertir %s'):format(info.name), ctx.reasonRows())
                if values then ctx.run('sanction.warn', { serverId = id, reason = values[1] }, 'Avertissement envoyé.') end
            end),
            info.jail and entry(ctx, info, ('Sortir de prison (%d min)'):format(math.ceil((info.jail.remaining or 0) / 60)), 'sanctions.jail', { notSelf = true },
                function() ctx.run('sanction.unjail', { serverId = id }, 'Joueur libéré de prison.') end)
                or entry(ctx, info, 'Prison staff', 'sanctions.jail', { notSelf = true, protect = true }, function()
                    local values = ctx.input(('Prison staff : %s'):format(info.name), ctx.reasonRows({ { type = 'number', label = 'Durée (minutes)', required = true, min = 1, default = 10 } }))
                    if values then ctx.run('sanction.jail', { serverId = id, minutes = values[1], reason = values[2] }, 'Joueur mis en prison staff.') end
                end),
            entry(ctx, info, 'Bannir', 'sanctions.ban', { notSelf = true, protect = true }, function()
                local durations = { { value = '24', label = '24 heures' }, { value = '72', label = '3 jours' }, { value = '168', label = '7 jours' }, { value = '720', label = '30 jours' } }

                if ctx.can('sanctions.ban_permanent') then
                    durations[#durations + 1] = { value = 'permanent', label = 'Définitif' }
                end

                local values = ctx.input(('Bannir %s'):format(info.name), ctx.reasonRows({ { type = 'select', label = 'Durée', required = true, options = durations, default = '24' } }))
                if values then ctx.run('sanction.ban', { serverId = id, duration = values[1], reason = values[2] }, 'Joueur banni.') end
            end),
            entry(ctx, info, 'Expulser', 'players.kick', { notSelf = true, protect = true }, function()
                local values = ctx.input(('Expulser %s'):format(info.name), ctx.reasonRows())
                if values then ctx.run('player.kick', { serverId = id, reason = values[1] }, 'Joueur expulsé.') end
            end),
            entry(ctx, info, 'Déconnecter (sans raison affichée)', 'players.crash', { notSelf = true, protect = true }, function()
                ctx.run('player.crash', { serverId = id }, 'Joueur déconnecté.')
            end),
        }

        if ctx.can('sanctions.view') then
            items[#items + 1] = { label = 'Historique des sanctions', submenu = historyMenu(ctx, info) }
        end

        return { title = 'Sanctions', items = items, sheet = info }
    end
end

-- Argent : compte, opération, montant et raison
local ACCOUNTS = { { 'money', 'Liquide', 'economy.money', 'money' }, { 'bank', 'Banque', 'economy.money', 'bank' }, { 'black_money', 'Argent sale', 'economy.black_money', 'blackMoney' } }

local function jobsMenu(ctx, info)
    return function()
        local result = ctx.ask('economy.jobs', {})
        local items = {}

        for _, job in ipairs(result and result.jobs or {}) do
            items[#items + 1] = { label = job.label, right = job.name, submenu = function()
                local grades = {}

                for _, grade in ipairs(job.grades or {}) do
                    grades[#grades + 1] = { label = grade.label, right = tostring(grade.grade), onSelect = function()
                        if ctx.run('economy.setJob', { serverId = info.serverId, job = job.name, grade = grade.grade }, ('Métier : %s · %s.'):format(job.label, grade.label)) then
                            ctx.back(2)
                        end
                    end }
                end

                return { title = job.label, items = grades, sheet = info }
            end }
        end

        return { title = 'Changer de métier', items = items, sheet = info }
    end
end

local function moneyMenu(ctx, player)
    return function()
        local info = loadInfo(ctx, player.id)

        if not info then
            return { title = 'Joueur déconnecté', items = { { label = "Ce joueur n'est plus connecté.", info = true } } }
        end

        local items = {}

        for _, account in ipairs(ACCOUNTS) do
            local key, label, permission, field = account[1], account[2], account[3], account[4]

            if ctx.can(permission) then
                items[#items + 1] = entry(ctx, info, label, permission, { protect = true }, function()
                    local values = ctx.input(('%s de %s : %s'):format(label, info.name, moneyText(info[field])), {
                        { type = 'select', label = 'Opération', required = true, default = 'add', options = { { value = 'add', label = 'Donner' }, { value = 'remove', label = 'Retirer' }, { value = 'set', label = 'Définir' } } },
                        { type = 'number', label = 'Montant', required = true, min = 0 },
                        { type = 'input', label = 'Raison', required = true, min = 3, max = 200 },
                    })
                    if values then ctx.run('economy.money', { serverId = info.serverId, account = key, operation = values[1], amount = values[2], reason = values[3] }, 'Solde modifié.') end
                end)
                items[#items].right = moneyText(info[field])
            end
        end

        if ctx.can('economy.job') then
            items[#items + 1] = { label = 'Changer de métier', right = info.job and (info.job.label or info.job.name) or nil, disabled = info.protected,
                desc = info.protected and 'Rang égal ou supérieur au vôtre.' or nil, submenu = not info.protected and jobsMenu(ctx, info) or nil }
        end

        if #items == 0 then
            items[1] = { label = 'Aucune permission sur l\u{2019}argent ou le métier', info = true }
        end

        return { title = 'Argent et métier', items = items, sheet = info }
    end
end

local function inventoryMenu(ctx, player)
    return function()
        local info = loadInfo(ctx, player.id)

        if not info then
            return { title = 'Joueur déconnecté', items = { { label = "Ce joueur n'est plus connecté.", info = true } } }
        end

        local id = info.serverId
        local items = {}

        if ctx.can('economy.items') then
            items[#items + 1] = entry(ctx, info, 'Ouvrir son inventaire', 'economy.items', { notSelf = true, desc = 'Lecture seule, à l\u{2019}écran.' }, function()
                if ctx.run('economy.inspect', { serverId = id }, nil) then
                    ctx.closeQuick()
                end
            end)
            items[#items + 1] = entry(ctx, info, 'Donner un objet', 'economy.items', { protect = true }, function()
                local values = ctx.input(('Donner un objet à %s'):format(info.name), {
                    { type = 'input', label = "Nom de l'objet (ex. water)", required = true, min = 1, max = 60 },
                    { type = 'number', label = 'Quantité', required = true, min = 1, default = 1 },
                })
                if values then ctx.run('economy.giveItem', { serverId = id, item = values[1], count = values[2] }, 'Objet donné.') end
            end)

            local result = ctx.ask('economy.inventory', { serverId = id })

            if result and result.ok then
                items[#items + 1] = { label = ('Objets (%.1f / %.1f kg)'):format((result.weight or 0) / 1000, (result.maxWeight or 0) / 1000), info = true }

                for _, item in ipairs(result.items or {}) do
                    items[#items + 1] = { label = item.label, right = ('x%d'):format(item.count), desc = info.protected and 'Rang égal ou supérieur au vôtre : lecture seule.' or 'Entrée : retirer une quantité.',
                        disabled = info.protected, onSelect = function()
                            local values = ctx.input(('Retirer %s'):format(item.label), { { type = 'number', label = ('Quantité (max %d)'):format(item.count), required = true, min = 1, max = item.count, default = item.count } })
                            if values then ctx.run('economy.removeItem', { serverId = id, item = item.name, count = values[1] }, ('%s retiré.'):format(item.label)) end
                        end }
                end
            end
        end

        if ctx.can('economy.clear') then
            items[#items + 1] = entry(ctx, info, "Vider l'inventaire", 'economy.clear', { protect = true }, function()
                local values = ctx.input(("Vider l'inventaire de %s"):format(info.name), ctx.reasonRows())
                if values then ctx.run('economy.clearInventory', { serverId = id, reason = values[1] }, 'Inventaire vidé.') end
            end)
        end

        if #items == 0 then
            items[1] = { label = "Aucune permission sur l'inventaire", info = true }
        end

        return { title = 'Inventaire', items = items, sheet = info }
    end
end

local function licensesMenu(ctx, player)
    return function()
        local info = loadInfo(ctx, player.id)

        if not info then
            return { title = 'Joueur déconnecté', items = { { label = "Ce joueur n'est plus connecté.", info = true } } }
        end

        local items = {}
        local editable = ctx.can('players.licenses') and not info.protected

        for _, license in ipairs(info.licenses or {}) do
            items[#items + 1] = { label = license.label, toggle = true, on = license.owned, disabled = not editable, onSelect = function()
                ctx.run('license.set', { serverId = info.serverId, type = license.type, owned = not license.owned }, license.owned and ('%s retiré.'):format(license.label) or ('%s donné.'):format(license.label))
            end }
        end

        if #items == 0 then
            items[1] = { label = 'Aucun permis défini', info = true }
        end

        return { title = 'Permis', items = items, sheet = info }
    end
end

local function vehiclesMenu(ctx, player)
    return function()
        local info = loadInfo(ctx, player.id)
        local items = {}

        for _, vehicle in ipairs(info and info.profile and info.profile.vehicles or {}) do
            items[#items + 1] = { label = vehicle.plate, right = vehicle.stored and 'au garage' or 'sorti', info = true }
        end

        for _, instance in ipairs(info and info.profile and info.profile.instances or {}) do
            items[#items + 1] = { label = instance.label, right = instance.kind, info = true }
        end

        if #items == 0 then
            items[1] = { label = 'Aucun véhicule ni propriété', info = true }
        end

        return { title = 'Véhicules et propriétés', items = items, sheet = info }
    end
end

local function logsMenu(ctx, player)
    return function()
        local info = loadInfo(ctx, player.id)
        local result = info and ctx.ask('logs.player', { license = info.license })
        local items = {}

        for _, log in ipairs(result and result.logs or {}) do
            items[#items + 1] = { label = ('%s · %s'):format(log.action, log.target or log.actor or ''), right = log.actor, info = true }

            if #items >= 40 then
                break
            end
        end

        if #items == 0 then
            items[1] = { label = 'Aucun log récent', info = true }
        end

        return { title = 'Logs du joueur', items = items, sheet = info }
    end
end

local function premiumMenu(ctx, player)
    return function()
        local info = loadInfo(ctx, player.id)

        if not info then
            return { title = 'Joueur déconnecté', items = { { label = "Ce joueur n'est plus connecté.", info = true } } }
        end

        local target = { serverId = info.serverId }
        local items = {
            { label = info.premium and ('Abonnement : %s'):format(info.premium.label) or 'Aucun abonnement', info = true },
            { label = 'Attribuer un abonnement', onSelect = function()
                local values = ctx.input(('Abonnement pour %s'):format(info.name), {
                    { type = 'select', label = 'Abonnement', required = true, default = 'premium', options = { { value = 'premium', label = 'Premium' }, { value = 'premium_plus', label = 'Premium+' } } },
                    { type = 'input', label = 'Durée en jours (ou « lifetime »)', required = true, default = '30' },
                })
                if values then ctx.run('premium.set', { serverId = info.serverId, tier = values[1], days = values[2] == 'lifetime' and 'lifetime' or tonumber(values[2]) }, 'Abonnement attribué.') end
            end },
        }

        if info.premium then
            items[#items + 1] = { label = "Retirer l'abonnement", onSelect = function() ctx.run('premium.remove', target, 'Abonnement retiré.') end }
        end

        items[#items + 1] = { label = 'Crédits boutique', right = tostring(info.credits or 0), onSelect = function()
            local values = ctx.input(('Crédits de %s'):format(info.name), {
                { type = 'number', label = 'Montant (négatif pour retirer)', required = true },
                { type = 'input', label = 'Raison', required = true, min = 3, max = 200 },
            })
            if values then ctx.run('credits.change', { serverId = info.serverId, amount = values[1], reason = values[2] }, 'Crédits modifiés.') end
        end }

        return { title = 'Premium et crédits', items = items, sheet = info }
    end
end

---------------------------------------------------------------------
-- Menu d'un joueur : fiche à côté, puis ses sous-menus
---------------------------------------------------------------------

function QuickPlayerMenu(player, ctx)
    return function()
        local info = loadInfo(ctx, player.id)

        if not info then
            return { title = ('%d · %s'):format(player.id, player.name), items = { { label = "Ce joueur n'est plus connecté.", info = true } } }
        end

        local items = {
            { label = 'Actions', desc = 'Déplacement, surveillance, soins.', submenu = actionsMenu(ctx, player) },
            { label = 'Sanctions', desc = 'Avertir, prison, ban, kick, historique.', submenu = sanctionsMenu(ctx, player) },
            { label = 'Argent et métier', submenu = moneyMenu(ctx, player) },
            { label = 'Inventaire', submenu = inventoryMenu(ctx, player) },
            { label = 'Permis', submenu = licensesMenu(ctx, player) },
            { label = 'Véhicules et propriétés', submenu = vehiclesMenu(ctx, player) },
            { label = 'Personnage', desc = 'Apparence, véhicule, recréer, wipe.', submenu = characterMenu(ctx, player) },
        }

        if ctx.can('logs.view') then
            items[#items + 1] = { label = 'Logs du joueur', submenu = logsMenu(ctx, player) }
        end

        if ctx.can('premium.manage') then
            items[#items + 1] = { label = 'Premium et crédits', submenu = premiumMenu(ctx, player) }
        end

        if ctx.can('players.view') then
            items[#items + 1] = { label = 'Ouvrir sa fiche dans le panel', onSelect = function() ctx.closeQuick() OpenPanelOnPlayer(info.serverId) end }
        end

        return { title = ('%d · %s'):format(info.serverId, info.name), items = items, sheet = info }
    end
end
