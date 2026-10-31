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

-- Réglages d'une façon de faire les arrêts : Config.Route complété par Config.Tasks[task]
function TaskSettings(task)
    local settings = {}

    for key, value in pairs(Config.Route) do
        settings[key] = value
    end

    for key, value in pairs(Config.Tasks[task] or {}) do
        settings[key] = value
    end

    return settings
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
        vehicle = saved.vehicle or job.vehicle, depot = saved.depot, spawn = saved.spawn, stations = type(saved.stations) == 'table' and saved.stations or {},
    }
end


