Config = {}

-- Langue utilisée (fichier dans locales/). "fr" par défaut si la convar esx:locale n'est pas définie.
Config.Locale = GetConvar("esx:locale", "fr")

-- Active les commandes /char et /chardel
Config.EnableCommands = ESX.GetConfig().EnableDebug

-- Format de la date de naissance enregistrée en base / affichée en jeu
-- Le menu se remplit TOUJOURS en JJ/MM/AAAA.
-- Choix : "DD/MM/YYYY" (JJ/MM/AAAA) | "MM/DD/YYYY" | "YYYY/MM/DD"
Config.DateFormat = "DD/MM/YYYY"

-- Limites de validation (utilisées par le menu ET revérifiées côté serveur)
Config.MaxNameLength = 20  -- Longueur max du prénom / nom (strictement inférieure à cette valeur)
Config.MinHeight = 120     -- Taille minimum en cm
Config.MaxHeight = 220     -- Taille maximum en cm
Config.MinAge = 18         -- Âge minimum du personnage
Config.MaxAge = 100        -- Âge maximum du personnage

Config.FullCharDelete = true -- Supprime toutes les données liées au personnage lors d'un /chardel
Config.EnableDebugging = ESX.GetConfig().EnableDebug -- Commandes de debug
