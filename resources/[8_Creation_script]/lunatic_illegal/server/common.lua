-- Outils communs aux fichiers serveur de lunatic_illegal.

-- Crew réel du joueur, lu dans lunatic_admin. Ne jamais se fier au statebag « crew » côté serveur :
-- un client peut écrire dans son propre statebag (il ne sert qu'à l'affichage côté client).
---@return { id: number, label: string, type: string, level: number, rank: number, leader: boolean }|nil
function CrewOf(src)
    local found, crew = pcall(function()
        return exports.lunatic_admin:getPlayerCrew(src)
    end)

    return found and crew or nil
end

-- A sur lui une tablette de son crew (marché noir, contrats)
function HasCrewTablet(src)
    local crew = CrewOf(src)

    if not crew then
        return false
    end

    for _, slot in pairs(exports.ox_inventory:Search(src, 'slots', Config.TabletItem) or {}) do
        if slot.metadata and slot.metadata.crew == crew.id then
            return true
        end
    end

    return false
end

-- Policiers en service : joueurs connectés dont le métier est une structure de type Police
function PolicePlayers()
    local list = {}

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        local found, structure = pcall(function() return exports.lunatic_admin:getStructure(xPlayer.getJob().name) end)

        if found and structure and structure.kind == 'public' and structure.type == 'police' then
            list[#list + 1] = xPlayer.source
        end
    end

    return list
end

---------------------------------------------------------------------
-- Arme en main (braquages) : « melee » (couteau, batte…) ou « firearm » ; les poings et les objets ne comptent pas
---------------------------------------------------------------------

-- Ni menaçants ni crédibles pour un braquage
local NOT_WEAPONS = {
    WEAPON_UNARMED = true, WEAPON_PETROLCAN = true, WEAPON_HAZARDCAN = true, WEAPON_FERTILIZERCAN = true, WEAPON_FIREEXTINGUISHER = true,
    WEAPON_BALL = true, WEAPON_SNOWBALL = true, WEAPON_FLARE = true, WEAPON_STUNGUN = true, WEAPON_STUNGUN_MP = true,
}

-- Hash en entier positif : joaat et GetSelectedPedWeapon ne rendent pas toujours le même signe
local function unsigned(hash)
    hash = tonumber(hash) or 0
    return hash < 0 and hash + 4294967296 or hash
end

local weaponClasses = nil -- hash -> 'melee' | 'firearm', lu dans ox_inventory (une arme avec munitions = arme à feu)

local function classes()
    if weaponClasses then
        return weaponClasses
    end

    weaponClasses = {}

    for name, item in pairs(exports.ox_inventory:Items() or {}) do
        if type(item) == 'table' and item.weapon and not item.throwable and not NOT_WEAPONS[name:upper()] then
            weaponClasses[unsigned(joaat(name))] = item.ammoname and 'firearm' or 'melee'
        end
    end

    return weaponClasses
end

-- Classe de l'arme que le joueur tient en main (nil : mains nues ou objet)
function WeaponClass(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end

    return classes()[unsigned(GetSelectedPedWeapon(ped))]
end

-- L'arme en main respecte-t-elle la règle du braquage ? (none, any, melee, firearm)
function WeaponAllowed(src, rule)
    if not rule or rule == 'none' then
        return true
    end

    local class = WeaponClass(src)
    return class ~= nil and (rule == 'any' or rule == class)
end

function WeaponRuleText(rule)
    if rule == 'firearm' then
        return 'Il vous faut une arme à feu en main.'
    elseif rule == 'melee' then
        return 'Il vous faut une arme blanche en main (couteau, batte…).'
    end

    return 'Il vous faut une arme en main (couteau, batte, arme à feu…).'
end
