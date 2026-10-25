Config = {}

-- Emplacements de personnages : default sans abonnement, max = plafond absolu.
-- Avec un abonnement, c'est l'avantage « personnages » du VIP / VIP+ (panel : tuile Boutique), plus les ajouts du staff.
Config.Slots = { default = 1, max = 5 }

-- Abonnements si lunatic_admin ne tourne pas (sinon nom, couleur et nombre de personnages viennent du panel)
Config.Tiers = {
    premium = { label = 'VIP', color = '#f2c26b', characters = 2 },
    premium_plus = { label = 'VIP+', color = '#9650ff', characters = 3 },
}

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
