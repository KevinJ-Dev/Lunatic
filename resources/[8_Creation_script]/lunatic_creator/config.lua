Config = {}

-- Pièce où se fait la création (appartement haut de gamme d'Eclipse Towers, chargé par bob74_ipl).
-- Chaque joueur y est seul : il est placé dans une instance (routing bucket) le temps de la création.
Config.Room = vector4(-786.87, 315.76, 217.64, 270.0)

-- Éclairage studio autour du personnage pendant la création (offset : droite, devant, hauteur par rapport à lui)
Config.Lights = {
    { offset = vector3(-1.1, 1.5, 1.3), color = { 255, 244, 232 }, range = 5.0, intensity = 4.0 },  -- principale, devant à gauche
    { offset = vector3(1.3, 1.2, 0.8), color = { 214, 220, 255 }, range = 4.0, intensity = 2.0 },   -- appoint, devant à droite
    { offset = vector3(0.0, -1.0, 1.7), color = { 170, 120, 255 }, range = 3.5, intensity = 2.5 },  -- contre-jour violet (couleur du panel)
}

-- Heure affichée pendant la création (pour la lumière du jour), l'heure du serveur revient ensuite
Config.ClockHour = 13

-- Décalage du personnage vers la droite de l'écran (0 = centré, 0.25 = un quart de demi-écran), pour le panneau de gauche
Config.CameraShift = 0.25
-- Même décalage quand le panneau des styles est ouvert à droite (les deux panneaux encadrent le personnage)
Config.CameraShiftBoth = 0.03

-- Lieux d'apparition proposés à la fin de la création (aperçu en direct sur place, arrivée avec l'animation GTA).
-- image : lien https (facultatif), affiché derrière le nom.
Config.Spawns = {
    { group = 'Los Santos', label = 'Vespucci', coords = vector4(-1184.4, -1509.8, 4.38, 305.0), image = '' },
    { group = 'Los Santos', label = 'Place des Cubes', coords = vector4(195.17, -933.77, 30.69, 144.0), image = '' },
    { group = 'Los Santos', label = 'Gouvernement', coords = vector4(-544.9, -204.4, 38.22, 210.0), image = '' },
    { group = 'Blaine County', label = 'Sandy Shores', coords = vector4(1961.3, 3740.4, 32.34, 300.0), image = '' },
    { group = 'Blaine County', label = 'Paleto Bay', coords = vector4(-103.6, 6330.7, 31.49, 135.0), image = '' },
    { group = 'Aéroport', label = 'Aéroport international', coords = vector4(-1037.62, -2737.71, 20.17, 330.0), image = '' },
}

-- Catégories de vêtements (composants et accessoires GTA), dans l'ordre des cartes ; icon : dessin de la carte sans image
Config.Clothes = {
    { label = 'Vestes', kind = 'component', id = 11, camera = 2, icon = 'jacket' },
    { label = 'Sous-haut', kind = 'component', id = 8, camera = 2, icon = 'shirt' },
    { label = 'Bras et gants', kind = 'component', id = 3, camera = 2, icon = 'glove' },
    { label = 'Bas', kind = 'component', id = 4, camera = 3, icon = 'pants' },
    { label = 'Chaussures', kind = 'component', id = 6, camera = 3, icon = 'shoe' },
    { label = 'Chapeaux', kind = 'prop', id = 0, camera = 1, icon = 'hat' },
    { label = 'Lunettes', kind = 'prop', id = 1, camera = 1, icon = 'glasses' },
    { label = 'Masques', kind = 'component', id = 1, camera = 1, icon = 'mask' },
    { label = 'Accessoires', kind = 'component', id = 7, camera = 2, icon = 'chain' },
    { label = 'Sacs', kind = 'component', id = 5, camera = 3, icon = 'bag' },
    { label = "Boucles d'oreilles", kind = 'prop', id = 2, camera = 1, icon = 'earring' },
    { label = 'Montres', kind = 'prop', id = 6, camera = 2, icon = 'watch' },
}

-- Images des vêtements (Lunatic Clothes Renderer, option « Numéros du jeu ») : lien https vers un hébergement,
-- ou chemin dans html/clothes/ de la resource. {sex} = male / female, {id} = numéro GTA, {drawable}, {texture}.
-- Vide : numéro du style dans le cercle. Réglable aussi dans le panel (Autres > Création perso), qui a la priorité.
Config.ClothesImages = {
    component = '', -- ex. 'https://images.monserveur.fr/clothes/{sex}/{id}/{drawable}.png'
    prop = '',      -- même chose pour chapeaux, lunettes, boucles d'oreilles et montres
}

-- Tenue proposée au départ de l'étape Vêtements (à ajuster selon tes packs de vêtements)
Config.StarterOutfit = {
    male = { components = { [11] = { 0, 0 }, [8] = { 15, 0 }, [3] = { 0, 0 }, [4] = { 0, 0 }, [6] = { 1, 0 } }, props = {} },
    female = { components = { [11] = { 0, 0 }, [8] = { 2, 0 }, [3] = { 0, 0 }, [4] = { 0, 0 }, [6] = { 0, 0 } }, props = {} },
}

-- Outil photo staff (panel : Autres > Création perso) : miniatures des styles prises en jeu
Config.Photos = {
    overlays = { 1, 2, 4, 5, 8, 0, 9, 3, 6, 7 }, -- calques visibles sur un portrait (barbe, sourcils, maquillage, blush, lèvres, peau)
    hairColor = 2,    -- couleur des cheveux, barbe et sourcils sur les photos
    makeupColor = 7,  -- couleur du blush et du rouge à lèvres sur les photos
    delay = 250,      -- attente (ms) entre l'application d'un style et le portrait
}

-- Micro coupé pendant la création (vocal basé sur Mumble, ex. pma-voice) ; chaque joueur est déjà seul dans son instance
Config.MuteVoice = true

-- Compte à rebours (secondes) quand le staff renvoie un joueur à la création (« Recréer »)
Config.ReturnCountdown = 5

-- Animation du bouton « Bras levés » (vérifier les trous des vêtements)
Config.ArmsUp = { dict = 'missminuteman_1ig_2', anim = 'handsup_base' }

-- Temps laissé à la photo d'identité (mugshot) avant l'arrivée en ville
Config.MugshotSeconds = 3

-- Caméras (en haut à droite) : distance devant le personnage, hauteur visée, champ de vision
Config.Cameras = {
    { label = 'Visage', distance = 0.75, height = 0.65, fov = 38.0 },
    { label = 'Buste', distance = 1.45, height = 0.35, fov = 45.0 },
    { label = 'Corps', distance = 2.7, height = 0.0, fov = 50.0 },
}

-- Nationalités proposées (choix obligatoire ; le serveur refuse toute valeur hors de cette liste)
Config.Nationalities = {
    'Américaine', 'Française', 'Canadienne', 'Mexicaine', 'Britannique', 'Irlandaise', 'Belge', 'Suisse',
    'Italienne', 'Espagnole', 'Portugaise', 'Allemande', 'Néerlandaise', 'Polonaise', 'Ukrainienne', 'Russe',
    'Turque', 'Grecque', 'Libanaise', 'Marocaine', 'Algérienne', 'Tunisienne', 'Sénégalaise', 'Ivoirienne',
    'Nigériane', 'Haïtienne', 'Jamaïcaine', 'Cubaine', 'Portoricaine', 'Colombienne', 'Brésilienne', 'Argentine',
    'Chinoise', 'Japonaise', 'Coréenne', 'Vietnamienne', 'Philippine', 'Indienne', 'Australienne',
}

-- Noms tirés par le bouton « Aléatoire »
Config.RandomNames = {
    male = { 'James', 'Michael', 'David', 'Lucas', 'Hugo', 'Nathan', 'Carlos', 'Diego', 'Marcus', 'Tyler', 'Ethan', 'Liam', 'Noah', 'Mason', 'Logan', 'Jayden', 'Antonio', 'Victor', 'Malik', 'Ryan' },
    female = { 'Emma', 'Olivia', 'Sophia', 'Mia', 'Chloe', 'Léa', 'Camila', 'Isabella', 'Jade', 'Zoe', 'Ava', 'Lily', 'Grace', 'Maya', 'Nina', 'Sarah', 'Elena', 'Aaliyah', 'Jasmine', 'Lucia' },
    last = { 'Smith', 'Johnson', 'Williams', 'Brown', 'Garcia', 'Martinez', 'Rodriguez', 'Lopez', 'Miller', 'Davis', 'Wilson', 'Moore', 'Taylor', 'Anderson', 'Thomas', 'Jackson', 'White', 'Harris', 'Martin', 'Dubois', 'Moreau', 'Laurent', 'Rossi', 'Novak', 'Walker', 'Young', 'King', 'Wright', 'Scott', 'Green' },
}

-- Prénom et nom : nombre de caractères accepté
Config.NameLength = { min = 2, max = 19 }

-- Taille du personnage (cm)
Config.Height = { min = 150, max = 210, default = 178 }

-- Âge accepté (revérifié par le serveur)
Config.Age = { min = 18, max = 90 }

-- Tenue pendant la création, avant le choix des vêtements (composants GTA : 3 bras, 4 bas, 6 chaussures, 8 sous-haut, 11 haut)
Config.Undress = {
    male = { [3] = 15, [4] = 61, [6] = 34, [8] = 15, [11] = 15 },
    female = { [3] = 15, [4] = 17, [6] = 35, [8] = 14, [11] = 18 },
}
