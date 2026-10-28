-- Menu rapide du staff (client/quickmenu.lua) : données des sous-menus. Les actions passent par les actions du panel
-- (lunatic_admin:action), qui revérifient permissions et protections de rang comme depuis le panel.

local TOOLS = { 'tools.noclip', 'tools.invisible', 'tools.godmode', 'tools.ghost', 'tools.names', 'tools.coords', 'tools.tpm', 'tools.vehicles' }

-- Accueil du menu : chiffres du moment, droits du membre, outils actifs
lib.callback.register('lunatic_admin:quick', function(src)
    local rank = Staff.rankOf(src)

    if not Ranks.hasPermission(rank, 'panel.open') then
        return false
    end

    local tools = false

    for _, permission in ipairs(TOOLS) do
        tools = tools or Ranks.hasPermission(rank, permission)
    end

    return {
        name = Staff.displayName(src), adminMode = AdminMode.isOn(src), online = #GetPlayers(), staff = AdminMode.count(),
        reports = Reports.pendingCount(), permissions = Ranks.permissionList(rank), tools = tools, modes = Panel.toolModesOf(src),
    }
end)

-- Listes des sous-menus : players (joueurs connectés), staff (membres connectés), reports (en cours)
lib.callback.register('lunatic_admin:quickList', function(src, kind)
    local rank = Staff.rankOf(src)

    if not Ranks.hasPermission(rank, 'panel.open') then
        return false
    end

    local list = {}

    if kind == 'players' and Ranks.hasPermission(rank, 'players.view') then
        for _, id in ipairs(GetPlayers()) do
            local target = tonumber(id)
            local staffRank = Staff.rankOf(target)
            list[#list + 1] = { id = target, name = Staff.displayName(target), rank = staffRank and staffRank.name or nil }
        end

        table.sort(list, function(a, b) return a.id < b.id end)
    elseif kind == 'staff' and (Ranks.hasPermission(rank, 'staff.view') or Ranks.hasPermission(rank, 'staff.online')) then
        for _, id in ipairs(GetPlayers()) do
            local target = tonumber(id)
            local staffRank = Staff.rankOf(target)

            if staffRank then
                list[#list + 1] = { id = target, name = Staff.displayName(target), rank = staffRank.name, level = staffRank.level, adminMode = AdminMode.isOn(target) }
            end
        end

        table.sort(list, function(a, b) return a.level > b.level end)
    elseif kind == 'reports' and Ranks.hasPermission(rank, 'reports.manage') then
        list = Reports.activeList()
    end

    return list
end)
