Config = {}

-- Position du HUD : 'bottom-center', 'bottom-right' ou 'minimap' (a droite de la minimap)
Config.Position = 'bottom-center'

-- Style des cercles :
--   'ring'     : anneau lumineux autour de l'icone
--   'liquid'   : bulle qui se remplit de liquide
--   'segments' : anneau decoupe en 12 crans
Config.Style = 'segments'

-- Affiche le pourcentage sous chaque cercle
Config.ShowPercent = false

-- Animations : arrivee en cascade, secousse rouge quand on prend des degats,
-- halo quand on se soigne / mange / boit, vague du style 'liquid'
Config.Animations = true

-- Taille globale du HUD (1.0 = normal, 1.2 = plus gros, 0.8 = plus petit)
Config.Scale = 1.0

-- Frequence de mise a jour en millisecondes (200 = fluide et leger)
Config.UpdateInterval = 200

-- En dessous de ce pourcentage, le cercle clignote en rouge
Config.LowThreshold = 20

-- Commande pour afficher / masquer le HUD (mettre false pour desactiver)
Config.Command = 'hud'

-- Masque les barres de vie / armure d'origine sous la minimap
Config.HideDefaultBars = true

-- Colle la minimap tout a gauche sur les ecrans larges (21:9, 32:9), comme en 16:9.
-- Mets false si un autre script deplace deja ta minimap.
Config.MinimapLeft = true

-- Temps maximum sous l'eau en secondes (10.0 = valeur GTA par defaut)
Config.MaxUnderwaterTime = 10.0

-- Faim et soif
--   Mode 'auto'       : utilise esx_status s'il tourne, sinon le HUD gere la faim / soif lui-meme
--   Mode 'esx_status' : uniquement esx_status (+ esx_basicneeds)
--   Mode 'builtin'    : toujours gere par le HUD
-- Les reglages en dessous ne servent que quand le HUD gere la faim / soif lui-meme.
Config.Needs = {
    Mode          = 'auto',
    HungerMinutes = 60,  -- temps pour passer de 100 % a 0 % de faim
    ThirstMinutes = 45,  -- temps pour passer de 100 % a 0 % de soif
    Damage        = 3,   -- vie perdue toutes les 5 secondes a 0 % (0 = aucun degat)
    RespawnValue  = 50,  -- faim / soif minimum apres une reanimation
}

-- Ordre d'affichage, de gauche a droite
Config.Order = { 'health', 'armor', 'hunger', 'thirst', 'stamina', 'oxygen' }

-- Reglages de chaque statut
--   enabled        : afficher ce statut
--   color          : couleur de la jauge
--   hideWhenFull   : cache le cercle quand il est a 100 %
--   hideWhenEmpty  : cache le cercle quand il est a 0 %
Config.Statuses = {
    health  = { enabled = true, color = '#ff4d5e' },
    armor   = { enabled = true, color = '#4d9dff', hideWhenEmpty = true },
    hunger  = { enabled = true, color = '#ffa63d' },
    thirst  = { enabled = true, color = '#3dd6ff' },
    stamina = { enabled = true, color = '#9be15d', hideWhenFull = true },
    oxygen  = { enabled = true, color = '#b79dff' }, -- visible uniquement sous l'eau
}

-- Textes
Config.Locale = {
    hud_on  = 'HUD affiché',
    hud_off = 'HUD masqué',
    hunger  = 'Faim',
    thirst  = 'Soif',
    needs_builtin = 'géré par le HUD',
    needs_esx     = 'géré par esx_status',
    needs_none    = 'aucune valeur reçue',
}
