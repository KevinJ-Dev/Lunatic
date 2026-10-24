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
    end
end)
