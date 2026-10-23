"use strict";

// ====================================================================
//  lunatic_admin — lot 6 : page Logs (actions du staff, historique du tchat)
//  et traduction des actions en phrases (utilisée aussi par le tableau de bord).
// ====================================================================

const ACTION_LABELS = {
    "rank.create": "a créé le rang",
    "rank.update": "a modifié le rang",
    "rank.duplicate": "a dupliqué un rang en",
    "rank.delete": "a supprimé le rang",
    "staff.add": "a ajouté au staff",
    "staff.setRank": "a changé le rang de",
    "staff.remove": "a retiré du staff",
    "staff.founder": "a nommé Fondateur",
    "player.goto": "est allé vers",
    "player.bring": "a ramené",
    "player.return": "a renvoyé",
    "player.spectate": "a observé",
    "player.freeze": "a figé",
    "player.unfreeze": "a libéré",
    "player.heal": "a soigné",
    "player.revive": "a réanimé",
    "player.feed": "a nourri",
    "player.careZone": "a soigné la zone :",
    "player.appearance": "a ouvert le menu d'apparence de",
    "player.recreate": "a renvoyé à la création de personnage",
    "player.copyAppearance": "a copié l'apparence de",
    "player.wipe": "a wipe",
    "premium.set": "a donné un abonnement à",
    "premium.remove": "a retiré l'abonnement de",
    "credits.change": "a modifié les crédits boutique de",
    "server.restart": "a programmé un redémarrage du serveur",
    "server.cancelRestart": "a annulé le redémarrage du serveur",
    "server.maintenance": "a modifié le mode maintenance",
    "server.healAll": "a soigné tout le serveur",
    "server.bringAll": "a téléporté tout le monde à lui",
    "server.kickAll": "a expulsé tout le monde",
    "poles.create": "a créé un métier",
    "poles.rename": "a renommé un métier",
    "poles.whitelist": "a modifié la liste blanche d'un métier",
    "poles.delete": "a supprimé un métier",
    "poles.grade": "a modifié un grade",
    "poles.addGrade": "a ajouté un grade",
    "poles.removeGrade": "a supprimé un grade",
    "poles.member": "a changé le poste de",
    "poles.fire": "a renvoyé de son poste",
    "events.create": "a programmé un event",
    "events.update": "a modifié un event",
    "events.cancel": "a annulé un event",
    "events.finish": "a terminé un event",
    "dev.resource": "a géré une resource",
    "dev.refresh": "a rechargé la liste des resources",
    "license.give": "a donné un permis à",
    "license.remove": "a retiré un permis à",
    "tool.ghost.on": "a activé le mode fantôme",
    "tool.ghost.off": "a coupé le mode fantôme",
    "player.kick": "a expulsé",
    "player.crash": "a déconnecté (crash)",
    "context.vehicle": "a agi sur le véhicule",
    "structures.create": "a créé une structure",
    "structures.save": "a modifié la fiche d'une structure",
    "structures.delete": "a supprimé une structure",
    "structures.point": "a modifié les points d'une structure",
    "structures.account": "a modifié le compte d'une structure",
    "catalogs.create": "a créé un catalogue",
    "catalogs.delete": "a supprimé un catalogue",
    "catalogs.line": "a modifié un catalogue",
    "catalogs.link": "a rattaché ou détaché un catalogue",
    "fence.item": "a modifié le catalogue du recelleur",
    "drugs.save": "a modifié une drogue",
    "drugs.delete": "a supprimé une drogue",
    "drugs.lab": "a modifié un laboratoire de drogue",
    "territories.save": "a modifié un territoire",
    "territories.reset": "a remis à zéro un territoire",
    "territories.delete": "a supprimé un territoire",
    "workshops.save": "a modifié un atelier d'armes",
    "workshops.delete": "a supprimé un atelier d'armes",
    "workshops.recipe": "a modifié une recette d'atelier",
    "market.item": "a modifié le marché noir",
    "market.dropoff": "a modifié un point de livraison du marché noir",
    "contracts.save": "a modifié les réglages d'un type de contrat",
    "contracts.point": "a modifié un point de contrat",
    "contracts.cancel": "a annulé le contrat d'un crew",
    "heists.save": "a modifié les réglages des braquages",
    "heists.point": "a modifié un point de braquage",
    "heists.reset": "a rendu un lieu de braquage disponible",
    "missions.save": "a modifié les réglages d'une mission",
    "items.save": "a modifié un objet",
    "items.delete": "a supprimé ou réinitialisé un objet",
    "items.give": "a donné un objet",
    "fence.location": "a modifié les emplacements du recelleur",
    "crews.create": "a créé un crew",
    "crews.save": "a modifié un crew",
    "crews.delete": "a supprimé un crew",
    "crews.member": "a modifié les membres d'un crew :",
    "crews.xp": "a ajusté l'XP d'un crew",
    "shops.create": "a créé un magasin",
    "shops.save": "a modifié un magasin",
    "shops.delete": "a supprimé un magasin",
    "shops.location": "a modifié les emplacements d'un magasin",
    "context.entity": "a agi sur l'entité",
    "vehicle.give": "a donné un véhicule à",
    "inventory.open": "a ouvert l'inventaire de",
    "sanction.warn": "a averti",
    "sanction.ban": "a banni",
    "sanction.revoke": "a révoqué une sanction de",
    "sanction.jail": "a mis en prison",
    "sanction.unjail": "a libéré de prison",
    "tool.noclip.on": "a activé le noclip",
    "tool.noclip.off": "a coupé le noclip",
    "tool.invisible.on": "s'est rendu invisible",
    "tool.invisible.off": "est redevenu visible",
    "tool.godmode.on": "s'est rendu invincible",
    "tool.godmode.off": "a coupé l'invincibilité",
    "vehicle.spawn": "a fait apparaître le véhicule",
    "vehicle.delete": "a supprimé",
    "economy.money": "a modifié l'argent de",
    "economy.setJob": "a changé le métier de",
    "economy.giveItem": "a donné un objet à",
    "economy.removeItem": "a retiré un objet à",
    "economy.clearInventory": "a vidé l'inventaire de",
    "economy.inspect": "a ouvert l'inventaire de",
    "world.weather": "a changé la météo",
    "world.cycle": "a réglé le cycle météo",
    "world.blackout": "a réglé la panne de courant",
    "world.time": "a changé l'heure",
    "world.freeze": "a figé / relancé l'heure",
};

const ACCOUNT_LABELS = { money: "liquide", bank: "banque", black_money: "argent sale" };
const DETAIL_LABELS = {
    reason: "Raison", before: "Avant", after: "Après", amount: "Montant", account: "Compte", operation: "Opération",
    count: "Quantité", item: "Objet", serverId: "ID joueur", license: "Licence", id: "Référence", hours: "Durée (heures)",
    removed: "Objets supprimés", permissions: "Permissions", level: "Niveau", rank: "Rang", from: "De", to: "Vers",
    type: "Type", color: "Couleur", name: "Nom",
};
const LOG_CATEGORIES = [
    { value: "", label: "Toutes les catégories" },
    { value: "staff", label: "Rangs et staff" },
    { value: "players", label: "Joueurs" },
    { value: "sanctions", label: "Sanctions" },
    { value: "tools", label: "Outils" },
    { value: "economy", label: "Économie" },
];
const LOG_PERIODS = [
    { value: "today", label: "Aujourd'hui" },
    { value: "week", label: "7 jours" },
    { value: "month", label: "30 jours" },
    { value: "all", label: "Tout" },
];
const CHAT_CHANNELS = [
    { value: "", label: "Tous les canaux" },
    { value: "hrp", label: "HRP" },
    { value: "me", label: "/me" },
    { value: "do", label: "/do" },
    { value: "staff", label: "Tchat staff" },
    { value: "announce", label: "Annonces" },
];

// Phrase lisible pour une action du staff : { verb, summary }
function describeLog(log) {
    const d = log.details && typeof log.details === "object" ? log.details : {};
    const verb = ACTION_LABELS[log.action] || log.action;
    let summary = "";

    switch (log.action) {
        case "economy.money": {
            const sign = d.operation === "add" ? "+" : d.operation === "remove" ? "−" : "=";
            summary = `${sign}${money(d.amount)} ${ACCOUNT_LABELS[d.account] || d.account || ""} (${money(d.before)} → ${money(d.after)})`;
            break;
        }
        case "economy.giveItem":
        case "economy.removeItem":
            summary = `${d.count}x ${d.item}`;
            break;
        case "economy.setJob":
        case "staff.setRank":
            summary = `${d.before || d.from || "?"} → ${d.after || d.to || "?"}`;
            break;
        case "staff.add":
            summary = d.rank ? `rang ${d.rank}` : "";
            break;
        case "sanction.ban":
            summary = `${d.hours === "permanent" ? "définitif" : `${d.hours} h`} · ${d.reason || ""}`;
            break;
        case "world.weather":
            summary = d.weather || "";
            break;
        case "world.time":
            summary = `${String(d.hour).padStart(2, "0")}:${String(d.minute).padStart(2, "0")}`;
            break;
        case "world.cycle":
        case "world.blackout":
        case "world.freeze":
            summary = d.enabled ? "activé" : "désactivé";
            break;
        case "premium.set":
            summary = `${d.tier === "premium_plus" ? "Premium+" : "Premium"} · ${d.days === "lifetime" ? "à vie" : `${d.days} jours`}`;
            break;
        case "server.restart":
            summary = `dans ${d.minutes} min${d.reason ? ` · ${d.reason}` : ""}`;
            break;
        case "server.maintenance":
            summary = `${d.enabled ? "activée" : "désactivée"} · ${d.message || ""}`;
            break;
        case "server.healAll":
            summary = `${d.players} joueur(s)`;
            break;
        case "server.bringAll":
            summary = `${d.count} joueur(s)`;
            break;
        case "poles.create":
            summary = `${d.label} (${d.job}) · ${d.grades} grade(s)`;
            break;
        case "poles.rename":
            summary = `${d.job} : ${d.before} → ${d.after}`;
            break;
        case "poles.whitelist":
            summary = `${d.job} · ${d.enabled ? "liste blanche" : "ouvert à tous"}`;
            break;
        case "poles.delete":
            summary = `${d.label} (${d.job})`;
            break;
        case "poles.grade":
            summary = `${d.job} · ${d.label} · salaire ${d.before} → ${d.after}`;
            break;
        case "poles.addGrade":
            summary = `${d.job} · ${d.label} (${d.salary})`;
            break;
        case "poles.removeGrade":
            summary = `${d.job} · ${d.label}`;
            break;
        case "poles.member":
            summary = `${d.job} · ${d.gradeLabel}`;
            break;
        case "catalogs.create":
        case "catalogs.delete":
        case "catalogs.line":
            summary = [d.label, d.item, d.operation].filter(Boolean).join(" · ");
            break;
        case "crews.create":
        case "crews.save":
        case "crews.delete":
        case "crews.member":
            summary = [d.label, d.type, d.operation].filter(Boolean).join(" · ");
            break;
        case "fence.item":
            summary = [d.item, d.price !== undefined ? `${d.price} $` : null, d.category, d.operation].filter(Boolean).join(" · ");
            break;
        case "drugs.save":
        case "drugs.delete":
        case "drugs.lab":
            summary = [d.item, d.crewType, d.price !== undefined ? `${d.price} $` : null, d.operation].filter(Boolean).join(" · ");
            break;
        case "territories.save":
        case "territories.reset":
        case "territories.delete":
        case "workshops.save":
        case "workshops.delete":
        case "workshops.recipe":
        case "market.item":
        case "market.dropoff":
        case "contracts.save":
        case "contracts.point":
        case "contracts.cancel":
        case "heists.save":
        case "heists.point":
        case "heists.reset":
        case "missions.save":
            summary = [d.label, d.item, d.operation].filter(Boolean).join(" · ");
            break;
        case "items.save":
        case "items.delete":
            summary = [d.label || d.item, d.item, d.operation].filter(Boolean).join(" · ");
            break;
        case "items.give":
            summary = `${d.count} × ${d.item}`;
            break;
        case "fence.location":
            summary = [d.operation, d.ped].filter(Boolean).join(" · ");
            break;
        case "crews.xp":
            summary = `${d.label} · ${d.amount > 0 ? "+" : ""}${d.amount} XP`;
            break;
        case "shops.create":
        case "shops.save":
        case "shops.delete":
        case "shops.location":
            summary = [d.label, d.category, d.operation, d.items !== undefined ? `${d.items} article(s)` : null].filter(Boolean).join(" · ");
            break;
        case "catalogs.link":
            summary = `${d.label} · ${d.linked ? "rattaché à" : "détaché de"} ${d.job}`;
            break;
        case "structures.point":
            summary = `${d.job} · ${({ add: "ajout", move: "déplacement", delete: "suppression" })[d.operation] || d.operation} · ${d.type}`;
            break;
        case "structures.account":
            summary = `${d.job} · ${d.amount > 0 ? "+" : ""}${d.amount} · ${d.reason || ""}`;
            break;
        case "structures.create":
        case "structures.save":
        case "structures.delete":
            summary = [d.label, d.job, d.type].filter(Boolean).join(" · ");
            break;
        case "context.vehicle":
        case "context.entity":
            summary = ({ repair: "réparation", flip: "retournement", enter: "monté dedans", delete: "suppression", freeze: "gel", unfreeze: "dégel" })[d.operation] || d.operation || "";
            break;
        case "vehicle.give":
            summary = `${d.model} · ${d.plate}`;
            break;
        case "dev.resource":
            summary = `${{ start: "démarrage", stop: "arrêt", restart: "redémarrage" }[d.operation] || d.operation} · ${d.name} (${d.before} → ${d.after})`;
            break;
        case "events.create":
        case "events.update":
        case "events.cancel":
        case "events.finish":
            summary = `${d.title} · ${new Date(d.startsAt * 1000).toLocaleString("fr-FR", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })}`;
            break;
        case "poles.fire":
            summary = d.job || "";
            break;
        case "server.kickAll":
            summary = `${d.count} joueur(s) · ${d.reason || ""}`;
            break;
        case "credits.change":
            summary = `${d.amount > 0 ? "+" : ""}${d.amount} (${d.before} → ${d.after}) · ${d.reason || ""}`;
            break;
        case "license.give":
        case "license.remove":
            summary = d.license || "";
            break;
        case "player.wipe":
            summary = d.reason || "";
            break;
        case "sanction.jail":
            summary = `${d.minutes} min · ${d.reason || ""}`;
            break;
        case "sanction.revoke":
            summary = `#${d.id} · ${d.reason || ""}`;
            break;
        case "economy.clearInventory":
            summary = `${Array.isArray(d.removed) ? d.removed.length : 0} emplacement(s) · ${d.reason || ""}`;
            break;
        default:
            summary = d.reason || "";
    }

    return { verb, summary };
}

// ---------- Page Logs ----------

const logsView = {
    tab: "actions",
    category: "", staff: "", period: "week", search: "",
    channel: "", chatPeriod: "today", chatSearch: "",
    logs: null, more: false, staffList: [],
    messages: null, chatMore: false,
};
let logsDom = null;
let logsTimer = null;
let logsRequest = 0; // une réponse arrivée après un changement de filtre est ignorée

function renderLogs() {
    const root = $("view-logs");
    const tabs = [];
    if (can("logs.view")) tabs.push({ value: "actions", label: "Actions du staff" });
    if (can("logs.chat")) tabs.push({ value: "chat", label: "Tchat" });
    if (!tabs.some((t) => t.value === logsView.tab)) logsView.tab = tabs.length ? tabs[0].value : "actions";

    // Structure gardée entre deux rafraîchissements (recherche conservée)
    if (!logsDom || !root.contains(logsDom.body)) {
        logsDom = {
            tabs: h("div", { class: "segmented" }),
            filters: h("div", { class: "filters" }),
            body: h("div", { class: "table" }),
            footer: h("div", { class: "logs-footer" }),
        };
        root.replaceChildren(h("div", { class: "content" },
            h("div", { class: "page-head" }, h("div", { class: "grow" },
                h("h1", { class: "page-title" }, "Logs"),
                h("div", { class: "page-sub" }, "Historique des actions du staff et du tchat")
            ), logsDom.tabs),
            h("div", { class: "toolbar logs-toolbar" }, logsDom.filters),
            h("div", { class: "scroll" }, logsDom.body, logsDom.footer)
        ));
        paintLogsFilters(tabs);
        fetchLogs(false);
        return;
    }

    logsDom.tabs.replaceChildren(...segmentedButtons(tabs, logsView.tab, (value) => { logsView.tab = value; paintLogsFilters(tabs); fetchLogs(false); }));
}

function selectInput(options, current, onChange) {
    const el = h("select", { class: "input" }, options.map((o) => h("option", { value: o.value, selected: o.value === current }, o.label)));
    el.addEventListener("change", () => onChange(el.value));
    return el;
}

function searchBox(placeholder, value, onChange) {
    const input = h("input", { placeholder, value });
    input.addEventListener("input", () => {
        clearTimeout(logsTimer);
        logsTimer = setTimeout(() => onChange(input.value), 300);
    });
    return h("label", { class: "search" }, icon("i-search"), input);
}

function paintLogsFilters(tabs) {
    const v = logsView;
    logsDom.tabs.replaceChildren(...segmentedButtons(tabs, v.tab, (value) => { v.tab = value; paintLogsFilters(tabs); fetchLogs(false); }));

    if (v.tab === "actions") {
        logsDom.staffSelect = selectInput([{ value: "", label: "Tous les membres" }, ...v.staffList.map((m) => ({ value: m.license, label: m.name }))], v.staff, (value) => { v.staff = value; fetchLogs(false); });
        logsDom.filters.replaceChildren(
            selectInput(LOG_CATEGORIES, v.category, (value) => { v.category = value; fetchLogs(false); }),
            logsDom.staffSelect,
            h("div", { class: "segmented" }, ...segmentedButtons(LOG_PERIODS, v.period, (value) => { v.period = value; paintLogsFilters(tabs); fetchLogs(false); })),
            h("span", { class: "grow" }),
            searchBox("Joueur, membre, raison…", v.search, (value) => { v.search = value; fetchLogs(false); })
        );
    } else {
        logsDom.filters.replaceChildren(
            selectInput(CHAT_CHANNELS, v.channel, (value) => { v.channel = value; fetchLogs(false); }),
            h("div", { class: "segmented" }, ...segmentedButtons(LOG_PERIODS, v.chatPeriod, (value) => { v.chatPeriod = value; paintLogsFilters(tabs); fetchLogs(false); })),
            h("span", { class: "grow" }),
            searchBox("Joueur ou texte du message", v.chatSearch, (value) => { v.chatSearch = value; fetchLogs(false); })
        );
    }
}

async function fetchLogs(append) {
    const v = logsView;
    const chat = v.tab === "chat";
    const list = chat ? v.messages : v.logs;
    const before = append && list && list.length ? list[list.length - 1].id : undefined;

    if (!append) {
        if (chat) v.messages = null; else v.logs = null;
        paintLogs();
    }

    const payload = chat
        ? { channel: v.channel, period: v.chatPeriod, search: v.chatSearch, before }
        : { category: v.category, staff: v.staff, period: v.period, search: v.search, before };

    const request = ++logsRequest;
    let res;
    try {
        res = await nui("action", { action: chat ? "logs.chat" : "logs.list", payload });
    } catch (e) {
        return;
    }
    if (request !== logsRequest) return;

    if (!res || !res.ok) {
        if (res && res.error) toast(res.error, "error");
        if (chat) v.messages = v.messages || []; else v.logs = v.logs || [];
        return paintLogs();
    }

    if (chat) {
        const rows = Array.isArray(res.messages) ? res.messages : [];
        v.messages = append ? [...(v.messages || []), ...rows] : rows;
        v.chatMore = !!res.more;
    } else {
        const rows = Array.isArray(res.logs) ? res.logs : [];
        v.logs = append ? [...(v.logs || []), ...rows] : rows;
        v.more = !!res.more;
        const staffList = Array.isArray(res.staff) ? res.staff : [];
        if (JSON.stringify(staffList) !== JSON.stringify(v.staffList)) {
            v.staffList = staffList;
            const tabs = [];
            if (can("logs.view")) tabs.push({ value: "actions", label: "Actions du staff" });
            if (can("logs.chat")) tabs.push({ value: "chat", label: "Tchat" });
            paintLogsFilters(tabs);
        }
    }
    paintLogs();
}

function logRow(log) {
    const { verb, summary } = describeLog(log);
    const row = h("button", { class: "log-row" },
        h("span", { class: "log-date" }, fmtDate(log.created)),
        h("span", { class: "log-text" },
            h("b", null, log.actor || "?"), ` ${verb} `,
            log.target ? h("b", null, log.target) : null,
            summary ? h("span", { class: "log-summary" }, summary) : null
        ),
        icon("i-search")
    );
    row.addEventListener("click", () => openLogDetail(log));
    return row;
}

const CHANNEL_BADGES = { hrp: "HRP", me: "/me", do: "/do", staff: "Staff", announce: "Annonce", clear: "Vidage" };

function chatRow(m) {
    return h("div", { class: "log-row chat" },
        h("span", { class: "log-date" }, fmtDate(m.created)),
        h("span", { class: `badge ${m.channel === "staff" || m.channel === "announce" ? "warn" : "muted"}` }, CHANNEL_BADGES[m.channel] || m.channel),
        h("span", { class: "log-text" }, h("b", null, m.name), " ", m.message || (m.channel === "clear" ? "a vidé le tchat" : ""))
    );
}

function paintLogs() {
    const v = logsView;
    const chat = v.tab === "chat";
    const list = chat ? v.messages : v.logs;

    if (!list) {
        logsDom.body.replaceChildren(h("div", { class: "empty" }, "Chargement…"));
        logsDom.footer.replaceChildren();
        return;
    }

    logsDom.body.replaceChildren(...(list.length
        ? list.map(chat ? chatRow : logRow)
        : [h("div", { class: "empty" }, icon("i-list"), chat ? "Aucun message ne correspond." : "Aucune action ne correspond.")]));

    const more = chat ? v.chatMore : v.more;
    logsDom.footer.replaceChildren(more ? h("button", { class: "btn", onclick: () => fetchLogs(true) }, "Charger plus") : h("span"));
}

function detailValue(value) {
    if (value === null || value === undefined || value === "") return "—";
    if (typeof value === "object") return h("pre", { class: "detail-pre" }, JSON.stringify(value, null, 2));
    return String(value);
}

function openLogDetail(log) {
    const { verb, summary } = describeLog(log);
    const d = log.details && typeof log.details === "object" ? log.details : {};
    const rows = [
        ["Date", fmtDate(log.created)],
        ["Auteur", log.actor],
        ["Action", `${verb} (${log.action})`],
        ["Cible", log.target],
        ...Object.keys(d).map((key) => [DETAIL_LABELS[key] || key, d[key]]),
    ];

    openModal((close) => [
        h("header", null, h("h3", null, `${log.actor || "?"} ${verb}${log.target ? ` ${log.target}` : ""}`), summary ? h("p", null, summary) : null),
        h("div", { class: "body" }, h("div", { class: "detail-list" }, rows.map(([label, value]) =>
            h("div", { class: "detail-row" }, h("span", null, label), h("div", null, detailValue(value)))))),
        h("footer", null, h("button", { class: "btn", onclick: () => close() }, "Fermer")),
    ]);
}
