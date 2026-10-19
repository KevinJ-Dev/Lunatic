Config = {}

-- Affichage des points en jeu
Config.MarkerDistance = 15.0       -- distance d'affichage du marqueur au sol
Config.InteractDistance = 1.5      -- distance pour [E]
Config.ActionDistance = 3.0        -- distance maximale vérifiée par le serveur (marge réseau comprise)
Config.MarkerColor = { 150, 80, 255, 120 }

-- Coffres (ox_inventory)
Config.StorageSlots = 60           -- Stockage : un coffre partagé par point
Config.StorageWeight = 300000      -- en grammes
Config.LockerSlots = 20            -- Casier : un coffre personnel par membre et par structure
Config.LockerWeight = 50000

-- Gestion
Config.RecruitDistance = 5.0       -- un joueur recruté doit être à moins de cette distance du patron
Config.AccountMaxAction = 10000000 -- montant maximum d'un dépôt ou retrait
Config.HistorySize = 30            -- lignes d'historique affichées

-- Catalogues
Config.MaxPurchase = 50            -- quantité maximale par achat

-- Sonnette
Config.DoorbellCooldown = 30       -- secondes entre deux sonneries d'un même joueur
