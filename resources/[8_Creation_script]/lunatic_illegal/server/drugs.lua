-- Drogues côté jeu : production dans les laboratoires (membres d'un crew du bon type) et vente aux passants.
-- Les drogues viennent du panel (GlobalState.lunaticDrugs) ; tout est revérifié ici.

local ox = exports.ox_inventory
local admin = exports.lunatic_admin

local function fail(message)
    return { ok = false, error = message }
end

local function notify(target, message, kind)
    TriggerClientEvent('esx:showNotification', target, message, kind or 'info')
end

local function itemLabel(name)
    local item = ox:Items(name)
    return item and item.label or name
end

local function drugs()
    return GlobalState.lunaticDrugs or {}
end

local function findDrug(id)
    for _, drug in ipairs(drugs()) do
        if drug.id == tonumber(id) then
            return drug
        end
    end
end

-- Emplacement de laboratoire -> laboratoire et drogue
local function findLabLocation(locationId)
    for _, drug in ipairs(drugs()) do
        for _, lab in ipairs(drug.labs or {}) do
            for _, location in ipairs(lab.locations or {}) do
                if location.id == tonumber(locationId) then
                    return location, lab, drug
                end
            end
        end
    end
end

local function near(src, coords, distance)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and #(GetEntityCoords(ped) - coords) <= distance
end

-- Policiers en service : joueurs connectés dont le métier est une structure de type Police
local function policePlayers()
    local list = {}

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local structure = admin:getStructure(xPlayer.getJob().name)

        if structure and structure.kind == 'public' and structure.type == 'police' then
            list[#list + 1] = xPlayer.source
        end
    end

    return list
end

---------------------------------------------------------------------
-- Laboratoires : production en deux temps (début puis fin après la durée)
---------------------------------------------------------------------

local producing = {}

AddEventHandler('playerDropped', function()
    producing[source] = nil
end)

local function labCheck(src, locationId)
    local location, lab, drug = findLabLocation(locationId)

    if not location or not drug.active then
        return nil, 'Laboratoire introuvable.'
    end

    if not near(src, vector3(location.x, location.y, location.z), Config.LabDistance + 2.0) then
        return nil, 'Vous êtes trop loin.'
    end

    local crew = Player(src).state.crew

    if not crew or crew.type ~= lab.crewType then
        return nil, "Ce laboratoire n'est pas pour votre crew."
    end

    for _, ingredient in ipairs(lab.ingredients or {}) do
        if (ox:GetItemCount(src, ingredient.item) or 0) < ingredient.count then
            return nil, ('Il vous manque : %d × %s.'):format(ingredient.count, itemLabel(ingredient.item))
        end
    end

    if not ox:CanCarryItem(src, drug.item, lab.output) then
        return nil, "Vous n'avez pas assez de place."
    end

    return lab, drug
end

lib.callback.register('lunatic_illegal:labStart', function(src, locationId)
    local lab, drug = labCheck(src, locationId)

    if not lab then
        return fail(drug)
    end

    producing[src] = { locationId = locationId, at = GetGameTimer(), duration = lab.duration }
    return { ok = true, duration = lab.duration, label = itemLabel(drug.item), output = lab.output }
end)

lib.callback.register('lunatic_illegal:labFinish', function(src, locationId)
    local pending = producing[src]
    producing[src] = nil

    if not pending or pending.locationId ~= locationId then
        return fail('Production interrompue.')
    end

    if GetGameTimer() - pending.at < pending.duration * 1000 - 1500 then
        return fail('Production trop rapide.')
    end

    local lab, drug = labCheck(src, locationId)

    if not lab then
        return fail(drug)
    end

    for _, ingredient in ipairs(lab.ingredients or {}) do
        ox:RemoveItem(src, ingredient.item, ingredient.count)
    end

    ox:AddItem(src, drug.item, lab.output)
    return { ok = true, label = itemLabel(drug.item), output = lab.output }
end)

RegisterNetEvent('lunatic_illegal:labCancel', function()
    producing[source] = nil
end)

---------------------------------------------------------------------
-- Vente aux passants
---------------------------------------------------------------------

local lastSale = {}

AddEventHandler('playerDropped', function()
    lastSale[source] = nil
end)

lib.callback.register('lunatic_illegal:sell', function(src, drugId, pedCoords)
    local drug = findDrug(drugId)

    if not drug or not drug.active then
        return fail('Cette drogue ne se vend pas.')
    end

    -- Le passant est local au client : on vérifie au moins que le vendeur est à côté de la position annoncée
    if type(pedCoords) ~= 'vector3' or not near(src, pedCoords, Config.SellDistance + 1.5) then
        return fail('Le passant est trop loin.')
    end

    if lastSale[src] and os.time() - lastSale[src] < Config.SellCooldown then
        return fail('Doucement, attendez un peu avant de démarcher.')
    end

    local police = policePlayers()

    if #police < (drug.cops or 0) then
        return fail("Il n'y a pas assez de policiers en ville pour vendre maintenant.")
    end

    local count = ox:GetItemCount(src, drug.item) or 0

    if count < drug.volumeMin then
        return fail(('Il faut au moins %d × %s.'):format(drug.volumeMin, itemLabel(drug.item)))
    end

    lastSale[src] = os.time()

    if math.random() > Config.SellChance then
        return { ok = true, refused = true }
    end

    -- Territoire : bonus si le crew du vendeur tient la zone où a lieu la vente
    local crew = Player(src).state.crew
    local found, territory = pcall(function() return admin:territoryAt(pedCoords.x, pedCoords.y) end)
    local held = found and territory and crew and territory.owner == crew.id

    local quantity = math.random(drug.volumeMin, math.min(drug.volumeMax, count))
    local unit = math.floor(drug.price * (1 + (math.random() * 2 - 1) * Config.PriceVariation) + 0.5)

    if held then
        unit = math.floor(unit * (1 + (territory.priceBonus or 0) / 100) + 0.5)
    end

    local total = math.max(0, unit * quantity)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not ox:RemoveItem(src, drug.item, quantity) then
        return fail('Vente impossible.')
    end

    if total > 0 then
        xPlayer.addAccountMoney(Config.SellAccount, total, 'Vente de drogue')
    end

    -- Progression du crew : XP (avec le bonus du territoire tenu) et influence (journalisée avec la position, pour les territoires)
    if crew then
        local xp = drug.xp or 0

        if held then
            xp = math.floor(xp * (1 + (territory.xpBonus or 0) / 100) + 0.5)
        end

        if xp > 0 then
            admin:addCrewXp(crew.id, xp)
        end

        if (drug.influence or 0) > 0 then
            admin:addCrewInfluence(crew.id, drug.influence, pedCoords.x, pedCoords.y, 'drug:' .. drug.item)
        end
    end

    -- Alerte police anonyme, position approximative
    if #police > 0 and math.random() < Config.AlertChance then
        local x = pedCoords.x + math.random(-40, 40)
        local y = pedCoords.y + math.random(-40, 40)

        for _, officer in ipairs(police) do
            TriggerClientEvent('lunatic_illegal:drugAlert', officer, { x = x, y = y })
        end
    end

    return { ok = true, quantity = quantity, total = total, label = itemLabel(drug.item), territory = held and territory.label or nil }
end)
