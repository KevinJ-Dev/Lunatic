-- Events à zone, côté joueur : entrée et sortie des zones des events chargés (le serveur valide et pose les règles
-- dans LocalPlayer.state.lunaticEvent), puis application des règles locales : invincibilité du joueur et de son
-- véhicule, heure de l'event, musique d'ambiance. Le coma, le respawn et la faim / soif sont gérés par
-- lunatic_gameplay et esx_basicneeds, qui lisent le même état.

local radiusBlips = {}
local lastRequest = { id = nil, at = 0 }
local protectedVehicle = nil
local playingAudio = nil

local function current()
    return LocalPlayer.state.lunaticEvent
end

---------------------------------------------------------------------
-- Zones sur la carte
---------------------------------------------------------------------

local function clearZoneBlips()
    for _, blip in pairs(radiusBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    radiusBlips = {}
end

local function drawZoneBlips(list)
    clearZoneBlips()

    for _, zone in ipairs(type(list) == 'table' and list or {}) do
        local blip = AddBlipForRadius(zone.x + 0.0, zone.y + 0.0, 0.0, zone.radius + 0.0)
        SetBlipColour(blip, 27)
        SetBlipAlpha(blip, 90)
        radiusBlips[zone.id] = blip
    end
end

AddStateBagChangeHandler('lunaticEventZones', 'global', function(_, _, value)
    drawZoneBlips(value)
end)

---------------------------------------------------------------------
-- Règles locales
---------------------------------------------------------------------

local function releaseVehicle()
    if protectedVehicle and DoesEntityExist(protectedVehicle) then
        SetEntityInvincible(protectedVehicle, false)
        SetVehicleCanBeVisiblyDamaged(protectedVehicle, true)
        SetVehicleTyresCanBurst(protectedVehicle, true)
    end

    protectedVehicle = nil
end

local function stopAudio()
    if playingAudio then
        playingAudio = nil
        SendNUIMessage({ action = 'eventAudio' })
    end
end

-- Appelé à chaque changement des règles (entrée, sortie, event modifié ou déchargé)
local function applyEvent(event)
    if not event then
        -- Le mode invincible du staff (outils) reste prioritaire
        if not (StaffImmortal and StaffImmortal()) then
            SetEntityInvincible(PlayerPedId(), false)
            SetPlayerInvincible(PlayerId(), false)
        end

        releaseVehicle()
        stopAudio()

        if GlobalState.lunaticClock then
            NetworkOverrideClockTime(tonumber(GlobalState.lunaticClock.h) or 12, tonumber(GlobalState.lunaticClock.m) or 0, 0)
        end

        return
    end

    if not event.vehicleGodmode then
        releaseVehicle()
    end

    local audio = event.audio and ('%s|%s'):format(event.audio, event.volume or 50) or nil

    if audio ~= playingAudio then
        playingAudio = audio
        SendNUIMessage({ action = 'eventAudio', url = event.audio, volume = (tonumber(event.volume) or 50) / 100 })
    end
end

AddStateBagChangeHandler('lunaticEvent', ('player:%s'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    -- Le gestionnaire passe avant la mise à jour de LocalPlayer.state : on applique la nouvelle valeur reçue
    applyEvent(value)
end)

-- Entretien des règles (le personnage ou le véhicule peut changer)
CreateThread(function()
    while true do
        local event = current()

        if event then
            local ped = PlayerPedId()

            if event.godmode then
                SetEntityInvincible(ped, true)
                SetPlayerInvincible(PlayerId(), true)
            end

            if event.vehicleGodmode then
                local vehicle = GetVehiclePedIsIn(ped, false)

                if vehicle ~= 0 and vehicle ~= protectedVehicle then
                    releaseVehicle()
                    protectedVehicle = vehicle
                end

                if protectedVehicle and DoesEntityExist(protectedVehicle) then
                    SetEntityInvincible(protectedVehicle, true)
                    SetVehicleCanBeVisiblyDamaged(protectedVehicle, false)
                    SetVehicleTyresCanBurst(protectedVehicle, false)
                end
            end

            if event.hour then
                NetworkOverrideClockTime(event.hour, 0, 0)
            end

            Wait(250)
        else
            Wait(1000)
        end
    end
end)

---------------------------------------------------------------------
-- Entrée et sortie des zones (le serveur revérifie la position)
---------------------------------------------------------------------

local function request(name, id)
    local now = GetGameTimer()

    if lastRequest.id == id and now - lastRequest.at < 3000 then
        return
    end

    lastRequest = { id = id, at = now }
    TriggerServerEvent(name, id)
end

CreateThread(function()
    drawZoneBlips(GlobalState.lunaticEventZones)

    while true do
        local zones = GlobalState.lunaticEventZones
        local event = current()

        if type(zones) == 'table' and #zones > 0 then
            local coords = GetEntityCoords(PlayerPedId())
            local inside = nil

            for _, zone in ipairs(zones) do
                if #(vector2(coords.x, coords.y) - vector2(zone.x, zone.y)) <= zone.radius then
                    inside = zone
                    break
                end
            end

            if inside and (not event or event.id ~= inside.id) then
                request('lunatic_admin:eventEnter', inside.id)
            elseif not inside and event and #(vector2(coords.x, coords.y) - vector2(event.x, event.y)) > event.radius + 5.0 then
                request('lunatic_admin:eventLeave', 'leave')
            end

            Wait(500)
        else
            Wait(2000)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clearZoneBlips()
        releaseVehicle()
    end
end)
