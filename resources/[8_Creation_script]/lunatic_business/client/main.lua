-- lunatic_business : côté client. Marqueurs au sol des points de sa structure, [E] pour interagir, menus ox_lib.
-- La Sonnette est visible par tous ; les autres points seulement par les membres de la structure.

local points = {}
local playerJob
local onJobChanged -- défini plus bas : les magasins réservés à un métier apparaissent ou disparaissent

local refreshStructureBlips -- défini plus bas : blips de la structure du joueur

local function loadPoints(list)
    points = type(list) == 'table' and list or {}

    if refreshStructureBlips then
        refreshStructureBlips()
    end
end

AddStateBagChangeHandler('lunaticStructurePoints', 'global', function(_, _, value)
    loadPoints(value)
end)

RegisterNetEvent('esx:playerLoaded', function(data)
    playerJob = data and data.job

    if refreshStructureBlips then
        refreshStructureBlips()
    end
end)

RegisterNetEvent('esx:setJob', function(job)
    playerJob = job

    if onJobChanged then
        onJobChanged()
    end
end)

CreateThread(function()
    loadPoints(GlobalState.lunaticStructurePoints)

    if ESX.IsPlayerLoaded() then
        playerJob = ESX.GetPlayerData().job
        refreshStructureBlips()
    end
end)

local function money(amount)
    return ('%s %s'):format(tostring(math.floor(amount or 0)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', ''), GlobalState.lunaticCurrency or '$')
end

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function failed(result)
    if result and result.ok then
        return false
    end

    notify(result and result.error or 'Action impossible.', 'error')
    return true
end

local function playtime(minutes)
    minutes = minutes or 0
    return minutes < 60 and ('%d min'):format(minutes) or ('%d h %02d'):format(math.floor(minutes / 60), minutes % 60)
end

---------------------------------------------------------------------
-- Gestion (patron)
---------------------------------------------------------------------

local openManagement

local function gradeLabel(grades, number)
    for _, grade in ipairs(grades) do
        if grade.grade == number then
            return grade.label
        end
    end

    return ('Grade %d'):format(number)
end

local function memberMenu(point, data, member)
    local bossGrade = data.grades[#data.grades].grade
    local options = {}

    -- Grade suivant, sans jamais atteindre celui du patron
    for i, grade in ipairs(data.grades) do
        if grade.grade == member.grade then
            local up, down = data.grades[i + 1], data.grades[i - 1]

            if up and up.grade < bossGrade then
                options[#options + 1] = { title = ('Promouvoir : %s'):format(up.label), icon = 'arrow-up', onSelect = function()
                    if not failed(lib.callback.await('lunatic_business:setGrade', false, point.id, member.identifier, up.grade)) then
                        notify(('%s est maintenant %s.'):format(member.name, up.label), 'success')
                    end
                    openManagement(point)
                end }
            end

            if down then
                options[#options + 1] = { title = ('Rétrograder : %s'):format(down.label), icon = 'arrow-down', onSelect = function()
                    if not failed(lib.callback.await('lunatic_business:setGrade', false, point.id, member.identifier, down.grade)) then
                        notify(('%s est maintenant %s.'):format(member.name, down.label), 'success')
                    end
                    openManagement(point)
                end }
            end
        end
    end

    options[#options + 1] = { title = 'Renvoyer', icon = 'door-open', iconColor = '#ff6b6b', onSelect = function()
        local answer = lib.alertDialog({ header = ('Renvoyer %s ?'):format(member.name), content = 'Il redevient sans emploi.', centered = true, cancel = true, labels = { confirm = 'Renvoyer', cancel = 'Annuler' } })

        if answer == 'confirm' and not failed(lib.callback.await('lunatic_business:fire', false, point.id, member.identifier)) then
            notify(('%s a été renvoyé.'):format(member.name), 'success')
        end

        openManagement(point)
    end }

    lib.registerContext({ id = 'lb_member', title = member.name, menu = 'lb_members', options = options })
    lib.showContext('lb_member')
end

local function membersMenu(point, data)
    local options = {}

    for _, member in ipairs(data.members) do
        local isMe = member.identifier == data.me
        options[#options + 1] = {
            title = isMe and ('%s (vous)'):format(member.name) or member.name,
            description = ('%s · %s · %s de service'):format(gradeLabel(data.grades, member.grade), member.online and 'en ligne' or 'hors ligne', playtime(member.playtime)),
            icon = member.online and 'circle' or 'circle-dot',
            iconColor = member.online and '#5fd3a0' or '#6b6b78',
            disabled = isMe or member.grade >= data.grades[#data.grades].grade,
            onSelect = function()
                memberMenu(point, data, member)
            end,
        }
    end

    lib.registerContext({ id = 'lb_members', title = ('Membres (%d)'):format(#data.members), menu = 'lb_manage', options = options })
    lib.showContext('lb_members')
end

local function recruitMenu(point)
    local options = {}

    for _, nearby in ipairs(lib.getNearbyPlayers(GetEntityCoords(PlayerPedId()), Config.RecruitDistance, false)) do
        local serverId = GetPlayerServerId(nearby.id)
        local state = Player(serverId).state
        local name = state.firstName and ('%s %s'):format(state.firstName, state.lastName or '') or GetPlayerName(nearby.id)

        options[#options + 1] = { title = name, description = ('ID %d'):format(serverId), icon = 'user-plus', onSelect = function()
            local result = lib.callback.await('lunatic_business:recruit', false, point.id, serverId)

            if not failed(result) then
                notify(('%s a été recruté.'):format(result.name or name), 'success')
            end
        end }
    end

    if #options == 0 then
        options[1] = { title = 'Personne à proximité', description = ('Le joueur doit être à moins de %d m.'):format(Config.RecruitDistance), disabled = true }
    end

    lib.registerContext({ id = 'lb_recruit', title = 'Recruter un joueur proche', menu = 'lb_manage', options = options })
    lib.showContext('lb_recruit')
end

local function accountMenu(point, data)
    local function operation(kind)
        local input = lib.inputDialog(kind == 'deposit' and 'Déposer du liquide' or 'Retirer du liquide', {
            { type = 'number', label = 'Montant', min = 1, max = Config.AccountMaxAction, required = true },
        })

        if not input or not input[1] then
            return accountMenu(point, data)
        end

        local result = lib.callback.await('lunatic_business:account', false, point.id, kind, math.floor(input[1]))

        if not failed(result) then
            data.balance = result.balance
            notify(('%s effectué. Solde : %s.'):format(kind == 'deposit' and 'Dépôt' or 'Retrait', money(result.balance)), 'success')
        end

        accountMenu(point, data)
    end

    lib.registerContext({ id = 'lb_account', title = 'Compte de société', menu = 'lb_manage', options = {
        { title = ('Solde : %s'):format(money(data.balance)), icon = 'building-columns', readOnly = true },
        { title = 'Déposer du liquide', icon = 'arrow-down', onSelect = function() operation('deposit') end },
        { title = 'Retirer du liquide', icon = 'arrow-up', onSelect = function() operation('withdraw') end },
        { title = 'Historique', icon = 'clock-rotate-left', onSelect = function()
            local result = lib.callback.await('lunatic_business:history', false, point.id)

            if failed(result) then
                return
            end

            local options = {}

            for _, entry in ipairs(result.history) do
                options[#options + 1] = {
                    title = ('%s%s'):format(entry.amount > 0 and '+' or '-', money(math.abs(entry.amount))),
                    description = ('%s · %s · solde %s'):format(entry.reason ~= '' and entry.reason or '—', entry.actor ~= '' and entry.actor or '?', money(entry.balance)),
                    icon = entry.amount > 0 and 'plus' or 'minus',
                    iconColor = entry.amount > 0 and '#5fd3a0' or '#ff8a84',
                    readOnly = true,
                }
            end

            if #options == 0 then
                options[1] = { title = 'Aucune opération', readOnly = true }
            end

            lib.registerContext({ id = 'lb_history', title = 'Historique du compte', menu = 'lb_account', options = options })
            lib.showContext('lb_history')
        end },
    } })
    lib.showContext('lb_account')
end

openManagement = function(point)
    local data = lib.callback.await('lunatic_business:management', false, point.id)

    if failed(data) then
        return
    end

    lib.registerContext({ id = 'lb_manage', title = ('Gestion · %s'):format(data.label), options = {
        { title = 'Compte de société', description = ('Solde : %s'):format(money(data.balance)), icon = 'building-columns', onSelect = function() accountMenu(point, data) end },
        { title = ('Membres (%d)'):format(#data.members), description = 'Promouvoir, rétrograder, renvoyer', icon = 'users', onSelect = function() membersMenu(point, data) end },
        { title = 'Recruter un joueur proche', icon = 'user-plus', onSelect = function() recruitMenu(point) end },
    } })
    lib.showContext('lb_manage')
end

---------------------------------------------------------------------
-- Vestiaire
---------------------------------------------------------------------

local appearance = exports['illenium-appearance']

local function openWardrobe(point)
    local data = lib.callback.await('lunatic_business:outfits', false, point.id)

    if failed(data) then
        return
    end

    local options = {}

    for _, outfit in ipairs(data.outfits) do
        options[#options + 1] = { title = ('Tenue : %s'):format(outfit.label), icon = 'shirt', onSelect = function()
            local ped = PlayerPedId()
            appearance:setPedComponents(ped, outfit.outfit.components)
            appearance:setPedProps(ped, outfit.outfit.props)
            notify(('Tenue « %s » enfilée.'):format(outfit.label), 'success')
        end }
    end

    if not data.model then
        options[#options + 1] = { title = 'Aucune tenue', description = 'Les tenues ne concernent que les personnages homme ou femme du jeu.', readOnly = true }
    elseif #data.outfits == 0 then
        options[#options + 1] = { title = 'Aucune tenue pour votre grade', readOnly = true }
    end

    options[#options + 1] = { title = 'Reprendre ma tenue civile', icon = 'user', onSelect = function()
        TriggerEvent('illenium-appearance:client:reloadSkin', true)
    end }

    if data.isBoss and data.model then
        options[#options + 1] = { title = 'Enregistrer ma tenue pour un grade', description = 'La tenue que vous portez devient celle du grade choisi', icon = 'floppy-disk', onSelect = function()
            local choices = {}

            for _, grade in ipairs(data.grades) do
                choices[#choices + 1] = { value = grade.grade, label = grade.label }
            end

            local input = lib.inputDialog('Enregistrer la tenue', { { type = 'select', label = 'Grade', options = choices, required = true } })

            if not input or input[1] == nil then
                return openWardrobe(point)
            end

            local ped = PlayerPedId()
            local result = lib.callback.await('lunatic_business:saveOutfit', false, point.id, input[1], {
                components = appearance:getPedComponents(ped),
                props = appearance:getPedProps(ped),
            })

            if not failed(result) then
                notify('Tenue enregistrée.', 'success')
            end

            openWardrobe(point)
        end }

        if #data.outfits > 0 then
            options[#options + 1] = { title = 'Supprimer une tenue', icon = 'trash', onSelect = function()
                local choices = {}

                for _, outfit in ipairs(data.outfits) do
                    choices[#choices + 1] = { value = outfit.grade, label = outfit.label }
                end

                local input = lib.inputDialog('Supprimer une tenue', { { type = 'select', label = 'Grade', options = choices, required = true } })

                if input and input[1] ~= nil and not failed(lib.callback.await('lunatic_business:deleteOutfit', false, point.id, input[1])) then
                    notify('Tenue supprimée.', 'success')
                end

                openWardrobe(point)
            end }
        end
    end

    lib.registerContext({ id = 'lb_wardrobe', title = 'Vestiaire', options = options })
    lib.showContext('lb_wardrobe')
end

---------------------------------------------------------------------
-- Interaction avec un point
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Catalogues et craft
---------------------------------------------------------------------

local catalogs = {}

local function loadCatalogs(value)
    catalogs = type(value) == 'table' and value or {}
end

AddStateBagChangeHandler('lunaticCatalogs', 'global', function(_, _, value)
    loadCatalogs(value)
end)

CreateThread(function()
    loadCatalogs(GlobalState.lunaticCatalogs)
end)

local function itemLabel(name)
    local item = exports.ox_inventory:Items(name)
    return item and item.label or name
end

local function itemImage(name)
    return ('nui://ox_inventory/web/images/%s.png'):format(name)
end

local function myGrade(job)
    return playerJob and playerJob.name == job and tonumber(playerJob.grade) or -1
end

local function catalogsFor(job, kinds)
    local list = {}

    for _, catalog in pairs(catalogs) do
        if catalog.jobs and catalog.jobs[job] and kinds[catalog.kind] then
            list[#list + 1] = catalog
        end
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local openCatalogList

local function openCatalog(point, catalog, back)
    local grade = myGrade(point.job)
    local options = {}

    for _, line in ipairs(catalog.lines or {}) do
        local locked = catalog.kind == 'equipment' and grade < (line.minGrade or 0)
        local price = line.price > 0 and money(line.price) or 'Gratuit'

        options[#options + 1] = {
            title = ('%s%s'):format(line.count > 1 and (line.count .. ' × ') or '', itemLabel(line.item)),
            description = locked and ('Grade minimum : %d'):format(line.minGrade) or ('%s (compte de la société)'):format(price),
            image = itemImage(line.item),
            icon = 'box',
            disabled = locked,
            onSelect = function()
                local input = lib.inputDialog(itemLabel(line.item), { { type = 'number', label = 'Quantité', default = 1, min = 1, max = Config.MaxPurchase, required = true } })

                if input and input[1] then
                    local result = lib.callback.await('lunatic_business:buy', false, point.id, catalog.id, line.id, math.floor(input[1]))

                    if not failed(result) then
                        notify(result.total > 0 and ('%d × %s pour %s.'):format(result.amount, result.label, money(result.total))
                            or ('%d × %s récupéré.'):format(result.amount, result.label), 'success')
                    end
                end

                openCatalog(point, catalog, back)
            end,
        }
    end

    if #options == 0 then
        options[1] = { title = 'Catalogue vide', readOnly = true }
    end

    lib.registerContext({ id = 'lb_catalog', title = catalog.label, menu = back and 'lb_catalogs' or nil, options = options })
    lib.showContext('lb_catalog')
end

openCatalogList = function(point, kinds)
    local list = catalogsFor(point.job, kinds)

    if #list == 0 then
        return notify('Aucun catalogue disponible ici.', 'info')
    end

    if #list == 1 then
        return openCatalog(point, list[1], false)
    end

    local options = {}

    for _, catalog in ipairs(list) do
        options[#options + 1] = { title = catalog.label, description = ('%d article%s'):format(#catalog.lines, #catalog.lines > 1 and 's' or ''), icon = 'shield-halved', onSelect = function()
            openCatalog(point, catalog, true)
        end }
    end

    lib.registerContext({ id = 'lb_catalogs', title = 'Catalogues', options = options })
    lib.showContext('lb_catalogs')
end

local function craft(point, catalog, line)
    local start = lib.callback.await('lunatic_business:craftStart', false, point.id, catalog.id, line.id)

    if failed(start) then
        return
    end

    local done = lib.progressBar({
        duration = start.duration * 1000,
        label = ('Fabrication : %s'):format(start.label),
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    })

    if not done then
        TriggerServerEvent('lunatic_business:craftCancel')
        return notify('Fabrication annulée.', 'error')
    end

    local result = lib.callback.await('lunatic_business:craftFinish', false, point.id, catalog.id, line.id)

    if not failed(result) then
        notify(('%d × %s fabriqué.'):format(result.amount, result.label), 'success')
    end
end

local function openCraft(point)
    local grade = myGrade(point.job)
    local options = {}

    for _, catalog in ipairs(catalogsFor(point.job, { craft = true })) do
        for _, line in ipairs(catalog.lines or {}) do
            local parts = {}

            for _, ingredient in ipairs(line.ingredients or {}) do
                parts[#parts + 1] = ('%d × %s'):format(ingredient.count, itemLabel(ingredient.item))
            end

            local locked = grade < (line.minGrade or 0)
            options[#options + 1] = {
                title = ('%s%s'):format(line.count > 1 and (line.count .. ' × ') or '', itemLabel(line.item)),
                description = locked and ('Grade minimum : %d'):format(line.minGrade) or ('%s · %d s'):format(table.concat(parts, ' + '), line.duration),
                image = itemImage(line.item),
                icon = 'hammer',
                disabled = locked,
                onSelect = function()
                    craft(point, catalog, line)
                end,
            }
        end
    end

    if #options == 0 then
        return notify('Aucune recette disponible ici.', 'info')
    end

    lib.registerContext({ id = 'lb_craft', title = 'Fabrication', options = options })
    lib.showContext('lb_craft')
end

local handlers = {
    management = function(point)
        if not playerJob or playerJob.grade_name ~= 'boss' then
            return notify('Réservé au patron.', 'error')
        end

        openManagement(point)
    end,
    storage = function(point)
        exports.ox_inventory:openInventory('stash', ('lb_storage_%d'):format(point.id))
    end,
    locker = function(point)
        exports.ox_inventory:openInventory('stash', ('lb_locker_%s'):format(point.job))
    end,
    wardrobe = openWardrobe,
    catalog = function(point)
        openCatalogList(point, { equipment = true })
    end,
    armory = function(point)
        openCatalogList(point, { equipment = true })
    end,
    craft = openCraft,
    doorbell = function(point)
        TriggerServerEvent('lunatic_business:ring', point.id)
    end,
    custom = function(point)
        TriggerServerEvent('lunatic_business:useCustom', point.id)
        TriggerEvent('lunatic_business:customClient', point)
    end,
}

local function storeVehicle(point)
    local result = lib.callback.await('lunatic_business:garageStore', false, point.id)

    if not failed(result) then
        notify(('%s rangé.'):format(result.label), 'success')
    end
end

handlers.garage = function(point)
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        return storeVehicle(point)
    end

    local data = lib.callback.await('lunatic_business:garage', false, point.id)

    if failed(data) then
        return
    end

    local options = {}

    if data.out then
        options[#options + 1] = { title = ('Ranger : %s'):format(data.out), description = 'Le véhicule doit être près du garage.', icon = 'warehouse', onSelect = function() storeVehicle(point) end }
    end

    for _, vehicle in ipairs(data.vehicles) do
        options[#options + 1] = {
            title = vehicle.label, description = vehicle.model, icon = 'car', disabled = data.out ~= nil,
            onSelect = function()
                local result = lib.callback.await('lunatic_business:garageTake', false, point.id, vehicle.id)

                if not failed(result) then
                    notify(('%s sorti (plaque %s).'):format(result.label, result.plate), 'success')
                end
            end,
        }
    end

    if #options == 0 then
        options[1] = { title = 'Aucun véhicule', description = 'Rien pour votre grade dans ce garage (parc réglé par le staff).', disabled = true }
    end

    lib.registerContext({ id = 'lb_garage', title = ('%s · %s'):format(point.label, data.label), options = options })
    lib.showContext('lb_garage')
end

RegisterNetEvent('lunatic_business:ringed', function(data)
    notify(('%s sonne à %s (%s). Point GPS ajouté.'):format(data.name, data.job, data.label), 'info')
    SetNewWaypoint(data.x + 0.0, data.y + 0.0)
end)

local structureBlips = {}

refreshStructureBlips = function()
    for _, blip in ipairs(structureBlips) do
        RemoveBlip(blip)
    end

    structureBlips = {}

    for _, point in ipairs(points) do
        if point.type == 'blips' and playerJob and playerJob.name == point.job then
            local data = point.data or {}
            local blip = AddBlipForCoord(point.x, point.y, point.z)
            SetBlipSprite(blip, tonumber(data.sprite) or 60)
            SetBlipColour(blip, tonumber(data.color) or 0)
            SetBlipScale(blip, tonumber(data.scale) or 0.8)
            SetBlipDisplay(blip, 4)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(point.label)
            EndTextCommandSetBlipName(blip)
            structureBlips[#structureBlips + 1] = blip
        end
    end
end

-- Sonnette : visible par tous ; le reste par les membres
local function visible(point)
    return point.type == 'doorbell' or (playerJob ~= nil and playerJob.name == point.job)
end

---------------------------------------------------------------------
-- Magasins automatiques : blips, emplacements (même boucle que les points), ouverture ox_inventory
---------------------------------------------------------------------

local shops = {}
local shopTargets = {} -- emplacements à afficher : { x, y, z, label, shop, index }
local shopBlips = {}

local function shopAllowed(shop)
    if not shop.jobs or #shop.jobs == 0 then
        return true
    end

    for _, job in ipairs(shop.jobs) do
        if playerJob and playerJob.name == job then
            return true
        end
    end

    return false
end

local function refreshShops()
    for _, blip in ipairs(shopBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    shopBlips, shopTargets = {}, {}

    for _, shop in ipairs(shops) do
        if shopAllowed(shop) then
            for index, location in ipairs(shop.locations or {}) do
                -- Réglages de la tuile Interactions : PNJ, rayon du [E], blip affiché ou non
                shopTargets[#shopTargets + 1] = {
                    x = location.x, y = location.y, z = location.z, label = shop.label, shop = shop, index = index,
                    radius = tonumber(location.radius) or Config.InteractDistance, ped = location.ped, pedPos = location.pedPos, id = location.id,
                }

                if location.showBlip ~= false then
                    local blip = AddBlipForCoord(location.x, location.y, location.z)
                    SetBlipSprite(blip, shop.blip.sprite or 52)
                    SetBlipColour(blip, shop.blip.color or 2)
                    SetBlipScale(blip, (shop.blip.scale or 0.8) + 0.0)
                    SetBlipAsShortRange(blip, true)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentSubstringPlayerName(shop.blip.label ~= '' and shop.blip.label or shop.label)
                    EndTextCommandSetBlipName(blip)
                    shopBlips[#shopBlips + 1] = blip
                end
            end
        end
    end
end

-- PNJ des emplacements (tuile Interactions) : locaux, immobiles, invulnérables ; seulement à proximité
local shopPeds = {} -- id d'emplacement -> { ped, key }

local function deleteShopPed(id)
    local entry = shopPeds[id]

    if entry and DoesEntityExist(entry.ped) then
        DeleteEntity(entry.ped)
    end

    shopPeds[id] = nil
end

local function createShopPed(target, key)
    local model = joaat(target.ped)

    if not IsModelInCdimage(model) or not IsModelAPed(model) then
        return
    end

    RequestModel(model)
    local timeout = GetGameTimer() + 5000

    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        Wait(50)
    end

    if not HasModelLoaded(model) then
        return
    end

    local position = target.pedPos or { x = target.x, y = target.y, z = target.z, h = 0.0 }
    local ped = CreatePed(4, model, position.x, position.y, position.z, position.h or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)

    if not ped or ped == 0 then
        return
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetEntityHeading(ped, position.h or 0.0)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    FreezeEntityPosition(ped, true)
    shopPeds[target.id] = { ped = ped, key = key }
end

CreateThread(function()
    while true do
        local coords = GetEntityCoords(PlayerPedId())
        local wanted = {}

        for _, target in ipairs(shopTargets) do
            if target.ped and target.id then
                local position = target.pedPos or target
                -- Clé : modèle et position ; un changement dans le panel recrée le PNJ
                local key = ('%s:%.2f:%.2f:%.2f:%.1f'):format(target.ped, position.x, position.y, position.z, position.h or 0.0)

                if #(coords - vector3(position.x, position.y, position.z)) < 80.0 then
                    wanted[target.id] = true
                    local entry = shopPeds[target.id]

                    if entry and (entry.key ~= key or not DoesEntityExist(entry.ped)) then
                        deleteShopPed(target.id)
                        entry = nil
                    end

                    if not entry then
                        createShopPed(target, key)
                    end
                end
            end
        end

        for id in pairs(shopPeds) do
            if not wanted[id] then
                deleteShopPed(id)
            end
        end

        Wait(2000)
    end
end)

AddStateBagChangeHandler('lunaticShops', 'global', function(_, _, value)
    shops = type(value) == 'table' and value or {}
    refreshShops()
end)

onJobChanged = function()
    refreshShops()
    refreshStructureBlips()
end

CreateThread(function()
    shops = GlobalState.lunaticShops or {}
    Wait(1000)
    refreshShops()
end)

---------------------------------------------------------------------
-- Agences de location : interface (html/) et aperçu 3D du véhicule dans la vitrine.
-- Pendant le choix, le joueur attend invisible dans la vitrine (l'intérieur s'y charge) ; il revient au comptoir
-- avant de louer ou de rendre, car le serveur vérifie qu'il s'y trouve. Le véhicule montré n'existe que chez lui.
---------------------------------------------------------------------

local rental = nil -- { target, info, back, vehicle, cam, heading, pitch, distance, token }

local function rentalCamera()
    local spot = rental.info.showroom
    local h, p = math.rad(rental.heading), math.rad(rental.pitch)
    local target = vector3(spot.x, spot.y, spot.z + 0.5)
    local position = target + vector3(-math.sin(h) * math.cos(p) * rental.distance, math.cos(h) * math.cos(p) * rental.distance, math.sin(p) * rental.distance)

    SetCamCoord(rental.cam, position.x, position.y, position.z)
    PointCamAtCoord(rental.cam, target.x, target.y, target.z)
end

local function deletePreview()
    if rental and rental.vehicle and DoesEntityExist(rental.vehicle) then
        DeleteEntity(rental.vehicle)
    end

    if rental then
        rental.vehicle = nil
    end
end

-- Véhicule choisi posé dans la vitrine, phares allumés ; caméra reculée selon sa taille
local function previewVehicle(offer)
    rental.token = rental.token + 1
    local token = rental.token
    local model = joaat(offer.model)
    deletePreview()

    if not IsModelInCdimage(model) or not lib.requestModel(model, 10000) then
        return
    end

    -- Un autre véhicule a été choisi pendant le chargement
    if not rental or token ~= rental.token then
        SetModelAsNoLongerNeeded(model)
        return
    end

    local spot = rental.info.showroom
    local vehicle = CreateVehicle(model, spot.x, spot.y, spot.z, spot.h or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    SetVehicleOnGroundProperly(vehicle)
    FreezeEntityPosition(vehicle, true)
    SetEntityInvincible(vehicle, true)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleLights(vehicle, 2)
    SetVehicleNumberPlateText(vehicle, 'LOCATION')
    rental.vehicle = vehicle

    local min, max = GetModelDimensions(model)
    rental.distance = math.max(4.0, #(max - min) * 1.15)
    rentalCamera()
end

local function teleport(coords, heading)
    local ped = PlayerPedId()
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)

    if heading then
        SetEntityHeading(ped, heading)
    end

    local timeout = GetGameTimer() + 3000

    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        Wait(0)
    end
end

-- Fin de l'aperçu : joueur ramené au comptoir, visible ; attend que le serveur voie la nouvelle position
local function closeRental()
    if not rental then
        return
    end

    local back = rental.back
    DoScreenFadeOut(250)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'rentalClose' })
    deletePreview()
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(rental.cam, false)
    rental = nil

    local ped = PlayerPedId()
    teleport(back, back.w)
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    DisplayRadar(true)
    Wait(600)
    DoScreenFadeIn(400)
end

local function rentalData(info)
    return {
        action = 'rentalOpen', label = info.label, header = info.header, vehicles = info.vehicles, active = info.active,
        cash = info.cash, bank = info.bank, maxPeriods = info.maxPeriods, currency = GlobalState.lunaticCurrency or '$',
    }
end

local function openRental(target)
    if rental then
        return
    end

    local info = lib.callback.await('lunatic_business:rentalOpen', false, target.shop.slug, target.index)

    if failed(info) then
        return
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    rental = {
        target = target, info = info, back = vector4(coords.x, coords.y, coords.z, GetEntityHeading(ped)),
        heading = (info.showroom.h or 0.0) + 145.0, pitch = 12.0, distance = 5.0, token = 0,
    }

    DoScreenFadeOut(250)

    while not IsScreenFadedOut() do
        Wait(0)
    end

    -- Joueur invisible et figé dans la vitrine, un peu à l'écart du véhicule
    local spot = info.showroom
    teleport(vector3(spot.x, spot.y, spot.z - 0.5))
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    DisplayRadar(false)

    rental.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    rentalCamera()
    RenderScriptCams(true, false, 0, true, true)

    -- La page choisit le premier véhicule et demande son aperçu
    SetNuiFocus(true, true)
    SendNUIMessage(rentalData(info))

    Wait(300)
    DoScreenFadeIn(400)

    CreateThread(function()
        while rental do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)
end

-- Compte à rebours de la location en cours, en petit à droite de la minimap
local rentalTimer = nil -- { label, endsAt }

-- Bord droit et bas de la minimap (fractions de l'écran), selon la zone de sécurité et le format d'écran
local function minimapCorner()
    local safezone = GetSafeZoneSize()
    local margin = (1.0 / 20.0) * (math.abs(safezone - 1.0) * 10)
    local width = 1.0 / (4 * GetAspectRatio(false))
    return margin + width, 1.0 - margin
end

RegisterNetEvent('lunatic_business:rentalTimer', function(timer)
    rentalTimer = timer and { label = timer.label, endsAt = GetGameTimer() + timer.remaining * 1000 } or nil

    if not rentalTimer then
        return SendNUIMessage({ action = 'rentalTimer' })
    end

    CreateThread(function()
        local current = rentalTimer

        while rentalTimer == current do
            local right, bottom = minimapCorner()
            SendNUIMessage({
                action = 'rentalTimer', label = current.label, remaining = math.floor((current.endsAt - GetGameTimer()) / 1000),
                left = right, bottom = bottom, hidden = IsRadarHidden() or IsPauseMenuActive(),
            })
            Wait(1000)
        end
    end)
end)

RegisterNUICallback('rentalPreview', function(data, cb)
    cb({})

    if not rental then
        return
    end

    for _, offer in ipairs(rental.info.vehicles) do
        if offer.id == tonumber(data.id) then
            previewVehicle(offer)
        end
    end
end)

-- Glisser : tourner autour du véhicule ; molette : zoom
RegisterNUICallback('rentalRotate', function(data, cb)
    cb({})

    if rental then
        rental.heading = rental.heading - (tonumber(data.dx) or 0) * 0.4
        rental.pitch = math.max(-5.0, math.min(60.0, rental.pitch + (tonumber(data.dy) or 0) * 0.25))
        rental.distance = math.max(2.5, math.min(14.0, rental.distance + (tonumber(data.zoom) or 0)))
        rentalCamera()
    end
end)

RegisterNUICallback('rentalClose', function(_, cb)
    cb({})
    closeRental()
end)

RegisterNUICallback('rentalRent', function(data, cb)
    cb({})

    if not rental then
        return
    end

    local target = rental.target
    closeRental()

    local result = lib.callback.await('lunatic_business:rent', false, target.shop.slug, target.index, tonumber(data.id), data.account == 'bank' and 'bank' or 'money', tonumber(data.periods) or 1)

    if not failed(result) then
        notify(('%s loué pour %d minutes%s (plaque %s).'):format(result.label, result.duration,
            result.price > 0 and (', ' .. money(result.price) .. (result.account == 'bank' and ' par carte' or ' en liquide')) or '', result.plate), 'success')
    end
end)

RegisterNUICallback('rentalReturn', function(_, cb)
    cb({})

    if not rental then
        return
    end

    local target = rental.target
    closeRental()

    local result = lib.callback.await('lunatic_business:rentReturn', false, target.shop.slug, target.index)

    if not failed(result) then
        notify(('%s rendu, merci !'):format(result.label), 'success')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and rental then
        deletePreview()
        SetNuiFocus(false, false)
        RenderScriptCams(false, false, 0, true, true)
        local ped = PlayerPedId()
        SetEntityCoordsNoOffset(ped, rental.back.x, rental.back.y, rental.back.z, false, false, false)
        FreezeEntityPosition(ped, false)
        SetEntityVisible(ped, true, false)
        SetEntityCollision(ped, true, true)
        SetEntityInvincible(ped, false)
        DisplayRadar(true)
        DoScreenFadeIn(0)
    end
end)

-- Grossiste : revente des objets que le joueur a sur lui
local function openBuyback(target)
    local info = lib.callback.await('lunatic_business:buybackOpen', false, target.shop.slug, target.index)

    if failed(info) then
        return
    end

    local options = {}

    for _, offer in ipairs(info.offers) do
        options[#options + 1] = {
            title = offer.count > 0 and ('%s × %d'):format(offer.label, offer.count) or offer.label,
            description = ("%s l'unité%s"):format(money(offer.price), offer.count > 0 and '' or " · vous n'en avez pas"),
            image = ('nui://ox_inventory/web/images/%s.png'):format(offer.item),
            icon = 'hand-holding-dollar',
            disabled = offer.count < 1,
            onSelect = function()
                local input = lib.inputDialog(offer.label, { { type = 'number', label = 'Quantité à revendre', default = offer.count, min = 1, max = offer.count, required = true } })

                if input and input[1] then
                    local result = lib.callback.await('lunatic_business:buybackSell', false, target.shop.slug, target.index, offer.item, math.floor(input[1]))

                    if not failed(result) then
                        notify(('%d × %s revendu pour %s.'):format(result.quantity, result.label, money(result.total)), 'success')
                    end
                end

                openBuyback(target)
            end,
        }
    end

    if #options == 0 then
        options[1] = { title = 'Ce grossiste ne rachète rien pour le moment.', readOnly = true }
    end

    lib.registerContext({ id = 'lb_buyback', title = info.label, options = options })
    lib.showContext('lb_buyback')
end

local function openShop(target)
    if target.shop.kind == 'buyback' then
        return openBuyback(target)
    end

    if target.shop.kind == 'items' then
        return exports.ox_inventory:openInventory('shop', { type = ('lunatic_%s'):format(target.shop.slug), id = target.index })
    end

    if target.shop.kind == 'rental' then
        return openRental(target)
    end

    notify(("« %s » n'est pas encore disponible."):format(target.label), 'info')
end

---------------------------------------------------------------------
-- Boucle : marqueurs et [E]
---------------------------------------------------------------------

CreateThread(function()
    local shown -- id du point affiché dans le texte d'aide
    local color = Config.MarkerColor

    while true do
        local sleep = 750
        local coords = GetEntityCoords(PlayerPedId())
        local closest, closestDistance

        for _, target in ipairs(shopTargets) do
            local distance = #(coords - vector3(target.x, target.y, target.z))

            if distance < Config.MarkerDistance then
                sleep = 0

                if not target.ped then
                    DrawMarker(25, target.x, target.y, target.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 1.1, 1.0, color[1], color[2], color[3], color[4], false, false, 2, false, nil, nil, false)
                end

                if distance < (target.radius or Config.InteractDistance) and (not closestDistance or distance < closestDistance) then
                    closest, closestDistance = { id = ('shop_%s_%d'):format(target.shop.slug, target.index), type = 'shop', label = target.label, target = target }, distance
                end
            end
        end

        local driving = IsPedInAnyVehicle(PlayerPedId(), false)

        for _, point in ipairs(points) do
            if point.type ~= 'blips' and visible(point) then
                local distance = #(coords - vector3(point.x, point.y, point.z))

                if distance < Config.MarkerDistance then
                    sleep = 0
                    DrawMarker(25, point.x, point.y, point.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 1.1, 1.0, color[1], color[2], color[3], color[4], false, false, 2, false, nil, nil, false)

                    local reach = driving and (point.type == 'garage' and Config.GarageStoreDistance or 0.0) or Config.InteractDistance

                    if distance < reach and (not closestDistance or distance < closestDistance) then
                        closest, closestDistance = point, distance
                    end
                end
            end
        end

        if closest then
            if shown ~= closest.id then
                shown = closest.id
                lib.showTextUI(('[E] %s'):format(closest.type == 'doorbell' and 'Sonner' or (closest.type == 'garage' and IsPedInAnyVehicle(PlayerPedId(), false)) and 'Ranger le véhicule' or closest.label))
            end

            if IsControlJustReleased(0, 38) and (closest.type == 'garage' or not IsPedInAnyVehicle(PlayerPedId(), false)) then
                local handler = handlers[closest.type]

                if closest.type == 'shop' then
                    openShop(closest.target)
                elseif handler then
                    handler(closest)
                else
                    notify(("« %s » n'est pas encore disponible."):format(closest.typeLabel or closest.type), 'info')
                end
            end
        elseif shown then
            shown = nil
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        lib.hideTextUI()

        for _, blip in ipairs(shopBlips) do
            RemoveBlip(blip)
        end

        for _, blip in ipairs(structureBlips) do
            RemoveBlip(blip)
        end

        for id in pairs(shopPeds) do
            deleteShopPed(id)
        end
    end
end)
