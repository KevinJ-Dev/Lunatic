-- Lot D : page Monde (météo et heure), pilotée via les exports de lunatic_world.

local function worldReady()
    return GetResourceState('lunatic_world') == 'started'
end

-- Appelle un export de lunatic_world et renvoie sa réponse { ok, error }
local function call(name, ...)
    if not worldReady() then
        return { ok = false, error = "lunatic_world n'est pas démarré." }
    end

    local args = { ... }
    local ok, result = pcall(function()
        return exports.lunatic_world[name](exports.lunatic_world, table.unpack(args))
    end)

    if not ok or type(result) ~= 'table' then
        print(('[lunatic_admin] lunatic_world:%s a échoué : %s'):format(name, tostring(result)))
        return { ok = false, error = 'lunatic_world ne répond pas (voir la console).' }
    end

    return result
end

-- État du monde pour la page Monde
table.insert(Panel.stateHooks, function(state, _, rank)
    if not Ranks.hasPermission(rank, 'world.weather') and not Ranks.hasPermission(rank, 'world.time') then
        return
    end

    if not worldReady() then
        state.world = { available = false }
        return
    end

    local ok, world = pcall(function()
        return exports.lunatic_world:getState()
    end)

    if ok and type(world) == 'table' then
        world.available = true
        state.world = world
    else
        state.world = { available = false }
    end
end)

local function denied()
    return Panel.fail("Vous n'avez pas la permission.")
end

local function done(result, src, action, details)
    if not result.ok then
        return Panel.fail(result.error or 'Action impossible.')
    end

    Logs.add(src, action, nil, details)
    return { ok = true } -- non silencieux : les autres panels voient le nouvel état
end

Panel.actions['world.weather'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'world.weather') then
        return denied()
    end

    return done(call('setWeather', data.weather), src, 'world.weather', { weather = data.weather })
end

Panel.actions['world.cycle'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'world.weather') then
        return denied()
    end

    return done(call('setCycle', data.enabled == true), src, 'world.cycle', { enabled = data.enabled == true })
end

Panel.actions['world.blackout'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'world.weather') then
        return denied()
    end

    return done(call('setBlackout', data.enabled == true), src, 'world.blackout', { enabled = data.enabled == true })
end

Panel.actions['world.time'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'world.time') then
        return denied()
    end

    return done(call('setTime', data.hour, data.minute), src, 'world.time', { hour = data.hour, minute = data.minute })
end

Panel.actions['world.freeze'] = function(src, actor, data)
    if not Ranks.hasPermission(actor, 'world.time') then
        return denied()
    end

    return done(call('setFrozen', data.enabled == true), src, 'world.freeze', { enabled = data.enabled == true })
end

print('[lunatic_admin] Module Monde chargé.')
