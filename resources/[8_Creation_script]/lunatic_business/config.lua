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

-- Location de véhicules
Config.RentalWarnings = { 300, 60 }   -- avertissements avant la fin (secondes restantes)
Config.RentalGrace = 120              -- après la fin : véhicule repris dès qu'il est vide, ou de force après ce délai (secondes)
Config.RentalReturnDistance = 30.0    -- distance maximale entre le véhicule et le comptoir pour le rendre

-- Sonnette
Config.DoorbellCooldown = 30       -- secondes entre deux sonneries d'un même joueur
