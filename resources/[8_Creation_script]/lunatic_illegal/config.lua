Config = {}

-- Crews (les crews, rangs et types se gèrent dans le panel staff, tuile Crews)
Config.InviteDistance = 5.0       -- un joueur invité doit être à moins de cette distance du chef
Config.InviteTimeout = 60         -- secondes pour accepter une invitation

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

-- Délinquance de rue (vol à l'arraché ; réglages dans le panel, page Missions)
Config.StreetAccount = 'black_money' -- compte crédité de l'argent volé
