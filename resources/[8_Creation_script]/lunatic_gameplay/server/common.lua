-- Outils serveur partagés par les systèmes de lunatic_gameplay

-- Réglages d'une section de la tuile Fonctionnalités (lunatic_admin), table vide sans le panel
function FeaturesOf(section)
    local features = GlobalState.lunaticFeatures
    return features and features[section] or {}
end

-- Journal du panel staff (tuile Logs) ; sans effet si lunatic_admin est arrêté
function GameLog(category, level, src, action, target, details)
    pcall(function() exports.lunatic_admin:log(category, level, src, action, target, details) end)
end

function Notify(target, message, kind)
    TriggerClientEvent('esx:showNotification', target, message, kind or 'info')
end

-- Service public du métier du joueur (tuile Services publics), nil sinon
function StructureOf(xPlayer)
    local job = xPlayer and xPlayer.getJob()

    if not job or GetResourceState('lunatic_admin') ~= 'started' then
        return nil
    end

    local ok, structure = pcall(function() return exports.lunatic_admin:getStructure(job.name) end)
    return ok and structure or nil
end
