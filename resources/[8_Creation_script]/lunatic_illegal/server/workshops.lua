-- Craft d'armes côté jeu : fabrication aux ateliers (membres des crews autorisés, level suffisant).
-- Les ateliers viennent du panel (GlobalState.lunaticWorkshops) ; tout est revérifié ici.
-- Les armes fabriquées n'ont pas de numéro de série (intraçables).

local ox = exports.ox_inventory
local admin = exports.lunatic_admin

local function fail(message)
    return { ok = false, error = message }
end

local function itemLabel(name)
    local item = ox:Items(name)
    return item and item.label or name
end

local function findLocation(locationId)
    for _, workshop in ipairs(GlobalState.lunaticWorkshops or {}) do
        for _, location in ipairs(workshop.locations or {}) do
            if location.id == tonumber(locationId) then
                return location, workshop
            end
        end
    end
end

local function findRecipe(workshop, recipeId)
    for _, recipe in ipairs(workshop.recipes or {}) do
        if recipe.id == tonumber(recipeId) then
            return recipe
        end
    end
end

local function allowed(workshop, crewType)
    for _, value in ipairs(workshop.crewTypes or {}) do
        if value == crewType then
            return true
        end
    end

    return false
end

-- Policiers en service : joueurs connectés dont le métier est une structure de type Police
local function policePlayers()
    local list = {}

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local found, structure = pcall(function() return admin:getStructure(xPlayer.getJob().name) end)

        if found and structure and structure.kind == 'public' and structure.type == 'police' then
            list[#list + 1] = xPlayer.source
        end
    end

    return list
end

local crafting = {}

AddEventHandler('playerDropped', function()
    crafting[source] = nil
end)

---@return table|nil recipe, table|string workshopOrError, table|nil location
local function craftCheck(src, locationId, recipeId)
    local location, workshop = findLocation(locationId)

    if not location then
        return nil, 'Atelier introuvable.'
    end

    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or #(GetEntityCoords(ped) - vector3(location.x, location.y, location.z)) > Config.WorkshopDistance + 2.0 then
        return nil, 'Vous êtes trop loin.'
    end

    local crew = CrewOf(src)

    if not crew or not allowed(workshop, crew.type) then
        return nil, "Cet atelier n'est pas pour votre crew."
    end

    local recipe = findRecipe(workshop, recipeId)

    if not recipe then
        return nil, 'Recette introuvable.'
    end

    local needed = math.max(workshop.minLevel or 1, recipe.minLevel or 1)

    if crew.level < needed then
        return nil, ('Votre crew doit être level %d.'):format(needed)
    end

    for _, ingredient in ipairs(recipe.ingredients or {}) do
        if (ox:GetItemCount(src, ingredient.item) or 0) < ingredient.count then
            return nil, ('Il vous manque : %d × %s.'):format(ingredient.count, itemLabel(ingredient.item))
        end
    end

    if not ox:CanCarryItem(src, recipe.item, recipe.count) then
        return nil, "Vous n'avez pas assez de place."
    end

    return recipe, workshop, location, crew
end

lib.callback.register('lunatic_illegal:craftStart', function(src, locationId, recipeId)
    local recipe, workshop = craftCheck(src, locationId, recipeId)

    if not recipe then
        return fail(workshop)
    end

    crafting[src] = { locationId = locationId, recipeId = recipeId, at = GetGameTimer(), duration = recipe.duration }
    return { ok = true, duration = recipe.duration, label = itemLabel(recipe.item), count = recipe.count }
end)

lib.callback.register('lunatic_illegal:craftFinish', function(src, locationId, recipeId)
    local pending = crafting[src]
    crafting[src] = nil

    if not pending or pending.locationId ~= locationId or pending.recipeId ~= recipeId then
        return fail('Fabrication interrompue.')
    end

    if GetGameTimer() - pending.at < pending.duration * 1000 - 1500 then
        return fail('Fabrication trop rapide.')
    end

    local recipe, workshop, location, crew = craftCheck(src, locationId, recipeId)

    if not recipe then
        return fail(workshop)
    end

    for _, ingredient in ipairs(recipe.ingredients or {}) do
        ox:RemoveItem(src, ingredient.item, ingredient.count)
    end

    -- Arme : sans numéro de série ni propriétaire enregistré
    local item = ox:Items(recipe.item)
    ox:AddItem(src, recipe.item, recipe.count, item and item.weapon and { registered = false } or nil)

    if (recipe.xp or 0) > 0 then
        pcall(function() admin:addCrewXp(crew.id, recipe.xp) end)
    end

    -- Alerte police anonyme, position approximative
    if workshop.alert and math.random() < Config.CraftAlertChance then
        local police = policePlayers()

        for _, officer in ipairs(police) do
            TriggerClientEvent('lunatic_illegal:craftAlert', officer, { x = location.x + math.random(-60, 60), y = location.y + math.random(-60, 60) })
        end
    end

    return { ok = true, label = itemLabel(recipe.item), count = recipe.count }
end)

RegisterNetEvent('lunatic_illegal:craftCancel', function()
    crafting[source] = nil
end)
