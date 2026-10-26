Config = {}

-- Zone d'un magasin par défaut (réglable magasin par magasin dans le panel) : rayon du [E] autour du point (un grand
-- rayon couvre tout le magasin), marqueur au sol, PNJ au point ('' pour aucun). Le serveur revérifie la distance.
Config.StoreDefaults = { radius = 2.0, marker = true, ped = '' }
Config.Marker = { 150, 80, 255, 110 } -- couleur du marqueur au sol (couleur du panel)

-- Enseignes (modifiables et complétées dans le panel) : nom de la bannière, couleur, image de bannière (lien https ou
-- clé de la tuile Images, vide : couleur seule), nom affiché sur la bannière ou non, couleur du blip
Config.Brands = {
    binco = { label = 'binco', color = '#f7931e', image = '', showText = true, blip = 47 },
    suburban = { label = 'SUBURBAN', color = '#1f6fd1', image = '', showText = true, blip = 3 },
    ponsonbys = { label = 'PONSONBYS', color = '#1b1b1f', image = '', showText = true, blip = 40 },
    discount = { label = 'Discount Store', color = '#2e9e4f', image = '', showText = true, blip = 2 },
}
Config.BrandOrder = { 'binco', 'suburban', 'ponsonbys', 'discount' }
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
}

-- Groupes de la barre du bas et catégories (composants et accessoires GTA) ; price = prix par défaut d'une pièce,
-- réglable dans le panel. camera = vue prise à l'ouverture du groupe.
Config.Groups = {
    { key = 'tops', label = 'Hauts', icon = 'shirt', camera = 'torso', categories = {
        { key = 'jacket', label = 'Hauts', kind = 'component', id = 11, price = 60 },
        { key = 'undershirt', label = 'Sous-hauts', kind = 'component', id = 8, price = 30 },
        { key = 'arms', label = 'Bras', kind = 'component', id = 3, price = 0 },
    } },
    { key = 'legs', label = 'Bas', icon = 'pants', camera = 'legs', categories = {
        { key = 'pants', label = 'Bas', kind = 'component', id = 4, price = 40 },
    } },
    { key = 'feet', label = 'Chaussures', icon = 'shoe', camera = 'feet', categories = {
        { key = 'shoes', label = 'Chaussures', kind = 'component', id = 6, price = 40 },
    } },
    { key = 'head', label = 'Tête', icon = 'hat', camera = 'head', categories = {
        { key = 'hat', label = 'Chapeaux', kind = 'prop', id = 0, price = 25 },
        { key = 'glasses', label = 'Lunettes', kind = 'prop', id = 1, price = 20 },
        { key = 'mask', label = 'Masques', kind = 'component', id = 1, price = 30 },
        { key = 'earrings', label = "Boucles d'oreilles", kind = 'prop', id = 2, price = 20 },
    } },
    { key = 'accessories', label = 'Accessoires', icon = 'watch', camera = 'torso', categories = {
        { key = 'chain', label = 'Chaînes et cravates', kind = 'component', id = 7, price = 25 },
        { key = 'watch', label = 'Montres', kind = 'prop', id = 6, price = 30 },
        { key = 'bracelet', label = 'Bracelets', kind = 'prop', id = 7, price = 20 },
    } },
    { key = 'bags', label = 'Sacs', icon = 'bag', camera = 'torso', categories = {
        { key = 'bag', label = 'Sacs', kind = 'component', id = 5, price = 35 },
    } },
}

-- Vues de la caméra : distance devant le personnage, hauteur visée, champ de vision
Config.Cameras = {
    head = { distance = 0.85, height = 0.65, fov = 36.0 },
    torso = { distance = 1.5, height = 0.3, fov = 45.0 },
    legs = { distance = 1.5, height = -0.45, fov = 45.0 },
    feet = { distance = 1.2, height = -0.8, fov = 40.0 },
    full = { distance = 2.7, height = 0.0, fov = 50.0 },
}
-- Décalage du personnage vers la droite de l'écran (le panneau est à gauche)
Config.CameraShift = 0.25

-- Animation du bouton « Bras levés » (vérifier les trous des vêtements)
Config.ArmsUp = { dict = 'missminuteman_1ig_2', anim = 'handsup_base' }

-- Images des vêtements : liens réglés dans le panel (Autres → Création perso), sinon ceux-ci.
-- {sex} = male / female, {id} = numéro GTA, {drawable}, {texture}. Vide : numéro du modèle.
Config.ClothesImages = { component = '', prop = '' }
