-- Menu contextuel (doc Vision) : Alt gauche maintenu fait apparaître le curseur (l'entité visée est surlignée),
-- clic droit ouvre le menu à la souris sur ce qui est visé : soi-même, un joueur, un PNJ, un véhicule, un objet ou le sol.
-- Les scripts y ajoutent leurs entrées : exports.lunatic_context:register(nom, fonction(ctx) -> entrées, ordre).
--   ctx   = { entity, kind = 'self' | 'player' | 'ped' | 'vehicle' | 'object' | 'ground', serverId, coords, inVehicle }
--   entrée = { label, right?, color? ('red' | 'blue'), header? (texte seul), disabled?, onSelect? = fonction, submenu? = entrées }
-- Ce moteur ne décide de rien : chaque script vérifie ses droits, et ses actions passent par son serveur.

-- Clic droit : visée à pied (25), visée en véhicule (68), clic droit du curseur (238)
local RIGHT_CLICKS = { 25, 68, 238 }
local RANGE = 60.0
-- Carte, véhicules, PNJ, objets : la carte arrête le rayon (pas de sélection à travers un mur)
local RAY_FLAGS = 1 | 2 | 4 | 8 | 16
local LOOK_CONTROLS = { 1, 2, 24, 25, 68, 69, 70, 91, 92, 106, 140, 141, 142, 257, 263, 264 }

local providers = {} -- nom -> { fn, order, resource }
local openMenu = nil -- menu ouvert : { items = { [id] = entrée } }
local outlined = 0
local held = false -- touche du menu (Alt gauche par défaut) maintenue
local lastOpen = 0

-- Touche réglable dans Paramètres > Raccourcis clavier > FiveM ; marche à pied comme en véhicule
-- (le contrôle 19 du jeu, la roue des armes, ne répond pas dans tous les cas)
RegisterCommand('+lunatic_context', function() held = true end, false)
RegisterCommand('-lunatic_context', function() held = false end, false)
RegisterKeyMapping('+lunatic_context', 'Menu contextuel (maintenir, puis clic droit)', 'keyboard', 'LMENU')

---------------------------------------------------------------------
-- Enregistrement des scripts
---------------------------------------------------------------------

exports('register', function(name, fn, order)
    if type(name) ~= 'string' then
        return
    end

    providers[name] = { fn = fn, order = tonumber(order) or 50, resource = GetInvokingResource() }
end)

-- Script arrêté : ses entrées disparaissent
AddEventHandler('onClientResourceStop', function(resource)
    for name, provider in pairs(providers) do
        if provider.resource == resource then
            providers[name] = nil
        end
    end
end)

---------------------------------------------------------------------
-- Cible sous la souris
---------------------------------------------------------------------

local function cursor()
    return GetDisabledControlNormal(0, 239), GetDisabledControlNormal(0, 240)
end

-- Entité réelle (PNJ, véhicule, objet) ; un bâtiment ou un décor de la carte touché par le rayon donne 0
local function validEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return 0
    end

    local kind = GetEntityType(entity)

    if kind == 1 or kind == 2 or kind == 3 then
        return entity
    end

    return 0
end

local function ray(x, y)
    local from, direction = GetWorldCoordFromScreenCoord(x, y)
    local to = from + direction * RANGE
    return from, to
end

-- Rayon depuis la caméra à travers le point de l'écran (au clic) : entité touchée (ou 0) et point d'impact
local function aim(x, y)
    local from, to = ray(x, y)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, RAY_FLAGS, 0, 4)
    local _, hit, coords, _, entity = GetShapeTestResult(handle)

    if hit ~= 1 then
        return 0, nil
    end

    return validEntity(entity), coords
end

-- Survol : test non bloquant, lu aux images suivantes (1 = encore en cours)
local probe = nil

local function hoverAim(x, y)
    if probe then
        local status, hit, _, _, entity = GetShapeTestResult(probe)

        if status == 1 then
            return nil
        end

        probe = nil
        return hit == 1 and validEntity(entity) or 0
    end

    local from, to = ray(x, y)
    probe = StartShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, RAY_FLAGS, 0, 4)
    return nil
end

local function contextOf(entity, coords)
    local ped = PlayerPedId()
    local inVehicle = GetVehiclePedIsIn(ped, false)
    local ctx = { entity = entity, coords = coords, inVehicle = inVehicle ~= 0 and inVehicle or nil, kind = 'ground' }
    local kind = entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) or 0

    if kind == 1 and entity == ped then
        ctx.kind, ctx.serverId = 'self', GetPlayerServerId(PlayerId())
    elseif kind == 1 and IsPedAPlayer(entity) then
        ctx.kind, ctx.serverId = 'player', GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))
    elseif kind == 1 then
        ctx.kind = 'ped'
    elseif kind == 2 then
        ctx.kind = 'vehicle'
    elseif kind == 3 then
        ctx.kind = 'object'
    else
        ctx.entity = 0
    end

    return ctx
end

-- Contour seulement sur les PNJ, joueurs et véhicules : sur les objets (décors de la carte surtout), le contour peut faire crasher le jeu
local function canOutline(entity)
    if entity == 0 or not DoesEntityExist(entity) then
        return false
    end

    local kind = GetEntityType(entity)
    return kind == 1 or kind == 2
end

local function setOutline(entity)
    if entity == outlined then
        return
    end

    if outlined ~= 0 and canOutline(outlined) then
        SetEntityDrawOutline(outlined, false)
    end

    outlined = 0

    if canOutline(entity) then
        SetEntityDrawOutlineColor(150, 80, 255, 255)
        SetEntityDrawOutline(entity, true)
        outlined = entity
    end
end

---------------------------------------------------------------------
-- Menu
---------------------------------------------------------------------

-- Entrées de tous les scripts, dans leur ordre ; chaque entrée reçoit un id pour la page (sans les fonctions)
local function collect(ctx)
    local list = {}

    for name, provider in pairs(providers) do
        list[#list + 1] = { name = name, provider = provider }
    end

    table.sort(list, function(a, b) return a.provider.order < b.provider.order end)

    local byId, tree, counter = {}, {}, 0

    local function convert(items, into)
        for _, item in ipairs(items) do
            if type(item) == 'table' and item.label then
                counter = counter + 1
                local id = tostring(counter)
                byId[id] = item
                local node = { id = id, label = item.label, right = item.right, color = item.color, header = item.header == true, disabled = item.disabled == true }

                if type(item.submenu) == 'table' and #item.submenu > 0 then
                    node.children = {}
                    convert(item.submenu, node.children)
                elseif type(item.submenu) == 'table' then
                    node.disabled = true
                end

                into[#into + 1] = node
            end
        end
    end

    for index, entry in ipairs(list) do
        local ok, items = pcall(entry.provider.fn, ctx)

        if ok and type(items) == 'table' and #items > 0 then
            if index > 1 and #tree > 0 then
                tree[#tree + 1] = { separator = true }
            end

            convert(items, tree)
        elseif not ok then
            print(('[lunatic_context] Entrées de « %s » : %s'):format(entry.name, tostring(items)))
        end
    end

    return tree, byId
end

local function closeMenu()
    if not openMenu then
        return
    end

    openMenu = nil
    -- Alt relâché pendant le menu : le jeu n'a pas reçu le relâchement (focus sur la page)
    held = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function showMenu(entity, coords, x, y)
    local ctx = contextOf(entity, coords)
    local tree, byId = collect(ctx)

    if #tree == 0 then
        return
    end

    openMenu = { items = byId }
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', x = x, y = y, items = tree })
end

RegisterNUICallback('select', function(data, cb)
    cb({})
    local item = openMenu and openMenu.items[tostring(data.id)]
    closeMenu()

    -- onSelect peut venir d'un autre script (référence de fonction appelable)
    if item and item.onSelect then
        CreateThread(function()
            local ok, err = pcall(item.onSelect)

            if not ok then
                print(('[lunatic_context] Action « %s » : %s'):format(item.label, tostring(err)))
            end
        end)
    end
end)

RegisterNUICallback('close', function(_, cb)
    cb({})
    closeMenu()
end)

---------------------------------------------------------------------
-- Alt maintenu : curseur, entité surlignée ; clic droit : menu
---------------------------------------------------------------------

local function rightClicked()
    for _, control in ipairs(RIGHT_CLICKS) do
        if IsDisabledControlJustPressed(0, control) or IsControlJustPressed(0, control) then
            return true
        end
    end

    return false
end

CreateThread(function()
    while true do
        if not openMenu and held and not IsPauseMenuActive() and not IsNuiFocused() then
            SetMouseCursorActiveThisFrame()

            for _, control in ipairs(LOOK_CONTROLS) do
                DisableControlAction(0, control, true)
            end

            local x, y = cursor()

            local hovered = hoverAim(x, y)

            if hovered then
                setOutline(hovered)
            end

            if rightClicked() and GetGameTimer() - lastOpen > 250 then
                lastOpen = GetGameTimer()
                local entity, coords = aim(x, y)
                setOutline(0)
                showMenu(entity, coords, x, y)
            end

            Wait(0)
        else
            setOutline(0)
            Wait(openMenu and 100 or 0)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        setOutline(0)
        closeMenu()
    end
end)
