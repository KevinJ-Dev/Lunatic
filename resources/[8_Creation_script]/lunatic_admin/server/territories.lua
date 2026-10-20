-- Illégal, étape 4 : territoires. Zones circulaires placées depuis le panel (tuile Illégal, onglet Territoires).
-- Le crew qui a le plus d'influence dans une zone (gagnée en vendant de la drogue, sur Config.TerritoryDays jours,
-- l'influence ancienne comptant de moins en moins) la tient dès qu'il atteint le seuil de la zone, et touche ses bonus.
-- Calcul côté serveur uniquement : toutes les Config.TerritoryRefresh secondes et peu après chaque vente dans une zone.
-- Diffusé dans GlobalState.lunaticTerritories (carte des membres de crews, lunatic_illegal).

Territories = {}

local WINDOW = Config.TerritoryDays * 86400
local LIMITS = { territories = 100, radiusMin = 25, radiusMax = 600, bonus = 200, influence = 100000 }

---@type table<number, table> territoires par id
local territories = {}
---@type table<number, { crew: number, score: number }[]> classement par territoire (dernier calcul)
local rankings = {}
---@type table<number, boolean> territoires à recalculer (vente récente dans la zone)
local dirty = {}
local loaded = false

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer l'illégal.")
end

local function positionOf(src)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z - 0.98 }
end

local function whole(value, min, max)
    value = tonumber(value)

    if not value or value ~= math.floor(value) or value < min or value > max then
        return nil
    end

    return value
end

local function load()
    territories = {}

    for _, row in ipairs(MySQL.query.await('SELECT * FROM `lunatic_territories`') or {}) do
        territories[tonumber(row.id)] = {
            id = tonumber(row.id), label = row.label,
            x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), radius = tonumber(row.radius),
            priceBonus = tonumber(row.price_bonus), xpBonus = tonumber(row.xp_bonus), minInfluence = tonumber(row.min_influence),
            active = tonumber(row.active) == 1, owner = tonumber(row.owner_crew), ownerSince = tonumber(row.owner_since),
            resetAt = tonumber(row.reset_at) or 0,
        }
    end
end

local function inside(t, x, y)
    return (x - t.x) ^ 2 + (y - t.y) ^ 2 <= t.radius ^ 2
end

-- Diffusion aux joueurs : zones actives et crew qui les tient
local function publish()
    local list = {}

    for _, t in pairs(territories) do
        if t.active then
            local owner = t.owner and Crews.basic(t.owner)

            list[#list + 1] = {
                id = t.id, label = t.label, x = t.x, y = t.y, radius = t.radius, priceBonus = t.priceBonus, xpBonus = t.xpBonus,
                owner = owner and { id = owner.id, label = owner.label } or nil,
            }
        end
    end

    table.sort(list, function(a, b) return a.id < b.id end)
    GlobalState.lunaticTerritories = list
end

local function notifyCrew(crewId, message, kind)
    for _, target in ipairs(Crews.onlineSources(crewId)) do
        TriggerClientEvent('esx:showNotification', target, message, kind or 'info')
    end
end

local function setOwner(t, owner)
    local previous = t.owner
    t.owner = owner
    t.ownerSince = owner and os.time() or nil

    -- (oxmysql n'accepte pas nil au milieu des paramètres : deux requêtes)
    if owner then
        MySQL.update.await('UPDATE `lunatic_territories` SET `owner_crew` = ?, `owner_since` = ? WHERE `id` = ?', { owner, t.ownerSince, t.id })
    else
        MySQL.update.await('UPDATE `lunatic_territories` SET `owner_crew` = NULL, `owner_since` = NULL WHERE `id` = ?', { t.id })
    end

    if previous and Crews.basic(previous) then
        notifyCrew(previous, ('Votre crew a perdu le territoire « %s ».'):format(t.label), 'error')
    end

    if owner then
        notifyCrew(owner, ('Votre crew contrôle maintenant le territoire « %s » !'):format(t.label), 'success')
    end
end

-- Influence de chaque crew dans la zone : gains des Config.TerritoryDays derniers jours (depuis la dernière remise à zéro),
-- pondérés de 1 (à l'instant) à 0 (fin de la période). Renvoie true si le crew qui tient la zone a changé.
local function compute(t)
    local now = os.time()
    local since = math.max(now - WINDOW, t.resetAt or 0)

    local rows = MySQL.query.await([[
        SELECT `crew_id`, SUM(`amount` * (1 - (? - `created_at`) / ?)) AS `score`
        FROM `lunatic_crew_influence`
        WHERE `created_at` > ? AND POW(`x` - ?, 2) + POW(`y` - ?, 2) <= ?
        GROUP BY `crew_id`
        ORDER BY `score` DESC
    ]], { now, WINDOW, since, t.x, t.y, t.radius * t.radius }) or {}

    local ranking = {}

    for _, row in ipairs(rows) do
        local crewId = tonumber(row.crew_id)
        local score = math.floor((tonumber(row.score) or 0) * 10 + 0.5) / 10

        if crewId and score > 0 and Crews.basic(crewId) then
            ranking[#ranking + 1] = { crew = crewId, score = score }
        end
    end

    rankings[t.id] = ranking

    local leader = ranking[1]
    local owner = t.active and leader and leader.score >= t.minInfluence and leader.crew or nil

    -- Égalité : le crew en place garde la zone
    if owner and t.owner and owner ~= t.owner then
        for _, entry in ipairs(ranking) do
            if entry.crew == t.owner and entry.score >= leader.score then
                owner = t.owner
            end
        end
    end

    if owner ~= t.owner then
        setOwner(t, owner)
        return true
    end

    return false
end

local function computeAll()
    for _, t in pairs(territories) do
        compute(t)
    end

    publish()
end

-- Appelé à chaque gain d'influence (export addCrewInfluence, server/drugs.lua) : recalcul des zones touchées
function Territories.touch(x, y)
    x, y = tonumber(x), tonumber(y)

    if not x or not y then
        return
    end

    for id, t in pairs(territories) do
        if t.active and inside(t, x, y) then
            dirty[id] = true
        end
    end
end

table.insert(Panel.readyHooks, function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lunatic_territories` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `label` VARCHAR(60) NOT NULL,
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `radius` INT NOT NULL DEFAULT 150,
            `price_bonus` INT NOT NULL DEFAULT 20,
            `xp_bonus` INT NOT NULL DEFAULT 20,
            `min_influence` INT NOT NULL DEFAULT 10,
            `active` TINYINT NOT NULL DEFAULT 1,
            `owner_crew` INT NULL DEFAULT NULL,
            `owner_since` BIGINT NULL DEFAULT NULL,
            `reset_at` BIGINT NOT NULL DEFAULT 0,
            `created_by` VARCHAR(80) NOT NULL DEFAULT '',
            `created_at` BIGINT NOT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Le calcul filtre l'influence par date (syntaxe MariaDB ; sans cet index, le calcul marche quand même)
    pcall(function()
        MySQL.query.await('CREATE INDEX IF NOT EXISTS `idx_lunatic_crew_influence_time` ON `lunatic_crew_influence` (`created_at`)')
    end)

    load()
    loaded = true
    computeAll()
end)

CreateThread(function()
    local nextFull = os.time() + Config.TerritoryRefresh

    while true do
        Wait(2000)

        if loaded then
            if os.time() >= nextFull then
                nextFull = os.time() + Config.TerritoryRefresh
                dirty = {}
                computeAll()
            elseif next(dirty) then
                local list = dirty
                dirty = {}
                local changed = false

                for id in pairs(list) do
                    if territories[id] and compute(territories[id]) then
                        changed = true
                    end
                end

                if changed then
                    publish()
                end
            end
        end
    end
end)

---------------------------------------------------------------------
-- Exports (lunatic_illegal)
---------------------------------------------------------------------

-- Territoire actif qui contient le point (le plus petit si plusieurs se chevauchent), pour les bonus de vente
exports('territoryAt', function(x, y)
    x, y = tonumber(x), tonumber(y)

    if not x or not y then
        return nil
    end

    local best

    for _, t in pairs(territories) do
        if t.active and inside(t, x, y) and (not best or t.radius < best.radius) then
            best = t
        end
    end

    return best and { id = best.id, label = best.label, owner = best.owner, priceBonus = best.priceBonus, xpBonus = best.xpBonus } or nil
end)

-- Territoires vus par un crew (menu /crew) : zones tenues d'abord, avec son influence et celle du crew en tête
exports('getCrewTerritories', function(crewId)
    crewId = tonumber(crewId)
    local list = {}

    for _, t in pairs(territories) do
        if t.active then
            local ranking = rankings[t.id] or {}
            local mine = 0

            for _, entry in ipairs(ranking) do
                if entry.crew == crewId then
                    mine = entry.score
                end
            end

            local owner = t.owner and Crews.basic(t.owner)

            list[#list + 1] = {
                label = t.label, owned = t.owner ~= nil and t.owner == crewId, owner = owner and owner.label or nil,
                influence = mine, leader = ranking[1] and ranking[1].score or 0, minInfluence = t.minInfluence,
                priceBonus = t.priceBonus, xpBonus = t.xpBonus,
            }
        end
    end

    table.sort(list, function(a, b)
        if a.owned ~= b.owned then
            return a.owned
        end

        return a.label < b.label
    end)

    return list
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

local function territoryFor(actor, id)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return nil, denied()
    end

    local t = territories[tonumber(id) or -1]

    if not t then
        return nil, Panel.fail('Territoire introuvable.')
    end

    return t
end

Panel.actions['territories.list'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local list = {}

    for _, t in pairs(territories) do
        local ranking = {}

        for index, entry in ipairs(rankings[t.id] or {}) do
            if index > 5 then
                break
            end

            local crew = Crews.basic(entry.crew)

            if crew then
                ranking[#ranking + 1] = { crew = crew.id, label = crew.label, color = crew.color, score = entry.score }
            end
        end

        local owner = t.owner and Crews.basic(t.owner)

        list[#list + 1] = {
            id = t.id, label = t.label, x = t.x, y = t.y, z = t.z, radius = t.radius,
            priceBonus = t.priceBonus, xpBonus = t.xpBonus, minInfluence = t.minInfluence, active = t.active,
            owner = owner and { id = owner.id, label = owner.label, color = owner.color } or nil, ownerSince = t.ownerSince,
            ranking = ranking,
        }
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return { ok = true, silent = true, territories = list, days = Config.TerritoryDays, refresh = Config.TerritoryRefresh }
end

Panel.actions['territories.save'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    local label = type(data.label) == 'string' and data.label:gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    local radius = whole(data.radius, LIMITS.radiusMin, LIMITS.radiusMax)
    local priceBonus = whole(data.priceBonus, 0, LIMITS.bonus)
    local xpBonus = whole(data.xpBonus, 0, LIMITS.bonus)
    local minInfluence = whole(data.minInfluence, 0, LIMITS.influence)

    if #label < 2 or #label > 60 then
        return Panel.fail('Le nom doit faire entre 2 et 60 caractères.')
    end

    if not radius then
        return Panel.fail(('Rayon : un nombre entier entre %d et %d mètres.'):format(LIMITS.radiusMin, LIMITS.radiusMax))
    end

    if not priceBonus or not xpBonus then
        return Panel.fail(('Bonus : un pourcentage entier entre 0 et %d.'):format(LIMITS.bonus))
    end

    if not minInfluence then
        return Panel.fail("Seuil d'influence : un nombre entier positif.")
    end

    local active = data.active ~= false
    local t

    if data.id then
        local err
        t, err = territoryFor(actor, data.id)

        if not t then
            return err
        end

        MySQL.update.await('UPDATE `lunatic_territories` SET `label` = ?, `radius` = ?, `price_bonus` = ?, `xp_bonus` = ?, `min_influence` = ?, `active` = ? WHERE `id` = ?', {
            label, radius, priceBonus, xpBonus, minInfluence, active and 1 or 0, t.id,
        })
    else
        local count = 0

        for _ in pairs(territories) do
            count = count + 1
        end

        if count >= LIMITS.territories then
            return Panel.fail(('Maximum %d territoires.'):format(LIMITS.territories))
        end

        local position = positionOf(src)

        if not position then
            return Panel.fail('Position introuvable.')
        end

        MySQL.insert.await('INSERT INTO `lunatic_territories` (`label`, `x`, `y`, `z`, `radius`, `price_bonus`, `xp_bonus`, `min_influence`, `active`, `created_by`, `created_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
            label, position.x, position.y, position.z, radius, priceBonus, xpBonus, minInfluence, active and 1 or 0, Staff.displayName(src), os.time(),
        })
    end

    load()
    computeAll()
    Logs.add(src, 'territories.save', nil, { label = label, operation = data.id and 'edit' or 'add' })

    return { ok = true, silent = true }
end

-- Recentre la zone sur la position du staff
Panel.actions['territories.move'] = function(src, actor, data)
    local t, err = territoryFor(actor, data.id)

    if not t then
        return err
    end

    local position = positionOf(src)

    if not position then
        return Panel.fail('Position introuvable.')
    end

    MySQL.update.await('UPDATE `lunatic_territories` SET `x` = ?, `y` = ?, `z` = ? WHERE `id` = ?', { position.x, position.y, position.z, t.id })
    load()
    computeAll()
    Logs.add(src, 'territories.save', nil, { label = t.label, operation = 'move' })

    return { ok = true, silent = true }
end

-- Remise à zéro : l'influence gagnée avant maintenant ne compte plus dans cette zone
Panel.actions['territories.reset'] = function(src, actor, data)
    local t, err = territoryFor(actor, data.id)

    if not t then
        return err
    end

    t.resetAt = os.time()
    MySQL.update.await('UPDATE `lunatic_territories` SET `reset_at` = ? WHERE `id` = ?', { t.resetAt, t.id })
    compute(t)
    publish()
    Logs.add(src, 'territories.reset', nil, { label = t.label })

    return { ok = true, silent = true }
end

Panel.actions['territories.delete'] = function(src, actor, data)
    local t, err = territoryFor(actor, data.id)

    if not t then
        return err
    end

    MySQL.update.await('DELETE FROM `lunatic_territories` WHERE `id` = ?', { t.id })
    rankings[t.id] = nil
    load()
    publish()
    Logs.add(src, 'territories.delete', nil, { label = t.label })

    return { ok = true, silent = true }
end

Panel.actions['territories.tp'] = function(src, actor, data)
    local t, err = territoryFor(actor, data.id)

    if not t then
        return err
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(t.x, t.y, t.z + 1.0))
    return { ok = true, silent = true }
end

-- Vue staff : affiche les zones sur la carte du staff (lunatic_illegal), même sans crew
Panel.actions['territories.staffView'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'illegal.manage') then
        return denied()
    end

    TriggerClientEvent('lunatic_illegal:staffTerritories', src, data.enabled == true)
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Territoires chargé.')
