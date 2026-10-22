-- Lot 4 : effets des outils staff. Chaque mode est activé par le serveur (après vérification de la permission).

local modes = { noclip = false, invisible = false, godmode = false, ghost = false, names = false, coords = false }

local function ask(action, payload)
    return lib.callback.await('lunatic_admin:action', false, action, payload or {})
end

local function notifyError(result)
    if result and not result.ok then
        ESX.ShowNotification(result.error or 'Action impossible.', 'error')
    end
end

---------------------------------------------------------------------
-- Affichage à l'écran
---------------------------------------------------------------------

local function drawScreenText(text, x, y, scale, rgb, centre)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextColour(rgb[1], rgb[2], rgb[3], 235)
    SetTextOutline()
    SetTextCentre(centre == true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function draw3dText(coords, text, rgb)
    SetTextScale(0.0, 0.3)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(rgb[1], rgb[2], rgb[3], 235)
    SetTextOutline()
    SetTextCentre(true)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function hexToRgb(hex)
    local r, g, b = (hex or ''):match('^#(%x%x)(%x%x)(%x%x)$')
    return r and { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) } or nil
end

---------------------------------------------------------------------
-- Invisibilité, invincibilité, noclip
---------------------------------------------------------------------

local function controlledEntity()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
        return vehicle, ped
    end

    return ped, ped
end

-- Réapplique l'état « normal » ou « staff » du personnage selon les modes actifs
local function applyBody()
    local ped = PlayerPedId()
    -- Mode fantôme = invisible + invincible en un seul interrupteur
    local hidden = modes.invisible or modes.noclip or modes.ghost
    local immortal = modes.godmode or modes.noclip or modes.ghost

    SetEntityVisible(ped, not hidden, false)
    SetEntityInvincible(ped, immortal)
    SetPlayerInvincible(PlayerId(), immortal)

    if not hidden then
        ResetEntityAlpha(ped)
    end
end

local noclipSpeed = Config.NoclipSpeed

local function noclipLoop()
    CreateThread(function()
        local entity = controlledEntity()

        FreezeEntityPosition(entity, true)
        SetEntityCollision(entity, false, false)

        while modes.noclip do
            entity = controlledEntity()

            -- Contrôles de déplacement réservés au noclip
            DisableControlAction(0, 30, true) -- gauche / droite
            DisableControlAction(0, 31, true) -- avant / arrière
            DisableControlAction(0, 21, true) -- Maj
            DisableControlAction(0, 36, true) -- Ctrl
            DisableControlAction(0, 44, true) -- Q
            DisableControlAction(0, 38, true) -- E
            DisableControlAction(0, 14, true) -- molette (armes)
            DisableControlAction(0, 15, true)
            DisableControlAction(0, 16, true)
            DisableControlAction(0, 17, true)

            if IsDisabledControlJustPressed(0, 15) then
                noclipSpeed = math.min(noclipSpeed * 1.25, 120.0)
            elseif IsDisabledControlJustPressed(0, 14) then
                noclipSpeed = math.max(noclipSpeed / 1.25, 1.0)
            end

            local rotation = GetGameplayCamRot(2)
            local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
            local forward = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
            local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)
            local move = vector3(0.0, 0.0, 0.0)

            if IsDisabledControlPressed(0, 32) then move = move + forward end
            if IsDisabledControlPressed(0, 33) then move = move - forward end
            if IsDisabledControlPressed(0, 35) then move = move + right end
            if IsDisabledControlPressed(0, 34) then move = move - right end
            if IsDisabledControlPressed(0, 38) then move = move + vector3(0.0, 0.0, 1.0) end
            if IsDisabledControlPressed(0, 44) then move = move - vector3(0.0, 0.0, 1.0) end

            local multiplier = IsDisabledControlPressed(0, 21) and 4.0 or IsDisabledControlPressed(0, 36) and 0.25 or 1.0
            local position = GetEntityCoords(entity) + move * (noclipSpeed * multiplier * GetFrameTime())

            SetEntityCoordsNoOffset(entity, position.x, position.y, position.z, true, true, true)
            SetEntityHeading(entity, rotation.z)
            SetEntityVisible(entity, false, false)

            drawScreenText(('Noclip · vitesse %d · Z/S/Q/D, E monter, A descendre, Maj rapide, Ctrl lent, molette'):format(math.floor(noclipSpeed)), 0.5, 0.95, 0.32, { 255, 255, 255 }, true)
            Wait(0)
        end

        -- Sortie du noclip : retour au sol avec collisions
        FreezeEntityPosition(entity, false)
        SetEntityCollision(entity, true, true)
        SetEntityVisible(entity, true, false)
        applyBody()
    end)
end

-- Maintient l'invisibilité / l'invincibilité (le personnage peut changer après une réapparition)
CreateThread(function()
    while true do
        if modes.invisible or modes.godmode or modes.noclip or modes.ghost then
            applyBody()

            -- Le staff invisible se voit lui-même en transparence
            if modes.invisible or modes.noclip or modes.ghost then
                SetEntityLocallyVisible(PlayerPedId())
                SetEntityAlpha(PlayerPedId(), 110, false)
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------------
-- Noms au-dessus des têtes
---------------------------------------------------------------------

local staffColors = {}

local function namesLoop()
    CreateThread(function()
        local nextColors = 0

        while modes.names do
            if GetGameTimer() >= nextColors then
                staffColors = lib.callback.await('lunatic_admin:staffColors', false) or {}
                nextColors = GetGameTimer() + 10000
            end

            local myCoords = GetEntityCoords(PlayerPedId())

            for _, player in ipairs(GetActivePlayers()) do
                local ped = GetPlayerPed(player)

                if ped ~= 0 and DoesEntityExist(ped) then
                    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)

                    if #(head - myCoords) <= Config.NamesDistance then
                        local serverId = GetPlayerServerId(player)
                        local state = Player(serverId).state
                        local name = (state.firstName and state.lastName) and ('%s %s'):format(state.firstName, state.lastName) or GetPlayerName(player)
                        local rgb = hexToRgb(staffColors[tostring(serverId)]) or { 255, 255, 255 }

                        draw3dText(head + vector3(0.0, 0.0, 0.42), ('[%d] %s'):format(serverId, name), rgb)
                    end
                end
            end

            Wait(0)
        end
    end)
end

---------------------------------------------------------------------
-- Coordonnées et badge des modes actifs
---------------------------------------------------------------------

local function currentPosition()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    return coords, GetEntityHeading(ped)
end

CreateThread(function()
    while true do
        local labels = {}

        if modes.noclip then labels[#labels + 1] = 'NOCLIP' end
        if modes.ghost then labels[#labels + 1] = 'FANTÔME' end
        if modes.invisible then labels[#labels + 1] = 'INVISIBLE' end
        if modes.godmode then labels[#labels + 1] = 'INVINCIBLE' end

        if #labels > 0 or modes.coords then
            if #labels > 0 then
                drawScreenText(table.concat(labels, '  ·  '), 0.5, 0.012, 0.36, { 190, 150, 255 }, true)
            end

            if modes.coords then
                local coords, heading = currentPosition()
                drawScreenText(('x %.2f   y %.2f   z %.2f   h %.1f'):format(coords.x, coords.y, coords.z, heading), 0.5, 0.045, 0.34, { 255, 255, 255 }, true)
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- Coordonnées pour la page Outils (copie vector3 / vector4)
RegisterNUICallback('getCoords', function(_, cb)
    local coords, heading = currentPosition()
    cb({ x = coords.x, y = coords.y, z = coords.z, h = heading })
end)

---------------------------------------------------------------------
-- Activation par le serveur
---------------------------------------------------------------------

RegisterNetEvent('lunatic_admin:tool', function(mode, enabled)
    if modes[mode] == nil then
        return
    end

    local wasEnabled = modes[mode]
    modes[mode] = enabled == true

    if mode == 'noclip' and modes.noclip and not wasEnabled then
        noclipLoop()
    elseif mode == 'names' and modes.names and not wasEnabled then
        namesLoop()
    end

    applyBody()
end)

-- Raccourci du noclip (F2 par défaut) : passe par le serveur qui vérifie la permission
RegisterCommand('lunatic_noclip', function()
    CreateThread(function()
        notifyError(ask('tool.toggle', { tool = 'noclip', enabled = not modes.noclip }))
    end)
end, false)
RegisterKeyMapping('lunatic_noclip', 'Staff : noclip', 'keyboard', Config.NoclipKey)

-- Raccourci du mode fantôme (aucune touche par défaut, à choisir dans les raccourcis FiveM)
RegisterCommand('lunatic_ghost', function()
    CreateThread(function()
        notifyError(ask('tool.toggle', { tool = 'ghost', enabled = not modes.ghost }))
    end)
end, false)
RegisterKeyMapping('lunatic_ghost', 'Staff : mode fantôme (godmod invisible)', 'keyboard', Config.GhostKey)

-- Raccourci de la téléportation au marqueur (aucune touche par défaut)
RegisterCommand('lunatic_tpm', function()
    CreateThread(function()
        notifyError(ask('tool.tpm'))
    end)
end, false)
RegisterKeyMapping('lunatic_tpm', 'Staff : téléportation au marqueur', 'keyboard', '')

---------------------------------------------------------------------
-- Téléportation au marqueur
---------------------------------------------------------------------

RegisterNetEvent('lunatic_admin:tpm', function()
    local blip = GetFirstBlipInfoId(8) -- marqueur posé sur la carte

    if not DoesBlipExist(blip) then
        return ESX.ShowNotification('Aucun marqueur sur la carte.', 'error')
    end

    local target = GetBlipInfoIdCoord(blip)
    local ground

    -- Cherche le sol en descendant depuis le ciel (la zone se charge pendant la recherche)
    for height = 1000.0, 0.0, -25.0 do
        RequestCollisionAtCoord(target.x, target.y, height)
        Wait(0)

        local found, z = GetGroundZFor_3dCoord(target.x, target.y, height, false)

        if found then
            ground = z
            break
        end
    end

    Teleport(vector3(target.x, target.y, (ground or 200.0) + 1.0))
end)

---------------------------------------------------------------------
-- Véhicules
---------------------------------------------------------------------

local SUBMARINES = { submersible = true, submersible2 = true, kosatka = true, avisa = true }

local function vehicleType(model, hash)
    if SUBMARINES[model] then return 'submarine' end
    if model:find('^trailer') or model:find('^tanker') or model:find('^boattrailer') or model:find('^tr%d') then return 'trailer' end
    if IsThisModelABike(hash) or IsThisModelABicycle(hash) then return 'bike' end
    if IsThisModelABoat(hash) or IsThisModelAJetski(hash) then return 'boat' end
    if IsThisModelAHeli(hash) then return 'heli' end
    if IsThisModelAPlane(hash) then return 'plane' end
    return 'automobile'
end

-- Recelleur : le serveur demande si un modèle de PNJ existe
lib.callback.register('lunatic_admin:pedModel', function(model)
    local hash = joaat(type(model) == 'string' and model:lower() or '')
    return IsModelInCdimage(hash) and IsModelAPed(hash)
end)

-- Lot L (Give un véhicule) : le serveur demande si le modèle existe et de quel type il est
lib.callback.register('lunatic_admin:vehicleModel', function(model)
    model = type(model) == 'string' and model:lower() or ''
    local hash = joaat(model)

    if model == '' or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return { ok = false }
    end

    return { ok = true, hash = hash, type = vehicleType(model, hash) }
end)

-- Tuile Items : partie client d'un objet d'ox_inventory (faim, soif, animation, objet en main, durée), connue seulement du jeu
lib.callback.register('lunatic_admin:itemClientInfo', function(name)
    local item = exports.ox_inventory:Items(name)
    local client = item and item.client

    if type(client) ~= 'table' then
        return {}
    end

    local anim, prop = client.anim, client.prop

    return {
        hunger = client.status and client.status.hunger or 0,
        thirst = client.status and client.status.thirst or 0,
        usetime = client.usetime,
        animDict = type(anim) == 'table' and anim.dict or (anim == 'eating' and 'mp_player_inteat@burger') or nil,
        propModel = type(prop) == 'table' and prop.model or nil,
        propName = type(prop) == 'string' and prop or nil,
    }
end)

-- Appelé par la page Outils : vérifie le modèle, le serveur crée le véhicule, on monte dedans
RegisterNUICallback('vehicleSpawn', function(data, cb)
    local model = type(data) == 'table' and type(data.model) == 'string' and data.model:lower():gsub('%s', '') or ''
    local hash = joaat(model)

    if model == '' or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return cb({ ok = false, error = ('Le modèle « %s » n\'existe pas.'):format(model) })
    end

    local result = ask('vehicle.spawn', { model = model, type = vehicleType(model, hash) })

    if not result or not result.ok then
        return cb(result or { ok = false, error = 'Pas de réponse du serveur.' })
    end

    local timeout = GetGameTimer() + 3000

    while not NetworkDoesEntityExistWithNetworkId(result.netId) and GetGameTimer() < timeout do
        Wait(0)
    end

    local vehicle = NetworkGetEntityFromNetworkId(result.netId)

    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        SetVehicleOnGroundProperly(vehicle)
        SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
    end

    cb({ ok = true })
end)

RegisterNetEvent('lunatic_admin:vehicleFix', function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)

    if vehicle ~= 0 then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        SetVehicleUndriveable(vehicle, false)
        SetVehicleDirtLevel(vehicle, 0.0)
        WashDecalsFromVehicle(vehicle, 1.0)
    end
end)

RegisterNetEvent('lunatic_admin:vehicleFlip', function()
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)

    if vehicle ~= 0 then
        local rotation = GetEntityRotation(vehicle, 2)
        SetEntityRotation(vehicle, 0.0, 0.0, rotation.z, 2, true)
        SetVehicleOnGroundProperly(vehicle)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    for mode in pairs(modes) do
        modes[mode] = false
    end

    local entity = controlledEntity()
    FreezeEntityPosition(entity, false)
    SetEntityCollision(entity, true, true)
    SetEntityVisible(entity, true, false)
    applyBody()
end)
