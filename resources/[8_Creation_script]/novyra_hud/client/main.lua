-- novyra_hud | NightCraft Studio

local playerLoaded = false
local nuiReady     = false
local userEnabled  = true
local visible      = false
local hiddenBy     = {} -- ressources qui ont demande de masquer le HUD
local needs        = {} -- faim / soif, de 0 a 100
local last         = {} -- dernieres valeurs envoyees a l'interface
local minimapRefreshed = false
local anchorDirty       = true -- renvoyer la position de la minimap a l'interface

-- ---------------------------------------------------------------------------
-- Utilitaires
-- ---------------------------------------------------------------------------

local function round(value)
    return math.floor(value + 0.5)
end

local function clamp(value)
    if value < 0 then return 0 end
    if value > 100 then return 100 end
    return value
end

local function sendConfig()
    local statuses = {}

    for name, cfg in pairs(Config.Statuses) do
        statuses[name] = { enabled = cfg.enabled, color = cfg.color }
    end

    SendNUIMessage({
        action     = 'config',
        statuses   = statuses,
        order      = Config.Order,
        position   = Config.Position,
        style      = Config.Style,
        percent    = Config.ShowPercent,
        animations = Config.Animations,
        scale      = Config.Scale,
        low        = Config.LowThreshold,
    })
end

local function shouldShow()
    return playerLoaded
        and userEnabled
        and next(hiddenBy) == nil
        and not IsPauseMenuActive()
        and not IsScreenFadedOut()
end

-- ---------------------------------------------------------------------------
-- Lecture des statuts
-- ---------------------------------------------------------------------------

local function readStatuses()
    local ped    = PlayerPedId()
    local player = PlayerId()
    local values = {}

    if IsEntityDead(ped) then
        values.health = 0
    else
        local maxHealth = GetEntityMaxHealth(ped)
        values.health = (GetEntityHealth(ped) - 100) / math.max(1, maxHealth - 100) * 100
    end

    values.armor   = GetPedArmour(ped)
    values.hunger  = needs.hunger
    values.thirst  = needs.thirst
    values.stamina = 100 - GetPlayerSprintStaminaRemaining(player)

    if IsPedSwimmingUnderWater(ped) then
        values.oxygen = GetPlayerUnderwaterTimeRemaining(player) / Config.MaxUnderwaterTime * 100
    end

    return values
end

-- Renvoie uniquement ce qui a change depuis le dernier envoi (false = cercle cache)
local function getChanges()
    local values  = readStatuses()
    local changes = nil

    for name, cfg in pairs(Config.Statuses) do
        local value = false

        if cfg.enabled and values[name] ~= nil then
            value = round(clamp(values[name]))

            if (cfg.hideWhenFull and value >= 100) or (cfg.hideWhenEmpty and value <= 0) then
                value = false
            end
        end

        if last[name] ~= value then
            last[name] = value
            changes = changes or {}
            changes[name] = value
        end
    end

    return changes
end

-- ---------------------------------------------------------------------------
-- Boucle principale
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local show = nuiReady and shouldShow()

        if show ~= visible then
            visible = show
            if show then last = {} end
            SendNUIMessage({ action = 'visible', state = show })
        end

        if visible then
            local changes = getChanges()
            if changes then
                SendNUIMessage({ action = 'update', data = changes })
            end
        end

        Wait(visible and Config.UpdateInterval or 500)
    end
end)

-- ---------------------------------------------------------------------------
-- Interface prete
-- ---------------------------------------------------------------------------

RegisterNUICallback('ready', function(_, cb)
    sendConfig()
    anchorDirty = true
    last     = {}
    visible  = false
    nuiReady = true
    cb('ok')
end)

-- ---------------------------------------------------------------------------
-- Faim / soif
--   esx_status present  -> le HUD affiche ses valeurs
--   esx_status absent   -> le HUD gere lui-meme la faim et la soif (mode integre)
-- ---------------------------------------------------------------------------

local builtin    = false -- true = faim / soif geres par le HUD
local esxFeeding = false -- true = esx_status envoie des valeurs
local identifier = nil
local wasDead    = false

local function isNeed(name)
    return name == 'hunger' or name == 'thirst'
end

local function kvpKey()
    local id = identifier or (ESX.PlayerData and ESX.PlayerData.identifier) or 'default'
    return 'needs:' .. tostring(id)
end

-- Sauvegarde par personnage, sur le PC du joueur
local function saveNeeds()
    if builtin and needs.hunger and needs.thirst then
        SetResourceKvp(kvpKey(), json.encode({ hunger = needs.hunger, thirst = needs.thirst }))
    end
end

local function startBuiltin()
    if builtin then return end

    local saved = GetResourceKvpString(kvpKey())
    local data  = saved and json.decode(saved) or {}

    needs.hunger = clamp(tonumber(data.hunger) or 100)
    needs.thirst = clamp(tonumber(data.thirst) or 100)
    builtin = true

    print('[novyra_hud] esx_status ne fournit pas la faim / soif : le HUD les gere lui-meme (mode integre).')
end

-- Valeurs envoyees par esx_status (+ esx_basicneeds)
AddEventHandler('esx_status:onTick', function(data)
    if Config.Needs.Mode == 'builtin' then return end

    for i = 1, #data do
        local status = data[i]
        if isNeed(status.name) then
            needs[status.name] = status.percent
            esxFeeding = true
            builtin = false
        end
    end
end)

-- Mode integre : memes events que esx_status, pour que la nourriture et les boissons
-- (ox_inventory, autres scripts) fonctionnent sans rien changer.
-- Les quantites sont sur l'echelle esx_status : 1 000 000 = 100 %.
local function addNeed(name, amount)
    amount = tonumber(amount)

    if builtin and isNeed(name) and amount then
        needs[name] = clamp(needs[name] + amount / 10000)
    end
end

RegisterNetEvent('esx_status:add', function(name, amount)
    addNeed(name, amount)
end)

RegisterNetEvent('esx_status:remove', function(name, amount)
    addNeed(name, -(tonumber(amount) or 0))
end)

RegisterNetEvent('esx_status:set', function(name, amount)
    amount = tonumber(amount)

    if builtin and isNeed(name) and amount then
        needs[name] = clamp(amount / 10000)
    end
end)

RegisterNetEvent('esx_basicneeds:healPlayer', function()
    if builtin then
        needs.hunger = 100
        needs.thirst = 100
    end
end)

-- Depuis un autre script (valeurs de 0 a 100) :
--   exports.novyra_hud:setStatus('hunger', 75)   fixe la valeur
--   exports.novyra_hud:addStatus('thirst', 20)   ajoute (ou retire si negatif)
--   exports.novyra_hud:getStatus('hunger')       lit la valeur
local function setStatus(name, percent)
    percent = tonumber(percent)

    if isNeed(name) and percent then
        needs[name] = clamp(percent)
    end
end

exports('setStatus', setStatus)
AddEventHandler('novyra_hud:setStatus', setStatus)

exports('addStatus', function(name, percent)
    percent = tonumber(percent)

    if isNeed(name) and percent then
        needs[name] = clamp((needs[name] or 100) + percent)
    end
end)

exports('getStatus', function(name)
    return needs[name]
end)

-- Choix du mode + faim / soif qui descendent en mode integre
CreateThread(function()
    local cfg    = Config.Needs
    local waited = 0
    local ticks  = 0
    local warned = false

    while true do
        Wait(1000)

        if not playerLoaded then
            waited = 0
        else
            if not builtin and not esxFeeding then
                waited = waited + 1

                if cfg.Mode == 'esx_status' then
                    if waited == 15 and not warned then
                        warned = true
                        print('[novyra_hud] Aucune valeur de faim / soif recue de esx_status. Verifie esx_status + esx_basicneeds, ou mets Config.Needs.Mode = \'auto\'.')
                    end
                elseif cfg.Mode == 'builtin'
                    or (waited >= 3 and GetResourceState('esx_status') ~= 'started')
                    or waited >= 15 then
                    startBuiltin()
                end
            end

            if builtin then
                local ped  = PlayerPedId()
                local dead = IsEntityDead(ped)

                ticks = ticks + 1

                if dead then
                    wasDead = true
                elseif wasDead then
                    -- Reanimation : on ne repart pas affame
                    wasDead = false
                    needs.hunger = math.max(needs.hunger, cfg.RespawnValue)
                    needs.thirst = math.max(needs.thirst, cfg.RespawnValue)
                else
                    needs.hunger = clamp(needs.hunger - 100 / (cfg.HungerMinutes * 60))
                    needs.thirst = clamp(needs.thirst - 100 / (cfg.ThirstMinutes * 60))

                    -- A 0, le joueur perd de la vie toutes les 5 secondes
                    if cfg.Damage > 0 and ticks % 5 == 0 and (needs.hunger <= 0 or needs.thirst <= 0) then
                        SetEntityHealth(ped, math.max(0, GetEntityHealth(ped) - cfg.Damage))
                    end
                end

                if ticks % 30 == 0 then
                    saveNeeds()
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        saveNeeds()
    end
end)

-- ---------------------------------------------------------------------------
-- ESX
-- ---------------------------------------------------------------------------

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    if type(xPlayer) == 'table' and xPlayer.identifier then
        identifier = xPlayer.identifier
    end

    playerLoaded = true
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    saveNeeds()

    playerLoaded     = false
    minimapRefreshed = false
    builtin          = false
    esxFeeding       = false
    identifier       = nil
    needs            = {}
end)

-- Si la ressource est redemarree alors que le joueur est deja en jeu
CreateThread(function()
    if ESX.PlayerLoaded or (ESX.IsPlayerLoaded and ESX.IsPlayerLoaded()) then
        playerLoaded = true
    end
end)

-- ---------------------------------------------------------------------------
-- Commande, events et exports
-- ---------------------------------------------------------------------------

local function setVisible(state, source)
    source = source or 'external'
    hiddenBy[source] = (not state) and true or nil
end

-- Depuis un autre script : exports.novyra_hud:setVisible(false) puis exports.novyra_hud:setVisible(true)
exports('setVisible', function(state)
    setVisible(state, GetInvokingResource())
end)

exports('isVisible', function()
    return visible
end)

-- Ou par event client : TriggerEvent('novyra_hud:setVisible', false)
AddEventHandler('novyra_hud:setVisible', function(state)
    setVisible(state, 'event')
end)

if Config.Command then
    RegisterCommand(Config.Command, function(_, args)
        -- /hud info : valeurs exactes de faim / soif et qui les gere
        if args and args[1] == 'info' then
            local source = builtin and Config.Locale.needs_builtin
                or (esxFeeding and Config.Locale.needs_esx or Config.Locale.needs_none)
            local message = ('%s %.1f %% | %s %.1f %% | %s'):format(
                Config.Locale.hunger, needs.hunger or 0, Config.Locale.thirst, needs.thirst or 0, source)

            ESX.ShowNotification(message)
            print('[novyra_hud] ' .. message)
            return
        end

        userEnabled = not userEnabled
        ESX.ShowNotification(userEnabled and Config.Locale.hud_on or Config.Locale.hud_off)
    end, false)
end

-- Une ressource arretee ne doit pas laisser le HUD cache
AddEventHandler('onResourceStop', function(resource)
    hiddenBy[resource] = nil
end)

-- ---------------------------------------------------------------------------
-- Minimap : calage a gauche sur tous les ecrans + barres d'origine masquees
-- ---------------------------------------------------------------------------

local BASE_RATIO = 16.0 / 9.0

-- Decalage a appliquer a la minimap. GTA la cale sur une zone 16:9 centree : sur un
-- ecran plus large (21:9, 32:9) elle se retrouve loin du bord, on la ramene a gauche.
-- Au-dela de 32:9 c'est du triple ecran : on la laisse sur l'ecran du milieu.
local function getMinimapOffset()
    local ratio = GetAspectRatio(false)

    if Config.MinimapLeft and ratio > BASE_RATIO + 0.01 and ratio < 3.7 then
        return -((ratio - BASE_RATIO) / (2.0 * BASE_RATIO))
    end

    return 0.0
end

-- Positions d'origine de GTA, decalees de "offset"
local function setMinimapPosition(offset)
    SetMinimapComponentPosition('minimap', 'L', 'B', -0.0045 + offset, 0.002, 0.150, 0.188888)
    SetMinimapComponentPosition('minimap_mask', 'L', 'B', 0.020 + offset, 0.032, 0.111, 0.159)
    SetMinimapComponentPosition('minimap_blur', 'L', 'B', -0.030 + offset, 0.022, 0.266, 0.237)
end

-- Ou se trouve la minimap a l'ecran, en % de la hauteur d'ecran (suit le format
-- d'ecran et le reglage "zone de securite" du jeu). Sert a aligner le HUD dessus.
local function getMinimapAnchor(movedLeft)
    local ratio  = GetAspectRatio(false)
    local inset  = (1.0 - GetSafeZoneSize()) * 0.5
    local pillar = 0.0

    if ratio > BASE_RATIO and not movedLeft then
        pillar = (ratio - BASE_RATIO) / 2.0
    end

    return {
        left   = (pillar + inset * math.min(ratio, BASE_RATIO)) * 100.0,
        bottom = inset * 100.0,
        width  = 25.0,
    }
end

CreateThread(function()
    local minimap       = Config.HideDefaultBars and RequestScaleformMovie('minimap') or nil
    local appliedOffset = 0.0
    local lastAnchor    = ''
    local nextCheck     = 0

    while true do
        local now   = GetGameTimer()
        local ready = not minimap or HasScaleformMovieLoaded(minimap)

        -- Une fois par seconde : suit les changements de resolution / format d'ecran
        if ready and now >= nextCheck and playerLoaded and not IsScreenFadedOut() and not IsPlayerSwitchInProgress() then
            nextCheck = now + 1000

            local offset = getMinimapOffset()
            local moved  = math.abs(offset - appliedOffset) > 0.0005

            if moved then
                setMinimapPosition(offset)
                appliedOffset = offset
            end

            -- La minimap reste agrandie / transparente tant qu'elle n'est pas rafraichie
            -- apres un deplacement ou apres le chargement de son scaleform
            if moved or (minimap and not minimapRefreshed) then
                Wait(500)
                SetRadarBigmapEnabled(true, false)
                Wait(100)
                SetRadarBigmapEnabled(false, false)
                minimapRefreshed = true
            end

            if nuiReady then
                local anchor = getMinimapAnchor(appliedOffset ~= 0.0)
                local key    = ('%.2f|%.2f'):format(anchor.left, anchor.bottom)

                if key ~= lastAnchor or anchorDirty then
                    lastAnchor  = key
                    anchorDirty = false
                    SendNUIMessage({ action = 'anchor', left = anchor.left, bottom = anchor.bottom, width = anchor.width })
                end
            end
        end

        if minimap and ready then
            BeginScaleformMovieMethod(minimap, 'SETUP_HEALTH_ARMOUR')
            ScaleformMovieMethodAddParamInt(3)
            EndScaleformMovieMethod()
        end

        Wait(minimap and 0 or 500)
    end
end)

-- Remet la minimap a sa place d'origine si la ressource est arretee
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and Config.MinimapLeft then
        setMinimapPosition(0.0)
    end
end)
