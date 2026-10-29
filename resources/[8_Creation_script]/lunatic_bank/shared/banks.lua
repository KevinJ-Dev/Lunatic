-- Agences : celles réglées dans le panel staff (Autres → Banques, GlobalState.lunaticBanks), sinon celles de la config.
-- Même liste côté client et côté serveur.

function Banks()
    local list = {}

    for _, bank in ipairs(GlobalState.lunaticBanks or {}) do
        if bank.enabled ~= false then
            list[#list + 1] = bank
        end
    end

    return #list > 0 and list or Config.Banks
end
