-- Tuile Fonctionnalités, côté client de chaque joueur : PvP, densité de population, HUD et minimap, Rich Presence Discord.
-- Réglages lus dans GlobalState.lunaticFeatures (server/features.lua), appliqués en direct.

local function features()
    return GlobalState.lunaticFeatures or {}
end

local function toggle(key)
    local toggles = features().toggles or {}
    return toggles[key] ~= false
end

---------------------------------------------------------------------
-- PvP, HUD, minimap (vérifiés régulièrement : un respawn ou un autre script peut les remettre)
---------------------------------------------------------------------

local function applyToggles()
    local ped = PlayerPedId()
    local pvp = toggle('pvp')
    NetworkSetFriendlyFireOption(pvp)
    SetCanAttackFriendly(ped, pvp, false)

    if GetResourceState('novyra_hud') == 'started' then
        pcall(function() exports.novyra_hud:setVisible(toggle('hud')) end)
    end
end

AddStateBagChangeHandler('lunaticFeatures', 'global', function()
    SetTimeout(0, applyToggles)
end)

CreateThread(function()
    while true do
        applyToggles()
        Wait(5000)
    end
end)

-- Minimap et compteur de vitesse : à chaque image (le jeu les réaffiche en entrant dans un véhicule)
CreateThread(function()
    while true do
        local f = features()
        local population = f.population or {}
        local minimap = toggle('minimap')
        local speedometer = toggle('speedometer')

        -- Densité des PNJ et véhicules civils
        SetPedDensityMultiplierThisFrame(population.peds or 1.0)
        SetScenarioPedDensityMultiplierThisFrame(population.scenario or 1.0, population.scenario or 1.0)
        SetVehicleDensityMultiplierThisFrame(population.vehicles or 1.0)
        SetRandomVehicleDensityMultiplierThisFrame(population.vehicles or 1.0)
        SetParkedVehicleDensityMultiplierThisFrame(population.parked or 1.0)

        if not minimap then
            DisplayRadar(false)
        end

        -- Compteur de vitesse du HUD du jeu (zone de nom de rue et de véhicule)
        if not speedometer then
            HideHudComponentThisFrame(6) -- nom du véhicule
            HideHudComponentThisFrame(8) -- classe du véhicule
        end

        Wait(0)
    end
end)

-- Minimap réactivée quand l'option revient
local radarHidden = false

CreateThread(function()
    while true do
        local hide = not toggle('minimap')

        if radarHidden and not hide then
            DisplayRadar(true)
        end

        radarHidden = hide
        Wait(1000)
    end
end)

---------------------------------------------------------------------
-- Rich Presence Discord
---------------------------------------------------------------------

local function placeholders(textValue)
    local coords = GetEntityCoords(PlayerPedId())
    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local values = {
        player_rp_name = (LocalPlayer.state.firstName and LocalPlayer.state.lastName) and ('%s %s'):format(LocalPlayer.state.firstName, LocalPlayer.state.lastName) or GetPlayerName(PlayerId()),
        player_id = tostring(GetPlayerServerId(PlayerId())),
        player_street = GetStreetNameFromHashKey(streetHash),
        server_name = GetConvar('sv_projectName', 'Lunatic RP'),
        server_players = tostring(GlobalState.lunaticPlayerCount or #GetActivePlayers()),
        server_maxplayers = tostring(GlobalState.lunaticMaxPlayers or 64),
    }

    return (textValue:gsub('{([%w_]+)}', function(key)
        return values[key] or ('{' .. key .. '}')
    end))
end

CreateThread(function()
    local lastAppId

    while true do
        local discord = features().discord or {}

        if discord.enabled and discord.appId and discord.appId ~= '' then
            if lastAppId ~= discord.appId then
                SetDiscordAppId(discord.appId)
                lastAppId = discord.appId
            end

            if discord.asset and discord.asset ~= '' then
                SetDiscordRichPresenceAsset(discord.asset)
                SetDiscordRichPresenceAssetText(discord.assetText or '')
            end

            SetRichPresence(placeholders(discord.presence or ''))
        end

        Wait(15000)
    end
end)
