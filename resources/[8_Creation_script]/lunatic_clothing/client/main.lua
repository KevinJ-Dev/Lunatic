-- Magasins de vêtements, côté client : marqueurs et [E], essayage en direct (caméra devant le personnage, bras
-- levés, rotation), panier envoyé au serveur. Quitter sans payer remet la tenue d'avant (illenium-appearance).
-- Repris de lunatic_creator : caméra décalée, nombre de modèles et de couleurs, bras levés.

local appearanceApi = exports['illenium-appearance']
local shop = nil -- magasin ouvert : { index, store, original, anchor, cam, view }

local function notify(text, kind)
    ESX.ShowNotification(text, kind or 'info')
end

local function sexOf(ped)
    return GetEntityModel(ped) == `mp_f_freemode_01` and 'female' or 'male'
end

---------------------------------------------------------------------
-- Pièces portées
---------------------------------------------------------------------

local function wornPiece(ped, category)
    if category.kind == 'prop' then
        local drawable = GetPedPropIndex(ped, category.id)
        return { drawable, drawable >= 0 and GetPedPropTextureIndex(ped, category.id) or 0 }
    end

    return { GetPedDrawableVariation(ped, category.id), GetPedTextureVariation(ped, category.id) }
end

local function wornAll(ped)
    local worn = {}

    for _, group in ipairs(Config.Groups) do
        for _, category in ipairs(group.categories) do
            worn[category.key] = wornPiece(ped, category)
        end
    end

    return worn
end

local function applyPiece(ped, category, drawable, texture)
    if category.kind == 'prop' then
        if drawable < 0 then
            ClearPedProp(ped, category.id)
        else
            SetPedPropIndex(ped, category.id, drawable, texture, true)
        end

        return
    end

    SetPedComponentVariation(ped, category.id, drawable, texture, 0)
end

-- Nombre de modèles et de couleurs d'une catégorie (selon le modèle homme / femme)
local function counts(category, drawable)
    local ped = PlayerPedId()

    if category.kind == 'prop' then
        return { drawables = GetNumberOfPedPropDrawableVariations(ped, category.id), textures = drawable >= 0 and GetNumberOfPedPropTextureVariations(ped, category.id, drawable) or 0 }
    end

    return { drawables = GetNumberOfPedDrawableVariations(ped, category.id), textures = GetNumberOfPedTextureVariations(ped, category.id, drawable) }
end

---------------------------------------------------------------------
-- Caméra (devant le personnage, décalée pour laisser le panneau à gauche)
---------------------------------------------------------------------

local function setCamera(view, instant)
    local settings = Config.Cameras[view] or Config.Cameras.torso
    local anchor = shop.anchor
    shop.view = view

    local angle = math.rad(anchor.w)
    local forward = vector3(-math.sin(angle), math.cos(angle), 0.0)
    local right = vector3(math.cos(angle), math.sin(angle), 0.0)
    local halfWidth = settings.distance * math.tan(math.rad(settings.fov) / 2) * GetAspectRatio(false)
    local base = vector3(anchor.x, anchor.y, anchor.z) + right * (halfWidth * Config.CameraShift)
    local position = base + forward * settings.distance + vector3(0.0, 0.0, settings.height)

    local new = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', position.x, position.y, position.z, 0.0, 0.0, 0.0, settings.fov, false, 2)
    PointCamAtCoord(new, base.x, base.y, base.z + settings.height)

    if shop.cam and not instant then
        SetCamActiveWithInterp(new, shop.cam, 500, 1, 1)
        local old = shop.cam
        SetTimeout(600, function() DestroyCam(old, false) end)
    else
        if shop.cam then
            DestroyCam(shop.cam, false)
        end

        SetCamActive(new, true)
        RenderScriptCams(true, true, 400, true, true)
    end

    shop.cam = new
end

---------------------------------------------------------------------
-- Ouverture et fermeture
---------------------------------------------------------------------

local function groupsFor()
    local list = {}

    for _, group in ipairs(Config.Groups) do
        local categories = {}

        for _, category in ipairs(group.categories) do
            categories[#categories + 1] = { key = category.key, label = category.label, kind = category.kind, id = category.id, price = ClothingPrice(category.key) }
        end

        list[#list + 1] = { key = group.key, label = group.label, icon = group.icon, camera = group.camera, categories = categories }
    end

    return list
end

local function closeShop(restore)
    if not shop then
        return
    end

    local ped = PlayerPedId()

    if restore and shop.original then
        appearanceApi:setPedAppearance(ped, shop.original)
    end

    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)
    SetEntityHeading(ped, shop.anchor.w)
    RenderScriptCams(false, true, 400, true, true)

    if shop.cam then
        DestroyCam(shop.cam, false)
    end

    DisplayRadar(true)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    shop = nil
end

local function openShop(index, store)
    if shop then
        return
    end

    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) then
        return notify('Descendez du véhicule.', 'error')
    end

    pcall(lib.hideContext, false)

    if GetResourceState('ox_inventory') == 'started' then
        pcall(function() exports.ox_inventory:closeInventory() end)
    end

    ClearPedTasksImmediately(ped)
    local coords = GetEntityCoords(ped)
    shop = { index = index, store = store, original = appearanceApi:getPedAppearance(ped), anchor = vector4(coords.x, coords.y, coords.z, GetEntityHeading(ped)) }
    FreezeEntityPosition(ped, true)
    DisplayRadar(false)
    setCamera('torso', true)

    local brand = Config.Brands[store.brand] or Config.Brands.binco
    local images = (GlobalState.lunaticCreator or {}).clothesImages or Config.ClothesImages
    local pages = {}

    for _, page in ipairs(Config.Pages) do
        pages[page] = ClothingPageOn(store, page)
    end

    SendNUIMessage({ action = 'open', data = {
        store = store.label, brand = { label = brand.label, color = brand.color }, pages = pages,
        groups = groupsFor(), worn = wornAll(ped), sex = sexOf(ped), images = images, currency = GlobalState.lunaticCurrency or '$',
    } })
    SetNuiFocus(true, true)
end

---------------------------------------------------------------------
-- Interface
---------------------------------------------------------------------

RegisterNUICallback('counts', function(data, cb)
    local category = ClothingCategory(data.key)
    cb(category and counts(category, tonumber(data.drawable) or 0) or { drawables = 0, textures = 0 })
end)

RegisterNUICallback('apply', function(data, cb)
    local category = ClothingCategory(data.key)

    if shop and category then
        applyPiece(PlayerPedId(), category, math.floor(tonumber(data.drawable) or 0), math.floor(tonumber(data.texture) or 0))
    end

    cb({})
end)

RegisterNUICallback('camera', function(data, cb)
    if shop and Config.Cameras[data.view] and data.view ~= shop.view then
        setCamera(data.view, false)
    end

    cb({})
end)

RegisterNUICallback('rotate', function(data, cb)
    if shop then
        local ped = PlayerPedId()
        SetEntityHeading(ped, (GetEntityHeading(ped) + (tonumber(data.delta) or 0)) % 360)
    end

    cb({})
end)

RegisterNUICallback('armsUp', function(data, cb)
    cb({})
    local ped = PlayerPedId()

    if data.on ~= true then
        return ClearPedTasks(ped)
    end

    lib.requestAnimDict(Config.ArmsUp.dict)
    TaskPlayAnim(ped, Config.ArmsUp.dict, Config.ArmsUp.anim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
end)

-- Paiement : seules les pièces changées partent au serveur, qui recalcule le prix
RegisterNUICallback('buy', function(data, cb)
    if not shop then
        return cb({ ok = false })
    end

    local result = lib.callback.await('lunatic_clothing:buy', false, shop.index, type(data.changes) == 'table' and data.changes or {}, data.account)

    if not result or not result.ok then
        return cb({ ok = false, error = result and result.error or 'Paiement impossible.' })
    end

    cb({ ok = true })
    closeShop(false)

    if result.count > 0 then
        notify(result.total > 0 and ('Achat réglé : %d pièce%s pour %d %s.'):format(result.count, result.count > 1 and 's' or '', result.total, GlobalState.lunaticCurrency or '$')
            or 'Tenue enregistrée.', 'success')
    end
end)

RegisterNUICallback('close', function(_, cb)
    cb({})
    closeShop(true)
end)

---------------------------------------------------------------------
-- Marqueurs, [E] et blips
---------------------------------------------------------------------

local blips = {}

local function refreshBlips()
    for _, blip in ipairs(blips) do
        RemoveBlip(blip)
    end

    blips = {}

    for _, store in ipairs(ClothingStores()) do
        if store.blip then
            local brand = Config.Brands[store.brand] or Config.Brands.binco
            local blip = AddBlipForCoord(store.x, store.y, store.z)
            SetBlipSprite(blip, Config.Blip.sprite)
            SetBlipColour(blip, brand.blip)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(store.label)
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end
    end
end

CreateThread(refreshBlips)
AddStateBagChangeHandler('lunaticClothing', 'global', function()
    SetTimeout(500, refreshBlips)
end)

CreateThread(function()
    while true do
        local wait = 1000

        if not shop then
            local coords = GetEntityCoords(PlayerPedId())
            local color = Config.Marker

            for index, store in ipairs(ClothingStores()) do
                local distance = #(coords - vector3(store.x, store.y, store.z))

                if distance < 10.0 then
                    wait = 0
                    DrawMarker(1, store.x, store.y, store.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 0.8, 0.25, color[1], color[2], color[3], color[4], false, false, 2, false, nil, nil, false)

                    if distance <= Config.StoreDistance then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName(('~INPUT_CONTEXT~ %s'):format(store.label))
                        EndTextCommandDisplayHelp(0, false, true, -1)

                        if IsControlJustReleased(0, 38) then
                            openShop(index, store)
                        end
                    end
                end
            end
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        closeShop(true)

        for _, blip in ipairs(blips) do
            RemoveBlip(blip)
        end
    end
end)
