--[[
    Novyra Studio - Loading Screen
    Ferme le loading screen proprement une fois le joueur réellement en jeu.
--]]

local SHUTDOWN_DELAY <const> = 1500   -- laisse le temps à l'anim de sortie (ms)
local SAFETY_TIMEOUT <const> = 60000  -- filet de sécurité si aucun event ne tombe (ms)

local closed = false

local function closeLoadingScreen()
    if closed then return end
    closed = true

    -- Prévient la page pour lancer l'animation de sortie
    SendLoadingScreenMessage(json.encode({ eventName = 'novyra:close' }))

    CreateThread(function()
        Wait(SHUTDOWN_DELAY)
        ShutdownLoadingScreen()
        ShutdownLoadingScreenNui()
    end)
end

-- ESX : personnage chargé
RegisterNetEvent('esx:playerLoaded', function()
    closeLoadingScreen()
end)

-- Callback NUI envoyé par la page quand la barre atteint 100 %
RegisterNUICallback('loadingComplete', function(_, cb)
    cb({})
end)

-- Filet de sécurité : dès que la session est active, on attend le spawn
CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(250)
    end

    local start = GetGameTimer()
    while not closed do
        local ped = PlayerPedId()
        local spawned = DoesEntityExist(ped) and not IsEntityDead(ped) and IsScreenFadedIn()

        if (spawned and GetGameTimer() - start > 5000) or GetGameTimer() - start > SAFETY_TIMEOUT then
            closeLoadingScreen()
        end
        Wait(500)
    end
end)
