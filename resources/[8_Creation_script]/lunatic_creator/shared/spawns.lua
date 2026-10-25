-- Lieux d'apparition : ceux réglés dans le panel staff (lunatic_admin, GlobalState.lunaticCreator), sinon ceux de la config.
-- Même liste côté client (choix et aperçu) et côté serveur (vérification du choix, arrivée après un crash).

function CreatorSpawns()
    local custom = GlobalState.lunaticCreator and GlobalState.lunaticCreator.spawns

    if type(custom) ~= 'table' or #custom == 0 then
        return Config.Spawns
    end

    local list = {}

    for _, spawn in ipairs(custom) do
        if spawn.enabled ~= false then
            list[#list + 1] = {
                group = spawn.group, label = spawn.label, image = spawn.image,
                coords = vector4(spawn.x + 0.0, spawn.y + 0.0, spawn.z + 0.0, (spawn.h or 0) + 0.0),
            }
        end
    end

    return #list > 0 and list or Config.Spawns
end
