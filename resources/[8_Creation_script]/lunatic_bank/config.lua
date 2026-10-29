Config = {}

-- Numéro de compte : préfixe + 8 chiffres (ex. LN04821937)
Config.IbanPrefix = 'LN'

-- Agences par défaut (guichets des banques de GTA) ; celles réglées dans le panel (Autres → Banques) les remplacent
Config.Banks = {
    { label = 'Fleeca Legion Square', x = 149.9, y = -1040.5, z = 29.37, h = 340.0 },
    { label = 'Fleeca Hawick', x = 314.2, y = -278.6, z = 54.17, h = 340.0 },
    { label = 'Fleeca Burton', x = -351.5, y = -49.5, z = 49.04, h = 340.0 },
    { label = 'Fleeca Rockford Hills', x = -1213.0, y = -330.8, z = 37.79, h = 30.0 },
    { label = 'Fleeca Great Ocean', x = -2962.6, y = 482.6, z = 15.70, h = 90.0 },
    { label = 'Fleeca Route 68', x = 1175.1, y = 2706.6, z = 38.09, h = 180.0 },
    { label = 'Pacific Standard', x = 247.6, y = 223.1, z = 106.29, h = 160.0 },
    { label = 'Blaine County Savings', x = -113.2, y = 6470.0, z = 31.63, h = 135.0 },
}

Config.Distance = 2.0       -- [E] au guichet
Config.ServerDistance = 6.0 -- distance revérifiée par le serveur à chaque opération

-- Montants proposés au retrait et au dépôt (montant libre à côté)
Config.Shortcuts = { 100, 500, 1000, 5000 }

-- Montant maximal par opération
Config.MaxAmount = 1000000

-- Plafonds par défaut sur 24 h glissantes, selon la carte (abonnement) : standard = carte verte, premium = jaune (VIP),
-- premium_plus = noire (VIP+). Ceux réglés dans le panel (Économie → Autre → Banque) les remplacent.
Config.Limits = {
    withdraw = { standard = 5000, premium = 15000, premium_plus = 50000 },
    deposit = { standard = 2000, premium = 4000, premium_plus = 6000 },
    transfer = { standard = 10000, premium = 50000, premium_plus = 250000 },
}

-- Distributeurs : modèles de la carte, distance du [E]
Config.AtmModels = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' }
Config.AtmDistance = 1.5

Config.HistoryLimit = 50     -- transactions affichées
Config.TransferCooldown = 3  -- secondes entre deux virements
