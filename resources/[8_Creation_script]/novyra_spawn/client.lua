local ESX = exports['es_extended']:getSharedObject()

local State = {
    loaded   = false,  -- le joueur est entré en ville
    open     = false,  -- l'écran est affiché
    entering = false,  -- transition d'entrée en cours
    shot     = 0,
}

local shotCams, enterCams = {}, {}

-- ═════════════════════════════════════════════
--  Caméras
-- ═════════════════════════════════════════════
local function killCams(list)
    for i = #list, 1, -1 do
        if DoesCamExist(list[i]) then
            SetCamActive(list[i], false)
            DestroyCam(list[i], false)
        end
        list[i] = nil
    end
end

local function newCam(pos, rot, fov)
    return CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, fov or 60.0, false, 2)
end

local function playShot(i)
    local s = Config.Cameras[i]
    if not s then return end

    SetFocusPosAndVel(s.coords.x, s.coords.y, s.coords.z, 0.0, 0.0, 0.0)

    local yaw   = math.rad(s.rot.z)
    local drift = vec3(math.cos(yaw), math.sin(yaw), 0.0) * (Config.ShotDrift or 6.0)

    local from = newCam(s.coords, s.rot, s.fov)
    local to   = newCam(s.coords + drift, s.rot, s.fov)

    local old = shotCams
    shotCams = { from, to }

    SetCamActive(from, true)
    RenderScriptCams(true, false, 0, true, true)
    SetCamActiveWithInterp(to, from, Config.ShotDuration, 0, 0)
    ShakeCam(to, 'HAND_SHAKE', 0.12)
    killCams(old)

    SendNUIMessage({ action = 'shot', label = s.label, index = i, total = #Config.Cameras, duration = Config.ShotDuration })
end

local function shotLoop()
    CreateThread(function()
        State.shot = 1
        playShot(1)

        while State.open and not State.entering do
            local t = 0
            while t < Config.ShotDuration - 700 do
                if not State.open or State.entering then return end
                Wait(100)
                t = t + 100
            end

            if #Config.Cameras > 1 then
                DoScreenFadeOut(600)
                Wait(650)
                if not State.open or State.entering then return end
                State.shot = State.shot % #Config.Cameras + 1
                playShot(State.shot)
                Wait(350)
                DoScreenFadeIn(700)
            else
                playShot(State.shot)
            end
        end
    end)
end

-- ═════════════════════════════════════════════
--  Données joueur
-- ═════════════════════════════════════════════
local function account(name)
    for _, a in ipairs(ESX.PlayerData.accounts or {}) do
        if a.name == name then return a.money end
    end
    return 0
end

local function location(ped)
    local c = GetEntityCoords(ped)
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(c.x, c.y, c.z))
    local zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
    if zone == 'NULL' then zone = '' end
    if street ~= '' and zone ~= '' then return street .. ', ' .. zone end
    return street ~= '' and street or (zone ~= '' and zone or 'Los Santos')
end

local function jobLabel()
    local job = ESX.PlayerData.job
    if not job or job.name == 'unemployed' then return 'Sans emploi' end
    if job.grade_label and job.grade_label ~= '' then
        return ('%s · %s'):format(job.label, job.grade_label)
    end
    return job.label
end

-- ═════════════════════════════════════════════
--  Ouverture / fermeture
-- ═════════════════════════════════════════════
local function hudLoop()
    CreateThread(function()
        while State.open do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            Wait(0)
        end
    end)
end

local function open(info)
    if State.open then return end
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end

    State.open, State.entering, State.loaded = true, false, false
    TriggerEvent('novyra_spawn:opened')

    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    DisplayRadar(false)

    hudLoop()
    shotLoop()

    SendNUIMessage({
        action = 'open',
        config = {
            serverName = Config.ServerName,
            tagline    = Config.Tagline,
            logo       = Config.Logo,
            centerLogo = Config.CenterLogo,
            accent     = Config.Accent,
            accent2    = Config.Accent2,
            discord    = Config.Discord,
            enterKey   = Config.EnterKey,
            showInfo   = Config.ShowInfo,
            letterbox  = Config.Letterbox,
            news       = Config.News,
        },
        player = {
            name       = info.name,
            job        = jobLabel(),
            location   = location(ped),
            cash       = account('money'),
            bank       = account('bank'),
            players    = info.players,
            maxPlayers = info.maxPlayers,
        },
    })

    SetNuiFocus(true, true)
    if IsScreenFadedOut() then DoScreenFadeIn(800) end
end

local function reset()
    SetNuiFocus(false, false)
    killCams(shotCams)
    killCams(enterCams)
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()

    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        FreezeEntityPosition(ped, false)
        SetEntityVisible(ped, true, false)
        SetEntityInvincible(ped, false)
    end

    DisplayRadar(true)
    if IsScreenFadedOut() then DoScreenFadeIn(300) end
end

-- ═════════════════════════════════════════════
--  Entrée en ville
-- ═════════════════════════════════════════════
local function transitionDescend(ped)
    local p, h = GetEntityCoords(ped), GetEntityHeading(ped)

    DoScreenFadeOut(500)
    Wait(550)
    killCams(shotCams)
    ClearFocus()
    SetEntityVisible(ped, true, false)

    local sky  = newCam(vec3(p.x, p.y, p.z + 70.0), vec3(-89.0, 0.0, h), 50.0)
    local back = newCam(GetOffsetFromEntityInWorldCoords(ped, 0.0, -3.2, 0.9), vec3(0.0, 0.0, h), 50.0)
    PointCamAtEntity(back, ped, 0.0, 0.0, 0.5, true)
    enterCams = { sky, back }

    SetCamActive(sky, true)
    RenderScriptCams(true, false, 0, true, true)
    Wait(300)
    DoScreenFadeIn(500)

    SetCamActiveWithInterp(back, sky, 2600, 1, 1)
    Wait(2600)
    RenderScriptCams(false, true, 1000, true, true)
    Wait(1000)
end

local function transitionFade(ped)
    DoScreenFadeOut(500)
    Wait(600)
    killCams(shotCams)
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()
    SetEntityVisible(ped, true, false)
    Wait(200)
    DoScreenFadeIn(700)
end

local function enter(name)
    if not State.open or State.entering then return end
    State.entering = true
    SetNuiFocus(false, false)

    local ped = PlayerPedId()
    if Config.Transition == 'descend' then transitionDescend(ped) else transitionFade(ped) end

    State.open = false
    reset()
    State.loaded, State.entering = true, false

    TriggerEvent('novyra_spawn:entered')

    if Config.Welcome and Config.Welcome ~= '' then
        ESX.ShowNotification((Config.Welcome:gsub('{name}', name or '')))
    end
end

RegisterNUICallback('enter', function(data, cb)
    local ok = State.open and not State.entering
    cb({ ok = ok })
    if ok then CreateThread(function() enter(data and data.name) end) end
end)

-- ═════════════════════════════════════════════
--  Chargement du joueur (ESX uniquement)
-- ═════════════════════════════════════════════
RegisterNetEvent('esx:playerLoaded', function(xPlayer, isNew)
    ESX.PlayerData = xPlayer
    State.loaded = false

    -- Nouveau personnage : on laisse la création de personnage se faire
    if isNew then
        State.loaded = true
        return
    end

    CreateThread(function()
        -- attend que le ped soit prêt et l'écran de chargement fermé
        local timeout = GetGameTimer() + 15000
        while (not DoesEntityExist(PlayerPedId()) or GetIsLoadingScreenActive()) and GetGameTimer() < timeout do
            Wait(100)
        end
        Wait(Config.OpenDelay or 1000)

        ESX.TriggerServerCallback('novyra_spawn:getInfo', function(info)
            open(info or {})
        end)
    end)
end)

RegisterNetEvent('esx:setJob', function(job)
    ESX.PlayerData.job = job
end)

-- ═════════════════════════════════════════════
--  Exports
-- ═════════════════════════════════════════════
exports('playerLoaded', function() return State.loaded end)
exports('isOpen', function() return State.open end)

-- ═════════════════════════════════════════════
--  Outil : récupérer un plan caméra
-- ═════════════════════════════════════════════
if Config.CamCommand and Config.CamCommand ~= '' then
    RegisterCommand(Config.CamCommand, function()
        local c, r, f = GetGameplayCamCoord(), GetGameplayCamRot(2), GetGameplayCamFov()
        print(("{ label = 'Nouveau plan', coords = vec3(%.2f, %.2f, %.2f), rot = vec3(%.2f, 0.0, %.2f), fov = %.1f },")
            :format(c.x, c.y, c.z, r.x, r.z, f))
        ESX.ShowNotification('Plan caméra affiché dans la console F8')
    end, false)
end

-- ═════════════════════════════════════════════
--  Restart de la ressource
-- ═════════════════════════════════════════════
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    State.loaded = ESX.PlayerLoaded == true
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    State.open = false
    reset()
end)
