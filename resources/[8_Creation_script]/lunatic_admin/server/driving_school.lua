-- Tuile Autres → Auto-école : point de l'auto-école, code de la route (QCM) et examens pratiques par type de véhicule
-- (permis délivré, prix, véhicule, spawn, trajet avec la vitesse autorisée à chaque point).
-- Réglages en KVP 'driving'. Le jeu (lunatic_driving) lit tout par exports.lunatic_admin:getDrivingSchool() ;
-- GlobalState.lunaticDriving ne contient que le public (pas les bonnes réponses du code).

local EXAM_TYPES = { 'car', 'bike', 'truck', 'plane', 'heli', 'boat' }

local DEFAULT_QUESTIONS = {
    { q = 'En agglomération, sauf indication contraire, la vitesse est limitée à :', a = { '30 km/h', '50 km/h', '70 km/h' }, c = 2 },
    { q = 'Un feu orange fixe signifie :', a = { "Je m'arrête, sauf si c'est dangereux", "J'accélère pour passer", 'Je peux passer sans ralentir' }, c = 1 },
    { q = 'À une intersection sans signalisation, la priorité revient :', a = { 'Au véhicule venant de gauche', 'Au véhicule venant de droite', 'Au plus gros véhicule' }, c = 2 },
    { q = "Le port de la ceinture de sécurité est obligatoire :", a = { 'Seulement sur autoroute', "Pour le conducteur seulement", 'Pour tous les occupants' }, c = 3 },
    { q = "Face à un panneau STOP, je dois :", a = { "Ralentir et passer", "Marquer un arrêt complet", "Klaxonner et passer" }, c = 2 },
    { q = 'Sur autoroute, la vitesse maximale est de :', a = { '110 km/h', '130 km/h', '150 km/h' }, c = 2 },
    { q = "Un véhicule de secours avec sirène arrive derrière moi :", a = { 'Je le laisse passer en me décalant', "J'accélère devant lui", "Je m'arrête au milieu de la voie" }, c = 1 },
    { q = "Téléphoner en tenant son téléphone en conduisant est :", a = { 'Autorisé à faible vitesse', 'Interdit', 'Autorisé à un feu rouge' }, c = 2 },
    { q = 'Pour dépasser un véhicule, je dois en principe le faire par :', a = { 'La droite', 'La gauche', "Le côté le plus libre" }, c = 2 },
    { q = "Un piéton est engagé sur un passage piéton :", a = { 'Je klaxonne pour le presser', "Je lui cède le passage", 'Je passe derrière lui' }, c = 2 },
    { q = "Après avoir bu de l'alcool, je peux conduire :", a = { 'Si je me sens bien', "Après un café", "Non, je laisse le volant ou j'attends" }, c = 3 },
    { q = "Une ligne continue au milieu de la chaussée :", a = { 'Peut être franchie pour dépasser', 'Ne doit pas être franchie', 'Sert seulement la nuit' }, c = 2 },
}

local DEFAULTS = {
    maxErrors = 3,
    minEngine = 750,
    ped = 'a_m_y_business_01',
    blip = true,
    school = { x = 239.47, y = -1380.96, z = 33.74, h = 140.0 },
    finalTp = { x = 233.66, y = -1393.42, z = 30.51, h = 140.0 },
    theory = { price = 200, count = 10, pass = 8, questions = DEFAULT_QUESTIONS },
    exams = {
        car = { label = 'Voiture', license = 'drive', price = 500, model = 'blista', speed = 50, active = true, spawn = nil, points = {} },
        bike = { label = 'Moto', license = 'drive_bike', price = 400, model = 'pcj', speed = 50, active = true, spawn = nil, points = {} },
        truck = { label = 'Camion', license = 'drive_truck', price = 800, model = 'mule', speed = 50, active = true, spawn = nil, points = {} },
        plane = { label = 'Avion', license = 'aircraft', price = 5000, model = 'cuban800', speed = 300, active = false, spawn = nil, points = {} },
        heli = { label = 'Hélicoptère', license = 'helicopter', price = 5000, model = 'frogger', speed = 200, active = false, spawn = nil, points = {} },
        boat = { label = 'Bateau', license = 'boat', price = 600, model = 'dinghy', speed = 80, active = true, spawn = nil, points = {} },
    },
}

local LIMITS = { errors = 20, engine = 1000, price = 1000000, speed = 500, points = 60, questions = 60, answers = 4, question = 200, answer = 100 }

local function copy(value)
    return json.decode(json.encode(value))
end

local function denied()
    return Panel.fail("Vous n'avez pas la permission de gérer l'auto-école.")
end

local function whole(value, min, max)
    value = tonumber(value)

    if not value or value ~= math.floor(value) or value < min or value > max then
        return nil
    end

    return value
end

local function cleanText(value, min, max)
    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length >= min and length <= max and text or nil
end

local function position(value)
    if type(value) ~= 'table' then
        return nil
    end

    local x, y, z, h = tonumber(value.x), tonumber(value.y), tonumber(value.z), tonumber(value.h) or 0.0

    if not x or not y or not z or x < -5000 or x > 5000 or y < -5000 or y > 9000 or z < -300 or z > 3000 then
        return nil
    end

    local r = function(n) return math.floor(n * 100 + 0.5) / 100 end
    return { x = r(x), y = r(y), z = r(z), h = math.floor((h % 360) * 10 + 0.5) / 10 }
end

-- Complète les réglages enregistrés avec les valeurs par défaut
local function merge(saved)
    local result = copy(DEFAULTS)

    if type(saved) ~= 'table' then
        return result
    end

    for _, key in ipairs({ 'maxErrors', 'minEngine', 'ped', 'blip', 'school', 'finalTp' }) do
        if saved[key] ~= nil then
            result[key] = saved[key]
        end
    end

    if type(saved.theory) == 'table' then
        for key in pairs(result.theory) do
            if saved.theory[key] ~= nil then
                result.theory[key] = saved.theory[key]
            end
        end
    end

    for _, id in ipairs(EXAM_TYPES) do
        local exam = type(saved.exams) == 'table' and saved.exams[id]

        if type(exam) == 'table' then
            for key, value in pairs(exam) do
                result.exams[id][key] = value
            end
        end
    end

    return result
end

local saved = GetResourceKvpString('driving')
local settings = merge(saved and json.decode(saved) or nil)

local function publish()
    local exams = {}

    for _, id in ipairs(EXAM_TYPES) do
        local exam = settings.exams[id]
        exams[id] = { label = exam.label, license = exam.license, price = exam.price, active = exam.active and exam.spawn ~= nil and #exam.points >= 2 }
    end

    GlobalState.lunaticDriving = {
        school = settings.school, ped = settings.ped, blip = settings.blip,
        theory = { price = settings.theory.price, count = settings.theory.count, pass = settings.theory.pass },
        exams = exams,
    }
end

publish()

-- Permis avion et hélicoptère ajoutés à la table ESX s'ils manquent
table.insert(Panel.readyHooks, function()
    MySQL.query.await("INSERT IGNORE INTO `licenses` (`type`, `label`) VALUES ('aircraft', 'Permis avion'), ('helicopter', 'Permis hélicoptère'), ('boat', 'Permis bateau'), ('drive_truck', 'Permis poids lourd')")

    if Panel.reloadLicenses then
        Panel.reloadLicenses()
    end
end)

exports('getDrivingSchool', function()
    return copy(settings)
end)

---------------------------------------------------------------------
-- Actions du panel
---------------------------------------------------------------------

Panel.actions['driving.info'] = function(_, actor)
    if not Ranks.hasPermission(actor, 'others.manage') then
        return denied()
    end

    local licenses = {}

    for _, entry in ipairs(Panel.licenseCatalogue and Panel.licenseCatalogue() or {}) do
        licenses[#licenses + 1] = { type = entry.type, label = entry.label }
    end

    return { ok = true, silent = true, settings = settings, types = EXAM_TYPES, licenses = licenses }
end

local function readQuestions(list)
    if type(list) ~= 'table' or #list > LIMITS.questions then
        return nil, ('%d questions au maximum.'):format(LIMITS.questions)
    end

    local questions = {}

    for index, entry in ipairs(list) do
        local q = cleanText(entry.q, 5, LIMITS.question)
        local answers = {}

        if not q then
            return nil, ('Question n°%d : de 5 à %d caractères.'):format(index, LIMITS.question)
        end

        for _, answer in ipairs(type(entry.a) == 'table' and entry.a or {}) do
            local text = cleanText(answer, 1, LIMITS.answer)

            if not text then
                return nil, ('Question n°%d : une réponse est vide ou trop longue.'):format(index)
            end

            answers[#answers + 1] = text
        end

        local correct = whole(entry.c, 1, #answers)

        if #answers < 2 or #answers > LIMITS.answers or not correct then
            return nil, ('Question n°%d : de 2 à %d réponses, dont une bonne.'):format(index, LIMITS.answers)
        end

        questions[#questions + 1] = { q = q, a = answers, c = correct }
    end

    return questions
end

local function readExam(id, data, licenses)
    local label = DEFAULTS.exams[id].label
    data = type(data) == 'table' and data or {}

    local price = whole(data.price, 0, LIMITS.price)
    local speed = whole(data.speed, 10, LIMITS.speed)
    local model = type(data.model) == 'string' and data.model:lower():match('^[%w_]+$')

    if not price or not speed then
        return nil, ('%s : prix ou vitesse invalide.'):format(label)
    end

    if not model or #model > 30 then
        return nil, ('%s : modèle du véhicule invalide.'):format(label)
    end

    if not licenses[data.license] then
        return nil, ('%s : permis inconnu.'):format(label)
    end

    local points = {}

    if type(data.points) == 'table' and #data.points > LIMITS.points then
        return nil, ('%s : %d points de trajet au maximum.'):format(label, LIMITS.points)
    end

    for index, point in ipairs(type(data.points) == 'table' and data.points or {}) do
        local spot = position(point)
        local limit = whole(point.speed, 10, LIMITS.speed)

        if not spot or not limit then
            return nil, ('%s : point de trajet n°%d invalide.'):format(label, index)
        end

        points[#points + 1] = { x = spot.x, y = spot.y, z = spot.z, speed = limit }
    end

    local spawn = data.spawn ~= nil and position(data.spawn) or nil

    if data.spawn ~= nil and not spawn then
        return nil, ('%s : position de spawn invalide.'):format(label)
    end

    return { label = label, license = data.license, price = price, model = model, speed = speed, active = data.active == true, spawn = spawn, points = points }
end

Panel.actions['driving.save'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'others.manage') then
        return denied()
    end

    local maxErrors = whole(data.maxErrors, 0, LIMITS.errors)
    local minEngine = whole(data.minEngine, 0, LIMITS.engine)
    local school, finalTp = position(data.school), position(data.finalTp)
    local ped = type(data.ped) == 'string' and data.ped:match('^[%w_]+$')

    if not maxErrors or not minEngine then
        return Panel.fail(('Erreurs max (0 à %d) ou santé moteur min (0 à %d) invalide.'):format(LIMITS.errors, LIMITS.engine))
    end

    if not school or not finalTp then
        return Panel.fail("Position de l'auto-école ou de la téléportation finale invalide.")
    end

    if not ped or #ped > 40 then
        return Panel.fail('Modèle du PNJ invalide.')
    end

    local theory = type(data.theory) == 'table' and data.theory or {}
    local questions, err = readQuestions(theory.questions)

    if not questions then
        return Panel.fail(err)
    end

    local price, count, pass = whole(theory.price, 0, LIMITS.price), whole(theory.count, 1, #questions), whole(theory.pass, 1, 60)

    if not price or not count or not pass or pass > count then
        return Panel.fail('Code : prix, nombre de questions (au plus le nombre de questions écrites) et bonnes réponses minimum (au plus ce nombre).')
    end

    local licenses = {}

    for _, entry in ipairs(Panel.licenseCatalogue and Panel.licenseCatalogue() or {}) do
        licenses[entry.type] = true
    end

    local exams = {}

    for _, id in ipairs(EXAM_TYPES) do
        local exam, examError = readExam(id, type(data.exams) == 'table' and data.exams[id] or nil, licenses)

        if not exam then
            return Panel.fail(examError)
        end

        exams[id] = exam
    end

    settings = {
        maxErrors = maxErrors, minEngine = minEngine, ped = ped, blip = data.blip ~= false, school = school, finalTp = finalTp,
        theory = { price = price, count = count, pass = pass, questions = questions }, exams = exams,
    }

    SetResourceKvp('driving', json.encode(settings))
    publish()

    Logs.add(src, 'driving.save', nil, { questions = #questions })
    return { ok = true, silent = true }
end

-- TP du staff sur une position de la page (point de l'auto-école, spawn, point de trajet)
Panel.actions['driving.tp'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'others.manage') then
        return denied()
    end

    local spot = position(data)

    if not spot then
        return Panel.fail('Position invalide.')
    end

    TriggerClientEvent('lunatic_admin:teleport', src, vector3(spot.x, spot.y, spot.z))
    return { ok = true, silent = true }
end

print('[lunatic_admin] Module Auto-école chargé.')
