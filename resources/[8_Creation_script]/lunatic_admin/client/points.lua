-- Vue staff des points de la page Braquages (magasins, maisons, GoFast, yacht) : un blip par point sur la carte,
-- et de près un repère au sol avec son nom. Activée depuis le panel (« Voir les points en jeu »), pour soi seulement.

local points = nil -- liste reçue du serveur, nil = vue coupée
local blips = {}

local COLORS = { house = 5, gofast_start = 2, gofast_drop = 2, gofast_sea_start = 3, gofast_sea_drop = 3, yacht = 1 }

local function clearBlips()
    for _, blip in ipairs(blips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    blips = {}
end

RegisterNetEvent('lunatic_admin:holdupStaffView', function(list)
    clearBlips()
    points = type(list) == 'table' and list or nil

    for _, point in ipairs(points or {}) do
        local blip = AddBlipForCoord(point.x + 0.0, point.y + 0.0, (point.z > -100.0 and point.z or 0.0) + 0.0)
        SetBlipSprite(blip, 1)
        SetBlipScale(blip, 0.7)
        SetBlipColour(blip, point.active and (COLORS[point.type] or 27) or 40)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(('[%s] %s #%d'):format(point.short, point.label, point.id))
        EndTextCommandSetBlipName(blip)
        blips[#blips + 1] = blip
    end
end)

local function drawText3D(x, y, z, text)
    local visible, sx, sy = World3dToScreen2d(x, y, z)

    if not visible then
        return
    end

    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 230)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end

CreateThread(function()
    while true do
        local wait = 1000

        if points then
            local coords = GetEntityCoords(PlayerPedId())

            for _, point in ipairs(points) do
                local z = point.z > -100.0 and point.z or coords.z
                local distance = #(coords - vector3(point.x, point.y, z))

                if distance < 40.0 then
                    wait = 0
                    -- Les positions sont à hauteur des pieds (« Définir ») : repère posé au sol, texte au-dessus
                    DrawMarker(1, point.x, point.y, z - 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.6, 255, 160, 60, 140, false, false, 2, false, nil, nil, false)
                    drawText3D(point.x, point.y, z + 1.2, ('%s · %s #%d%s'):format(point.short, point.label, point.id, point.active and '' or ' (inactif)'))
                end
            end
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clearBlips()
    end
end)
