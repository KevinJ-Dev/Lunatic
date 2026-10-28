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

-- Nom RP (prénom nom) d'un joueur connecté, sinon le nom affiché par le panel
local function rpNameOf(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    local first, last = xPlayer and xPlayer.get('firstName'), xPlayer and xPlayer.get('lastName')

    if type(first) == 'string' and first ~= '' and type(last) == 'string' and last ~= '' then
        return ('%s %s'):format(first, last)
    end

    return xPlayer and xPlayer.getName() or Staff.displayName(src)
end

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
            list[#list + 1] = { id = target, name = rpNameOf(target), pseudo = GetPlayerName(target), rank = staffRank and staffRank.name or nil }
        end

        table.sort(list, function(a, b) return a.id < b.id end)
    elseif kind == 'staff' and (Ranks.hasPermission(rank, 'staff.view') or Ranks.hasPermission(rank, 'staff.online')) then
        for _, id in ipairs(GetPlayers()) do
            local target = tonumber(id)
            local staffRank = Staff.rankOf(target)

            if staffRank then
                list[#list + 1] = { id = target, name = rpNameOf(target), rank = staffRank.name, level = staffRank.level, adminMode = AdminMode.isOn(target) }
            end
        end

        table.sort(list, function(a, b) return a.level > b.level end)
    elseif kind == 'reports' and Ranks.hasPermission(rank, 'reports.manage') then
        list = Reports.activeList()
    end

    return list
end)
