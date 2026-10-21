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
