local ESX = exports['es_extended']:getSharedObject()

ESX.RegisterServerCallback('novyra_spawn:getInfo', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)

    cb({
        name       = xPlayer and xPlayer.getName() or GetPlayerName(source),
        players    = #GetPlayers(),
        maxPlayers = Config.MaxPlayers or GetConvarInt('sv_maxclients', 48),
    })
end)
