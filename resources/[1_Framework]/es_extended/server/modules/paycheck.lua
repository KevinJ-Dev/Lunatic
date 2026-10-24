-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2022-2026 ESX Framework

local function getPaycheckBatchSize()
    return math.max(1, math.floor(tonumber(Config.PaycheckBatchSize) or 100))
end

local function getPaycheckBatchDelay()
    return math.max(0, math.floor(tonumber(Config.PaycheckBatchDelay) or 250))
end

local function getPaycheckJitter()
    return math.max(0, math.floor(tonumber(Config.PaycheckJitter) or 0))
end

local function getSociety(name)
    local society
    TriggerEvent("esx_society:getSociety", name, function(result)
        society = result
    end)
    return society
end

local function getSharedAccount(name)
    local account
    TriggerEvent("esx_addonaccount:getSharedAccount", name, function(result)
        account = result
    end)
    return account
end

local function resolveSocietyAccounts(xPlayers)
    local accounts = {}

    if not Config.EnableSocietyPayouts then
        return accounts
    end

    for i = 1, #xPlayers do
        local xPlayer = xPlayers[i]
        local jobName = xPlayer.job and xPlayer.job.name

        if jobName and accounts[jobName] == nil then
            local society = getSociety(jobName)

            if society then
                local account = getSharedAccount(society.account)
                accounts[jobName] = {
                    accountName = society.account,
                    account = account,
                    available = account and account.money or 0,
                    pendingDebit = 0,
                }
            else
                accounts[jobName] = false
            end
        end
    end

    return accounts
end

local function flushSocietyDebits(accounts)
    for _, entry in pairs(accounts) do
        if entry and entry.account then
            if entry.pendingDebit > 0 then
                entry.account.removeMoney(entry.pendingDebit)
                entry.pendingDebit = 0
            end

            local account = getSharedAccount(entry.accountName)
            if account then
                entry.account = account
                entry.available = account.money
            end
        end
    end
end

local function logPaycheck(title, xPlayer, salary)
    if not Config.LogPaycheck then
        return
    end

    ESX.DiscordLogFields("Paycheck", title, "green", {
        { name = "Player", value = xPlayer.name, inline = true },
        { name = "ID", value = xPlayer.source, inline = true },
        { name = "Amount", value = salary, inline = true },
    })
end

local function payPlayer(xPlayer, societyAccounts, bankTitle, receivedPaycheck)
    local player = xPlayer.source

    if ESX.GetPlayerFromId(player) ~= xPlayer then
        return
    end

    local jobLabel = xPlayer.job.label
    local job = xPlayer.job.grade_name
    local onDuty = xPlayer.job.onDuty
    local features = GlobalState.lunaticFeatures
    local offDuty = features and features.newPlayers and tonumber(features.newPlayers.offDuty) or Config.OffDutyPaycheckMultiplier
    local salary = (job == "unemployed" or onDuty) and xPlayer.job.grade_salary or ESX.Math.Round(xPlayer.job.grade_salary * offDuty)

    if not xPlayer.paycheckEnabled or salary <= 0 then
        return
    end

    if job == "unemployed" then
        xPlayer.addAccountMoney("bank", salary, "Welfare Check")
        TriggerClientEvent(
            "esx:showAdvancedNotification",
            player,
            bankTitle,
            receivedPaycheck,
            TranslateCap("received_help", salary),
            "CHAR_BANK_MAZE",
            9
        )
        logPaycheck("Paycheck - Unemployment Benefits", xPlayer, salary)
        return
    end

    if Config.EnableSocietyPayouts then
        local societyEntry = societyAccounts[xPlayer.job.name]

        if societyEntry then
            if societyEntry.account and societyEntry.available >= salary then
                societyEntry.available -= salary
                societyEntry.pendingDebit += salary
                xPlayer.addAccountMoney("bank", salary, "Paycheck")
                TriggerClientEvent(
                    "esx:showAdvancedNotification",
                    player,
                    bankTitle,
                    receivedPaycheck,
                    TranslateCap("received_salary", salary),
                    "CHAR_BANK_MAZE",
                    9
                )
                logPaycheck("Paycheck - " .. jobLabel, xPlayer, salary)
            else
                TriggerClientEvent(
                    "esx:showAdvancedNotification",
                    player,
                    bankTitle,
                    "",
                    TranslateCap("company_nomoney"),
                    "CHAR_BANK_MAZE",
                    1
                )
            end

            return
        end

        xPlayer.addAccountMoney("bank", salary, "Paycheck")
        TriggerClientEvent(
            "esx:showAdvancedNotification",
            player,
            bankTitle,
            receivedPaycheck,
            TranslateCap("received_salary", salary),
            "CHAR_BANK_MAZE",
            9
        )
        logPaycheck("Paycheck - " .. jobLabel, xPlayer, salary)
        return
    end

    xPlayer.addAccountMoney("bank", salary, "Paycheck")
    TriggerClientEvent(
        "esx:showAdvancedNotification",
        player,
        bankTitle,
        receivedPaycheck,
        TranslateCap("received_salary", salary),
        "CHAR_BANK_MAZE",
        9
    )
    logPaycheck("Paycheck - Generic", xPlayer, salary)
end

-- Lunatic : intervalle et allocations Premium réglés dans le panel staff (tuile Économie, lunatic_admin),
-- lus dans GlobalState.lunaticEconomy à chaque tour : aucun redémarrage. Sans lunatic_admin, la config ESX s'applique.
local function getPaycheckInterval()
    local economy = GlobalState.lunaticEconomy
    local minutes = economy and tonumber(economy.paycheckMinutes)

    return minutes and minutes >= 1 and minutes * 60000 or Config.PaycheckInterval
end

local function payAllowance(xPlayer, bankTitle)
    local economy = GlobalState.lunaticEconomy
    local player = xPlayer.source

    if not economy or type(economy.allowances) ~= "table" or not xPlayer.paycheckEnabled or ESX.GetPlayerFromId(player) ~= xPlayer then
        return
    end

    local tier = Player(player).state.premium
    local amount = tier and math.floor(tonumber(economy.allowances[tier]) or 0) or 0

    if amount <= 0 then
        return
    end

    xPlayer.addAccountMoney("bank", amount, "Allocation " .. tier)
    TriggerClientEvent(
        "esx:showAdvancedNotification",
        player,
        bankTitle,
        tier == "premium_plus" and "Allocation Premium+" or "Allocation Premium",
        ("Vous avez reçu %s %s"):format(amount, GlobalState.lunaticCurrency or "$"),
        "CHAR_BANK_MAZE",
        9
    )
end

local function runPaycheck()
    local jitter = getPaycheckJitter()
    if jitter > 0 then
        Wait(math.random(jitter))
    end

    local xPlayers = ESX.GetExtendedPlayers()
    local societyAccounts = resolveSocietyAccounts(xPlayers)
    local batchSize = getPaycheckBatchSize()
    local batchDelay = getPaycheckBatchDelay()
    local bankTitle = TranslateCap("bank")
    local receivedPaycheck = TranslateCap("received_paycheck")

    for i = 1, #xPlayers do
        payPlayer(xPlayers[i], societyAccounts, bankTitle, receivedPaycheck)
        payAllowance(xPlayers[i], bankTitle)

        if i % batchSize == 0 then
            flushSocietyDebits(societyAccounts)
            Wait(batchDelay)
        end
    end

    flushSocietyDebits(societyAccounts)
end

function StartPayCheck()
    CreateThread(function()
        local lastRun = GetGameTimer()

        while true do
            -- Petites attentes : un nouvel intervalle réglé dans le panel compte tout de suite
            Wait(1000)

            if GetGameTimer() - lastRun >= getPaycheckInterval() then
                lastRun = GetGameTimer()
                runPaycheck()
            end
        end
    end)
end
