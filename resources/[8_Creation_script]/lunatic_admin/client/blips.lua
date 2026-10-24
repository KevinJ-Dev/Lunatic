-- Blips de la carte gérés dans le panel (tuile Blips) : recréés dès que GlobalState.lunaticBlips change,
-- sans redémarrage. Les blips des magasins restent créés par lunatic_business.

local created = {}

local function clear()
    for _, blip in ipairs(created) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    created = {}
end

local function apply(list)
    clear()

    for _, entry in ipairs(type(list) == 'table' and list or {}) do
        local blip = AddBlipForCoord(entry.x + 0.0, entry.y + 0.0, entry.z + 0.0)
        SetBlipSprite(blip, entry.sprite)
        SetBlipColour(blip, entry.color)
        SetBlipScale(blip, entry.scale + 0.0)
        SetBlipDisplay(blip, 4)
        SetBlipAsShortRange(blip, entry.short == true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(entry.label)
        EndTextCommandSetBlipName(blip)
        created[#created + 1] = blip
    end
end

AddStateBagChangeHandler('lunaticBlips', 'global', function(_, _, value)
    apply(value)
end)

CreateThread(function()
    while not GlobalState.lunaticBlips do
        Wait(1000)
    end

    apply(GlobalState.lunaticBlips)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clear()
    end
end)
