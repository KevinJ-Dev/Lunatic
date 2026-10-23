-- Lot 2 : effets des actions du staff sur le joueur (déclenchés uniquement par le serveur)

---------------------------------------------------------------------
-- Téléportation (aller vers, ramener, renvoyer)
---------------------------------------------------------------------

-- Utilisé aussi par client/tools.lua (téléportation au marqueur)
function Teleport(coords)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    -- Le conducteur emmène son véhicule avec lui
    local entity = (vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped) and vehicle or ped

    DoScreenFadeOut(250)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(entity, coords.x, coords.y, coords.z, false, false, false, false)

    local timeout = GetGameTimer() + 3000

    while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(0)
    end

    DoScreenFadeIn(250)
end

RegisterNetEvent('lunatic_admin:teleport', function(coords)
    if type(coords) ~= 'vector3' then
        return
    end

    -- Hauteur inconnue (point placé sur la carte du panel) : on cherche le sol en descendant depuis le ciel
    if coords.z < -100.0 then
        local ground = nil

        for height = 1000.0, 0.0, -25.0 do
            RequestCollisionAtCoord(coords.x, coords.y, height)
            Wait(0)

            local found, z = GetGroundZFor_3dCoord(coords.x, coords.y, height, false)

            if found then
                ground = z
                break
            end
        end

        coords = vector3(coords.x, coords.y, (ground or 200.0) + 1.0)
    end

    Teleport(coords)
end)

---------------------------------------------------------------------
-- Figer / libérer
---------------------------------------------------------------------

local isFrozen = false

local function applyFreeze()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    FreezeEntityPosition(ped, isFrozen)

    if vehicle ~= 0 then
        FreezeEntityPosition(vehicle, isFrozen)
    end
end

RegisterNetEvent('lunatic_admin:freeze', function(state)
    isFrozen = state == true
    applyFreeze()
end)

-- Réapplique le gel si le personnage change (réapparition, véhicule)
CreateThread(function()
    while true do
        if isFrozen then
            applyFreeze()
            Wait(500)
        else
            Wait(2000)
        end
    end
end)

---------------------------------------------------------------------
-- Soigner / réanimer
---------------------------------------------------------------------

-- Soin : la vie seulement (l'armure et la faim / soif ne sont pas touchées)
local function heal()
    local ped = PlayerPedId()

    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
end

-- Nourrir : faim et soif au maximum (statuts d'esx_status, 1 000 000 = plein)
local function feed()
    TriggerEvent('esx_status:set', 'hunger', 1000000)
    TriggerEvent('esx_status:set', 'thirst', 1000000)
end

-- Utilisés aussi par client/tools.lua (soin de zone)
HealSelf, FeedSelf = heal, feed

RegisterNetEvent('lunatic_admin:feed', function()
    feed()
end)

RegisterNetEvent('lunatic_admin:heal', function()
    if not IsEntityDead(PlayerPedId()) then
        heal()
    end
end)

RegisterNetEvent('lunatic_admin:revive', function()
    local ped = PlayerPedId()

    if IsEntityDead(ped) or IsPedFatallyInjured(ped) then
        local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)

        DoScreenFadeOut(300)

        while not IsScreenFadedOut() do
            Wait(0)
        end

        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
        ped = PlayerPedId()
        ClearPedTasksImmediately(ped)

        -- ESX repasse le joueur en vie et relance sa détection de mort
        TriggerServerEvent('esx:onPlayerSpawn')
        TriggerEvent('esx:onPlayerSpawn')

        DoScreenFadeIn(300)
    end

    heal()
end)

---------------------------------------------------------------------
-- Observer un joueur
---------------------------------------------------------------------

local STOP_CONTROL = 194 -- Retour arrière
local UNDERGROUND = 15.0 -- on se place sous la cible pour garder sa zone chargée

---@type {target:number, name:string, coords:vector3, heading:number}|nil
local spectate

local function targetPed(serverId)
    local player = GetPlayerFromServerId(serverId)
    local ped = player ~= -1 and GetPlayerPed(player) or 0

    return (ped ~= 0 and DoesEntityExist(ped)) and ped or nil
end

local function stopSpectate(message)
    if not spectate then
        return
    end

    local session = spectate
    spectate = nil

    local ped = PlayerPedId()
    NetworkSetInSpectatorMode(false, ped)
    SetEntityCoords(ped, session.coords.x, session.coords.y, session.coords.z, false, false, false, false)
    SetEntityHeading(ped, session.heading)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)
    NetworkSetEntityInvisibleToNetwork(ped, false)
    SetEntityInvincible(ped, false)

    TriggerServerEvent('lunatic_admin:spectateEnd')

    if message then
        ESX.ShowNotification(message, 'info')
    end
end

local function drawHint(text)
    SetTextFont(4)
    SetTextScale(0.0, 0.42)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.92)
end

RegisterNetEvent('lunatic_admin:spectate', function(serverId, coords, name)
    if type(serverId) ~= 'number' or type(coords) ~= 'vector3' then
        return
    end

    ClosePanel()

    local ped = PlayerPedId()

    -- Nouvelle session (la boucle d'une observation précédente s'arrête d'elle-même),
    -- en gardant la position de départ d'origine pour le retour
    local previous = spectate
    local session = {
        target = serverId,
        name = type(name) == 'string' and name or ('Joueur ' .. serverId),
        coords = previous and previous.coords or GetEntityCoords(ped),
        heading = previous and previous.heading or GetEntityHeading(ped),
    }
    spectate = session

    -- Invisible et intouchable, placé sous la cible pour que le jeu la charge
    SetEntityVisible(ped, false, false)
    NetworkSetEntityInvisibleToNetwork(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, coords.x, coords.y, coords.z - UNDERGROUND, false, false, false, false)

    local found
    local timeout = GetGameTimer() + 5000

    repeat
        Wait(100)
        found = targetPed(serverId)
    until found or GetGameTimer() > timeout or spectate ~= session

    if spectate ~= session then
        return
    end

    if not found then
        return stopSpectate("Impossible d'observer ce joueur (trop loin ou en chargement).")
    end

    NetworkSetInSpectatorMode(true, found)

    local nextFollow = 0

    while spectate == session do
        local current = targetPed(serverId)

        if not current then
            stopSpectate("Le joueur observé n'est plus accessible.")
            break
        end

        -- Suit la cible pour garder sa zone chargée
        if GetGameTimer() >= nextFollow then
            local position = GetEntityCoords(current)
            SetEntityCoords(PlayerPedId(), position.x, position.y, position.z - UNDERGROUND, false, false, false, false)
            nextFollow = GetGameTimer() + 1000
        end

        drawHint(('Observation : %s   ·   [Retour arrière] arrêter'):format(session.name))

        if IsControlJustPressed(0, STOP_CONTROL) or IsDisabledControlJustPressed(0, STOP_CONTROL) then
            stopSpectate()
            break
        end

        Wait(0)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    if spectate then
        stopSpectate()
    end

    if isFrozen then
        isFrozen = false
        applyFreeze()
    end
end)
