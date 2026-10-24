-- Effets des drogues et de l'alcool : les objets de Config.Effects deviennent utilisables (consommés à l'usage).

local ox = exports.ox_inventory

CreateThread(function()
    -- ox_inventory doit avoir chargé ses objets
    while GetResourceState('ox_inventory') ~= 'started' do
        Wait(500)
    end

    Wait(2000)
    local registered = 0

    for effect, entry in pairs(Config.Effects) do
        for _, item in ipairs(entry.items) do
            if ox:Items(item) then
                registered = registered + 1

                ESX.RegisterUsableItem(item, function(source)
                    local settings = FeaturesOf('effects_' .. effect)

                    if settings.enabled == false then
                        return Notify(source, 'Sans effet pour le moment.', 'info')
                    end

                    if ox:RemoveItem(source, item, 1) then
                        TriggerClientEvent('lunatic_gameplay:effect', source, effect)
                    end
                end)
            end
        end
    end

    print(('[lunatic_gameplay] Effets : %d objet(s) utilisable(s).'):format(registered))
end)
