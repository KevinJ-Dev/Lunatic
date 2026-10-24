-- Client : applique la météo et l'heure reçues du serveur (GlobalState), identiques pour tous.

local currentWeather
local transitionUntil = 0

local SNOW = { SNOW = true, BLIZZARD = true, SNOWLIGHT = true, XMAS = true }

local function applyWeather(weather, instant)
    if type(weather) ~= 'string' or weather == currentWeather then
        return
    end

    local previous = currentWeather
    currentWeather = weather

    ClearOverrideWeather()
    ClearWeatherTypePersist()

    if instant or not previous then
        SetWeatherTypeNowPersist(weather)
        SetWeatherTypeNow(weather)
        SetOverrideWeather(weather)
    else
        -- Transition progressive, puis verrouillage de la météo
        SetWeatherTypeOvertimePersist(weather, Config.TransitionSeconds + 0.0)
        transitionUntil = GetGameTimer() + Config.TransitionSeconds * 1000

        SetTimeout(Config.TransitionSeconds * 1000, function()
            if currentWeather == weather then
                SetOverrideWeather(weather)
            end
        end)
    end

    -- Traces de pas et de pneus dans la neige
    local snow = SNOW[weather] == true
    SetForceVehicleTrails(snow)
    SetForcePedFootstepsTracks(snow)
end

local function applyWorld(world, instant)
    if type(world) ~= 'table' then
        return
    end

    applyWeather(world.weather, instant)
    SetArtificialLightsState(world.blackout == true)
    SetArtificialLightsStateAffectsVehicles(false) -- les phares restent allumés pendant une panne
end

local function applyClock(clock)
    -- Dans la zone d'un event avec une heure imposée (lunatic_admin), l'heure de l'event reste affichée
    local event = LocalPlayer.state.lunaticEvent

    if event and event.hour then
        return
    end

    if type(clock) == 'table' then
        NetworkOverrideClockTime(tonumber(clock.h) or 12, tonumber(clock.m) or 0, 0)
    end
end

AddStateBagChangeHandler('lunaticWorld', 'global', function(_, _, value)
    applyWorld(value, false)
end)

AddStateBagChangeHandler('lunaticClock', 'global', function(_, _, value)
    applyClock(value)
end)

CreateThread(function()
    -- L'heure n'avance que sur ordre du serveur (sinon chaque joueur dériverait)
    PauseClock(true)

    while not GlobalState.lunaticWorld do
        Wait(200)
    end

    applyWorld(GlobalState.lunaticWorld, true)
    applyClock(GlobalState.lunaticClock)

    -- Filet de sécurité : réapplique l'état si un autre script l'a modifié
    while true do
        Wait(10000)

        if GetGameTimer() > transitionUntil and GlobalState.lunaticWorld then
            local wanted = GlobalState.lunaticWorld.weather

            if wanted and wanted ~= currentWeather then
                applyWeather(wanted, true)
            else
                SetOverrideWeather(currentWeather)
            end
        end

        PauseClock(true)
        applyClock(GlobalState.lunaticClock)
    end
end)
