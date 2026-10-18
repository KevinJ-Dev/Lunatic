Config = {}

-- État au tout premier démarrage (ensuite, la météo et l'heure sont mémorisées entre deux redémarrages)
Config.StartWeather = 'CLEAR'
Config.StartHour = 12

-- Durée réelle d'une minute de jeu (GTA par défaut : 2 secondes, soit 48 minutes pour une journée)
Config.MinuteDuration = 2000

-- Cycle météo automatique : changement toutes les CycleMinutes minutes réelles
Config.WeatherCycle = true
Config.CycleMinutes = 30

-- Durée de la transition progressive entre deux météos (secondes)
Config.TransitionSeconds = 15

-- Météos proposées dans le panel (identifiant GTA = libellé)
Config.Weathers = {
    EXTRASUNNY = 'Grand soleil',
    CLEAR = 'Dégagé',
    CLOUDS = 'Nuageux',
    OVERCAST = 'Couvert',
    CLEARING = 'Éclaircies',
    RAIN = 'Pluie',
    THUNDER = 'Orage',
    FOGGY = 'Brouillard',
    SMOG = 'Smog',
    SNOWLIGHT = 'Neige légère',
    SNOW = 'Neige',
    BLIZZARD = 'Blizzard',
    XMAS = 'Noël',
    HALLOWEEN = 'Halloween',
}

-- Enchaînements possibles du cycle automatique (la neige et les météos spéciales n'y sont pas)
Config.Cycle = {
    EXTRASUNNY = { 'EXTRASUNNY', 'CLEAR', 'CLOUDS' },
    CLEAR = { 'CLEAR', 'EXTRASUNNY', 'CLOUDS', 'SMOG' },
    CLOUDS = { 'CLOUDS', 'CLEAR', 'OVERCAST' },
    OVERCAST = { 'OVERCAST', 'CLOUDS', 'RAIN', 'CLEARING' },
    RAIN = { 'RAIN', 'CLEARING', 'THUNDER' },
    THUNDER = { 'RAIN', 'CLEARING' },
    CLEARING = { 'CLEARING', 'CLOUDS', 'CLEAR' },
    FOGGY = { 'FOGGY', 'CLEAR', 'CLOUDS' },
    SMOG = { 'SMOG', 'CLEAR', 'FOGGY' },
}
