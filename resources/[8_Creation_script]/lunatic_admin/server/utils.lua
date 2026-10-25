-- Petits utilitaires partagés par les modules serveur du panel (chargé avant eux).
-- Chaque module garde ses noms courts : local cleanText = Util.cleanText

Util = {}

function Util.now()
    return os.time()
end

-- Copie profonde d'une table simple (données JSON)
function Util.copy(value)
    return json.decode(json.encode(value))
end

-- Nombre entier compris entre min et max, sinon nil
function Util.whole(value, min, max)
    value = tonumber(value)

    if not value or value ~= math.floor(value) or value < min or value > max then
        return nil
    end

    return value
end

-- Texte nettoyé (caractères de contrôle et espaces en trop retirés) de min à max caractères, sinon nil.
-- Une valeur absente (nil) est refusée.
function Util.cleanText(value, min, max)
    if type(value) ~= 'string' then
        return nil
    end

    local text = value:gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(text)

    return length and length >= min and length <= max and text or nil
end

-- Comme Util.cleanText, mais une valeur absente (nil) compte comme un texte vide
function Util.cleanTextOrEmpty(value, min, max)
    return Util.cleanText(value == nil and '' or value, min, max)
end

-- Position du jeu (x, y, z dans la carte, cap ramené à 0-360), arrondie ; nil si invalide
function Util.position(value)
    if type(value) ~= 'table' then
        return nil
    end

    local x, y, z, h = tonumber(value.x), tonumber(value.y), tonumber(value.z), tonumber(value.h) or 0.0

    if not x or not y or not z or x < -5000 or x > 5000 or y < -5000 or y > 9000 or z < -300 or z > 3000 then
        return nil
    end

    local r = function(n) return math.floor(n * 100 + 0.5) / 100 end
    return { x = r(x), y = r(y), z = r(z), h = math.floor((h % 360) * 10 + 0.5) / 10 }
end
