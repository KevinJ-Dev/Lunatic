-- Auto-école, côté serveur : tout ce qui compte est vérifié ici (présence au point de l'auto-école, paiement,
-- réponses du code, passage aux points dans l'ordre et dans le véhicule d'examen, santé du moteur, erreurs).
-- Les permis sont inscrits dans user_licenses (table ESX). Réglages : exports.lunatic_admin:getDrivingSchool().

local admin = exports.lunatic_admin
local sessions = {} -- joueur -> { kind = 'theory' | 'exam', ... }

local function now()
    return os.time()
end

-- nil pendant un redémarrage de lunatic_admin (il n'est pas une dépendance déclarée)
local function settings()
    if GetResourceState('lunatic_admin') ~= 'started' then
        return nil
    end

    local ok, s = pcall(function() return admin:getDrivingSchool() end)
    return ok and s or nil
end

local function notify(src, text, kind)
    TriggerClientEvent('esx:showNotification', src, text, kind or 'info')
end

local function distanceTo(src, point)
    local ped = GetPlayerPed(src)

    if not ped or ped == 0 or not point then
        return math.huge
    end

    return #(GetEntityCoords(ped) - vector3(point.x, point.y, point.z))
end

local function hasLicense(identifier, licenseType)
    return (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `user_licenses` WHERE `owner` = ? AND `type` = ?', { identifier, licenseType })) or 0) > 0
end

local function grantLicense(identifier, licenseType)
    if not hasLicense(identifier, licenseType) then
        MySQL.insert.await('INSERT INTO `user_licenses` (`type`, `owner`) VALUES (?, ?)', { licenseType, identifier })
    end
end

-- Paiement : liquide d'abord, sinon banque
local function pay(xPlayer, price, label)
    if price <= 0 then
        return true
    end

    if xPlayer.getMoney() >= price then
        xPlayer.removeMoney(price, label)
        return true
    end

    local bank = xPlayer.getAccount('bank')

    if bank and bank.money >= price then
        xPlayer.removeAccountMoney('bank', price, label)
        return true
    end

    return false
end

local function log(src, action, target, details)
    pcall(function() admin:log('players', 'info', src, action, target, details) end)
end

---------------------------------------------------------------------
-- Menu de l'auto-école
---------------------------------------------------------------------

lib.callback.register('lunatic_driving:menu', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    local s = settings()

    if not xPlayer or not s or distanceTo(src, s.school) > Config.SchoolDistance then
        return nil
    end

    local exams = {}

    for id, exam in pairs(s.exams) do
        exams[#exams + 1] = {
            id = id, label = exam.label, price = exam.price,
            open = exam.active and exam.spawn ~= nil and #exam.points >= 2,
            owned = hasLicense(xPlayer.identifier, exam.license),
        }
    end

    table.sort(exams, function(a, b) return a.price < b.price end)

    return {
        theory = { price = s.theory.price, count = s.theory.count, pass = s.theory.pass, owned = hasLicense(xPlayer.identifier, 'dmv') },
        exams = exams, busy = sessions[src] ~= nil,
    }
end)

---------------------------------------------------------------------
-- Code de la route
---------------------------------------------------------------------

lib.callback.register('lunatic_driving:startTheory', function(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    local s = settings()

    if not s then
        return { ok = false, error = "L'auto-école est fermée pour le moment." }
    end

    if not xPlayer or distanceTo(src, s.school) > Config.SchoolDistance then
        return { ok = false, error = "Vous êtes trop loin de l'auto-école." }
    end

    if sessions[src] then
        return { ok = false, error = 'Vous avez déjà un examen en cours.' }
    end

    if hasLicense(xPlayer.identifier, 'dmv') then
        return { ok = false, error = 'Vous avez déjà le code de la route.' }
    end

    if not pay(xPlayer, s.theory.price, 'Auto-école : code') then
        return { ok = false, error = "Vous n'avez pas assez d'argent." }
    end

    -- Tirage des questions au hasard
    local pool = s.theory.questions
    local order = {}

    for i = 1, #pool do
        order[i] = i
    end

    for i = #order, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end

    local picked, questions = {}, {}

    for i = 1, math.min(s.theory.count, #pool) do
        local q = pool[order[i]]
        picked[i] = q.c
        questions[i] = { q = q.q, a = q.a }
    end

    sessions[src] = { kind = 'theory', answers = picked, pass = s.theory.pass, expires = now() + Config.TheoryMinutes * 60 }
    return { ok = true, questions = questions, pass = s.theory.pass }
end)

lib.callback.register('lunatic_driving:submitTheory', function(src, answers)
    local session = sessions[src]
    local xPlayer = ESX.GetPlayerFromId(src)

    if not session or session.kind ~= 'theory' or not xPlayer then
        return { ok = false, error = 'Aucun code en cours.' }
    end

    sessions[src] = nil

    if now() > session.expires then
        return { ok = false, error = 'Temps écoulé : le code est raté.' }
    end

    local score = 0

    for i, correct in ipairs(session.answers) do
        if type(answers) == 'table' and tonumber(answers[i]) == correct then
            score = score + 1
        end
    end

    local passed = score >= session.pass

    if passed then
        grantLicense(xPlayer.identifier, 'dmv')
    end

    log(src, passed and 'driving.theory_pass' or 'driving.theory_fail', nil, { score = score, total = #session.answers })
    return { ok = true, passed = passed, score = score, total = #session.answers, pass = session.pass }
end)

---------------------------------------------------------------------
-- Examen pratique
---------------------------------------------------------------------

local function endExam(src, passed, reason)
    local session = sessions[src]

    if not session or session.kind ~= 'exam' then
        return
    end

    sessions[src] = nil

    if session.vehicle and DoesEntityExist(session.vehicle) then
        DeleteEntity(session.vehicle)
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local s = settings()

    if passed and xPlayer then
        grantLicense(xPlayer.identifier, session.license)
        -- Premier permis : lunatic_gameplay remet l'objet « Permis de conduire »
        TriggerEvent('lunatic_driving:licenseGranted', src, session.license)
    end

    if GetPlayerPing(src) > 0 then
        TriggerClientEvent('lunatic_driving:examEnded', src, { passed = passed, reason = reason, label = session.label })
        if s then
            TriggerClientEvent('lunatic_admin:teleport', src, vector3(s.finalTp.x, s.finalTp.y, s.finalTp.z))
        end
    end

    log(src, passed and 'driving.exam_pass' or 'driving.exam_fail', session.label, { errors = session.errors, reason = reason })
end

lib.callback.register('lunatic_driving:startExam', function(src, id)
    local xPlayer = ESX.GetPlayerFromId(src)
    local s = settings()

    if not s then
        return { ok = false, error = "L'auto-école est fermée pour le moment." }
    end

    local exam = type(id) == 'string' and s.exams[id]

    if not xPlayer or distanceTo(src, s.school) > Config.SchoolDistance then
        return { ok = false, error = "Vous êtes trop loin de l'auto-école." }
    end

    if not exam or not exam.active or not exam.spawn or #exam.points < 2 then
        return { ok = false, error = "Cet examen n'est pas ouvert." }
    end

    if sessions[src] then
        return { ok = false, error = 'Vous avez déjà un examen en cours.' }
    end

    if not hasLicense(xPlayer.identifier, 'dmv') then
        return { ok = false, error = "Passez d'abord le code de la route." }
    end

    if hasLicense(xPlayer.identifier, exam.license) then
        return { ok = false, error = 'Vous avez déjà ce permis.' }
    end

    if not pay(xPlayer, exam.price, ('Auto-école : %s'):format(exam.label)) then
        return { ok = false, error = "Vous n'avez pas assez d'argent." }
    end

    local spawn = exam.spawn
    local vehicle = CreateVehicleServerSetter(joaat(exam.model), Config.VehicleTypes[id] or 'automobile', spawn.x + 0.0, spawn.y + 0.0, spawn.z + 0.0, (spawn.h or 0.0) + 0.0)
    local timeout = GetGameTimer() + 3000

    while vehicle ~= 0 and not DoesEntityExist(vehicle) and GetGameTimer() < timeout do
        Wait(0)
    end

    if vehicle == 0 or not DoesEntityExist(vehicle) then
        xPlayer.addAccountMoney('bank', exam.price, 'Auto-école : remboursement')
        return { ok = false, error = "Le véhicule d'examen n'a pas pu être créé (remboursé) : prévenez le staff." }
    end

    SetVehicleNumberPlateText(vehicle, 'ECOLE')
    Entity(vehicle).state:set('fuel', 100.0, true)

    sessions[src] = {
        kind = 'exam', id = id, label = exam.label, license = exam.license, vehicle = vehicle, points = exam.points,
        next = 1, errors = 0, maxErrors = s.maxErrors, minEngine = s.minEngine, expires = now() + Config.ExamMinutes * 60,
    }

    log(src, 'driving.exam_start', exam.label, { price = exam.price })
    return {
        ok = true, netId = NetworkGetNetworkIdFromEntity(vehicle), points = exam.points, label = exam.label,
        maxErrors = s.maxErrors, minEngine = s.minEngine, radius = Config.PointRadius[id] or 8.0, air = id == 'plane' or id == 'heli',
    }
end)

-- Passage à un point : dans l'ordre, dans le véhicule d'examen, à portée
lib.callback.register('lunatic_driving:checkpoint', function(src, index)
    local session = sessions[src]

    if not session or session.kind ~= 'exam' or tonumber(index) ~= session.next then
        return { ok = false }
    end

    local point = session.points[session.next]
    local ped = GetPlayerPed(src)

    if GetVehiclePedIsIn(ped, false) ~= session.vehicle or distanceTo(src, point) > (Config.PointRadius[session.id] or 8.0) + 10.0 then
        return { ok = false }
    end

    session.next = session.next + 1
    return { ok = true, done = session.next > #session.points }
end)

-- Erreur relevée par le client (vitesse, choc) : une erreur ne peut que pénaliser le joueur
lib.callback.register('lunatic_driving:error', function(src, reason)
    local session = sessions[src]

    if not session or session.kind ~= 'exam' then
        return nil
    end

    session.errors = session.errors + 1

    if session.errors > session.maxErrors then
        endExam(src, false, ("Trop d'erreurs (%d)."):format(session.errors))
        return { errors = session.errors, failed = true }
    end

    return { errors = session.errors, failed = false }
end)

lib.callback.register('lunatic_driving:finish', function(src)
    local session = sessions[src]

    if not session or session.kind ~= 'exam' then
        return nil
    end

    if session.next <= #session.points then
        endExam(src, false, 'Trajet incomplet.')
        return
    end

    local engine = DoesEntityExist(session.vehicle) and GetVehicleEngineHealth(session.vehicle) or 0

    if engine < session.minEngine then
        endExam(src, false, 'Véhicule trop endommagé.')
        return
    end

    endExam(src, session.errors <= session.maxErrors, nil)
end)

RegisterNetEvent('lunatic_driving:abort', function(reason)
    local src = source
    endExam(src, false, type(reason) == 'string' and reason:sub(1, 80) or 'Examen abandonné.')
end)

-- Examen trop long, véhicule disparu
CreateThread(function()
    while true do
        Wait(5000)

        for src, session in pairs(sessions) do
            if now() > session.expires then
                if session.kind == 'exam' then
                    endExam(src, false, 'Temps écoulé.')
                else
                    sessions[src] = nil
                end
            elseif session.kind == 'exam' and not DoesEntityExist(session.vehicle) then
                endExam(src, false, "Véhicule d'examen disparu.")
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local session = sessions[source]

    if session and session.vehicle and DoesEntityExist(session.vehicle) then
        DeleteEntity(session.vehicle)
    end

    sessions[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, session in pairs(sessions) do
            if session.vehicle and DoesEntityExist(session.vehicle) then
                DeleteEntity(session.vehicle)
            end
        end
    end
end)
