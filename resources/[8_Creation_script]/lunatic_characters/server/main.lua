-- Sélection de personnage : ESX en mode multi-personnages (identifiant « charN:<licence> »).
-- Le serveur décide de tout : emplacements autorisés (abonnement + ajouts du staff), personnage chargé, changement en jeu.

local selecting = {}  -- [source] = true : à l'écran de sélection
local lastSwitch = {} -- [source] = horodatage du dernier changement de personnage

local function licenseOf(src)
    local ok, identifier = pcall(ESX.GetIdentifier, src)
    return ok and identifier or nil
end

-- Emplacements autorisés : 1 par défaut, plus selon l'abonnement (lunatic_admin), plus ceux ajoutés par le staff
local function slotCount(src)
    local slots = Config.Slots.default

    if GetResourceState('lunatic_admin') == 'started' then
        local ok, premium = pcall(function() return exports.lunatic_admin:getPremium(src) end)

        if ok and type(premium) == 'table' then
            slots = premium.tier == 'premium_plus' and Config.Slots.premium_plus or Config.Slots.premium
        end
    end

    local extra = MySQL.scalar.await('SELECT `extra` FROM `lunatic_character_slots` WHERE `license` = ?', { licenseOf(src) })
    return math.max(1, math.min(Config.Slots.max, slots + (tonumber(extra) or 0)))
end

-- Personnages du compte (emplacement, nom, métier, argent)
local function characters(src)
    local license = licenseOf(src)

    if not license then
        return {}
    end

    local rows = MySQL.query.await(
        'SELECT `identifier`, `firstname`, `lastname`, `sex`, `dateofbirth`, `job`, `job_grade`, `accounts` FROM `users` WHERE `identifier` LIKE ?',
        { 'char%:' .. license }
    ) or {}

    local jobs = ESX.GetJobs() or {}
    local list = {}

    for _, row in ipairs(rows) do
        local slot = tonumber(row.identifier:match('^char(%d+):'))

        -- LIKE accepte « _ » comme joker : on revérifie que la fin est exactement la licence
        if slot and row.identifier:sub(-#license - 1) == ':' .. license then
            local ok, accounts = pcall(json.decode, row.accounts or '')
            accounts = ok and type(accounts) == 'table' and accounts or {}
            local job = jobs[row.job]
            local grade = job and job.grades and job.grades[tostring(row.job_grade)]

            list[#list + 1] = {
                slot = slot,
                firstname = row.firstname, lastname = row.lastname, sex = row.sex, dateofbirth = row.dateofbirth,
                job = job and job.label or row.job, grade = grade and grade.label or nil,
                money = tonumber(accounts.money) or 0, bank = tonumber(accounts.bank) or 0,
            }
        end
    end

    table.sort(list, function(a, b) return a.slot < b.slot end)
    return list
end

-- Connexion : identifiant requis, migration terminée, pas de session déjà ouverte sur ce compte
AddEventHandler('playerConnecting', function(_, _, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)

    local license = licenseOf(src)

    if not license then
        return deferrals.done("Impossible de lire votre licence Rockstar : relancez FiveM puis reconnectez-vous.")
    end

    if not Migration.done then
        return deferrals.done("Le serveur termine une mise à jour des personnages : reconnectez-vous dans un instant.")
    end

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        if xPlayer.identifier:sub(-#license - 1) == ':' .. license and GetPlayerPing(xPlayer.source) > 0 then
            return deferrals.done('Ce compte est déjà connecté au serveur.')
        end
    end

    deferrals.done()
end)

-- Ouverture de l'écran : le joueur attend seul dans une instance privée
RegisterNetEvent('lunatic_characters:open', function()
    local src = source

    if ESX.GetPlayerFromId(src) then
        return
    end

    selecting[src] = true
    SetPlayerRoutingBucket(src, 7000 + src)
end)

lib.callback.register('lunatic_characters:list', function(src)
    if not selecting[src] then
        return nil
    end

    return { characters = characters(src), slots = slotCount(src), tiers = Config.Slots }
end)

-- Jouer un personnage (ou créer celui d'un emplacement vide) ; renvoie { ok = true } ou { error = '…' }
lib.callback.register('lunatic_characters:play', function(src, slot)
    slot = math.tointeger(tonumber(slot))

    if not selecting[src] or ESX.GetPlayerFromId(src) then
        return { error = "La sélection n'est pas ouverte." }
    end

    if not Migration.done then
        return { error = 'Mise à jour des personnages en cours, réessayez dans un instant.' }
    end

    if not slot or slot < 1 or slot > slotCount(src) then
        return { error = 'Emplacement verrouillé.' }
    end

    local exists = false

    for _, character in ipairs(characters(src)) do
        if character.slot == slot then
            exists = true
        end
    end

    selecting[src] = nil
    SetPlayerRoutingBucket(src, 0)

    -- ESX charge le personnage (ou le crée sans identité : lunatic_creator ouvre alors la création)
    if exists then
        TriggerEvent('esx:onPlayerJoined', src, 'char' .. slot)
    else
        TriggerEvent('esx:onPlayerJoined', src, 'char' .. slot, {})
    end

    return { ok = true }
end)

-- Changer de personnage en jeu : ESX sauvegarde et décharge le personnage, le client revient à la sélection
RegisterNetEvent('lunatic_characters:switch', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or Player(src).state.lunaticCreating then
        return
    end

    local now = os.time()

    if (lastSwitch[src] or 0) > now - Config.SwitchCooldown then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = ('Attendez %d s avant de changer à nouveau de personnage.'):format(lastSwitch[src] + Config.SwitchCooldown - now) })
        return
    end

    lastSwitch[src] = now
    TriggerEvent('esx:playerLogout', src)
end)

AddEventHandler('playerDropped', function()
    selecting[source] = nil
    lastSwitch[source] = nil
end)
