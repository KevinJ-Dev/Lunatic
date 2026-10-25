-- Création de personnage, côté client : pièce privée, caméras, aperçu en direct (héritage, pilosité, yeux,
-- maquillage, détails, traits du visage, vêtements), aperçu du lieu d'apparition, puis enregistrement
-- (identité par server/identity.lua, apparence par illenium-appearance), photo d'identité et arrivée avec l'animation GTA.
-- Ouverte par le serveur (« lunatic_creator:start ») à la première connexion ou après « Recréer » dans le panel.

local active = false
local cam = nil
local cameraIndex = 2
local anchor = Config.Room   -- position du personnage (la pièce, puis l'aperçu du lieu d'apparition)
local heading = Config.Room.w
local spawnIndex = nil

local MODELS = { male = `mp_m_freemode_01`, female = `mp_f_freemode_01` }
-- Type de couleur de chaque calque du visage : 1 = couleurs des cheveux, 2 = maquillage
local OVERLAY_COLOR_TYPE = { [1] = 1, [2] = 1, [10] = 1, [5] = 2, [8] = 2 }

local appearance -- choix en cours (renvoyé tel quel par l'interface)

-- Tenue de départ : { components = { ["11"] = { drawable, texture } }, props = { ... } } (clés texte pour l'interface)
local function starterClothes(sex)
    local starter = Config.StarterOutfit[sex] or { components = {}, props = {} }
    local clothes = { components = {}, props = {} }

    for id, value in pairs(starter.components or {}) do
        clothes.components[tostring(id)] = { value[1], value[2] }
    end

    for id, value in pairs(starter.props or {}) do
        clothes.props[tostring(id)] = { value[1], value[2] }
    end

    return clothes
end

local function defaults(sex)
    return {
        sex = sex,
        heritage = sex == 'female' and { father = 0, mother = 21, shape = 0.8, skin = 0.5 } or { father = 0, mother = 21, shape = 0.5, skin = 0.5 },
        hair = { style = 0, color = 0, highlight = 0 },
        eyeColor = 0,
        overlays = {},
        features = {},
        clothes = starterClothes(sex),
    }
end

local appearanceApi = function()
    return exports['illenium-appearance']
end

---------------------------------------------------------------------
-- Application sur le personnage
---------------------------------------------------------------------

local function applyClothes(ped)
    for component, drawable in pairs(Config.Undress[appearance.sex] or {}) do
        SetPedComponentVariation(ped, component, drawable, 0, 0)
    end

    ClearAllPedProps(ped)
    local clothes = appearance.clothes or {}

    for id, value in pairs(clothes.components or {}) do
        SetPedComponentVariation(ped, tonumber(id), value[1], value[2] or 0, 0)
    end

    for id, value in pairs(clothes.props or {}) do
        if value[1] >= 0 then
            SetPedPropIndex(ped, tonumber(id), value[1], value[2] or 0, true)
        end
    end
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
    applyClothes(ped)
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

local function placePed()
    local ped = PlayerPedId()
    SetEntityCoords(ped, anchor.x, anchor.y, anchor.z - 0.98, false, false, false, false)
    SetEntityHeading(ped, heading)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
end

local function setSex(sex)
    appearanceApi():setPlayerModel(MODELS[sex])
    placePed()
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

-- Nombre de modèles et de couleurs d'un vêtement (selon le modèle choisi)
local function clothesCounts(kind, id, drawable)
    local ped = PlayerPedId()

    if kind == 'prop' then
        return { drawables = GetNumberOfPedPropDrawableVariations(ped, id), textures = drawable >= 0 and GetNumberOfPedPropTextureVariations(ped, id, drawable) or 0 }
    end

    return { drawables = GetNumberOfPedDrawableVariations(ped, id), textures = GetNumberOfPedTextureVariations(ped, id, drawable) }
end

---------------------------------------------------------------------
-- Caméras (relatives à la position du personnage : pièce ou lieu d'apparition)
---------------------------------------------------------------------

local function setCamera(index, instant)
    local settings = Config.Cameras[index] or Config.Cameras[2]
    cameraIndex = index

    local base = vector3(anchor.x, anchor.y, anchor.z)
    local angle = math.rad(anchor.w)
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

local function stopCamera(ease)
    RenderScriptCams(false, ease == true, ease and 500 or 0, true, true)

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

local function waitCollision()
    RequestCollisionAtCoord(anchor.x, anchor.y, anchor.z)
    local timeout = GetGameTimer() + 5000

    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < timeout do
        Wait(0)
    end
end

local function spawnList()
    local list = {}

    for index, spawn in ipairs(Config.Spawns) do
        list[#list + 1] = { index = index, group = spawn.group, label = spawn.label, image = spawn.image }
    end

    return list
end

local function clothesList()
    local list = {}

    for index, entry in ipairs(Config.Clothes) do
        list[#list + 1] = { index = index, label = entry.label, kind = entry.kind, id = entry.id, camera = entry.camera, extra = entry.extra }
    end

    return list
end

local function open()
    if active then
        return
    end

    active = true
    fade(true)
    TriggerServerEvent('lunatic_creator:enter')

    appearance = defaults('male')
    anchor, heading, spawnIndex = Config.Room, Config.Room.w, nil
    setSex('male')
    waitCollision()

    RequestStreamedTextureDict('char_creator_portraits', true)
    DisplayRadar(false)
    setCamera(2, true)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        appearance = appearance,
        options = options(),
        config = {
            height = Config.Height, age = Config.Age, cameras = #Config.Cameras, spawns = spawnList(), clothes = clothesList(),
            mugshot = Config.MugshotSeconds, nationalities = Config.Nationalities, names = Config.RandomNames,
        },
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

-- Arrivée en ville avec l'animation de changement de personnage de GTA (caméra qui monte puis redescend)
local function arrive()
    local ped = PlayerPedId()
    SwitchOutPlayer(ped, 0, 1)

    local timeout = GetGameTimer() + 8000

    while GetPlayerSwitchState() ~= 5 and GetGameTimer() < timeout do
        Wait(0)
    end

    -- En l'air : le joueur rejoint le monde de tous, puis la caméra redescend sur lui
    SendNUIMessage({ action = 'close' })
    TriggerServerEvent('lunatic_creator:leave')
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    Wait(1500)
    SwitchInPlayer(ped)

    timeout = GetGameTimer() + 15000

    while IsPlayerSwitchInProgress() and GetGameTimer() < timeout do
        Wait(0)
    end

    DisplayRadar(true)
    active = false
end

-- Ouverte par le serveur (server/identity.lua) : première connexion sans identité ou « Recréer » du panel
RegisterNetEvent('lunatic_creator:start', function()
    -- Attend la fin de l'écran de chargement et que le personnage soit en vie
    while GetIsLoadingScreenActive() or not ESX.PlayerLoaded or ESX.PlayerData.dead do
        Wait(200)
    end

    Wait(500)
    open()
end)

-- Identité enregistrée (ou effacée) par le serveur : données ESX du client à jour
RegisterNetEvent('lunatic_creator:setPlayerData', function(identity, name)
    ESX.SetPlayerData('name', name)

    for _, key in ipairs({ 'firstName', 'lastName', 'dateofbirth', 'sex', 'height' }) do
        ESX.SetPlayerData(key, identity and identity[key] or nil)
    end
end)

---------------------------------------------------------------------
-- Interface
---------------------------------------------------------------------

RegisterNUICallback('sex', function(data, cb)
    local sex = data.sex == 'female' and 'female' or 'male'

    if sex ~= appearance.sex then
        -- Nouveau modèle : on repart des réglages par défaut du sexe choisi (coiffures, calques et vêtements diffèrent)
        appearance = defaults(sex)
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

-- Nombre de modèles / couleurs d'un vêtement
RegisterNUICallback('clothesCounts', function(data, cb)
    cb(clothesCounts(data.kind == 'prop' and 'prop' or 'component', tonumber(data.id) or 0, tonumber(data.drawable) or 0))
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

-- Aperçu d'un lieu d'apparition : le personnage y est placé (seul, dans son instance)
RegisterNUICallback('spawn', function(data, cb)
    local spawn = Config.Spawns[tonumber(data.index) or 0]
    cb({})

    if not spawn or spawnIndex == tonumber(data.index) then
        return
    end

    spawnIndex = tonumber(data.index)
    fade(true)
    anchor = spawn.coords
    heading = spawn.coords.w
    placePed()
    waitCollision()
    setCamera(3, true)
    Wait(200)
    fade(false)
end)

-- Fin de la création : identité et nationalité, apparence (illenium-appearance), photo, arrivée
RegisterNUICallback('finish', function(data, cb)
    local identity = type(data) == 'table' and data.identity

    if type(identity) ~= 'table' then
        return cb({ ok = false, error = 'Identité incomplète.' })
    end

    if not spawnIndex or not Config.Spawns[spawnIndex] then
        return cb({ ok = false, error = "Choisissez un lieu d'apparition." })
    end

    -- Le serveur revérifie tout (nom, date, taille, genre, nationalité) avant d'enregistrer
    local result = lib.callback.await('lunatic_creator:registerIdentity', false, {
        firstname = identity.firstname, lastname = identity.lastname, dateofbirth = identity.dateofbirth,
        sex = appearance.sex == 'female' and 'f' or 'm', height = tonumber(identity.height), nationality = identity.nationality,
    })

    if type(result) ~= 'table' or not result.ok then
        return cb({ ok = false, error = type(result) == 'table' and result.error or 'Identité refusée.' })
    end

    TriggerServerEvent('illenium-appearance:server:saveAppearance', appearanceApi():getPedAppearance(PlayerPedId()))
    cb({ ok = true })

    -- Photo d'identité : face à l'objectif, quelques secondes
    heading = anchor.w
    SetEntityHeading(PlayerPedId(), heading)
    setCamera(1, false)
    SendNUIMessage({ action = 'mugshot', seconds = Config.MugshotSeconds })
    Wait(1200)
    lib.callback.await('lunatic_creator:mugshot', false)
    Wait(math.max(0, Config.MugshotSeconds * 1000 - 1200))

    SetNuiFocus(false, false)
    stopCamera(false)
    arrive()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and active then
        SetNuiFocus(false, false)
        stopCamera(false)
        FreezeEntityPosition(PlayerPedId(), false)
        DisplayRadar(true)
        DoScreenFadeIn(0)
    end
end)
