Config = {}

-- Les réglages qui changent souvent (délais, frais, options) sont dans le panel staff (tuile Fonctionnalités) :
-- lus en direct dans GlobalState.lunaticFeatures. Ici, seulement ce qui dépend de la carte ou des objets.

-- Mort et respawn : hôpitaux (le plus proche du lieu de la mort est choisi)
Config.Hospitals = {
    { label = 'Pillbox Hill', coords = vector4(298.6, -584.6, 43.26, 70.0) },
    { label = 'Sandy Shores', coords = vector4(1839.6, 3672.9, 34.28, 210.0) },
    { label = 'Paleto Bay', coords = vector4(-247.7, 6331.2, 32.43, 225.0) },
}
Config.DeathKeepItems = { 'phone', 'id_card' } -- objets gardés quand l'inventaire est vidé au respawn
Config.ReviveDistance = 3.0     -- distance maximale pour réanimer quelqu'un (/reanimer)
Config.MedicCallCooldown = 60   -- secondes entre deux appels aux secours d'un même joueur
Config.MedicTypes = { medic = true } -- types de services publics (tuile Services publics) qui peuvent réanimer
