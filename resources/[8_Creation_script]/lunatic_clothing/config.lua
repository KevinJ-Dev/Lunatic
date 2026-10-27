Config = {}

-- Zone d'un magasin par défaut (réglable magasin par magasin dans le panel) : rayon du [E] autour du point (un grand
-- rayon couvre tout le magasin), marqueur au sol, PNJ au point ('' pour aucun). Le serveur revérifie la distance.
Config.StoreDefaults = { radius = 2.0, marker = true, ped = '' }
Config.Marker = { 150, 80, 255, 110 } -- couleur du marqueur au sol (couleur du panel)

-- Enseignes (modifiables et complétées dans le panel) : nom de la bannière, couleur, image de bannière (lien https ou
-- clé de la tuile Images, vide : couleur seule), nom affiché sur la bannière ou non, couleur du blip,
-- coefficient appliqué au prix des pièces (1 = prix du catalogue), catégories non vendues (clés de Config.Groups),
-- couleur du nom sur la bannière (vide : blanc) et flat = une catégorie par bouton dans la barre du bas (au lieu des groupes)
local NOT_JEWELRY = { jacket = true, undershirt = true, arms = true, pants = true, shoes = true, hat = true, glasses = true, mask = true, bag = true }

Config.Brands = {
    binco = { label = 'binco', color = '#f7931e', image = '', showText = true, blip = 47, coef = 1.0, exclude = {} },
    suburban = { label = 'SUBURBAN', color = '#1f6fd1', image = '', showText = true, blip = 3, coef = 1.2, exclude = {} },
    ponsonbys = { label = 'PONSONBYS', color = '#1b1b1f', image = '', showText = true, blip = 40, coef = 2.0, exclude = {} },
    discount = { label = 'Discount Store', color = '#2e9e4f', image = '', showText = true, blip = 2, coef = 0.8, exclude = {} },
    -- Bijouterie de luxe : bijoux seulement, une catégorie par bouton
    vangelico = { label = 'VANGELICO', color = '#141210', textColor = '#d9b45a', image = '', showText = true, blip = 46, coef = 3.0, exclude = NOT_JEWELRY, flat = true },
}
Config.BrandOrder = { 'binco', 'suburban', 'ponsonbys', 'discount', 'vangelico' }
Config.Blip = { sprite = 73, scale = 0.7 }

-- Mes tenues : nombre de tenues enregistrées par personnage (réglable dans le panel) ; Favoris : pièces par sexe
Config.MaxOutfits = 10
Config.MaxFavorites = 60

-- Pages proposées à l'accueil du magasin (activées magasin par magasin dans le panel)
Config.Pages = { 'catalogue', 'ready', 'outfits', 'favorites' }

-- Magasins par défaut (positions des magasins de vêtements d'illenium-appearance) ; ceux réglés dans le panel les remplacent
Config.Stores = {
    { label = 'Discount Store de Grapeseed', brand = 'discount', x = 1693.2, y = 4828.11, z = 42.07, h = 188.66 },
    { label = 'Ponsonbys de Rockford Hills', brand = 'ponsonbys', x = -705.5, y = -149.22, z = 37.42, h = 122.0 },
    { label = 'Suburban de Del Perro', brand = 'suburban', x = -1192.61, y = -768.4, z = 17.32, h = 216.6 },
    { label = 'Binco de Textile City', brand = 'binco', x = 425.91, y = -801.03, z = 29.49, h = 177.79 },
    { label = 'Ponsonbys de Burton', brand = 'ponsonbys', x = -168.73, y = -301.41, z = 39.73, h = 238.67 },
    { label = 'Binco de Strawberry', brand = 'binco', x = 75.39, y = -1398.28, z = 29.38, h = 6.73 },
    { label = 'Binco de Vespucci', brand = 'binco', x = -827.39, y = -1075.93, z = 11.33, h = 294.31 },
    { label = 'Ponsonbys de Morningwood', brand = 'ponsonbys', x = -1445.86, y = -240.78, z = 49.82, h = 36.17 },
    { label = 'Discount Store de Paleto Bay', brand = 'discount', x = 9.22, y = 6515.74, z = 31.88, h = 131.27 },
    { label = 'Suburban de Harmony', brand = 'suburban', x = 615.35, y = 2762.72, z = 42.09, h = 170.51 },
    { label = 'Discount Store de la Route 68', brand = 'discount', x = 1191.61, y = 2710.91, z = 38.22, h = 269.96 },
    { label = 'Suburban de Chumash', brand = 'suburban', x = -3171.32, y = 1043.56, z = 20.86, h = 334.3 },
    { label = 'Discount Store de Great Ocean', brand = 'discount', x = -1105.52, y = 2707.79, z = 19.11, h = 317.19 },
    { label = 'Binco de Vespucci Beach', brand = 'binco', x = -1119.24, y = -1440.6, z = 5.23, h = 300.5 },
    { label = 'Suburban de Hawick', brand = 'suburban', x = 124.82, y = -224.36, z = 54.56, h = 335.41 },
    { label = 'Vangelico de Rockford Hills', brand = 'vangelico', x = -623.0, y = -232.5, z = 38.06, h = 125.0, pages = { catalogue = true, ready = false, outfits = false, favorites = true } },
}

-- Groupes de la barre du bas et catégories (composants et accessoires GTA) ; price = prix par défaut d'une pièce,
-- réglable dans le panel. camera = vue prise à l'ouverture du groupe (ou de la catégorie si elle a la sienne),
-- icon = dessin du bouton quand l'enseigne affiche une catégorie par bouton.
Config.Groups = {
    { key = 'tops', label = 'Hauts', icon = 'shirt', camera = 'torso', categories = {
        { key = 'jacket', label = 'Hauts', kind = 'component', id = 11, price = 60, icon = 'shirt' },
        { key = 'undershirt', label = 'Sous-hauts', kind = 'component', id = 8, price = 30, icon = 'shirt' },
        { key = 'arms', label = 'Bras', kind = 'component', id = 3, price = 0, icon = 'glove' },
    } },
    { key = 'legs', label = 'Bas', icon = 'pants', camera = 'legs', categories = {
        { key = 'pants', label = 'Bas', kind = 'component', id = 4, price = 40, icon = 'pants' },
    } },
    { key = 'feet', label = 'Chaussures', icon = 'shoe', camera = 'feet', categories = {
        { key = 'shoes', label = 'Chaussures', kind = 'component', id = 6, price = 40, icon = 'shoe' },
    } },
    { key = 'head', label = 'Tête', icon = 'hat', camera = 'head', categories = {
        { key = 'hat', label = 'Chapeaux', kind = 'prop', id = 0, price = 25, icon = 'hat' },
        { key = 'glasses', label = 'Lunettes', kind = 'prop', id = 1, price = 20, icon = 'glasses' },
        { key = 'mask', label = 'Masques', kind = 'component', id = 1, price = 30, icon = 'mask' },
        { key = 'earrings', label = "Boucles d'oreilles", kind = 'prop', id = 2, price = 20, icon = 'earring', camera = 'ear' },
    } },
    { key = 'accessories', label = 'Accessoires', icon = 'watch', camera = 'torso', categories = {
        { key = 'chain', label = 'Chaînes et cravates', kind = 'component', id = 7, price = 25, icon = 'chain', camera = 'neck' },
        { key = 'watch', label = 'Montres', kind = 'prop', id = 6, price = 30, icon = 'watch', camera = 'wrist' },
        { key = 'bracelet', label = 'Bracelets', kind = 'prop', id = 7, price = 20, icon = 'bracelet', camera = 'wristRight' },
    } },
    { key = 'bags', label = 'Sacs', icon = 'bag', camera = 'torso', categories = {
        { key = 'bag', label = 'Sacs', kind = 'component', id = 5, price = 35, icon = 'bag' },
    } },
}

-- Vues de la caméra : distance devant le personnage, hauteur visée, champ de vision ; side = décalage vers la droite
-- du personnage (négatif : sa gauche), angle = rotation autour de lui (degrés, positif : vers sa droite),
-- pose = animation jouée tant que la vue est active (bijoux du poignet)
Config.Cameras = {
    head = { distance = 0.85, height = 0.65, fov = 36.0 },
    torso = { distance = 1.5, height = 0.3, fov = 45.0 },
    legs = { distance = 1.5, height = -0.45, fov = 45.0 },
    feet = { distance = 1.2, height = -0.8, fov = 40.0 },
    full = { distance = 2.7, height = 0.0, fov = 50.0 },
    neck = { distance = 0.6, height = 0.45, fov = 34.0 },
    ear = { distance = 0.45, height = 0.65, fov = 32.0, angle = -70.0 },
    wrist = { distance = 0.7, height = 0.2, fov = 32.0, side = -0.12, pose = 'watch' },
    wristRight = { distance = 0.7, height = 0.2, fov = 32.0, side = 0.12, pose = 'watch' },
}

-- Animations des vues (poignet levé comme pour regarder l'heure, celle des magasins de vêtements de GTA)
Config.Poses = {
    watch = { dict = 'anim@random@shop_clothes@watches', anim = 'base' },
}
-- Décalage du personnage vers la droite de l'écran (le panneau est à gauche)
Config.CameraShift = 0.25

-- Animation du bouton « Bras levés » (vérifier les trous des vêtements)
Config.ArmsUp = { dict = 'missminuteman_1ig_2', anim = 'handsup_base' }

-- Gestion du catalogue (staff, ouverte depuis le panel) : photos avec screenshot-basic, une pièce ou toute une série.
-- La pièce est portée seule sur une tenue de base, devant un écran vert (détouré : fond transparent), cadrée par ces
-- vues, recadrée autour de la pièce puis enregistrée dans html/clothes/ ; visible aussitôt (envoyée par le serveur jusqu'au
-- prochain démarrage de la ressource, qui la livre ensuite avec ses fichiers).
Config.Capture = {
    size = 256,          -- côté de la miniature (pixels)
    crop = 0.8,          -- part de la hauteur de l'écran gardée au centre avant le détourage
    quality = 0.9,
    behind = 1.3,        -- distance de l'écran vert derrière le personnage (mètres)
    wait = 150,          -- attente (ms) après le chargement d'une pièce, avant la photo
    -- Double photo : sans puis avec la pièce, seul ce qui change est gardé (le corps disparaît). threshold = écart de
    -- couleur (somme R+V+B, 0-765) en dessous duquel un pixel est retiré ; baseEvery = photos avant de reprendre celle
    -- de la tenue de base
    threshold = 45,
    baseEvery = 25,
    -- Personnage de base de FiveM (comme au début de la création de personnage) pendant la gestion du catalogue
    character = {
        male = { father = 0, mother = 21, shape = 0.5, skin = 0.5 },
        female = { father = 0, mother = 21, shape = 0.8, skin = 0.5 },
    },
    -- Pose figée (animation arrêtée) : debout, bras le long du corps ; les deux photos restent identiques.
    -- time = moment de l'animation où elle est figée (0.0 à 1.0)
    pose = {
        male = { dict = 'anim@heists@heist_corona@team_idles@male_a', anim = 'idle', time = 0.0 },
        female = { dict = 'anim@heists@heist_corona@team_idles@female_a', anim = 'idle', time = 0.0 },
    },
    -- Tenue de base pendant les photos (composant GTA = modèle) : torse nu, sous-vêtements, pieds nus, cheveux courts
    base = {
        male = { [1] = 0, [2] = 0, [3] = 15, [4] = 61, [5] = 0, [6] = 34, [7] = 0, [8] = 15, [9] = 0, [10] = 0, [11] = 15 },
        female = { [1] = 0, [2] = 0, [3] = 15, [4] = 17, [5] = 0, [6] = 35, [7] = 0, [8] = 14, [9] = 0, [10] = 0, [11] = 18 },
    },
    cameras = {
        neck = { distance = 0.55, height = 0.45, fov = 30.0 },
        ear = { distance = 0.4, height = 0.65, fov = 28.0, angle = -70.0 },
        wrist = { distance = 0.6, height = 0.2, fov = 28.0, side = -0.12, pose = 'watch' },
        wristRight = { distance = 0.6, height = 0.2, fov = 28.0, side = 0.12, pose = 'watch' },
        head = { distance = 0.75, height = 0.65, fov = 30.0 },
        torso = { distance = 1.35, height = 0.25, fov = 40.0 },
        legs = { distance = 1.45, height = -0.5, fov = 42.0 },
        feet = { distance = 1.0, height = -0.85, fov = 36.0 },
    },
}

-- Images du Lunatic Clothes Renderer (option « Numéros du jeu ») : copiez les dossiers male/ et female/ de sa sortie
-- dans html/renderer/ puis « ensure lunatic_clothing ». Elles passent avant les photos prises en jeu ; une image absente
-- laisse la place à la suivante. {sex}, {id} = numéro GTA, {drawable}. Vérifiez le nom des dossiers des accessoires.
Config.RendererImages = {
    component = 'renderer/{sex}/{id}/{drawable}.png',
    prop = 'renderer/{sex}/p{id}/{drawable}.png',
}

-- Images des vêtements : liens réglés dans le panel (Autres → Création perso), sinon ceux-ci.
-- {sex} = male / female, {id} = numéro GTA, {drawable}, {texture}. Vide : numéro du modèle.
Config.ClothesImages = { component = '', prop = '' }
