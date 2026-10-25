Config = {}

-- Emplacements de personnages selon l'abonnement (lunatic_admin : Premium / Premium+) ; max = plafond absolu
Config.Slots = { default = 1, premium = 2, premium_plus = 3, max = 5 }

-- Écran de sélection : le personnage choisi est montré sur ce décor, seul dans une instance privée
-- (ped : position et orientation ; camera : distance devant lui, hauteur, visée, champ, décalage à droite du panneau)
Config.Scene = {
    ped = vector4(-1184.4, -1509.8, 4.38, 305.0),
    camera = { distance = 2.1, height = 0.55, aim = 0.45, fov = 42.0, shift = 0.28 },
    clockHour = 14, -- heure affichée pendant la sélection (lumière du jour), l'heure du serveur revient ensuite
}

-- Changer de personnage en jeu (sauvegarde puis retour à la sélection)
Config.SwitchCommand = 'personnages'
Config.SwitchCooldown = 60 -- secondes entre deux changements
