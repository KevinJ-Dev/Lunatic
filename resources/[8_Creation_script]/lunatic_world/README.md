# lunatic_world

Météo et heure **identiques pour tous les joueurs**. Le serveur est la seule source de vérité : il diffuse l'état par `GlobalState` (`lunaticWorld`, `lunaticClock`) et chaque client l'applique.

- **Heure** : avance d'une minute de jeu toutes les `Config.MinuteDuration` ms (2 s comme GTA), peut être figée. L'horloge locale de chaque joueur est mise en pause pour éviter les décalages.
- **Météo** : transition progressive (`Config.TransitionSeconds`), traces dans la neige pour les météos neigeuses, panne de courant (éclairage de la ville coupé, phares conservés).
- **Cycle automatique** : toutes les `Config.CycleMinutes` minutes, météo suivante tirée parmi `Config.Cycle` (enchaînements réalistes, sans neige).
- L'état est mémorisé entre deux redémarrages (KVP de la resource).

Pilotage : page **Monde** du panel `lunatic_admin` (permissions `world.weather` et `world.time`).

## Exports serveur

```lua
exports.lunatic_world:getState()              -- { weather, hour, minute, frozen, cycle, blackout, weathers, cycleMinutes }
exports.lunatic_world:setWeather('RAIN')      -- { ok, error }
exports.lunatic_world:setTime(22, 30)         -- { ok, error }
exports.lunatic_world:setFrozen(true)
exports.lunatic_world:setCycle(false)
exports.lunatic_world:setBlackout(true)
```
