Config = {}

-- Les réglages qui changent souvent (délais, frais, options) sont dans le panel staff (tuile Fonctionnalités) :
-- lus en direct dans GlobalState.lunaticFeatures. Ici, seulement ce qui dépend de la carte ou des objets.

-- Mort et respawn : hôpitaux (le plus proche du lieu de la mort est choisi)
Config.Hospitals = {
    { label = 'Pillbox Hill', coords = vector4(298.6, -584.6, 43.26, 70.0) },
    { label = 'Sandy Shores', coords = vector4(1839.6, 3672.9, 34.28, 210.0) },
    { label = 'Paleto Bay', coords = vector4(-247.7, 6331.2, 32.43, 225.0) },
}
Config.DeathKeepItems = { 'phone', 'id_card' } -- objets gardés quand l'inventaire est vidé au respawn
Config.ReviveDistance = 3.0     -- distance maximale pour réanimer quelqu'un (/reanimer)
Config.MedicCallCooldown = 60   -- secondes entre deux appels aux secours d'un même joueur
Config.TakeCallKey = 'Y'        -- touche des secouristes pour prendre le dernier appel (modifiable dans les touches de GTA)
Config.TakeCallSeconds = 120    -- durée pendant laquelle un appel reçu peut être pris avec cette touche
-- Contrôles gardés pendant l'inconscience : caméra (souris, manette), vocal, menu Échap
Config.DeathAllowedControls = { 1, 2, 3, 4, 5, 6, 199, 200, 249 }
Config.MedicTypes = { medic = true } -- types de services publics (tuile Services publics) qui peuvent réanimer
Config.EventRespawnDelay = 5     -- secondes avant le respawn dans la zone d'un event (règle « Respawn », lunatic_admin)

-- Carburant : stations-service (le plein se fait près d'une pompe, à moins de Config.FuelStationRadius du centre)
Config.FuelStationRadius = 35.0
Config.FuelPumpModels = { 'prop_gas_pump_1a', 'prop_gas_pump_1b', 'prop_gas_pump_1c', 'prop_gas_pump_1d', 'prop_gas_pump_old2', 'prop_gas_pump_old3', 'prop_vintage_pump' }
Config.FuelPumpDistance = 3.0     -- distance à la pompe pour [E]
Config.FuelVehicleDistance = 6.0  -- le véhicule doit être garé à côté de la pompe
Config.FuelStations = {
    vector3(49.4, 2778.8, 58.0), vector3(263.9, 2606.5, 44.9), vector3(1039.9, 2671.1, 39.5), vector3(1207.3, 2660.2, 37.9),
    vector3(2539.7, 2594.2, 37.9), vector3(2679.9, 3263.9, 55.2), vector3(2005.1, 3773.9, 32.4), vector3(1687.2, 4929.4, 42.1),
    vector3(1701.3, 6416.0, 32.8), vector3(179.9, 6602.8, 31.9), vector3(-94.5, 6419.6, 31.5), vector3(-2554.9, 2334.4, 33.1),
    vector3(-1800.4, 803.7, 138.7), vector3(-1437.6, -276.7, 46.2), vector3(-2096.2, -320.3, 13.2), vector3(-724.6, -935.2, 19.2),
    vector3(-526.0, -1211.0, 18.2), vector3(-70.2, -1761.8, 29.5), vector3(265.6, -1261.3, 29.3), vector3(819.7, -1028.8, 26.4),
    vector3(1208.9, -1402.6, 35.2), vector3(1181.4, -330.8, 69.3), vector3(620.8, 269.1, 103.1), vector3(2581.3, 362.0, 108.5),
    vector3(176.6, -1562.0, 29.3), vector3(-319.3, -1471.7, 30.5),
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

-- Carte d'identité (modèle FR, US, BE ou CA choisi dans la tuile Fonctionnalités → Carte d'identité)
Config.IdCardItem = 'id_card'
Config.IdCardDuration = 10    -- secondes d'affichage (Retour arrière pour fermer avant)
Config.IdCardShowDistance = 3.0
