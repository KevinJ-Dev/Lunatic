-- Actions RP du menu contextuel côté serveur : fouille d'un joueur (mains levées ou inconscient, à côté).
-- Policier qui fouille : averti si le joueur porte plus de liquide que le seuil « Liquide suspect » (panel : Économie →
-- Autre → Banque), argent qu'il devra justifier. Tout est revérifié ici : le client ne fait qu'afficher l'entrée.

local ox = exports.ox_inventory
local lastSearch = {} -- joueur -> dernière fouille (anti-spam)

local function isPolice(xPlayer)
    local structure = StructureOf(xPlayer)
    return structure ~= nil and structure.kind == 'public' and structure.type == 'police'
end

local function suspiciousCash()
    local economy = GlobalState.lunaticEconomy
    return math.floor(tonumber(type(economy) == 'table' and economy.suspiciousCash) or Config.SuspiciousCash)
end

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

    -- Grosse somme en liquide : le policier est averti (argent à justifier, comme IRL)
    local threshold = suspiciousCash()
    local searcher, searched = ESX.GetPlayerFromId(src), ESX.GetPlayerFromId(target)

    if threshold > 0 and searcher and searched and isPolice(searcher) then
        local cash = searched.getAccount('money').money

        if cash >= threshold then
            Notify(src, ('Somme suspecte : %d $ en liquide. La personne doit en justifier l\u{2019}origine.'):format(cash), 'error')
            pcall(function() exports.lunatic_admin:log('economy', 'warn', src, 'police.suspiciousCash', nil, { target = target, cash = cash }) end)
        end
    end

    return { ok = true }
end)

AddEventHandler('playerDropped', function()
    lastSearch[source] = nil
end)
