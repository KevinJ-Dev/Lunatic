-- Lot K : outils développeur côté client (activés par le serveur après vérification de la permission).
-- Infos entité : vise une entité (ped, véhicule, objet) pour voir son modèle, son id réseau, sa position… E l'envoie au panel.
-- Debug : position, rue, intérieur, véhicule, nombre d'entités et FPS en haut à gauche.

local modes = { entity = false, debug = false }
local CAPTURE_KEY = 38 -- E
local RAY_DISTANCE = 120.0

local function drawLine(text, x, y, scale, rgb)
    SetTextFont(4)
    SetTextScale(0.0, scale or 0.32)
    SetTextColour(rgb and rgb[1] or 255, rgb and rgb[2] or 255, rgb and rgb[3] or 255, 235)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function draw3d(coords, text)
    SetTextScale(0.0, 0.3)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 235)
    SetTextOutline()
    SetTextCentre(true)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

---------------------------------------------------------------------
-- Infos entité
---------------------------------------------------------------------

local function cameraDirection()
    local rot = GetGameplayCamRot(2)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    return vector3(-math.sin(z) * math.abs(math.cos(x)), math.cos(z) * math.abs(math.cos(x)), math.sin(x))
end

-- Entité sous le centre de l'écran (véhicules, peds, objets), en ignorant son propre personnage
local function aimedEntity()
    local from = GetGameplayCamCoord()
    local to = from + cameraDirection() * RAY_DISTANCE
    -- Test synchrone : le résultat est disponible tout de suite (pas d'attente d'une image)
    local probe = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 2 | 4 | 8 | 16, PlayerPedId(), 7)
    local _, hit, _, _, entity = GetShapeTestResult(probe)

    if hit == 1 and entity and entity ~= 0 and DoesEntityExist(entity) then
        return entity
    end
end

local TYPES = { [1] = 'Ped', [2] = 'Véhicule', [3] = 'Objet' }

local function entityInfo(entity)
    local model = GetEntityModel(entity)
    local coords = GetEntityCoords(entity)
    local kind = GetEntityType(entity)
    local info = {
        type = TYPES[kind] or 'Entité',
        hash = model,
        hashHex = ('0x%08X'):format(model & 0xFFFFFFFF),
        coords = { x = coords.x, y = coords.y, z = coords.z },
        heading = GetEntityHeading(entity),
        health = GetEntityHealth(entity),
        maxHealth = GetEntityMaxHealth(entity),
        networked = NetworkGetEntityIsNetworked(entity),
    }

    if info.networked then
        info.netId = NetworkGetNetworkIdFromEntity(entity)
        local owner = NetworkGetEntityOwner(entity)
        info.owner = owner and owner ~= -1 and GetPlayerServerId(owner) or nil
    end

    if kind == 2 then
        info.model = GetDisplayNameFromVehicleModel(model):lower()
        info.plate = GetVehicleNumberPlateText(entity)
        info.engine = math.floor(GetVehicleEngineHealth(entity))
    elseif kind == 1 then
        if IsPedAPlayer(entity) then
            info.player = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
        end

        info.armour = GetPedArmour(entity)
    end

    return info
end

local function infoLines(info)
    local lines = {
        ('%s · %s%s'):format(info.type, info.model or info.hashHex, info.model and (' (' .. info.hashHex .. ')') or ''),
        ('x %.2f  y %.2f  z %.2f  h %.1f'):format(info.coords.x, info.coords.y, info.coords.z, info.heading),
        ('Santé %d/%d%s'):format(info.health, info.maxHealth, info.engine and ('  ·  moteur ' .. info.engine) or ''),
    }

    if info.netId then
        lines[#lines + 1] = ('Réseau %d%s'):format(info.netId, info.owner and ('  ·  géré par le joueur ' .. info.owner) or '')
    else
        lines[#lines + 1] = 'Entité locale (non synchronisée)'
    end

    if info.plate then
        lines[#lines + 1] = ('Plaque %s'):format(info.plate)
    end

    if info.player then
        lines[#lines + 1] = ('Joueur ID %d'):format(info.player)
    end

    return lines
end

local function entityLoop()
    CreateThread(function()
        local outlined

        while modes.entity do
            local entity = aimedEntity()

            if outlined and outlined ~= entity and DoesEntityExist(outlined) then
                SetEntityDrawOutline(outlined, false)
            end

            -- Petit viseur au centre de l'écran
            DrawRect(0.5, 0.5, 0.0025, 0.004, 255, 255, 255, 200)

            if entity then
                if outlined ~= entity then
                    SetEntityDrawOutlineColor(150, 80, 255, 255)
                    SetEntityDrawOutline(entity, true)
                    outlined = entity
                end

                local info = entityInfo(entity)
                local lines = infoLines(info)
                lines[#lines + 1] = '~c~E : envoyer au panel'
                draw3d(GetEntityCoords(entity) + vector3(0.0, 0.0, 1.0), table.concat(lines, '~n~'))

                if IsControlJustPressed(0, CAPTURE_KEY) then
                    SendNUIMessage({ action = 'devEntity', entity = info })
                    print(('[lunatic_admin] Entité : %s'):format(json.encode(info)))
                    ESX.ShowNotification('Infos envoyées au panel (page Développeur) et à la console F8.', 'success')
                end
            else
                outlined = nil
            end

            Wait(0)
        end

        if outlined and DoesEntityExist(outlined) then
            SetEntityDrawOutline(outlined, false)
        end
    end)
end

---------------------------------------------------------------------
-- Affichage de debug
---------------------------------------------------------------------

local function debugLoop()
    CreateThread(function()
        local pools, fps, frames, lastSample = { 0, 0, 0 }, 0, 0, GetGameTimer()

        while modes.debug do
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local now = GetGameTimer()
            frames = frames + 1

            -- FPS et compteurs d'entités : recalculés chaque seconde
            if now - lastSample >= 1000 then
                fps = math.floor(frames * 1000 / (now - lastSample) + 0.5)
                frames, lastSample = 0, now
                pools = { #GetGamePool('CPed'), #GetGamePool('CVehicle'), #GetGamePool('CObject') }
            end

            local street, crossing = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
            local streetName = GetStreetNameFromHashKey(street)
            local crossingName = crossing ~= 0 and GetStreetNameFromHashKey(crossing) or nil
            local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
            local interior = GetInteriorFromEntity(ped)
            local vehicle = GetVehiclePedIsIn(ped, false)

            local lines = {
                ('ID serveur %d  ·  %d FPS'):format(GetPlayerServerId(PlayerId()), fps),
                ('x %.2f  y %.2f  z %.2f  h %.1f'):format(coords.x, coords.y, coords.z, GetEntityHeading(ped)),
                ('%s%s  ·  %s'):format(streetName, crossingName and (' / ' .. crossingName) or '', zone),
                ('Intérieur %s  ·  santé %d  ·  armure %d'):format(interior ~= 0 and tostring(interior) or 'aucun', GetEntityHealth(ped), GetPedArmour(ped)),
                ('Entités : %d peds  ·  %d véhicules  ·  %d objets'):format(pools[1], pools[2], pools[3]),
            }

            if vehicle ~= 0 then
                lines[#lines + 1] = ('Véhicule %s  ·  %d km/h  ·  moteur %d  ·  plaque %s'):format(
                    GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)):lower(), math.floor(GetEntitySpeed(vehicle) * 3.6),
                    math.floor(GetVehicleEngineHealth(vehicle)), GetVehicleNumberPlateText(vehicle))
            end

            DrawRect(0.125, 0.025 + #lines * 0.0125, 0.24, 0.012 + #lines * 0.025, 10, 8, 18, 170)

            for i, text in ipairs(lines) do
                drawLine(text, 0.01, 0.012 + (i - 1) * 0.025, 0.32, i == 1 and { 190, 160, 255 } or nil)
            end

            Wait(0)
        end
    end)
end

---------------------------------------------------------------------
-- Activation par le serveur
---------------------------------------------------------------------

RegisterNetEvent('lunatic_admin:devMode', function(mode, enabled)
    if modes[mode] == nil then
        return
    end

    local wasEnabled = modes[mode]
    modes[mode] = enabled == true

    if modes[mode] and not wasEnabled then
        if mode == 'entity' then
            entityLoop()
        else
            debugLoop()
        end
    end
end)
