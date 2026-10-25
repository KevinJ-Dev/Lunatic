-- Lot L : commandes staff qui n'existaient pas encore (le reste se fait déjà depuis le panel).
-- Crash Player (/crash), Give un véhicule (/givecar), inventaire d'un joueur (/inv).
-- Chaque commande passe par la même action que le panel : mêmes permissions, mêmes contrôles, mêmes logs.

local ox = exports.ox_inventory

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

-- Joueur connecté, éventuellement interdit sur soi-même et protégé si son rang est égal ou supérieur
---@return number|nil target, table|nil error
local function targetOf(src, actor, data, options)
    local target = tonumber(data.serverId)

    if not target or not GetPlayerName(target) then
        return nil, Panel.fail("Ce joueur n'est pas connecté.")
    end

    if options.notSelf and target == src then
        return nil, Panel.fail('Action impossible sur vous-même.')
    end

    if options.protect and target ~= src then
        local rank = Staff.rankOf(target)

        if rank and rank.level >= actor.level then
            return nil, Panel.fail('Ce membre du staff a un rang égal ou supérieur au vôtre.')
        end
    end

    return target
end

---------------------------------------------------------------------
-- Crash Player : déconnexion sans raison affichée
---------------------------------------------------------------------

Panel.actions['player.crash'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'players.crash') then
        return denied()
    end

    local target, err = targetOf(src, actor, data, { notSelf = true, protect = true })

    if not target then
        return err
    end

    local name = Staff.displayName(target)
    Logs.add(src, 'player.crash', name, { serverId = target, license = GetPlayerIdentifierByType(target, 'license') })
    DropPlayer(target, Config.CrashMessage)

    return { ok = true, name = name }
end

---------------------------------------------------------------------
-- Give un véhicule : ajouté au garage du joueur (table owned_vehicles d'ESX)
---------------------------------------------------------------------

local PLATE_LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ'

-- Plaque libre de 8 caractères : 3 lettres, un espace, 4 chiffres
local function newPlate()
    for _ = 1, 20 do
        local letters = ''

        for _ = 1, 3 do
            local i = math.random(1, #PLATE_LETTERS)
            letters = letters .. PLATE_LETTERS:sub(i, i)
        end

        local plate = ('%s %04d'):format(letters, math.random(0, 9999))
        local used = MySQL.scalar.await('SELECT COUNT(*) FROM `owned_vehicles` WHERE `plate` = ?', { plate })

        if (tonumber(used) or 0) == 0 then
            return plate
        end
    end
end

-- Type de garage ESX selon le type de véhicule détecté par le client
local GARAGE_TYPES = { boat = 'boat', submarine = 'boat', heli = 'aircraft', plane = 'aircraft' }

-- Boutique des joueurs (lunatic_store) : véhicule ajouté au garage ; renvoie la plaque (nil si aucune plaque libre)
exports('giveOwnedVehicle', function(identifier, hash, vehicleType)
    local plate = newPlate()

    if not plate or type(identifier) ~= 'string' or not tonumber(hash) then
        return nil
    end

    MySQL.insert.await('INSERT INTO `owned_vehicles` (`owner`, `plate`, `vehicle`, `type`, `stored`) VALUES (?, ?, ?, ?, 1)', {
        identifier, plate, json.encode({ model = tonumber(hash), plate = plate, fuelLevel = 100.0 }), GARAGE_TYPES[vehicleType] or 'car',
    })

    return plate
end)

Panel.actions['vehicle.give'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'vehicles.give') then
        return denied()
    end

    local target, err = targetOf(src, actor, data, {})

    if not target then
        return err
    end

    local xPlayer = ESX.GetPlayerFromId(target)

    if not xPlayer then
        return Panel.fail("Ce joueur n'a pas encore chargé son personnage.")
    end

    local model = type(data.model) == 'string' and data.model:lower():gsub('%s', '') or ''

    if not model:match('^[%w_]+$') or #model > 30 then
        return Panel.fail('Nom de modèle invalide.')
    end

    -- Le serveur ne connaît pas les modèles du jeu : le client du staff vérifie qu'il existe
    local ok, info = pcall(lib.callback.await, 'lunatic_admin:vehicleModel', src, model)

    if not ok or type(info) ~= 'table' then
        return Panel.fail('Vérification du modèle impossible (êtes-vous en jeu ?).')
    end

    if not info.ok then
        return Panel.fail(("Le modèle « %s » n'existe pas."):format(model))
    end

    local plate = newPlate()

    if not plate then
        return Panel.fail('Aucune plaque libre trouvée, réessayez.')
    end

    MySQL.insert.await('INSERT INTO `owned_vehicles` (`owner`, `plate`, `vehicle`, `type`, `stored`) VALUES (?, ?, ?, ?, 1)', {
        xPlayer.identifier, plate, json.encode({ model = info.hash, plate = plate }), GARAGE_TYPES[info.type] or 'car',
    })

    local name = Staff.displayName(target)
    Logs.add(src, 'vehicle.give', name, { serverId = target, model = model, plate = plate })

    if target ~= src then
        Panel.notify(target, ('Le staff vous a donné un véhicule (%s, plaque %s) : il vous attend au garage.'):format(model, plate), 'success')
    end

    return { ok = true, silent = true, plate = plate, model = model, name = name }
end

---------------------------------------------------------------------
-- Inventaire d'un joueur : ouvert à côté du sien (prendre, déposer, déplacer)
---------------------------------------------------------------------

Panel.actions['inventory.open'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'economy.items') then
        return denied()
    end

    local target, err = targetOf(src, actor, data, { notSelf = true, protect = true })

    if not target then
        return err
    end

    local ok, opened = pcall(function()
        return ox:forceOpenInventory(src, 'player', target)
    end)

    if not ok or not opened then
        return Panel.fail("Impossible d'ouvrir cet inventaire (joueur occupé ou inventaire déjà ouvert).")
    end

    local name = Staff.displayName(target)
    Logs.add(src, 'inventory.open', name, { serverId = target })

    return { ok = true, silent = true, name = name }
end

---------------------------------------------------------------------
-- Commandes du tchat
---------------------------------------------------------------------

-- Exécute une action du panel depuis une commande et répond par une notification
local function command(name, usage, minArgs, build)
    RegisterCommand(name, function(src, args)
        if src == 0 then
            return print(('[lunatic_admin] /%s : commande à utiliser en jeu.'):format(name))
        end

        local actor = Staff.rankOf(src)

        if not actor then
            return Panel.notify(src, 'Commande réservée au staff.', 'error')
        end

        if #args < minArgs then
            return Panel.notify(src, ('Utilisation : %s'):format(usage), 'error')
        end

        local action, data, success = build(args)
        local ok, result = pcall(Panel.actions[action], src, actor, data)

        if not ok then
            print(('[lunatic_admin] Erreur dans /%s : %s'):format(name, result))
            return Panel.notify(src, 'Erreur serveur, consultez la console.', 'error')
        end

        if result.ok then
            if success then
                Panel.notify(src, success(result), 'success')
            end

            if not result.silent then
                Staff.broadcastRefresh()
            end
        else
            Panel.notify(src, result.error or 'Action impossible.', 'error')
        end
    end, false)
end

command('crash', '/crash <id>', 1, function(args)
    return 'player.crash', { serverId = tonumber(args[1]) }, function(res)
        return ('%s a été déconnecté.'):format(res.name)
    end
end)

command('givecar', '/givecar <id> <modèle>', 2, function(args)
    return 'vehicle.give', { serverId = tonumber(args[1]), model = args[2] }, function(res)
        return ('%s donné à %s (plaque %s).'):format(res.model, res.name, res.plate)
    end
end)

command('inv', '/inv <id>', 1, function(args)
    return 'inventory.open', { serverId = tonumber(args[1]) }, nil
end)

print('[lunatic_admin] Module Commandes chargé.')
