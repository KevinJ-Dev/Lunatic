-- Anti-AFK : le client signale l'inactivité, le serveur expulse (le staff n'est jamais expulsé).

RegisterNetEvent('lunatic_gameplay:afk', function()
    local src = source

    if not FeaturesOf('misc').afk then
        return
    end

    if GetResourceState('lunatic_admin') == 'started' then
        local ok, rank = pcall(function() return exports.lunatic_admin:getRank(src) end)

        if ok and rank then
            return
        end
    end

    -- Zone AFK avec « envoyer les inactifs » : le joueur y part au lieu d'être expulsé
    local zone = GlobalState.lunaticAfkZone

    if type(zone) == 'table' and zone.enabled and zone.autoSend and SendToAfk and not IsPlayerDown(src) and SendToAfk(src) then
        return
    end

    DropPlayer(src, 'Expulsé pour inactivité (AFK).')
end)
