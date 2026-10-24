-- Carte d'identité : objet utilisable (regarder, montrer à la personne la plus proche), remise à la connexion si
-- le joueur n'en a pas (réglable). Identité ESX, photo de la tuile Images (mugshot), modèle choisi dans le panel.

local ox = exports.ox_inventory

local function identityOf(xPlayer)
    local mugshot

    if GetResourceState('lunatic_admin') == 'started' then
        local ok, image = pcall(function() return exports.lunatic_admin:getMugshot(xPlayer.identifier) end)
        mugshot = ok and image or nil
    end

    local name = xPlayer.getName() or ''
    local first, last = xPlayer.get('firstName'), xPlayer.get('lastName')

    return {
        firstName = first or name:match('^(%S+)') or '', lastName = last or name:match('%s(.+)$') or '',
        dateofbirth = xPlayer.get('dateofbirth') or '', sex = xPlayer.get('sex') or '', height = xPlayer.get('height') or '',
        number = ('%09d'):format(tonumber(xPlayer.identifier:sub(1, 7), 16) or 0):sub(1, 9),
        model = FeaturesOf('idcard').model or 'fr', photo = mugshot,
    }
end

local function hasCard(src)
    return (ox:Search(src, 'count', Config.IdCardItem) or 0) > 0
end

ESX.RegisterUsableItem(Config.IdCardItem, function(source)
    TriggerClientEvent('lunatic_gameplay:idcardMenu', source)
end)

lib.callback.register('lunatic_gameplay:idcard', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not hasCard(src) then
        return nil
    end

    return identityOf(xPlayer)
end)

RegisterNetEvent('lunatic_gameplay:idcardShow', function(targetId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    targetId = tonumber(targetId)

    if not xPlayer or not targetId or not GetPlayerName(targetId) or not hasCard(src) then
        return
    end

    local me, target = GetPlayerPed(src), GetPlayerPed(targetId)

    if me == 0 or target == 0 or #(GetEntityCoords(me) - GetEntityCoords(target)) > Config.IdCardShowDistance + 1.0 then
        return Notify(src, 'Personne à côté de vous.', 'error')
    end

    TriggerClientEvent('lunatic_gameplay:idcardDisplay', targetId, identityOf(xPlayer))
    Notify(src, "Vous montrez votre carte d'identité.", 'info')
end)

-- Carte remise à la connexion si le joueur n'en a pas (identité créée)
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    SetTimeout(5000, function()
        if FeaturesOf('idcard').autoGive == false or not GetPlayerName(playerId) then
            return
        end

        local current = ESX.GetPlayerFromId(playerId)

        if current and current.get('firstName') and not hasCard(playerId) then
            ox:AddItem(playerId, Config.IdCardItem, 1)
        end
    end)
end)
