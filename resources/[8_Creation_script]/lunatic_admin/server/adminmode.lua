-- Mode administration (menu admin, doc Vision) : le staff le met quand il est en service, l'enlève quand il joue en RP.
-- Activé : alertes de reports (server/reports.lua) et noms / ID au-dessus des têtes (avec la permission Noms et ID).
-- Coupé à la déconnexion. Bascule depuis le menu rapide (F9), la page Reports du panel ou la commande /modeadmin.

AdminMode = {}

local on = {} -- membre du staff -> true

function AdminMode.isOn(src)
    return on[src] == true
end

function AdminMode.count()
    local count = 0

    for _ in pairs(on) do
        count = count + 1
    end

    return count
end

local function set(src, enabled)
    on[src] = enabled or nil

    -- Noms et ID au-dessus des têtes : suivent le mode
    if Staff.can(src, 'tools.names') then
        Panel.setToolMode(src, 'names', enabled)
    end

    Logs.add(src, enabled and 'adminmode.on' or 'adminmode.off', nil, nil)
    Panel.notify(src, enabled and 'Mode administration activé : alertes de reports et noms au-dessus des têtes.'
        or 'Mode administration désactivé : plus aucune alerte de report.', enabled and 'success' or 'info')
end

-- enabled absent : bascule
Panel.actions['adminmode.toggle'] = function(src, _, data)
    local enabled

    if data.enabled == nil then
        enabled = not on[src]
    else
        enabled = data.enabled == true
    end

    set(src, enabled)
    return { ok = true, adminMode = enabled }
end

table.insert(Panel.stateHooks, function(state, src)
    state.me.adminMode = on[src] == true
    state.adminModeCount = AdminMode.count()
end)

AddEventHandler('playerDropped', function()
    on[source] = nil
end)
