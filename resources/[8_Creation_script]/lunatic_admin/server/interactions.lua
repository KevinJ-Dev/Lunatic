-- Tuile Interactions : tous les points d'interaction du monde au même endroit, par catégorie
-- (magasins, location, grossistes, recelleur). Les données restent celles des tuiles Catalogues et Illégal :
-- les actions de modification sont shops.* et fence.* (autorisées aussi par la permission « Interactions »).
-- Mode édition : le staff voit en jeu tous les points avec leur nom et leur rayon (client/interactions.lua).

local GROUPS = {
    { id = 'shops', label = 'Magasins' },
    { id = 'vehicles', label = 'Véhicules' },
    { id = 'wholesale', label = 'Grossistes' },
    { id = 'illegal', label = 'Illégal' },
    { id = 'jobs', label = 'Jobs Farm', soon = true },
    { id = 'misc', label = 'Divers', soon = true },
}

-- Catégorie d'un magasin selon son genre
local KIND_GROUP = { items = 'shops', clothing = 'shops', barber = 'shops', tattoo = 'shops', rental = 'vehicles', buyback = 'wholesale' }

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer les interactions.")
end

-- Nom de lieu proche (rue) : calculé par le jeu du staff, sinon vide
local function entries()
    local list = {}

    for _, entry in ipairs(Shops.allLocations()) do
        local shop, location = entry.shop, entry.location
        list[#list + 1] = {
            key = ('shop:%d'):format(location.id), source = 'shop', id = location.id, shopId = shop.id, index = entry.index,
            group = KIND_GROUP[shop.kind] or 'shops', label = shop.label, category = shop.category,
            x = location.x, y = location.y, z = location.z, h = location.h,
            ped = location.ped or '', pedPos = location.pedPos, radius = location.radius, showBlip = location.showBlip,
            blip = shop.blip,
        }
    end

    for _, location in ipairs(Fence.locations()) do
        list[#list + 1] = {
            key = ('fence:%d'):format(location.id), source = 'fence', id = location.id, group = 'illegal', label = 'Recelleur',
            x = location.x, y = location.y, z = location.z, h = location.h,
            ped = location.ped or '', radius = location.radius, showBlip = location.showBlip, blip = { sprite = 500, color = 1 },
        }
    end

    return list
end

Panel.actions['interactions.list'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'interactions.manage') then
        return denied()
    end

    return {
        ok = true, silent = true, groups = GROUPS, interactions = entries(), shops = Shops.list(),
        radius = Config.InteractionRadius, defaultPed = Config.InteractionDefaultPed, fenceDefaultPed = Config.FenceDefaultPed,
    }
end

-- Mode édition : affichage en jeu de tous les points (nom, rayon, PNJ) pour le staff
Panel.actions['interactions.editMode'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'interactions.manage') then
        return denied()
    end

    TriggerClientEvent('lunatic_admin:interactionsEditMode', src, data.enabled == true)
    return { ok = true, silent = true }
end
