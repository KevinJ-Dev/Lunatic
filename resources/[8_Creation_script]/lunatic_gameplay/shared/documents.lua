-- Guichets de documents (carte d'identité, permis) : ceux réglés dans le panel staff (Autres → Guichets de documents,
-- GlobalState.lunaticDocumentOffices), sinon ceux de la config. Même liste côté client et côté serveur.

function DocumentOffices()
    local list = {}

    for _, office in ipairs(GlobalState.lunaticDocumentOffices or {}) do
        if office.enabled ~= false then
            list[#list + 1] = office
        end
    end

    return #list > 0 and list or Config.DocumentOffices
end
