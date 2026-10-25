-- Tuile Économie : salaires des métiers (entreprises, services publics, Pôle emploi), aide de l'État, plafonds de banque,
-- frais de fourrière, devise et intervalle de paie. Tout s'applique sans redémarrage :
--   - salaires : tables ESX job_grades puis ESX.RefreshJob (comme le Pôle emploi) ;
--   - réglages : GlobalState.lunaticEconomy (lu par la paie d'ESX, es_extended/server/modules/paycheck.lua)
--     et GlobalState.lunaticCurrency (symbole affiché par nos scripts).
-- Les plafonds de banque et les frais de fourrière sont enregistrés pour les futurs scripts de banque et de garage.

local UNEMPLOYED = 'unemployed'

-- Valeurs par défaut (bouton « Par défaut » du panel)
local DEFAULTS = {
    paycheckMinutes = 15,
    allowances = { premium = 35, premium_plus = 70 },
    bank = { standard = 2000, premium = 4000, premium_plus = 6000 },
    impound = { car = 300, bike = 300, truck = 300, boat = 300, heli = 300, plane = 300 },
    currency = '$',
}
local DEFAULT_UNEMPLOYED_SALARY = 20

local LIMITS = {
    allowance = 100000,
    bank = 100000000,
    impound = 1000000,
    paycheckMin = 1,
    paycheckMax = 240,
}

local settings = json.decode(json.encode(DEFAULTS))

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

local copy = Util.copy

-- Garde les clés connues et complète les manquantes par les valeurs par défaut
local function merge(saved)
    local result = copy(DEFAULTS)

    if type(saved) ~= 'table' then
        return result
    end

    if tonumber(saved.paycheckMinutes) then
        result.paycheckMinutes = math.floor(tonumber(saved.paycheckMinutes))
    end

    for _, group in ipairs({ 'allowances', 'bank', 'impound' }) do
        if type(saved[group]) == 'table' then
            for key in pairs(result[group]) do
                if tonumber(saved[group][key]) then
                    result[group][key] = math.floor(tonumber(saved[group][key]))
                end
            end
        end
    end

    if type(saved.currency) == 'string' and saved.currency ~= '' then
        result.currency = saved.currency
    end

    return result
end

local function publish()
    GlobalState.lunaticEconomy = settings
    GlobalState.lunaticCurrency = settings.currency
end

local saved = GetResourceKvpString('economy')
settings = merge(saved and json.decode(saved) or nil)
publish()

local function store()
    SetResourceKvp('economy', json.encode(settings))
    publish()
end

exports('getEconomy', function()
    return copy(settings)
end)

-- Tuile Boutique (onglet Premium) : aide de l'État par abonnement, même réglage que cette tuile
function Panel.allowances()
    return copy(settings.allowances)
end

---@return boolean ok, string|nil error
function Panel.setAllowances(values)
    for tier in pairs(settings.allowances) do
        local amount = tonumber(values[tier])

        if not amount or amount ~= math.floor(amount) or amount < 0 or amount > LIMITS.allowance then
            return false, ("Aide de l'État : un nombre entier de 0 à %d."):format(LIMITS.allowance)
        end
    end

    for tier in pairs(settings.allowances) do
        settings.allowances[tier] = math.floor(tonumber(values[tier]))
    end

    store()
    return true
end

-- Symbole de la devise pour le panel (montants affichés partout)
table.insert(Panel.stateHooks, function(state)
    state.currency = settings.currency
end)

---------------------------------------------------------------------
-- Outils
---------------------------------------------------------------------

local function wholeNumber(value, max)
    local number = tonumber(value)

    if not number or number ~= math.floor(number) or number < 0 or number > max then
        return nil
    end

    return math.floor(number)
end

local function sortedGrades(job)
    local grades = {}

    for _, grade in pairs(job.grades or {}) do
        grades[#grades + 1] = { grade = tonumber(grade.grade), label = grade.label, salary = tonumber(grade.salary) or 0 }
    end

    table.sort(grades, function(a, b) return a.grade < b.grade end)
    return grades
end

local function typeLabels()
    local labels = {}

    for kind, list in pairs(Config.StructureTypes) do
        labels[kind] = {}

        for _, entry in ipairs(list) do
            labels[kind][entry.id] = entry.label
        end
    end

    return labels
end

local function unemployedSalary()
    local job = ESX.GetJobs()[UNEMPLOYED]
    local grade = job and job.grades and job.grades['0']
    return grade and tonumber(grade.salary) or 0
end

local function setUnemployedSalary(src, salary)
    local before = unemployedSalary()

    if before == salary then
        return
    end

    MySQL.update.await('UPDATE `job_grades` SET `salary` = ? WHERE `job_name` = ? AND `grade` = 0', { salary, UNEMPLOYED })
    ESX.RefreshJob(UNEMPLOYED)
    Logs.add(src, 'economy.salaries', nil, { job = UNEMPLOYED, changes = { { grade = 0, label = 'Chômage', before = before, after = salary } } })
end

---------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------

Panel.actions['economy.overview'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'economy.manage') then
        return denied()
    end

    local labels = typeLabels()
    local lists = { company = {}, public = {}, interim = {} }

    for name, job in pairs(ESX.GetJobs()) do
        if name ~= UNEMPLOYED then
            local structure = Structures.get(name)
            local kind = structure and lists[structure.kind] and structure.kind or 'interim'

            lists[kind][#lists[kind] + 1] = {
                job = name,
                label = job.label or name,
                typeLabel = structure and (labels[structure.kind] or {})[structure.type] or 'Pôle emploi',
                logo = structure and structure.logo or '',
                color = structure and structure.color or '#9650ff',
                grades = sortedGrades(job),
            }
        end
    end

    for _, list in pairs(lists) do
        table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    end

    return {
        ok = true,
        silent = true,
        jobs = lists,
        settings = settings,
        unemployed = unemployedSalary(),
        defaults = DEFAULTS,
        defaultUnemployed = DEFAULT_UNEMPLOYED_SALARY,
        limits = { salary = Config.PolesMaxSalary, allowance = LIMITS.allowance, bank = LIMITS.bank, impound = LIMITS.impound, paycheckMin = LIMITS.paycheckMin, paycheckMax = LIMITS.paycheckMax },
    }
end

---------------------------------------------------------------------
-- Salaires d'un métier
---------------------------------------------------------------------

Panel.actions['economy.salaries'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'economy.manage') then
        return denied()
    end

    local job = type(data.job) == 'string' and data.job ~= UNEMPLOYED and ESX.GetJobs()[data.job]

    if not job then
        return Panel.fail('Métier introuvable.')
    end

    if type(data.salaries) ~= 'table' then
        return Panel.fail('Salaires invalides.')
    end

    local changes, queries = {}, {}

    for _, grade in ipairs(sortedGrades(job)) do
        local value = data.salaries[tostring(grade.grade)]

        if value ~= nil then
            local salary = wholeNumber(value, Config.PolesMaxSalary)

            if not salary then
                return Panel.fail(('Salaire invalide pour « %s » : nombre entier de 0 à %d.'):format(grade.label, Config.PolesMaxSalary))
            end

            if salary ~= grade.salary then
                changes[#changes + 1] = { grade = grade.grade, label = grade.label, before = grade.salary, after = salary }
                queries[#queries + 1] = { query = 'UPDATE `job_grades` SET `salary` = ? WHERE `job_name` = ? AND `grade` = ?', values = { salary, job.name, grade.grade } }
            end
        end
    end

    if #changes == 0 then
        return { ok = true }
    end

    MySQL.transaction.await(queries)
    ESX.RefreshJob(job.name)
    Logs.add(src, 'economy.salaries', nil, { job = job.name, label = job.label, changes = changes })

    return { ok = true }
end

---------------------------------------------------------------------
-- Réglages (une section à la fois)
---------------------------------------------------------------------

local function readGroup(values, defaults, max, what)
    if type(values) ~= 'table' then
        return nil, Panel.fail('Valeurs invalides.')
    end

    local result = {}

    for key in pairs(defaults) do
        local amount = wholeNumber(values[key], max)

        if not amount then
            return nil, Panel.fail(('%s : nombre entier de 0 à %d.'):format(what, max))
        end

        result[key] = amount
    end

    return result
end

local function cleanCurrency(value)
    if type(value) ~= 'string' then
        return nil
    end

    local symbol = value:gsub('%c', ''):match('^%s*(.-)%s*$')
    local length = utf8.len(symbol)

    return length and length >= 1 and length <= 4 and symbol or nil
end

local SECTIONS = {
    aid = function(src, data)
        local unemployed = wholeNumber(data.unemployed, Config.PolesMaxSalary)

        if not unemployed then
            return nil, Panel.fail(('Allocation chômage : nombre entier de 0 à %d.'):format(Config.PolesMaxSalary))
        end

        local allowances, err = readGroup(data.allowances, DEFAULTS.allowances, LIMITS.allowance, 'Allocations')

        if not allowances then
            return nil, err
        end

        setUnemployedSalary(src, unemployed)
        return { allowances = allowances }
    end,
    bank = function(_, data)
        local bank, err = readGroup(data.bank, DEFAULTS.bank, LIMITS.bank, 'Plafonds de dépôt')
        return bank and { bank = bank }, err
    end,
    impound = function(_, data)
        local impound, err = readGroup(data.impound, DEFAULTS.impound, LIMITS.impound, 'Frais de fourrière')
        return impound and { impound = impound }, err
    end,
    currency = function(_, data)
        local symbol = cleanCurrency(data.currency)

        if not symbol then
            return nil, Panel.fail('Le symbole doit faire entre 1 et 4 caractères.')
        end

        return { currency = symbol }
    end,
    paycheck = function(_, data)
        local minutes = wholeNumber(data.paycheckMinutes, LIMITS.paycheckMax)

        if not minutes or minutes < LIMITS.paycheckMin then
            return nil, Panel.fail(('Intervalle de paie : de %d à %d minutes.'):format(LIMITS.paycheckMin, LIMITS.paycheckMax))
        end

        return { paycheckMinutes = minutes }
    end,
}

Panel.actions['economy.saveSettings'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'economy.manage') then
        return denied()
    end

    local read = SECTIONS[data.section]

    if not read then
        return Panel.fail('Section inconnue.')
    end

    local values, err = read(src, data)

    if not values then
        return err
    end

    local before = {}

    for key, value in pairs(values) do
        before[key] = copy(settings[key])
        settings[key] = value
    end

    store()
    Logs.add(src, 'economy.settings', nil, { section = data.section, before = before, after = values })

    return { ok = true }
end

print('^2[lunatic_admin]^7 Économie : réglages chargés (paie toutes les ' .. settings.paycheckMinutes .. ' min, devise ' .. settings.currency .. ').')
