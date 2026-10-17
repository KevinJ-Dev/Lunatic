-- Historique des actions du staff (consultable dans le panel au lot 6)

Logs = {}

---@param actor number|nil source du joueur, nil ou 0 pour la console
---@param action string identifiant court de l'action (ex : rank.create)
---@param target string|nil cible lisible (nom de rang, nom de joueur…)
---@param details table|nil données complémentaires
function Logs.add(actor, action, target, details)
    local license, name = nil, 'Console'

    if actor and actor > 0 then
        license = GetPlayerIdentifierByType(actor, 'license')
        name = GetPlayerName(actor) or 'Inconnu'
    end

    MySQL.insert('INSERT INTO `lunatic_admin_logs` (`actor_license`, `actor_name`, `action`, `target`, `details`) VALUES (?, ?, ?, ?, ?)', {
        license,
        name,
        action,
        target,
        details and json.encode(details) or nil,
    })

    print(('[lunatic_admin] %s : %s%s'):format(name, action, target and (' -> ' .. target) or ''))
end
