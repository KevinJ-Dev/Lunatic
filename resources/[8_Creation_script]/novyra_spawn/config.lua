Config = {}

-- ═════════════════════════════════════════════
--  NOVYRA STUDIO · novyra_spawn
-- ═════════════════════════════════════════════

-- Identité
Config.ServerName  = 'Novyra Studio'
Config.Tagline     = 'Roleplay · Los Santos'
Config.Logo        = 'img/emblem.png'  -- petit logo en haut à gauche ('' = monogramme)
Config.CenterLogo  = 'img/logo.png'    -- grand logo au centre ('' pour masquer)
Config.Accent      = '#22c7ff'     -- couleur principale (cyan du logo)
Config.Accent2     = '#8b4dff'     -- couleur secondaire (violet du logo)
Config.Discord     = 'discord.gg/novyra'  -- '' pour masquer
Config.MaxPlayers  = nil           -- nil = valeur de sv_maxclients

-- Notification à l'arrivée ({name} = nom RP, '' pour désactiver)
Config.Welcome = 'Bienvenue sur Novyra, {name} !'

-- Comportement
Config.EnterKey     = true         -- Entrée valide aussi
Config.ShowInfo     = true         -- métier, position, liquide, banque
Config.Letterbox    = true         -- bandes noires cinéma
Config.Transition   = 'descend'    -- 'descend' (plongée sur le joueur) ou 'fade'
Config.OpenDelay    = 1000         -- attente (ms) après le chargement du joueur avant d'ouvrir

-- Plans caméra
Config.ShotDuration = 9000         -- durée d'un plan (ms)
Config.ShotDrift    = 6.0          -- travelling latéral pendant un plan (mètres)
Config.CamCommand   = 'spawncam'   -- affiche ta caméra actuelle en F8 ('' pour désactiver)

Config.Cameras = {
    { label = 'Vinewood Hills',      coords = vec3(911.05, 40.93, 120.78),    rot = vec3(-6.0, 0.0, 250.99), fov = 60.0 },
    { label = 'Downtown Los Santos', coords = vec3(-80.0, -1010.0, 330.0),    rot = vec3(-12.0, 0.0, 330.0), fov = 55.0 },
    { label = 'Plage de Vespucci',   coords = vec3(-1640.0, -1190.0, 40.0),   rot = vec3(-8.0, 0.0, 210.0),  fov = 58.0 },
    { label = 'Port de Los Santos',  coords = vec3(1000.0, -3230.0, 70.0),    rot = vec3(-10.0, 0.0, 40.0),  fov = 60.0 },
}

-- Actualités (défilent en bas de l'écran) · tag : 'maj' | 'event' | 'info' | 'alerte'
Config.News = {
    { tag = 'maj',   title = 'Mise à jour 2.4',        text = 'Nouveau garage central et refonte des concessions' },
    { tag = 'event', title = 'Rallye de Sandy Shores', text = 'Départ samedi 21h à l\'aérodrome' },
    { tag = 'info',  title = 'Recrutement LSPD',       text = 'Candidatures ouvertes sur le Discord' },
}
