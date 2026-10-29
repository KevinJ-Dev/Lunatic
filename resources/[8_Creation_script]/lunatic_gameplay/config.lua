Config = {}

-- Les réglages qui changent souvent (délais, frais, options) sont dans le panel staff (tuile Fonctionnalités) :
-- lus en direct dans GlobalState.lunaticFeatures. Ici, seulement ce qui dépend de la carte ou des objets.

-- Mort et respawn : hôpitaux par défaut (le plus proche du lieu de la mort est choisi) ;
-- ceux réglés dans le panel (Autres → Hôpitaux) les remplacent. Les autres réglages de la mort sont dans le panel.
Config.Hospitals = {
    { label = 'Pillbox Hill', coords = vector4(298.6, -584.6, 43.26, 70.0) },
    { label = 'Sandy Shores', coords = vector4(1839.6, 3672.9, 34.28, 210.0) },
    { label = 'Paleto Bay', coords = vector4(-247.7, 6331.2, 32.43, 225.0) },
}
Config.TakeCallKey = 'Y'        -- touche par défaut des secouristes pour prendre un appel (chaque joueur la change dans les touches de GTA)

-- Carburant : stations-service (le plein se fait près d'une pompe, à moins de Config.FuelStationRadius du centre)
Config.FuelStationRadius = 35.0
Config.FuelPumpModels = { 'prop_gas_pump_1a', 'prop_gas_pump_1b', 'prop_gas_pump_1c', 'prop_gas_pump_1d', 'prop_gas_pump_old2', 'prop_gas_pump_old3', 'prop_vintage_pump' }
Config.FuelPumpDistance = 3.0     -- distance à la pompe pour [E]
Config.FuelVehicleDistance = 6.0  -- le véhicule doit être garé à côté de la pompe
Config.FuelRate = 1.5             -- litres versés par seconde (le serveur paie d'après ce débit)
Config.FuelStations = {
    vector3(49.4, 2778.8, 58.0), vector3(263.9, 2606.5, 44.9), vector3(1039.9, 2671.1, 39.5), vector3(1207.3, 2660.2, 37.9),
    vector3(2539.7, 2594.2, 37.9), vector3(2679.9, 3263.9, 55.2), vector3(2005.1, 3773.9, 32.4), vector3(1687.2, 4929.4, 42.1),
    vector3(1701.3, 6416.0, 32.8), vector3(179.9, 6602.8, 31.9), vector3(-94.5, 6419.6, 31.5), vector3(-2554.9, 2334.4, 33.1),
    vector3(-1800.4, 803.7, 138.7), vector3(-1437.6, -276.7, 46.2), vector3(-2096.2, -320.3, 13.2), vector3(-724.6, -935.2, 19.2),
    vector3(-526.0, -1211.0, 18.2), vector3(-70.2, -1761.8, 29.5), vector3(265.6, -1261.3, 29.3), vector3(819.7, -1028.8, 26.4),
    vector3(1208.9, -1402.6, 35.2), vector3(1181.4, -330.8, 69.3), vector3(620.8, 269.1, 103.1), vector3(2581.3, 362.0, 108.5),
    vector3(176.6, -1562.0, 29.3), vector3(-319.3, -1471.7, 30.5), vector3(1784.3, 3330.6, 41.3),
}
-- Consommation par classe de véhicule (GetVehicleClass) : multiplicateur de la consommation de base
Config.FuelClassUsage = {
    [0] = 1.0, [1] = 1.0, [2] = 1.2, [3] = 1.0, [4] = 1.1, [5] = 1.2, [6] = 1.3, [7] = 1.5, [8] = 0.7, [9] = 1.2,
    [10] = 1.6, [11] = 1.4, [12] = 1.2, [13] = 0.0, [14] = 0.8, [15] = 1.5, [16] = 1.5, [17] = 1.0, [18] = 1.0, [19] = 1.4, [20] = 1.5, [21] = 0.0,
}

-- Effets (réglages de durée, vitesse, tremblement, flou et filtre : tuile Fonctionnalités → Effets)
-- items : objets qui déclenchent l'effet (consommés à l'usage ; ignorés s'ils n'existent pas dans ox_inventory)
Config.Effects = {
    cannabis = { items = { 'joint', 'blunt' }, timecycle = 'spectator6', postfx = 'ChopVision', walk = 'move_m@drunk@slightlydrunk', anim = { dict = 'amb@world_human_smoking_pot@male@base', clip = 'base' }, label = 'Vous fumez…' },
    cocaine = { items = { 'cocaine' }, timecycle = 'drug_flying_base', postfx = 'DrugsMichaelAliensFight', label = 'Vous prenez de la cocaïne…' },
    meth = { items = { 'meth' }, timecycle = 'drug_drive_blend01', postfx = 'DrugsTrevorClownsFight', label = 'Vous prenez de la meth…' },
    fentanyl = { items = { 'fentanyl' }, timecycle = 'drug_wobbly', postfx = 'DrugsDrivingIn', walk = 'move_m@drunk@verydrunk', label = 'Vous prenez du fentanyl…' },
    alcohol = { items = { 'beer', 'wine', 'vodka', 'whisky', 'tequila', 'champagne' }, timecycle = 'Drunk', walk = 'move_m@drunk@moderatedrunk', shake = 'DRUNK_SHAKE', anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' }, label = 'Vous buvez…' },
}

-- Arme dans le dos : groupes d'armes concernés (GetWeapontypeGroup) et position sur le dos
Config.BackWeaponGroups = {
    [`GROUP_RIFLE`] = true, [`GROUP_SHOTGUN`] = true, [`GROUP_SMG`] = true, [`GROUP_SNIPER`] = true, [`GROUP_MG`] = true,
}
Config.BackWeaponOffset = { bone = 24818, pos = vector3(0.08, -0.17, -0.02), rot = vector3(0.0, 165.0, 0.0) }

-- Zones sécurisées : pas de tir ni de coups à l'intérieur
Config.SafeZones = {
    { label = 'Hôpital Pillbox Hill', coords = vector3(307.0, -590.0, 43.3), radius = 45.0 },
    { label = 'Commissariat de Mission Row', coords = vector3(440.0, -982.0, 30.7), radius = 40.0 },
    { label = 'Hôpital de Sandy Shores', coords = vector3(1839.6, 3672.9, 34.3), radius = 30.0 },
    { label = 'Hôpital de Paleto Bay', coords = vector3(-247.7, 6331.2, 32.4), radius = 30.0 },
}

-- Carte d'identité (document de l'État de San Andreas) : remise, prix du duplicata, durée d'affichage et rayon réglés dans le panel
-- (Fonctionnalités → Carte d'identité)
Config.IdCardItem = 'id_card'

-- Permis de conduire : objet remis à la réussite du premier examen (lunatic_driving), duplicata au guichet.
-- Ce qui figure sur le permis (type = permis ESX de la table user_licenses), dans cet ordre :
-- kind 'class' = classe américaine (CLASS), 'end' = mention (END)
Config.DriverLicenseItem = 'driver_license'
Config.DriverLicenseCategories = {
    { type = 'drive', code = 'C', label = 'Voiture', kind = 'class' },
    { type = 'drive_bike', code = 'M', label = 'Moto', kind = 'class' },
    { type = 'drive_truck', code = 'A', label = 'Camion', kind = 'class' },
    { type = 'boat', code = 'BOAT', label = 'Bateau', kind = 'end' },
    { type = 'aircraft', code = 'PILOT', label = 'Avion', kind = 'end' },
    { type = 'helicopter', code = 'HELI', label = 'Hélicoptère', kind = 'end' },
}

-- Guichets de documents par défaut (postes de police) ; ceux réglés dans le panel (Autres → Guichets de documents)
-- les remplacent. ped : PNJ derrière le guichet ('' pour aucun).
Config.DocumentOffices = {
    { label = 'Commissariat de Mission Row', x = 441.0, y = -978.9, z = 30.69, h = 180.0, ped = 's_m_y_cop_01' },
    { label = 'Bureau du shérif de Sandy Shores', x = 1853.2, y = 3689.6, z = 34.27, h = 210.0, ped = 's_m_y_sheriff_01' },
    { label = 'Bureau du shérif de Paleto Bay', x = -448.4, y = 6012.8, z = 31.72, h = 310.0, ped = 's_m_y_sheriff_01' },
}
Config.OfficeDistance = 2.0
Config.OfficeBlip = { sprite = 498, color = 29, scale = 0.75 }

-- Menu contextuel (Alt + clic droit sur soi) : emotes rapides. flag 49 = haut du corps, en boucle, on peut marcher ;
-- 48 = haut du corps, une fois ; 1 = corps entier, en boucle.
Config.HandsUp = { label = 'Lever les mains', dict = 'missminuteman_1ig_2', anim = 'handsup_base', flag = 49 }
Config.ContextEmotes = {
    Config.HandsUp,
    { label = 'Saluer', dict = 'gestures@m@standing@casual', anim = 'gesture_hello', flag = 48 },
    { label = 'Applaudir', dict = 'amb@world_human_cheering@male_a', anim = 'base', flag = 49 },
    { label = 'Croiser les bras', dict = 'amb@world_human_hang_out_street@female_arms_crossed@base', anim = 'base', flag = 49 },
    { label = 'Pointer du doigt', dict = 'gestures@f@standing@casual', anim = 'gesture_point', flag = 48 },
    { label = 'Pouce levé', dict = 'anim@mp_player_intselfiethumbs_up', anim = 'idle_a', flag = 48 },
    { label = 'Facepalm', dict = 'anim@mp_player_intcelebrationmale@face_palm', anim = 'face_palm', flag = 48 },
    { label = 'Réfléchir', dict = 'misscarsteal4@aliens', anim = 'rehearsal_base_idle_director', flag = 49 },
    { label = "S'asseoir par terre", dict = 'anim@heists@fleeca_bank@ig_7_jetski_owner', anim = 'owner_idle', flag = 1 },
}

-- Objets tenus en main depuis le menu contextuel (os 57005 = main droite)
Config.ContextPropsOrder = { 'umbrella', 'boombox' }
Config.ContextProps = {
    umbrella = { label = 'Parapluie', model = 'p_amb_brollie_01', bone = 57005, offset = vector3(0.15, 0.005, 0.0), rotation = vector3(87.0, -20.0, 180.0), dict = 'amb@world_human_drinking@coffee@male@base', anim = 'base', flag = 49 },
    boombox = { label = 'Boombox', model = 'prop_boombox_01', bone = 57005, offset = vector3(0.27, 0.0, 0.0), rotation = vector3(0.0, 263.0, 58.0), dict = 'move_weapon@jerrycan@generic', anim = 'idle', flag = 49 },
}

-- Fouille depuis le menu contextuel : distance maximale (mains levées ou inconscient)
Config.SearchDistance = 2.5
