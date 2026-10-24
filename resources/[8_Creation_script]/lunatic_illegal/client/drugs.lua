-- Drogues côté jeu : laboratoires ([E] pour les membres du bon type de crew) et vente aux passants ([E] près d'un PNJ).

local drugs = {}
local soldTo = {} -- passants déjà démarchés (une seule tentative par passant)
local busy = false
local staffView = false -- activée depuis le panel (onglet Drogues) : tous les laboratoires visibles, sans production

RegisterNetEvent('lunatic_illegal:staffView', function(enabled)
    staffView = enabled == true
    notify(staffView and 'Vue staff : tous les laboratoires sont affichés en orange.' or 'Vue staff des laboratoires désactivée.', 'info')
end)

local function notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

local function money(amount)
    return ('%s %s'):format(tostring(math.floor(amount or 0)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', ''), GlobalState.lunaticCurrency or '$')
end

local function itemLabel(name)
    local item = exports.ox_inventory:Items(name)
    return item and item.label or name
end

-- Diagnostic F8 : pourquoi un laboratoire est visible ou non (crew, type, emplacements)
local lastReport

local function report()
    local crew = LocalPlayer.state.crew
    local labs, placed, mine = 0, 0, 0

    for _, drug in ipairs(drugs) do
        for _, lab in ipairs(drug.labs or {}) do
            labs = labs + 1

            if #(lab.locations or {}) > 0 then
                placed = placed + 1

                if drug.active and crew and lab.crewType == crew.lab then
                    mine = mine + 1
                end
            end
        end
    end

    local text = ('[lunatic_illegal] Drogues : %d drogue(s), %d laboratoire(s) dont %d placé(s). Votre crew : %s. Laboratoires visibles pour vous : %d.'):format(
        #drugs, labs, placed, crew and ('%s (type %s)'):format(crew.label, crew.type) or 'aucun', mine)

    if text ~= lastReport then
        lastReport = text
        print(text)
    end
end

AddStateBagChangeHandler('lunaticDrugs', 'global', function(_, _, value)
    drugs = type(value) == 'table' and value or {}
    report()
end)

AddStateBagChangeHandler('crew', ('player:%d'):format(GetPlayerServerId(PlayerId())), function()
    Wait(0)
    report()
end)

CreateThread(function()
    drugs = GlobalState.lunaticDrugs or {}
    Wait(3000)
    report()
end)

---------------------------------------------------------------------
-- Laboratoires
---------------------------------------------------------------------

local function produce(location)
    if busy then
        return
    end

    busy = true
    local start = lib.callback.await('lunatic_illegal:labStart', false, location.id)

    if not start or not start.ok then
        busy = false
        return notify(start and start.error or 'Production impossible.', 'error')
    end

    local done = lib.progressBar({
        duration = start.duration * 1000,
        label = ('Production : %d × %s'):format(start.output, start.label),
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    })

    if not done then
        TriggerServerEvent('lunatic_illegal:labCancel')
        busy = false
        return notify('Production annulée.', 'error')
    end

    local result = lib.callback.await('lunatic_illegal:labFinish', false, location.id)
    busy = false

    if result and result.ok then
        notify(('%d × %s produit.'):format(result.output, result.label), 'success')
    else
        notify(result and result.error or 'Production impossible.', 'error')
    end
end

-- Emplacements des laboratoires du type de crew du joueur ; en vue staff, tous les autres aussi (sans production)
local function myLabs()
    local crew = LocalPlayer.state.crew
    local list = {}

    for _, drug in ipairs(drugs) do
        for _, lab in ipairs(drug.labs or {}) do
            local usable = drug.active and crew and lab.crewType == crew.lab

            if usable or staffView then
                for _, location in ipairs(lab.locations or {}) do
                    list[#list + 1] = {
                        location = location,
                        label = itemLabel(drug.item),
                        staffOnly = not usable,
                        info = ('%s · crew %s%s'):format(itemLabel(drug.item), lab.crewTypeLabel or lab.crewType, drug.active and '' or ' · drogue désactivée'),
                    }
                end
            end
        end
    end

    return list
end

---------------------------------------------------------------------
-- Vente aux passants
---------------------------------------------------------------------

-- Drogue active que le joueur possède (la première trouvée)
local function drugInPocket()
    for _, drug in ipairs(drugs) do
        if drug.active and (exports.ox_inventory:Search('count', drug.item) or 0) >= drug.volumeMin then
            return drug
        end
    end
end

local function closestBuyer(coords)
    local best, bestDistance

    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and not soldTo[ped] and IsPedHuman(ped) and not IsPedDeadOrDying(ped, true)
            and not IsPedInAnyVehicle(ped, false) and not IsEntityAMissionEntity(ped) then
            local distance = #(coords - GetEntityCoords(ped))

            if distance < Config.SellDistance and (not bestDistance or distance < bestDistance) then
                best, bestDistance = ped, distance
            end
        end
    end

    return best
end

local function sellTo(ped, drug)
    busy = true
    soldTo[ped] = true

    -- Le passant s'arrête et fait face au vendeur
    ClearPedTasks(ped)
    TaskTurnPedToFaceEntity(ped, PlayerPedId(), 1500)
    TaskTurnPedToFaceEntity(PlayerPedId(), ped, 1500)
    Wait(1500)
    FreezeEntityPosition(ped, true)

    local result = lib.callback.await('lunatic_illegal:sell', false, drug.id, GetEntityCoords(ped))

    FreezeEntityPosition(ped, false)
    TaskWanderStandard(ped, 10.0, 10)
    busy = false

    if not result or not result.ok then
        return notify(result and result.error or 'Vente impossible.', 'error')
    end

    if result.refused then
        return notify("Le passant n'est pas intéressé.", 'info')
    end

    notify(('Vendu %d × %s pour %s.%s'):format(result.quantity, result.label, money(result.total),
        result.territory and (' Bonus du territoire « %s ».'):format(result.territory) or ''), 'success')
end

---------------------------------------------------------------------
-- Boucle : [E] au laboratoire ou près d'un passant
---------------------------------------------------------------------

CreateThread(function()
    local shown -- texte affiché
    local nextScan = 0
    local labs, drug = {}, nil

    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local text, action

        if GetGameTimer() > nextScan then
            nextScan = GetGameTimer() + 1000
            labs = myLabs()
            drug = drugInPocket()
        end

        if not busy and not IsPedInAnyVehicle(ped, false) then
            for _, entry in ipairs(labs) do
                local location = entry.location
                local distance = #(coords - vector3(location.x, location.y, location.z))

                if entry.staffOnly then
                    -- Vue staff : visible de plus loin, en orange, sans [E]
                    if distance < 60.0 then
                        sleep = 0
                        DrawMarker(25, location.x, location.y, location.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 1.1, 1.0, 242, 160, 60, 140, false, false, 2, false, nil, nil, false)

                        if distance < Config.LabDistance then
                            text = ('[Vue staff] Laboratoire : %s'):format(entry.info)
                        end
                    end
                elseif distance < 15.0 then
                    sleep = 0
                    DrawMarker(25, location.x, location.y, location.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1, 1.1, 1.0, 120, 200, 90, 110, false, false, 2, false, nil, nil, false)

                    if distance < Config.LabDistance then
                        text, action = ('[E] Produire : %s'):format(entry.label), function() produce(location) end
                    end
                end
            end

            if not text and drug then
                sleep = 250
                local buyer = closestBuyer(coords)

                if buyer then
                    sleep = 0
                    text, action = ('[E] Proposer : %s'):format(itemLabel(drug.item)), function() sellTo(buyer, drug) end
                end
            end
        end

        if text then
            if shown ~= text then
                shown = text
                lib.showTextUI(text)
            end

            if action and IsControlJustReleased(0, 38) then
                lib.hideTextUI()
                shown = nil
                CreateThread(action)
            end
        elseif shown then
            shown = nil
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)

-- Alerte reçue par la police : point temporaire sur la carte
RegisterNetEvent('lunatic_illegal:drugAlert', function(alert)
    notify('Signalement : activité suspecte (deal) dans le secteur indiqué sur la carte.', 'error')
    local blip = AddBlipForRadius(alert.x + 0.0, alert.y + 0.0, 0.0, 80.0)
    SetBlipColour(blip, 1)
    SetBlipAlpha(blip, 120)
    local center = AddBlipForCoord(alert.x + 0.0, alert.y + 0.0, 0.0)
    SetBlipSprite(center, 51)
    SetBlipColour(center, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Deal signalé')
    EndTextCommandSetBlipName(center)

    SetTimeout(Config.AlertDuration * 1000, function()
        RemoveBlip(blip)
        RemoveBlip(center)
    end)
end)
