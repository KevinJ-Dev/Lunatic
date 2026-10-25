-- Identité du personnage (remplace esx_identity) : prénom, nom, date de naissance, sexe, taille et nationalité.
-- Le serveur décide seul qui doit créer son personnage, revérifie tout ce que l'interface envoie et l'enregistre.
-- ESX relit lui-même firstname / lastname / dateofbirth / sex / height dans `users` à chaque connexion.

Identity = {
    pending = {},  -- [source] = true : identité à créer (ouvert par le serveur uniquement)
    creating = {}, -- [source] = true : joueur dans la pièce de création (instance privée)
    arrival = {},  -- [source] = { identifier, coords } : identité validée, photo et arrivée en cours
}

local DRAFT_MAX = 60000 -- taille maximale d'un brouillon encodé (caractères)
local draftSaved = {}   -- [source] = horodatage du dernier brouillon (limite d'envoi)

local nationalities = {}
for _, name in ipairs(Config.Nationalities) do
    nationalities[name] = true
end

---------------------------------------------------------------------
-- Vérifications
---------------------------------------------------------------------

-- Lettres (accents compris), séparées par un espace, un tiret ou une apostrophe ; nil si refusé
local function cleanName(value)
    if type(value) ~= 'string' then
        return nil
    end

    local name = value:gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(name)

    if not length or length < Config.NameLength.min or length > Config.NameLength.max then
        return nil
    end

    local ok, valid = pcall(function()
        local afterSeparator = true -- pas de séparateur en premier

        for _, code in utf8.codes(name) do
            local letter = (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
                or (code >= 0xC0 and code <= 0xFF and code ~= 0xD7 and code ~= 0xF7)

            if letter then
                afterSeparator = false
            elseif (code == 32 or code == 45 or code == 39) and not afterSeparator then
                afterSeparator = true
            else
                return false
            end
        end

        return not afterSeparator -- ni séparateur en dernier
    end)

    if not ok or not valid then
        return nil
    end

    -- Majuscule au début et après un séparateur (Jean-Pierre, D'Artagnan)
    return (name:lower():gsub('^%l', string.upper):gsub("([%s%-'])(%l)", function(separator, letter)
        return separator .. letter:upper()
    end))
end

-- Date JJ/MM/AAAA existante et âge dans les bornes ; renvoie la date au format JJ/MM/AAAA
local function cleanBirth(value)
    if type(value) ~= 'string' then
        return nil
    end

    local day, month, year = value:match('^(%d%d?)/(%d%d?)/(%d%d%d%d)$')
    day, month, year = tonumber(day), tonumber(month), tonumber(year)

    if not day or month < 1 or month > 12 then
        return nil
    end

    local leap = (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
    local days = { 31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

    if day < 1 or day > days[month] then
        return nil
    end

    local now = os.date('*t')
    local age = now.year - year

    if now.month < month or (now.month == month and now.day < day) then
        age = age - 1
    end

    if age < Config.Age.min or age > Config.Age.max then
        return nil
    end

    return ('%02d/%02d/%04d'):format(day, month, year)
end

---------------------------------------------------------------------
-- Données du joueur
---------------------------------------------------------------------

local FIELDS = { 'firstName', 'lastName', 'dateofbirth', 'sex', 'height' }

-- Applique l'identité au joueur connecté (xPlayer, state bags, client) ; identity = nil pour l'effacer
local function setPlayerData(xPlayer, identity)
    local src = xPlayer.source
    local state = Player(src).state
    local name = identity and ('%s %s'):format(identity.firstName, identity.lastName) or GetPlayerName(src)

    xPlayer.setName(name)
    state:set('name', name, true)

    for _, key in ipairs(FIELDS) do
        local value = identity and identity[key] or nil
        xPlayer.set(key, value)
        state:set(key, value, true)
    end

    TriggerClientEvent('lunatic_creator:setPlayerData', src, identity, name)
end

local function needsIdentity(identifier)
    local firstname = MySQL.scalar.await('SELECT `firstname` FROM `users` WHERE `identifier` = ?', { identifier })
    return not firstname or firstname == ''
end

-- Ouvre la création de personnage au joueur
local function start(playerId, countdown)
    Identity.pending[playerId] = true
    -- Lu par lunatic_admin (pas de photo automatique) et novyra_spawn (pas d'écran d'entrée)
    Player(playerId).state:set('lunaticCreating', true, true)
    TriggerClientEvent('lunatic_creator:start', playerId, countdown == true)
end

local function checkPlayer(playerId, xPlayer)
    if xPlayer and needsIdentity(xPlayer.getIdentifier()) then
        start(playerId)
    end
end

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    checkPlayer(playerId, xPlayer)
end)

-- Redémarrage de la resource : les joueurs déjà connectés sans identité retrouvent la création
MySQL.ready(function()
    Wait(2000)

    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        checkPlayer(xPlayer.source, xPlayer)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local arrival = Identity.arrival[src]

    Identity.pending[src] = nil
    Identity.arrival[src] = nil
    draftSaved[src] = nil

    -- Parti pendant la photo ou l'arrivée : à la reconnexion, il apparaît au lieu choisi et non dans la pièce
    -- (après la sauvegarde d'ESX, qui enregistre la position de la pièce)
    if arrival then
        SetTimeout(4000, function()
            local c = arrival.coords
            MySQL.update.await('UPDATE `users` SET `position` = ? WHERE `identifier` = ?', {
                json.encode({ x = c.x, y = c.y, z = c.z, heading = c.w }), arrival.identifier,
            })
        end)
    end
end)

---------------------------------------------------------------------
-- Brouillon : reprise de la création après un crash ou une déconnexion
---------------------------------------------------------------------

local function deleteDraft(identifier)
    MySQL.update.await('DELETE FROM `lunatic_character_draft` WHERE `identifier` = ?', { identifier })
end

lib.callback.register('lunatic_creator:getDraft', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not Identity.pending[src] then
        return nil
    end

    local data = MySQL.scalar.await('SELECT `data` FROM `lunatic_character_draft` WHERE `identifier` = ?', { xPlayer.getIdentifier() })
    local ok, draft = pcall(json.decode, data or '')

    return ok and type(draft) == 'table' and draft or nil
end)

lib.callback.register('lunatic_creator:saveDraft', function(src, data)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not Identity.pending[src] or not Identity.creating[src] or type(data) ~= 'table' then
        return false
    end

    -- Au plus un brouillon par seconde et par joueur
    if (draftSaved[src] or 0) > GetGameTimer() - 1000 then
        return false
    end

    draftSaved[src] = GetGameTimer()

    local draft = {
        step = math.tointeger(tonumber(data.step) or 0) or 0,
        identity = type(data.identity) == 'table' and data.identity or nil,
        appearance = type(data.appearance) == 'table' and data.appearance or nil,
    }
    local ok, encoded = pcall(json.encode, draft)

    if not ok or #encoded > DRAFT_MAX then
        return false
    end

    MySQL.query.await('INSERT INTO `lunatic_character_draft` (`identifier`, `data`, `updated_at`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `data` = VALUES(`data`), `updated_at` = VALUES(`updated_at`)', {
        xPlayer.getIdentifier(), encoded, os.time(),
    })

    return true
end)

---------------------------------------------------------------------
-- Enregistrement (fin de la création)
---------------------------------------------------------------------

-- Renvoie { ok = true } ou { error = 'message' }
lib.callback.register('lunatic_creator:registerIdentity', function(src, data)
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not Identity.pending[src] or not Identity.creating[src] then
        return { error = "La création de personnage n'est pas ouverte." }
    end

    if type(data) ~= 'table' then
        return { error = 'Identité incomplète.' }
    end

    local firstName, lastName = cleanName(data.firstname), cleanName(data.lastname)
    local birth = cleanBirth(data.dateofbirth)
    local height = tonumber(data.height)
    height = height and math.tointeger(height)
    local sex = (data.sex == 'm' or data.sex == 'f') and data.sex or nil

    if not firstName then
        return { error = 'Prénom invalide.' }
    elseif not lastName then
        return { error = 'Nom invalide.' }
    elseif not birth then
        return { error = ('Date de naissance invalide (de %d à %d ans).'):format(Config.Age.min, Config.Age.max) }
    elseif not height or height < Config.Height.min or height > Config.Height.max then
        return { error = 'Taille invalide.' }
    elseif not sex then
        return { error = 'Genre invalide.' }
    elseif type(data.nationality) ~= 'string' or not nationalities[data.nationality] then
        return { error = 'Choisissez une nationalité dans la liste.' }
    end

    local spawn = CreatorSpawns()[math.tointeger(tonumber(data.spawn) or 0) or 0]

    if not spawn then
        return { error = "Choisissez un lieu d'apparition." }
    end

    local identifier = xPlayer.getIdentifier()

    -- Une identité déjà enregistrée ne se remplace pas (il faut « Recréer » depuis le panel)
    if not needsIdentity(identifier) then
        Identity.pending[src] = nil
        return { error = 'Ce personnage a déjà une identité.' }
    end

    local identity = { firstName = firstName, lastName = lastName, dateofbirth = birth, sex = sex, height = height }

    MySQL.update.await('UPDATE `users` SET `firstname` = ?, `lastname` = ?, `dateofbirth` = ?, `sex` = ?, `height` = ? WHERE `identifier` = ?', {
        firstName, lastName, birth, sex, height, identifier,
    })
    MySQL.query.await('INSERT INTO `lunatic_character_info` (`identifier`, `nationality`, `created_at`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `nationality` = VALUES(`nationality`), `created_at` = VALUES(`created_at`)', {
        identifier, data.nationality, os.time(),
    })

    setPlayerData(xPlayer, identity)
    Identity.pending[src] = nil
    Identity.arrival[src] = { identifier = identifier, coords = spawn.coords }
    deleteDraft(identifier)

    return { ok = true }
end)

---------------------------------------------------------------------
-- Exports
---------------------------------------------------------------------

-- Efface l'identité et l'apparence d'un joueur connecté et le renvoie à la création (« Recréer » du panel).
-- Seules les resources du serveur peuvent appeler un export : aucun joueur ne peut le déclencher.
exports('resetIdentity', function(playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)

    if not xPlayer then
        return false
    end

    MySQL.update.await('UPDATE `users` SET `firstname` = NULL, `lastname` = NULL, `dateofbirth` = NULL, `sex` = NULL, `height` = NULL, `skin` = NULL WHERE `identifier` = ?', {
        xPlayer.getIdentifier(),
    })

    setPlayerData(xPlayer, nil)
    deleteDraft(xPlayer.getIdentifier())
    start(playerId, true)
    return true
end)

-- Lieux d'apparition de la config (proposés par le panel staff tant qu'aucun n'y est réglé)
exports('getDefaultSpawns', function()
    local list = {}

    for _, spawn in ipairs(Config.Spawns) do
        list[#list + 1] = { group = spawn.group, label = spawn.label, image = spawn.image or '', enabled = true, x = spawn.coords.x, y = spawn.coords.y, z = spawn.coords.z, h = spawn.coords.w }
    end

    return list
end)

exports('getNationality', function(identifier)
    return MySQL.scalar.await('SELECT `nationality` FROM `lunatic_character_info` WHERE `identifier` = ?', { identifier })
end)
