-- Zone AFK, côté client : téléportation (aller et retour) et invincibilité dans la zone si réglée.

local protected = false

RegisterNetEvent('lunatic_gameplay:afkTeleport', function(point)
    if type(point) ~= 'table' then
        return
    end

    DoScreenFadeOut(400)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    local ped = PlayerPedId()
    RequestCollisionAtCoord(point.x, point.y, point.z)
    SetEntityCoords(ped, point.x + 0.0, point.y + 0.0, point.z - 0.98, false, false, false, false)
    SetEntityHeading(ped, (point.h or 0.0) + 0.0)
    Wait(600)
    DoScreenFadeIn(400)
end)

CreateThread(function()
    while true do
        local zone = GlobalState.lunaticAfkZone
        local inside = LocalPlayer.state.afkZone == true and type(zone) == 'table' and zone.invincible

        if inside then
            SetEntityInvincible(PlayerPedId(), true)
            protected = true
        elseif protected then
            SetEntityInvincible(PlayerPedId(), false)
            protected = false
        end

        Wait(1000)
    end
end)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/afk', 'Aller dans la zone AFK (ou en revenir)')
end)
