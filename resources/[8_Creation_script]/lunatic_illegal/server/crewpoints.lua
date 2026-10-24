-- Infrastructure des crews côté jeu (positions et planques placées dans le panel, tuile Crews).
-- Coffres : stockage commun, stockage séparé, coffre de planque. Planques : entrée dans un intérieur isolé (routing
-- bucket propre à la planque), coffre et sortie. Réservé aux membres du crew ; tout est revérifié ici.

local admin = exports.lunatic_admin
local ox = exports.ox_inventory

local inside = {} -- joueur -> id de la planque où il est

local function fail(message)
    return { ok = false, error = message }
end

local function distanceTo(src, x, y, z)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return math.huge
    end

    return #(GetEntityCoords(ped) - vector3(x, y, z))
end

local function setBucket(src, bucket)
    SetPlayerRoutingBucket(src, bucket)

    if bucket ~= 0 then
        SetRoutingBucketPopulationEnabled(bucket, false)
    end
end

-- Point du crew du joueur (sinon message d'erreur)
local function pointOf(src, pointId, kinds)
    local point = admin:getCrewPoint(pointId)
    local crew = CrewOf(src)

    if not point or not kinds[point.kind] then
        return nil, 'Point introuvable.'
    end

    if not crew or crew.id ~= point.crew then
        return nil, "Réservé aux membres du crew."
    end

    return point
end

-- Points du crew du joueur (rien sans crew)
lib.callback.register('lunatic_illegal:crewPoints', function(src)
    local crew = CrewOf(src)
    return crew and admin:getCrewPoints(crew.id) or {}
end)

-- Coffre : stockage commun ou séparé (au point), coffre de planque (dans la planque)
lib.callback.register('lunatic_illegal:crewStash', function(src, pointId)
    local point, err = pointOf(src, pointId, { storage = true, stash = true, property = true })

    if not point then
        return fail(err)
    end

    if point.kind == 'property' then
        local interior = Config.BurglaryInteriors[point.interior]
        local chest = interior and interior.spots[1] and interior.spots[1].coords

        if inside[src] ~= point.id or not chest or distanceTo(src, chest.x, chest.y, chest.z) > Config.CrewPointDistance + 1.5 then
            return fail('Vous êtes trop loin du coffre.')
        end
    elseif distanceTo(src, point.x, point.y, point.z) > Config.CrewPointDistance + 1.5 then
        return fail('Vous êtes trop loin du coffre.')
    end

    ox:forceOpenInventory(src, 'stash', point.stash)
    return { ok = true }
end)

-- Planque : entrée par la porte, dans le monde de la planque
lib.callback.register('lunatic_illegal:crewPropertyEnter', function(src, pointId)
    local point, err = pointOf(src, pointId, { property = true })

    if not point then
        return fail(err)
    end

    if not Config.BurglaryInteriors[point.interior] then
        return fail("Cette planque n'a pas d'intérieur.")
    end

    if distanceTo(src, point.x, point.y, point.z) > Config.CrewPointDistance + 1.5 then
        return fail('Vous êtes trop loin de la porte.')
    end

    inside[src] = point.id
    setBucket(src, Config.CrewPropertyBucket + point.id)
    return { ok = true, interior = point.interior }
end)

-- Sortie : la porte ; le joueur y est téléporté encore dans le monde de la planque, puis demande à en sortir
-- (crewPropertyLeave). Changer de monde avant d'avoir quitté l'intérieur fait planter le jeu.
lib.callback.register('lunatic_illegal:crewPropertyExit', function(src)
    local point = inside[src] and admin:getCrewPoint(inside[src])

    if not point then
        inside[src] = nil
        setBucket(src, 0)
        return fail("Vous n'êtes dans aucune planque.")
    end

    return { ok = true, x = point.x, y = point.y, z = point.z, h = point.h }
end)

lib.callback.register('lunatic_illegal:crewPropertyLeave', function(src)
    if inside[src] then
        inside[src] = nil
        setBucket(src, 0)
    end

    return true
end)

-- Sorti autrement (mort, téléporté) : retour dans le monde normal
CreateThread(function()
    while true do
        Wait(2000)

        for src, pointId in pairs(inside) do
            local point = admin:getCrewPoint(pointId)
            local interior = point and Config.BurglaryInteriors[point.interior]
            local ped = GetPlayerPed(src)

            if not ped or ped == 0 or not interior or #(GetEntityCoords(ped) - interior.entry.xyz) > 60.0 then
                inside[src] = nil
                setBucket(src, 0)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    inside[source] = nil
end)
