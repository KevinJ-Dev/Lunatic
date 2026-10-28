-- Garage public, côté client : interface (liste, places, fourrière), aperçu du véhicule à la sortie de l'emplacement,
-- sortie (joueur mis au volant, réglages posés) et rangement. Le [E] est affiché par lunatic_business, qui envoie
-- lunatic_garage:open (à pied) ou lunatic_garage:store (au volant d'un garage public).

local garage = nil -- interface ouverte : { target, data, entries, preview, cam, token }

local function notify(text, kind)
    ESX.ShowNotification(text, kind or 'info')
end

local function failed(result)
    if result and result.ok then
        return false
    end

    notify(result and result.error or 'Action impossible.', 'error')
    return true
end

-- Type d'entité du modèle pour le serveur (CreateVehicleServerSetter)
local function entityType(model)
    if IsThisModelAHeli(model) then
        return 'heli'
    elseif IsThisModelAPlane(model) then
        return 'plane'
    elseif IsThisModelABoat(model) or IsThisModelAJetski(model) then
        return 'boat'
    elseif IsThisModelABike(model) or IsThisModelABicycle(model) then
        return 'bike'
    end

    return 'automobile'
end

-- Nom affiché et nom du modèle (photo des véhicules du jeu)
local function vehicleName(model)
    local display = GetDisplayNameFromVehicleModel(model)
    local label = GetLabelText(display)
    return label ~= 'NULL' and label or display, display:lower()
end

-- Joueur mis au volant d'un véhicule du serveur dès qu'il est arrivé dans son jeu ; renvoie le véhicule
local function seatWhenReady(netId, timeout)
    local limit = GetGameTimer() + (timeout or 5000)

    while netId and GetGameTimer() < limit do
        local vehicle = NetworkDoesNetworkIdExist(netId) and NetToVeh(netId) or 0

        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            local ped = PlayerPedId()

            if GetVehiclePedIsIn(ped, false) == vehicle then
                return vehicle
            end

            SetPedIntoVehicle(ped, vehicle, -1)
        end

        Wait(50)
    end

    return nil
end

---------------------------------------------------------------------
-- Aperçu : véhicule local à la sortie de l'emplacement, caméra tournée vers lui
---------------------------------------------------------------------

local function deletePreview()
    if garage and garage.preview and DoesEntityExist(garage.preview) then
        DeleteEntity(garage.preview)
    end

    if garage then
        garage.preview = nil
    end
end

local function aimCamera(vehicle, model)
    local spawn = garage.data.spawn
    local min, max = GetModelDimensions(model)
    local distance = math.max(5.0, #(max - min) * 1.1)
    local angle = math.rad((spawn.h or 0.0) + Config.CameraAngle)
    local center = GetEntityCoords(vehicle)
    local position = center + vector3(-math.sin(angle) * distance, math.cos(angle) * distance, Config.CameraHeight)

    SetCamCoord(garage.cam, position.x, position.y, position.z)
    PointCamAtCoord(garage.cam, center.x, center.y, center.z + 0.3)
end

local function preview(entry)
    garage.token = garage.token + 1
    local token = garage.token
    deletePreview()

    local model = entry.model

    if not IsModelInCdimage(model) or not lib.requestModel(model, 10000) then
        return
    end

    if not garage or token ~= garage.token then
        SetModelAsNoLongerNeeded(model)
        return
    end

    local spawn = garage.data.spawn
    local z = spawn.z

    -- Bateau : à la surface de l'eau sous la sortie
    if garage.data.vehicleType == 'boat' then
        local found, height = GetWaterHeight(spawn.x, spawn.y, spawn.z)
        z = found and height or z
    end

    local vehicle = CreateVehicle(model, spawn.x, spawn.y, z, spawn.h or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    lib.setVehicleProperties(vehicle, entry.props)
    SetVehicleNumberPlateText(vehicle, entry.plate)

    if garage.data.vehicleType ~= 'boat' then
        SetVehicleOnGroundProperly(vehicle)
    end

    FreezeEntityPosition(vehicle, true)
    SetEntityInvincible(vehicle, true)
    SetVehicleLights(vehicle, 2)
    garage.preview = vehicle
    aimCamera(vehicle, model)
end

---------------------------------------------------------------------
-- Ouverture et fermeture
---------------------------------------------------------------------

local function closeGarage()
    if not garage then
        return
    end

    deletePreview()
    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(garage.cam, false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    garage = nil
end

AddEventHandler('lunatic_garage:open', function(target)
    if garage or type(target) ~= 'table' then
        return
    end

    local info = lib.callback.await('lunatic_garage:open', false, target.slug, target.index, target.kind)

    if failed(info) then
        return
    end

    local list = {}

    for index, entry in ipairs(info.vehicles) do
        local label, name = vehicleName(entry.model)
        list[#list + 1] = { id = index, plate = entry.plate, label = label, name = name, state = entry.state }
    end

    garage = { target = target, data = info, entries = info.vehicles, token = 0, cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true) }
    local coords = GetEntityCoords(PlayerPedId())
    SetCamCoord(garage.cam, coords.x, coords.y, coords.z + 1.0)
    RenderScriptCams(true, true, 500, true, true)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', kind = info.kind, label = info.label, vehicles = list, slots = info.slots, stored = info.stored })

    CreateThread(function()
        while garage do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)
end)

RegisterNUICallback('preview', function(data, cb)
    cb({})
    local entry = garage and garage.entries[tonumber(data.id) or -1]

    if entry then
        preview(entry)
    end
end)

RegisterNUICallback('close', function(_, cb)
    cb({})
    closeGarage()
end)

-- Sortir : écran noir, véhicule posé par le serveur, joueur au volant, réglages enregistrés remis
RegisterNUICallback('takeOut', function(data, cb)
    cb({})
    local entry = garage and garage.entries[tonumber(data.id) or -1]

    if not entry or entry.state ~= 'stored' then
        return
    end

    local target = garage.target
    closeGarage()
    DoScreenFadeOut(250)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    local result = lib.callback.await('lunatic_garage:takeOut', false, target.slug, target.index, entry.plate, entityType(entry.model))

    if not failed(result) then
        local vehicle = seatWhenReady(result.netId, 8000)

        if vehicle then
            lib.setVehicleProperties(vehicle, result.props)
            SetVehicleNumberPlateText(vehicle, result.plate)
        end

        notify(('Véhicule %s sorti du garage.'):format(result.plate), 'success')
    end

    DoScreenFadeIn(400)
end)

-- Ranger (au volant, dans la zone d'un garage public)
local storing = false

AddEventHandler('lunatic_garage:store', function(target)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if storing or type(target) ~= 'table' then
        return
    end

    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return notify('Prenez le volant pour ranger le véhicule.', 'error')
    end

    storing = true
    local result = lib.callback.await('lunatic_garage:store', false, target.slug, target.index, VehToNet(vehicle), lib.getVehicleProperties(vehicle))
    storing = false

    if not failed(result) then
        notify(('Véhicule %s rangé au garage.'):format(result.plate), 'success')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        closeGarage()
    end
end)
