Config = {}

-- Places de garage : véhicules rangés en même temps, tous garages publics confondus, sans Premium. Premium et Premium+
-- ont celles réglées dans la tuile Boutique du panel (5 et 10 par défaut) si elles sont plus nombreuses.
-- Réglable dans le panel (Catalogues → Garage public → Réglages des garages), qui a la priorité.
Config.BaseSlots = 3

-- Distances vérifiées par le serveur (marge réseau comprise) : ouvrir un garage et sortir un véhicule, puis ranger au
-- volant (le [E] « Ranger le véhicule » est affiché par lunatic_business, à Config.GarageStoreDistance)
Config.ActionDistance = 6.0
Config.StoreDistance = 12.0

-- Caméra de l'aperçu : tournée de cet angle (degrés) par rapport à l'avant du véhicule, à cette hauteur
Config.CameraAngle = 35.0
Config.CameraHeight = 1.4
