-- Carte d'identité côté client : menu de l'objet (regarder, montrer), affichage de la carte (page web de la ressource).

local showing = false

local function display(identity)
    SendNUIMessage({ action = 'idcard', identity = identity })
    showing = true
    local closeAt = GetGameTimer() + Config.IdCardDuration * 1000

    CreateThread(function()
        while showing and GetGameTimer() < closeAt do
            DisableControlAction(0, 177, true)

            if IsDisabledControlJustReleased(0, 177) then -- Retour arrière
                break
            end

            Wait(0)
        end

        showing = false
        SendNUIMessage({ action = 'idcardHide' })
    end)
end

RegisterNetEvent('lunatic_gameplay:idcardDisplay', function(identity)
    if type(identity) == 'table' then
        display(identity)
    end
end)

local function closestPlayer()
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local best, bestDistance

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)

        if ped ~= myPed then
            local distance = #(GetEntityCoords(ped) - myCoords)

            if distance <= Config.IdCardShowDistance and (not bestDistance or distance < bestDistance) then
                best, bestDistance = GetPlayerServerId(player), distance
            end
        end
    end

    return best
end

RegisterNetEvent('lunatic_gameplay:idcardMenu', function()
    lib.registerContext({
        id = 'lg_idcard', title = "Carte d'identité",
        options = {
            { title = 'Regarder ma carte', icon = 'id-card', onSelect = function()
                local identity = lib.callback.await('lunatic_gameplay:idcard', false)

                if identity then
                    display(identity)
                end
            end },
            { title = 'Montrer à la personne la plus proche', icon = 'hand', onSelect = function()
                local target = closestPlayer()

                if not target then
                    return Notify('Personne à côté de vous.', 'error')
                end

                TriggerServerEvent('lunatic_gameplay:idcardShow', target)
            end },
        },
    })
    lib.showContext('lg_idcard')
end)
