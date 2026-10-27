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
Config.MaxPurchase = 50            -- quantité maximale par achat (par article dans le panier des magasins)
Config.MaxCartLines = 30           -- articles différents dans un même panier
-- Magasins d'articles (LTD, Ammunation…) : couleur de la bannière par catégorie de la tuile Catalogues, et nom affiché en
-- grand (l'image d'en-tête du magasin, si elle est réglée, passe derrière). Catégorie absente : couleur du panel.
Config.StoreThemes = {
    ltd = { color = '#d3122a', title = 'LTD', sub = 'Limited Gasoline' },
    ammunation = { color = '#2b2b2e', title = 'AMMU-NATION' },
    vangelico = { color = '#141210', title = 'VANGELICO', textColor = '#d9b45a' },
    skateshop = { color = '#1f6fd1', title = 'SKATE SHOP' },
}

-- Location de véhicules
Config.RentalWarnings = { 300, 60 }   -- avertissements avant la fin (secondes restantes)
Config.BuybackAccount = 'money'      -- grossistes : compte crédité à la revente ('money' liquide, 'bank')
Config.BuybackMax = 500              -- quantité maximale par revente
Config.RentalGrace = 120              -- après la fin : véhicule repris dès qu'il est vide, ou de force après ce délai (secondes)
Config.RentalReturnDistance = 30.0    -- distance maximale entre le véhicule et le comptoir pour le rendre
-- Vitrine d'aperçu par défaut (grand garage intérieur de GTA) : le véhicule choisi y est montré en 3D, visible du seul joueur.
-- Réglable dans le panel (tuile Catalogues, agence de location : « Vitrine d'aperçu »), qui a la priorité.
Config.RentalShowroom = vector4(228.7, -991.6, -99.0, 200.0)

-- Véhicules de service (parc et garages placés dans le panel, fiche de la structure)
Config.GarageStoreDistance = 8.0     -- au volant, distance au point Garages pour [E] Ranger
Config.GarageReturnDistance = 20.0   -- distance maximale entre le véhicule et le point pour le ranger (vérifiée par le serveur)

-- Sonnette
Config.DoorbellCooldown = 30       -- secondes entre deux sonneries d'un même joueur
