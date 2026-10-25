-- Sélection de personnage, côté client : écran à la connexion et après /personnages, aperçu du personnage choisi
-- sur un décor, puis apparition à sa dernière position (en mode multi-personnages, ESX ne fait plus apparaître le joueur).

local open = false
local cam = nil
local characters = {} -- [emplacement] = personnage (avec son apparence enregistrée)
local previewToken = 0

local function shutdownLoadingScreen()
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
end

local function stopCamera()
    if cam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, false)
        cam = nil
    end
end

-- Heure du serveur (lunatic_world) après la sélection
local function restoreClock()
    local clock = GlobalState.lunaticClock

    if type(clock) == 'table' then
        NetworkOverrideClockTime(tonumber(clock.h) or 12, tonumber(clock.m) or 0, 0)
    else
        NetworkClearClockTimeOverride()
    end
end

-- Personnage posé sur le décor, figé (le joueur est seul dans son instance)
local function placePed(visible)
    local ped = PlayerPedId()
    local spot = Config.Scene.ped

    SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z - 0.98, false, false, false)
    SetEntityHeading(ped, spot.w)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetEntityVisible(ped, visible, false)
    ResetEntityAlpha(ped)
    ClearPedTasksImmediately(ped)
end

-- Caméra face au personnage, décalée pour qu'il apparaisse à droite du panneau
local function sceneCamera()
    local spot, settings = Config.Scene.ped, Config.Scene.camera
    local angle = math.rad(spot.w)
    local forward = vector3(-math.sin(angle), math.cos(angle), 0.0)
    local right = vector3(math.cos(angle), math.sin(angle), 0.0)
    local halfWidth = settings.distance * math.tan(math.rad(settings.fov) / 2) * GetAspectRatio(false)
    local base = vector3(spot.x, spot.y, spot.z) + right * (halfWidth * settings.shift)
    local position = base + forward * settings.distance + vector3(0.0, 0.0, settings.height)

    stopCamera()
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', position.x, position.y, position.z, 0.0, 0.0, 0.0, settings.fov, false, 2)
    PointCamAtCoord(cam, base.x, base.y, base.z + settings.aim)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
end

-- Aperçu : le personnage de l'emplacement avec son apparence enregistrée (rien pour un emplacement vide)
local function preview(slot)
    previewToken = previewToken + 1
    local token = previewToken
    local character = characters[slot]

    if not character or not character.skin or GetResourceState('illenium-appearance') ~= 'started' then
        SetEntityVisible(PlayerPedId(), false, false)
        return
    end

    pcall(function() exports['illenium-appearance']:setPlayerAppearance(character.skin) end)

    -- Un autre personnage a été choisi pendant le chargement du modèle
    if token == previewToken and open then
        placePed(true)
    end
end

local function showSelection()
    if open then
        return
    end

    open = true
    DoScreenFadeOut(0)

    if GetResourceState('spawnmanager') == 'started' then
        pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
    end

    TriggerServerEvent('lunatic_characters:open')

    local spot = Config.Scene.ped
    RequestCollisionAtCoord(spot.x, spot.y, spot.z)
    placePed(false)
    sceneCamera()
    DisplayRadar(false)

    local data = lib.callback.await('lunatic_characters:list', false) or {}
    local list = {}
    characters = {}

    -- La page n'a pas besoin des apparences (gardées ici pour l'aperçu)
    for _, character in ipairs(data.characters or {}) do
        characters[character.slot] = character
        local entry = {}

        for key, value in pairs(character) do
            if key ~= 'skin' then
                entry[key] = value
            end
        end

        list[#list + 1] = entry
    end

    shutdownLoadingScreen()

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open', characters = list, slots = data.slots or 1, max = data.max or Config.Slots.max,
        tiers = data.tiers or Config.Tiers, vip = data.vip, serverId = GetPlayerServerId(PlayerId()),
    })

    -- Pas de HUD ni d'actions pendant la sélection ; décor en plein jour
    CreateThread(function()
        while open do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            NetworkOverrideClockTime(Config.Scene.clockHour, 0, 0)
            Wait(0)
        end
    end)

    Wait(400)
    DoScreenFadeIn(600)
end

local function closeSelection()
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('preview', function(data, cb)
    cb({})

    if open then
        preview(tonumber(data.slot))
    end
end)

RegisterNUICallback('play', function(data, cb)
    if not open then
        return cb({ error = "La sélection n'est pas ouverte." })
    end

    local result = lib.callback.await('lunatic_characters:play', false, tonumber(data.slot))

    if type(result) ~= 'table' or not result.ok then
        return cb({ error = type(result) == 'table' and result.error or 'Pas de réponse du serveur.' })
    end

    cb({ ok = true })
    DoScreenFadeOut(500)
    closeSelection()
end)

-- Personnage chargé par ESX : il apparaît à sa dernière position, avec son apparence et son équipement
RegisterNetEvent('esx:playerLoaded', function(xPlayer, _, skin)
    open = false
    SetNuiFocus(false, false)

    if not IsScreenFadedOut() then
        DoScreenFadeOut(0)
    end

    ESX.SpawnPlayer(skin, xPlayer.coords, function()
        stopCamera()
        restoreClock()

        -- Ce que fait ESX hors mode multi-personnages (Core.FreezePlayer(false)) : contrôles et collisions rendus
        local ped = PlayerPedId()
        SetPlayerControl(PlayerId(), true, 0)
        SetEntityCollision(ped, true, true)
        SetEntityVisible(ped, true, false)
        SetEntityInvincible(ped, false)
        FreezeEntityPosition(ped, false)

        TriggerEvent('esx:onPlayerSpawn')
        TriggerEvent('esx:restoreLoadout')
        TriggerServerEvent('esx:onPlayerSpawn')
        TriggerEvent('esx:loadingScreenOff')
        shutdownLoadingScreen()

        DisplayRadar(true)
        DoScreenFadeIn(800)
    end)
end)

-- Personnage déchargé (/personnages) : retour à la sélection
RegisterNetEvent('esx:onPlayerLogout', function()
    Wait(500)
    showSelection()
end)

-- Arrivée sur le serveur (ou resource relancée avant d'avoir choisi) : écran de sélection
CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(100)
    end

    Wait(500)

    if not ESX.PlayerLoaded then
        showSelection()
    end
end)

-- Changer de personnage en jeu (vivant, à pied, pas en création)
RegisterCommand(Config.SwitchCommand, function()
    if open or not ESX.PlayerLoaded or LocalPlayer.state.lunaticCreating then
        return
    end

    local ped = PlayerPedId()

    if IsEntityDead(ped) or ESX.PlayerData.dead or IsPedInAnyVehicle(ped, false) or IsPedCuffed(ped) or IsPedInMeleeCombat(ped) or IsPedShooting(ped) then
        return lib.notify({ type = 'error', description = 'Impossible de changer de personnage maintenant (mort, menotté, en véhicule ou en combat).' })
    end

    local answer = lib.alertDialog({
        header = 'Changer de personnage',
        content = 'Votre personnage actuel est sauvegardé, puis vous revenez à la sélection des personnages.',
        centered = true,
        cancel = true,
        labels = { confirm = 'Changer', cancel = 'Annuler' },
    })

    if answer == 'confirm' then
        TriggerServerEvent('lunatic_characters:switch')
    end
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and open then
        SetNuiFocus(false, false)
        stopCamera()
        restoreClock()
        DisplayRadar(true)
        DoScreenFadeIn(0)
    end
end)
