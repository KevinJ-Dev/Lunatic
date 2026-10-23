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

---------------------------------------------------------------------
-- Missions du panel (page Missions) : réglages, contrôles communs, gain et alerte police
---------------------------------------------------------------------

-- Réglages complets d'une mission : communs, avancés et butin (nil si lunatic_admin ne répond pas)
function MissionSettings(id)
    local found, value = pcall(function() return exports.lunatic_admin:getMissionSettings(id) end)
    return found and value or nil
end

-- Pourquoi la mission ne peut pas commencer (activée, policiers, crew et level), ou nil
function MissionProblem(src, m)
    if not m or not m.enabled then
        return "Ce n'est pas le moment."
    end

    if #PolicePlayers() < (m.police or 0) then
        return "Trop risqué : il n'y a pas assez de policiers en ville."
    end

    if m.levelRequired then
        local crew = CrewOf(src)

        if not crew then
            return "Ce coup-là, c'est pour les crews."
        end

        if crew.level < (m.minLevel or 1) then
            return ('Votre crew doit être level %d pour ce coup.'):format(m.minLevel)
        end
    end
end

function MoneyText(amount)
    return ('%s $'):format(tostring(math.floor(amount or 0)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', ''))
end

-- Mission réussie : gain (60 à 140 % du gain réglé) sur le compte donné, butin, XP et influence si le joueur a un crew
function MissionPayout(src, m, coords, origin, account)
    local ox = exports.ox_inventory
    local reward = math.floor((m.reward or 0) * math.random(60, 140) / 100)
    local xPlayer = ESX.GetPlayerFromId(src)

    if xPlayer and reward > 0 then
        xPlayer.addAccountMoney(account, reward, origin)
    end

    local loot = {}

    for _, entry in ipairs(m.loot or {}) do
        if math.random(100) <= entry.chance then
            local count = math.random(entry.min, entry.max)

            if ox:CanCarryItem(src, entry.item, count) and ox:AddItem(src, entry.item, count) then
                local item = ox:Items(entry.item)
                loot[#loot + 1] = ('%d × %s'):format(count, item and item.label or entry.item)
            end
        end
    end

    local crew = CrewOf(src)

    if crew then
        if (m.xp or 0) > 0 then
            pcall(function() exports.lunatic_admin:addCrewXp(crew.id, m.xp) end)
        end

        if (m.influence or 0) > 0 then
            pcall(function() exports.lunatic_admin:addCrewInfluence(crew.id, m.influence, coords.x, coords.y, origin) end)
        end
    end

    return reward, loot
end

-- Alerte aux policiers en service (position floutée de « blur » mètres)
function AlertPolice(coords, label, blur)
    blur = blur or 0

    for _, officer in ipairs(PolicePlayers()) do
        TriggerClientEvent('lunatic_illegal:heistAlert', officer, { x = coords.x + math.random(-blur, blur), y = coords.y + math.random(-blur, blur), label = label })
    end
end

function IsPolice(src)
    for _, officer in ipairs(PolicePlayers()) do
        if officer == src then
            return true
        end
    end

    return false
end
