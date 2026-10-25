-- Sélection de personnage, côté client : écran à la connexion et après /personnages, puis apparition du personnage
-- choisi (en mode multi-personnages, ESX ne fait plus apparaître le joueur lui-même).

local open = false
local cam = nil

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

-- Joueur caché et figé sur le décor, caméra fixe
local function placeScene()
    local ped = PlayerPedId()
    local scene = Config.Scene

    RequestCollisionAtCoord(scene.ped.x, scene.ped.y, scene.ped.z)
    SetEntityCoordsNoOffset(ped, scene.ped.x, scene.ped.y, scene.ped.z, false, false, false)
    SetEntityHeading(ped, scene.ped.w)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)

    stopCamera()
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', scene.camera.x, scene.camera.y, scene.camera.z, 0.0, 0.0, 0.0, scene.fov, false, 2)
    PointCamAtCoord(cam, scene.lookAt.x, scene.lookAt.y, scene.lookAt.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
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
    placeScene()
    DisplayRadar(false)

    local data = lib.callback.await('lunatic_characters:list', false)
    shutdownLoadingScreen()

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', characters = data and data.characters or {}, slots = data and data.slots or 1, tiers = data and data.tiers or Config.Slots })
    DoScreenFadeIn(600)

    -- Pas de HUD ni d'actions pendant la sélection
    CreateThread(function()
        while open do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            Wait(0)
        end
    end)
end

local function closeSelection()
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

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

-- Personnage chargé par ESX : on le fait apparaître (position enregistrée, apparence, équipement)
RegisterNetEvent('esx:playerLoaded', function(xPlayer, _, skin)
    open = false
    SetNuiFocus(false, false)

    if not IsScreenFadedOut() then
        DoScreenFadeOut(0)
    end

    ESX.SpawnPlayer(skin, xPlayer.coords, function()
        stopCamera()

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
        DisplayRadar(true)
        DoScreenFadeIn(0)
    end
end)
