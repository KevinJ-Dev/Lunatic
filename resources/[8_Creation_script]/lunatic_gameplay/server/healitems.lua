-- Objets de soin (panel : tuile Autres → Heal Items EMS, GlobalState.lunaticHealItems).
-- Chaque objet réglé devient utilisable ; le serveur vérifie l'accès, la distance, l'objet et l'état de la cible.

local ox = exports.ox_inventory
local registered = {}

local function settingsOf(item)
    for _, entry in ipairs(GlobalState.lunaticHealItems or {}) do
        if entry.item == item then
            return entry
        end
    end
end

local function hasAccess(xPlayer, entry)
    if entry.access == 'all' then
        return true
    end

    if entry.access == 'medic' then
        return IsMedic(xPlayer)
    end

    return xPlayer.getJob().name == entry.access
end

-- Les objets réglés dans le panel deviennent utilisables (un objet retiré du panel ne fait plus rien)
local function registerItems(list)
    for _, entry in ipairs(type(list) == 'table' and list or {}) do
        if not registered[entry.item] then
            registered[entry.item] = true
            ESX.RegisterUsableItem(entry.item, function(src)
                local settings = settingsOf(entry.item)

                if settings then
                    TriggerClientEvent('lunatic_gameplay:useHealItem', src, settings)
                end
            end)
        end
    end
end

AddStateBagChangeHandler('lunaticHealItems', 'global', function(_, _, value)
    registerItems(value)
end)

CreateThread(function()
    registerItems(GlobalState.lunaticHealItems)
end)

lib.callback.register('lunatic_gameplay:healFinish', function(src, item, targetId)
    local settings = settingsOf(item)
    local xPlayer = ESX.GetPlayerFromId(src)
    targetId = tonumber(targetId) or src

    if not settings or not xPlayer then
        return { ok = false, error = "Cet objet ne soigne plus." }
    end

    if not hasAccess(xPlayer, settings) then
        return { ok = false, error = 'Vous ne savez pas utiliser cet objet.' }
    end

    if (targetId == src and settings.target == 'other') or (targetId ~= src and settings.target == 'self') then
        return { ok = false, error = 'Cible impossible pour cet objet.' }
    end

    if targetId ~= src then
        local me, other = GetPlayerPed(src), GetPlayerPed(targetId)

        if me == 0 or other == 0 or #(GetEntityCoords(me) - GetEntityCoords(other)) > 4.0 then
            return { ok = false, error = 'Rapprochez-vous de la personne.' }
        end
    end

    if (ox:Search(src, 'count', item) or 0) < 1 then
        return { ok = false, error = "Vous n'avez plus cet objet." }
    end

    local down = IsPlayerDown(targetId)

    if down and not settings.revive then
        return { ok = false, error = 'La personne est inconsciente : il faut un objet de réanimation.' }
    end

    if settings.consume then
        ox:RemoveItem(src, item, 1)
    end

    if down then
        RevivePlayer(targetId, src)
    end

    TriggerClientEvent('lunatic_gameplay:healApply', targetId, settings.heal, settings.armor)

    if targetId ~= src then
        GameLog('players', 'info', src, 'player.healItem', GetPlayerName(targetId), { item = item, revive = down })
    end

    return { ok = true, revived = down }
end)
