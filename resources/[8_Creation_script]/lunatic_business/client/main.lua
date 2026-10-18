-- lunatic_business : côté client. Marqueurs au sol des points de sa structure, [E] pour interagir, menus ox_lib.
-- La Sonnette est visible par tous ; les autres points seulement par les membres de la structure.

local points = {}
local playerJob

local function loadPoints(list)
    points = type(list) == 'table' and list or {}
end

AddStateBagChangeHandler('lunaticStructurePoints', 'global', function(_, _, value)
    loadPoints(value)
end)

RegisterNetEvent('esx:playerLoaded', function(data)
    playerJob = data and data.job
end)

RegisterNetEvent('esx:setJob', function(job)
    playerJob = job
end)

CreateThread(function()
    loadPoints(GlobalState.lunaticStructurePoints)

    if ESX.IsPlayerLoaded() then
        playerJob = ESX.GetPlayerData().job
    end
end)

local function money(amount)
    return ('%s $'):format(tostring(math.floor(amount or 0)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', ''))
end

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

local function playtime(minutes)
    minutes = minutes or 0
    return minutes < 60 and ('%d min'):format(minutes) or ('%d h %02d'):format(math.floor(minutes / 60), minutes % 60)
end

---------------------------------------------------------------------
-- Gestion (patron)
---------------------------------------------------------------------

local openManagement

local function gradeLabel(grades, number)
    for _, grade in ipairs(grades) do
        if grade.grade == number then
            return grade.label
        end
    end

    return ('Grade %d'):format(number)
end

local function memberMenu(point, data, member)
    local bossGrade = data.grades[#data.grades].grade
    local options = {}

    -- Grade suivant, sans jamais atteindre celui du patron
    for i, grade in ipairs(data.grades) do
        if grade.grade == member.grade then
            local up, down = data.grades[i + 1], data.grades[i - 1]

            if up and up.grade < bossGrade then
                options[#options + 1] = { title = ('Promouvoir : %s'):format(up.label), icon = 'arrow-up', onSelect = function()
                    if not failed(lib.callback.await('lunatic_business:setGrade', false, point.id, member.identifier, up.grade)) then
                        notify(('%s est maintenant %s.'):format(member.name, up.label), 'success')
                    end
                    openManagement(point)
                end }
            end

            if down then
                options[#options + 1] = { title = ('Rétrograder : %s'):format(down.label), icon = 'arrow-down', onSelect = function()
                    if not failed(lib.callback.await('lunatic_business:setGrade', false, point.id, member.identifier, down.grade)) then
                        notify(('%s est maintenant %s.'):format(member.name, down.label), 'success')
                    end
                    openManagement(point)
                end }
            end
        end
    end

    options[#options + 1] = { title = 'Renvoyer', icon = 'door-open', iconColor = '#ff6b6b', onSelect = function()
        local answer = lib.alertDialog({ header = ('Renvoyer %s ?'):format(member.name), content = 'Il redevient sans emploi.', centered = true, cancel = true, labels = { confirm = 'Renvoyer', cancel = 'Annuler' } })

        if answer == 'confirm' and not failed(lib.callback.await('lunatic_business:fire', false, point.id, member.identifier)) then
            notify(('%s a été renvoyé.'):format(member.name), 'success')
        end

        openManagement(point)
    end }

    lib.registerContext({ id = 'lb_member', title = member.name, menu = 'lb_members', options = options })
    lib.showContext('lb_member')
end

local function membersMenu(point, data)
    local options = {}

    for _, member in ipairs(data.members) do
        local isMe = member.identifier == data.me
        options[#options + 1] = {
            title = isMe and ('%s (vous)'):format(member.name) or member.name,
            description = ('%s · %s · %s de service'):format(gradeLabel(data.grades, member.grade), member.online and 'en ligne' or 'hors ligne', playtime(member.playtime)),
            icon = member.online and 'circle' or 'circle-dot',
            iconColor = member.online and '#5fd3a0' or '#6b6b78',
            disabled = isMe or member.grade >= data.grades[#data.grades].grade,
            onSelect = function()
                memberMenu(point, data, member)
            end,
        }
    end

    lib.registerContext({ id = 'lb_members', title = ('Membres (%d)'):format(#data.members), menu = 'lb_manage', options = options })
    lib.showContext('lb_members')
end

local function recruitMenu(point)
    local options = {}

    for _, nearby in ipairs(lib.getNearbyPlayers(GetEntityCoords(PlayerPedId()), Config.RecruitDistance, false)) do
        local serverId = GetPlayerServerId(nearby.id)
        local state = Player(serverId).state
        local name = state.firstName and ('%s %s'):format(state.firstName, state.lastName or '') or GetPlayerName(nearby.id)

        options[#options + 1] = { title = name, description = ('ID %d'):format(serverId), icon = 'user-plus', onSelect = function()
            local result = lib.callback.await('lunatic_business:recruit', false, point.id, serverId)

            if not failed(result) then
                notify(('%s a été recruté.'):format(result.name or name), 'success')
            end
        end }
    end

    if #options == 0 then
        options[1] = { title = 'Personne à proximité', description = ('Le joueur doit être à moins de %d m.'):format(Config.RecruitDistance), disabled = true }
    end

    lib.registerContext({ id = 'lb_recruit', title = 'Recruter un joueur proche', menu = 'lb_manage', options = options })
    lib.showContext('lb_recruit')
end

local function accountMenu(point, data)
    local function operation(kind)
        local input = lib.inputDialog(kind == 'deposit' and 'Déposer du liquide' or 'Retirer du liquide', {
            { type = 'number', label = 'Montant', min = 1, max = Config.AccountMaxAction, required = true },
        })

        if not input or not input[1] then
            return accountMenu(point, data)
        end

        local result = lib.callback.await('lunatic_business:account', false, point.id, kind, math.floor(input[1]))

        if not failed(result) then
            data.balance = result.balance
            notify(('%s effectué. Solde : %s.'):format(kind == 'deposit' and 'Dépôt' or 'Retrait', money(result.balance)), 'success')
        end

        accountMenu(point, data)
    end

    lib.registerContext({ id = 'lb_account', title = 'Compte de société', menu = 'lb_manage', options = {
        { title = ('Solde : %s'):format(money(data.balance)), icon = 'building-columns', readOnly = true },
        { title = 'Déposer du liquide', icon = 'arrow-down', onSelect = function() operation('deposit') end },
        { title = 'Retirer du liquide', icon = 'arrow-up', onSelect = function() operation('withdraw') end },
        { title = 'Historique', icon = 'clock-rotate-left', onSelect = function()
            local result = lib.callback.await('lunatic_business:history', false, point.id)

            if failed(result) then
                return
            end

            local options = {}

            for _, entry in ipairs(result.history) do
                options[#options + 1] = {
                    title = ('%s%s'):format(entry.amount > 0 and '+' or '-', money(math.abs(entry.amount))),
                    description = ('%s · %s · solde %s'):format(entry.reason ~= '' and entry.reason or '—', entry.actor ~= '' and entry.actor or '?', money(entry.balance)),
                    icon = entry.amount > 0 and 'plus' or 'minus',
                    iconColor = entry.amount > 0 and '#5fd3a0' or '#ff8a84',
                    readOnly = true,
                }
            end

            if #options == 0 then
                options[1] = { title = 'Aucune opération', readOnly = true }
            end

            lib.registerContext({ id = 'lb_history', title = 'Historique du compte', menu = 'lb_account', options = options })
            lib.showContext('lb_history')
        end },
    } })
    lib.showContext('lb_account')
end

openManagement = function(point)
    local data = lib.callback.await('lunatic_business:management', false, point.id)

    if failed(data) then
        return
    end

    lib.registerContext({ id = 'lb_manage', title = ('Gestion · %s'):format(data.label), options = {
        { title = 'Compte de société', description = ('Solde : %s'):format(money(data.balance)), icon = 'building-columns', onSelect = function() accountMenu(point, data) end },
        { title = ('Membres (%d)'):format(#data.members), description = 'Promouvoir, rétrograder, renvoyer', icon = 'users', onSelect = function() membersMenu(point, data) end },
        { title = 'Recruter un joueur proche', icon = 'user-plus', onSelect = function() recruitMenu(point) end },
    } })
    lib.showContext('lb_manage')
end

---------------------------------------------------------------------
-- Vestiaire
---------------------------------------------------------------------

local appearance = exports['illenium-appearance']

local function openWardrobe(point)
    local data = lib.callback.await('lunatic_business:outfits', false, point.id)

    if failed(data) then
        return
    end

    local options = {}

    for _, outfit in ipairs(data.outfits) do
        options[#options + 1] = { title = ('Tenue : %s'):format(outfit.label), icon = 'shirt', onSelect = function()
            local ped = PlayerPedId()
            appearance:setPedComponents(ped, outfit.outfit.components)
            appearance:setPedProps(ped, outfit.outfit.props)
            notify(('Tenue « %s » enfilée.'):format(outfit.label), 'success')
        end }
    end

    if not data.model then
        options[#options + 1] = { title = 'Aucune tenue', description = 'Les tenues ne concernent que les personnages homme ou femme du jeu.', readOnly = true }
    elseif #data.outfits == 0 then
        options[#options + 1] = { title = 'Aucune tenue pour votre grade', readOnly = true }
    end

    options[#options + 1] = { title = 'Reprendre ma tenue civile', icon = 'user', onSelect = function()
        TriggerEvent('illenium-appearance:client:reloadSkin', true)
    end }

    if data.isBoss and data.model then
        options[#options + 1] = { title = 'Enregistrer ma tenue pour un grade', description = 'La tenue que vous portez devient celle du grade choisi', icon = 'floppy-disk', onSelect = function()
            local choices = {}

            for _, grade in ipairs(data.grades) do
                choices[#choices + 1] = { value = grade.grade, label = grade.label }
            end

            local input = lib.inputDialog('Enregistrer la tenue', { { type = 'select', label = 'Grade', options = choices, required = true } })

            if not input or input[1] == nil then
                return openWardrobe(point)
            end

            local ped = PlayerPedId()
            local result = lib.callback.await('lunatic_business:saveOutfit', false, point.id, input[1], {
                components = appearance:getPedComponents(ped),
                props = appearance:getPedProps(ped),
            })

            if not failed(result) then
                notify('Tenue enregistrée.', 'success')
            end

            openWardrobe(point)
        end }

        if #data.outfits > 0 then
            options[#options + 1] = { title = 'Supprimer une tenue', icon = 'trash', onSelect = function()
                local choices = {}

                for _, outfit in ipairs(data.outfits) do
                    choices[#choices + 1] = { value = outfit.grade, label = outfit.label }
                end

                local input = lib.inputDialog('Supprimer une tenue', { { type = 'select', label = 'Grade', options = choices, required = true } })

                if input and input[1] ~= nil and not failed(lib.callback.await('lunatic_business:deleteOutfit', false, point.id, input[1])) then
                    notify('Tenue supprimée.', 'success')
                end

                openWardrobe(point)
            end }
        end
    end

    lib.registerContext({ id = 'lb_wardrobe', title = 'Vestiaire', options = options })
    lib.showContext('lb_wardrobe')
end

---------------------------------------------------------------------
-- Interaction avec un point
---------------------------------------------------------------------

local handlers = {
    management = function(point)
        if not playerJob or playerJob.grade_name ~= 'boss' then
            return notify('Réservé au patron.', 'error')
        end

        openManagement(point)
    end,
    storage = function(point)
        exports.ox_inventory:openInventory('stash', ('lb_storage_%d'):format(point.id))
    end,
    locker = function(point)
        exports.ox_inventory:openInventory('stash', ('lb_locker_%s'):format(point.job))
    end,
    wardrobe = openWardrobe,
    doorbell = function(point)
        TriggerServerEvent('lunatic_business:ring', point.id)
    end,
    custom = function(point)
        TriggerServerEvent('lunatic_business:useCustom', point.id)
        TriggerEvent('lunatic_business:customClient', point)
    end,
}

RegisterNetEvent('lunatic_business:ringed', function(data)
    notify(('%s sonne à %s (%s). Point GPS ajouté.'):format(data.name, data.job, data.label), 'info')
    SetNewWaypoint(data.x + 0.0, data.y + 0.0)
end)

local function visible(point)
    return point.type == 'doorbell' or (playerJob ~= nil and playerJob.name == point.job)
end

---------------------------------------------------------------------
-- Boucle : marqueurs et [E]
---------------------------------------------------------------------

CreateThread(function()
    local shown -- id du point affiché dans le texte d'aide
    local color = Config.MarkerColor

    while true do
        local sleep = 750
        local coords = GetEntityCoords(PlayerPedId())
        local closest, closestDistance

        for _, point in ipairs(points) do
            if visible(point) then
                local distance = #(coords - vector3(point.x, point.y, point.z))

                if distance < Config.MarkerDistance then
                    sleep = 0
                    DrawMarker(25, point.x, point.y, point.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 1.1, 1.0, color[1], color[2], color[3], color[4], false, false, 2, false, nil, nil, false)

                    if distance < Config.InteractDistance and (not closestDistance or distance < closestDistance) then
                        closest, closestDistance = point, distance
                    end
                end
            end
        end

        if closest then
            if shown ~= closest.id then
                shown = closest.id
                lib.showTextUI(('[E] %s'):format(closest.type == 'doorbell' and 'Sonner' or closest.label))
            end

            if IsControlJustReleased(0, 38) and not IsPedInAnyVehicle(PlayerPedId(), false) then
                local handler = handlers[closest.type]

                if handler then
                    handler(closest)
                else
                    notify(("« %s » n'est pas encore disponible."):format(closest.typeLabel or closest.type), 'info')
                end
            end
        elseif shown then
            shown = nil
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        lib.hideTextUI()
    end
end)
