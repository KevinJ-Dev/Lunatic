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

-- Réglages d'un métier : ceux du panel (Autres → Métiers d'intérim, GlobalState.lunaticInterim), sinon la config
function JobSettings(id)
    local job = JobById(id)

    if not job then
        return nil
    end

    local saved = (GlobalState.lunaticInterim or {})[id] or {}

    return {
        enabled = saved.enabled ~= false, salary = tonumber(saved.salary) or job.salary, stops = tonumber(saved.stops) or job.stops or 5,
        vehicle = saved.vehicle or job.vehicle, depot = saved.depot, spawn = saved.spawn,
    }
end

-- Métier d'intérim d'un nom de métier ESX (« interim_garbage » -> fiche Éboueur), nil sinon
function JobFromName(name)
    if type(name) ~= 'string' or name:sub(1, #Config.JobPrefix) ~= Config.JobPrefix then
        return nil
    end

    return JobById(name:sub(#Config.JobPrefix + 1))
end
