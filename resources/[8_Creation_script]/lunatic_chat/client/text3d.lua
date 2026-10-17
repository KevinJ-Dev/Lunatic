-- Texte 3D des /me et /do au-dessus des personnages

---@type table<number, {kind:string, text:string, expires:number}[]> id serveur -> textes affichés
local entries = {}

local colors = {
    me = { 205, 175, 255 },
    ['do'] = { 140, 205, 255 },
}

local MAX_LINES = 3
local LINE_HEIGHT = 0.13

RegisterNetEvent('lunatic_chat:text3d', function(serverId, kind, text)
    if type(serverId) ~= 'number' or type(text) ~= 'string' or not colors[kind] then
        return
    end

    local list = entries[serverId] or {}
    entries[serverId] = list

    list[#list + 1] = {
        kind = kind,
        text = kind == 'me' and ('* %s *'):format(text) or ('%s (Do)'):format(text),
        expires = GetGameTimer() + Config.Duration3D,
    }

    if #list > MAX_LINES then
        table.remove(list, 1)
    end
end)

local function drawText(coords, text, rgb)
    SetTextScale(0.0, 0.34)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(rgb[1], rgb[2], rgb[3], 240)
    SetTextOutline()
    SetTextCentre(true)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

CreateThread(function()
    while true do
        local wait = 500

        if next(entries) then
            wait = 0
            local now = GetGameTimer()
            local myCoords = GetEntityCoords(PlayerPedId())

            for serverId, list in pairs(entries) do
                for i = #list, 1, -1 do
                    if list[i].expires <= now then
                        table.remove(list, i)
                    end
                end

                if #list == 0 then
                    entries[serverId] = nil
                else
                    local player = GetPlayerFromServerId(serverId)
                    local ped = player ~= -1 and GetPlayerPed(player) or 0

                    if ped ~= 0 and DoesEntityExist(ped) then
                        local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)

                        if #(head - myCoords) <= Config.Radius3D + 5.0 then
                            for i, entry in ipairs(list) do
                                drawText(head + vector3(0.0, 0.0, 0.35 + (#list - i) * LINE_HEIGHT), entry.text, colors[entry.kind])
                            end
                        end
                    end
                end
            end
        end

        Wait(wait)
    end
end)
