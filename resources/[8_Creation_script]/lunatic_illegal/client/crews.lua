-- Crews côté client : réponse aux invitations. Le crew se gère depuis la tablette (client/tablet.lua).

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

-- Commande /crew : demande au staff pour rejoindre un crew ou en créer un
RegisterCommand('crew', function()
    local options = lib.callback.await('lunatic_illegal:crewRequestOptions', false)

    if failed(options) then
        return
    end

    local kinds = { { value = 'create', label = 'Créer un crew' } }

    if #options.crews > 0 then
        table.insert(kinds, 1, { value = 'join', label = 'Rejoindre un crew' })
    end

    local first = lib.inputDialog('Demande de crew', {
        { type = 'select', label = 'Je veux…', options = kinds, required = true, default = kinds[1].value },
    })

    if not first then
        return
    end

    local data = { kind = first[1] }

    if data.kind == 'join' then
        local crews = {}

        for _, crew in ipairs(options.crews) do
            crews[#crews + 1] = { value = tostring(crew.id), label = ('%s (%s)'):format(crew.label, crew.typeLabel) }
        end

        local answer = lib.inputDialog('Rejoindre un crew', {
            { type = 'select', label = 'Crew', options = crews, required = true, searchable = true },
            { type = 'textarea', label = 'Motivation', max = options.messageMax, autosize = true },
        })

        if not answer then
            return
        end

        data.crew, data.message = tonumber(answer[1]), answer[2] or ''
    else
        local types = {}

        for _, entry in ipairs(options.types) do
            types[#types + 1] = { value = entry.id, label = entry.label }
        end

        local answer = lib.inputDialog('Créer un crew', {
            { type = 'input', label = 'Nom du crew', required = true, min = 2, max = 60 },
            { type = 'select', label = 'Type', options = types, required = true },
            { type = 'textarea', label = 'Motivation et projet', max = options.messageMax, autosize = true },
        })

        if not answer then
            return
        end

        data.label, data.type, data.message = answer[1], answer[2], answer[3] or ''
    end

    local result = lib.callback.await('lunatic_illegal:crewRequest', false, data)

    if not failed(result) then
        notify('Demande envoyée au staff : vous serez prévenu de la réponse.', 'success')
    end
end, false)

TriggerEvent('chat:addSuggestion', '/crew', 'Demander à rejoindre un crew ou à en créer un')

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
