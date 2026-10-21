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
