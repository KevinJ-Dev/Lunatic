-- Menu rapide du staff (menu admin, doc Vision) : une touche (F9 par défaut, réglable dans les touches de FiveM) ouvre
-- « Administration » à gauche. Le personnage reste libre de ses mouvements : le menu se pilote au clavier
-- (flèches haut / bas, Entrée, Retour arrière pour revenir, F9 pour fermer), la page ne fait qu'afficher.
-- Sous-menus : mode administration, reports, joueurs, staff, joueurs hors ligne, outils ; « Gestion » ouvre le panel.
-- Chaque action passe par les actions du panel (lunatic_admin:action) : le serveur revérifie tout.

local CONTROLS = { up = 172, down = 173, select = 201, back = 177 }
local BLOCKED = { 172, 173, 174, 175, 176, 177, 191, 194, 199, 200, 201, 202, 27 } -- flèches, Entrée, retour, téléphone, pause

local stack = nil   -- menus ouverts, le dernier est affiché
local summary = nil -- accueil : chiffres, droits, outils actifs
local busy = false  -- saisie ou attente du serveur en cours

local function can(permission)
    for _, entry in ipairs(summary and summary.permissions or {}) do
        if entry == permission then
            return true
        end
    end

    return false
end

local function ask(action, payload)
    return lib.callback.await('lunatic_admin:action', false, action, payload or {})
end

-- Action du panel : erreur ou message de réussite en notification
local function run(action, payload, okMessage)
    local result = ask(action, payload)

    if not result or not result.ok then
        ESX.ShowNotification(result and result.error or 'Action impossible.', 'error')
        return nil
    end

    if okMessage then
        ESX.ShowNotification(okMessage, 'success')
    end

    return result
end

-- Saisie (raison, montant, durée…) : fenêtre aux couleurs du menu rapide (web/quick.js), mêmes champs que
-- lib.inputDialog (input, number, select, checkbox). Renvoie la liste des valeurs, ou nil si annulée.
local dialog = nil

local function input(title, rows)
    busy = true
    dialog = promise.new()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'quickInput', title = title, rows = rows })
    local values = Citizen.Await(dialog)
    dialog = nil
    SetNuiFocus(false, false)
    busy = false
    return values
end

RegisterNUICallback('quickInputDone', function(data, cb)
    cb({})

    if dialog then
        dialog:resolve(type(data.values) == 'table' and data.values or nil)
    end
end)

---------------------------------------------------------------------
-- Affichage
---------------------------------------------------------------------

local function current()
    return stack and stack[#stack]
end

local function paint()
    local menu = current()

    if not menu then
        return
    end

    local items = {}

    for _, item in ipairs(menu.items) do
        items[#items + 1] = { label = item.label, right = item.right, toggle = item.toggle, on = item.on, disabled = item.disabled, info = item.info }
    end

    -- Fiche du joueur affichée à côté seulement sur l'entrée « Fiche du joueur »
    local selected = menu.items[menu.index]
    local sheet = selected and selected.sheet or nil
    SendNUIMessage({
        action = 'quick', data = {
            title = 'Administration', subtitle = menu.title, items = items, index = menu.index, desc = selected and selected.desc or menu.desc,
            stats = summary and { online = summary.online, staff = summary.staff, reports = summary.reports } or nil, depth = #stack, sheet = sheet,
        },
    })
end

local function closeQuick()
    if not stack then
        return
    end

    stack = nil
    SendNUIMessage({ action = 'quickClose' })

    -- Saisie en cours : annulée
    if dialog then
        dialog:resolve(nil)
    end
end

local function push(menu)
    menu.index = menu.index or 1

    -- Première entrée utilisable
    while menu.items[menu.index] and (menu.items[menu.index].disabled or menu.items[menu.index].info) and menu.index < #menu.items do
        menu.index = menu.index + 1
    end

    stack[#stack + 1] = menu
    paint()
end

-- Menu à recalculer (après une action) sans changer la position
local function refresh()
    local menu = current()

    if menu and menu.build then
        local index = menu.index
        local fresh = menu.build()

        if fresh then
            menu.items, menu.title, menu.desc, menu.sheet = fresh.items, fresh.title, fresh.desc, fresh.sheet
            menu.index = math.min(index, math.max(1, #menu.items))
        end
    end

    paint()
end

local function open(build)
    local menu = build()

    if menu then
        menu.build = build
        push(menu)
    end
end

---------------------------------------------------------------------
-- Sous-menus
---------------------------------------------------------------------

local playerMenu, reportMenu

local function reasonRows(extra)
    local rows = extra or {}
    rows[#rows + 1] = { type = 'input', label = 'Raison', required = true, min = 3, max = 200 }
    return rows
end

-- Menus d'un joueur (client/quickplayer.lua) : outils du menu rapide partagés
local ctx = {
    can = can, ask = ask, run = run, input = input, reasonRows = reasonRows,
    open = function(build) open(build) end,
    closeQuick = function() closeQuick() end,
    -- Revenir de n menus en arrière (ex. après le choix d'un métier)
    back = function(count)
        for _ = 1, count or 1 do
            if stack and #stack > 1 then
                table.remove(stack)
            end
        end
    end,
}

playerMenu = function(player)
    return QuickPlayerMenu(player, ctx)
end

local function playersMenu()
    local list = lib.callback.await('lunatic_admin:quickList', false, 'players') or {}
    local items = {}

    for _, player in ipairs(list) do
        items[#items + 1] = { label = ('%d · %s'):format(player.id, player.name), right = player.rank or player.pseudo, submenu = playerMenu(player) }
    end

    if #items == 0 then
        items[1] = { label = 'Aucun joueur connecté', info = true }
    end

    return { title = ('Joueurs (%d)'):format(#list), items = items }
end

local function staffMenu()
    local list = lib.callback.await('lunatic_admin:quickList', false, 'staff') or {}
    local items = {}

    for _, member in ipairs(list) do
        items[#items + 1] = {
            label = ('%d · %s'):format(member.id, member.name), right = member.adminMode and ('%s · en service'):format(member.rank) or member.rank,
            submenu = playerMenu(member),
        }
    end

    if #items == 0 then
        items[1] = { label = 'Aucun membre connecté', info = true }
    end

    return { title = ('Staff en ligne (%d)'):format(#list), items = items }
end

local STATUS = { open = 'en attente', taken = 'pris en charge' }

reportMenu = function(id)
    return function()
        local report

        for _, entry in ipairs(lib.callback.await('lunatic_admin:quickList', false, 'reports') or {}) do
            if entry.id == id then
                report = entry
            end
        end

        if not report then
            return { title = ('Report #%d'):format(id), items = { { label = 'Report fermé ou introuvable', info = true } } }
        end

        local payload = { id = report.id }
        local items = {}

        if report.status == 'open' then
            items[#items + 1] = { label = 'Prendre en charge', onSelect = function() run('reports.take', payload, ('Report #%d pris en charge.'):format(report.id)) end }
        end

        items[#items + 1] = { label = 'Répondre au joueur', desc = 'Il reçoit le message dans le tchat et répond avec /report.', onSelect = function()
            local values = input(('Report #%d : répondre'):format(report.id), { { type = 'input', label = 'Message', required = true, min = 1, max = 300 } })
            if values then run('reports.message', { id = report.id, text = values[1] }, 'Message envoyé.') end
        end }

        if #report.messages > 0 then
            local messages = {}

            for _, message in ipairs(report.messages) do
                messages[#messages + 1] = { label = ('%s : %s'):format(message.name, message.text), info = true }
            end

            items[#items + 1] = { label = 'Discussion', right = tostring(#report.messages), submenu = function() return { title = ('Report #%d · discussion'):format(report.id), items = messages } end }
        end

        items[#items + 1] = { label = 'Aller vers le joueur', disabled = not report.online, onSelect = function() run('reports.goto', payload, nil) end }
        items[#items + 1] = { label = 'Ramener le joueur', disabled = not report.online, onSelect = function() run('reports.bring', payload, 'Joueur ramené.') end }
        items[#items + 1] = { label = 'Fermer le report', onSelect = function()
            local values = input(('Fermer le report #%d'):format(report.id), { { type = 'input', label = 'Réponse au joueur (facultative)', max = 300 } })

            if values and run('reports.close', { id = report.id, answer = values[1] or '' }, ('Report #%d fermé.'):format(report.id)) then
                table.remove(stack)
            end
        end }

        return { title = ('Report #%d · %s'):format(report.id, report.name), desc = report.message, items = items }
    end
end

local function reportsMenu()
    local list = lib.callback.await('lunatic_admin:quickList', false, 'reports') or {}
    local items = {}

    for _, report in ipairs(list) do
        items[#items + 1] = {
            label = ('#%d · %s'):format(report.id, report.name), right = report.status == 'taken' and report.staff or STATUS[report.status],
            desc = report.message, submenu = reportMenu(report.id),
        }
    end

    if #items == 0 then
        items[1] = { label = 'Aucun report en cours', info = true }
    end

    return { title = ('Reports (%d)'):format(#list), items = items }
end

-- Joueurs hors ligne : recherche (nom RP ou licence), puis le menu du joueur (client/quickplayer.lua)
local function offlineMenu(query)
    return function()
        local result = ask('offline.search', { query = query })
        local items = {}

        for _, player in ipairs(result and result.players or {}) do
            items[#items + 1] = { label = player.name, right = player.online and ('en ligne · %d'):format(player.online) or nil, submenu = QuickOfflineMenu(player.identifier, ctx) }
        end

        if #items == 0 then
            items[1] = { label = 'Aucun joueur trouvé', info = true }
        end

        return { title = ('Recherche : %s'):format(query), items = items }
    end
end

local TOOL_LABELS = {
    { 'noclip', 'Noclip' }, { 'invisible', 'Invisible' }, { 'godmode', 'Invincible' }, { 'ghost', 'Mode fantôme' },
    { 'names', 'Noms et ID' }, { 'coords', 'Coordonnées' },
}

local function toolsMenu()
    local modes = summary.modes or {}
    local items = {}

    for _, entry in ipairs(TOOL_LABELS) do
        local mode, label = entry[1], entry[2]

        if can('tools.' .. mode) then
            items[#items + 1] = { label = label, toggle = true, on = modes[mode] == true, onSelect = function()
                local result = run('tool.toggle', { tool = mode, enabled = not modes[mode] }, nil)

                if result and result.tools then
                    summary.modes = result.tools
                end
            end }
        end
    end

    if can('tools.tpm') then
        items[#items + 1] = { label = 'TP au marqueur', onSelect = function() run('tool.tpm', {}, nil) end }
    end

    if can('tools.vehicles') then
        items[#items + 1] = { label = 'Réparer mon véhicule', onSelect = function() run('vehicle.repair', {}, 'Véhicule réparé.') end }
        items[#items + 1] = { label = 'Retourner mon véhicule', onSelect = function() run('vehicle.flip', {}, nil) end }
        items[#items + 1] = { label = 'Supprimer mon véhicule', onSelect = function() run('vehicle.delete', { radius = 0 }, 'Véhicule supprimé.') end }
    end

    return { title = 'Outils de modération', items = items }
end

local function rootMenu()
    summary = lib.callback.await('lunatic_admin:quick', false) or summary
    local items = {
        { label = 'Mode administration', toggle = true, on = summary.adminMode, desc = 'Alertes de reports et noms au-dessus des têtes.', onSelect = function()
            run('adminmode.toggle', {}, nil)
        end },
    }

    if can('reports.manage') then
        items[#items + 1] = { label = 'Liste des reports', right = summary.reports > 0 and tostring(summary.reports) or nil, submenu = reportsMenu }
    end

    if can('players.view') then
        items[#items + 1] = { label = 'Liste des joueurs', right = tostring(summary.online), submenu = playersMenu }
    end

    if can('staff.view') or can('staff.online') then
        items[#items + 1] = { label = 'Liste des modérateurs et staff', submenu = staffMenu }
    end

    if can('players.offline') then
        items[#items + 1] = { label = 'Joueurs hors ligne', desc = 'Recherche par nom RP ou licence.', onSelect = function()
            local values = input('Joueurs hors ligne', { { type = 'input', label = 'Nom RP ou licence', required = true, min = 2, max = 60 } })
            if values then open(offlineMenu(values[1])) end
        end }
    end

    if can('players.offline') or can('sanctions.view') then
        items[#items + 1] = { label = 'Joueurs bannis', submenu = QuickBannedMenu(ctx) }
    end

    if summary.tools then
        items[#items + 1] = { label = 'Outils de modération', submenu = toolsMenu }
    end

    -- Pages du panel hors joueurs (client/quickpages.lua), selon les permissions
    for _, entry in ipairs(QuickPageEntries(ctx)) do
        items[#items + 1] = entry
    end

    return { title = summary.name, items = items }
end

---------------------------------------------------------------------
-- Clavier (le personnage reste libre : seules les touches du menu sont bloquées)
---------------------------------------------------------------------

local function choose()
    local menu = current()
    local item = menu and menu.items[menu.index]

    if not item or item.disabled or item.info then
        return
    end

    busy = true

    if item.submenu then
        open(item.submenu)
    elseif item.onSelect then
        item.onSelect()

        if stack then
            refresh()
        end
    end

    busy = false
end

local function move(step)
    local menu = current()

    if not menu or #menu.items == 0 then
        return
    end

    for _ = 1, #menu.items do
        menu.index = (menu.index - 1 + step) % #menu.items + 1

        if not menu.items[menu.index].info then
            break
        end
    end

    paint()
end

local function inputLoop()
    CreateThread(function()
        local repeatAt = 0

        while stack do
            for _, control in ipairs(BLOCKED) do
                DisableControlAction(0, control, true)
            end

            if not busy and not IsPauseMenuActive() then
                local now = GetGameTimer()
                local up, down = IsDisabledControlPressed(0, CONTROLS.up), IsDisabledControlPressed(0, CONTROLS.down)

                -- Flèche maintenue : défile après un court délai
                if IsDisabledControlJustPressed(0, CONTROLS.up) or IsDisabledControlJustPressed(0, CONTROLS.down) then
                    move(up and -1 or 1)
                    repeatAt = now + 350
                elseif (up or down) and now >= repeatAt then
                    move(up and -1 or 1)
                    repeatAt = now + 90
                elseif IsDisabledControlJustPressed(0, CONTROLS.select) then
                    CreateThread(choose)
                elseif IsDisabledControlJustPressed(0, CONTROLS.back) then
                    if #stack > 1 then
                        table.remove(stack)
                        refresh()
                    else
                        closeQuick()
                    end
                end
            end

            Wait(0)
        end
    end)
end

RegisterCommand('staffmenu', function()
    if IsPanelOpen() then
        return
    end

    if stack then
        return closeQuick()
    end

    CreateThread(function()
        summary = lib.callback.await('lunatic_admin:quick', false)

        if not summary then
            return ESX.ShowNotification("Vous n'avez pas accès au menu staff.", 'error')
        end

        stack = {}
        open(rootMenu)
        inputLoop()
    end)
end, false)
RegisterKeyMapping('staffmenu', 'Staff : menu rapide (administration)', 'keyboard', Config.QuickMenuKey)

-- Le panel s'ouvre : le menu rapide se ferme
AddEventHandler('lunatic_admin:closeQuick', closeQuick)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        closeQuick()
    end
end)
