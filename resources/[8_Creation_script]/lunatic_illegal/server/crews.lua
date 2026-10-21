-- Crews côté jeu : actions de la tablette (onglet Crew). Les données (crews, rangs, membres, XP) sont dans lunatic_admin (exports).
-- Le chef (rang le plus haut) invite, promeut, rétrograde et renvoie ; les autres peuvent quitter le crew.

local admin = exports.lunatic_admin

---@type table<number, { crew: number, from: string, expires: number }> invitations en attente par joueur invité
local invites = {}

AddEventHandler('playerDropped', function()
    invites[source] = nil
end)

local function fail(message)
    return { ok = false, error = message }
end

local function notify(target, message, kind)
    TriggerClientEvent('esx:showNotification', target, message, kind or 'info')
end

-- Crew du joueur et son rang ; leader = rang le plus haut
---@return table|nil xPlayer, table|nil view, table|nil me
local function myCrew(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer then
        return nil
    end

    local membership = admin:getCrewOf(xPlayer.identifier)

    if not membership then
        return xPlayer
    end

    local view = admin:getCrewView(membership.crew)

    if not view then
        return xPlayer
    end

    return xPlayer, view, { rank = membership.rank, leader = membership.rank == view.topRank }
end

local function memberIn(view, identifier)
    for _, member in ipairs(view.members) do
        if member.identifier == identifier then
            return member
        end
    end
end

lib.callback.register('lunatic_illegal:crew', function(src)
    local xPlayer, view, me = myCrew(src)

    if not xPlayer then
        return fail('Personnage non chargé.')
    end

    if not view then
        return { ok = true, crew = nil }
    end

    return { ok = true, crew = view, me = { identifier = xPlayer.identifier, rank = me.rank, leader = me.leader } }
end)

-- Territoires vus par le crew du joueur (zones tenues, influence)
lib.callback.register('lunatic_illegal:territories', function(src)
    local _, view = myCrew(src)

    if not view then
        return fail("Vous ne faites partie d'aucun crew.")
    end

    local found, list = pcall(function() return admin:getCrewTerritories(view.id) end)
    return { ok = true, territories = found and list or {} }
end)

lib.callback.register('lunatic_illegal:invite', function(src, targetId)
    local xPlayer, view, me = myCrew(src)

    if not view or not me.leader then
        return fail('Réservé au chef du crew.')
    end

    local target = ESX.GetPlayerFromId(tonumber(targetId) or -1)

    if not target or target.source == src then
        return fail('Joueur introuvable.')
    end

    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target.source))) > Config.InviteDistance + 1.0 then
        return fail('Ce joueur est trop loin.')
    end

    if admin:getCrewOf(target.identifier) then
        return fail('Ce joueur fait déjà partie d\'un crew.')
    end

    invites[target.source] = { crew = view.id, from = xPlayer.getName(), expires = os.time() + Config.InviteTimeout }
    TriggerClientEvent('lunatic_illegal:invited', target.source, { crew = view.label, type = view.typeLabel, from = xPlayer.getName(), timeout = Config.InviteTimeout })

    return { ok = true, name = target.getName() }
end)

lib.callback.register('lunatic_illegal:answer', function(src, accept)
    local invite = invites[src]
    invites[src] = nil

    if not invite or invite.expires < os.time() then
        return fail("L'invitation a expiré.")
    end

    if accept ~= true then
        return { ok = true, joined = false }
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local view = admin:getCrewView(invite.crew)

    if not xPlayer or not view then
        return fail("Ce crew n'existe plus.")
    end

    local lowest = view.ranks[1] and view.ranks[1].rank or 0
    local ok, err = admin:setCrewMember(xPlayer.identifier, view.id, lowest)

    if not ok then
        return fail(err)
    end

    for _, member in ipairs(view.members) do
        if member.online then
            notify(member.online, ('%s a rejoint le crew.'):format(xPlayer.getName()), 'success')
        end
    end

    return { ok = true, joined = true, crew = view.label }
end)

lib.callback.register('lunatic_illegal:setRank', function(src, identifier, rank)
    local xPlayer, view, me = myCrew(src)

    if not view or not me.leader then
        return fail('Réservé au chef du crew.')
    end

    local member = type(identifier) == 'string' and memberIn(view, identifier)
    rank = tonumber(rank)

    if not member or identifier == xPlayer.identifier then
        return fail('Membre introuvable.')
    end

    -- Le chef ne nomme pas un autre chef et ne touche pas à un autre chef
    if not rank or rank >= view.topRank or member.rank >= view.topRank then
        return fail('Rang invalide.')
    end

    local ok, err = admin:setCrewMember(identifier, view.id, rank)

    if not ok then
        return fail(err)
    end

    if member.online then
        notify(member.online, 'Votre rang dans le crew a changé.', 'info')
    end

    return { ok = true }
end)

lib.callback.register('lunatic_illegal:kick', function(src, identifier)
    local xPlayer, view, me = myCrew(src)

    if not view or not me.leader then
        return fail('Réservé au chef du crew.')
    end

    local member = type(identifier) == 'string' and memberIn(view, identifier)

    if not member or identifier == xPlayer.identifier or member.rank >= view.topRank then
        return fail('Vous ne pouvez pas renvoyer ce membre.')
    end

    admin:setCrewMember(identifier, nil)

    if member.online then
        notify(member.online, ('Vous avez été renvoyé du crew %s.'):format(view.label), 'error')
    end

    return { ok = true }
end)

lib.callback.register('lunatic_illegal:leave', function(src)
    local xPlayer, view, me = myCrew(src)

    if not view then
        return fail("Vous n'avez pas de crew.")
    end

    if me.leader then
        return fail("Le chef ne peut pas quitter son crew : demandez au staff de nommer un autre chef.")
    end

    admin:setCrewMember(xPlayer.identifier, nil)
    return { ok = true, crew = view.label }
end)

print('[lunatic_illegal] Crews démarrés.')
