Config = {}

-- Touche d'ouverture par défaut (modifiable par chaque joueur dans Paramètres > Raccourcis > FiveM)
Config.OpenKey = 'T'

-- Longueur maximale d'un message du tchat et d'un /me ou /do
Config.MaxLength = 200
Config.Max3DLength = 120

-- Portées en mètres
Config.LocalRadius = 20.0 -- HRP local (message sans commande ou /hrp)
Config.Radius3D = 15.0    -- /me et /do

-- Durée d'affichage du texte 3D au-dessus du personnage (ms)
Config.Duration3D = 7000

-- Anti-spam : au plus "max" messages par fenêtre, et un délai minimum entre deux messages
Config.RateLimit = { max = 4, windowMs = 5000, minIntervalMs = 700 }

-- Durée de conservation de l'historique des messages en base (jours)
Config.LogRetentionDays = 14
