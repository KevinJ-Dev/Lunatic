-- Lot C : prison staff (hors RP).
-- La peine ne s'écoule que joueur connecté ; elle reprend à la reconnexion. Le serveur décompte le temps,
-- surveille la position et relâche le joueur : le client ne fait qu'afficher et téléporter.

---@type table<string, {sanctionId:number, remaining:number, reason:string}> peines en cours, par licence
local jails = {}
---@type table<number, string> joueurs connectés en prison : source -> licence
local inside = {}
local loaded = false
local sendInside -- défini plus bas, utilisé au chargement

local TICK = 5         -- secondes entre deux décomptes
local SAVE_EVERY = 30  -- secondes entre deux sauvegardes du temps restant

local function save(license)
    local jail = jails[license]

    if jail then
        MySQL.update('UPDATE `lunatic_admin_jail` SET `remaining` = ? WHERE `license` = ?', { math.max(0, math.floor(jail.remaining)), license })
    end
end

table.insert(Panel.readyHooks, function()
    local rows = MySQL.query.await('SELECT `license`, `sanction_id`, `remaining`, `reason` FROM `lunatic_admin_jail`') or {}

    for _, row in ipairs(rows) do
        jails[row.license] = { sanctionId = row.sanction_id, remaining = tonumber(row.remaining) or 0, reason = row.reason }
    end

    loaded = true
    print(('[lunatic_admin] Module Prison chargé : %d peine(s) en cours.'):format(#rows))

    -- Redémarrage de la resource : les détenus déjà connectés retournent en cellule
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local license = GetPlayerIdentifierByType(src, 'license')

        if license and jails[license] then
            sendInside(src, license)
        end
    end
end)

---------------------------------------------------------------------
-- Entrée, sortie
---------------------------------------------------------------------

function sendInside(src, license)
    local jail = jails[license]

    if not jail then
        return
    end

    inside[src] = license
    TriggerClientEvent('lunatic_admin:jail', src, math.floor(jail.remaining), jail.reason)
end

local function release(license, message)
    local jail = jails[license]

    if not jail then
        return
    end

    jails[license] = nil
    MySQL.update('DELETE FROM `lunatic_admin_jail` WHERE `license` = ?', { license })

    for src, lic in pairs(inside) do
        if lic == license then
            inside[src] = nil
            TriggerClientEvent('lunatic_admin:unjail', src)
            Panel.notify(src, message or 'Vous avez purgé votre peine : vous êtes libre.', 'success')
        end
    end
end

-- Utilisés par server/sanctions.lua (révocation) et la fiche joueur
function Panel.jailRemaining(sanctionId)
    for _, jail in pairs(jails) do
        if jail.sanctionId == sanctionId then
            return math.floor(jail.remaining)
        end
    end
end

function Panel.releaseJailBySanction(sanctionId)
    for license, jail in pairs(jails) do
        if jail.sanctionId == sanctionId then
            release(license, 'Votre peine a été levée par le staff.')
            return
        end
    end
end

function Panel.jailOf(src)
    local license = GetPlayerIdentifierByType(src, 'license')
    local jail = license and jails[license]

    return jail and { remaining = math.floor(jail.remaining), reason = jail.reason } or nil
end

-- Reconnexion d'un joueur qui n'a pas fini sa peine
AddEventHandler('esx:playerLoaded', function(playerId)
    local src = tonumber(playerId)
    local license = src and GetPlayerIdentifierByType(src, 'license')

    if not license then
        return
    end

    local timeout = GetGameTimer() + 15000

    while not loaded and GetGameTimer() < timeout do
        Wait(200)
    end

    if jails[license] then
        Wait(3000) -- laisse le personnage apparaître
        sendInside(src, license)
        Panel.notify(src, 'Vous reprenez votre peine de prison staff.', 'error')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local license = inside[src]

    if license then
        inside[src] = nil
        save(license)
    end
end)

---------------------------------------------------------------------
-- Décompte, surveillance de la zone, sauvegarde
---------------------------------------------------------------------

CreateThread(function()
    local sinceSave = 0

    while true do
        Wait(TICK * 1000)
        sinceSave = sinceSave + TICK

        for src, license in pairs(inside) do
            local jail = jails[license]

            if not jail or not GetPlayerName(src) then
                inside[src] = nil
            else
                jail.remaining = jail.remaining - TICK

                if jail.remaining <= 0 then
                    release(license)
                else
                    -- Évasion (ou téléportation par quelqu'un) : retour dans la cour
                    local ped = GetPlayerPed(src)

                    if ped and ped ~= 0 and #(GetEntityCoords(ped) - Config.Jail.spawn) > Config.Jail.radius + 15.0 then
                        TriggerClientEvent('lunatic_admin:jailBack', src)
                    end

                    if sinceSave >= SAVE_EVERY then
                        TriggerClientEvent('lunatic_admin:jailSync', src, math.floor(jail.remaining))
                    end
                end
            end
        end

        if sinceSave >= SAVE_EVERY then
            sinceSave = 0

            for _, license in pairs(inside) do
                save(license)
            end
        end
    end
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

Panel.actions['sanction.jail'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'sanctions.jail') then
        return Panel.fail("Vous n'avez pas la permission de mettre en prison.")
    end

    local target = tonumber(data.serverId)

    if not target or not GetPlayerName(target) then
        return Panel.fail("Ce joueur n'est plus connecté.")
    end

    if target == src then
        return Panel.fail('Action impossible sur vous-même.')
    end

    local license = GetPlayerIdentifierByType(target, 'license')

    if Panel.sanctions.isProtectedLicense(actor, license) then
        return Panel.fail('Ce membre du staff a un rang égal ou supérieur au vôtre.')
    end

    if jails[license] then
        return Panel.fail(('Ce joueur est déjà en prison (%d min restantes).'):format(math.ceil(jails[license].remaining / 60)))
    end

    local minutes = tonumber(data.minutes)

    if not minutes or minutes ~= math.floor(minutes) or minutes < 1 or minutes > Config.Jail.maxMinutes then
        return Panel.fail(('Durée invalide : de 1 à %d minutes.'):format(Config.Jail.maxMinutes))
    end

    local reason = Panel.sanctions.cleanReason(data.reason)

    if not reason then
        return Panel.fail(('La raison doit faire entre %d et %d caractères.'):format(Config.SanctionReasonMin, Config.SanctionReasonMax))
    end

    local sanction = Panel.sanctions.create('jail', Panel.sanctions.onlineTarget(target), src, actor, reason, nil)

    jails[license] = { sanctionId = sanction.id, remaining = minutes * 60, reason = reason }
    MySQL.insert.await('INSERT INTO `lunatic_admin_jail` (`license`, `sanction_id`, `remaining`, `reason`) VALUES (?, ?, ?, ?)', {
        license, sanction.id, minutes * 60, reason,
    })

    sendInside(target, license)
    Panel.notify(target, ('Vous êtes en prison staff pour %d minute(s) : %s'):format(minutes, reason), 'error')
    Logs.add(src, 'sanction.jail', sanction.name, { id = sanction.id, minutes = minutes, reason = reason })

    return { ok = true, silent = true, id = sanction.id }
end

Panel.actions['sanction.unjail'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'sanctions.jail') then
        return Panel.fail("Vous n'avez pas la permission de libérer.")
    end

    local target = tonumber(data.serverId)
    local license = target and GetPlayerIdentifierByType(target, 'license')
    local jail = license and jails[license]

    if not jail then
        return Panel.fail("Ce joueur n'est pas en prison.")
    end

    MySQL.update.await('UPDATE `lunatic_admin_sanctions` SET `revoked_at` = ?, `revoked_by` = ?, `revoke_reason` = ? WHERE `id` = ?', {
        os.time(), Staff.displayName(src), 'Libéré depuis le panel', jail.sanctionId,
    })

    release(license, 'Le staff vous a libéré de prison.')
    Logs.add(src, 'sanction.unjail', Staff.displayName(target), { id = jail.sanctionId })

    return { ok = true, silent = true }
end
