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
