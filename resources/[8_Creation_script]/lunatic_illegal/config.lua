Config = {}

-- Crews (les crews, rangs et types se gèrent dans le panel staff, tuile Crews)
Config.InviteDistance = 5.0       -- un joueur invité doit être à moins de cette distance du chef
Config.InviteTimeout = 60         -- secondes pour accepter une invitation
Config.CrewPointDistance = 1.5    -- distance pour [E] aux coffres et portes des planques de crew (placés dans le panel)
Config.CrewPropertyBucket = 6000  -- monde de la planque n = 6000 + n

-- Recelleur (catalogue et emplacements dans le panel, tuile Illégal)
Config.FenceAccount = 'black_money' -- compte crédité à la revente : 'black_money' (argent sale), 'money' ou 'bank'
Config.FenceCrewOnly = false        -- true : seuls les membres d'un crew peuvent revendre
Config.FenceDistance = 2.0          -- distance au PNJ pour [E]

-- Drogues (drogues, laboratoires et emplacements dans le panel, tuile Illégal)
Config.LabDistance = 1.5            -- distance à l'emplacement du laboratoire pour [E]
Config.SellDistance = 2.0           -- distance au passant pour [E]
Config.SellChance = 0.7             -- probabilité qu'un passant accepte (0 à 1)
Config.SellCooldown = 8             -- secondes entre deux démarchages
Config.PriceVariation = 0.15        -- variation aléatoire du prix (0.15 = ±15 %)
Config.SellAccount = 'black_money'  -- compte crédité : 'black_money', 'money' ou 'bank'
Config.AlertChance = 0.2            -- probabilité d'alerter la police à chaque vente
Config.AlertDuration = 90           -- secondes d'affichage de la zone d'alerte chez la police

-- Territoires (zones, seuils et bonus dans le panel, onglet Territoires) : carte des membres de crews
Config.TerritoryColors = { mine = 2, enemy = 1, free = 0 } -- couleurs de blip : vert (à votre crew), rouge (à un autre), blanc (libre)
Config.TerritoryAlpha = 90          -- transparence des zones sur la carte (0 à 255)
Config.TerritoryBlipSprite = 1      -- icône au centre de la zone

-- Craft d'armes (ateliers, recettes et emplacements dans le panel, onglet Craft d'armes)
Config.WorkshopDistance = 1.5       -- distance à l'emplacement de l'atelier pour [E]
Config.CraftAlertChance = 0.15      -- probabilité d'alerter la police à chaque fabrication (si l'atelier l'autorise)

-- Tablette des crews (objet ox_inventory) et marché noir (catalogue et points de livraison dans le panel, onglet Tablette)
Config.TabletItem = 'crew_tablet'   -- objet à avoir sur soi pour consulter le marché et commander (lié au crew à la première ouverture)
Config.TabletPrice = 2500           -- prix d'une tablette chiffrée chez le recelleur (0 = pas en vente)
Config.TabletAccount = 'black_money'
Config.MarketPickupDistance = 2.0   -- distance au point de livraison pour [E]
Config.MarketRefresh = 60           -- secondes entre deux mises à jour des commandes du crew (points de livraison)
Config.MarketAlertChance = 0.1      -- probabilité d'alerter la police à chaque récupération de colis

-- Contrats de mission (onglet Missions de la tablette ; réglages et points dans le panel, onglet Missions)
Config.ContractMinRank = 2          -- rang de crew minimum pour accepter ou abandonner un contrat (rangs par défaut : 0 = C … 3 = S, le chef)
Config.ContractOffers = 3           -- offres proposées à chaque crew
Config.ContractRotation = 3600      -- secondes avant de nouvelles offres
Config.ContractAccount = 'black_money' -- compte crédité à la réussite
Config.ContractPackage = 'sealed_package' -- objet du colis des livraisons (inutile hors de son contrat)

-- Braquages (réglages, modèles détectés et points dans le panel, onglet Braquages)
Config.HeistClusterRadius = { store = 25.0, jewelry = 40.0, fleeca = 25.0 } -- cibles proches = un même lieu (même délai)
Config.HeistWindow = 900            -- secondes pour finir un braquage commencé ; ensuite le lieu est fermé jusqu'à la fin de son délai

-- Braquages de magasins avec un PNJ au comptoir (points et réglages dans le panel, page Braquages)
Config.HoldupAccount = 'black_money' -- compte crédité du gain
Config.HoldupRange = 7.0            -- distance maximum au vendeur pour le menacer (m)
Config.HoldupKeepRange = 9.0        -- au-delà pendant que le sac se remplit : braquage raté, alarme
Config.HoldupSpawnRange = 60.0      -- les vendeurs apparaissent quand un joueur est à moins de cette distance (m)

-- Délinquance de rue (vol à l'arraché et racket ; réglages dans le panel, page Missions)
Config.StreetAccount = 'black_money' -- compte crédité de l'argent volé

-- Braquage ATM (réglages dans le panel, page Missions) : modèles de distributeurs reconnus
Config.AtmModels = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' }

-- Cambriolage (maisons dans le panel, page Braquages → Maison ; réglages dans la page Missions)
-- Intérieurs des appartements du jeu de base : arrivée, porte de sortie, endroits à fouiller (à ajuster si un repère
-- tombe mal). Chaque maison a son propre « monde » (routing bucket) : seuls ceux qui y sont entrés s'y croisent.
Config.BurglaryAccount = 'black_money' -- compte crédité de l'argent trouvé
Config.BurglaryBucket = 4000            -- monde de la maison n = 4000 + n
Config.BurglaryInteriors = {
    low = {
        label = 'Petit appartement',
        entry = vector4(266.1, -1005.4, -100.0, 0.0),
        exit = vector3(266.0, -1007.4, -100.0),
        spots = {
            { label = 'Cuisine', coords = vector3(265.9, -997.5, -99.0) },
            { label = 'Commode', coords = vector3(262.5, -1002.0, -99.0) },
            { label = 'Armoire', coords = vector3(260.1, -1004.0, -99.0) },
            { label = 'Table de nuit', coords = vector3(257.0, -1003.0, -99.0) },
            { label = 'Salon', coords = vector3(259.0, -997.5, -99.0) },
            { label = 'Salle de bain', coords = vector3(254.4, -1000.5, -99.0) },
        },
    },
    mid = {
        label = 'Appartement moyen',
        entry = vector4(346.5, -1010.5, -99.2, 0.0),
        exit = vector3(346.5, -1012.6, -99.2),
        spots = {
            { label = 'Cuisine', coords = vector3(342.0, -1003.5, -99.2) },
            { label = 'Salon', coords = vector3(341.0, -997.0, -99.2) },
            { label = 'Bureau', coords = vector3(338.5, -1002.0, -99.2) },
            { label = 'Armoire', coords = vector3(351.2, -999.5, -99.2) },
            { label = 'Table de nuit', coords = vector3(350.5, -994.0, -99.2) },
            { label = 'Salle de bain', coords = vector3(347.0, -994.5, -99.2) },
            { label = 'Dressing', coords = vector3(352.5, -996.5, -99.2) },
        },
    },
}
