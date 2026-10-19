Config = {}

-- Crews (les crews, rangs et types se gèrent dans le panel staff, tuile Crews)
Config.CrewCommand = 'crew'       -- menu du crew
Config.InviteDistance = 5.0       -- un joueur invité doit être à moins de cette distance du chef
Config.InviteTimeout = 60         -- secondes pour accepter une invitation

-- Recelleur (catalogue et emplacements dans le panel, tuile Illégal)
Config.FenceAccount = 'black_money' -- compte crédité à la revente : 'black_money' (argent sale), 'money' ou 'bank'
Config.FenceCrewOnly = false        -- true : seuls les membres d'un crew peuvent revendre
Config.FenceDistance = 2.0          -- distance au PNJ pour [E]
