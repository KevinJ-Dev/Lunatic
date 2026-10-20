-- Menu du crew (/crew) : informations, membres, gestion par le chef, invitations.

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function failed(result)
    if result and result.ok then
        return false
    end

    notify(result and result.error or 'Action impossible.', 'error')
    return true
end

local openCrew

local function memberMenu(data, member)
    local options = {}
    local ranks = data.crew.ranks

    for index, rank in ipairs(ranks) do
        if rank.rank == member.rank then
            local up, down = ranks[index + 1], ranks[index - 1]

            if up and up.rank < data.crew.topRank then
                options[#options + 1] = { title = ('Promouvoir : %s'):format(up.label), icon = 'arrow-up', onSelect = function()
                    if not failed(lib.callback.await('lunatic_illegal:setRank', false, member.identifier, up.rank)) then
                        notify(('%s est maintenant %s.'):format(member.name, up.label), 'success')
                    end
                    openCrew()
                end }
            end

            if down then
                options[#options + 1] = { title = ('Rétrograder : %s'):format(down.label), icon = 'arrow-down', onSelect = function()
                    if not failed(lib.callback.await('lunatic_illegal:setRank', false, member.identifier, down.rank)) then
                        notify(('%s est maintenant %s.'):format(member.name, down.label), 'success')
                    end
                    openCrew()
                end }
            end
        end
    end

    options[#options + 1] = { title = 'Renvoyer du crew', icon = 'door-open', iconColor = '#ff6b6b', onSelect = function()
        local answer = lib.alertDialog({ header = ('Renvoyer %s ?'):format(member.name), content = 'Il quitte le crew immédiatement.', centered = true, cancel = true, labels = { confirm = 'Renvoyer', cancel = 'Annuler' } })

        if answer == 'confirm' and not failed(lib.callback.await('lunatic_illegal:kick', false, member.identifier)) then
            notify(('%s a été renvoyé.'):format(member.name), 'success')
        end

        openCrew()
    end }

    lib.registerContext({ id = 'li_member', title = member.name, menu = 'li_members', options = options })
    lib.showContext('li_member')
end

local function membersMenu(data)
    local options = {}

    for _, member in ipairs(data.crew.members) do
        local isMe = member.identifier == data.me.identifier
        options[#options + 1] = {
            title = isMe and ('%s (vous)'):format(member.name) or member.name,
            description = ('%s · %s'):format(member.rankLabel, member.online and 'en ligne' or 'hors ligne'),
            icon = 'user', iconColor = member.online and '#5fd3a0' or '#6b6b78',
            disabled = not data.me.leader or isMe or member.rank >= data.crew.topRank,
            onSelect = function() memberMenu(data, member) end,
        }
    end

    lib.registerContext({ id = 'li_members', title = ('Membres (%d)'):format(#data.crew.members), menu = 'li_crew', options = options })
    lib.showContext('li_members')
end

local function inviteMenu()
    local options = {}

    for _, nearby in ipairs(lib.getNearbyPlayers(GetEntityCoords(PlayerPedId()), Config.InviteDistance, false)) do
        local serverId = GetPlayerServerId(nearby.id)
        local state = Player(serverId).state
        local name = state.firstName and ('%s %s'):format(state.firstName, state.lastName or '') or GetPlayerName(nearby.id)

        options[#options + 1] = { title = name, description = ('ID %d'):format(serverId), icon = 'user-plus', disabled = state.crew ~= nil, onSelect = function()
            local result = lib.callback.await('lunatic_illegal:invite', false, serverId)

            if not failed(result) then
                notify(('Invitation envoyée à %s.'):format(result.name), 'success')
            end
        end }
    end

    if #options == 0 then
        options[1] = { title = 'Personne à proximité', description = ('Le joueur doit être à moins de %d m.'):format(Config.InviteDistance), readOnly = true }
    end

    lib.registerContext({ id = 'li_invite', title = 'Inviter un joueur proche', menu = 'li_crew', options = options })
    lib.showContext('li_invite')
end

local function territoriesMenu()
    local data = lib.callback.await('lunatic_illegal:territories', false)

    if failed(data) then
        return
    end

    local options = {}

    for _, t in ipairs(data.territories) do
        options[#options + 1] = {
            title = t.owned and ('%s · tenu par votre crew'):format(t.label) or t.label,
            description = t.owned
                and ("Votre influence : %d · bonus +%d %% au prix, +%d %% d'XP"):format(math.floor(t.influence), t.priceBonus, t.xpBonus)
                or ('Tenu par : %s · votre influence : %d (en tête : %d, seuil %d)'):format(t.owner or 'personne', math.floor(t.influence), math.floor(t.leader), t.minInfluence),
            icon = t.owned and 'flag' or 'map-location-dot',
            iconColor = t.owned and '#5fd3a0' or nil,
            readOnly = true,
        }
    end

    if #options == 0 then
        options[1] = { title = 'Aucun territoire pour le moment.', icon = 'map', readOnly = true }
    end

    lib.registerContext({ id = 'li_territories', title = 'Territoires', menu = 'li_crew', options = options })
    lib.showContext('li_territories')
end

openCrew = function()
    local data = lib.callback.await('lunatic_illegal:crew', false)

    if failed(data) then
        return
    end

    if not data.crew then
        return notify("Vous ne faites partie d'aucun crew.", 'info')
    end

    local crew = data.crew
    local options = {
        { title = ('%s · level %d'):format(crew.typeLabel, crew.level), description = crew.nextLevelXp and ('%d / %d XP'):format(crew.xp, crew.nextLevelXp) or ('%d XP (level maximum)'):format(crew.xp), icon = 'chart-line', readOnly = true },
        { title = ('Membres (%d)'):format(#crew.members), description = data.me.leader and 'Promouvoir, rétrograder, renvoyer' or 'Liste des membres', icon = 'users', onSelect = function() membersMenu(data) end },
        { title = 'Territoires', description = "Zones tenues et influence du crew (vendre de la drogue dans une zone y donne de l'influence)", icon = 'map', onSelect = territoriesMenu },
    }

    if data.me.leader then
        options[#options + 1] = { title = 'Inviter un joueur proche', icon = 'user-plus', onSelect = inviteMenu }
    else
        options[#options + 1] = { title = 'Quitter le crew', icon = 'door-open', iconColor = '#ff6b6b', onSelect = function()
            local answer = lib.alertDialog({ header = ('Quitter %s ?'):format(crew.label), content = 'Vous ne pourrez revenir que sur invitation du chef.', centered = true, cancel = true, labels = { confirm = 'Quitter', cancel = 'Annuler' } })

            if answer == 'confirm' then
                local result = lib.callback.await('lunatic_illegal:leave', false)

                if not failed(result) then
                    notify(('Vous avez quitté %s.'):format(result.crew), 'success')
                end
            end
        end }
    end

    lib.registerContext({ id = 'li_crew', title = crew.label, options = options })
    lib.showContext('li_crew')
end

RegisterCommand(Config.CrewCommand, function()
    openCrew()
end, false)

TriggerEvent('chat:addSuggestion', '/' .. Config.CrewCommand, 'Menu de votre crew')

-- Invitation reçue : réponse par une boîte de dialogue
RegisterNetEvent('lunatic_illegal:invited', function(invite)
    local answer = lib.alertDialog({
        header = ('Rejoindre %s ?'):format(invite.crew),
        content = ('%s vous invite dans son crew (%s). Vous avez %d secondes pour répondre.'):format(invite.from, invite.type, invite.timeout),
        centered = true, cancel = true, labels = { confirm = 'Rejoindre', cancel = 'Refuser' },
    })

    local result = lib.callback.await('lunatic_illegal:answer', false, answer == 'confirm')

    if not failed(result) and result.joined then
        notify(('Bienvenue dans %s.'):format(result.crew), 'success')
    end
end)
