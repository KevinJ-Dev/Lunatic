Config = {}

-- Crews (les crews, rangs et types se gèrent dans le panel staff, tuile Crews)
Config.CrewCommand = 'crew'       -- menu du crew
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
