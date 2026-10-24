-- Outils client partagés par les systèmes de lunatic_gameplay

function FeaturesOf(section)
    local features = GlobalState.lunaticFeatures
    return features and features[section] or {}
end

function Notify(message, kind)
    ESX.ShowNotification(message, kind or 'info')
end

-- Texte à l'écran (centré horizontalement)
function DrawScreenText(x, y, text, scale)
    SetTextFont(4)
    SetTextScale(scale or 0.45, scale or 0.45)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(255, 255, 255, 235)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end
