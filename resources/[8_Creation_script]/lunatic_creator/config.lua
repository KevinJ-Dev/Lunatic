Config = {}

-- Pièce où se fait la création (appartement haut de gamme d'Eclipse Towers, chargé par bob74_ipl).
-- Chaque joueur y est seul : il est placé dans une instance (routing bucket) le temps de la création.
Config.Room = vector4(-786.87, 315.76, 217.64, 270.0)

-- Arrivée après la création (partie 2 : choix du lieu d'apparition)
Config.DefaultSpawn = vector4(-1037.62, -2737.71, 20.17, 330.0) -- aéroport de Los Santos

-- Caméras (en haut à droite) : distance devant le personnage, hauteur visée, champ de vision
Config.Cameras = {
    { label = 'Visage', distance = 0.75, height = 0.65, fov = 38.0 },
    { label = 'Buste', distance = 1.45, height = 0.35, fov = 45.0 },
    { label = 'Corps', distance = 2.7, height = 0.0, fov = 50.0 },
}

-- Taille du personnage (cm) ; doit rester dans les bornes d'esx_identity (Config.MinHeight / MaxHeight)
Config.Height = { min = 150, max = 210, default = 178 }

-- Âge accepté (esx_identity revérifie avec ses propres bornes)
Config.Age = { min = 18, max = 90 }

-- Tenue pendant la création, avant le choix des vêtements (composants GTA : 3 bras, 4 bas, 6 chaussures, 8 sous-haut, 11 haut)
Config.Undress = {
    male = { [3] = 15, [4] = 61, [6] = 34, [8] = 15, [11] = 15 },
    female = { [3] = 15, [4] = 17, [6] = 35, [8] = 14, [11] = 18 },
}
