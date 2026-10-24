-- Tuile Interactions, mode édition : le staff voit en jeu tous les points d'interaction (magasins, location, grossistes,
-- recelleur) à moins de 60 m, avec leur nom, leur rayon de [E] et leur PNJ, même ceux sans blip.

local enabled = false

local function draw3dText(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)

    if not onScreen then
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

local function points()
    local list = {}

    for _, shop in ipairs(GlobalState.lunaticShops or {}) do
        for _, location in ipairs(shop.locations or {}) do
            list[#list + 1] = {
                x = location.x, y = location.y, z = location.z, radius = tonumber(location.radius) or 1.5, label = shop.label,
                ped = location.ped, pedPos = location.pedPos, blip = location.showBlip ~= false,
            }
        end
    end

    for _, location in ipairs((GlobalState.lunaticFence or {}).locations or {}) do
        list[#list + 1] = { x = location.x, y = location.y, z = location.z, radius = tonumber(location.radius) or 2.0, label = 'Recelleur', ped = location.ped, blip = location.showBlip == true }
    end

    return list
end

RegisterNetEvent('lunatic_admin:interactionsEditMode', function(value)
    enabled = value == true
    ESX.ShowNotification(enabled and 'Mode édition des interactions : activé.' or 'Mode édition des interactions : désactivé.', 'info')

    if not enabled then
        return
    end

    CreateThread(function()
        local list, refreshAt = points(), GetGameTimer() + 2000

        while enabled do
            if GetGameTimer() > refreshAt then
                list, refreshAt = points(), GetGameTimer() + 2000
            end

            local coords = GetEntityCoords(PlayerPedId())

            for _, point in ipairs(list) do
                if #(coords - vector3(point.x, point.y, point.z)) < 60.0 then
                    local size = point.radius * 2.0
                    DrawMarker(1, point.x, point.y, point.z - 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, 0.4, 242, 194, 107, 70, false, false, 2, false, nil, nil, false)
                    draw3dText(point.x, point.y, point.z + 1.2, ('%s~n~~c~[E] %.1f m · %s · %s'):format(point.label, point.radius, point.ped and ('PNJ ' .. point.ped) or 'sans PNJ', point.blip and 'blip' or 'sans blip'))

                    if point.pedPos then
                        DrawLine(point.x, point.y, point.z + 0.2, point.pedPos.x, point.pedPos.y, point.pedPos.z + 0.2, 150, 80, 255, 200)
                    end
                end
            end

            Wait(0)
        end
    end)
end)
