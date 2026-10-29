-- Actions RP du menu contextuel (lunatic_context : Alt gauche maintenu + clic droit).
-- Sur soi : emotes rapides, arrêter l'animation, détacher un objet coincé, parapluie, boombox, regarder ses papiers.
-- Sur un joueur : montrer sa carte d'identité ou son permis, le fouiller (mains levées ou inconscient, vérifié par le serveur).
-- Touche réglable (X par défaut) : arrête l'emote ou l'objet en main en cours, sinon lève / baisse les mains.
-- Mains levées partagées par le statebag handsUp (fouille).

local RESOURCE = 'lunatic_context'
local HANDS_UP = Config.HandsUp

local carried = nil -- objet porté : { key, entity, dict, anim, since }
local current = nil -- emote lancée depuis le menu : { dict, anim }

---------------------------------------------------------------------
-- Animations et objets portés
---------------------------------------------------------------------

local function loadDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000

    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
        Wait(10)
    end

    return HasAnimDictLoaded(dict)
end

local function loadModel(model)
    RequestModel(model)
    local timeout = GetGameTimer() + 3000

    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        Wait(10)
    end

    return HasModelLoaded(model)
end

local function setHandsUp(value)
    if (LocalPlayer.state.handsUp == true) ~= value then
        LocalPlayer.state:set('handsUp', value, true)
    end
end

local function dropCarried()
    if carried and DoesEntityExist(carried.entity) then
        DetachEntity(carried.entity, true, false)
        DeleteEntity(carried.entity)
    end

    carried = nil
end

local function canAnimate(ped)
    return not IsPedInAnyVehicle(ped, false) and not IsPedDeadOrDying(ped, true) and not IsPedRagdoll(ped)
end

local function stopAnimation()
    local ped = PlayerPedId()
    dropCarried()
    current = nil
    setHandsUp(false)
    ClearPedTasks(ped)
end

local function playEmote(emote)
    local ped = PlayerPedId()

    if not canAnimate(ped) then
        return Notify('Impossible pour le moment.', 'error')
    end

    if not loadDict(emote.dict) then
        return Notify('Animation indisponible.', 'error')
    end

    dropCarried()
    TaskPlayAnim(ped, emote.dict, emote.anim, 3.0, 3.0, -1, emote.flag or 49, 0.0, false, false, false)
    RemoveAnimDict(emote.dict)
    current = { dict = emote.dict, anim = emote.anim }
    setHandsUp(emote.dict == HANDS_UP.dict and emote.anim == HANDS_UP.anim)
end

-- Parapluie, boombox… : sorti, ou rangé s'il est déjà en main
local function toggleCarry(key)
    local def = Config.ContextProps[key]
    local ped = PlayerPedId()

    if carried and carried.key == key then
        return stopAnimation()
    end

    if not canAnimate(ped) then
        return Notify('Impossible pour le moment.', 'error')
    end

    local model = joaat(def.model)

    if not loadModel(model) or not loadDict(def.dict) then
        return Notify('Objet indisponible.', 'error')
    end

    stopAnimation()

    local coords = GetEntityCoords(ped)
    local object = CreateObject(model, coords.x, coords.y, coords.z + 0.2, true, true, false)
    SetModelAsNoLongerNeeded(model)
    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, def.bone), def.offset.x, def.offset.y, def.offset.z,
        def.rotation.x, def.rotation.y, def.rotation.z, true, true, false, true, 1, true)
    TaskPlayAnim(ped, def.dict, def.anim, 3.0, 3.0, -1, def.flag or 49, 0.0, false, false, false)
    RemoveAnimDict(def.dict)
    carried = { key = key, entity = object, dict = def.dict, anim = def.anim, since = GetGameTimer() }
end

-- Objets restés accrochés au personnage (script planté, animation coupée) : détachés, supprimés quand ils sont à nous.
-- L'arme en main et l'arme dans le dos ne sont jamais touchées.
local function detachObjects()
    local ped = PlayerPedId()
    local weapon = GetCurrentPedWeaponEntityIndex(ped)
    local back = BackWeaponObject()
    local count = 0

    for _, object in ipairs(GetGamePool('CObject')) do
        if object ~= weapon and object ~= back and IsEntityAttachedToEntity(object, ped) then
            DetachEntity(object, true, false)

            if not NetworkGetEntityIsNetworked(object) or NetworkHasControlOfEntity(object) then
                SetEntityAsMissionEntity(object, true, true)
                DeleteEntity(object)
            end

            count = count + 1
        end
    end

    carried = nil
    ClearPedSecondaryTask(ped)
    Notify(count > 0 and ('%d objet(s) détaché(s).'):format(count) or 'Aucun objet accroché.', count > 0 and 'success' or 'info')
end

-- Animation coupée (véhicule, chute, autre script) : objet porté retiré, mains levées terminées
CreateThread(function()
    while true do
        local ped = PlayerPedId()

        if carried and GetGameTimer() - carried.since > 1500 and not IsEntityPlayingAnim(ped, carried.dict, carried.anim, 3) then
            dropCarried()
        end

        if LocalPlayer.state.handsUp and not IsEntityPlayingAnim(ped, HANDS_UP.dict, HANDS_UP.anim, 3) then
            setHandsUp(false)
        end

        Wait(500)
    end
end)

-- X : arrête ce qui est en cours (mains levées, emote, objet en main), sinon lève les mains
RegisterCommand('lunatic_handsup', function()
    local ped = PlayerPedId()

    if IsEntityPlayingAnim(ped, HANDS_UP.dict, HANDS_UP.anim, 3) then
        StopAnimTask(ped, HANDS_UP.dict, HANDS_UP.anim, 2.0)
        current = nil
        setHandsUp(false)
    elseif carried or (current and IsEntityPlayingAnim(ped, current.dict, current.anim, 3)) then
        stopAnimation()
    -- X annule aussi les barres de progression d'ox_lib : pas de mains levées pendant l'une d'elles
    elseif not IsNuiFocused() and not lib.progressActive() then
        playEmote(HANDS_UP)
    end
end, false)
RegisterKeyMapping('lunatic_handsup', 'Lever les mains / arrêter l’animation', 'keyboard', 'X')

---------------------------------------------------------------------
-- Entrées du menu
---------------------------------------------------------------------

local function documentCount(item)
    local ok, count = pcall(function() return exports.ox_inventory:Search('count', item) end)
    return ok and tonumber(count) or 0
end

local function selfItems(ctx)
    local inVehicle = ctx.inVehicle ~= nil
    local emotes = {}

    for _, emote in ipairs(Config.ContextEmotes) do
        emotes[#emotes + 1] = { label = emote.label, onSelect = function() playEmote(emote) end }
    end

    local items = {
        { label = ('ID %d (vous)'):format(ctx.serverId), header = true },
        { label = 'Emotes rapides', submenu = emotes, disabled = inVehicle },
        { label = "Arrêter l'animation", onSelect = stopAnimation },
        { label = "Détacher l'objet", onSelect = detachObjects },
    }

    for _, key in ipairs(Config.ContextPropsOrder) do
        local def = Config.ContextProps[key]
        local inHand = carried and carried.key == key

        items[#items + 1] = { label = inHand and ('Ranger : %s'):format(def.label:lower()) or def.label, right = inHand and 'en main' or nil, disabled = inVehicle, onSelect = function() toggleCarry(key) end }
    end

    if documentCount(Config.IdCardItem) > 0 then
        items[#items + 1] = { label = "Regarder ma carte d'identité", onSelect = function()
            local identity = lib.callback.await('lunatic_gameplay:idcard', false)

            if identity then
                TriggerEvent('lunatic_gameplay:idcardDisplay', identity)
            end
        end }
    end

    return items
end

local function playerItems(ctx)
    local target = ctx.serverId
    local ped = ctx.entity
    local items = { { label = ('ID %d'):format(target), header = true } }

    if documentCount(Config.IdCardItem) > 0 then
        items[#items + 1] = { label = "Montrer ma carte d'identité", onSelect = function()
            TriggerServerEvent('lunatic_gameplay:idcardShowTo', 'idcard', target)
        end }
    end

    if documentCount(Config.DriverLicenseItem) > 0 then
        items[#items + 1] = { label = 'Montrer mon permis', onSelect = function()
            TriggerServerEvent('lunatic_gameplay:idcardShowTo', 'license', target)
        end }
    end

    -- Indication seulement : le serveur revérifie mains levées / inconscience et distance
    local searchable = Player(target).state.handsUp == true or IsPedDeadOrDying(ped, true)

    items[#items + 1] = {
        label = 'Fouiller', right = not searchable and 'mains levées' or nil, disabled = not searchable, close = true,
        onSelect = function()
            local result = lib.callback.await('lunatic_gameplay:search', false, target)

            if result and result.error then
                Notify(result.error, 'error')
            end
        end,
    }

    return items
end

local function build(ctx)
    if ctx.kind == 'self' and ctx.serverId then
        return selfItems(ctx)
    end

    if ctx.kind == 'player' and ctx.serverId and DoesEntityExist(ctx.entity) then
        return playerItems(ctx)
    end
end

local function register()
    local ok, err = pcall(function()
        exports[RESOURCE]:register('roleplay', build, 10)
    end)

    if not ok then
        print(('[lunatic_gameplay] Actions RP : enregistrement dans %s impossible : %s'):format(RESOURCE, err))
    end
end

CreateThread(function()
    if GetResourceState(RESOURCE) == 'started' then
        register()
    end
end)

-- lunatic_context (re)démarré après nous
AddEventHandler('onClientResourceStart', function(resource)
    if resource == RESOURCE then
        register()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        dropCarried()
        setHandsUp(false)
    end
end)
