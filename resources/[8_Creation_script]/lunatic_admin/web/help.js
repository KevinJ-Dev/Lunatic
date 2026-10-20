"use strict";

// ====================================================================
//  lunatic_admin — aide de la page (bouton « ? » en haut à droite)
//  Pour chaque page : à quoi elle sert, ce qui s'applique en jeu, les pièges courants.
// ====================================================================

const HELP = {
    home: {
        what: "L'accueil regroupe une tuile par page autorisée par votre rang, et vos fiches ouvertes récemment.",
        game: "Rien ne change en jeu depuis cette page.",
        tips: [
            "Chaque page s'ouvre dans son onglet ; les onglets restent ouverts quand vous fermez le panel.",
            "Glissez un onglet pour le déplacer ; clic molette ou Ctrl+W pour le fermer.",
            "Ctrl+K (ou la loupe) cherche partout : joueurs, pages, entreprises, magasins, crews.",
        ],
    },
    dashboard: {
        what: "Vue d'ensemble : joueurs connectés, fréquentation sur 24 h, staff en ligne et dernières actions du staff.",
        game: "Lecture seule, rien ne change en jeu.",
        tips: ["Les chiffres se mettent à jour pendant que le panel est ouvert."],
    },
    players: {
        what: "Fiche des joueurs connectés (onglet En ligne) ou de n'importe quel joueur déjà venu (onglet Hors ligne, recherche en base).",
        game: "Les actions (téléportation, soins, argent, inventaire, sanctions…) s'appliquent tout de suite au joueur.",
        tips: [
            "La fiche est découpée en Actions, Personnage, Argent et objets, Historique.",
            "Un joueur de rang égal ou supérieur au vôtre est protégé : la plupart des actions sont grisées.",
            "Toute opération d'argent demande une raison, enregistrée dans les logs.",
        ],
    },
    sanctions: {
        what: "Historique des avertissements, kicks, bans et peines de prison, et liste des déconnexions récentes.",
        game: "Un ban est vérifié à chaque connexion ; le révoquer laisse le joueur revenir immédiatement.",
        tips: ["« Déconnexions récentes » permet de bannir un joueur qui vient de quitter le serveur."],
    },
    tools: {
        what: "Vos outils de staff : modes (noclip, invisible, noms…), téléportation, soins de zone.",
        game: "Les modes restent actifs jusqu'à ce que vous les coupiez, même panel fermé.",
        tips: ["Seuls les outils autorisés par votre rang apparaissent."],
    },
    logs: {
        what: "Historique des actions du staff et du tchat, filtrable par catégorie, membre, période et texte.",
        game: "Lecture seule.",
        tips: ["Les actions sensibles (argent, objets, sanctions) gardent la raison saisie."],
    },
    ranks: {
        what: "Rangs du staff : nom, couleur, niveau et permissions.",
        game: "Les changements s'appliquent en temps réel aux membres connectés, sans redémarrage.",
        tips: [
            "Plus le niveau est haut, plus le rang est prioritaire ; vous ne pouvez modifier que les rangs inférieurs au vôtre.",
            "Vous ne pouvez pas donner une permission que vous n'avez pas.",
            "Utilisez la recherche et « Tout cocher / Tout décocher » par famille pour aller plus vite.",
        ],
    },
    members: {
        what: "Membres du staff et leur rang.",
        game: "Le rang d'un membre connecté change tout de suite.",
        tips: ["Vous ne pouvez gérer que les membres d'un rang inférieur au vôtre."],
    },
    companies: {
        what: "Entreprises : fiche d'identité, grades, membres, points en jeu (coffre, gestion, vestiaire…), catalogues et compte de société.",
        game: "Les points apparaissent en jeu (marqueur au sol + [E]) dès qu'ils sont placés, sans redémarrage.",
        tips: [
            "Les points se placent à votre position : déplacez-vous en jeu avant de cliquer.",
            "Le badge « Incomplet » d'un catalogue indique ce qui manque pour qu'il marche (point Catalogue, Armurerie ou Craft…).",
            "Une barre « Modifications non enregistrées » apparaît tant que la fiche n'est pas enregistrée.",
        ],
    },
    publics: {
        what: "Services publics (police, médecins, administration, gouvernement) : même fonctionnement que les entreprises.",
        game: "Les points (dont l'Armurerie) apparaissent en jeu dès qu'ils sont placés.",
        tips: ["Un catalogue peut être partagé entre plusieurs structures (ex. armurerie commune)."],
    },
    illegal: {
        what: "Activités illégales : recelleur, drogues et territoires (puis craft d'armes, tablette, missions).",
        game: "Tout s'applique en jeu sans redémarrage.",
        tips: [
            "Le PNJ du recelleur apparaît là où vous vous tenez, tourné dans votre direction ; pas de blip.",
            "Le badge « Incomplet » liste ce qui manque (objet inconnu, emplacement, laboratoire…).",
            "Territoires : le crew qui a le plus d'influence (ventes de drogue) dans un cercle le tient et touche ses bonus ; « Voir sur ma carte » affiche les zones même sans crew.",
        ],
    },
    crews: {
        what: "Crews (gangs, MC, mafias, organisations) : identité, rangs, membres et progression.",
        game: "Les membres gèrent leur crew en jeu avec /crew ; les changements faits ici sont immédiats.",
        tips: ["Un crew sans chef (membre au rang le plus haut) est signalé « Incomplet »."],
    },
    catalogs: {
        what: "Magasins automatiques (LTD, Ammunation, grossistes, location…) : articles, prix, permis, jobs autorisés, emplacements et blips.",
        game: "Les magasins sont recréés en jeu à chaque enregistrement, sans redémarrage.",
        tips: [
            "Les emplacements s'enregistrent tout de suite ; le reste de la fiche avec « Enregistrer ».",
            "Une pastille orange dans la liste signale un magasin incomplet (pas d'emplacement, pas d'article…).",
        ],
    },
    poles: {
        what: "Pôle emploi : création des métiers et de leurs grades.",
        game: "Un métier créé ici est disponible tout de suite, sans redémarrage.",
        tips: ["Les grades vont du plus bas au plus haut."],
    },
    events: {
        what: "Planning des events : création, modification et annulation.",
        game: "Annonces automatiques dans le tchat (rappel puis début) et point sur la carte des joueurs ; commandes /events et /eventgps.",
        tips: ["Les dates s'affichent à l'heure du PC de chaque joueur."],
    },
    world: {
        what: "Météo et heure du serveur.",
        game: "Identiques pour tous les joueurs, appliquées tout de suite.",
        tips: [],
    },
    server: {
        what: "Gestion globale : redémarrage planifié, mode maintenance, actions sur tous les joueurs.",
        game: "Les actions de masse touchent tous les joueurs connectés : à utiliser avec précaution.",
        tips: ["Le mode maintenance bloque les connexions des joueurs hors staff."],
    },
    dev: {
        what: "Resources du serveur (démarrer, arrêter, redémarrer) et outils de diagnostic en jeu.",
        game: "Arrêter une resource la coupe pour tous les joueurs.",
        tips: [
            "Après un envoi de nouveaux fichiers, « Chercher les nouvelles (refresh) » relit les manifestes.",
            "« Infos entité » : visez quelque chose en jeu et appuyez sur E.",
        ],
    },
};

function openHelp() {
    const page = NAV.find((n) => n.id === view) || NAV[0];
    const help = HELP[view] || HELP.home;
    const title = view === "home" ? "Accueil" : page.label;

    openModal((close) => [
        h("header", null, h("h3", null, `Aide · ${title}`)),
        h("div", { class: "body help-body" },
            h("div", { class: "help-block" }, h("b", null, "À quoi sert cette page"), h("p", null, help.what)),
            h("div", { class: "help-block" }, h("b", null, "En jeu"), h("p", null, help.game)),
            help.tips.length ? h("div", { class: "help-block" }, h("b", null, "Bon à savoir"), h("ul", null, help.tips.map((t) => h("li", null, t)))) : null),
        h("footer", null, h("button", { class: "btn primary", onclick: () => close() }, "Compris")),
    ]);
}
