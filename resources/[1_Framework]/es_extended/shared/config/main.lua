Config = {}

-- Français activé par défaut pour tout le serveur.
Config.Locale = "fr"

-- Traduction anglaise de secours uniquement si une clé manque en français.
Config.LocaleFallback = GetConvar("esx:localeFallback", "true") ~= "false"

-- Réglage automatique avec ox_inventory : ne pas modifier sans raison.
Config.CustomInventory = false

Config.Accounts = {
    bank = {
        label = TranslateCap("account_bank"),
        round = true,
    },
    black_money = {
        label = TranslateCap("account_black_money"),
        round = true,
    },
    money = {
        label = TranslateCap("account_money"),
        round = true,
    },
}

Config.StartingAccountMoney = { bank = 50000 }

Config.StartingInventoryItems = false -- table/false

Config.DefaultSpawns = { -- Position de réapparition par défaut
    { x = 222.2027, y = -864.0162, z = 30.2922, heading = 1.0 },
}

---@deprecated Use `Config.CommandPermissions` as the single source of truth for command ACLs.
--- Kept temporarily for backwards compatibility with external resources that still read `Config.AdminGroups`.
--- Will be removed in ESX 1.15.
Config.AdminGroups = {
    ["owner"] = true,
    ["admin"] = true,
}

Config.CommandPermissions = {
    ["setcoords"]           = { "owner", "admin" }, -- /setcoords, /tp
    ["setjob"]              = { "owner", "admin" },
    ["car"]                 = { "owner", "admin" },
    ["cardel"]              = { "owner", "admin" }, -- /cardel, /dv
    ["fix"]                 = { "owner", "admin" }, -- /fix, /repair
    ["setaccountmoney"]     = { "owner", "admin" },
    ["giveaccountmoney"]    = { "owner", "admin" },
    ["removeaccountmoney"]  = { "owner", "admin" },
    ["giveitem"]            = { "owner", "admin" },
    ["giveweapon"]          = { "owner", "admin" },
    ["giveammo"]            = { "owner", "admin" },
    ["giveweaponcomponent"] = { "owner", "admin" },
    ["clearall"]            = { "owner", "admin" }, -- /clearall, /clsall
    ["refreshjobs"]         = { "owner", "admin" },
    ["refreshitems"]        = { "owner", "admin" },
    ["clearinventory"]      = { "owner", "admin" },
    ["clearloadout"]        = { "owner", "admin" },
    ["setgroup"]            = { "owner", "admin" },
    ["save"]                = { "owner", "admin" },
    ["saveall"]             = { "owner", "admin" },
    ["goto"]                = { "owner", "admin" },
    ["bring"]               = { "owner", "admin" },
    ["kill"]                = { "owner", "admin" },
    ["freeze"]              = { "owner", "admin" },
    ["unfreeze"]            = { "owner", "admin" },
    ["setdim"]              = { "owner", "admin" }, -- /setdim, /setbucket
    ["players"]             = { "owner", "admin" },
    ["noclip"]              = { "owner", "admin" },
    ["tpm"]                 = { "owner", "admin" },
    ["coords"]              = { "owner", "admin" },
    ["clear"]               = { "user", "admin", "owner" }, -- /clear, /cls
    ["group"]               = { "user", "admin", "owner" },
    ["job"]                 = { "user", "admin", "owner" },
    ["info"]                = { "user", "admin", "owner" },
    ["playtime"]            = { "user", "admin", "owner" },
}

Config.ValidCharacterSets = { -- Only enable additional charsets if your server is multilingual. By default everything is false.
    ['el'] = false, -- Greek
    ['sr'] = false, -- Cyrillic
    ['he'] = false, -- Hebrew
    ['ar'] = false, -- Arabic
    ['zh-cn'] = false -- Chinese, Japanese, Korean
}

Config.EnablePaycheck = true -- enable paycheck
Config.LogPaycheck = false -- Logs paychecks to a nominated Discord channel via webhook (default is false)
Config.EnableSocietyPayouts = false -- pay from the society account that the player is employed at? Requirement: esx_society
Config.MaxWeight = 24 -- the max inventory weight without a backpack
Config.PaycheckInterval = 7 * 60000 -- how often to receive paychecks in milliseconds
Config.SaveDeathStatus = true -- Save the death status of a player
Config.EnableDebug = false -- Use Debug options?

Config.DefaultJobDuty = true -- A players default duty status when changing jobs
Config.OffDutyPaycheckMultiplier = 0.5 -- The multiplier for off duty paychecks. 0.5 = 50% of the on duty paycheck

Config.Multichar = GetResourceState("esx_multicharacter") ~= "missing"
Config.Identity = true -- Select a character identity data before they have loaded in (this happens by default with multichar)
Config.DistanceGive = 4.0 -- Max distance when giving items, weapons etc.

Config.AdminLogging = false -- Logs the usage of certain commands by those with group.admin ace permissions (default is false)

-------------------------------------
-- DO NOT CHANGE BELOW THIS LINE !!!
-------------------------------------
if GetResourceState("ox_inventory") ~= "missing" then
    Config.CustomInventory = "ox"
end

Config.EnableDefaultInventory = Config.CustomInventory == false -- Display the default Inventory ( F2 )
Config.Identifier = GetConvar("esx:identifier", "license")