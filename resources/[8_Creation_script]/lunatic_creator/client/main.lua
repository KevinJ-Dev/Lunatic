-- Création de personnage, côté client : pièce privée, caméras, aperçu en direct (héritage, pilosité, yeux,
-- maquillage, détails, traits du visage), puis enregistrement (identité par esx_identity, apparence par
-- illenium-appearance). Ouverte par esx_identity (« lunatic_creator:open ») à la première connexion ou après
-- « Recréer » dans le panel staff.

local active = false
local cam = nil
local cameraIndex = 2
local heading = Config.Room.w

local MODELS = { male = `mp_m_freemode_01`, female = `mp_f_freemode_01` }
-- Type de couleur de chaque calque du visage : 1 = couleurs des cheveux, 2 = maquillage
local OVERLAY_COLOR_TYPE = { [1] = 1, [2] = 1, [10] = 1, [5] = 2, [8] = 2 }

local appearance -- choix en cours (renvoyé tel quel par l'interface)

local function defaults(sex)
    return {
        sex = sex,
        heritage = { father = 0, mother = 21, shape = 0.5, skin = 0.5 },
        hair = { style = 0, color = 0, highlight = 0 },
        eyeColor = 0,
        overlays = {},
        features = {},
    }
end

local appearanceApi = function()
    return exports['illenium-appearance']
end

---------------------------------------------------------------------
-- Application sur le personnage
---------------------------------------------------------------------

local function undress(ped, sex)
    for component, drawable in pairs(Config.Undress[sex] or {}) do
        SetPedComponentVariation(ped, component, drawable, 0, 0)
    end

    ClearAllPedProps(ped)
end

local function applyHeritage(ped)
    local h = appearance.heritage
    SetPedHeadBlendData(ped, h.father, h.mother, 0, h.father, h.mother, 0, h.shape + 0.0, h.skin + 0.0, 0.0, false)
end

local function applyHair(ped)
    local hair = appearance.hair
    SetPedComponentVariation(ped, 2, hair.style, 0, 0)
    SetPedHairColor(ped, hair.color, hair.highlight)
end

local function applyOverlay(ped, index)
    local o = appearance.overlays[tostring(index)]

    if not o or o.style < 0 then
        SetPedHeadOverlay(ped, index, 255, 0.0)
        return
    end

    SetPedHeadOverlay(ped, index, o.style, (o.opacity or 1.0) + 0.0)

    local colorType = OVERLAY_COLOR_TYPE[index]

    if colorType then
        SetPedHeadOverlayColor(ped, index, colorType, o.color or 0, o.color or 0)
    end
end

local function applyAll()
    local ped = PlayerPedId()
    applyHeritage(ped)
    applyHair(ped)
    SetPedEyeColor(ped, appearance.eyeColor)

    for index = 0, 12 do
        applyOverlay(ped, index)
    end

    for index = 0, 19 do
        SetPedFaceFeature(ped, index, (appearance.features[tostring(index)] or 0.0) + 0.0)
    end
end

local function setSex(sex)
    appearanceApi():setPlayerModel(MODELS[sex])
    local ped = PlayerPedId()
    SetEntityCoords(ped, Config.Room.x, Config.Room.y, Config.Room.z - 0.98, false, false, false, false)
    SetEntityHeading(ped, heading)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    undress(ped, sex)
    applyAll()
end

-- Nombre de choix et palettes, selon le modèle (envoyé à l'interface)
local function options()
    local ped = PlayerPedId()
    local overlayCounts = {}

    for index = 0, 12 do
        overlayCounts[tostring(index)] = GetPedHeadOverlayNum(index)
    end

    local hairColors, makeupColors = {}, {}

    for i = 0, GetNumHairColors() - 1 do
        local r, g, b = GetPedHairRgbColor(i)
        hairColors[#hairColors + 1] = { r, g, b }
    end

    for i = 0, GetNumMakeupColors() - 1 do
        local r, g, b = GetMakeupRgbColor(i)
        makeupColors[#makeupColors + 1] = { r, g, b }
    end

    return {
        hairStyles = GetNumberOfPedDrawableVariations(ped, 2),
        overlays = overlayCounts,
        hairColors = hairColors,
        makeupColors = makeupColors,
    }
end

---------------------------------------------------------------------
-- Caméras
---------------------------------------------------------------------

local function setCamera(index, instant)
    local settings = Config.Cameras[index] or Config.Cameras[2]
    cameraIndex = index

    local base = vector3(Config.Room.x, Config.Room.y, Config.Room.z)
    local angle = math.rad(Config.Room.w)
    local forward = vector3(-math.sin(angle), math.cos(angle), 0.0)
    local position = base + forward * settings.distance + vector3(0.0, 0.0, settings.height)

    local new = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', position.x, position.y, position.z, 0.0, 0.0, 0.0, settings.fov, false, 2)
    PointCamAtCoord(new, base.x, base.y, base.z + settings.height)

    if cam and not instant then
        SetCamActiveWithInterp(new, cam, 600, 1, 1)
        local old = cam
        SetTimeout(700, function() DestroyCam(old, false) end)
    else
        if cam then
            DestroyCam(cam, false)
        end

        SetCamActive(new, true)
        RenderScriptCams(true, false, 0, true, true)
    end

    cam = new
end

local function stopCamera()
    RenderScriptCams(false, true, 500, true, true)

    if cam then
        DestroyCam(cam, false)
        cam = nil
    end
end

---------------------------------------------------------------------
-- Ouverture et fermeture
---------------------------------------------------------------------

local function fade(out)
    if out then
        DoScreenFadeOut(500)

        while not IsScreenFadedOut() do
            Wait(0)
        end
    else
        DoScreenFadeIn(600)
    end
end

local function open()
    if active then
        return
    end

    active = true
    fade(true)
    TriggerServerEvent('lunatic_creator:enter')

    appearance = defaults('male')
    heading = Config.Room.w
    RequestCollisionAtCoord(Config.Room.x, Config.Room.y, Config.Room.z)
    setSex('male')

    local timeout = GetGameTimer() + 5000

    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < timeout do
        Wait(0)
    end

    RequestStreamedTextureDict('char_creator_portraits', true)
    DisplayRadar(false)
    setCamera(2, true)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        appearance = appearance,
        options = options(),
        config = { height = Config.Height, age = Config.Age, cameras = #Config.Cameras },
    })

    Wait(300)
    fade(false)

    -- Pas de HUD ni d'actions pendant la création
    CreateThread(function()
        while active do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            Wait(0)
        end
    end)
end

local function close(spawn)
    fade(true)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    stopCamera()

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    TriggerServerEvent('lunatic_creator:leave')
    active = false

    if spawn then
        RequestCollisionAtCoord(spawn.x, spawn.y, spawn.z)
        SetEntityCoords(ped, spawn.x, spawn.y, spawn.z - 0.98, false, false, false, false)
        SetEntityHeading(ped, spawn.w)
    end

    DisplayRadar(true)
    Wait(800)
    fade(false)
end

AddEventHandler('lunatic_creator:open', open)

---------------------------------------------------------------------
-- Interface
---------------------------------------------------------------------

RegisterNUICallback('sex', function(data, cb)
    local sex = data.sex == 'female' and 'female' or 'male'

    if sex ~= appearance.sex then
        -- Nouveau modèle : on repart des réglages par défaut du sexe choisi (coiffures et calques diffèrent)
        appearance = defaults(sex)

        if sex == 'female' then
            appearance.heritage = { father = 0, mother = 21, shape = 0.8, skin = 0.5 }
        end

        setSex(sex)
    end

    cb({ appearance = appearance, options = options() })
end)

-- Modification de l'apparence (l'interface envoie l'état complet)
RegisterNUICallback('appearance', function(data, cb)
    if type(data) == 'table' and type(data.heritage) == 'table' then
        data.sex = appearance.sex
        appearance = data
        applyAll()
    end

    cb({})
end)

RegisterNUICallback('camera', function(data, cb)
    local index = tonumber(data.index)

    if index and Config.Cameras[index] and index ~= cameraIndex then
        setCamera(index, false)
    end

    cb({})
end)

RegisterNUICallback('rotate', function(data, cb)
    heading = (heading + (tonumber(data.delta) or 0)) % 360
    SetEntityHeading(PlayerPedId(), heading)
    cb({})
end)

-- Fin de la création : identité (esx_identity), apparence (illenium-appearance), lieu de naissance
RegisterNUICallback('finish', function(data, cb)
    local identity = type(data) == 'table' and data.identity

    if type(identity) ~= 'table' then
        return cb({ ok = false, error = 'Identité incomplète.' })
    end

    local ok = exports.esx_identity:registerIdentity({
        firstname = identity.firstname, lastname = identity.lastname, dateofbirth = identity.dateofbirth,
        sex = appearance.sex == 'female' and 'f' or 'm', height = tonumber(identity.height),
    })

    if not ok then
        return cb({ ok = false, error = "Identité refusée : vérifiez le nom, le prénom et la date de naissance." })
    end

    TriggerServerEvent('illenium-appearance:server:saveAppearance', appearanceApi():getPedAppearance(PlayerPedId()))
    lib.callback.await('lunatic_creator:saveInfo', false, { birthplace = identity.birthplace or '' })

    cb({ ok = true })
    close(Config.DefaultSpawn)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and active then
        SetNuiFocus(false, false)
        stopCamera()
        FreezeEntityPosition(PlayerPedId(), false)
        DisplayRadar(true)
        DoScreenFadeIn(0)
    end
end)
