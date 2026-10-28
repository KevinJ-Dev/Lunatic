-- Menu rapide du staff : pages du panel hors joueurs, en menus natifs (tableau de bord, sanctions, logs, staff, météo,
-- serveur, events) ou ouvertes dans le panel (« Gestion » : éditeurs avec formulaires et cartes). Chaque entrée n'apparaît
-- qu'avec sa permission ; chaque action passe par l'action du panel correspondante, revérifiée par le serveur.
-- ctx (client/quickmenu.lua) : can, ask, run, input, reasonRows, closeQuick, back, open.

local function panelState()
    return lib.callback.await('lunatic_admin:open', false) or {}
end

---------------------------------------------------------------------
-- Tableau de bord
---------------------------------------------------------------------

local function dashboardMenu(ctx)
    return function()
        local d = panelState().dashboard or {}
        local items = {
            { label = 'Joueurs en ligne', right = ('%d / %d'):format(d.players or 0, d.maxPlayers or 0), info = true },
        }

        if d.staff then
            items[#items + 1] = { label = 'Staff en ligne', right = tostring(#d.staff), info = true }

            for _, member in ipairs(d.staff) do
                items[#items + 1] = { label = ('   %d · %s'):format(member.serverId, member.name), right = member.rank and member.rank.name or nil, info = true }
            end
        end

        if d.sanctions then
            items[#items + 1] = { label = 'Bans actifs', right = tostring(d.sanctions.activeBans or 0), info = true }
            items[#items + 1] = { label = 'Bans (24 h)', right = tostring(d.sanctions.bans24h or 0), info = true }
            items[#items + 1] = { label = 'Warns (24 h)', right = tostring(d.sanctions.warns24h or 0), info = true }
        end

        return { title = 'Tableau de bord', items = items }
    end
end

---------------------------------------------------------------------
-- Sanctions récentes
---------------------------------------------------------------------

local SANCTION_TYPES = { warn = 'Warn', ban = 'Ban', jail = 'Prison', kick = 'Kick' }

local function sanctionsMenu(ctx, filter)
    return function()
        local result = ctx.ask('sanctions.list', filter or {})
        local items = {}

        if not filter then
            items[#items + 1] = { label = 'Seulement les actives', submenu = sanctionsMenu(ctx, { status = 'active' }) }
            items[#items + 1] = { label = 'Bans', submenu = sanctionsMenu(ctx, { type = 'ban' }) }
            items[#items + 1] = { label = 'Warns', submenu = sanctionsMenu(ctx, { type = 'warn' }) }
            items[#items + 1] = { label = 'Prisons', submenu = sanctionsMenu(ctx, { type = 'jail' }) }
            items[#items + 1] = { label = 'Rechercher…', onSelect = function()
                local values = ctx.input('Rechercher une sanction', { { type = 'input', label = 'Nom ou référence (#42)', required = true, min = 1, max = 60 } })
                if values then ctx.open(sanctionsMenu(ctx, { search = values[1] })) end
            end }
        end

        for _, s in ipairs(result and result.sanctions or {}) do
            local label = ('#%d · %s · %s'):format(s.id, SANCTION_TYPES[s.type] or s.type, s.name or '?')
            local revocable = s.active and s.canRevoke

            items[#items + 1] = { label = label, right = s.active and 'active' or (s.revoked and 'révoquée' or nil), info = not revocable,
                desc = ('%s · par %s%s'):format(s.reason or '', s.staff or '?', revocable and ' · Entrée : révoquer' or ''), onSelect = function()
                    local values = ctx.input(('Révoquer la sanction #%d'):format(s.id), ctx.reasonRows())
                    if values then ctx.run('sanction.revoke', { id = s.id, reason = values[1] }, 'Sanction révoquée.') end
                end }
        end

        if #items == 0 or (filter and #items == 0) then
            items[#items + 1] = { label = 'Aucune sanction', info = true }
        end

        return { title = filter and 'Sanctions' or 'Sanctions récentes', items = items }
    end
end

---------------------------------------------------------------------
-- Logs
---------------------------------------------------------------------

local LOG_CATEGORIES = {
    { 'all', 'Tous' }, { 'players', 'Joueurs' }, { 'economy', 'Économie' }, { 'inventory', 'Inventaire' }, { 'vehicles', 'Véhicules' },
    { 'staff', 'Staff' }, { 'companies', 'Sociétés' }, { 'illegal', 'Illégal' },
}

local function logsMenu(ctx)
    return function()
        local items = {}

        for _, category in ipairs(LOG_CATEGORIES) do
            items[#items + 1] = { label = category[2], submenu = function()
                local result = ctx.ask('logs.list', { category = category[1] ~= 'all' and category[1] or nil })
                local list = {}

                for _, log in ipairs(result and result.logs or {}) do
                    list[#list + 1] = { label = ('%s · %s'):format(log.actor or 'Système', log.action), right = log.target, info = true }

                    if #list >= 50 then
                        break
                    end
                end

                if #list == 0 then
                    list[1] = { label = 'Aucun log', info = true }
                end

                return { title = ('Logs · %s'):format(category[2]), items = list }
            end }
        end

        return { title = 'Logs', items = items }
    end
end

---------------------------------------------------------------------
-- Membres du staff : rang, retirer, ajouter
---------------------------------------------------------------------

local function memberMenu(ctx, member)
    return function()
        local state = panelState()
        local me = state.me or {}
        local items = { { label = member.online and ('En ligne · ID %d'):format(member.serverId) or 'Hors ligne', info = true } }

        if ctx.can('staff.manage') then
            items[#items + 1] = { label = 'Changer de rang', submenu = function()
                local ranks = {}

                for _, rank in ipairs(state.ranks or {}) do
                    if me.rank and (me.rank.owner or rank.level < me.rank.level) then
                        ranks[#ranks + 1] = { label = rank.name, right = tostring(rank.level), onSelect = function()
                            if ctx.run('staff.setRank', { license = member.license, rankId = rank.id }, ('%s est maintenant %s.'):format(member.name, rank.name)) then
                                ctx.back(2)
                            end
                        end }
                    end
                end

                return { title = 'Changer de rang', items = ranks }
            end }
            items[#items + 1] = { label = 'Retirer du staff', onSelect = function()
                local values = ctx.input(('Retirer %s du staff'):format(member.name), { { type = 'checkbox', label = 'Je confirme', required = true } })

                if values and values[1] and ctx.run('staff.remove', { license = member.license }, ('%s a été retiré du staff.'):format(member.name)) then
                    ctx.back(1)
                end
            end }
        end

        return { title = member.name, items = items }
    end
end

local function staffManageMenu(ctx)
    return function()
        local state = panelState()
        local ranks = {}

        for _, rank in ipairs(state.ranks or {}) do
            ranks[rank.id] = rank
        end

        local items = {}

        if ctx.can('staff.manage') then
            items[#items + 1] = { label = 'Ajouter un membre', submenu = function()
                local fresh = panelState()
                local me = fresh.me or {}
                local list = {}

                for _, candidate in ipairs(fresh.candidates or {}) do
                    list[#list + 1] = { label = ('%d · %s'):format(candidate.serverId, candidate.name), submenu = function()
                        local choices = {}

                        for _, rank in ipairs(fresh.ranks or {}) do
                            if me.rank and (me.rank.owner or rank.level < me.rank.level) then
                                choices[#choices + 1] = { label = rank.name, right = tostring(rank.level), onSelect = function()
                                    if ctx.run('staff.add', { serverId = candidate.serverId, rankId = rank.id }, 'Membre ajouté au staff.') then
                                        ctx.back(2)
                                    end
                                end }
                            end
                        end

                        return { title = ('Rang de %s'):format(candidate.name), items = choices }
                    end }
                end

                if #list == 0 then
                    list[1] = { label = 'Aucun joueur à ajouter', info = true }
                end

                return { title = 'Ajouter un membre', items = list }
            end }
        end

        table.sort(state.staff or {}, function(a, b) return (a.online and 1 or 0) > (b.online and 1 or 0) end)

        for _, member in ipairs(state.staff or {}) do
            local rank = ranks[member.rankId]
            items[#items + 1] = { label = member.name, right = ('%s%s'):format(rank and rank.name or '?', member.online and ' · en ligne' or ''), submenu = memberMenu(ctx, member) }
        end

        return { title = 'Membres du staff', items = items }
    end
end

---------------------------------------------------------------------
-- Météo et heure (lunatic_world)
---------------------------------------------------------------------

local function worldMenu(ctx)
    return function()
        local world = panelState().world or {}

        if not world.available then
            return { title = 'Météo et heure', items = { { label = 'lunatic_world ne tourne pas', info = true } } }
        end

        local items = {}

        if ctx.can('world.time') then
            items[#items + 1] = { label = 'Heure', right = ('%02d:%02d'):format(world.hour or 0, world.minute or 0), onSelect = function()
                local values = ctx.input("Régler l'heure", {
                    { type = 'number', label = 'Heure (0-23)', required = true, min = 0, max = 23, default = world.hour },
                    { type = 'number', label = 'Minute (0-59)', required = true, min = 0, max = 59, default = 0 },
                })
                if values then ctx.run('world.time', { hour = values[1], minute = values[2] }, ('Heure réglée sur %02d:%02d.'):format(values[1], values[2])) end
            end }
            items[#items + 1] = { label = "Figer l'heure", toggle = true, on = world.frozen, onSelect = function() ctx.run('world.freeze', { enabled = not world.frozen }, nil) end }
        end

        if ctx.can('world.weather') then
            items[#items + 1] = { label = 'Cycle météo automatique', toggle = true, on = world.cycle, onSelect = function() ctx.run('world.cycle', { enabled = not world.cycle }, nil) end }
            items[#items + 1] = { label = 'Panne de courant', toggle = true, on = world.blackout, onSelect = function() ctx.run('world.blackout', { enabled = not world.blackout }, nil) end }
            items[#items + 1] = { label = 'Météo', info = true }

            for _, weather in ipairs(world.weathers or {}) do
                items[#items + 1] = { label = weather.label, right = weather.id == world.weather and 'actuelle' or nil, onSelect = function()
                    if weather.id ~= world.weather then
                        ctx.run('world.weather', { weather = weather.id }, ('Météo : %s.'):format(weather.label))
                    end
                end }
            end
        end

        return { title = 'Météo et heure', items = items }
    end
end

---------------------------------------------------------------------
-- Serveur : annonces, redémarrage planifié, maintenance, actions de masse
---------------------------------------------------------------------

local function serverMenu(ctx)
    return function()
        local items = {}

        if ctx.can('chat.announce') then
            items[#items + 1] = { label = 'Annonce serveur', onSelect = function()
                local values = ctx.input('Annonce serveur', { { type = 'input', label = 'Message', required = true, min = 3, max = 200 } })
                if values then ExecuteCommand(('annonce %s'):format(values[1])) end
            end }
        end

        if ctx.can('chat.announce_mod') then
            items[#items + 1] = { label = 'Annonce Modération', onSelect = function()
                local values = ctx.input('Annonce Modération', { { type = 'input', label = 'Message', required = true, min = 3, max = 200 } })
                if values then ExecuteCommand(('annoncemodo %s'):format(values[1])) end
            end }
        end

        if ctx.can('server.manage') then
            items[#items + 1] = { label = 'Redémarrage planifié', onSelect = function()
                local values = ctx.input('Redémarrage planifié', {
                    { type = 'number', label = 'Dans combien de minutes', required = true, min = 1, default = 15 },
                    { type = 'input', label = 'Raison (facultative)', max = 100 },
                })
                if values then ctx.run('server.restart', { minutes = values[1], reason = values[2] or '' }, 'Redémarrage planifié.') end
            end }
            items[#items + 1] = { label = 'Annuler le redémarrage', onSelect = function() ctx.run('server.cancelRestart', {}, 'Redémarrage annulé.') end }
            items[#items + 1] = { label = 'Maintenance', desc = 'Activer : seuls les staff peuvent se connecter.', submenu = function()
                return { title = 'Maintenance', items = {
                    { label = 'Activer', onSelect = function()
                        local values = ctx.input('Maintenance', { { type = 'input', label = 'Message affiché aux joueurs', min = 5, max = 200 } })
                        if values then ctx.run('server.maintenance', { enabled = true, message = values[1] ~= '' and values[1] or nil }, 'Maintenance activée.') end
                    end },
                    { label = 'Désactiver', onSelect = function() ctx.run('server.maintenance', { enabled = false }, 'Maintenance désactivée.') end },
                } }
            end }
            items[#items + 1] = { label = 'Soigner tout le monde', onSelect = function() ctx.run('server.healAll', {}, 'Tous les joueurs sont soignés.') end }
            items[#items + 1] = { label = 'Ramener tout le monde', onSelect = function() ctx.run('server.bringAll', {}, 'Tous les joueurs sont ramenés.') end }
            items[#items + 1] = { label = 'Expulser tout le monde', onSelect = function()
                local values = ctx.input('Expulser tout le monde', ctx.reasonRows())
                if values then ctx.run('server.kickAll', { reason = values[1] }, 'Joueurs expulsés.') end
            end }
        end

        if #items == 0 then
            items[1] = { label = 'Aucune permission ici', info = true }
        end

        return { title = 'Serveur', items = items }
    end
end

---------------------------------------------------------------------
-- Events
---------------------------------------------------------------------

local function eventsMenu(ctx)
    return function()
        local result = ctx.ask('events.list', {})
        local items = {}

        for _, event in ipairs(result and result.events or {}) do
            local cancelled = event.status == 'cancelled'
            items[#items + 1] = { label = event.title or ('Event #%d'):format(event.id), right = cancelled and 'annulé' or nil, desc = event.description ~= '' and event.description or nil, submenu = function()
                local list = { { label = event.place ~= '' and ('Lieu : %s'):format(event.place) or 'Lieu non précisé', info = true } }

                if not cancelled then
                    list[#list + 1] = { label = "Annuler l'event", onSelect = function()
                        if ctx.run('events.cancel', { id = event.id }, 'Event annulé.') then
                            ctx.back(1)
                        end
                    end }
                end

                list[#list + 1] = { label = 'Modifier dans le panel', onSelect = function() ctx.closeQuick() OpenPanelOn('events') end }
                return { title = event.title or 'Event', items = list }
            end }
        end

        items[#items + 1] = { label = 'Créer un event dans le panel', onSelect = function() ctx.closeQuick() OpenPanelOn('events') end }
        return { title = 'Events', items = items }
    end
end

---------------------------------------------------------------------
-- Gestion : pages du panel (éditeurs) ouvertes directement
---------------------------------------------------------------------

local PANEL_PAGES = {
    { 'companies', 'Entreprises', 'companies.manage' }, { 'publics', 'Services publics', 'publics.manage' },
    { 'crews', 'Crews', 'crews.manage' }, { 'illegal', 'Illégal', 'illegal.manage' }, { 'catalogs', 'Catalogues', 'catalogs.manage' },
    { 'items', 'Items', 'items.manage' }, { 'blips', 'Blips', 'blips.manage' }, { 'economy', 'Économie', 'economy.manage' },
    { 'shop', 'Boutique', 'shop.manage' }, { 'poles', 'Pôle emploi', 'poles.manage' }, { 'images', 'Images', 'images.manage' },
    { 'interactions', 'Interactions', 'interactions.manage' }, { 'features', 'Fonctionnalités', 'features.manage' },
    { 'others', 'Autres', 'others.manage' }, { 'ranks', 'Rangs et permissions', 'ranks.view' },
}

local function gestionMenu(ctx)
    return function()
        local items = {}

        for _, page in ipairs(PANEL_PAGES) do
            if ctx.can(page[3]) then
                items[#items + 1] = { label = page[2], desc = 'Ouvre cette page du panel.', onSelect = function() ctx.closeQuick() OpenPanelOn(page[1]) end }
            end
        end

        items[#items + 1] = { label = 'Panel complet', onSelect = function() ctx.closeQuick() OpenPanelOn('home') end }
        return { title = 'Gestion', items = items }
    end
end

---------------------------------------------------------------------
-- Entrées de l'accueil du menu rapide, selon les permissions
---------------------------------------------------------------------

function QuickPageEntries(ctx)
    local items = {}
    local add = function(show, label, submenu, desc)
        if show then
            items[#items + 1] = { label = label, submenu = submenu, desc = desc }
        end
    end

    add(true, 'Tableau de bord', dashboardMenu(ctx), 'Joueurs et staff en ligne, sanctions du jour.')
    add(ctx.can('sanctions.view'), 'Sanctions', sanctionsMenu(ctx, nil), 'Dernières sanctions, révocation.')
    add(ctx.can('logs.view'), 'Logs', logsMenu(ctx), 'Derniers logs par catégorie.')
    add(ctx.can('staff.view'), 'Membres du staff', staffManageMenu(ctx), 'Rangs, retrait et ajout de membres.')
    add(ctx.can('world.weather') or ctx.can('world.time'), 'Météo et heure', worldMenu(ctx))
    add(ctx.can('server.manage') or ctx.can('chat.announce') or ctx.can('chat.announce_mod'), 'Serveur', serverMenu(ctx), 'Annonces, redémarrage, maintenance, actions de masse.')
    add(ctx.can('events.manage'), 'Events', eventsMenu(ctx))
    add(true, 'Gestion', gestionMenu(ctx), 'Pages du panel : entreprises, catalogues, items, économie…')
    return items
end
