-- Magasins de vêtements et barbiers, côté client : zone de chaque magasin (rayon, marqueur, PNJ), essayage en direct
-- (caméra devant le personnage, bras levés, rotation), panier, prêt-à-porter, mes tenues et favoris (vérifiés par le serveur).
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
    -- Tatouages : lus dans l'apparence (le jeu ne les rend pas), voir tattooWorn
    if category.kind == 'tattoo' then
        return nil
    end

    -- Coupe : { modèle, variante, couleur, reflets } ; calque du visage : { style, opacité 0-10, couleur }
    if category.kind == 'hair' then
        return { GetPedDrawableVariation(ped, 2), GetPedTextureVariation(ped, 2), GetPedHairColor(ped), GetPedHairHighlightColor(ped) }
    end

    if category.kind == 'overlay' then
        local _, value, _, color, _, opacity = GetPedHeadOverlayData(ped, category.id)

        if value == 255 then
            return { 0, 0, color }
        end

        return { value, math.floor(opacity * 10 + 0.5), color }
    end

    if category.kind == 'prop' then
        local drawable = GetPedPropIndex(ped, category.id)
        return { drawable, drawable >= 0 and GetPedPropTextureIndex(ped, category.id) or 0 }
    end

    return { GetPedDrawableVariation(ped, category.id), GetPedTextureVariation(ped, category.id) }
end

local function wornAll(ped, kind)
    local worn = {}

    for _, group in ipairs(ClothingGroupsOf(kind)) do
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

-- Pièce complète (coupe et calques du visage compris)
local function applyValue(ped, category, value)
    if category.kind == 'hair' then
        SetPedComponentVariation(ped, 2, value[1], value[2], 0)
        SetPedHairColor(ped, value[3], value[4])
    elseif category.kind == 'overlay' then
        local opacity = value[2] / 10
        SetPedHeadOverlay(ped, category.id, opacity > 0 and value[1] or 255, opacity + 0.0)
        SetPedHeadOverlayColor(ped, category.id, category.palette == 'makeup' and 2 or 1, value[3], value[3])
    else
        applyPiece(ped, category, value[1], value[2])
    end
end

-- Nuancier des cheveux du jeu (couleurs et reflets, barbe, sourcils)
local function hairColors()
    local list = {}

    for index = 0, GetNumHairColors() - 1 do
        local r, g, b = GetPedHairRgbColor(index)
        list[#list + 1] = ('#%02x%02x%02x'):format(r, g, b)
    end

    return list
end

-- Tatouages portés (table illenium : zone -> liste) remis sur le personnage, comme illenium-appearance (opacité = passes)
local function applyTattoos(ped, tattoos)
    local female = sexOf(ped) == 'female'
    ClearPedDecorations(ped)

    for _, list in pairs(type(tattoos) == 'table' and tattoos or {}) do
        for _, tattoo in ipairs(type(list) == 'table' and list or {}) do
            local hash = type(tattoo) == 'table' and (female and tattoo.hashFemale or tattoo.hashMale)

            if type(hash) == 'string' and hash ~= '' and type(tattoo.collection) == 'string' then
                for _ = 1, math.max(1, math.floor((tonumber(tattoo.opacity) or 0.1) * 10 + 0.5)) do
                    AddPedDecorationFromHashes(ped, joaat(tattoo.collection), joaat(hash))
                end
            end
        end
    end
end

-- Noms des tatouages portés par catégorie (zone) du salon
local function tattooWorn(groups, tattoos)
    local worn = {}

    for _, group in ipairs(groups) do
        for _, category in ipairs(group.categories) do
            local names = {}

            for _, tattoo in ipairs(type(tattoos[category.zone]) == 'table' and tattoos[category.zone] or {}) do
                if type(tattoo) == 'table' and tattoo.name then
                    names[#names + 1] = tattoo.name
                end
            end

            worn[category.key] = names
        end
    end

    return worn
end

-- Tatouages proposés par catégorie (zone) : ceux qui existent pour ce sexe, { name, label }
local function tattoosFor(groups, sex)
    local lists = {}

    for _, group in ipairs(groups) do
        for _, category in ipairs(group.categories) do
            local list = {}

            for _, tattoo in ipairs(ClothingTattoos()[category.zone] or {}) do
                local hash = sex == 'female' and tattoo.hashFemale or tattoo.hashMale

                if type(hash) == 'string' and hash ~= '' then
                    list[#list + 1] = { name = tattoo.name, label = tattoo.label }
                end
            end

            lists[category.key] = list
        end
    end

    return lists
end

-- Nuancier du maquillage (maquillage, blush, rouge à lèvres)
local function makeupColors()
    local list = {}

    for index = 0, GetNumMakeupColors() - 1 do
        local r, g, b = GetMakeupRgbColor(index)
        list[#list + 1] = ('#%02x%02x%02x'):format(r, g, b)
    end

    return list
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

    if category.kind == 'overlay' then
        return { drawables = GetPedHeadOverlayNum(category.id), textures = 0 }
    end

    if category.kind == 'prop' then
        return { drawables = GetNumberOfPedPropDrawableVariations(ped, category.id), textures = drawable >= 0 and GetNumberOfPedPropTextureVariations(ped, category.id, drawable) or 0 }
    end

    return { drawables = GetNumberOfPedDrawableVariations(ped, category.id), textures = GetNumberOfPedTextureVariations(ped, category.id, drawable) }
end

---------------------------------------------------------------------
-- Caméra (devant le personnage, décalée pour laisser le panneau à gauche)
---------------------------------------------------------------------

-- Pose d'une vue (poignet levé pour les montres) : dans la gestion du catalogue, la boucle de pose figée la prend ;
-- en magasin, l'animation est jouée tant que la vue est active
local function setViewPose(name)
    local pose = name and Config.Poses[name] or nil

    if shop.mode == 'tool' then
        shop.pose = pose
        return
    end

    local ped = PlayerPedId()

    if pose then
        if pcall(lib.requestAnimDict, pose.dict, 3000) then
            TaskPlayAnim(ped, pose.dict, pose.anim, 4.0, -4.0, -1, 1, 0.0, false, false, false)
        end
    elseif shop.viewPose then
        ClearPedTasks(ped)
    end

    shop.viewPose = pose
end

-- Os visé par une vue (poignet) : lu une fois la pose de la vue en place ; nil si la caméra a changé entre-temps
local function boneTarget(settings, token)
    local ped = PlayerPedId()
    local pose = settings.pose and Config.Poses[settings.pose]

    if pose then
        local timeout = GetGameTimer() + 1500

        while not IsEntityPlayingAnim(ped, pose.dict, pose.anim, 3) and GetGameTimer() < timeout do
            Wait(50)
        end
    end

    -- Fin du fondu vers la pose (ou du retour des bras le long du corps)
    Wait(450)

    if not shop or shop.cameraToken ~= token then
        return nil
    end

    return GetPedBoneCoords(PlayerPedId(), settings.bone, 0.0, 0.0, 0.0)
end

local function setCamera(view, instant, override)
    local settings = override or Config.Cameras[view] or Config.Cameras.torso
    local anchor = shop.anchor
    shop.view = view
    shop.cameraToken = (shop.cameraToken or 0) + 1
    local token = shop.cameraToken
    setViewPose(settings.pose)

    -- Caméra face au personnage, tournée autour de lui (angle), décalée sur son côté (side) puis vers la droite de
    -- l'écran pour laisser le panneau à gauche
    local angle = math.rad(anchor.w)
    local forward = vector3(-math.sin(angle), math.cos(angle), 0.0)
    local right = vector3(math.cos(angle), math.sin(angle), 0.0)
    local orbit = math.rad(settings.angle or 0.0)
    local direction = forward * math.cos(orbit) + right * math.sin(orbit)
    -- Gauche de l'écran vue de la caméra (= droite du personnage quand la caméra est en face)
    local screenLeft = vector3(direction.y, -direction.x, 0.0)
    local halfWidth = settings.distance * math.tan(math.rad(settings.fov) / 2) * GetAspectRatio(false)
    local shift = screenLeft * (halfWidth * (override and 0.0 or shop.shift or Config.CameraShift))
    local target, position

    if settings.bone then
        local bone = boneTarget(settings, token)

        if not bone then
            return
        end

        target = bone + shift
        position = target + direction * settings.distance + vector3(0.0, 0.0, settings.height or 0.0)
    else
        target = vector3(anchor.x, anchor.y, anchor.z + settings.height) + right * (settings.side or 0.0) + shift
        position = target + direction * settings.distance
    end

    local new = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', position.x, position.y, position.z, 0.0, 0.0, 0.0, settings.fov, false, 2)
    PointCamAtCoord(new, target.x, target.y, target.z)

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
-- Enseigne « une catégorie par bouton » (bijouterie) : chaque catégorie devient son propre groupe dans la barre
local function groupsFor(brand)
    local list = {}

    for _, group in ipairs(ClothingGroupsOf(brand and ClothingBrandKind(brand) or 'clothing')) do
        local categories = {}

        for _, category in ipairs(group.categories) do
            if not brand or ClothingBrandSells(brand, category.key) then
                local base = ClothingPrice(category.key)
                local entry = {
                    key = category.key, label = category.label, kind = category.kind, id = category.id, base = base,
                    price = brand and ClothingBrandPrice(brand, base) or base, camera = category.camera, undress = category.undress, palette = category.palette, zone = category.zone,
                }

                if brand and brand.flat then
                    list[#list + 1] = { key = category.key, label = category.label, icon = category.icon or group.icon, camera = category.camera or group.camera, categories = { entry } }
                else
                    categories[#categories + 1] = entry
                end
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
local catalogueWaiting = {} -- sexe -> promesse en attente de la réponse du serveur

local function catalogueFor(sex)
    local version = GlobalState.lunaticClothingVersion

    if catalogueCache.version ~= version then
        catalogueCache = { version = version }
    end

    if not catalogueCache[sex] then
        local waiting = promise.new()
        catalogueWaiting[sex] = waiting
        TriggerServerEvent('lunatic_clothing:catalogue', sex)
        SetTimeout(15000, function()
            if catalogueWaiting[sex] == waiting then
                catalogueWaiting[sex] = nil
                waiting:resolve(nil)
            end
        end)
        local items = Citizen.Await(waiting)
        catalogueWaiting[sex] = nil
        catalogueCache[sex] = type(items) == 'table' and items or {}
    end

    return catalogueCache[sex]
end

RegisterNetEvent('lunatic_clothing:catalogue', function(sex, items)
    local waiting = catalogueWaiting[sex]

    if waiting then
        catalogueWaiting[sex] = nil
        waiting:resolve(items or {})
    end
end)

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

-- HUD des autres scripts (novyra_hud, esx_status) masqué en magasin et pendant la gestion (repris de lunatic_creator)
local function setHud(visible)
    if GetResourceState('novyra_hud') == 'started' then
        pcall(function() exports.novyra_hud:setVisible(visible) end)
    end

    TriggerEvent('esx_status:setDisplay', visible and 0.5 or 0.0)
    DisplayRadar(visible)
end

-- Retirer / remettre (boutons du magasin) : pièces enlevées pour la vue seulement (shop.hidden = pièce à remettre par
-- catégorie), remises avant tout achat, tenue remise ou sortie
local function undressedPiece(ped, category)
    if category.kind == 'prop' then
        return -1
    end

    return (Config.Capture.base[sexOf(ped)] or {})[category.id] or 0
end

local function restoreHidden(keys)
    if not shop or not shop.hidden then
        return
    end

    local ped = PlayerPedId()

    for _, key in ipairs(keys or {}) do
        local piece = shop.hidden[key]
        local category = ClothingCategory(key)

        if piece and category then
            applyPiece(ped, category, piece[1], piece[2])
        end

        shop.hidden[key] = nil
    end

    if not keys then
        for key, piece in pairs(shop.hidden) do
            local category = ClothingCategory(key)

            if category then
                applyPiece(ped, category, piece[1], piece[2])
            end
        end

        shop.hidden = {}
    end
end

local function undressEntry(key)
    for _, entry in ipairs(Config.Undress) do
        if entry.key == key then
            return entry
        end
    end
end

local function closeShop(restore)
    if not shop then
        return
    end

    if shop.mode ~= 'tool' then
        restoreHidden()
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

    setHud(true)
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
        favorites = type(profile.favorites) == 'table' and profile.favorites or {}, hidden = {},
    }
    FreezeEntityPosition(ped, true)
    setHud(false)
    setCamera('torso', true)

    local brand = ClothingBrand(store.brand)
    local kind = ClothingBrandKind(brand)
    local sex = sexOf(ped)
    local items = catalogueFor(sex)
    local pages = {}

    -- Barbier et salon de tatouage : catalogue seulement
    for _, page in ipairs(Config.Pages) do
        pages[page] = kind ~= 'clothing' and page == 'catalogue' or (kind == 'clothing' and ClothingPageOn(store, page))
    end

    local groups = groupsFor(brand)
    local worn = wornAll(ped, kind)

    -- Salon de tatouage : tatouages de l'apparence, modifiés en direct pendant l'essai
    if kind == 'tattoo' then
        shop.tattoos = json.decode(json.encode(type(shop.original.tattoos) == 'table' and shop.original.tattoos or {}))
        worn = tattooWorn(groups, shop.tattoos)
    end

    local undress = kind == 'barber' and Config.BarberUndress or kind == 'tattoo' and Config.TattooUndress or nil

    SendNUIMessage({ action = 'open', data = {
        store = store.label, brand = { label = brand.label, color = brand.color, textColor = brand.textColor, image = bannerImage(brand.image), showText = brand.showText ~= false },
        kind = kind, pages = pages, groups = groups, worn = worn, sex = sex, currency = currency(), items = items, coef = tonumber(brand.coef) or 1.0,
        hairColors = kind == 'barber' and hairColors() or nil, makeupColors = kind == 'barber' and makeupColors() or nil, autoUndress = undress,
        tattoos = kind == 'tattoo' and tattoosFor(groups, sex) or nil, tattooMax = Config.TattooMax,
        images = (GlobalState.lunaticCreator or {}).clothesImages or Config.ClothesImages, renderer = Config.RendererImages,
        ready = readyFor(brand.key, sex), outfits = profile.outfits or {}, maxOutfits = profile.max or 0,
        favorites = type(profile.favorites) == 'table' and profile.favorites[sex] or {},
        undress = Config.Undress,
    } })
    SetNuiFocus(true, true)
end

-- Après un achat ou une tenue remise : la nouvelle tenue devient celle à remettre en quittant
local function settle(pieces)
    restoreHidden()
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
        -- Pièce choisie : elle n'est plus retirée
        if shop.hidden then
            shop.hidden[category.key] = nil
        end

        if (category.kind == 'hair' or category.kind == 'overlay') and type(data.value) == 'table' then
            local value = {}

            for index = 1, category.kind == 'hair' and 4 or 3 do
                value[index] = math.max(0, math.floor(tonumber(data.value[index]) or 0))
            end

            applyValue(PlayerPedId(), category, value)
        else
            applyPiece(PlayerPedId(), category, math.floor(tonumber(data.drawable) or 0), math.floor(tonumber(data.texture) or 0))
        end
    end

    cb({})
end)

-- Essai des tatouages d'une zone (liste de noms) : remis aussitôt sur le personnage
RegisterNUICallback('tattoos', function(data, cb)
    cb({})
    local category = ClothingCategory(data.key)

    if not shop or not shop.tattoos or not category or category.kind ~= 'tattoo' or type(data.names) ~= 'table' then
        return
    end

    local current, list = {}, {}

    for _, tattoo in ipairs(shop.tattoos[category.zone] or {}) do
        current[tattoo.name] = tattoo
    end

    for _, name in ipairs(data.names) do
        local tattoo = current[name] or ClothingTattoo(category.zone, name)

        if tattoo and #list < Config.TattooMax then
            list[#list + 1] = tattoo
        end
    end

    shop.tattoos[category.zone] = list
    applyTattoos(PlayerPedId(), shop.tattoos)
end)

RegisterNUICallback('undress', function(data, cb)
    local entry = shop and shop.mode == 'shop' and undressEntry(data.key)

    if not entry then
        return cb({})
    end

    if data.on ~= true then
        restoreHidden(entry.categories)
        return cb({})
    end

    local ped = PlayerPedId()

    for _, key in ipairs(entry.categories) do
        local category = ClothingCategory(key)

        if category and not shop.hidden[key] then
            shop.hidden[key] = wornPiece(ped, category)
            applyPiece(ped, category, undressedPiece(ped, category), 0)
        end
    end

    cb({})
end)

-- Photo prise depuis le démarrage de la ressource, pas encore dans ses fichiers : demandée au serveur, une à la fois
-- (réponse en événement latent ; plusieurs demandes de la même image n'en font qu'une)
local imageWaiting, imageQueue, imageCurrent = {}, {}, nil

local function imageDone(path, uri)
    for _, cb in ipairs(imageWaiting[path] or {}) do
        cb({ uri = uri or nil })
    end

    imageWaiting[path] = nil

    if imageCurrent == path then
        imageCurrent = nil
    end
end

local function imageNext()
    if imageCurrent or #imageQueue == 0 then
        return
    end

    local path = table.remove(imageQueue, 1)
    imageCurrent = path
    TriggerServerEvent('lunatic_clothing:image', path)

    SetTimeout(20000, function()
        if imageCurrent == path then
            imageDone(path, nil)
            imageNext()
        end
    end)
end

RegisterNetEvent('lunatic_clothing:image', function(path, uri)
    if imageWaiting[path] then
        imageDone(path, uri ~= false and uri or nil)
    end

    imageNext()
end)

RegisterNUICallback('image', function(data, cb)
    local path = data.path

    if type(path) ~= 'string' or not path:match('^clothes/[%w_%-]+%.webp$') then
        return cb({})
    end

    if imageWaiting[path] then
        table.insert(imageWaiting[path], cb)
        return
    end

    imageWaiting[path] = { cb }
    imageQueue[#imageQueue + 1] = path
    imageNext()
end)

-- Essayage d'une tenue entière (prêt-à-porter)
RegisterNUICallback('tryPieces', function(data, cb)
    if shop then
        restoreHidden()
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

    -- Tatouages achetés : illenium-appearance les garde aussi (sinon ils disparaîtraient à la prochaine apparence remise)
    if shop.tattoos then
        pcall(function() appearanceApi:setPedTattoos(PlayerPedId(), shop.tattoos) end)
    end

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
        images = (GlobalState.lunaticCreator or {}).clothesImages or Config.ClothesImages, renderer = Config.RendererImages, screenshot = screenshot,
    }
end

-- Personnage de base de FiveM (héritage par défaut, sans pilosité ni maquillage, cheveux courts) en tenue de base,
-- figé face à la caméra
local function baseCharacter(sex)
    if sexOf(PlayerPedId()) ~= sex then
        appearanceApi:setPlayerModel(MODELS[sex])
    end

    local ped = PlayerPedId()
    local look = Config.Capture.character[sex]
    SetPedHeadBlendData(ped, look.father, look.mother, 0, look.father, look.mother, 0, look.shape + 0.0, look.skin + 0.0, 0.0, false)

    for index = 0, 12 do
        SetPedHeadOverlay(ped, index, 255, 0.0)
    end

    for index = 0, 19 do
        SetPedFaceFeature(ped, index, 0.0)
    end

    SetPedHairColor(ped, 0, 0)
    SetPedEyeColor(ped, 0)

    for component, drawable in pairs(Config.Capture.base[sex] or {}) do
        SetPedComponentVariation(ped, component, drawable, 0, 0)
    end

    ClearAllPedProps(ped)
    SetEntityCoords(ped, shop.anchor.x, shop.anchor.y, shop.anchor.z - 0.98, false, false, false, false)
    SetEntityHeading(ped, shop.anchor.w)
    FreezeEntityPosition(ped, true)
end

-- Pose figée tant que la gestion est ouverte : l'animation est relancée si besoin et arrêtée à chaque image
local function holdPose()
    CreateThread(function()
        while shop and shop.mode == 'tool' do
            local ped = PlayerPedId()
            local pose = shop.pose or Config.Capture.pose[sexOf(ped)]

            if not IsEntityPlayingAnim(ped, pose.dict, pose.anim, 3) then
                -- Animation absente du jeu : pas de pose, la gestion continue
                local loaded = pcall(lib.requestAnimDict, pose.dict, 3000)

                if loaded then
                    TaskPlayAnim(ped, pose.dict, pose.anim, 1000.0, -1000.0, -1, 1, pose.time or 0.0, false, false, false)
                    Wait(50)
                    SetEntityAnimCurrentTime(ped, pose.dict, pose.anim, pose.time or 0.0)
                end

                Wait(loaded and 200 or 2000)
            end

            SetEntityAnimSpeed(ped, pose.dict, pose.anim, 0.0)
            Wait(0)
        end

        ClearPedTasks(PlayerPedId())
    end)
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
    setHud(false)
    baseCharacter(sexOf(ped))
    holdPose()
    setCamera('torso', true)
    SendNUIMessage({ action = 'tool', data = toolData(sexOf(PlayerPedId()), shop.screenshot) })
    SetNuiFocus(true, true)
end)

-- Homme / femme : le personnage change de modèle le temps de la gestion
RegisterNUICallback('toolSex', function(data, cb)
    if not shop or shop.mode ~= 'tool' then
        return cb({})
    end

    local sex = data.sex == 'female' and 'female' or 'male'

    if sexOf(PlayerPedId()) ~= sex then
        baseCharacter(sex)
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

-- Écran vert (dessiné à chaque image tant que des photos sont en cours) : un mur derrière le personnage et le sol,
-- détourés ensuite par la page pour un fond transparent
local greenScreen = false

local function quad(a, b, c, d)
    for _, tri in ipairs({ { a, b, c }, { a, c, b }, { a, c, d }, { a, d, c } }) do
        DrawPoly(tri[1].x, tri[1].y, tri[1].z, tri[2].x, tri[2].y, tri[2].z, tri[3].x, tri[3].y, tri[3].z, 0, 255, 0, 255)
    end
end

local function startGreenScreen()
    if greenScreen then
        return
    end

    greenScreen = true

    CreateThread(function()
        while greenScreen and shop do
            local anchor = shop.anchor
            local angle = math.rad(anchor.w)
            local forward = vector3(-math.sin(angle), math.cos(angle), 0.0)
            local right = vector3(math.cos(angle), math.sin(angle), 0.0)
            local center = vector3(anchor.x, anchor.y, anchor.z)
            local back = center - forward * Config.Capture.behind
            local floor = anchor.z - 0.97
            local up = vector3(0.0, 0.0, 1.0)
            local bottom = vector3(back.x, back.y, floor)
            local near = vector3(center.x, center.y, floor) + forward * 4.0

            quad(bottom - right * 5.0, bottom + right * 5.0, bottom + right * 5.0 + up * 4.0, bottom - right * 5.0 + up * 4.0)
            quad(bottom - right * 5.0, bottom + right * 5.0, near + right * 5.0, near - right * 5.0)
            Wait(0)
        end

        greenScreen = false
    end)
end

-- Tenue de base des photos : la pièce photographiée est portée seule
local function photoBase(ped, sex)
    for component, drawable in pairs(Config.Capture.base[sex] or {}) do
        SetPedComponentVariation(ped, component, drawable, 0, 0)
    end

    ClearAllPedProps(ped)
end

-- Pièce chargée avant d'être mise (sinon la photo partirait avec l'ancienne)
local function wearForPhoto(ped, category, drawable)
    if category.kind == 'prop' then
        SetPedPreloadPropData(ped, category.id, drawable, 0)
        waitFor(function() return HasPedPreloadPropDataFinished(ped) end, 3000)
        SetPedPropIndex(ped, category.id, drawable, 0, true)
        ReleasePedPreloadPropData(ped)
    else
        SetPedPreloadVariationData(ped, category.id, drawable, 0)
        waitFor(function() return HasPedPreloadVariationDataFinished(ped) end, 3000)
        SetPedComponentVariation(ped, category.id, drawable, 0, 0)
        ReleasePedPreloadVariationData(ped)
    end

    Wait(Config.Capture.wait)
end

local function screenshot()
    local shot = promise.new()
    exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(image)
        shot:resolve(image)
    end)
    return Citizen.Await(shot)
end

-- Photo de la tenue de base par vue de caméra, reprise toutes les Config.Capture.baseEvery pièces (lumière qui change)
local baseShots = {}

-- Photo d'une pièce : tenue de base photographiée (ou reprise du cache), pièce mise, seconde photo ; la page ne garde
-- que ce qui change entre les deux (la pièce), détoure le fond vert et recadre. batch = série en cours (le catalogue
-- n'est republié qu'à la fin). Renvoie { ok, path, preview } ou { ok = false, error }.
local function photograph(category, drawable, view, batch)
    local ped = PlayerPedId()
    local sex = sexOf(ped)
    photoBase(ped, sex)

    if shop.photoView ~= view then
        shop.photoView = view
        setCamera(view, true, Config.Capture.cameras[view])
        -- Le temps que la pose de la vue (poignet levé) se mette en place
        Wait(500)
    end

    local base = baseShots[view]

    if not base or base.uses >= Config.Capture.baseEvery then
        Wait(Config.Capture.wait)
        base = { image = screenshot(), uses = 0 }
        baseShots[view] = base
    end

    base.uses = base.uses + 1
    wearForPhoto(ped, category, drawable)

    local image = screenshot()
    photoBase(ped, sex)
    cropReply = nil
    SendNUIMessage({ action = 'crop', image = image, base = base.image, threshold = Config.Capture.threshold, size = Config.Capture.size, crop = Config.Capture.crop, quality = Config.Capture.quality })
    local cropped = waitFor(function() return cropReply end, 8000)

    if not cropped or type(cropped.image) ~= 'string' then
        return { ok = false, error = cropped and cropped.error or 'Détourage impossible.' }
    end

    captureReply = nil
    TriggerLatentServerEvent('lunatic_clothing:photo', 200000, sex, category.key, drawable, cropped.image, batch == true)
    local reply = waitFor(function() return captureReply end, 15000)

    if not reply or not reply.ok then
        return { ok = false, error = 'Photo refusée par le serveur.' }
    end

    return { ok = true, path = reply.path, preview = cropped.image }
end

local function photoReady()
    return shop and shop.mode == 'tool' and shop.screenshot and GetResourceState('screenshot-basic') == 'started'
end

-- Vue de la caméra d'une catégorie (celle de son groupe)
local function photoView(key)
    for _, group in ipairs(Config.Groups) do
        for _, category in ipairs(group.categories) do
            if category.key == key then
                local view = category.camera or group.camera
                return Config.Capture.cameras[view] and view or 'torso'
            end
        end
    end

    return 'torso'
end

-- Une pièce (bouton « Prendre la photo ») ; la tenue d'avant revient ensuite
RegisterNUICallback('capture', function(data, cb)
    local category = ClothingCategory(data.key)
    local drawable = math.tointeger(tonumber(data.drawable))

    if not photoReady() then
        return cb({ ok = false, error = 'screenshot-basic ne tourne pas sur le serveur.' })
    end

    if not category or not drawable then
        return cb({ ok = false, error = 'Pièce invalide.' })
    end

    local ped = PlayerPedId()
    local worn = wornAll(ped)
    local previous = shop.view
    SendNUIMessage({ action = 'toolHide', hidden = true })
    startGreenScreen()
    baseShots, shop.photoView = {}, nil
    Wait(50)

    local result = photograph(category, drawable, photoView(category.key), false)

    greenScreen = false
    applyPieces(worn)
    applyPiece(ped, category, drawable, 0)
    setCamera(previous or 'torso', true)
    SendNUIMessage({ action = 'toolHide', hidden = false })
    cb(result)
end)

-- Série : toutes les pièces d'une catégorie ou de tout le catalogue (sexe affiché), une à une ; skip = garder les
-- pièces qui ont déjà une photo (reprise). Progression envoyée à la page, « Arrêter » met fin à la série.
local batchRunning = false

RegisterNUICallback('batchStop', function(_, cb)
    batchRunning = false
    cb({})
end)

RegisterNUICallback('batch', function(data, cb)
    if not photoReady() then
        return cb({ ok = false, error = 'screenshot-basic ne tourne pas sur le serveur.' })
    end

    if batchRunning then
        return cb({ ok = false, error = 'Une série est déjà en cours.' })
    end

    local ped = PlayerPedId()
    local sex = sexOf(ped)
    local items = catalogueFor(sex)
    local jobs = {}

    for _, group in ipairs(Config.Groups) do
        for _, category in ipairs(group.categories) do
            if data.scope == 'all' or category.key == data.key then
                for drawable = 0, counts(category, 0).drawables - 1 do
                    local item = items[category.key] and items[category.key][tostring(drawable)]
                    local photo = item and type(item.image) == 'string' and item.image:sub(1, 8) == 'clothes/'

                    if not (data.skip and photo) then
                        jobs[#jobs + 1] = { category = category, drawable = drawable, view = photoView(category.key) }
                    end
                end
            end
        end
    end

    if #jobs == 0 then
        return cb({ ok = false, error = 'Aucune pièce à photographier (toutes ont déjà une photo).' })
    end

    cb({ ok = true, total = #jobs })
    batchRunning = true

    CreateThread(function()
        local worn = wornAll(ped)
        local previous = shop.view
        local done, failed = 0, 0
        SendNUIMessage({ action = 'toolHide', hidden = true })
        startGreenScreen()
        baseShots, shop.photoView = {}, nil
        Wait(50)

        for index, job in ipairs(jobs) do
            if not batchRunning or not shop then
                break
            end

            local result = photograph(job.category, job.drawable, job.view, true)

            if result.ok then
                done = done + 1
            else
                failed = failed + 1
            end

            SendNUIMessage({ action = 'batchProgress', index = index, total = #jobs, done = done, failed = failed, label = ('%s n° %d'):format(job.category.label, job.drawable) })
        end

        batchRunning = false
        greenScreen = false
        TriggerServerEvent('lunatic_clothing:photosDone')

        if shop then
            applyPieces(worn)
            setCamera(previous or 'torso', true)
            catalogueCache = { version = nil }
            SendNUIMessage({ action = 'toolHide', hidden = false })
            SendNUIMessage({ action = 'batchDone', done = done, failed = failed, data = toolData(sexOf(PlayerPedId()), shop.screenshot) })
        end
    end)
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
            SetBlipSprite(blip, (Config.Blip.sprites or {})[ClothingBrandKind(brand)] or Config.Blip.sprite)
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
