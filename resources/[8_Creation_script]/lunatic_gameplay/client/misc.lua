-- Confort et sécurité (réglages : tuile Fonctionnalités → Gameplay → Confort & sécurité) :
-- arme dans le dos, zones sécurisées, anti-AFK.

local function settings()
    return FeaturesOf('misc')
end

---------------------------------------------------------------------
-- Arme dans le dos : la plus grosse arme de l'inventaire, quand elle n'est pas en main
---------------------------------------------------------------------

local backObject, backWeapon = nil, nil

local function removeBack()
    if backObject and DoesEntityExist(backObject) then
        DeleteEntity(backObject)
    end

    backObject, backWeapon = nil, nil
end

local function bigWeaponInInventory()
    local ok, items = pcall(function() return exports.ox_inventory:GetPlayerItems() end)

    if not ok or type(items) ~= 'table' then
        return nil
    end

    for _, item in pairs(items) do
        if type(item.name) == 'string' and item.name:sub(1, 7):upper() == 'WEAPON_' then
            local hash = joaat(item.name)

            if Config.BackWeaponGroups[GetWeapontypeGroup(hash)] then
                return hash
            end
        end
    end
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local wanted = nil

        if settings().weaponBack ~= false and not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false) then
            local hash = bigWeaponInInventory()

            if hash and GetSelectedPedWeapon(ped) ~= hash then
                wanted = hash
            end
        end

        if wanted ~= backWeapon then
            removeBack()

            if wanted then
                local model = GetWeapontypeModel(wanted)
                RequestModel(model)
                local timeout = GetGameTimer() + 3000

                while not HasModelLoaded(model) and GetGameTimer() < timeout do
                    Wait(50)
                end

                if HasModelLoaded(model) then
                    local coords = GetEntityCoords(ped)
                    local object = CreateObject(model, coords.x, coords.y, coords.z - 2.0, true, true, false)
                    local o = Config.BackWeaponOffset
                    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, o.bone), o.pos.x, o.pos.y, o.pos.z, o.rot.x, o.rot.y, o.rot.z, true, true, false, true, 2, true)
                    SetModelAsNoLongerNeeded(model)
                    backObject, backWeapon = object, wanted
                end
            end
        end

        Wait(1000)
    end
end)

---------------------------------------------------------------------
-- Zones sécurisées
---------------------------------------------------------------------

local inZone = nil

CreateThread(function()
    while true do
        local wait = 1000
        local zone = nil

        if settings().safeZones ~= false then
            local coords = GetEntityCoords(PlayerPedId())

            for _, entry in ipairs(Config.SafeZones) do
                if #(coords - entry.coords) < entry.radius then
                    zone = entry
                end
            end
        end

        if zone ~= inZone then
            inZone = zone

            if zone then
                Notify(('Zone sécurisée : %s.'):format(zone.label), 'info')
            end
        end

        if inZone then
            wait = 0
            local ped = PlayerPedId()
            DisablePlayerFiring(PlayerId(), true)

            for _, control in ipairs({ 24, 25, 140, 141, 142, 257, 263, 264 }) do
                DisableControlAction(0, control, true)
            end

            if GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then
                SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
            end
        end

        Wait(wait)
    end
end)

---------------------------------------------------------------------
-- Anti-AFK : avertissement puis expulsion (hors service seulement si réglé)
---------------------------------------------------------------------

local lastActive = GetGameTimer()
local lastCoords = vector3(0.0, 0.0, 0.0)
local warned = false

CreateThread(function()
    while true do
        Wait(5000)
        local s = settings()
        local coords = GetEntityCoords(PlayerPedId())

        if #(coords - lastCoords) > 1.0 or IsControlPressed(0, 1) or IsControlPressed(0, 2) then
            lastActive, warned = GetGameTimer(), false
        end

        lastCoords = coords

        -- Dans la zone AFK (tuile Autres), on n'est jamais expulsé
        if s.afk and not LocalPlayer.state.afkZone then
            local job = ESX.PlayerData and ESX.PlayerData.job
            local onDuty = job and job.name ~= 'unemployed' and job.onDuty
            local limit = (tonumber(s.afkMinutes) or 20) * 60000
            local idle = GetGameTimer() - lastActive

            if s.afkOffDutyOnly and onDuty then
                lastActive = GetGameTimer()
            elseif idle > limit then
                TriggerServerEvent('lunatic_gameplay:afk')
                lastActive = GetGameTimer()
            elseif idle > limit - 60000 and not warned then
                warned = true
                Notify('Inactif : vous serez expulsé dans une minute si vous ne bougez pas.', 'error')
            end
        else
            lastActive = GetGameTimer()
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        removeBack()
    end
end)
