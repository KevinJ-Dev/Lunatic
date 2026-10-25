-- Outil photo staff : miniatures des styles prises en jeu (lancé depuis lunatic_admin, Autres > Création perso).
-- Chaque image est enregistrée dans html/thumbs/ (sexe-catégorie-style.webp) avec l'index html/thumbs/index.json.
-- Les joueurs les reçoivent au prochain démarrage de la resource (ensure lunatic_creator).

local RESOURCE = GetCurrentResourceName()
local SESSION_SECONDS = 30 * 60
local IMAGE_MAX = 120000 -- taille maximale d'une miniature encodée (caractères)

local sessions = {} -- [source] = { sex, expires }
local thumbIndex = json.decode(LoadResourceFile(RESOURCE, 'html/thumbs/index.json') or '') or {}

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64_VALUE = {}

for i = 1, #B64 do
    B64_VALUE[B64:byte(i)] = i - 1
end

local function decodeBase64(data)
    local out, bits, value = {}, 0, 0

    for i = 1, #data do
        local digit = B64_VALUE[data:byte(i)]

        if digit then
            value = (value << 6) | digit
            bits = bits + 6

            if bits >= 8 then
                bits = bits - 8
                out[#out + 1] = string.char((value >> bits) & 0xFF)
                value = value & ((1 << bits) - 1)
            end
        end
    end

    return table.concat(out)
end

-- exports.lunatic_creator:startPhotoSession(source, 'male' | 'female') : appelé par lunatic_admin après vérification de la permission
exports('startPhotoSession', function(src, sex)
    src = tonumber(src)

    if not src or not GetPlayerName(src) or (sex ~= 'male' and sex ~= 'female') or Identity.creating[src] then
        return false
    end

    sessions[src] = { sex = sex, expires = os.time() + SESSION_SECONDS }
    TriggerClientEvent('lunatic_creator:photoTool', src, sex)
    return true
end)

RegisterNetEvent('lunatic_creator:thumb', function(sex, key, index, image)
    local src = source
    local session = sessions[src]

    if not session or session.expires < os.time() or sex ~= session.sex then
        return
    end

    index = math.tointeger(tonumber(index))

    if type(key) ~= 'string' or not (key == 'hair' or key:match('^overlay%-%d%d?$')) or not index or index < 0 or index > 999 then
        return
    end

    local encoded = type(image) == 'string' and #image <= IMAGE_MAX and image:match('^data:image/webp;base64,([%w%+/=]+)$')

    if not encoded then
        return
    end

    local bytes = decodeBase64(encoded)

    if not SaveResourceFile(RESOURCE, ('html/thumbs/%s-%s-%d.webp'):format(sex, key, index), bytes, #bytes) then
        return
    end

    thumbIndex[sex] = thumbIndex[sex] or {}
    local list = thumbIndex[sex][key] or {}
    thumbIndex[sex][key] = list

    for _, existing in ipairs(list) do
        if existing == index then
            return
        end
    end

    list[#list + 1] = index
end)

RegisterNetEvent('lunatic_creator:thumbsDone', function(sex, done, failed)
    local src = source

    if not sessions[src] or sessions[src].sex ~= sex then
        return
    end

    sessions[src] = nil
    SaveResourceFile(RESOURCE, 'html/thumbs/index.json', json.encode(thumbIndex), -1)

    TriggerClientEvent('ox_lib:notify', src, {
        type = 'success', duration = 12000,
        description = ('%d photos enregistrées (%d ratées). Faites « ensure lunatic_creator » pour les envoyer aux joueurs.'):format(tonumber(done) or 0, tonumber(failed) or 0),
    })
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
end)
