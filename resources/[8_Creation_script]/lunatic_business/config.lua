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
Config.WardrobeMax = 40           -- tenues au maximum par vestiaire (homme et femme confondus)

-- Catalogues
Config.MaxPurchase = 50            -- quantité maximale par achat (par article dans le panier des magasins)
Config.MaxCartLines = 30           -- articles différents dans un même panier
Config.OrderTimeout = 15           -- minutes avant qu'une commande non servie soit annulée
Config.ServeDistance = 3.0         -- l'employé sert le client à moins de cette distance
-- Craft : file d'attente au poste (on peut s'en écarter un peu, pas partir)
Config.CraftQueueMax = 5           -- fabrications en attente au maximum
Config.CraftMaxQuantity = 20       -- unités par fabrication
Config.CraftDistance = 8.0         -- au-delà, la file s'arrête
-- Magasins d'articles (LTD, Ammunation…) : couleur de la bannière par catégorie de la tuile Catalogues, et nom affiché en
-- grand (l'image d'en-tête du magasin, si elle est réglée, passe derrière). Catégorie absente : couleur du panel.
Config.StoreThemes = {
    ltd = { color = '#d3122a', title = 'LTD', sub = 'Limited Gasoline' },
    ammunation = { color = '#2b2b2e', title = 'AMMU-NATION' },
    vangelico = { color = '#141210', title = 'VANGELICO', textColor = '#d9b45a' },
    skateshop = { color = '#1f6fd1', title = 'SKATE SHOP' },
    resources = { color = '#3f7d3a', sub = 'Ressources' }, -- le nom du magasin en grand (Blé, Viandes…), l'image d'en-tête derrière
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

-- Vente de véhicules (concessionnaire, Vespucci Bike) : essai routier, seul dans une instance à part
Config.TestDriveTime = 120            -- durée de l'essai (secondes)
Config.TestDriveRadius = 800.0        -- distance maximale à la sortie du magasin, sinon l'essai s'arrête
Config.TestDriveRadiusByType = { boat = 2500.0, heli = 4000.0, plane = 6000.0 } -- bateaux et aérien : plus loin
Config.TestDriveBucket = 7000         -- instance de l'essai = ce numéro + id du joueur
-- Touche pour terminer l'essai et revenir au comptoir (contrôle GTA ; label = touche affichée dans l'aide, X par défaut)
Config.TestDriveKey = { control = 73, label = '~INPUT_VEH_DUCK~' }
-- Vente par un vendeur (employé du job lié au magasin, connecté) : distance vendeur / client, durée de l'offre,
-- délai entre deux demandes d'un même client
Config.SaleClientDistance = 10.0
Config.SaleOfferTime = 60
Config.SaleRequestCooldown = 60

-- Véhicules de service (parc et garages placés dans le panel, fiche de la structure)
Config.GarageStoreDistance = 8.0     -- au volant, distance au point Garages pour [E] Ranger
Config.GarageReturnDistance = 20.0   -- distance maximale entre le véhicule et le point pour le ranger (vérifiée par le serveur)

-- Sonnette
Config.DoorbellCooldown = 30       -- secondes entre deux sonneries d'un même joueur
