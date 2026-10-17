--[[
    nc_pommes - NightCraft Studio
    Cote serveur : c'est ici que tout est verifie (distance, temps, inventaire).
    Le client ne decide jamais de ce qu'il recoit.
]]

local STATE_KEY = 'nc_pommes:trees'
local TOLERANCE = 750      -- ms de marge sur la duree des actions (latence)
local STALE     = 15000    -- ms apres lesquelles une action jamais terminee est oubliee

local trees    = {}   -- [id] = true (pommes dispo) / false (vide)
local locks    = {}   -- [id] = { src = joueur, expires = timer }
local pending  = {}   -- [src] = { action, id, count, started, duration }
local lastSell = {}   -- [src] = timer

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------
local function notify(src, kind, key, ...)
    TriggerClientEvent('ox_lib:notify', src, {
        title       = Locale('title'),
        description = Locale(key, ...),
        type        = kind,
    })
end

local function syncTrees()
    GlobalState[STATE_KEY] = trees
end

local function isNear(src, coords)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local pos = GetEntityCoords(ped)
    return #(pos - vector3(coords.x, coords.y, coords.z)) <= Config.MaxDistance
end

local function getAllowedPlayer(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end

    if not IsJobAllowed(xPlayer.job and xPlayer.job.name) then
        notify(src, 'error', 'no_job')
        return nil
    end

    return xPlayer
end

local function countItem(src, item)
    return exports.ox_inventory:Search(src, 'count', item) or 0
end

local function clearPending(src)
    local p = pending[src]
    if p and p.action == 'harvest' then
        local lock = locks[p.id]
        if lock and lock.src == src then locks[p.id] = nil end
    end
    pending[src] = nil
end

-- true si le joueur a deja une action en cours (les actions abandonnees sont nettoyees)
local function isBusy(src)
    local p = pending[src]
    if not p then return false end

    if GetGameTimer() - p.started > p.duration + STALE then
        clearPending(src)
        return false
    end

    return true
end

-- Recupere l'action en attente et verifie qu'elle a bien dure le temps prevu
local function takePending(src, action)
    local p = pending[src]
    if not p or p.action ~= action then return nil end

    local elapsed = GetGameTimer() - p.started
    clearPending(src)

    if elapsed < p.duration - TOLERANCE then return nil end
    return p
end

---------------------------------------------------------------------------
-- Initialisation des arbres
---------------------------------------------------------------------------
for i = 1, #Config.Harvest.trees do
    trees[i] = true
end
syncTrees()

---------------------------------------------------------------------------
-- 1) RECOLTE
---------------------------------------------------------------------------
lib.callback.register('nc_pommes:harvest:start', function(src, id)
    if type(id) ~= 'number' then return false end

    local coords = Config.Harvest.trees[id]
    if not coords or isBusy(src) then return false end
    if not getAllowedPlayer(src) then return false end
    if not isNear(src, coords) then return false end

    if not trees[id] then
        notify(src, 'error', 'tree_empty')
        return false
    end

    local now  = GetGameTimer()
    local lock = locks[id]
    if lock and lock.src ~= src and lock.expires > now then
        notify(src, 'error', 'tree_busy')
        return false
    end

    if not exports.ox_inventory:CanCarryItem(src, Config.Items.apple, Config.Harvest.max) then
        notify(src, 'error', 'inventory_full')
        return false
    end

    locks[id]    = { src = src, expires = now + Config.Harvest.duration + STALE }
    pending[src] = { action = 'harvest', id = id, started = now, duration = Config.Harvest.duration }

    return true, Config.Harvest.duration
end)

RegisterNetEvent('nc_pommes:harvest:finish', function()
    local src = source
    local p   = takePending(src, 'harvest')
    if not p then return end

    local id = p.id
    if not trees[id] or not isNear(src, Config.Harvest.trees[id]) then return end

    local amount = math.random(Config.Harvest.min, Config.Harvest.max)
    if not exports.ox_inventory:AddItem(src, Config.Items.apple, amount) then
        notify(src, 'error', 'inventory_full')
        return
    end

    trees[id] = false
    syncTrees()

    SetTimeout(Config.Harvest.respawn * 1000, function()
        trees[id] = true
        syncTrees()
    end)

    notify(src, 'success', 'harvest_done', amount)
end)

---------------------------------------------------------------------------
-- 2) PRESSAGE
---------------------------------------------------------------------------
lib.callback.register('nc_pommes:process:start', function(src, count)
    count = math.floor(tonumber(count) or 0)
    if count < 1 or count > Config.Process.maxBatch then return false end

    if isBusy(src) then return false end
    if not getAllowedPlayer(src) then return false end
    if not isNear(src, Config.Process.coords) then return false end

    local need = count * Config.Process.input
    local give = count * Config.Process.output

    if countItem(src, Config.Items.apple) < need then
        notify(src, 'error', 'not_enough_apples', Config.Process.input)
        return false
    end

    if not exports.ox_inventory:CanSwapItem(src, Config.Items.apple, need, Config.Items.juice, give) then
        notify(src, 'error', 'inventory_full')
        return false
    end

    local duration = count * Config.Process.durationPerUnit
    pending[src] = { action = 'process', count = count, started = GetGameTimer(), duration = duration }

    return true, duration
end)

RegisterNetEvent('nc_pommes:process:finish', function()
    local src = source
    local p   = takePending(src, 'process')
    if not p then return end

    if not isNear(src, Config.Process.coords) then return end

    local need = p.count * Config.Process.input
    local give = p.count * Config.Process.output

    if countItem(src, Config.Items.apple) < need then
        notify(src, 'error', 'not_enough_apples', Config.Process.input)
        return
    end

    if not exports.ox_inventory:RemoveItem(src, Config.Items.apple, need) then return end

    if not exports.ox_inventory:AddItem(src, Config.Items.juice, give) then
        -- pas de place pour le jus : on rend les pommes
        exports.ox_inventory:AddItem(src, Config.Items.apple, need)
        notify(src, 'error', 'inventory_full')
        return
    end

    notify(src, 'success', 'process_done', give)
end)

---------------------------------------------------------------------------
-- 3) VENTE
---------------------------------------------------------------------------
lib.callback.register('nc_pommes:sell', function(src, itemName, count)
    count = math.floor(tonumber(count) or 0)
    if type(itemName) ~= 'string' or count < 1 or count > 10000 then return false end

    local now = GetGameTimer()
    if lastSell[src] and now - lastSell[src] < 500 then return false end
    lastSell[src] = now

    local entry
    for i = 1, #Config.Sell.items do
        if Config.Sell.items[i].item == itemName then
            entry = Config.Sell.items[i]
            break
        end
    end
    if not entry then return false end

    if isBusy(src) then return false end

    local xPlayer = getAllowedPlayer(src)
    if not xPlayer then return false end
    if not isNear(src, Config.Sell.coords) then return false end

    if countItem(src, itemName) < count then
        notify(src, 'error', 'not_enough_items')
        return false
    end

    if not exports.ox_inventory:RemoveItem(src, itemName, count) then return false end

    local total = entry.price * count
    xPlayer.addAccountMoney(Config.Sell.account, total, 'nc_pommes')

    local item  = exports.ox_inventory:Items(itemName)
    local label = item and item.label or itemName
    notify(src, 'success', 'sold', count, label, total)

    return true
end)

---------------------------------------------------------------------------
-- Annulation / deconnexion
---------------------------------------------------------------------------
RegisterNetEvent('nc_pommes:cancel', function()
    clearPending(source)
end)

AddEventHandler('playerDropped', function()
    local src = source
    clearPending(src)
    lastSell[src] = nil
end)
