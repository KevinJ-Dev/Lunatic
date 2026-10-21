-- Craft d'armes côté jeu : [E] aux ateliers des crews autorisés, menu des recettes, fabrication avec barre de progression.
-- Le serveur revérifie tout (crew, level, ingrédients, durée) ; l'affichage ici n'est qu'indicatif.

local workshops = {}
local busy = false
local staffView = false -- activée depuis le panel (onglet Craft d'armes) : tous les ateliers visibles, sans fabriquer

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function itemLabel(name)
    local item = exports.ox_inventory:Items(name)
    return item and item.label or name
end

local function count(name)
    return exports.ox_inventory:Search('count', name) or 0
end

local function allowed(workshop, crewType)
    for _, value in ipairs(workshop.crewTypes or {}) do
        if value == crewType then
            return true
        end
    end

    return false
end

AddStateBagChangeHandler('lunaticWorkshops', 'global', function(_, _, value)
    workshops = type(value) == 'table' and value or {}
end)

RegisterNetEvent('lunatic_illegal:staffWorkshops', function(enabled)
    staffView = enabled == true
    notify(staffView and 'Vue staff : tous les ateliers sont affichés en orange.' or 'Vue staff des ateliers désactivée.', 'info')
end)

CreateThread(function()
    workshops = GlobalState.lunaticWorkshops or {}
end)

---------------------------------------------------------------------
-- Fabrication
---------------------------------------------------------------------

local function craft(location, recipe)
    if busy then
        return
    end

    busy = true
    local start = lib.callback.await('lunatic_illegal:craftStart', false, location.id, recipe.id)

    if not start or not start.ok then
        busy = false
        return notify(start and start.error or 'Fabrication impossible.', 'error')
    end

    local done = lib.progressBar({
        duration = start.duration * 1000,
        label = ('Fabrication : %d × %s'):format(start.count, start.label),
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    })

    if not done then
        TriggerServerEvent('lunatic_illegal:craftCancel')
        busy = false
        return notify('Fabrication annulée.', 'error')
    end

    local result = lib.callback.await('lunatic_illegal:craftFinish', false, location.id, recipe.id)
    busy = false

    if result and result.ok then
        notify(('%d × %s fabriqué.'):format(result.count, result.label), 'success')
    else
        notify(result and result.error or 'Fabrication impossible.', 'error')
    end
end

local function openWorkshop(workshop, location)
    local crew = LocalPlayer.state.crew
    local level = crew and crew.level or 0
    local options = {}

    for _, recipe in ipairs(workshop.recipes or {}) do
        local needed = math.max(workshop.minLevel or 1, recipe.minLevel or 1)
        local parts, missing = {}, false

        for _, ingredient in ipairs(recipe.ingredients or {}) do
            local have = count(ingredient.item)
            missing = missing or have < ingredient.count
            parts[#parts + 1] = ('%s %d/%d'):format(itemLabel(ingredient.item), math.min(have, ingredient.count), ingredient.count)
        end

        local locked = level < needed

        options[#options + 1] = {
            title = ('%d × %s'):format(recipe.count, itemLabel(recipe.item)),
            description = locked and ('Level %d du crew requis'):format(needed) or ('%s · %d s'):format(table.concat(parts, ', '), recipe.duration),
            icon = locked and 'lock' or (missing and 'circle-xmark' or 'hammer'),
            iconColor = locked and '#6b6b78' or (missing and '#ff8a84' or '#5fd3a0'),
            disabled = locked,
            onSelect = function()
                if missing then
                    return notify('Il vous manque des ingrédients.', 'error')
                end

                craft(location, recipe)
            end,
        }
    end

    if #options == 0 then
        options[1] = { title = 'Aucune recette dans cet atelier.', readOnly = true }
    end

    lib.registerContext({ id = 'li_workshop', title = workshop.label, options = options })
    lib.showContext('li_workshop')
end

---------------------------------------------------------------------
-- Boucle : marqueurs et [E]
---------------------------------------------------------------------

CreateThread(function()
    local shown

    while true do
        local sleep = 750
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local crew = LocalPlayer.state.crew
        local text, action

        if not busy and not IsPedInAnyVehicle(ped, false) then
            for _, workshop in ipairs(workshops) do
                local usable = crew and allowed(workshop, crew.type)

                if usable or staffView then
                    for _, location in ipairs(workshop.locations or {}) do
                        local distance = #(coords - vector3(location.x, location.y, location.z))

                        if distance < (usable and 15.0 or 60.0) then
                            sleep = 0

                            if usable then
                                DrawMarker(25, location.x, location.y, location.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 1.1, 1.0, 107, 184, 242, 120, false, false, 2, false, nil, nil, false)
                            else
                                DrawMarker(25, location.x, location.y, location.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 1.1, 1.0, 242, 160, 60, 140, false, false, 2, false, nil, nil, false)
                            end

                            if distance < Config.WorkshopDistance then
                                if usable then
                                    text, action = ('[E] %s'):format(workshop.label), function() openWorkshop(workshop, location) end
                                else
                                    text = ('[Vue staff] %s · %d recette(s)'):format(workshop.label, #(workshop.recipes or {}))
                                end
                            end
                        end
                    end
                end
            end
        end

        if text then
            if shown ~= text then
                shown = text
                lib.showTextUI(text)
            end

            if action and IsControlJustReleased(0, 38) then
                lib.hideTextUI()
                shown = nil
                CreateThread(action)
            end
        elseif shown then
            shown = nil
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)

-- Alerte police : fabrication d'armes signalée dans un secteur
RegisterNetEvent('lunatic_illegal:craftAlert', function(alert)
    notify("Signalement : bruits d'atelier suspects (armes) dans le secteur indiqué sur la carte.", 'error')
    local area = AddBlipForRadius(alert.x + 0.0, alert.y + 0.0, 0.0, 100.0)
    SetBlipColour(area, 1)
    SetBlipAlpha(area, 120)
    local center = AddBlipForCoord(alert.x + 0.0, alert.y + 0.0, 0.0)
    SetBlipSprite(center, 110)
    SetBlipColour(center, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName("Atelier d'armes signalé")
    EndTextCommandSetBlipName(center)

    SetTimeout(Config.AlertDuration * 1000, function()
        RemoveBlip(area)
        RemoveBlip(center)
    end)
end)
