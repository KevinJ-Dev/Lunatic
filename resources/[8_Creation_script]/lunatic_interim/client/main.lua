-- Job Center (doc Vision « Jobs de farm ») côté client : [E] au comptoir, écran (html/) avec la fiche du métier, la tenue
-- de travail essayée sur le personnage (caméra de face), Accepter / Quitter le métier. Fermer remet la tenue d'avant.
-- Blip : tuile Blips du panel (Pôle emploi).

local appearance = exports['illenium-appearance']
local center = nil -- { index, data, original, cam, dressed }
local lastIndex = nil -- dernier comptoir ouvert (retour après l'habillage staff)
local shown = false

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function currentOutfit()
    local ped = PlayerPedId()
    return { components = appearance:getPedComponents(ped), props = appearance:getPedProps(ped) }
end

local function applyOutfit(outfit)
    local ped = PlayerPedId()
    appearance:setPedComponents(ped, outfit.components)
    appearance:setPedProps(ped, outfit.props)
end

-- Image et logo d'un métier : tuile Images du panel (clés interim_<id> et interim_logo_<id>)
local function imageOf(key)
    local url = (GlobalState.lunaticImages or {})[key]
    return type(url) == 'string' and url ~= '' and url or nil
end

local function view(data)
    local jobs = {}

    for _, job in ipairs(data.jobs) do
        jobs[#jobs + 1] = {
            id = job.id, label = job.label, company = job.company, color = job.color, salary = job.salary, duration = job.duration,
            participants = job.participants, missions = job.missions, hasOutfit = job.outfit ~= nil,
            image = imageOf('interim_' .. job.id), logo = imageOf('interim_logo_' .. job.id),
        }
    end

    return {
        jobs = jobs, current = data.current, mainJob = data.mainJob, staff = data.staff, model = data.model, currency = GlobalState.lunaticCurrency or '$',
        banner = imageOf('jobcenter_banner'),
    }
end

-- Caméra face au personnage, décalée pour qu'il apparaisse à droite du panneau
local function startCamera()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local h = math.rad(GetEntityHeading(ped))
    local forward, right = vector3(-math.sin(h), math.cos(h), 0.0), vector3(math.cos(h), math.sin(h), 0.0)
    local position = coords + forward * 2.6 + vector3(0.0, 0.0, 0.3)
    local target = coords + right * 0.6 + vector3(0.0, 0.0, 0.1)

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, position.x, position.y, position.z)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamFov(cam, 45.0)
    RenderScriptCams(true, true, 500, true, true)
    return cam
end

local function close(keep)
    if not center then
        return
    end

    -- Staff habillé pour une tenue d'intérim (homme ou femme) : son vrai personnage revient
    if not keep and center.dressed then
        TriggerEvent('illenium-appearance:client:reloadSkin', true)
    elseif not keep and center.original then
        applyOutfit(center.original)
    end

    if center.cam then
        RenderScriptCams(false, true, 400, true, true)
        DestroyCam(center.cam, false)
    end

    FreezeEntityPosition(PlayerPedId(), false)
    center = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function open(index, dressed)
    local data = lib.callback.await('lunatic_interim:open', false, index)

    if not data or not data.ok then
        return notify(data and data.error or 'Job Center indisponible.', 'error')
    end

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    lastIndex = index
    center = { index = index, data = data, original = currentOutfit(), dressed = dressed }
    center.cam = startCamera()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', center = view(data) })
end

local function jobData(id)
    for _, job in ipairs(center and center.data.jobs or {}) do
        if job.id == id then
            return job
        end
    end
end

-- Métier choisi : sa tenue est essayée (sinon la tenue d'avant)
RegisterNUICallback('preview', function(data, cb)
    cb({})
    local job = jobData(data.id)

    if center then
        applyOutfit(job and job.outfit or center.original)
    end
end)

RegisterNUICallback('accept', function(data, cb)
    if not center then
        return cb({ ok = false, error = 'Job Center fermé.' })
    end

    local result = lib.callback.await('lunatic_interim:accept', false, center.index, data.id) or { ok = false, error = 'Action impossible.' }
    cb(result)

    if result.ok then
        if result.outfit then
            applyOutfit(result.outfit)
        end

        close(result.outfit ~= nil)
        notify(('Vous êtes maintenant %s. Les missions arrivent bientôt.'):format(result.label:lower()), 'success')
    end
end)

RegisterNUICallback('quit', function(_, cb)
    if not center then
        return cb({ ok = false, error = 'Job Center fermé.' })
    end

    local result = lib.callback.await('lunatic_interim:quit', false, center.index) or { ok = false, error = 'Action impossible.' }
    cb(result)

    if result.ok then
        close(true)
        TriggerEvent('illenium-appearance:client:reloadSkin', true)
        notify(('Vous avez quitté le métier de %s.'):format(result.label:lower()), 'info')
    end
end)

-- Staff : la tenue portée en ouvrant le Job Center devient celle du métier
RegisterNUICallback('saveOutfit', function(data, cb)
    if not center then
        return cb({ ok = false, error = 'Job Center fermé.' })
    end

    local result = lib.callback.await('lunatic_interim:saveOutfit', false, center.index, data.id, center.original) or { ok = false, error = 'Action impossible.' }

    if result.ok then
        local fresh = lib.callback.await('lunatic_interim:open', false, center.index)

        if fresh and fresh.ok and center then
            center.data = fresh
            result.center = view(fresh)
        end
    end

    cb(result)
end)

RegisterNUICallback('close', function(_, cb)
    cb({})
    close(false)
end)

-- Staff : habillage libre (lunatic_clothing, homme ou femme), puis retour au comptoir pour enregistrer la tenue
RegisterNUICallback('dress', function(_, cb)
    if not center then
        return cb({ ok = false, error = 'Job Center fermé.' })
    end

    -- Tenue d'un métier essayée : on repart de la tenue portée en ouvrant le Job Center
    local index, dressed, original = center.index, center.dressed, center.original
    close(true)

    if not dressed and original then
        applyOutfit(original)
    end

    local result = lib.callback.await('lunatic_interim:dress', false, index) or { ok = false, error = 'Habillage indisponible.' }
    cb(result)

    if not result.ok then
        notify(result.error, 'error')
    end
end)

-- Tenue validée dans l'habillage : retour au comptoir, la tenue portée est prête à être enregistrée
AddEventHandler('lunatic_interim:dressed', function()
    if lastIndex and not center then
        Wait(300)
        open(lastIndex, true)
        notify('Tenue prête : « Enregistrer ma tenue » sur le métier voulu. Fermer le Job Center vous rend votre personnage.', 'info')
    end
end)

-- Comptoir : [E]
CreateThread(function()
    while true do
        local wait = 1000

        if not center then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local near = nil

            for index, spot in ipairs(Centers()) do
                local distance = #(coords - vector3(spot.x, spot.y, spot.z))

                if distance < 15.0 then
                    wait = 250
                end

                if distance <= Config.Distance and not IsPedInAnyVehicle(ped, false) then
                    near = index
                    break
                end
            end

            if near then
                wait = 0
                local label = ('[E] %s'):format(Centers()[near].label)

                if shown ~= label then
                    shown = label
                    lib.showTextUI(label)
                end

                if IsControlJustReleased(0, 38) then
                    shown = false
                    lib.hideTextUI()
                    open(near)
                end
            elseif shown then
                shown = false
                lib.hideTextUI()
            end
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if shown then
            lib.hideTextUI()
        end

        close(false)
    end
end)
