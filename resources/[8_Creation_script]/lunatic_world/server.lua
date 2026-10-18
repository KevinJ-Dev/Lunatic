-- Serveur : seule source de vérité pour la météo et l'heure, diffusées à tous via GlobalState.
-- Les changements passent par les exports (appelés par lunatic_admin, qui vérifie les permissions).

local state = {
    weather = Config.StartWeather,
    hour = Config.StartHour,
    minute = 0,
    frozen = false,   -- heure figée
    cycle = Config.WeatherCycle,
    blackout = false,
}

local nextCycleAt = 0

-- Reprend l'état mémorisé au dernier arrêt
local saved = GetResourceKvpString('state')

if saved then
    local ok, data = pcall(json.decode, saved)

    if ok and type(data) == 'table' then
        for key in pairs(state) do
            if data[key] ~= nil then
                state[key] = data[key]
            end
        end
    end
end

if not Config.Weathers[state.weather] then
    state.weather = Config.StartWeather
end

local function save()
    SetResourceKvp('state', json.encode(state))
end

local function publishWorld()
    GlobalState.lunaticWorld = { weather = state.weather, blackout = state.blackout }
end

local function publishClock()
    GlobalState.lunaticClock = { h = state.hour, m = state.minute }
end

publishWorld()
publishClock()

---------------------------------------------------------------------
-- Horloge
---------------------------------------------------------------------

CreateThread(function()
    local sinceSave = 0

    while true do
        Wait(Config.MinuteDuration)

        if not state.frozen then
            state.minute = state.minute + 1

            if state.minute >= 60 then
                state.minute = 0
                state.hour = (state.hour + 1) % 24
            end

            publishClock()
        end

        -- Sauvegarde environ toutes les 5 minutes réelles
        sinceSave = sinceSave + Config.MinuteDuration

        if sinceSave >= 5 * 60 * 1000 then
            sinceSave = 0
            save()
        end
    end
end)

---------------------------------------------------------------------
-- Cycle météo automatique
---------------------------------------------------------------------

local function setWeather(weather)
    state.weather = weather
    nextCycleAt = GetGameTimer() + Config.CycleMinutes * 60 * 1000
    publishWorld()
    save()
end

CreateThread(function()
    nextCycleAt = GetGameTimer() + Config.CycleMinutes * 60 * 1000

    while true do
        Wait(10000)

        if state.cycle and GetGameTimer() >= nextCycleAt then
            local options = Config.Cycle[state.weather] or { 'CLEAR' }
            local nextWeather = options[math.random(#options)]

            setWeather(nextWeather)
            print(('[lunatic_world] Cycle météo : %s'):format(nextWeather))
        end
    end
end)

---------------------------------------------------------------------
-- Exports (appelés par lunatic_admin)
---------------------------------------------------------------------

exports('getState', function()
    local weathers = {}

    for id, label in pairs(Config.Weathers) do
        weathers[#weathers + 1] = { id = id, label = label }
    end

    table.sort(weathers, function(a, b) return a.label < b.label end)

    return {
        weather = state.weather,
        hour = state.hour,
        minute = state.minute,
        frozen = state.frozen,
        cycle = state.cycle,
        blackout = state.blackout,
        weathers = weathers,
        cycleMinutes = Config.CycleMinutes,
    }
end)

-- Les exports renvoient { ok, error } (une seule valeur, plus sûre entre deux resources)
exports('setWeather', function(weather)
    if type(weather) ~= 'string' or not Config.Weathers[weather] then
        return { ok = false, error = 'Météo inconnue.' }
    end

    setWeather(weather)
    return { ok = true }
end)

exports('setTime', function(hour, minute)
    hour, minute = tonumber(hour), tonumber(minute)

    if not hour or not minute or hour ~= math.floor(hour) or minute ~= math.floor(minute) or hour < 0 or hour > 23 or minute < 0 or minute > 59 then
        return { ok = false, error = 'Heure invalide.' }
    end

    state.hour, state.minute = hour, minute
    publishClock()
    save()
    return { ok = true }
end)

exports('setFrozen', function(enabled)
    state.frozen = enabled == true
    save()
    return { ok = true }
end)

exports('setCycle', function(enabled)
    state.cycle = enabled == true
    nextCycleAt = GetGameTimer() + Config.CycleMinutes * 60 * 1000
    save()
    return { ok = true }
end)

exports('setBlackout', function(enabled)
    state.blackout = enabled == true
    publishWorld()
    save()
    return { ok = true }
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        save()
    end
end)

print(('[lunatic_world] Météo %s, %02d:%02d%s.'):format(state.weather, state.hour, state.minute, state.frozen and ' (heure figée)' or ''))
