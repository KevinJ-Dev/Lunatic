-- Magasins de vêtements, côté client : zone de chaque magasin (rayon, marqueur, PNJ), essayage en direct (caméra
-- devant le personnage, bras levés, rotation), panier, prêt-à-porter, mes tenues et favoris (vérifiés par le serveur).
-- Quitter sans payer remet la tenue d'avant (illenium-appearance).
-- Repris de lunatic_creator : caméra décalée, nombre de modèles et de couleurs, bras levés.

local appearanceApi = exports['illenium-appearance']
local shop = nil -- magasin ouvert : { index, store, original, anchor, cam, view }
local favoritesTimer = nil

local function notify(text, kind)
    ESX.ShowNotification(text, kind or 'info')
end

local function currency()
    return GlobalState.lunaticCurrency or '$'
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

local function applyPieces(pieces)
    local ped = PlayerPedId()

    for key, piece in pairs(type(pieces) == 'table' and pieces or {}) do
        local category = ClothingCategory(key)

        if category and type(piece) == 'table' then
            applyPiece(ped, category, math.floor(tonumber(piece[1]) or 0), math.floor(tonumber(piece[2]) or 0))
        end
    end
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

local function setCamera(view, instant, override)
    local settings = override or Config.Cameras[view] or Config.Cameras.torso
    local anchor = shop.anchor
    shop.view = view

    local angle = math.rad(anchor.w)
    local forward = vector3(-math.sin(angle), math.cos(angle), 0.0)
    local right = vector3(math.cos(angle), math.sin(angle), 0.0)
    local halfWidth = settings.distance * math.tan(math.rad(settings.fov) / 2) * GetAspectRatio(false)
    local base = vector3(anchor.x, anchor.y, anchor.z) + right * (halfWidth * (override and 0.0 or shop.shift or Config.CameraShift))
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

-- Groupes et catégories vendus par l'enseigne (toutes pour la gestion du catalogue) ; price = prix dans l'enseigne,
-- base = prix par défaut de la catégorie
local function groupsFor(brand)
    local list = {}

    for _, group in ipairs(Config.Groups) do
        local categories = {}

        for _, category in ipairs(group.categories) do
            if not brand or ClothingBrandSells(brand, category.key) then
                local base = ClothingPrice(category.key)
                categories[#categories + 1] = {
                    key = category.key, label = category.label, kind = category.kind, id = category.id, base = base,
                    price = brand and ClothingBrandPrice(brand, base) or base,
                }
            end
        end

        if #categories > 0 then
            list[#list + 1] = { key = group.key, label = group.label, icon = group.icon, camera = group.camera, categories = categories }
        end
    end

    return list
end

-- Fiches des pièces (nom, prix, image, bannie), gardées tant que le catalogue ne change pas
local catalogueCache = { version = nil }

local function catalogueFor(sex)
    local version = GlobalState.lunaticClothingVersion

    if catalogueCache.version ~= version then
        catalogueCache = { version = version }
    end

    if not catalogueCache[sex] then
        local result = lib.callback.await('lunatic_clothing:catalogue', false, sex)
        catalogueCache[sex] = result and result.items or {}
    end

    return catalogueCache[sex]
end

-- Image de bannière : lien direct, ou clé de la tuile Images du panel
local function bannerImage(value)
    if type(value) ~= 'string' or value == '' then
        return nil
    end

    if value:match('^https?://') or value:match('^nui://') then
        return value
    end

    return (GlobalState.lunaticImages or {})[value]
end

-- Tenues prêt-à-porter de cette enseigne pour ce sexe
local function readyFor(brand, sex)
    local list = {}

    for _, outfit in ipairs(ClothingReady()) do
        if outfit.sex == sex and ClothingReadyIn(outfit, brand) then
            list[#list + 1] = { id = outfit.id, label = outfit.label, price = outfit.price, pieces = outfit.pieces }
        end
    end

    return list
end

local function closeShop(restore)
    if not shop then
        return
    end

    local ped = PlayerPedId()

    -- Gestion du catalogue : le modèle a pu changer (homme / femme), on remet toute l'apparence
    if shop.mode == 'tool' then
        appearanceApi:setPlayerAppearance(shop.original)
        ped = PlayerPedId()
        TriggerServerEvent('lunatic_clothing:catalogueClosed')
    elseif restore and shop.original then
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

    local profile = lib.callback.await('lunatic_clothing:profile', false) or { outfits = {}, favorites = {}, max = 0 }

    pcall(lib.hideContext, false)

    if GetResourceState('ox_inventory') == 'started' then
        pcall(function() exports.ox_inventory:closeInventory() end)
    end

    ClearPedTasksImmediately(ped)
    local coords = GetEntityCoords(ped)
    shop = {
        mode = 'shop', index = index, store = store, original = appearanceApi:getPedAppearance(ped), anchor = vector4(coords.x, coords.y, coords.z, GetEntityHeading(ped)),
        favorites = type(profile.favorites) == 'table' and profile.favorites or {},
    }
    FreezeEntityPosition(ped, true)
    DisplayRadar(false)
    setCamera('torso', true)

    local brand = ClothingBrand(store.brand)
    local sex = sexOf(ped)
    local items = catalogueFor(sex)
    local pages = {}

    for _, page in ipairs(Config.Pages) do
        pages[page] = ClothingPageOn(store, page)
    end

    SendNUIMessage({ action = 'open', data = {
        store = store.label, brand = { label = brand.label, color = brand.color, image = bannerImage(brand.image), showText = brand.showText ~= false },
        pages = pages, groups = groupsFor(brand), worn = wornAll(ped), sex = sex, currency = currency(), items = items, coef = tonumber(brand.coef) or 1.0,
        images = (GlobalState.lunaticCreator or {}).clothesImages or Config.ClothesImages,
        ready = readyFor(brand.key, sex), outfits = profile.outfits or {}, maxOutfits = profile.max or 0,
        favorites = type(profile.favorites) == 'table' and profile.favorites[sex] or {},
    } })
    SetNuiFocus(true, true)
end

-- Après un achat ou une tenue remise : la nouvelle tenue devient celle à remettre en quittant
local function settle(pieces)
    applyPieces(pieces)
    shop.original = appearanceApi:getPedAppearance(PlayerPedId())
    return wornAll(PlayerPedId())
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

-- Essayage d'une tenue entière (prêt-à-porter)
RegisterNUICallback('tryPieces', function(data, cb)
    if shop then
        applyPieces(data.pieces)
    end

    cb({ worn = shop and wornAll(PlayerPedId()) or {} })
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

-- Panier : seules les pièces changées partent au serveur, qui recalcule le prix
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
        notify(result.total > 0 and ('Achat réglé : %d pièce%s pour %d %s.'):format(result.count, result.count > 1 and 's' or '', result.total, currency())
            or 'Tenue enregistrée.', 'success')
    end
end)

RegisterNUICallback('buyReady', function(data, cb)
    if not shop then
        return cb({ ok = false })
    end

    local result = lib.callback.await('lunatic_clothing:buyReady', false, shop.index, data.id, data.account)

    if not result or not result.ok then
        return cb({ ok = false, error = result and result.error or 'Paiement impossible.' })
    end

    notify(result.price > 0 and ('Tenue achetée : %d %s.'):format(result.price, currency()) or 'Tenue enregistrée.', 'success')
    cb({ ok = true, worn = settle(result.pieces) })
end)

RegisterNUICallback('saveOutfit', function(data, cb)
    cb(shop and lib.callback.await('lunatic_clothing:saveOutfit', false, shop.index, data.label) or { ok = false })
end)

RegisterNUICallback('wearOutfit', function(data, cb)
    if not shop then
        return cb({ ok = false })
    end

    local result = lib.callback.await('lunatic_clothing:wearOutfit', false, shop.index, data.id)

    if not result or not result.ok then
        return cb({ ok = false, error = result and result.error or 'Tenue indisponible.' })
    end

    cb({ ok = true, worn = settle(result.pieces) })
end)

RegisterNUICallback('renameOutfit', function(data, cb)
    cb(lib.callback.await('lunatic_clothing:renameOutfit', false, data.id, data.label) or { ok = false })
end)

RegisterNUICallback('deleteOutfit', function(data, cb)
    cb(lib.callback.await('lunatic_clothing:deleteOutfit', false, data.id) or { ok = false })
end)

-- Favoris : enregistrés une seconde après le dernier changement (liste du sexe porté, l'autre est gardée)
RegisterNUICallback('favorites', function(data, cb)
    cb({})

    if not shop or type(data.list) ~= 'table' then
        return
    end

    local favorites = shop.favorites
    favorites[sexOf(PlayerPedId())] = data.list

    if favoritesTimer then
        return
    end

    favoritesTimer = true
    SetTimeout(1200, function()
        favoritesTimer = nil
        TriggerServerEvent('lunatic_clothing:favorites', favorites)
    end)
end)

RegisterNUICallback('close', function(_, cb)
    cb({})
    closeShop(true)
end)

-- Panel staff (Prêt-à-porter) : tenue portée par le staff
lib.callback.register('lunatic_clothing:capture', function()
    local ped = PlayerPedId()
    return { sex = sexOf(ped), pieces = wornAll(ped) }
end)

---------------------------------------------------------------------
-- Gestion du catalogue (staff, ouverte depuis le panel) : fiche de chaque pièce, prix par défaut, photo
---------------------------------------------------------------------

local MODELS = { male = `mp_m_freemode_01`, female = `mp_f_freemode_01` }
local captureReply = nil  -- réponse du serveur après une photo
local cropReply = nil     -- image recadrée par la page

local function toolData(sex, screenshot)
    return {
        sex = sex, groups = groupsFor(nil), items = catalogueFor(sex), worn = wornAll(PlayerPedId()), currency = currency(),
        images = (GlobalState.lunaticCreator or {}).clothesImages or Config.ClothesImages, screenshot = screenshot,
    }
end

RegisterNetEvent('lunatic_clothing:catalogueTool', function(screenshot)
    if shop then
        return
    end

    TriggerEvent('lunatic_admin:closePanel')
    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) then
        TriggerServerEvent('lunatic_clothing:catalogueClosed')
        return notify('Descendez du véhicule pour gérer le catalogue.', 'error')
    end

    ClearPedTasksImmediately(ped)
    local coords = GetEntityCoords(ped)
    shop = { mode = 'tool', shift = 0.0, screenshot = screenshot == true, original = appearanceApi:getPedAppearance(ped), anchor = vector4(coords.x, coords.y, coords.z, GetEntityHeading(ped)) }
    FreezeEntityPosition(ped, true)
    DisplayRadar(false)
    setCamera('torso', true)
    SendNUIMessage({ action = 'tool', data = toolData(sexOf(ped), shop.screenshot) })
    SetNuiFocus(true, true)
end)

-- Homme / femme : le personnage change de modèle le temps de la gestion
RegisterNUICallback('toolSex', function(data, cb)
    if not shop or shop.mode ~= 'tool' then
        return cb({})
    end

    local sex = data.sex == 'female' and 'female' or 'male'

    if sexOf(PlayerPedId()) ~= sex then
        appearanceApi:setPlayerModel(MODELS[sex])
        local ped = PlayerPedId()
        SetEntityCoords(ped, shop.anchor.x, shop.anchor.y, shop.anchor.z - 0.98, false, false, false, false)
        SetEntityHeading(ped, shop.anchor.w)
        FreezeEntityPosition(ped, true)
    end

    cb(toolData(sex, shop.screenshot))
end)

RegisterNUICallback('saveItem', function(data, cb)
    if not shop or shop.mode ~= 'tool' then
        return cb({ ok = false })
    end

    local result = lib.callback.await('lunatic_clothing:saveItem', false, sexOf(PlayerPedId()), data.key, data.drawable, data.item)
    cb(result or { ok = false, error = 'Enregistrement impossible.' })
end)

RegisterNUICallback('setDefaultPrice', function(data, cb)
    if not shop or shop.mode ~= 'tool' then
        return cb({ ok = false })
    end

    cb(lib.callback.await('lunatic_clothing:setDefaultPrice', false, data.key, data.price) or { ok = false })
end)

RegisterNUICallback('cropped', function(data, cb)
    cb({})
    cropReply = type(data) == 'table' and data or { error = 'réponse vide' }
end)

RegisterNetEvent('lunatic_clothing:captured', function(ok, path)
    captureReply = { ok = ok == true, path = path }
end)

local function waitFor(getter, ms)
    local timeout = GetGameTimer() + ms

    while not getter() and GetGameTimer() < timeout do
        Wait(20)
    end

    return getter()
end

-- Photo de la pièce portée : interface cachée, caméra cadrée sur la pièce, capture, recadrage par la page, envoi
RegisterNUICallback('capture', function(data, cb)
    if not shop or shop.mode ~= 'tool' or not shop.screenshot or GetResourceState('screenshot-basic') ~= 'started' then
        return cb({ ok = false, error = 'screenshot-basic ne tourne pas sur le serveur.' })
    end

    local view = Config.Capture.cameras[data.view] and data.view or 'torso'
    local previous = shop.view
    SendNUIMessage({ action = 'toolHide', hidden = true })
    setCamera(view, true, Config.Capture.cameras[view])
    Wait(450)

    local shot = promise.new()
    exports['screenshot-basic']:requestScreenshot({ encoding = 'webp', quality = 0.95 }, function(image)
        shot:resolve(image)
    end)
    local image = Citizen.Await(shot)

    cropReply = nil
    SendNUIMessage({ action = 'crop', image = image, size = Config.Capture.size, crop = Config.Capture.crop, quality = Config.Capture.quality })
    local cropped = waitFor(function() return cropReply end, 5000)

    setCamera(previous or 'torso', true)
    SendNUIMessage({ action = 'toolHide', hidden = false })

    if not cropped or type(cropped.image) ~= 'string' then
        return cb({ ok = false, error = 'Recadrage impossible.' })
    end

    captureReply = nil
    TriggerLatentServerEvent('lunatic_clothing:photo', 200000, sexOf(PlayerPedId()), data.key, data.drawable, cropped.image)
    local reply = waitFor(function() return captureReply end, 15000)

    if not reply or not reply.ok then
        return cb({ ok = false, error = "Photo refusée par le serveur." })
    end

    cb({ ok = true, path = reply.path, preview = cropped.image })
end)

---------------------------------------------------------------------
-- Zones des magasins : marqueur, PNJ, [E] et blips
---------------------------------------------------------------------

local blips, peds = {}, {}

local function refreshStores()
    for _, blip in ipairs(blips) do
        RemoveBlip(blip)
    end

    for _, ped in ipairs(peds) do
        DeleteEntity(ped)
    end

    blips, peds = {}, {}

    for _, store in ipairs(ClothingStores()) do
        if store.blip then
            local brand = ClothingBrand(store.brand)
            local blip = AddBlipForCoord(store.x, store.y, store.z)
            SetBlipSprite(blip, Config.Blip.sprite)
            SetBlipColour(blip, tonumber(brand.blip) or 0)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(store.label)
            EndTextCommandSetBlipName(blip)
            blips[#blips + 1] = blip
        end

        local model = store.ped ~= '' and joaat(store.ped)

        if model and IsModelInCdimage(model) and lib.requestModel(model, 5000) then
            local ped = CreatePed(4, model, store.x, store.y, store.z - 1.0, (store.h or 0.0) + 0.0, false, false)
            SetModelAsNoLongerNeeded(model)
            FreezeEntityPosition(ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            peds[#peds + 1] = ped
        end
    end
end

CreateThread(refreshStores)
AddStateBagChangeHandler('lunaticClothing', 'global', function()
    SetTimeout(500, refreshStores)
end)

CreateThread(function()
    while true do
        local wait = 1000

        if not shop then
            local coords = GetEntityCoords(PlayerPedId())
            local color = Config.Marker

            for index, store in ipairs(ClothingStores()) do
                local distance = #(coords - vector3(store.x, store.y, store.z))

                if distance < store.radius + 10.0 then
                    wait = 0

                    -- Marqueur à la taille de la zone (petit point ou tout le magasin)
                    if store.marker then
                        local size = math.min(store.radius * 2.0, 30.0)
                        DrawMarker(1, store.x, store.y, store.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, 0.25, color[1], color[2], color[3], color[4], false, false, 2, false, nil, nil, false)
                    end

                    if distance <= store.radius then
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

        for _, ped in ipairs(peds) do
            DeleteEntity(ped)
        end
    end
end)
