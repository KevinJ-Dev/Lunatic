-- Objets de soin, côté client : choix de la cible (soi-même ou joueur le plus proche), barre de progression,
-- puis le serveur valide et applique (vie, armure, réanimation).

local function closestPlayer(maxDistance)
    local coords = GetEntityCoords(PlayerPedId())
    local best, bestDistance = nil, maxDistance

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local distance = #(coords - GetEntityCoords(GetPlayerPed(player)))

            if distance <= bestDistance then
                best, bestDistance = player, distance
            end
        end
    end

    return best and GetPlayerServerId(best) or nil
end

RegisterNetEvent('lunatic_gameplay:useHealItem', function(settings)
    local target = nil

    if settings.target ~= 'self' then
        target = closestPlayer(3.0)
    end

    if not target and settings.target == 'other' then
        return Notify('Personne à soigner à côté de vous.', 'error')
    end

    local done = lib.progressBar({
        duration = settings.duration * 1000,
        label = target and 'Soins en cours…' or 'Vous vous soignez…',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = target and { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' } or { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a' },
    })

    ClearPedTasks(PlayerPedId())

    if not done then
        return Notify('Soins annulés.', 'info')
    end

    local result = lib.callback.await('lunatic_gameplay:healFinish', false, settings.item, target)

    if not result or not result.ok then
        return Notify(result and result.error or 'Soins impossibles.', 'error')
    end

    Notify(result.revived and 'Personne réanimée.' or 'Soins effectués.', 'success')
end)

RegisterNetEvent('lunatic_gameplay:healApply', function(heal, armor)
    local ped = PlayerPedId()
    local max = GetEntityMaxHealth(ped)

    if heal and heal > 0 then
        -- Vie d'un joueur : de 100 (à terre) à max
        SetEntityHealth(ped, math.min(max, GetEntityHealth(ped) + math.floor((max - 100) * heal / 100)))
    end

    if armor and armor > 0 then
        SetPedArmour(ped, math.min(100, GetPedArmour(ped) + armor))
    end
end)
