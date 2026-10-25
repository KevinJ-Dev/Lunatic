Config = {}

-- Emplacements de personnages selon l'abonnement (lunatic_admin : Premium / Premium+) ; max = plafond absolu
Config.Slots = { default = 1, premium = 2, premium_plus = 3, max = 5 }

-- Écran de sélection : le joueur attend caché dans une instance privée, caméra fixe sur un décor
Config.Scene = {
    ped = vector4(-1184.4, -1509.8, 4.38, 305.0),
    camera = vector3(-1178.6, -1514.2, 6.4),
    lookAt = vector3(-1186.0, -1506.5, 5.2),
    fov = 55.0,
}

-- Changer de personnage en jeu (sauvegarde puis retour à la sélection)
Config.SwitchCommand = 'personnages'
Config.SwitchCooldown = 60 -- secondes entre deux changements
