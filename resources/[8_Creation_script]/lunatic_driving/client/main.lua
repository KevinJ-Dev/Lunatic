-- Auto-école, côté client : PNJ et blip, menu, questions du code, conduite de l'examen (points, vitesse, chocs).
-- Le client relève les erreurs et le passage aux points ; le serveur vérifie tout avant de délivrer le permis.

local ped, blip = nil, nil
local exam = nil -- examen en cours

local function notify(text, kind)
    ESX.ShowNotification(text, kind or 'info')
end

local function drawText(x, y, text, scale)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 230)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function currency()
    return GlobalState.lunaticCurrency or '$'
end

---------------------------------------------------------------------
-- PNJ et blip (GlobalState.lunaticDriving, tuile Autres → Auto-école)
---------------------------------------------------------------------

local function clearSchool()
    if ped and DoesEntityExist(ped) then
        DeleteEntity(ped)
    end

    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end

    ped, blip = nil, nil
end

local function setupSchool(data)
    clearSchool()

    if type(data) ~= 'table' or type(data.school) ~= 'table' then
        return
    end

    local s = data.school

    if data.blip then
        blip = AddBlipForCoord(s.x + 0.0, s.y + 0.0, s.z + 0.0)
        SetBlipSprite(blip, Config.Blip.sprite)
        SetBlipColour(blip, Config.Blip.color)
        SetBlipScale(blip, Config.Blip.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Auto-école')
        EndTextCommandSetBlipName(blip)
    end

    local model = joaat(data.ped or 'a_m_y_business_01')

    if not IsModelInCdimage(model) then
        return
    end

    RequestModel(model)
    local timeout = GetGameTimer() + 5000

    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        Wait(0)
    end

    ped = CreatePed(4, model, s.x + 0.0, s.y + 0.0, s.z - 1.0, (s.h or 0.0) + 0.0, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetModelAsNoLongerNeeded(model)
end

AddStateBagChangeHandler('lunaticDriving', 'global', function(_, _, value)
    setupSchool(value)
end)

CreateThread(function()
    while not GlobalState.lunaticDriving do
        Wait(1000)
    end

    setupSchool(GlobalState.lunaticDriving)
end)

---------------------------------------------------------------------
-- Code de la route
---------------------------------------------------------------------

local function takeTheory()
    local res = lib.callback.await('lunatic_driving:startTheory', false)

    if not res or not res.ok then
        return notify(res and res.error or "Code indisponible.", 'error')
    end

    local answers = {}

    for i, question in ipairs(res.questions) do
        local options = {}

        for index, answer in ipairs(question.a) do
            options[#options + 1] = { value = index, label = answer }
        end

        local input = lib.inputDialog(('Code de la route · question %d / %d'):format(i, #res.questions), {
            { type = 'select', label = question.q, options = options, required = true },
        })

        if not input then
            -- Fenêtre fermée : réponse vide (comptée fausse)
            answers[i] = 0
        else
            answers[i] = tonumber(input[1]) or 0
        end
    end

    local result = lib.callback.await('lunatic_driving:submitTheory', false, answers)

    if not result or not result.ok then
        return notify(result and result.error or 'Correction impossible.', 'error')
    end

    if result.passed then
        notify(('Code obtenu : %d / %d bonnes réponses.'):format(result.score, result.total), 'success')
    else
        notify(('Code raté : %d / %d (il en faut %d).'):format(result.score, result.total, result.pass), 'error')
    end
end

---------------------------------------------------------------------
-- Examen pratique
---------------------------------------------------------------------

local function stopExam()
    if exam and exam.blip and DoesBlipExist(exam.blip) then
        RemoveBlip(exam.blip)
    end

    exam = nil
end

local function pointBlip(point)
    if exam.blip and DoesBlipExist(exam.blip) then
        RemoveBlip(exam.blip)
    end

    exam.blip = AddBlipForCoord(point.x + 0.0, point.y + 0.0, point.z + 0.0)
    SetBlipColour(exam.blip, 5)
    SetBlipRoute(exam.blip, true)
    SetBlipRouteColour(exam.blip, 5)
end

local function addError(reason)
    notify(('Erreur : %s'):format(reason), 'error')
    local res = lib.callback.await('lunatic_driving:error', false, reason)

    if res then
        exam.errors = res.errors
    end
end

local function runExam(data)
    local timeout = GetGameTimer() + 5000

    while not NetworkDoesEntityExistWithNetworkId(data.netId) and GetGameTimer() < timeout do
        Wait(50)
    end

    local vehicle = NetworkGetEntityFromNetworkId(data.netId)

    if not DoesEntityExist(vehicle) then
        TriggerServerEvent('lunatic_driving:abort', "Véhicule d'examen introuvable.")
        return notify("Véhicule d'examen introuvable.", 'error')
    end

    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
    exam = { vehicle = vehicle, points = data.points, index = 1, errors = 0, maxErrors = data.maxErrors, minEngine = data.minEngine, radius = data.radius, air = data.air }
    pointBlip(exam.points[1])
    notify(('Examen %s : suivez les points, respectez les vitesses.'):format(data.label), 'info')

    local speeding, lastSpeedError, lastCrash, outSince = 0, 0, 0, nil
    local lastBody = GetVehicleBodyHealth(vehicle)

    while exam do
        local now = GetGameTimer()
        local playerPed = PlayerPedId()
        local point = exam.points[exam.index]
        local limit = point.speed
        local inVehicle = GetVehiclePedIsIn(playerPed, false) == vehicle

        -- Marqueur du point à atteindre
        DrawMarker(exam.air and 6 or 1, point.x, point.y, point.z - (exam.air and 0.0 or 1.0), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            exam.air and exam.radius or 4.0, exam.air and exam.radius or 4.0, exam.air and exam.radius or 1.0, 242, 194, 107, 120, false, false, 2, false, nil, nil, false)

        drawText(0.5, 0.86, ('Point %d / %d · limite %d km/h · erreurs %d / %d'):format(exam.index, #exam.points, limit, exam.errors, exam.maxErrors), 0.45)

        if inVehicle then
            outSince = nil
            local speed = GetEntitySpeed(vehicle) * 3.6

            -- Excès de vitesse prolongé
            if speed > limit + Config.SpeedTolerance then
                speeding = speeding + GetFrameTime()

                if speeding >= Config.SpeedingSeconds and now - lastSpeedError > 8000 then
                    lastSpeedError, speeding = now, 0
                    addError(('excès de vitesse (%d km/h pour %d)'):format(math.floor(speed), limit))
                end
            else
                speeding = 0
            end

            -- Choc
            local body = GetVehicleBodyHealth(vehicle)

            if lastBody - body >= Config.CrashDamage and now - lastCrash > 3000 then
                lastCrash = now
                addError('choc avec le véhicule')
            end

            lastBody = body

            -- Moteur trop abîmé : fin immédiate (le serveur vérifie la santé du moteur)
            if GetVehicleEngineHealth(vehicle) < exam.minEngine then
                lib.callback.await('lunatic_driving:finish', false)
                break
            end

            -- Point atteint
            local coords = GetEntityCoords(vehicle)

            if #(coords - vector3(point.x, point.y, point.z)) <= exam.radius then
                local res = lib.callback.await('lunatic_driving:checkpoint', false, exam.index)

                if res and res.ok then
                    if res.done then
                        lib.callback.await('lunatic_driving:finish', false)
                        break
                    end

                    exam.index = exam.index + 1
                    pointBlip(exam.points[exam.index])
                    PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', false)
                end
            end
        else
            outSince = outSince or now
            local left = Config.OutOfVehicleSeconds - math.floor((now - outSince) / 1000)
            drawText(0.5, 0.80, ("Remontez dans le véhicule d'examen (%d s)"):format(math.max(0, left)), 0.5)

            if left <= 0 then
                TriggerServerEvent('lunatic_driving:abort', 'Sortie du véhicule.')
                break
            end
        end

        Wait(0)
    end
end

local function takeExam(id)
    local res = lib.callback.await('lunatic_driving:startExam', false, id)

    if not res or not res.ok then
        return notify(res and res.error or 'Examen indisponible.', 'error')
    end

    CreateThread(function() runExam(res) end)
end

RegisterNetEvent('lunatic_driving:examEnded', function(result)
    stopExam()

    if result.passed then
        notify(('Félicitations : examen %s réussi, le permis est à vous !'):format(result.label or ''), 'success')
    else
        notify(('Examen %s raté%s'):format(result.label or '', result.reason and (' : ' .. result.reason) or '.'), 'error')
    end
end)

RegisterCommand('stopexamen', function()
    if exam then
        TriggerServerEvent('lunatic_driving:abort', 'Examen abandonné.')
    end
end, false)

---------------------------------------------------------------------
-- Menu au PNJ
---------------------------------------------------------------------

local function openMenu()
    local data = lib.callback.await('lunatic_driving:menu', false)

    if not data then
        return
    end

    if data.busy then
        return notify('Terminez votre examen en cours (/stopexamen pour abandonner).', 'error')
    end

    local options = {
        {
            title = 'Code de la route',
            description = data.theory.owned and 'Déjà obtenu' or ('%d questions · %d bonnes réponses requises · %d %s'):format(data.theory.count, data.theory.pass, data.theory.price, currency()),
            icon = 'book', disabled = data.theory.owned,
            onSelect = takeTheory,
        },
    }

    for _, e in ipairs(data.exams) do
        if e.open then
            options[#options + 1] = {
                title = ('Examen %s'):format(e.label),
                description = e.owned and 'Permis déjà obtenu' or not data.theory.owned and "Code de la route requis" or ('%d %s'):format(e.price, currency()),
                icon = 'car', disabled = e.owned or not data.theory.owned,
                onSelect = function() takeExam(e.id) end,
            }
        end
    end

    lib.registerContext({ id = 'lunatic_driving', title = 'Auto-école', options = options })
    lib.showContext('lunatic_driving')
end

CreateThread(function()
    while true do
        local data = GlobalState.lunaticDriving
        local wait = 1000

        if data and data.school and not exam then
            local s = data.school
            local distance = #(GetEntityCoords(PlayerPedId()) - vector3(s.x, s.y, s.z))

            if distance < 15.0 then
                wait = 0

                if distance <= Config.InteractDistance then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName("~INPUT_CONTEXT~ Auto-école")
                    EndTextCommandDisplayHelp(0, false, true, -1)

                    if IsControlJustReleased(0, 38) then
                        openMenu()
                    end
                end
            end
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clearSchool()
        stopExam()
    end
end)
