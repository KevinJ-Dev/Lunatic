-- Effets des drogues et de l'alcool côté client : animation, puis pendant la durée réglée dans le panel :
-- vitesse de course, tremblement de caméra, flou de mouvement, filtre visuel et démarche. Une nouvelle prise prolonge l'effet.

local active = nil -- { effect, endsAt }

local function settingsOf(effect)
    return FeaturesOf('effects_' .. effect)
end

local function loadAnimSet(name)
    RequestAnimSet(name)
    local timeout = GetGameTimer() + 3000

    while not HasAnimSetLoaded(name) and GetGameTimer() < timeout do
        Wait(50)
    end

    return HasAnimSetLoaded(name)
end

local function clearEffect()
    local ped = PlayerPedId()
    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    SetPedMotionBlur(ped, false)
    ClearTimecycleModifier()
    StopGameplayCamShaking(true)
    AnimpostfxStopAll()
    ResetPedMovementClipset(ped, 0.5)
    active = nil
end

local function startEffect(effect)
    local entry = Config.Effects[effect]
    local s = settingsOf(effect)
    local ped = PlayerPedId()
    local duration = tonumber(s.duration) or 120

    -- Déjà sous le même effet : prolongé
    if active and active.effect == effect then
        active.endsAt = GetGameTimer() + duration * 1000
        return
    end

    if active then
        clearEffect()
    end

    active = { effect = effect, endsAt = GetGameTimer() + duration * 1000 }

    SetRunSprintMultiplierForPlayer(PlayerId(), math.min(1.49, tonumber(s.speed) or 1.0))
    SetPedMotionBlur(ped, s.blur == true)

    if s.visual ~= false then
        if entry.timecycle then
            SetTimecycleModifier(entry.timecycle)
            SetTimecycleModifierStrength(0.6)
        end

        if entry.postfx then
            AnimpostfxPlay(entry.postfx, 0, true)
        end
    end

    local shake = tonumber(s.shake) or 0

    if shake > 0 then
        ShakeGameplayCam(entry.shake or 'DRUNK_SHAKE', shake)
    end

    if entry.walk and s.walk ~= false and loadAnimSet(entry.walk) then
        SetPedMovementClipset(ped, entry.walk, 0.5)
    end

    CreateThread(function()
        while active and active.effect == effect and GetGameTimer() < active.endsAt do
            Wait(1000)
        end

        if active and active.effect == effect then
            clearEffect()
        end
    end)
end

RegisterNetEvent('lunatic_gameplay:effect', function(effect)
    local entry = Config.Effects[effect]

    if not entry then
        return
    end

    local done = lib.progressBar({
        duration = 4000, label = entry.label or 'Consommation…', canCancel = false,
        disable = { car = false, combat = true },
        anim = entry.anim,
    })

    if done then
        startEffect(effect)
    end
end)

-- Mort ou respawn : plus d'effet
AddEventHandler('esx:onPlayerDeath', function()
    if active then
        clearEffect()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and active then
        clearEffect()
    end
end)
