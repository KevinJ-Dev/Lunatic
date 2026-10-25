-- Carte « Personnages » des fiches joueur : personnages du compte (lunatic_characters), emplacements en plus,
-- archivage et récupération. Les opérations sur la base sont faites par lunatic_characters (exports).

local function charactersApi()
    return GetResourceState('lunatic_characters') == 'started' and exports.lunatic_characters or nil
end

-- Licence du compte visé : joueur connecté (serverId) ou licence lue dans la fiche hors ligne
local function licenseFrom(data)
    if tonumber(data.serverId) then
        return GetPlayerIdentifierByType(tonumber(data.serverId), 'license')
    end

    local license = type(data.license) == 'string' and data.license or nil
    return license and license:match('^license:%x+$') and #license <= 60 and license or nil
end

-- Un compte d'un membre du staff de rang égal ou supérieur n'est pas modifiable (soi-même autorisé)
local function protected(src, actor, license)
    local member = Staff.get(license)
    local rank = member and Ranks.get(member.rankId)
    return rank ~= nil and rank.level >= actor.level and license ~= GetPlayerIdentifierByType(src, 'license')
end

local function call(fn, ...)
    local api = charactersApi()

    if not api then
        return false, "lunatic_characters n'est pas démarré."
    end

    local args = { ... }
    local ok, done, value = pcall(function() return api[fn](api, table.unpack(args)) end)

    if not ok then
        print(('[lunatic_admin] lunatic_characters:%s a échoué : %s'):format(fn, tostring(done)))
        return false, 'Opération impossible (voir la console).'
    end

    return done, value
end

Panel.actions['characters.get'] = function(_, actor, data)
    if not Ranks.hasPermission(actor, 'players.view') then
        return Panel.fail("Vous n'avez pas la permission.")
    end

    local license = licenseFrom(data)

    if not license then
        return Panel.fail('Joueur introuvable.')
    end

    local api = charactersApi()

    if not api then
        return Panel.fail("lunatic_characters n'est pas démarré.")
    end

    local ok, list = pcall(function() return api:getCharacters(license) end)

    if not ok or type(list) ~= 'table' then
        return Panel.fail('Personnages introuvables.')
    end

    list.ok, list.silent = true, true
    return list
end

local function manageTarget(src, actor, data)
    if not Ranks.hasPermission(actor, 'players.characters') then
        return nil, Panel.fail("Vous n'avez pas la permission de gérer les personnages.")
    end

    local license = licenseFrom(data)

    if not license then
        return nil, Panel.fail('Joueur introuvable.')
    end

    if protected(src, actor, license) then
        return nil, Panel.fail('Ce membre du staff a un rang égal ou supérieur au vôtre.')
    end

    return license
end

Panel.actions['characters.slots'] = function(src, actor, data)
    local license, err = manageTarget(src, actor, data)

    if not license then
        return err
    end

    local ok, message = call('setExtraSlots', license, data.extra)

    if not ok then
        return Panel.fail(message)
    end

    Logs.add(src, 'characters.slots', nil, { license = license, extra = tonumber(data.extra) })
    return { ok = true, silent = true }
end

-- L'identifiant doit appartenir au compte visé (pas d'action sur le personnage d'un autre)
local function ownIdentifier(license, identifier)
    return type(identifier) == 'string' and #identifier <= 60 and Util.licenseOf(identifier) == license
end

Panel.actions['characters.archive'] = function(src, actor, data)
    local license, err = manageTarget(src, actor, data)

    if not license then
        return err
    end

    local reason = Util.cleanText(data.reason, 3, 200)

    if not reason then
        return Panel.fail('La raison est obligatoire (3 caractères minimum).')
    end

    if not ownIdentifier(license, data.identifier) then
        return Panel.fail('Personnage introuvable.')
    end

    local ok, value = call('archiveCharacter', data.identifier)

    if not ok then
        return Panel.fail(value)
    end

    Logs.add(src, 'characters.archive', nil, { license = license, identifier = data.identifier, archived = value, reason = reason })
    return { ok = true, silent = true }
end

Panel.actions['characters.restore'] = function(src, actor, data)
    local license, err = manageTarget(src, actor, data)

    if not license then
        return err
    end

    if not ownIdentifier(license, data.identifier) then
        return Panel.fail('Personnage archivé introuvable.')
    end

    local ok, value = call('restoreCharacter', data.identifier, data.slot)

    if not ok then
        return Panel.fail(value)
    end

    Logs.add(src, 'characters.restore', nil, { license = license, identifier = value })
    return { ok = true, silent = true }
end
