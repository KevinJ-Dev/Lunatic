-- Territoires sur la carte : visibles par les membres d'un crew (zones à leur crew en vert, à un autre crew en rouge,
-- libres en blanc) et par le staff en « vue staff » (bouton de l'onglet Territoires du panel). Gérés dans le panel staff.

local territories = {}
local blips = {}
local staffView = false

local function clear()
    for _, blip in ipairs(blips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    blips = {}
end

local function draw()
    clear()

    local crew = LocalPlayer.state.crew

    if not crew and not staffView then
        return
    end

    for _, t in ipairs(territories) do
        local color = Config.TerritoryColors.free

        if t.owner then
            color = crew and t.owner.id == crew.id and Config.TerritoryColors.mine or Config.TerritoryColors.enemy
        end

        local area = AddBlipForRadius(t.x, t.y, 0.0, t.radius + 0.0)
        SetBlipColour(area, color)
        SetBlipAlpha(area, Config.TerritoryAlpha)
        blips[#blips + 1] = area

        local center = AddBlipForCoord(t.x, t.y, 0.0)
        SetBlipSprite(center, Config.TerritoryBlipSprite)
        SetBlipColour(center, color)
        SetBlipScale(center, 0.7)
        SetBlipAsShortRange(center, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(('Territoire : %s (%s)'):format(t.label, t.owner and t.owner.label or 'libre'))
        EndTextCommandSetBlipName(center)
        blips[#blips + 1] = center
    end
end

AddStateBagChangeHandler('lunaticTerritories', 'global', function(_, _, value)
    territories = type(value) == 'table' and value or {}
    draw()
end)

AddStateBagChangeHandler('crew', ('player:%d'):format(GetPlayerServerId(PlayerId())), function()
    Wait(0)
    draw()
end)

RegisterNetEvent('lunatic_illegal:staffTerritories', function(enabled)
    staffView = enabled == true
    draw()
    ESX.ShowNotification(staffView and 'Vue staff : territoires affichés sur votre carte.' or 'Vue staff des territoires désactivée.', 'info')
end)

CreateThread(function()
    territories = GlobalState.lunaticTerritories or {}
    Wait(2000)
    draw()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clear()
    end
end)
