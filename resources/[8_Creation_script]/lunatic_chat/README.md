# lunatic_chat

Tchat de Lunatic RP. Remplace la resource `chat` de FiveM (`provide 'chat'`) : ESX, ox_lib et les autres scripts y envoient leurs messages et leurs suggestions de commandes sans modification.

## Utilisation

- **T** ouvre le tchat (modifiable dans Paramètres > Raccourcis > FiveM), **Entrée** envoie, **Échap** ferme.
- **↑ / ↓** : messages précédents, ou choix d'une suggestion quand on tape une commande ; **Tab** complète la commande ; **Page préc. / suiv.** fait défiler l'historique.
- Un message sans commande est un **HRP local**, comme `/hrp` (portée `Config.LocalRadius`).

| Commande | Effet | Permission (panel staff) |
|---|---|---|
| `/hrp <message>` | Message hors RP aux joueurs proches | — |
| `/me <action>` | Texte 3D au-dessus du personnage : `* action *` | — |
| `/do <description>` | Texte 3D au-dessus du personnage : `description (Do)` | — |
| `/sc <message>` | Tchat staff privé | `chat.staff` |
| `/annonce <message>` | Annonce mise en avant pour tout le serveur | `chat.announce` |
| `/vidertchat` | Vide le tchat de tous les joueurs | `chat.clear` |

`/sc` et `/annonce` fonctionnent aussi depuis la console de l'hébergeur (auteur « Console »).

## Sécurité

- Les destinataires sont calculés par le serveur (distance + même instance) ; le client ne choisit rien.
- Les messages sont nettoyés (codes couleur `^1` et `~r~`, caractères de contrôle), limités en longueur et en fréquence.
- L'interface n'interprète jamais de HTML : tout est inséré comme texte.
- Historique dans la table `lunatic_chat_logs` (créée au démarrage), purgé après `Config.LogRetentionDays` jours.

Dépend de `lunatic_admin` pour les permissions staff.
