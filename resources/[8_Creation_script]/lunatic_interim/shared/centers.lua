-- Job Centers : ceux réglés dans le panel staff (Autres → Job Center, GlobalState.lunaticJobCenters), sinon ceux de la config.
-- Même liste côté client et côté serveur.

function Centers()
    local list = {}

    for _, center in ipairs(GlobalState.lunaticJobCenters or {}) do
        if center.enabled ~= false then
            list[#list + 1] = center
        end
    end

    return #list > 0 and list or Config.Centers
end

function JobById(id)
    for _, job in ipairs(Config.Jobs) do
        if job.id == id then
            return job
        end
    end
end
