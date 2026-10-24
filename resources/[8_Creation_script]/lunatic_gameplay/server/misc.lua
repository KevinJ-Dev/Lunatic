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

    DropPlayer(src, 'Expulsé pour inactivité (AFK).')
end)
