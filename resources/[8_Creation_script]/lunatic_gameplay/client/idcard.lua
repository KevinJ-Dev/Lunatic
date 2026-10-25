-- Carte d'identité côté client : menu de l'objet (regarder, montrer aux proches), affichage de la carte (page web),
-- guichets de documents (marqueur, [E], PNJ, blip) et point GPS vers le guichet pour les nouveaux arrivants.

local showing = false

local function display(identity)
    SendNUIMessage({ action = 'idcard', identity = identity })
    showing = true
    local closeAt = GetGameTimer() + (tonumber(FeaturesOf('idcard').duration) or 10) * 1000

    CreateThread(function()
        while showing and GetGameTimer() < closeAt do
            DisableControlAction(0, 177, true)

            if IsDisabledControlJustReleased(0, 177) then -- Retour arrière
                break
            end

            Wait(0)
        end

        showing = false
        SendNUIMessage({ action = 'idcardHide' })
    end)
end

RegisterNetEvent('lunatic_gameplay:idcardDisplay', function(identity)
    if type(identity) == 'table' then
        display(identity)
    end
end)

RegisterNetEvent('lunatic_gameplay:idcardMenu', function()
    lib.registerContext({
        id = 'lg_idcard', title = "Carte d'identité",
        options = {
            { title = 'Regarder ma carte', icon = 'id-card', onSelect = function()
                local identity = lib.callback.await('lunatic_gameplay:idcard', false)

                if identity then
                    display(identity)
                end
            end },
            { title = 'Montrer aux personnes proches', icon = 'hand', onSelect = function()
                TriggerServerEvent('lunatic_gameplay:idcardShow')
            end },
        },
    })
    lib.showContext('lg_idcard')
end)

---------------------------------------------------------------------
-- Guichets de documents
---------------------------------------------------------------------

local function takeCard(index, account)
    local result = lib.callback.await('lunatic_gameplay:officeIdcard', false, index, account)

    if not result or result.error then
        return Notify(result and result.error or 'Guichet indisponible.', 'error')
    end

    Notify(result.price > 0 and ("Duplicata de carte d'identité remis (%d %s)."):format(result.price, GlobalState.lunaticCurrency or '$')
        or "Voici votre carte d'identité.", 'success')
end

local function openOffice(index, office)
    local info = lib.callback.await('lunatic_gameplay:officeInfo', false, index)

    if not info then
        return Notify('Vous êtes trop loin du guichet.', 'error')
    end

    local options = {}
    local currency = GlobalState.lunaticCurrency or '$'

    if not info.identity then
        options[1] = { title = "Carte d'identité", description = "Vous n'avez pas encore d'identité.", icon = 'id-card', disabled = true }
    elseif info.hasCard then
        options[1] = { title = "Carte d'identité", description = 'Vous avez déjà votre carte sur vous.', icon = 'id-card', disabled = true }
    elseif info.price <= 0 then
        options[1] = { title = "Retirer ma carte d'identité", description = 'Gratuit : première carte', icon = 'id-card', onSelect = function() takeCard(index, 'money') end }
    else
        options[1] = { title = ('Duplicata en liquide (%d %s)'):format(info.price, currency), description = ('Liquide : %d %s'):format(info.cash, currency),
            icon = 'money-bill', disabled = info.cash < info.price, onSelect = function() takeCard(index, 'money') end }
        options[2] = { title = ('Duplicata par carte (%d %s)'):format(info.price, currency), description = ('Banque : %d %s'):format(info.bank, currency),
            icon = 'credit-card', disabled = info.bank < info.price, onSelect = function() takeCard(index, 'bank') end }
    end

    lib.registerContext({ id = 'lg_office', title = office.label, options = options })
    lib.showContext('lg_office')
end

-- Blips et PNJ des guichets, refaits quand le panel change la liste
local blips, peds = {}, {}

local function refreshOffices()
    for _, blip in ipairs(blips) do
        RemoveBlip(blip)
    end

    for _, ped in ipairs(peds) do
        DeleteEntity(ped)
    end

    blips, peds = {}, {}

    for _, office in ipairs(DocumentOffices()) do
        local blip = AddBlipForCoord(office.x, office.y, office.z)
        SetBlipSprite(blip, Config.OfficeBlip.sprite)
        SetBlipColour(blip, Config.OfficeBlip.color)
        SetBlipScale(blip, Config.OfficeBlip.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Guichet des documents')
        EndTextCommandSetBlipName(blip)
        blips[#blips + 1] = blip

        local model = office.ped and office.ped ~= '' and joaat(office.ped)

        if model and IsModelInCdimage(model) and lib.requestModel(model, 5000) then
            local ped = CreatePed(4, model, office.x, office.y, office.z - 1.0, office.h or 0.0, false, false)
            SetModelAsNoLongerNeeded(model)
            FreezeEntityPosition(ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            peds[#peds + 1] = ped
        end
    end
end

CreateThread(refreshOffices)
AddStateBagChangeHandler('lunaticDocumentOffices', 'global', function()
    SetTimeout(500, refreshOffices)
end)

-- Marqueur devant le guichet et [E]
CreateThread(function()
    while true do
        local wait = 1000
        local coords = GetEntityCoords(PlayerPedId())

        for index, office in ipairs(DocumentOffices()) do
            local distance = #(coords - vector3(office.x, office.y, office.z))

            if distance < 10.0 then
                wait = 0
                DrawMarker(1, office.x, office.y, office.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 0.8, 0.25, 150, 80, 255, 110, false, false, 2, false, nil, nil, false)

                if distance <= Config.OfficeDistance then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName(('~INPUT_CONTEXT~ %s'):format(office.label))
                    EndTextCommandDisplayHelp(0, false, true, -1)

                    if IsControlJustReleased(0, 38) then
                        openOffice(index, office)
                    end
                end
            end
        end

        Wait(wait)
    end
end)

-- Nouveau venu sans carte : point GPS vers le guichet le plus proche
RegisterNetEvent('lunatic_gameplay:officeGuide', function()
    local coords = GetEntityCoords(PlayerPedId())
    local best, bestDistance

    for _, office in ipairs(DocumentOffices()) do
        local distance = #(coords - vector3(office.x, office.y, office.z))

        if not bestDistance or distance < bestDistance then
            best, bestDistance = office, distance
        end
    end

    if best then
        SetNewWaypoint(best.x + 0.0, best.y + 0.0)
        Notify(("Récupérez votre carte d'identité au guichet : %s (point GPS)."):format(best.label), 'info')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for _, ped in ipairs(peds) do
            DeleteEntity(ped)
        end
    end
end)
