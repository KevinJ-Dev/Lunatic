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
