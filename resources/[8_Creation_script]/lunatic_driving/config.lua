Config = {}

Config.InteractDistance = 2.0        -- distance du [E] au PNJ de l'auto-école
Config.SchoolDistance = 8.0          -- le serveur vérifie que le joueur est au point de l'auto-école
Config.TheoryMinutes = 15            -- temps pour répondre au code
Config.ExamMinutes = 20              -- durée maximale d'un examen pratique
Config.SpeedTolerance = 5            -- km/h tolérés au-dessus de la limite
Config.SpeedingSeconds = 2           -- secondes d'excès de vitesse avant une erreur
Config.CrashDamage = 25              -- perte de santé de carrosserie comptée comme un choc
Config.OutOfVehicleSeconds = 15      -- hors du véhicule plus longtemps : examen échoué
Config.Blip = { sprite = 498, color = 3, scale = 0.8 }

-- Rayon des points de trajet (mètres) selon le type d'examen
Config.PointRadius = { car = 8.0, bike = 8.0, truck = 10.0, boat = 25.0, plane = 60.0, heli = 30.0 }
-- Type de véhicule pour la création côté serveur
Config.VehicleTypes = { car = 'automobile', bike = 'bike', truck = 'automobile', boat = 'boat', plane = 'plane', heli = 'heli' }
