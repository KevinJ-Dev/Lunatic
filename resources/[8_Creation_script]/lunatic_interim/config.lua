Config = {}

-- Métiers d'intérim (doc Vision « Jobs de farm ») : un métier ESX « interim_<id> » chacun, créé au démarrage s'il manque
-- (un seul grade « Intérimaire », paie ESX à 0 : on est payé à la mission). salary = gain d'une mission (affiché au
-- Job Center), duration = durée approximative en minutes, participants = texte affiché. color : pastille si pas de logo.
-- Image et logo de chaque métier : tuile Images du panel (Job Center).
-- kind = 'route' : tournée (dépôt, véhicule, arrêts), jouable ; vehicle et stops : valeurs par défaut, réglables dans le
-- panel (Autres → Métiers d'intérim), comme le salaire, le dépôt et la sortie du véhicule.
Config.JobPrefix = 'interim_'
Config.Jobs = {
    { id = 'canadair', label = 'Pilote de Canadair', company = 'San Andreas Air Fire', color = '#e5484d', salary = 450, duration = 15, participants = '1 personne',
        missions = { "Décolle avec le Canadair depuis l'aérodrome.", 'Écope de l\u{2019}eau sur un lac ou en mer.', 'Largue l\u{2019}eau sur les feux signalés.' } },
    { id = 'pilot', label = "Pilote d'avion", company = 'Adios Airlines', color = '#f5b301', salary = 400, duration = 12, participants = '1 personne',
        missions = { "Récupère un avion au terminal de l'aéroport.", 'Effectue un vol de transport vers une autre piste.', 'Atterris en toute sécurité pour encaisser ta paie.' } },
    { id = 'garbage', label = 'Éboueur', company = 'Hobo', color = '#2f9e44', salary = 300, duration = 15, participants = '1 à 4 personnes', kind = 'route', task = 'garbage', vehicle = 'trash', stops = 5,
        missions = { 'Récupère un camion poubelle au dépôt des éboueurs.', 'Parcours la ville pour vider les bacs à ordures.', 'Dépose les déchets à la décharge et reçois ta rémunération.' } },
    { id = 'miner', label = 'Mineur', company = 'LS Mining', color = '#a0784a', salary = 280, duration = 10, participants = '1 personne',
        missions = { 'Prends ton équipement et descends dans la mine.', 'Récolte un maximum de minerais.', 'Remonte à la surface pour être payé.' } },
    { id = 'delivery', label = 'Livreur', company = 'Post OP', color = '#e8590c', salary = 260, duration = 10, participants = '1 personne', kind = 'route', task = 'parcel', vehicle = 'boxville4', stops = 5,
        missions = { 'Charge ta camionnette au dépôt.', 'Livre les colis aux adresses indiquées.', 'Rapporte la camionnette pour être payé.' } },
    { id = 'hunter', label = 'Chasseur', company = 'Sport de plein air', color = '#5c7a29', salary = 320, duration = 15, participants = '1 personne',
        missions = { 'Prends ton fusil et rejoins la zone de chasse.', 'Traque et abats le gibier autorisé.', 'Dépèce les animaux et revends la viande.' } },
    { id = 'fuel', label = 'Pompiste', company = 'Globe Oil', color = '#1c7ed6', salary = 340, duration = 12, participants = '1 personne',
        missions = { 'Récupère le camion-citerne à la raffinerie.', 'Ravitaille les stations-service indiquées.', 'Ramène la citerne vide pour être payé.' } },
    { id = 'gopostal', label = 'Facteur', company = 'GoPostal', color = '#d6336c', salary = 240, duration = 10, participants = '1 personne', kind = 'route', task = 'parcel', vehicle = 'boxville2', stops = 6,
        missions = { 'Récupère ton fourgon GoPostal au centre de tri.', 'Distribue le courrier dans les boîtes aux lettres.', 'Rends le fourgon au centre pour être payé.' } },
    { id = 'tram', label = 'Conducteur de tramway', company = 'LS Transit', color = '#0ca678', salary = 300, duration = 12, participants = '1 personne',
        missions = { 'Prends les commandes du tramway au dépôt.', 'Dessers les arrêts de la ligne sans retard.', 'Ramène le tramway au dépôt pour être payé.' } },
    { id = 'train', label = 'Conducteur de train', company = 'Freight Train Co.', color = '#495057', salary = 380, duration = 15, participants = '1 personne',
        missions = { 'Monte dans la locomotive en gare de marchandises.', 'Livre les wagons aux gares de la ligne.', 'Termine ta tournée pour encaisser ta paie.' } },
    { id = 'fisher', label = 'Pêcheur', company = 'Pêcheries de Paleto', color = '#1098ad', salary = 260, duration = 12, participants = '1 personne',
        missions = { 'Prends ta canne et rejoins un spot de pêche.', 'Pêche le plus de poissons possible.', 'Revends ta pêche au marché aux poissons.' } },
}

-- Job Center par défaut (Pôle emploi) ; ceux réglés dans le panel (Autres → Job Center) le remplacent
Config.Centers = {
    { label = 'Job Center', x = -268.0, y = -957.0, z = 31.22, h = 205.0 },
}

Config.Distance = 2.0       -- [E] au comptoir
Config.ServerDistance = 6.0 -- revérifié par le serveur

-- Tournées : arrêts tirés au hasard sur les routes, entre minDistance et maxDistance du dépôt, espacés d'au moins gap ;
-- stopSeconds = temps minimum entre deux arrêts (vérifié par le serveur), reach = distance pour livrer, garbageBags = sacs
-- à ramasser par arrêt (Éboueur)
Config.Route = { minDistance = 400.0, maxDistance = 2500.0, gap = 250.0, stopSeconds = 15, reach = 8.0, garbageBags = 2 }
