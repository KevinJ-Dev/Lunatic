-- Lot M : menu contextuel staff dans ox_target (joueurs, véhicules, objets).
-- Le serveur envoie à chaque membre du staff les droits utiles au menu (pour griser/masquer les options),
-- et revérifie chaque action : le client n'est jamais cru sur parole.

-- Droits envoyés au client : clé locale -> permission du panel
local FLAGS = {
    use = 'contextmenu.use',
    dev = 'contextmenu.dev',
    view = 'players.view',
    teleport = 'players.goto', -- (goto est un mot réservé de Lua)
    bring = 'players.bring',
    freeze = 'players.freeze',
    heal = 'players.heal',
    spectate = 'players.spectate',
    items = 'economy.items',
    vehicles = 'tools.vehicles',
}

---@type table<number, string> dernier envoi par joueur (signature)
local sent = {}

local function flagsOf(src)
    local rank = Staff.rankOf(src)
    local flags = {}

    if rank and Ranks.hasPermission(rank, 'panel.open') then
        for key, permission in pairs(FLAGS) do
            flags[key] = Ranks.hasPermission(rank, permission) or nil
        end
    end

    return flags
end

-- Envoi seulement quand les droits changent (rang modifié, membre ajouté ou retiré)
CreateThread(function()
    while true do
        Wait(5000)

        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            local flags = flagsOf(src)
            local signature = json.encode(flags)

            if sent[src] ~= signature then
                sent[src] = signature
                TriggerClientEvent('lunatic_admin:contextFlags', src, flags)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    sent[source] = nil
end)

-- Le client (re)démarre : il redemande ses droits
RegisterNetEvent('lunatic_admin:contextFlagsRequest', function()
    sent[source] = nil
end)

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

---@return number|nil entity
local function entityOf(netId)
    netId = tonumber(netId)

    if not netId then
        return nil
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    return entity and entity ~= 0 and DoesEntityExist(entity) and entity or nil
end

---------------------------------------------------------------------
-- Véhicule visé
---------------------------------------------------------------------

-- repair / flip / enter : le serveur autorise, le client du staff applique (après avoir pris le contrôle du véhicule)
-- delete : supprimé par le serveur ; owner : propriétaire d'après owned_vehicles
Panel.actions['context.vehicle'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'contextmenu.use') or not Ranks.hasPermission(actor, 'tools.vehicles') then
        return denied()
    end

    local vehicle = entityOf(data.netId)

    if not vehicle or GetEntityType(vehicle) ~= 2 then
        return Panel.fail('Véhicule introuvable.')
    end

    local operation = data.operation
    local plate = (GetVehicleNumberPlateText(vehicle) or ''):match('^%s*(.-)%s*$')

    if operation == 'repair' or operation == 'flip' or operation == 'enter' then
        Logs.add(src, 'context.vehicle', plate, { operation = operation, plate = plate })
        return { ok = true, silent = true }
    end

    if operation == 'delete' then
        for seat = -1, 6 do
            local ped = GetPedInVehicleSeat(vehicle, seat)

            if ped and ped ~= 0 and IsPedAPlayer(ped) then
                return Panel.fail('Un joueur est dans ce véhicule.')
            end
        end

        DeleteEntity(vehicle)
        Logs.add(src, 'context.vehicle', plate, { operation = 'delete', plate = plate })
        return { ok = true, silent = true }
    end

    if operation == 'owner' then
        local row = plate ~= '' and MySQL.single.await([[
            SELECT ov.`owner`, u.`firstname`, u.`lastname` FROM `owned_vehicles` ov
            LEFT JOIN `users` u ON u.`identifier` = ov.`owner`
            WHERE TRIM(ov.`plate`) = ? LIMIT 1
        ]], { plate })

        if not row then
            return { ok = true, silent = true, owner = nil, plate = plate }
        end

        local name = row.firstname and row.firstname ~= '' and ('%s %s'):format(row.firstname, row.lastname or '') or row.owner
        return { ok = true, silent = true, owner = name, plate = plate }
    end

    return Panel.fail('Opération inconnue.')
end

---------------------------------------------------------------------
-- Section Dév : geler, supprimer une entité
---------------------------------------------------------------------

Panel.actions['context.entity'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'contextmenu.dev') then
        return denied()
    end

    local operation = data.operation

    if operation ~= 'freeze' and operation ~= 'unfreeze' and operation ~= 'delete' then
        return Panel.fail('Opération inconnue.')
    end

    -- Entité locale (décor de la carte, objet non synchronisé) : le client du staff agit seul, on garde une trace
    if data['local'] == true then
        Logs.add(src, 'context.entity', data.model and tostring(data.model) or 'entité locale', { operation = operation, ['local'] = true })
        return { ok = true, silent = true }
    end

    local entity = entityOf(data.netId)

    if not entity then
        return Panel.fail('Entité introuvable.')
    end

    if GetEntityType(entity) == 1 and IsPedAPlayer(entity) then
        return Panel.fail("Utilisez les options Staff pour agir sur un joueur.")
    end

    local model = GetEntityModel(entity)

    if operation == 'delete' then
        if GetEntityType(entity) == 2 then
            for seat = -1, 6 do
                local ped = GetPedInVehicleSeat(entity, seat)

                if ped and ped ~= 0 and IsPedAPlayer(ped) then
                    return Panel.fail('Un joueur est dans ce véhicule.')
                end
            end
        end

        DeleteEntity(entity)
    else
        FreezeEntityPosition(entity, operation == 'freeze')
    end

    Logs.add(src, 'context.entity', tostring(model), { operation = operation, netId = tonumber(data.netId) })
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Menu contextuel chargé.')
