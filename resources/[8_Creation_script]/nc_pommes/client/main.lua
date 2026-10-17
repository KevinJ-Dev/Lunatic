--[[
    nc_pommes - NightCraft Studio
    Cote client : marqueurs, touche [E], animations, menus.
]]

local STATE_KEY = 'nc_pommes:trees'

local busy      = false
local promptId  = nil
local promptTxt = nil
local sellPed   = nil
local blips     = {}

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------
local function notify(kind, key, ...)
    lib.notify({
        title       = Locale('title'),
        description = Locale(key, ...),
        type        = kind,
    })
end

local function showPrompt(id, text)
    if promptId == id and promptTxt == text then return end
    promptId, promptTxt = id, text
    lib.showTextUI(text)
end

local function hidePrompt(id)
    if promptId ~= id then return end
    promptId, promptTxt = nil, nil
    lib.hideTextUI()
end

local function hasJob()
    if not Config.Job then return true end
    local data = ESX.GetPlayerData()
    return IsJobAllowed(data and data.job and data.job.name)
end

local function countItem(item)
    return exports.ox_inventory:Search('count', item) or 0
end

local function isTreeFull(id)
    local state = GlobalState[STATE_KEY]
    return not state or state[id] ~= false
end

local function drawMarker(coords, color)
    local m = Config.Marker
    if not m.enabled then return end

    DrawMarker(m.type, coords.x, coords.y, coords.z + 0.15, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
        m.scale, m.scale, m.scale, color.r, color.g, color.b, color.a, true, true, 2, false, nil, nil, false)
end

local function addBlip(cfg, coords)
    if not cfg or not cfg.enabled then return end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, cfg.sprite)
    SetBlipColour(blip, cfg.color)
    SetBlipScale(blip, cfg.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(cfg.label)
    EndTextCommandSetBlipName(blip)

    blips[#blips + 1] = blip
end

local function progress(label, duration, anim)
    return lib.progressCircle({
        duration     = duration,
        label        = label,
        position     = 'bottom',
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = true },
        anim         = anim,
    })
end

---------------------------------------------------------------------------
-- 1) RECOLTE
---------------------------------------------------------------------------
local function harvest(id)
    if busy then return end
    busy = true

    local ok, duration = lib.callback.await('nc_pommes:harvest:start', false, id)
    if ok then
        if progress(Locale('progress_harvest'), duration, Config.Harvest.anim) then
            TriggerServerEvent('nc_pommes:harvest:finish')
        else
            TriggerServerEvent('nc_pommes:cancel')
            notify('inform', 'cancelled')
        end
    end

    busy = false
end

---------------------------------------------------------------------------
-- 2) PRESSAGE
---------------------------------------------------------------------------
local function process()
    if busy then return end
    busy = true

    local cfg     = Config.Process
    local maximum = math.min(math.floor(countItem(Config.Items.apple) / cfg.input), cfg.maxBatch)

    if maximum < 1 then
        notify('error', 'not_enough_apples', cfg.input)
        busy = false
        return
    end

    local count = 1
    if maximum > 1 then
        local input = lib.inputDialog(Locale('process_title'), {
            { type = 'slider', label = Locale('process_amount'), min = 1, max = maximum, default = maximum, step = 1 },
        })

        if not input then
            busy = false
            return
        end

        count = math.floor(tonumber(input[1]) or 0)
    end

    local ok, duration = lib.callback.await('nc_pommes:process:start', false, count)
    if ok then
        if progress(Locale('progress_process'), duration, cfg.anim) then
            TriggerServerEvent('nc_pommes:process:finish')
        else
            TriggerServerEvent('nc_pommes:cancel')
            notify('inform', 'cancelled')
        end
    end

    busy = false
end

---------------------------------------------------------------------------
-- 3) VENTE
---------------------------------------------------------------------------
local function sellItem(entry, owned)
    local input = lib.inputDialog(Locale('sell_title'), {
        { type = 'number', label = Locale('sell_amount'), min = 1, max = owned, default = owned },
    })
    if not input then return end

    local count = math.floor(tonumber(input[1]) or 0)
    if count < 1 then return end

    lib.callback.await('nc_pommes:sell', false, entry.item, count)
end

local function openSellMenu()
    local options = {}

    for i = 1, #Config.Sell.items do
        local entry = Config.Sell.items[i]
        local owned = countItem(entry.item)

        if owned > 0 then
            local data  = exports.ox_inventory:Items(entry.item)
            local label = data and data.label or entry.item

            options[#options + 1] = {
                title       = label,
                description = Locale('sell_line', entry.price, owned),
                icon        = 'apple-whole',
                onSelect    = function()
                    sellItem(entry, owned)
                end,
            }
        end
    end

    if #options == 0 then
        notify('error', 'nothing_to_sell')
        return
    end

    lib.registerContext({
        id      = 'nc_pommes_sell',
        title   = Locale('sell_title'),
        options = options,
    })
    lib.showContext('nc_pommes_sell')
end

local function spawnSellPed()
    if sellPed then return end

    local c     = Config.Sell.coords
    local model = joaat(Config.Sell.ped.model)

    lib.requestModel(model, 10000)
    sellPed = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetModelAsNoLongerNeeded(model)

    SetEntityInvincible(sellPed, true)
    FreezeEntityPosition(sellPed, true)
    SetBlockingOfNonTemporaryEvents(sellPed, true)

    if Config.Sell.ped.scenario then
        TaskStartScenarioInPlace(sellPed, Config.Sell.ped.scenario, 0, true)
    end
end

local function deleteSellPed()
    if sellPed and DoesEntityExist(sellPed) then
        DeleteEntity(sellPed)
    end
    sellPed = nil
end

---------------------------------------------------------------------------
-- Points d'interaction
---------------------------------------------------------------------------
local function interactionPoint(id, coords, opts)
    local point = lib.points.new({
        coords   = vec3(coords.x, coords.y, coords.z),
        distance = opts.distance or Config.Marker.drawDistance,
    })

    function point:nearby()
        if not hasJob() then
            hidePrompt(id)
            return
        end

        local active, text = opts.state()

        if opts.marker then
            drawMarker(self.coords, active and Config.Marker.color or Config.Marker.emptyColor)
        end

        if busy or self.currentDistance > Config.Marker.interact then
            hidePrompt(id)
            return
        end

        showPrompt(id, text)

        if active and IsControlJustReleased(0, Config.InteractKey) then
            hidePrompt(id)
            CreateThread(opts.action)
        end
    end

    function point:onExit()
        hidePrompt(id)
    end

    return point
end

CreateThread(function()
    -- Arbres
    for id = 1, #Config.Harvest.trees do
        interactionPoint('tree' .. id, Config.Harvest.trees[id], {
            marker = true,
            state  = function()
                if isTreeFull(id) then
                    return true, Locale('prompt_harvest')
                end
                return false, Locale('prompt_empty')
            end,
            action = function()
                harvest(id)
            end,
        })
    end

    -- Pressoir
    interactionPoint('process', Config.Process.coords, {
        marker = true,
        state  = function()
            return true, Locale('prompt_process')
        end,
        action = process,
    })

    -- Grossiste : un point large pour faire apparaitre le PNJ, un point court pour lui parler
    local sell = Config.Sell.coords

    local pedPoint = lib.points.new({ coords = vec3(sell.x, sell.y, sell.z), distance = 60.0 })
    function pedPoint:onEnter() spawnSellPed() end
    function pedPoint:onExit() deleteSellPed() end

    interactionPoint('sell', sell, {
        distance = 3.0,
        marker   = false,
        state    = function()
            return true, Locale('prompt_sell')
        end,
        action = openSellMenu,
    })

    -- Blips
    addBlip(Config.Harvest.blip, Config.Harvest.blip.coords)
    addBlip(Config.Process.blip, Config.Process.coords)
    addBlip(Config.Sell.blip, Config.Sell.coords)
end)

---------------------------------------------------------------------------
-- Outil de placement (Config.Debug = true)
---------------------------------------------------------------------------
if Config.Debug then
    RegisterCommand('pommepos', function()
        local c    = GetEntityCoords(PlayerPedId())
        local line = ('vec3(%.2f, %.2f, %.2f),'):format(c.x, c.y, c.z)

        lib.setClipboard(line)
        print('[nc_pommes] ' .. line)
        lib.notify({ title = Locale('title'), description = line, type = 'inform' })
    end, false)
end

---------------------------------------------------------------------------
-- Nettoyage
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    deleteSellPed()
    lib.hideTextUI()

    for i = 1, #blips do
        RemoveBlip(blips[i])
    end
end)
