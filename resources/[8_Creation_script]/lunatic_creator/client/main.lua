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
local spawns = {}            -- lieux d'apparition figés à l'ouverture (panel staff ou config)
local cameraShift = Config.CameraShift -- décalage du personnage selon les panneaux affichés

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
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
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

    local angle = math.rad(anchor.w)
    local forward = vector3(-math.sin(angle), math.cos(angle), 0.0)
    local right = vector3(math.cos(angle), math.sin(angle), 0.0)
    -- Le panneau occupe la gauche de l'écran : caméra et visée glissent sur le côté pour centrer le personnage à droite
    local halfWidth = settings.distance * math.tan(math.rad(settings.fov) / 2) * GetAspectRatio(false)
    local base = vector3(anchor.x, anchor.y, anchor.z) + right * (halfWidth * cameraShift)
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

    for index, spawn in ipairs(spawns) do
        list[#list + 1] = { index = index, group = spawn.group, label = spawn.label, image = spawn.image }
    end

    return list
end

local function clothesList()
    local list = {}

    for index, entry in ipairs(Config.Clothes) do
        list[#list + 1] = { index = index, label = entry.label, kind = entry.kind, id = entry.id, camera = entry.camera, icon = entry.icon }
    end

    return list
end

-- Lumières autour du personnage (décalages par rapport au point de création : droite, devant, hauteur)
local function drawLights()
    local angle = math.rad(anchor.w)
    local forward = vector3(-math.sin(angle), math.cos(angle), 0.0)
    local right = vector3(math.cos(angle), math.sin(angle), 0.0)
    local base = vector3(anchor.x, anchor.y, anchor.z)

    for _, light in ipairs(Config.Lights) do
        local at = base + right * light.offset.x + forward * light.offset.y + vector3(0.0, 0.0, light.offset.z)
        DrawLightWithRange(at.x, at.y, at.z, light.color[1], light.color[2], light.color[3], light.range, light.intensity)
    end
end

local function branding()
    local images = GlobalState.lunaticImages or {}
    local settings = GlobalState.lunaticCreator or {}

    return {
        banner = settings.showBanner ~= false and images.creator_banner or nil,
        logo = settings.showLogo ~= false and (images.creator_logo or 'logo.png') or nil,
    }
end

local function open()
    if active then
        return
    end

    active = true

    -- L'écran d'entrée de novyra_spawn se ferme tout seul quand la création démarre
    local timeout = GetGameTimer() + 3000

    while GetResourceState('novyra_spawn') == 'started' and exports.novyra_spawn:isOpen() and GetGameTimer() < timeout do
        Wait(100)
    end

    fade(true)
    TriggerServerEvent('lunatic_creator:enter')

    spawns = CreatorSpawns()
    cameraShift = Config.CameraShift
    anchor, heading, spawnIndex = Config.Room, Config.Room.w, nil

    -- Création interrompue (crash, déconnexion) : on reprend l'étape et les choix enregistrés
    local draft = lib.callback.await('lunatic_creator:getDraft', false)
    local saved = type(draft) == 'table' and type(draft.appearance) == 'table' and draft.appearance or nil

    appearance = defaults(saved and saved.sex == 'female' and 'female' or 'male')
    setSex(appearance.sex)

    if saved then
        saved.sex = appearance.sex
        appearance = saved

        if not pcall(applyAll) then
            appearance = defaults(appearance.sex)
            applyAll()
            draft.appearance = nil
        end
    end

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
            clothesImages = (GlobalState.lunaticCreator or {}).clothesImages or Config.ClothesImages,
        },
        branding = branding(),
        draft = type(draft) == 'table' and { step = draft.step, identity = draft.identity } or nil,
    })

    Wait(300)
    fade(false)

    -- Pas de HUD ni d'actions pendant la création ; éclairage studio et heure fixe
    CreateThread(function()
        while active do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            NetworkOverrideClockTime(Config.ClockHour, 0, 0)
            drawLights()

            local ped = PlayerPedId()

            if GetEntityHealth(ped) < GetEntityMaxHealth(ped) then
                SetEntityHealth(ped, GetEntityMaxHealth(ped))
            end

            Wait(0)
        end
    end)
end

-- Heure du serveur (lunatic_world) une fois la création terminée
local function restoreClock()
    local clock = GlobalState.lunaticClock

    if type(clock) == 'table' then
        NetworkOverrideClockTime(tonumber(clock.h) or 12, tonumber(clock.m) or 0, 0)
    else
        NetworkClearClockTimeOverride()
    end
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
    restoreClock()
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

-- Panneau de droite ouvert ou fermé : le personnage reste centré dans l'espace libre
RegisterNUICallback('layout', function(data, cb)
    cb({})
    local shift = data.side == true and Config.CameraShiftBoth or Config.CameraShift

    if shift ~= cameraShift then
        cameraShift = shift

        if active then
            setCamera(cameraIndex, false)
        end
    end
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
    local spawn = spawns[tonumber(data.index) or 0]
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

-- Brouillon (étape, identité saisie, apparence) : permet de reprendre après un crash ou une déconnexion
RegisterNUICallback('draft', function(data, cb)
    cb({})

    if active and type(data) == 'table' then
        lib.callback.await('lunatic_creator:saveDraft', false, { step = tonumber(data.step), identity = data.identity, appearance = appearance })
    end
end)

-- Fin de la création : identité et nationalité, apparence (illenium-appearance), photo, arrivée
RegisterNUICallback('finish', function(data, cb)
    local identity = type(data) == 'table' and data.identity

    if type(identity) ~= 'table' then
        return cb({ ok = false, error = 'Identité incomplète.' })
    end

    if not spawnIndex or not spawns[spawnIndex] then
        return cb({ ok = false, error = "Choisissez un lieu d'apparition." })
    end

    -- Le serveur revérifie tout (nom, date, taille, genre, nationalité) avant d'enregistrer
    local result = lib.callback.await('lunatic_creator:registerIdentity', false, {
        firstname = identity.firstname, lastname = identity.lastname, dateofbirth = identity.dateofbirth,
        sex = appearance.sex == 'female' and 'f' or 'm', height = tonumber(identity.height), nationality = identity.nationality,
        spawn = spawnIndex,
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

---------------------------------------------------------------------
-- Outil photo staff : miniatures des styles (cheveux et calques du visage), lancé depuis le panel
-- (Autres > Création perso). Le personnage du staff prend chaque style le temps d'un portrait GTA.
---------------------------------------------------------------------

local photoRunning = false
local photoReply = nil

RegisterNUICallback('thumbData', function(data, cb)
    cb({})
    photoReply = type(data) == 'table' and data or { error = 'réponse vide' }
end)

-- Portrait GTA sur fond transparent, converti par la page puis envoyé au serveur ; true si réussi
local function takeThumb(sex, key, index)
    local ped = PlayerPedId()
    local handle = RegisterPedheadshotTransparent(ped)
    local timeout = GetGameTimer() + 5000

    while (not IsPedheadshotReady(handle) or not IsPedheadshotValid(handle)) and GetGameTimer() < timeout do
        Wait(20)
    end

    if not IsPedheadshotReady(handle) or not IsPedheadshotValid(handle) then
        UnregisterPedheadshot(handle)
        return false
    end

    local txd = GetPedheadshotTxdString(handle)
    photoReply = nil
    SendNUIMessage({ action = 'thumbCapture', url = ('https://nui-img/%s/%s'):format(txd, txd) })

    timeout = GetGameTimer() + 5000

    while not photoReply and GetGameTimer() < timeout do
        Wait(20)
    end

    UnregisterPedheadshot(handle)

    if not photoReply or type(photoReply.image) ~= 'string' then
        return false
    end

    TriggerLatentServerEvent('lunatic_creator:thumb', 100000, sex, key, index, photoReply.image)
    return true
end

-- Base neutre des photos : pas de calque, sourcils légers, cheveux courts
local function photoBase(sex)
    local base = defaults(sex)
    base.hair = { style = 0, color = Config.Photos.hairColor, highlight = Config.Photos.hairColor }
    base.overlays = { ['2'] = { style = 0, opacity = 0.6, color = Config.Photos.hairColor } }
    return base
end

RegisterNetEvent('lunatic_creator:photoTool', function(sex)
    if active or photoRunning or (sex ~= 'male' and sex ~= 'female') then
        return
    end

    photoRunning = true
    local api = appearanceApi()
    local saved = api:getPedAppearance(PlayerPedId())

    FreezeEntityPosition(PlayerPedId(), true)
    appearance = photoBase(sex)
    api:setPlayerModel(MODELS[sex])
    applyAll()

    -- Liste des photos : toutes les coupes, puis chaque style des calques visibles sur un portrait
    local ped = PlayerPedId()
    local jobs = {}

    for index = 0, GetNumberOfPedDrawableVariations(ped, 2) - 1 do
        jobs[#jobs + 1] = { key = 'hair', index = index }
    end

    for _, overlay in ipairs(Config.Photos.overlays) do
        for index = 0, GetPedHeadOverlayNum(overlay) - 1 do
            jobs[#jobs + 1] = { key = 'overlay-' .. overlay, overlay = overlay, index = index }
        end
    end

    local done, failed = 0, 0

    for number, job in ipairs(jobs) do
        if not photoRunning then
            break
        end

        lib.showTextUI(('Photos des styles (%s) : %d / %d'):format(sex == 'male' and 'homme' or 'femme', number, #jobs))
        appearance = photoBase(sex)

        if job.key == 'hair' then
            appearance.hair.style = job.index
        else
            appearance.overlays[tostring(job.overlay)] = {
                style = job.index, opacity = 1.0,
                color = OVERLAY_COLOR_TYPE[job.overlay] == 2 and Config.Photos.makeupColor or Config.Photos.hairColor,
            }
        end

        applyAll()
        Wait(Config.Photos.delay)

        if takeThumb(sex, job.key, job.index) then
            done = done + 1
        else
            failed = failed + 1
        end
    end

    TriggerServerEvent('lunatic_creator:thumbsDone', sex, done, failed)
    lib.hideTextUI()

    -- Retour à l'apparence du staff
    api:setPlayerAppearance(saved)
    FreezeEntityPosition(PlayerPedId(), false)
    appearance = nil
    photoRunning = false
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and photoRunning then
        photoRunning = false
        lib.hideTextUI()
        FreezeEntityPosition(PlayerPedId(), false)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and active then
        SetNuiFocus(false, false)
        stopCamera(false)
        FreezeEntityPosition(PlayerPedId(), false)
        DisplayRadar(true)
        DoScreenFadeIn(0)
        restoreClock()
    end
end)
