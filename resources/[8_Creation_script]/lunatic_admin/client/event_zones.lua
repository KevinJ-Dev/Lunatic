-- Events à zone, côté joueur : entrée et sortie des zones des events chargés (le serveur valide et pose les règles
-- dans LocalPlayer.state.lunaticEvent), puis application des règles locales : invincibilité du joueur et de son
-- véhicule, heure de l'event, musique d'ambiance. Le coma, le respawn et la faim / soif sont gérés par
-- lunatic_gameplay et esx_basicneeds, qui lisent le même état.

local radiusBlips = {}
local lastRequest = { id = nil, at = 0 }
local protectedVehicle = nil
local playingAudio = nil
local savedOutfit = nil   -- tenue du joueur avant l'event, rendue à la sortie
local appliedOutfit = nil -- tenue d'event portée (signature)

local function current()
    return LocalPlayer.state.lunaticEvent
end

local function sexOf(ped)
    local model = GetEntityModel(ped)

    if model == `mp_m_freemode_01` then
        return 'male'
    elseif model == `mp_f_freemode_01` then
        return 'female'
    end
end

local function appearance()
    return GetResourceState('illenium-appearance') == 'started' and exports['illenium-appearance'] or nil
end

---------------------------------------------------------------------
-- Tenues (illenium-appearance) : vêtements et accessoires seulement, la tenue d'origine est rendue à la sortie
---------------------------------------------------------------------

local function applyOutfit(event)
    local api = appearance()

    if not api then
        return
    end

    local ped = PlayerPedId()
    local outfit = event and type(event.outfits) == 'table' and event.outfits[sexOf(ped) or ''] or nil

    if outfit then
        local signature = json.encode(outfit)

        if signature == appliedOutfit then
            return
        end

        savedOutfit = savedOutfit or { components = api:getPedComponents(ped), props = api:getPedProps(ped) }
        api:setPedComponents(ped, outfit.components)
        api:setPedProps(ped, outfit.props)
        appliedOutfit = signature
    elseif savedOutfit then
        api:setPedComponents(ped, savedOutfit.components)
        api:setPedProps(ped, savedOutfit.props)
        savedOutfit = nil
        appliedOutfit = nil
    end
end

-- Capture depuis le panel (onglet Tenues) : la tenue portée par le staff
RegisterNUICallback('captureOutfit', function(_, cb)
    local api = appearance()
    local ped = PlayerPedId()
    local sex = sexOf(ped)

    if not api then
        return cb({ ok = false, error = 'illenium-appearance est arrêté.' })
    end

    if not sex then
        return cb({ ok = false, error = 'Votre personnage doit être un modèle homme ou femme (freemode).' })
    end

    cb({ ok = true, sex = sex, components = api:getPedComponents(ped), props = api:getPedProps(ped) })
end)

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
        applyOutfit(nil)

        if GlobalState.lunaticClock then
            NetworkOverrideClockTime(tonumber(GlobalState.lunaticClock.h) or 12, tonumber(GlobalState.lunaticClock.m) or 0, 0)
        end

        return
    end

    if not event.vehicleGodmode then
        releaseVehicle()
    end

    applyOutfit(event)

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
-- Props des events chargés : objets locaux, posés quand le joueur approche (250 m), retirés ensuite
---------------------------------------------------------------------

local props = {}       -- clé "event:index" -> objet
local propsSignature = nil
local PROP_RANGE = 250.0

local function deleteProps(keep)
    for key, object in pairs(props) do
        if not (keep and keep[key]) then
            if DoesEntityExist(object) then
                DeleteObject(object)
            end

            props[key] = nil
        end
    end
end

local function spawnProp(entry)
    local model = joaat(entry.model)

    if not IsModelInCdimage(model) then
        return nil
    end

    RequestModel(model)
    local timeout = GetGameTimer() + 3000

    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not HasModelLoaded(model) then
        return nil
    end

    local object = CreateObjectNoOffset(model, entry.x + 0.0, entry.y + 0.0, entry.z + 0.0, false, false, false)
    SetEntityHeading(object, (entry.h or 0.0) + 0.0)
    FreezeEntityPosition(object, true)
    SetModelAsNoLongerNeeded(model)
    return object
end

CreateThread(function()
    while true do
        local zones = GlobalState.lunaticEventZones
        local signature = json.encode(zones or {})

        -- Event chargé, modifié ou déchargé : tout est reposé
        if signature ~= propsSignature then
            propsSignature = signature
            deleteProps(nil)
        end

        local coords = GetEntityCoords(PlayerPedId())
        local wanted = {}

        for _, zone in ipairs(type(zones) == 'table' and zones or {}) do
            for index, entry in ipairs(type(zone.props) == 'table' and zone.props or {}) do
                if #(vector2(coords.x, coords.y) - vector2(entry.x, entry.y)) < PROP_RANGE then
                    local key = ('%s:%s'):format(zone.id, index)
                    wanted[key] = true

                    if not props[key] then
                        props[key] = spawnProp(entry) or -1
                    end
                end
            end
        end

        deleteProps(wanted)
        Wait(2000)
    end
end)

---------------------------------------------------------------------
-- Affiche de l'event (diffusée par le serveur) : [Y] trace l'itinéraire vers la zone
---------------------------------------------------------------------

local POSTER_DURATION = 15000

RegisterNetEvent('lunatic_admin:eventPoster', function(poster)
    if type(poster) ~= 'table' then
        return
    end

    SendNUIMessage({ action = 'eventPoster', poster = poster, duration = POSTER_DURATION })

    if not poster.gps or not poster.x then
        return
    end

    CreateThread(function()
        local untilAt = GetGameTimer() + POSTER_DURATION

        while GetGameTimer() < untilAt do
            -- Y (INPUT_MP_TEXT_CHAT_TEAM)
            if IsControlJustReleased(0, 246) then
                SetNewWaypoint(poster.x + 0.0, poster.y + 0.0)
                ESX.ShowNotification(('Itinéraire tracé vers « %s ».'):format(poster.title or "l'event"), 'info')
                SendNUIMessage({ action = 'eventPoster' })
                return
            end

            Wait(0)
        end
    end)
end)

---------------------------------------------------------------------
-- Points de TP : marqueur au départ, [E] pour être téléporté (le serveur vérifie la position)
---------------------------------------------------------------------

CreateThread(function()
    while true do
        local event = current()
        local points = event and type(event.tp) == 'table' and event.tp or nil

        if points and #points > 0 then
            local coords = GetEntityCoords(PlayerPedId())
            local near = false

            for index, point in ipairs(points) do
                local from = vector3(point.from.x, point.from.y, point.from.z)
                local distance = #(coords - from)

                if distance < 30.0 then
                    near = true
                    DrawMarker(1, from.x, from.y, from.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.6, 242, 194, 107, 140, false, false, 2, false, nil, nil, false)
                end

                if distance < 1.6 then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName(('~INPUT_CONTEXT~ %s'):format(point.label))
                    EndTextCommandDisplayHelp(0, false, true, -1)

                    if IsControlJustReleased(0, 38) then
                        TriggerServerEvent('lunatic_admin:eventTp', index)
                    end
                end
            end

            Wait(near and 0 or 500)
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
        deleteProps(nil)
    end
end)
