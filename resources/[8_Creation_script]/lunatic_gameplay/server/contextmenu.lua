-- Actions RP du menu contextuel côté serveur : fouille d'un joueur (mains levées ou inconscient, à côté).
-- Tout est revérifié ici : le client ne fait qu'afficher l'entrée.

local ox = exports.ox_inventory
local lastSearch = {} -- joueur -> dernière fouille (anti-spam)

lib.callback.register('lunatic_gameplay:search', function(src, target)
    target = tonumber(target)
    local now = os.time()

    if not target or target == src or not GetPlayerName(target) then
        return { error = 'Joueur introuvable.' }
    end

    if (lastSearch[src] or 0) > now - 2 then
        return { error = 'Patientez un instant.' }
    end

    lastSearch[src] = now

    if IsPlayerDown(src) then
        return { error = 'Impossible dans votre état.' }
    end

    local ped, targetPed = GetPlayerPed(src), GetPlayerPed(target)

    if targetPed == 0 or GetPlayerRoutingBucket(target) ~= GetPlayerRoutingBucket(src)
        or #(GetEntityCoords(targetPed) - GetEntityCoords(ped)) > Config.SearchDistance then
        return { error = 'Personne trop loin.' }
    end

    if Player(target).state.handsUp ~= true and not IsPlayerDown(target) then
        return { error = 'La personne doit lever les mains ou être inconsciente.' }
    end

    ox:forceOpenInventory(src, 'player', target)
    Notify(target, "Quelqu'un vous fouille.", 'info')
    return { ok = true }
end)

AddEventHandler('playerDropped', function()
    lastSearch[source] = nil
end)
