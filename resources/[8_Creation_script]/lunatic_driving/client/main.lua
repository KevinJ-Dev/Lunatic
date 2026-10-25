-- Auto-école, côté client : PNJ et blip, page de l'auto-école (code puis examens), conduite de l'examen (points,
-- arrêts aux STOP, vitesse, chocs, fautes graves) affichée dans le HUD. Le client relève les fautes et le passage
-- aux points ; le serveur vérifie tout avant de délivrer le permis.

local ped, blip = nil, nil
local exam = nil -- examen en cours

local function notify(text, kind)
    ESX.ShowNotification(text, kind or 'info')
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
-- Page de l'auto-école
---------------------------------------------------------------------

local function openMenu()
    local data = lib.callback.await('lunatic_driving:menu', false)

    if not data or data.busy then
        SetNuiFocus(false, false)

        if data then
            notify('Terminez votre examen en cours (/stopexamen pour abandonner).', 'error')
        end

        return
    end

    data.currency = currency()
    SendNUIMessage({ action = 'school', data = data })
    SetNuiFocus(true, true)
end

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb(true)
end)

-- Retour à l'accueil après le code (résultat à jour)
RegisterNUICallback('back', function(_, cb)
    cb(true)
    openMenu()
end)

RegisterNUICallback('theory', function(_, cb)
    local res = lib.callback.await('lunatic_driving:startTheory', false)

    if not res or not res.ok then
        notify(res and res.error or 'Code indisponible.', 'error')
        return cb({ ok = false })
    end

    cb(res)
end)

RegisterNUICallback('submitTheory', function(data, cb)
    local result = lib.callback.await('lunatic_driving:submitTheory', false, type(data) == 'table' and data.answers or {})

    if result and result.ok then
        notify(result.passed and ('Code obtenu : %d / %d.'):format(result.score, result.total)
            or ('Code raté : %d / %d (il en faut %d).'):format(result.score, result.total, result.pass), result.passed and 'success' or 'error')
    end

    cb(result or { ok = false, error = 'Correction impossible.' })
end)

---------------------------------------------------------------------
-- Examen pratique
---------------------------------------------------------------------

local function stopExam()
    if exam and exam.blip and DoesBlipExist(exam.blip) then
        RemoveBlip(exam.blip)
    end

    exam = nil
    SendNUIMessage({ action = 'hudHide' })
end

local function pointBlip(point)
    if exam.blip and DoesBlipExist(exam.blip) then
        RemoveBlip(exam.blip)
    end

    local colour = point.stop and not exam.air and 1 or 5
    exam.blip = AddBlipForCoord(point.x + 0.0, point.y + 0.0, point.z + 0.0)
    SetBlipColour(exam.blip, colour)
    SetBlipRoute(exam.blip, true)
    SetBlipRouteColour(exam.blip, colour)
end

local function fault(text)
    PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET', false)
    SendNUIMessage({ action = 'fault', text = ('Faute : %s'):format(text) })
end

local function addError(reason)
    fault(reason)
    local res = lib.callback.await('lunatic_driving:error', false, reason)

    if res and exam then
        exam.errors = res.errors
    end
end

-- Faute grave : le serveur arrête l'examen (si c'est réglé ainsi dans le panel)
local function majorFault(kind)
    if exam and exam.majorFail and not exam.ending then
        exam.ending = true
        TriggerServerEvent('lunatic_driving:major', kind)
    end
end

-- Piéton percuté par le véhicule d'examen
local function hitPedestrian(vehicle)
    local origin = GetEntityCoords(vehicle)
    local me = PlayerPedId()

    for _, other in ipairs(GetGamePool('CPed')) do
        if other ~= me and #(GetEntityCoords(other) - origin) < 10.0 and HasEntityBeenDamagedByEntity(other, vehicle, true) then
            ClearEntityLastDamageEntity(other)
            return true
        end
    end

    return false
end

-- Passage validé par le serveur ; missed = STOP franchi sans arrêt (faute comptée par le serveur).
-- Renvoie true quand l'examen est terminé.
local function reachPoint(missed)
    local res = lib.callback.await('lunatic_driving:checkpoint', false, exam.index, missed)

    if not exam or not res or not res.ok then
        return not exam
    end

    exam.errors = res.errors or exam.errors

    if res.done then
        lib.callback.await('lunatic_driving:finish', false)
        return true
    end

    exam.index = exam.index + 1
    exam.entered, exam.stopped, exam.stillSince = false, false, nil
    pointBlip(exam.points[exam.index])
    PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', false)
    return false
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
    exam = {
        vehicle = vehicle, points = data.points, index = 1, errors = 0, maxErrors = data.maxErrors, minEngine = data.minEngine,
        radius = data.radius, air = data.air, majorFail = data.majorFail, label = data.label, endsAt = GetGameTimer() + data.seconds * 1000,
    }
    pointBlip(exam.points[1])
    notify(('Examen %s : suivez les points, respectez les limites et marquez les STOP.'):format(data.label), 'info')

    local speeding, lastSpeedError, lastCrash, lastHud, lastPedCheck, lastOutMessage = 0, 0, 0, 0, 0, 0
    local outSince, lastSpeed = nil, 0
    local lastBody = GetVehicleBodyHealth(vehicle)

    while exam do
        local now = GetGameTimer()
        local point = exam.points[exam.index]
        local limit = point.speed
        local inVehicle = GetVehiclePedIsIn(PlayerPedId(), false) == vehicle
        local stopPoint = point.stop and not exam.air
        local speed = inVehicle and GetEntitySpeed(vehicle) * 3.6 or 0.0
        local stopState = nil

        -- Marqueur du point à atteindre (rouge pour un STOP)
        local r, g, b = 242, 194, 107

        if stopPoint then
            r, g, b = 220, 40, 60
        end

        DrawMarker(exam.air and 6 or 1, point.x, point.y, point.z - (exam.air and 0.0 or 1.0), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            exam.air and exam.radius or 4.0, exam.air and exam.radius or 4.0, exam.air and exam.radius or 1.0, r, g, b, 120, false, false, 2, false, nil, nil, false)

        if inVehicle then
            outSince = nil

            -- Excès de vitesse prolongé ; très grand excès = faute grave (sauf avion et hélicoptère)
            if not exam.air and speed > limit + Config.MajorSpeeding then
                majorFault('speed')
            end

            if speed > limit + Config.SpeedTolerance then
                speeding = speeding + GetFrameTime()

                if speeding >= Config.SpeedingSeconds and now - lastSpeedError > 8000 then
                    lastSpeedError, speeding = now, 0
                    addError(('excès de vitesse (%d km/h pour %d)'):format(math.floor(speed), limit))
                end
            else
                speeding = 0
            end

            -- Choc : léger = faute, violent = faute grave
            local body = GetVehicleBodyHealth(vehicle)
            local damage = lastBody - body

            if damage >= Config.MajorCrashDamage then
                majorFault('crash')
            elseif damage >= Config.CrashDamage and now - lastCrash > 3000 then
                lastCrash = now
                addError('choc avec le véhicule')
            end

            lastBody = body

            if not exam.air and now - lastPedCheck > 300 then
                lastPedCheck = now

                if hitPedestrian(vehicle) then
                    majorFault('pedestrian')
                end
            end

            -- Moteur trop abîmé : fin immédiate (le serveur vérifie la santé du moteur)
            if GetVehicleEngineHealth(vehicle) < exam.minEngine then
                lib.callback.await('lunatic_driving:finish', false)
                break
            end

            -- Point atteint ; au STOP, arrêt complet avant de valider
            local distance = #(GetEntityCoords(vehicle) - vector3(point.x, point.y, point.z))

            if distance <= exam.radius then
                exam.entered = true

                if stopPoint and not exam.stopped then
                    if speed < 1.0 then
                        exam.stillSince = exam.stillSince or now

                        if now - exam.stillSince >= Config.StopSeconds * 1000 then
                            exam.stopped = true
                        end
                    else
                        exam.stillSince = nil
                    end
                end

                if (not stopPoint or exam.stopped) and reachPoint(false) then
                    break
                end
            elseif stopPoint and exam.entered and not exam.stopped and distance > exam.radius + 4.0 then
                fault('arrêt non marqué au STOP')

                if reachPoint(true) then
                    break
                end
            end

            if stopPoint and exam and distance <= exam.radius + 25.0 then
                stopState = exam.stopped and 'done' or 'need'
            end

            lastSpeed = speed
        else
            -- Sortie du véhicule en marche : faute grave ; sinon un délai pour remonter
            if not outSince and lastSpeed > 15.0 then
                majorFault('exit')
            end

            outSince = outSince or now
            lastSpeed = 0
            local left = Config.OutOfVehicleSeconds - math.floor((now - outSince) / 1000)

            if now - lastOutMessage > 1000 then
                lastOutMessage = now
                SendNUIMessage({ action = 'fault', text = ("Remontez dans le véhicule d'examen (%d s)"):format(math.max(0, left)) })
            end

            if left <= 0 then
                TriggerServerEvent('lunatic_driving:abort', 'Sortie du véhicule.')
                break
            end
        end

        if exam and now - lastHud > 150 then
            lastHud = now
            SendNUIMessage({ action = 'hud', data = {
                label = exam.label, speed = math.floor(speed), limit = limit, index = exam.index, total = #exam.points,
                errors = exam.errors, maxErrors = exam.maxErrors, left = math.floor((exam.endsAt - now) / 1000), stop = stopState,
            } })
        end

        Wait(0)
    end
end

RegisterNUICallback('exam', function(data, cb)
    SetNuiFocus(false, false)
    cb(true)

    local res = lib.callback.await('lunatic_driving:startExam', false, type(data) == 'table' and data.id or nil)

    if not res or not res.ok then
        return notify(res and res.error or 'Examen indisponible.', 'error')
    end

    CreateThread(function() runExam(res) end)
end)

RegisterNetEvent('lunatic_driving:examEnded', function(result)
    stopExam()
    SendNUIMessage({ action = 'examEnded', data = { passed = result.passed, reason = result.reason, label = result.label or '' } })

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
-- [E] au PNJ
---------------------------------------------------------------------

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
        SetNuiFocus(false, false)
    end
end)
