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
    "holdups.save": "a modifié un point de braquage",
    "blips.save": "a modifié un blip",
    "economy.salaries": "a modifié des salaires",
    "economy.settings": "a modifié l'économie",
    "images.save": "a modifié une image",
    "crews.wipe": "a remis à zéro un crew",
    "crews.point": "a modifié l'infrastructure d'un crew",
    "structures.vehicle": "a modifié le parc de véhicules de",
    "features.save": "a modifié les fonctionnalités",
    "crews.influence": "a effacé l'influence d'un crew",
    "crews.request": "a traité la demande de crew de",
    "images.delete": "a supprimé une image",
    "mugshots.retake": "a refait le mugshot de",
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
    "reports.take": "a pris en charge le report de",
    "economy.openInventory": "a ouvert l'inventaire de",
    "adminmode.on": "a activé le mode administration",
    "adminmode.off": "a coupé le mode administration",
    "reports.close": "a fermé le report de",
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
    "player.connect": "s'est connecté",
    "player.disconnect": "s'est déconnecté",
    "player.loaded": "a chargé son personnage",
    "player.respawn": "s'est réveillé à l'hôpital",
    "player.revive": "a réanimé",
    "money.add": "a reçu de l'argent",
    "money.remove": "a dépensé de l'argent",
    "money.set": "a eu son argent fixé",
    "job.change": "a changé de poste :",
    "item.give": "a donné un objet à",
    "item.drop": "a jeté un objet",
    "item.pickup": "a ramassé un objet",
    "company.grade": "a changé un grade chez",
    "company.fire": "a renvoyé un membre de",
    "company.recruit": "a recruté chez",
    "company.deposit": "a déposé sur le compte de",
    "company.withdraw": "a retiré du compte de",
    "vehicle.rent": "a loué",
    "vehicle.rent_return": "a rendu",
    "vehicle.service_out": "a sorti",
    "vehicle.service_in": "a rangé",
    "illegal.mission": "a terminé une mission illégale :",
    "illegal.drug_sell": "a vendu",
    "illegal.fence_sell": "a revendu au recelleur :",
};

const ACCOUNT_LABELS = { money: "liquide", bank: "banque", black_money: "argent sale" };
const DETAIL_LABELS = {
    reason: "Raison", before: "Avant", after: "Après", amount: "Montant", account: "Compte", operation: "Opération",
    count: "Quantité", item: "Objet", serverId: "ID joueur", license: "Licence", id: "Référence", hours: "Durée (heures)",
    removed: "Objets supprimés", permissions: "Permissions", level: "Niveau", rank: "Rang", from: "De", to: "Vers",
    type: "Type", color: "Couleur", name: "Nom",
};
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
            summary = `${d.tier === "premium_plus" ? "VIP+" : "VIP"} · ${d.days === "lifetime" ? "à vie" : `${d.days} jours`}`;
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
        case "crews.wipe":
            summary = [d.label, d.members ? `${d.members} membre(s) retiré(s)` : null].filter(Boolean).join(" · ");
            break;
        case "features.save":
            summary = [d.section, (d.changed || []).join(", ")].filter(Boolean).join(" · ");
            break;
        case "structures.vehicle":
            summary = [d.job, d.label, d.model, d.operation].filter(Boolean).join(" · ");
            break;
        case "crews.point":
            summary = [d.crew, d.kind, d.label, d.operation].filter(Boolean).join(" · ");
            break;
        case "crews.influence":
            summary = d.label || "";
            break;
        case "crews.request":
            summary = `${d.kind === "join" ? "rejoindre" : "créer"} ${d.label} · ${d.accept ? "acceptée" : "refusée"}`;
            break;
        case "images.save":
        case "images.delete":
            summary = [d.label || d.key, d.reset ? "image d'origine" : null].filter(Boolean).join(" · ");
            break;
        case "mugshots.retake":
            summary = d.all ? `tous les joueurs connectés (${d.count})` : d.identifier || "";
            break;
        case "economy.salaries":
            summary = [d.label || d.job, ...(d.changes || []).map((c) => `${c.label} ${c.before} → ${c.after}`)].join(" · ");
            break;
        case "economy.settings":
            summary = { aid: "Aide de l'État", bank: "Plafonds de banque", impound: "Fourrière", currency: "Devise", paycheck: "Intervalle de paie" }[d.section] || d.section;
            if (d.section === "currency" && d.after) summary += ` · ${(d.before || {}).currency} → ${d.after.currency}`;
            if (d.section === "paycheck" && d.after) summary += ` · ${(d.before || {}).paycheckMinutes} → ${d.after.paycheckMinutes} min`;
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
            summary = [d.item, d.price !== undefined ? `${d.price} ${currencySymbol()}` : null, d.category, d.operation].filter(Boolean).join(" · ");
            break;
        case "drugs.save":
        case "drugs.delete":
        case "drugs.lab":
            summary = [d.item, d.crewType, d.price !== undefined ? `${d.price} ${currencySymbol()}` : null, d.operation].filter(Boolean).join(" · ");
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
        case "holdups.save":
        case "blips.save":
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
        case "money.add":
        case "money.remove":
        case "money.set":
            summary = [`${money(d.amount)} ${ACCOUNT_LABELS[d.account] || d.account || ""}`, d.reason].filter(Boolean).join(" · ");
            break;
        case "item.give":
        case "item.drop":
        case "item.pickup":
            summary = `${d.count || 1} × ${d.label || d.item || "?"}`;
            break;
        case "job.change":
            summary = `${d.from || "?"} → ${d.to || "?"}`;
            break;
        case "company.deposit":
        case "company.withdraw":
            summary = money(d.amount);
            break;
        case "vehicle.rent":
        case "vehicle.rent_return":
        case "vehicle.service_out":
        case "vehicle.service_in":
            summary = d.plate ? `plaque ${d.plate}` : "";
            break;
        case "illegal.mission":
            summary = d.reward ? money(d.reward) : "";
            break;
        case "illegal.drug_sell":
        case "illegal.fence_sell":
            summary = `${d.quantity} pour ${money(d.total)}${d.territory ? ` · ${d.territory}` : ""}`;
            break;
        case "player.respawn":
            summary = d.fee ? `frais ${money(d.fee)}` : "";
            break;
        default:
            summary = d.reason || "";
    }

    return { verb, summary };
}

// ---------- Page Logs (comme Vision : recherche, niveaux, catégories, liste, détail) ----------

const LOG_CATEGORY_LIST = [
    { value: "all", label: "Tous", icon: "i-list" },
    { value: "players", label: "Joueurs", icon: "i-player" },
    { value: "economy", label: "Économie", icon: "i-coins" },
    { value: "inventory", label: "Inventaire", icon: "i-box" },
    { value: "vehicles", label: "Véhicules", icon: "i-car" },
    { value: "staff", label: "Staff", icon: "i-shield" },
    { value: "companies", label: "Sociétés", icon: "i-store" },
    { value: "illegal", label: "Illégal", icon: "i-mask" },
    { value: "chat", label: "Chat", icon: "i-edit" },
    { value: "anticheat", label: "Anti-Cheat", icon: "i-lock" },
];
const LOG_LEVELS = [
    { value: "all", label: "Tous" },
    { value: "info", label: "Info", color: "#5b9cff" },
    { value: "warn", label: "Avertissement", color: "#f2a33c" },
    { value: "error", label: "Erreur", color: "#ef5b5b" },
    { value: "success", label: "Succès", color: "#3ecf8e" },
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
const CHANNEL_BADGES = { hrp: "HRP", me: "/me", do: "/do", staff: "Staff", announce: "Annonce", clear: "Vidage" };

const logsView = {
    category: "all", level: "all", period: "week", search: "", staff: "", channel: "",
    logs: null, more: false, staffList: [], levels: {}, categories: {}, messages: null, chatMore: false, sel: null,
};
let logsTimer = null;
let logsRequest = 0; // une réponse arrivée après un changement de filtre est ignorée

function renderLogs() {
    if (!can("logs.view") && logsView.category !== "chat") logsView.category = "chat";
    if (!$("view-logs").childElementCount || (logsView.logs === null && logsView.messages === null)) {
        paintLogs();
        fetchLogs(false);
    }
}

function selectInput(options, current, onChange) {
    const el = h("select", { class: "input" }, options.map((o) => h("option", { value: o.value, selected: o.value === current }, o.label)));
    el.addEventListener("change", () => onChange(el.value));
    return el;
}

function logsGo(changes) {
    Object.assign(logsView, changes, { sel: null });
    fetchLogs(false);
}

async function fetchLogs(append) {
    const v = logsView;
    const chat = v.category === "chat";
    const list = chat ? v.messages : v.logs;
    const before = append && list && list.length ? list[list.length - 1].id : undefined;

    if (!append) {
        if (chat) v.messages = null; else v.logs = null;
        paintLogs();
    }

    const payload = chat
        ? { channel: v.channel, period: v.period, search: v.search, before }
        : { category: v.category, level: v.level, staff: v.category === "staff" ? v.staff : "", period: v.period, search: v.search, before };

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
        v.staffList = Array.isArray(res.staff) ? res.staff : v.staffList;
        if (!append) {
            v.levels = res.levels || {};
            v.categories = res.categories || {};
        }
    }
    paintLogs();
}

const logIdentifier = (log) => (log.actorLicense ? String(log.actorLicense).replace(/^license:/, "") : null);
const levelOf = (value) => LOG_LEVELS.find((l) => l.value === value) || LOG_LEVELS[1];
const categoryOf = (value) => LOG_CATEGORY_LIST.find((c) => c.value === value) || { label: value, icon: "i-list" };

function logTime(created) {
    const date = new Date(created * 1000);
    return [date.toLocaleDateString("fr-FR", { day: "2-digit", month: "2-digit" }), date.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })];
}

function logRow(log) {
    const { verb, summary } = describeLog(log);
    const level = levelOf(log.level);
    const [day, time] = logTime(log.created);
    const dot = h("span", { class: "log-dot" });
    dot.style.background = level.color;
    return h("button", { class: `log-item${logsView.sel === log.id ? " on" : ""}`, onclick: () => { logsView.sel = log.id; paintLogs(); } },
        mugshotImg(logIdentifier(log), "mug-row"),
        dot,
        h("span", { class: "log-main" },
            h("span", { class: "log-who" }, h("b", null, log.actor || "Console"), log.serverId ? h("span", { class: "muted mono" }, ` ${log.serverId}`) : null,
                h("span", { class: "log-badge" }, categoryOf(log.category).label)),
            h("span", { class: "log-line" }, `${verb}${log.target ? ` ${log.target}` : ""}${summary ? ` · ${summary}` : ""}`)),
        h("span", { class: "log-when mono" }, h("small", null, day), time));
}

function chatRow(m) {
    const [day, time] = logTime(m.created);
    return h("div", { class: "log-item chat" },
        h("span", { class: "mugshot mug-row" }, icon("i-edit")),
        h("span", { class: "log-main" },
            h("span", { class: "log-who" }, h("b", null, m.name), h("span", { class: `log-badge${m.channel === "staff" || m.channel === "announce" ? " warn" : ""}` }, CHANNEL_BADGES[m.channel] || m.channel)),
            h("span", { class: "log-line" }, m.message || (m.channel === "clear" ? "a vidé le tchat" : ""))),
        h("span", { class: "log-when mono" }, h("small", null, day), time));
}

function detailValue(value) {
    if (value === null || value === undefined || value === "") return "—";
    if (typeof value === "object") return h("pre", { class: "detail-pre" }, JSON.stringify(value, null, 2));
    return String(value);
}

function logDetail() {
    const log = (logsView.logs || []).find((l) => l.id === logsView.sel);
    if (!log) return h("aside", { class: "crew-col logs-detail" }, h("div", { class: "crew-col-head" }, icon("i-search"), "Détail"), h("div", { class: "empty" }, icon("i-list"), "Cliquez sur un log pour voir le détail."));
    const { verb, summary } = describeLog(log);
    const d = log.details && typeof log.details === "object" ? log.details : {};
    const level = levelOf(log.level);
    const date = new Date(log.created * 1000);
    const rows = [
        ["Joueur", `${log.actor || "Console"}${log.serverId ? ` (ID ${log.serverId})` : ""}`],
        ["Catégorie", categoryOf(log.category).label],
        ["Niveau", level.label],
        ["Action", `${verb} (${log.action})`],
        ["Cible", log.target],
        ["Détails", summary],
        ["Raison", d.reason],
        ["Horodatage", `${date.toLocaleDateString("fr-FR")} à ${date.toLocaleTimeString("fr-FR")}`],
        ...Object.keys(d).filter((k) => k !== "reason").map((key) => [DETAIL_LABELS[key] || key, d[key]]),
    ];
    return h("aside", { class: "crew-col logs-detail" },
        h("div", { class: "crew-col-head" }, icon("i-search"), "Détail"),
        h("div", { class: "crew-scroll crew-col-body" },
            h("div", { class: "logs-detail-head" }, mugshotImg(logIdentifier(log), "mug-head"), h("span", null, h("b", null, log.actor || "Console"), h("span", { class: "log-badge" }, categoryOf(log.category).label))),
            h("div", { class: "detail-list" }, rows.filter(([, value]) => value !== undefined && value !== null && value !== "").map(([label, value]) =>
                h("div", { class: "detail-row" }, h("span", null, label), h("div", null, detailValue(value)))))));
}

function paintLogs() {
    const root = $("view-logs");
    const v = logsView;
    const chat = v.category === "chat";
    const list = chat ? v.messages : v.logs;

    const search = h("input", { placeholder: chat ? "Joueur ou texte du message…" : "Rechercher un joueur, une action, un ID…", value: v.search });
    search.addEventListener("input", () => {
        clearTimeout(logsTimer);
        logsTimer = setTimeout(() => logsGo({ search: search.value }), 300);
    });

    const totalLevels = Object.values(v.levels).reduce((a, b) => a + b, 0);
    const chips = chat ? null : h("div", { class: "log-levels" }, LOG_LEVELS.map((l) => {
        const dot = h("span", { class: "log-dot" });
        if (l.color) dot.style.background = l.color;
        return h("button", { class: `log-level${v.level === l.value ? " on" : ""}`, onclick: () => v.level !== l.value && logsGo({ level: l.value }) },
            l.color ? dot : null, l.label, h("span", { class: "cnt" }, String(l.value === "all" ? totalLevels : v.levels[l.value] || 0)));
    }));

    const totalCategories = Object.values(v.categories).reduce((a, b) => a + b, 0);
    const categories = LOG_CATEGORY_LIST.filter((c) => (c.value === "chat" ? can("logs.chat") : can("logs.view")));
    const nav = h("aside", { class: "sidebar crew-nav crew-scroll" },
        h("div", { class: "crew-block" },
            h("div", { class: "crew-block-head" }, icon("i-layers"), "Catégories"),
            categories.map((c) => h("button", { class: `list-row${v.category === c.value ? " active" : ""}`, onclick: () => v.category !== c.value && logsGo({ category: c.value }) },
                icon(c.icon), h("span", { class: "name" }, c.label),
                c.value === "chat" ? null : h("span", { class: "cnt" }, String(c.value === "all" ? totalCategories : v.categories[c.value] || 0))))));

    let body;
    if (!list) body = h("div", { class: "empty" }, "Chargement…");
    else if (!list.length) body = h("div", { class: "empty" }, icon("i-list"), chat ? "Aucun message ne correspond." : "Aucun log ne correspond.");
    else {
        if (!chat) loadMugshots(list.map(logIdentifier)).then((found) => found && paintLogs());
        body = h("div", { class: "log-list" }, list.map(chat ? chatRow : logRow));
    }
    const more = chat ? v.chatMore : v.more;
    const category = categoryOf(v.category);

    const main = h("section", { class: "crew-col" },
        h("div", { class: "crew-col-head" }, icon(category.icon), v.category === "all" ? "Tous les logs" : category.label, h("span", { class: "cnt" }, String(list ? list.length : 0))),
        h("div", { class: "crew-scroll crew-col-body" }, body,
            more ? h("div", { class: "btn-row", style: "justify-content:center;margin-top:10px" }, h("button", { class: "btn small ghost", onclick: () => fetchLogs(true) }, "Charger plus")) : null),
        h("div", { class: "it-actions" },
            h("div", { class: "segmented" }, ...segmentedButtons(LOG_PERIODS, v.period, (value) => logsGo({ period: value }))),
            v.category === "staff" ? selectInput([{ value: "", label: "Tous les membres" }, ...v.staffList.map((m) => ({ value: m.license, label: m.name }))], v.staff, (value) => logsGo({ staff: value })) : null,
            chat ? selectInput(CHAT_CHANNELS, v.channel, (value) => logsGo({ channel: value })) : null,
            h("button", { class: "btn small ok-btn", style: "margin-left:auto", onclick: () => fetchLogs(false) }, icon("i-undo"), "Rafraîchir")));

    const keep = [...root.querySelectorAll(".crew-scroll")].map((el) => el.scrollTop);
    const focused = document.activeElement && document.activeElement.closest && document.activeElement.closest(".logs-search");
    root.replaceChildren(h("div", { class: "img-page logs-page" },
        h("div", { class: "logs-top" }, h("label", { class: "search logs-search" }, icon("i-search"), search), chips),
        h("div", { class: `crew-page logs-grid${chat ? " chat" : ""}` }, nav, main, chat ? null : logDetail())));
    root.querySelectorAll(".crew-scroll").forEach((el, index) => { if (keep[index]) el.scrollTop = keep[index]; });
    if (focused) {
        const again = root.querySelector(".logs-search input");
        again.focus();
        again.setSelectionRange(again.value.length, again.value.length);
    }
}
