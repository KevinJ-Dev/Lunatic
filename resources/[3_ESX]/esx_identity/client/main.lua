-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2022-2026 ESX Framework

local loadingScreenFinished = false
local ready = false
local guiEnabled = false
local registrationPending = false
local timecycleModifier = "hud_def_blur"
local themeDefaults = {
    secondaryColor = "#1b1c1a",
    backgroundColor = "#171918",
    accentColor = "#34342e",
}

ESX.SecureNetEvent("esx_identity:alreadyRegistered", function()
    while not loadingScreenFinished do
        Wait(100)
    end
    TriggerEvent("esx_skin:playerRegistered")
end)

ESX.SecureNetEvent("esx_identity:setPlayerData", function(data)
    SetTimeout(1, function()
        ESX.SetPlayerData("name", ("%s %s"):format(data.firstName, data.lastName))
        ESX.SetPlayerData("firstName", data.firstName)
        ESX.SetPlayerData("lastName", data.lastName)
        ESX.SetPlayerData("dateofbirth", data.dateOfBirth)
        ESX.SetPlayerData("sex", data.sex)
        ESX.SetPlayerData("height", data.height)
    end)
end)

AddEventHandler("esx:loadingScreenOff", function()
    loadingScreenFinished = true
end)

xLib.nui.register("ready", function()
    ready = true
    return 1
end)

function setGuiState(state)
        xLib.nui.focus(state, state)
        guiEnabled = state

        if state then
            SetTimecycleModifier(timecycleModifier)
        else
            ClearTimecycleModifier()
        end

        xLib.nui.send({
            type = "enableui",
            enable = state,
            theme = xLib.colors.getESXTheme(themeDefaults),
            settings = {
                maxNameLength = Config.MaxNameLength,
                minHeight = Config.MinHeight,
                maxHeight = Config.MaxHeight,
                minAge = Config.MinAge or 18,
                maxAge = Config.MaxAge,
                locale = Config.Locale,
                dateFormat = Config.DateFormat
            }
        })
end

RegisterNetEvent("esx_identity:showRegisterIdentity", function()
        TriggerEvent("esx_skin:resetFirstSpawn")

        -- Joueur déjà en jeu (ex. « Recréer » du panel staff) : l'écran de chargement est passé depuis longtemps
        if ESX.PlayerLoaded and not GetIsLoadingScreenActive() then
            loadingScreenFinished = true
        end

        -- Ajout Lunatic : la création de personnage maison (lunatic_creator) remplace cet écran quand elle est lancée ;
        -- l'identité y est validée par le même callback (export registerIdentity ci-dessous)
        if GetResourceState("lunatic_creator") == "started" then
            while not loadingScreenFinished do
                Wait(100)
            end

            if not ESX.PlayerData.dead then
                TriggerEvent("lunatic_creator:open")
            end

            return
        end

        -- Ajout Lunatic : relance l'interface toutes les 2 s tant qu'elle n'a pas signalé être prête,
        -- et n'écrit le message d'attente qu'une fois (il remplissait la console en boucle)
        local waited = 0
        while not (ready and loadingScreenFinished) do
            if waited % 20 == 0 then
                if waited == 0 then
                    print("[esx_identity] En attente du chargement de l'interface...")
                end
                xLib.nui.send({ type = "requestReady" })
            end
            waited = waited + 1
            Wait(100)
        end
        if not ESX.PlayerData.dead then
            setGuiState(true)
        end
end)

xLib.nui.register("register", function(data, reply)
        if not guiEnabled then
            return xLib.nui.fail("registrationClosed")
        end

        if registrationPending then
            return xLib.nui.fail("registrationPending")
        end
        registrationPending = true

        CreateThread(function()
            local ok, callback = pcall(xLib.callback.await, "esx_identity:registerIdentity", false, data)
            registrationPending = false
            if not ok or not callback then
                reply(xLib.nui.fail("registerFailed"))
                return
            end

            reply(xLib.nui.ok())
            ESX.ShowNotification(TranslateCap("thank_you_for_registering"))
            setGuiState(false)

            if not ESX.GetConfig().Multichar then
                TriggerEvent("esx_skin:playerRegistered")
            end
        end)
        return xLib.nui.defer
end)

-- Ajout Lunatic : enregistrement de l'identité depuis la création de personnage (lunatic_creator), avec les mêmes
-- vérifications serveur que l'écran d'origine ; true si l'identité est acceptée
exports("registerIdentity", function(data)
    local ok, result = pcall(xLib.callback.await, "esx_identity:registerIdentity", false, data)

    if ok and result then
        ESX.ShowNotification(TranslateCap("thank_you_for_registering"))
        return true
    end

    return false
end)
