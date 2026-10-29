-- Menu contextuel (doc Vision) : Alt gauche maintenu fait apparaître le curseur, clic droit ouvre le menu à la souris
-- sur ce qui est visé : soi-même, un joueur, un PNJ, un véhicule, un objet ou le sol.
-- Le menu reste ouvert tant qu'Alt est maintenu : une action le met à jour, un clic droit ailleurs vise autre chose,
-- relâcher Alt (ou Échap) le ferme. La page n'a jamais le focus : le jeu lit la souris et envoie survol et clics
-- à la page ; le clavier reste au jeu, le personnage marche et conduit normalement (caméra et tir bloqués).
-- Les scripts y ajoutent leurs entrées : exports.lunatic_context:register(nom, fonction(ctx) -> entrées, ordre).
--   ctx   = { entity, kind = 'self' | 'player' | 'ped' | 'vehicle' | 'object' | 'ground', serverId, coords, inVehicle }
--   entrée = { label, right?, color? ('red' | 'blue'), header? (texte seul), disabled?, onSelect? = fonction,
--              close? (ferme le menu après l'action : téléportation, autre interface…), submenu? = entrées }
-- Ce moteur ne décide de rien : chaque script vérifie ses droits, et ses actions passent par son serveur.

-- Clic droit : visée à pied (25), visée en véhicule (68), clic droit du curseur (238)
local RIGHT_CLICKS = { 25, 68, 238 }
local RANGE = 60.0
-- Carte, véhicules, PNJ, objets : la carte arrête le rayon (pas de sélection à travers un mur)
local RAY_FLAGS = 1 | 2 | 4 | 8 | 16
local LOOK_CONTROLS = { 1, 2, 24, 25, 68, 69, 70, 91, 92, 106, 140, 141, 142, 257, 263, 264 }
-- Menu ouvert : en plus, Échap (menu pause) et la roue des armes
local MENU_CONTROLS = { 37, 199, 200, 322 }
-- Clic gauche : attaque à pied (24), en véhicule (69), clic du curseur (237)
local LEFT_CLICKS = { 24, 69, 237 }
-- Délai avant de relire les entrées après une action (le temps que l'état du jeu change)
local REFRESH_DELAY = 250

local providers = {} -- nom -> { fn, order, resource }
local openMenu = nil -- menu ouvert : { ctx, items = { [id] = entrée } }
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

-- Rayon depuis la caméra à travers le point de l'écran, seulement au clic (pas de test à chaque image,
-- pas de contour : les deux ont été retirés après des crashs du jeu)
local function aim(x, y)
    local from, direction = GetWorldCoordFromScreenCoord(x, y)
    local to = from + direction * RANGE
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, RAY_FLAGS, 0, 4)
    local _, hit, coords, _, entity = GetShapeTestResult(handle)

    if hit ~= 1 then
        return 0, nil
    end

    return validEntity(entity), coords
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
    SendNUIMessage({ action = 'close' })
end

-- Ouvre (ou remplace) le menu ; sans entrée (ciel, sol…) rien n'est affiché jusqu'au relâchement d'Alt
local function showMenu(entity, coords, x, y)
    local ctx = contextOf(entity, coords)
    local tree, byId = collect(ctx)

    openMenu = { ctx = ctx, items = byId }
    SendNUIMessage({ action = 'open', x = x, y = y, items = tree })
end

-- Après une action : entrées relues pour la même cible (libellés à jour, entrées disparues…)
local function refreshMenu(menu)
    if openMenu ~= menu then
        return
    end

    local ctx = menu.ctx

    if ctx.entity ~= 0 and not DoesEntityExist(ctx.entity) then
        ctx.entity, ctx.kind, ctx.serverId = 0, 'ground', nil
    end

    local tree, byId = collect(ctx)
    menu.items = byId
    SendNUIMessage({ action = 'update', items = tree })
end

-- La page a trouvé l'entrée sous le clic (message "click")
RegisterNUICallback('select', function(data, cb)
    cb({})
    local menu = openMenu
    local item = menu and menu.items[tostring(data.id)]

    if not item then
        return
    end

    if item.close then
        closeMenu()
    end

    -- onSelect peut venir d'un autre script (référence de fonction appelable)
    CreateThread(function()
        if item.onSelect then
            local ok, err = pcall(item.onSelect)

            if not ok then
                print(('[lunatic_context] Action « %s » : %s'):format(item.label, tostring(err)))
            end
        end

        if not item.close then
            Wait(REFRESH_DELAY)
            refreshMenu(menu)
        end
    end)
end)

---------------------------------------------------------------------
-- Alt maintenu : curseur ; clic droit : menu
---------------------------------------------------------------------

local function pressed(controls)
    for _, control in ipairs(controls) do
        if IsDisabledControlJustPressed(0, control) or IsControlJustPressed(0, control) then
            return true
        end
    end

    return false
end

local function disable(controls)
    for _, control in ipairs(controls) do
        DisableControlAction(0, control, true)
    end
end

CreateThread(function()
    local lastX, lastY = -1, -1

    while true do
        if openMenu and (not held or IsPauseMenuActive() or IsNuiFocused()) then
            -- Alt relâché, menu pause ou autre interface ouverte : fermé
            closeMenu()
        end

        if held and not IsPauseMenuActive() and not IsNuiFocused() then
            SetMouseCursorActiveThisFrame()
            disable(LOOK_CONTROLS)

            local x, y = cursor()

            if openMenu then
                disable(MENU_CONTROLS)

                if x ~= lastX or y ~= lastY then
                    lastX, lastY = x, y
                    SendNUIMessage({ action = 'mouse', x = x, y = y })
                end

                if pressed(LEFT_CLICKS) then
                    SendNUIMessage({ action = 'click', x = x, y = y })
                end

                if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322) then
                    closeMenu()
                end
            end

            -- Clic droit : menu sur ce qui est visé (ou nouvelle cible, menu déjà ouvert)
            if pressed(RIGHT_CLICKS) and GetGameTimer() - lastOpen > 250 then
                lastOpen = GetGameTimer()
                local entity, coords = aim(x, y)
                showMenu(entity, coords, x, y)
                lastX, lastY = -1, -1
            end

            Wait(0)
        else
            Wait(0)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        closeMenu()
    end
end)
