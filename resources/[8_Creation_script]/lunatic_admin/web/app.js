"use strict";

// ====================================================================
//  lunatic_admin — interface du panel staff
//  L'interface n'a aucun pouvoir : chaque action est revérifiée par le serveur.
// ====================================================================

const IN_GAME = typeof GetParentResourceName === "function";
const RESOURCE = IN_GAME ? GetParentResourceName() : "lunatic_admin";
const SWATCHES = ["#9650ff", "#ff6b6b", "#f2c26b", "#5fd3a0", "#6bb8f2", "#ff8ad8", "#a3a3b2", "#ffffff"];

let state = null;
let view = "home";
let selectedRankId = null;
let draft = null; // copie modifiable du rang affiché dans l'éditeur
let busy = false;
const memberFilter = { text: "", onlineOnly: false };

// ---------- Outils DOM ----------

const $ = (id) => document.getElementById(id);

function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
        if (value === null || value === undefined || value === false) continue;
        if (key === "class") el.className = value;
        else if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
        else if (value === true) el.setAttribute(key, "");
        else el.setAttribute(key, value);
    }
    for (const child of children.flat()) {
        if (child === null || child === undefined || child === false) continue;
        el.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return el;
}

function icon(name) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("class", "i");
    const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
    use.setAttribute("href", `#${name}`);
    svg.append(use);
    return svg;
}

function dot(color) {
    const el = h("span", { class: "dot" });
    el.style.background = color;
    return el;
}

function rankPill(rank) {
    if (!rank) return h("span", { class: "rank-pill muted" }, "Rang inconnu");
    return h("span", { class: "rank-pill" }, dot(rank.color), rank.name);
}

function initials(name) {
    return (name || "?").trim().slice(0, 1).toUpperCase();
}

function shortLicense(license) {
    if (!license) return "";
    const id = license.replace(/^license:/, "");
    return `license:${id.slice(0, 6)}…${id.slice(-4)}`;
}

// ---------- Communication avec le jeu ----------

async function nui(name, data) {
    if (!IN_GAME) return demoNui(name, data);
    const response = await fetch(`https://${RESOURCE}/${name}`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify(data || {}),
    });
    return response.json();
}

async function act(action, payload, okMessage) {
    if (busy) return null;
    busy = true;
    try {
        const res = await nui("action", { action, payload });
        if (!res || !res.ok) {
            toast((res && res.error) || "Action impossible.", "error");
            return null;
        }
        if (res.state) applyState(res.state, true);
        if (okMessage) toast(okMessage, "ok");
        return res;
    } catch (e) {
        toast("Pas de réponse du serveur.", "error");
        return null;
    } finally {
        busy = false;
    }
}

function closePanel() {
    closeModal();
    document.body.classList.add("hidden");
    nui("close");
}

// ---------- Permissions (affichage seulement) ----------

const can = (perm) => !!state && state.me.permissions.includes(perm);
const myLevel = () => state.me.rank.level;
const iAmOwner = () => state.me.rank.owner;
const ranks = () => state.ranks || [];
const staff = () => state.staff || [];
const rankById = (id) => ranks().find((r) => r.id === id);

function canEditRank(rank) {
    if (!can("ranks.manage")) return false;
    return rank.owner ? iAmOwner() : rank.level < myLevel();
}

function canAssign(rank) {
    return can("staff.manage") && !rank.owner && rank.level < myLevel();
}

function canManageMember(member) {
    if (!can("staff.manage") || member.license === state.me.license) return false;
    const rank = rankById(member.rankId);
    return !rank || rank.level < myLevel();
}

function freeLevelBelow(max) {
    for (let level = max - 1; level >= 1; level--) {
        if (!ranks().some((r) => r.level === level)) return level;
    }
    return null;
}

// ---------- État ----------

// Une table Lua vide peut arriver sous forme d'objet {} : on force des tableaux partout
const list = (value) => (Array.isArray(value) ? value : []);

function normalize(raw) {
    raw.me.permissions = list(raw.me.permissions);
    raw.catalogue.families = list(raw.catalogue.families);
    raw.catalogue.permissions = list(raw.catalogue.permissions);
    if (raw.ranks) raw.ranks = list(raw.ranks).map((r) => ({ ...r, permissions: r.permissions === undefined ? undefined : list(r.permissions) }));
    if (raw.staff) raw.staff = list(raw.staff);
    if (raw.candidates) raw.candidates = list(raw.candidates);
    if (raw.players) raw.players = list(raw.players);
    if (raw.recent) raw.recent = list(raw.recent);
    raw.tools = raw.tools && typeof raw.tools === "object" && !Array.isArray(raw.tools) ? raw.tools : {};
    return raw;
}

function applyState(next, fromAction) {
    const keepDraft = !fromAction && draft && isDirty();
    state = normalize(next);

    if (!NAV.find((n) => n.id === view && n.show())) view = "home";

    if (draft && draft.id !== null && !rankById(draft.id)) {
        draft = null;
        selectedRankId = null;
    }

    if (!keepDraft) loadDraft();
    return keepDraft;
}

function loadDraft() {
    if (draft && draft.id === null && isDirty()) return;
    const rank = rankById(selectedRankId);
    if (!rank) {
        draft = null;
        return;
    }
    draft = {
        id: rank.id,
        name: rank.name,
        color: rank.color,
        level: rank.level,
        owner: rank.owner,
        permissions: new Set(rank.permissions || []),
    };
}

function isDirty() {
    if (!draft) return false;
    if (draft.id === null) return true;
    const rank = rankById(draft.id);
    if (!rank) return false;
    const perms = rank.permissions || [];
    return draft.name !== rank.name
        || draft.color !== rank.color
        || Number(draft.level) !== rank.level
        || perms.length !== draft.permissions.size
        || perms.some((p) => !draft.permissions.has(p));
}

// ---------- Rendu général ----------

// Pages du panel. L'accueil affiche une tuile par page visible (dans cet ordre) ;
// les pages d'un même groupe partagent une tuile et s'affichent en onglets dans la barre du haut.
const NAV = [
    { id: "home", label: "Gestion", icon: "i-home", show: () => true, tile: false },
    { id: "dashboard", label: "Tableau de bord", icon: "i-pulse", show: () => true },
    { id: "players", label: "Joueurs", icon: "i-player", show: () => can("players.view") },
    { id: "sanctions", label: "Sanctions", icon: "i-gavel", show: () => can("sanctions.view") },
    { id: "tools", label: "Outils", icon: "i-tool", show: () => hasAnyTool() },
    { id: "logs", label: "Logs", icon: "i-list", show: () => can("logs.view") || can("logs.chat") },
    { id: "ranks", label: "Rangs", icon: "i-layers", show: () => can("ranks.view"), group: "perms" },
    { id: "members", label: "Membres", icon: "i-users", show: () => can("staff.view"), group: "perms" },
    { id: "companies", label: "Entreprises", icon: "i-store", show: () => can("companies.manage") },
    { id: "publics", label: "Services publics", icon: "i-shield", show: () => can("publics.manage") },
    { id: "poles", label: "Pôle emploi", icon: "i-briefcase", show: () => can("poles.manage") },
    { id: "events", label: "Events", icon: "i-calendar", show: () => can("events.manage") },
    { id: "world", label: "Météo", icon: "i-sun", show: () => hasWorld() },
    { id: "server", label: "Serveur", icon: "i-server", show: () => can("server.manage") },
    { id: "dev", label: "Développeur", icon: "i-code", show: () => can("dev.manage") },
];
const GROUPS = { perms: { label: "Permissions", icon: "i-lock" } };

// Tuiles de l'accueil : une par page, une seule par groupe (vers la première page autorisée du groupe)
function tiles() {
    const list = [];
    const seen = new Set();
    for (const page of NAV) {
        if (page.tile === false || !page.show()) continue;
        if (page.group) {
            if (seen.has(page.group)) continue;
            seen.add(page.group);
            list.push({ target: page.id, label: GROUPS[page.group].label, icon: GROUPS[page.group].icon });
        } else {
            list.push({ target: page.id, label: page.label, icon: page.icon });
        }
    }
    return list;
}

function renderTopbar() {
    const page = NAV.find((n) => n.id === view) || NAV[0];
    const home = view === "home";
    $("brand").style.display = home ? "" : "none";
    $("crumb").style.display = home ? "none" : "";

    if (!home) {
        const title = page.group ? GROUPS[page.group].label : page.label;
        $("crumb").replaceChildren(
            h("button", { class: "crumb-back", title: "Retour à la gestion", onclick: () => go("home") }, icon("i-back")),
            h("button", { class: "crumb-root", onclick: () => go("home") }, "Gestion"),
            h("span", { class: "crumb-page" }, title)
        );
    }

    // Onglets du groupe de la page (ex. Permissions : Rangs / Membres)
    const siblings = page.group ? NAV.filter((n) => n.group === page.group && n.show()) : [];
    $("nav").classList.toggle("empty", siblings.length < 2);
    $("nav").replaceChildren(...(siblings.length < 2 ? [] : siblings.map((n) =>
        h("button", { class: `nav-link${view === n.id ? " active" : ""}`, onclick: () => go(n.id) }, icon(n.icon), n.label))));
}

function render() {
    if (!state) return;

    renderTopbar();

    const me = state.me;
    $("me").replaceChildren(
        h("span", { class: "avatar" }, initials(me.name)),
        h("span", { class: "who" }, h("b", null, me.name), h("span", { class: "muted" }, me.rank.name))
    );
    $("me").querySelector(".avatar").style.background = me.rank.color;

    for (const id of ["home", "dashboard", "players", "sanctions", "tools", "logs", "world", "server", "companies", "publics", "poles", "events", "dev", "ranks", "members"]) {
        $(`view-${id}`).classList.toggle("on", view === id);
    }

    if (view === "home") renderHome();
    if (view === "dashboard") renderDashboard();
    if (view === "players") renderPlayers();
    if (view === "sanctions") renderSanctions();
    if (view === "tools") renderTools();
    if (view === "logs") renderLogs();
    if (view === "world") renderWorld();
    if (view === "server") renderGlobal();
    if (view === "poles") renderPoles();
    if (view === "companies") renderStructures("company");
    if (view === "publics") renderStructures("public");
    if (view === "events") renderEvents();
    if (view === "dev") renderDev();
    if (view === "ranks") renderRanks();
    if (view === "members") renderMembers();
}

function go(target) {
    if (view === "ranks" && target !== "ranks" && isDirty()) {
        confirmBox("Modifications non enregistrées", "Quitter cette page annule les changements du rang en cours.", "Quitter sans enregistrer", true)
            .then((yes) => {
                if (!yes) return;
                draft = null;
                loadDraft();
                view = target;
                render();
            });
        return;
    }
    view = target;
    render();
}

// ---------- Accueil : grille de tuiles ----------

function homeKpis() {
    const d = state.dashboard || {};
    const kpis = [h("div", { class: "kpi" }, h("span", null, "Joueurs en ligne"), h("b", null, `${d.players ?? "—"}`), h("small", null, `sur ${d.maxPlayers ?? "?"} places`))];
    if (Array.isArray(d.staff)) kpis.push(h("div", { class: "kpi" }, h("span", null, "Staff en ligne"), h("b", null, `${d.staff.length}`), h("small", null, d.staff.length ? "membres connectés" : "aucun membre connecté")));
    if (d.sanctions) kpis.push(h("div", { class: "kpi" }, h("span", null, "Bans (24 h)"), h("b", null, `${d.sanctions.bans24h ?? 0}`), h("small", null, `${d.sanctions.activeBans ?? 0} bans actifs`)));
    return kpis;
}

function renderHome() {
    $("view-home").replaceChildren(h("div", { class: "home menu" },
        h("div", { class: "kpis menu-kpis" }, homeKpis()),
        h("div", { class: "tiles" }, tiles().map((t) =>
            h("button", { class: "tile", onclick: () => go(t.target) }, icon(t.icon), h("span", null, t.label))))
    ));
}

// ---------- Tableau de bord ----------

function renderDashboard() {
    const d = state.dashboard || {};
    const showStaff = Array.isArray(d.staff); // permission staff.online
    const staffOnline = showStaff ? d.staff : [];

    // Chiffres clés
    const kpis = [
        h("div", { class: "kpi" }, h("span", null, "Joueurs en ligne"), h("b", null, `${d.players ?? "—"}`), h("small", null, `sur ${d.maxPlayers ?? "?"} places`)),
    ];
    if (showStaff) {
        kpis.push(h("div", { class: "kpi" }, h("span", null, "Staff en ligne"), h("b", null, `${staffOnline.length}`), h("small", null, staffOnline.length ? "membres connectés" : "aucun membre connecté")));
    }
    if (d.sanctions) {
        kpis.push(
            h("div", { class: "kpi" }, h("span", null, "Bans actifs"), h("b", null, `${d.sanctions.activeBans ?? 0}`), h("small", null, `${d.sanctions.bans24h ?? 0} sur les dernières 24 h`)),
            h("div", { class: "kpi" }, h("span", null, "Avertissements"), h("b", null, `${d.sanctions.warns24h ?? 0}`), h("small", null, "sur les dernières 24 h"))
        );
    }

    // Courbe de fréquentation
    const chartCard = h("div", { class: "card dash-chart" },
        h("h3", { class: "card-title" }, "Fréquentation (24 h)"),
        playersChart(Array.isArray(d.history) ? d.history : [], d.maxPlayers)
    );

    // Staff en ligne
    const staffCard = !showStaff ? null : h("div", { class: "card" },
        h("h3", { class: "card-title" }, "Staff en ligne"),
        staffOnline.length
            ? h("div", { class: "dash-staff" }, staffOnline.map((m) => h("div", { class: "dash-staff-row" },
                h("span", { class: "status on" }),
                h("b", null, m.name),
                h("span", { class: "muted mono" }, `ID ${m.serverId}`),
                rankPill(m.rank))))
            : h("span", { class: "muted" }, "Aucun membre du staff connecté.")
    );

    // Dernières actions du staff
    const recent = Array.isArray(d.recent) ? d.recent : null;
    const recentCard = recent ? h("div", { class: "card dash-recent" },
        h("div", { class: "card-head" },
            h("h3", { class: "card-title" }, "Dernières actions du staff"),
            h("button", { class: "link", onclick: () => go("logs") }, "Voir tous les logs →")
        ),
        recent.length
            ? h("div", { class: "table" }, recent.map((log) => {
                const { verb, summary } = describeLog(log);
                return h("div", { class: "dash-log" },
                    h("span", { class: "log-date" }, ago(log.created)),
                    h("span", { class: "log-text" }, h("b", null, log.actor || "?"), ` ${verb} `, log.target ? h("b", null, log.target) : null,
                        summary ? h("span", { class: "log-summary" }, summary) : null)
                );
            }))
            : h("span", { class: "muted" }, "Aucune action enregistrée.")
    ) : null;

    $("view-dashboard").replaceChildren(h("div", { class: "home" },
        h("div", { class: "kpis", style: "margin-top:0" }, kpis),
        h("div", { class: `dash-grid${showStaff ? "" : " single"}` }, chartCard, staffCard),
        recentCard
    ));
}

// Courbe SVG du nombre de joueurs (relevés du serveur, 24 h glissantes)
function playersChart(samples, maxPlayers) {
    if (samples.length < 2) {
        return h("div", { class: "muted dash-empty" }, "Pas encore assez de relevés : la courbe se remplit toutes les 5 minutes depuis le démarrage du serveur.");
    }

    const width = 600;
    const height = 150;
    const pad = 6;
    const first = samples[0].t;
    const last = samples[samples.length - 1].t;
    const span = Math.max(1, last - first);
    const top = Math.max(4, ...samples.map((s) => s.n));
    const x = (t) => pad + ((t - first) / span) * (width - pad * 2);
    const y = (n) => height - pad - (n / top) * (height - pad * 2);
    const points = samples.map((s) => `${x(s.t).toFixed(1)},${y(s.n).toFixed(1)}`).join(" ");
    const area = `${pad},${height - pad} ${points} ${width - pad},${height - pad}`;
    const peak = Math.max(...samples.map((s) => s.n));

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
    svg.setAttribute("preserveAspectRatio", "none");
    svg.setAttribute("class", "chart");
    svg.innerHTML = `
        <defs><linearGradient id="chartFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stop-color="rgb(150,80,255)" stop-opacity=".45"/><stop offset="1" stop-color="rgb(150,80,255)" stop-opacity="0"/>
        </linearGradient></defs>
        <polygon points="${area}" fill="url(#chartFill)"/>
        <polyline points="${points}" fill="none" stroke="rgb(170,110,255)" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>`;

    const time = (t) => new Date(t * 1000).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
    return h("div", null,
        svg,
        h("div", { class: "chart-legend" },
            h("span", null, time(first)),
            h("span", null, `Pic : ${peak} joueur${peak > 1 ? "s" : ""}${maxPlayers ? ` / ${maxPlayers}` : ""}`),
            h("span", null, time(last))
        )
    );
}

// ---------- Joueurs ----------

let selectedPlayerId = null;
let playerInfo = null; // fiche chargée depuis le serveur, false = joueur introuvable
const playerFilter = { text: "" };
let playersDom = null;

const money = (n) => (typeof n === "number" ? `${new Intl.NumberFormat("fr-FR").format(n)} $` : "—");
const players = () => state.players || [];

function renderPlayers() {
    const root = $("view-players");

    // La structure est gardée entre deux rafraîchissements (recherche et défilement conservés)
    if (!playersDom || !root.contains(playersDom.list)) {
        const search = h("input", { placeholder: "Nom ou ID", value: playerFilter.text });
        search.addEventListener("input", () => {
            playerFilter.text = search.value;
            if (playersTab === "offline") scheduleOfflineSearch(search.value);
            else paintPlayerList();
        });
        playersDom = {
            title: h("h3", null, "Joueurs en ligne"),
            count: h("span", { class: "muted mono" }),
            tabs: h("div", { class: "segmented block" }),
            search,
            list: h("div", { class: "side-scroll" }),
            fiche: h("div", { class: "content" }),
        };
        root.replaceChildren(
            h("aside", { class: "sidebar" },
                h("div", { class: "side-head" }, playersDom.title, playersDom.count),
                h("div", { class: "side-search" }, playersDom.tabs),
                h("div", { class: "side-search" }, h("label", { class: "search" }, icon("i-search"), search)),
                playersDom.list
            ),
            playersDom.fiche
        );
    }

    // Onglets En ligne / Hors ligne (permission players.offline)
    if (!can("players.offline")) playersTab = "online";
    playersDom.tabs.style.display = can("players.offline") ? "" : "none";
    playersDom.tabs.replaceChildren(...[["online", "En ligne"], ["offline", "Hors ligne"]].map(([value, label]) =>
        h("button", { "aria-checked": String(playersTab === value), onclick: () => switchPlayersTab(value) }, label)));
    playersDom.title.textContent = playersTab === "offline" ? "Recherche en base" : "Joueurs en ligne";
    playersDom.search.placeholder = playersTab === "offline" ? "Nom RP ou licence (2 caractères min.)" : "Nom ou ID";

    paintPlayerList();
    paintFiche();
}

function paintPlayerList() {
    if (playersTab === "offline") return paintOfflineList();
    const text = playerFilter.text.trim().toLowerCase();
    const rows = players().filter((p) => !text || p.name.toLowerCase().includes(text) || String(p.serverId) === text);
    playersDom.count.textContent = String(players().length);

    playersDom.list.replaceChildren(...(rows.length ? rows.map((p) => {
        const row = h("button", { class: `list-row player-row${p.serverId === selectedPlayerId ? " active" : ""}`, onclick: () => selectPlayer(p.serverId) },
            h("span", { class: "pid" }, `${p.serverId}`),
            h("span", { class: "who" },
                h("b", null, p.name),
                h("span", null, [p.job, `${p.ping} ms`].filter(Boolean).join(" · "))
            ),
            p.frozen ? icon("i-snow") : null,
            p.jailed ? icon("i-lock") : null,
            p.rank ? dot(p.rank.color) : null
        );
        if (p.rank) row.title = p.rank.name;
        return row;
    }) : [h("div", { class: "muted side-empty" }, "Aucun joueur ne correspond.")]));
}

function selectPlayer(id) {
    if (selectedPlayerId === id) return;
    economyPanel = null;
    premiumPanel = null;
    selectedPlayerId = id;
    playerInfo = null;
    playerHistory = null;
    paintPlayerList();
    paintFiche();
    loadPlayerInfo();
}

async function loadPlayerInfo() {
    const id = selectedPlayerId;
    if (id === null) return;
    try {
        const res = await nui("action", { action: "player.info", payload: { serverId: id } });
        if (id !== selectedPlayerId) return;
        playerInfo = res && res.ok ? res.info : false;
    } catch (e) {
        return;
    }
    if (playerInfo && can("sanctions.view") && (!playerHistory || playerHistory.license !== playerInfo.license)) loadPlayerHistory(playerInfo.license);
    paintFiche();
}

function infoRow(label, value) {
    return h("div", { class: "info-row" }, h("span", null, label), h("b", null, value === undefined || value === null || value === "" ? "—" : value));
}

function bar(label, value, pct, color) {
    const fill = h("i");
    fill.style.width = `${Math.max(0, Math.min(100, pct))}%`;
    fill.style.background = color;
    return h("div", { class: "bar-row" }, h("div", { class: "info-row" }, h("span", null, label), h("b", null, value)), h("div", { class: "bar" }, fill));
}

function paintFiche() {
    if (playersTab === "offline") return paintOfflineFiche();
    const fiche = playersDom.fiche;

    if (selectedPlayerId === null) {
        return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-player"), "Sélectionnez un joueur pour voir sa fiche."));
    }
    if (playerInfo === false || !players().some((p) => p.serverId === selectedPlayerId)) {
        return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-door"), "Ce joueur n'est plus connecté."));
    }
    if (!playerInfo) {
        return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-player"), "Chargement de la fiche…"));
    }

    const info = playerInfo;

    // Garde la position de défilement entre deux rafraîchissements de la même fiche
    const previous = fiche.querySelector(".scroll");
    const keepScroll = previous && fiche.dataset.player === String(info.serverId) ? previous.scrollTop : 0;
    fiche.dataset.player = String(info.serverId);

    const reason = (perm, opts = {}) => {
        if (!can(perm)) return "Permission manquante";
        if (opts.notSelf && info.isSelf) return "Impossible sur vous-même";
        if (opts.protect && info.protected) return "Rang égal ou supérieur au vôtre";
        return opts.extra || null;
    };
    const button = (label, iconName, perm, opts, onclick) => {
        const blocked = reason(perm, opts);
        return h("button", { class: `btn action${opts.danger ? " danger" : ""}`, disabled: !!blocked, title: blocked, onclick }, icon(iconName), label);
    };
    const run = (action, okMessage, payload) => playerAction(action, okMessage, payload);

    const health = typeof info.health === "number" ? info.health : null;
    const maxHealth = info.maxHealth || 200;
    // Pour un joueur GTA, la vie va de 100 (au sol) à 200
    const healthPct = health === null ? 0 : ((health - 100) / Math.max(1, maxHealth - 100)) * 100;
    const down = health !== null && health <= 100;

    const sex = info.sex === "m" ? "Homme" : info.sex === "f" ? "Femme" : null;

    fiche.replaceChildren(
        h("div", { class: "page-head" },
            h("div", { class: "grow" },
                h("h1", { class: "page-title" }, info.name, info.rank ? rankPill(info.rank) : null),
                h("div", { class: "page-sub" },
                    `ID ${info.serverId}`, h("span", { class: "sep" }), info.pseudo || "—", h("span", { class: "sep" }),
                    h("span", { class: "mono" }, shortLicense(info.license)),
                    info.isSelf ? [h("span", { class: "sep" }), h("span", { class: "you" }, "Vous")] : null
                )
            )
        ),
        h("div", { class: "scroll" },
            h("div", { class: "card" },
                h("div", { class: "action-groups" },
                    h("div", { class: "action-group" }, h("span", { class: "group-title" }, "Déplacement"),
                        button("Aller vers", "i-goto", "players.goto", { notSelf: true }, () => run("player.goto", "Téléportation vers le joueur.")),
                        button("Ramener", "i-bring", "players.bring", { notSelf: true, protect: true }, () => run("player.bring", "Joueur ramené.")),
                        button("Renvoyer", "i-undo", "players.bring", { notSelf: true, protect: true, extra: info.canReturn ? null : "Le joueur n'a pas été ramené" }, () => run("player.return", "Joueur renvoyé à sa position."))
                    ),
                    h("div", { class: "action-group" }, h("span", { class: "group-title" }, "Surveillance"),
                        button("Observer", "i-eye", "players.spectate", { notSelf: true }, () => run("player.spectate", null)),
                        button(info.frozen ? "Libérer" : "Figer", "i-snow", "players.freeze", { notSelf: true, protect: true }, () => run("player.freeze", info.frozen ? "Joueur libéré." : "Joueur figé."))
                    ),
                    h("div", { class: "action-group" }, h("span", { class: "group-title" }, "Soins"),
                        button("Soigner", "i-heart", "players.heal", {}, () => run("player.heal", "Joueur soigné.")),
                        button("Réanimer", "i-pulse", "players.heal", {}, () => run("player.revive", "Joueur réanimé.")),
                        button("Nourrir", "i-food", "players.heal", {}, () => run("player.feed", "Faim et soif remplies."))
                    ),
                    h("div", { class: "action-group" }, h("span", { class: "group-title" }, "Personnage"),
                        button("Apparence", "i-player", "players.appearance", { protect: true }, async () => {
                            const res = await playerAction("player.appearance", info.isSelf ? null : "Menu d'apparence ouvert chez le joueur.");
                            if (res && info.isSelf) closePanel(); // le menu s'ouvre sur votre écran
                        }),
                        info.isSelf
                            ? button("Mon apparence", "i-player", "players.copy_appearance", {}, () => run("player.restoreAppearance", "Votre apparence est rétablie."))
                            : button("Copier l'apparence", "i-copy", "players.copy_appearance", {}, () => run("player.copyAppearance", "Apparence copiée sur vous (non enregistrée).")),
                        button("Recréer", "i-undo", "players.recreate", { protect: true, danger: true }, () => openRecreate(info)),
                        button("Wipe", "i-trash", "players.wipe", { notSelf: true, protect: true, danger: true }, () => openWipe(info)),
                        button("Donner un véhicule", "i-car", "vehicles.give", {}, () => openGiveCar(info))
                    ),
                    h("div", { class: "action-group" }, h("span", { class: "group-title" }, "Sanction"),
                        button("Avertir", "i-warn", "sanctions.warn", { notSelf: true, protect: true }, () => openWarn(info)),
                        info.jail
                            ? button("Sortir de prison", "i-lock", "sanctions.jail", { notSelf: true }, () => run("sanction.unjail", "Joueur libéré de prison."))
                            : button("Prison", "i-lock", "sanctions.jail", { notSelf: true, protect: true }, () => openJail(info)),
                        button("Bannir", "i-ban", "sanctions.ban", { notSelf: true, protect: true, danger: true }, () => openBan({ serverId: info.serverId, name: info.name })),
                        button("Expulser", "i-door", "players.kick", { notSelf: true, protect: true }, () => openKick(info)),
                        button("Déconnecter", "i-x", "players.crash", { notSelf: true, protect: true, danger: true }, () => openCrash(info))
                    )
                )
            ),
            h("div", { class: "info-grid" },
                h("div", { class: "card" }, h("h3", { class: "card-title" }, "Identité"),
                    infoRow("Naissance", info.dateofbirth), infoRow("Sexe", sex), infoRow("Taille", info.height ? `${info.height} cm` : null)),
                h("div", { class: "card" }, h("h3", { class: "card-title" }, "Métier"),
                    infoRow("Emploi", info.job && info.job.label), infoRow("Grade", info.job && info.job.grade)),
                h("div", { class: "card" }, h("h3", { class: "card-title" }, "Argent"),
                    infoRow("Liquide", money(info.money)), infoRow("Banque", money(info.bank))),
                h("div", { class: "card" }, h("h3", { class: "card-title" }, "État"),
                    bar("Santé", health === null ? "—" : down ? "Au sol" : `${Math.round(healthPct)} %`, healthPct, down ? "var(--danger)" : "var(--ok)"),
                    bar("Armure", typeof info.armor === "number" ? `${info.armor} %` : "—", info.armor || 0, "var(--info)"),
                    infoRow("Ping", `${info.ping} ms`),
                    infoRow("Figé", info.frozen ? "Oui" : "Non"),
                    info.jail ? infoRow("Prison", `${Math.ceil(info.jail.remaining / 60)} min restantes`) : null)
            ),
            licensesCard(info),
            economySection(info),
            premiumCard(info, { serverId: info.serverId }, () => loadPlayerInfo()),
            can("sanctions.view") ? historyCard(info) : null
        )
    );

    const scroller = fiche.querySelector(".scroll");
    if (scroller) scroller.scrollTop = keepScroll;
}

async function playerAction(action, okMessage, payload) {
    const res = await act(action, { serverId: selectedPlayerId, ...(payload || {}) }, okMessage);
    if (res) loadPlayerInfo();
    return res;
}

// Permis du joueur : interrupteurs (lecture seule sans la permission players.licenses)
function licensesCard(info) {
    const licenses = Array.isArray(info.licenses) ? info.licenses : null;
    if (!licenses || info.protected) return null;
    const editable = can("players.licenses");
    return h("div", { class: "card", style: "margin-top:16px" },
        h("h3", { class: "card-title" }, `Permis (${licenses.filter((l) => l.owned).length}/${licenses.length})`),
        licenses.length
            ? h("div", { class: "perm-grid" }, licenses.map((license) => {
                const row = h("div", { class: `perm${license.owned ? " on" : ""}${editable ? "" : " locked"}` },
                    h("span", { class: "switch" }),
                    h("span", { class: "txt" }, h("span", null, license.label), h("code", null, license.type)));
                if (editable) {
                    row.addEventListener("click", () => playerAction("license.set", license.owned ? `${license.label} retiré.` : `${license.label} donné.`, { type: license.type, owned: !license.owned }));
                }
                return row;
            }))
            : h("span", { class: "muted" }, "Aucun permis défini dans la table licenses.")
    );
}

function openWipe(info) {
    const confirmInput = h("input", { class: "input", placeholder: info.name });
    const reason = h("textarea", { class: "input textarea", maxlength: "200", placeholder: "Raison (3 caractères minimum)" });
    const confirmBtn = h("button", { class: "btn danger", disabled: true }, icon("i-trash"), "Wipe définitif");
    const update = () => {
        confirmBtn.disabled = confirmInput.value.trim().toLowerCase() !== info.name.toLowerCase() || reason.value.trim().length < 3;
    };
    confirmInput.addEventListener("input", update);
    reason.addEventListener("input", update);

    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await playerAction("player.wipe", `${info.name} a été wipe : il recrée son personnage.`, { confirm: confirmInput.value.trim(), reason: reason.value.trim() });
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, `Wipe de ${info.name}`),
                h("p", null, "Tout est réinitialisé : argent (montant de départ), inventaire, métier, véhicules, permis, identité et apparence. Le joueur repasse par la création de personnage. Un état complet avant wipe est gardé dans les logs.")),
            h("div", { class: "body" },
                h("div", { class: "field" }, h("label", null, `Tapez « ${info.name} » pour confirmer`), confirmInput),
                h("div", { class: "field" }, h("label", null, "Raison"), reason)
            ),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    confirmInput.focus();
}

function openRecreate(info) {
    const textarea = h("textarea", { class: "input textarea", maxlength: "120", placeholder: "Raison (3 caractères minimum), ex. personnage raté, crash pendant la création" });
    const confirmBtn = h("button", { class: "btn danger", disabled: true }, icon("i-undo"), "Renvoyer à la création");
    textarea.addEventListener("input", () => { confirmBtn.disabled = textarea.value.trim().length < 3; });

    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await playerAction("player.recreate", `${info.name} repasse par la création de personnage.`, { reason: textarea.value.trim() });
            if (!res) return;
            close();
            if (info.isSelf) closePanel();
        });
        return [
            h("header", null, h("h3", null, `Renvoyer ${info.name} à la création ?`),
                h("p", null, "Son identité (prénom, nom, date de naissance) et son apparence sont effacées. Il repasse aussitôt par l'écran d'identité puis la création d'apparence. L'argent, l'inventaire et le métier sont conservés.")),
            h("div", { class: "body" }, textarea),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    textarea.focus();
}

function openKick(info) {
    const textarea = h("textarea", { class: "input textarea", maxlength: "120", placeholder: "Raison visible par le joueur (3 caractères minimum)" });
    const confirmBtn = h("button", { class: "btn danger", disabled: true }, icon("i-door"), "Expulser");
    textarea.addEventListener("input", () => { confirmBtn.disabled = textarea.value.trim().length < 3; });

    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await playerAction("player.kick", `${info.name} a été expulsé.`, { reason: textarea.value.trim() });
            if (res) {
                close();
                selectedPlayerId = null;
                playerInfo = null;
                renderPlayers();
            }
        });
        return [
            h("header", null, h("h3", null, `Expulser ${info.name} ?`), h("p", null, "Le joueur est déconnecté immédiatement et voit la raison.")),
            h("div", { class: "body" }, textarea),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    textarea.focus();
}

// Crash Player : déconnexion sans raison affichée
async function openCrash(info) {
    const yes = await confirmBox(`Déconnecter ${info.name} ?`, "Le joueur est déconnecté avec un message générique, sans raison ni mention du staff. L'action reste dans les logs.", "Déconnecter", true);
    if (!yes) return;
    const res = await playerAction("player.crash", `${info.name} a été déconnecté.`);
    if (res) {
        selectedPlayerId = null;
        playerInfo = null;
        renderPlayers();
    }
}

// Give un véhicule : ajouté au garage du joueur avec une plaque libre
function openGiveCar(info) {
    const input = h("input", { class: "input mono", maxlength: "30", placeholder: "Modèle, ex. sultan" });
    const confirmBtn = h("button", { class: "btn primary", disabled: true }, icon("i-car"), "Donner");
    input.addEventListener("input", () => { confirmBtn.disabled = !/^[\w]{2,30}$/.test(input.value.trim()); });

    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await playerAction("vehicle.give", null, { model: input.value.trim().toLowerCase() });
            if (!res) return;
            toast(`${res.model} donné à ${info.name} (plaque ${res.plate}).`, "ok");
            close();
        });
        return [
            h("header", null, h("h3", null, `Donner un véhicule à ${info.name}`), h("p", null, "Le véhicule est ajouté à son garage (table owned_vehicles) avec une plaque libre.")),
            h("div", { class: "body" }, h("div", { class: "field" }, h("label", null, "Modèle du véhicule"), input)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    input.focus();
}

// Rafraîchissement automatique de la page Joueurs (ping, joueurs, fiche)
setInterval(async () => {
    if (!state || !["players", "home", "dashboard", "world", "server"].includes(view) || document.body.classList.contains("hidden")) return;
    try {
        const next = await nui("refresh");
        if (next && typeof next === "object") {
            applyState(next, false);
            render();
        }
    } catch (e) {
        // panel fermé entre-temps
    }
    if (view === "players") loadPlayerInfo();
}, 5000);

// ---------- Rangs ----------

function renderRanks(onlySidebar) {
    const manage = can("ranks.manage");
    const sidebar = h("aside", { class: "sidebar" },
        h("div", { class: "side-head" }, h("h3", null, "Rangs"), h("span", { class: "muted mono" }, `${ranks().length}`)),
        h("div", { class: "side-scroll" }, ranks().map((rank) => {
            const active = draft ? draft.id === rank.id : selectedRankId === rank.id;
            return h("button", { class: `list-row${active ? " active" : ""}`, onclick: () => selectRank(rank.id) },
                dot(rank.color),
                h("span", { class: "name" }, rank.name),
                rank.owner ? icon("i-crown") : (!canEditRank(rank) && manage ? icon("i-lock") : null),
                h("span", { class: "lvl" }, rank.owner ? "MAX" : `${rank.level}`),
                h("span", { class: "cnt", title: "Membres" }, `${rank.members}`)
            );
        })),
        manage ? h("div", { class: "side-foot" },
            h("button", { class: "btn primary wide", onclick: newRank }, icon("i-plus"), "Nouveau rang")
        ) : null
    );

    const root = $("view-ranks");
    if (onlySidebar && root.querySelector(".sidebar")) {
        root.querySelector(".sidebar").replaceWith(sidebar);
        return;
    }
    root.replaceChildren(sidebar, renderEditor());
}

function selectRank(id) {
    if (draft && draft.id === id) return;
    const open = () => {
        selectedRankId = id;
        draft = null;
        loadDraft();
        renderRanks();
    };
    if (isDirty()) {
        confirmBox("Modifications non enregistrées", "Changer de rang annule les changements en cours.", "Changer sans enregistrer", true)
            .then((yes) => yes && open());
        return;
    }
    open();
}

function newRank() {
    const level = freeLevelBelow(myLevel());
    if (level === null) return toast("Aucun niveau libre sous le vôtre.", "error");
    const create = () => {
        const used = new Set(ranks().map((r) => r.color));
        draft = {
            id: null,
            name: "Nouveau rang",
            color: SWATCHES.find((c) => !used.has(c)) || SWATCHES[0],
            level,
            owner: false,
            permissions: new Set(["panel.open"].filter(can)),
        };
        selectedRankId = null;
        renderRanks();
        const input = document.querySelector("#rank-name");
        if (input) { input.focus(); input.select(); }
    };
    if (isDirty()) {
        confirmBox("Modifications non enregistrées", "Créer un rang annule les changements en cours.", "Continuer", true).then((yes) => yes && create());
        return;
    }
    create();
}

function renderEditor() {
    if (!draft) {
        return h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-layers"), "Sélectionnez un rang pour voir ses permissions."));
    }

    const rank = draft.id === null ? null : rankById(draft.id);
    const editable = rank ? canEditRank(rank) : can("ranks.manage");
    const structural = editable && !draft.owner; // niveau et permissions
    const members = staff().filter((m) => m.rankId === draft.id);

    // En-tête
    const titleDot = dot(draft.color);
    const titleText = h("span", null, draft.name || "Sans nom");
    const sub = h("div", { class: "page-sub" });
    const saveBtn = h("button", { class: "btn primary", onclick: saveDraft }, icon("i-save"), draft.id === null ? "Créer le rang" : "Enregistrer");
    const resetBtn = h("button", { class: "btn ghost", onclick: resetDraft, title: "Annuler les modifications" }, icon("i-undo"), "Annuler");

    function refreshChrome() {
        titleDot.style.background = draft.color;
        titleText.textContent = draft.name || "Sans nom";
        const parts = draft.owner
            ? ["Fondateur", "Toutes les permissions"]
            : [`Niveau ${draft.level}`, `${draft.permissions.size} permission${draft.permissions.size > 1 ? "s" : ""}`];
        if (rank) parts.push(`${rank.members} membre${rank.members > 1 ? "s" : ""}`);
        sub.replaceChildren(...parts.flatMap((p, i) => (i ? [h("span", { class: "sep" }), p] : [p])));
        const dirty = isDirty();
        saveBtn.disabled = !dirty;
        resetBtn.style.display = dirty && draft.id !== null ? "" : "none";
        renderRanks(true);
    }

    const actions = h("div", { class: "actions" });
    if (editable) {
        actions.append(resetBtn);
        if (rank && !rank.owner) {
            actions.append(
                h("button", { class: "btn", onclick: () => duplicateRank(rank) }, icon("i-copy"), "Dupliquer"),
                h("button", { class: "btn danger", onclick: () => deleteRank(rank) }, icon("i-trash"), "Supprimer")
            );
        }
        actions.append(saveBtn);
    }

    // Formulaire
    const nameInput = h("input", { id: "rank-name", class: "input", maxlength: "32", value: draft.name, disabled: !editable });
    nameInput.addEventListener("input", () => { draft.name = nameInput.value; refreshChrome(); });

    const swatches = h("div", { class: "swatches" });
    const picker = h("input", { type: "color", value: draft.color, disabled: !editable });
    function paintSwatches() {
        swatches.replaceChildren(
            ...SWATCHES.map((color) => {
                const b = h("button", { class: `swatch${draft.color === color ? " on" : ""}`, disabled: !editable, title: color });
                b.style.background = color;
                b.addEventListener("click", () => { draft.color = color; picker.value = color; paintSwatches(); refreshChrome(); });
                return b;
            }),
            h("label", { class: "color-pick", title: "Couleur personnalisée" }, picker, icon("i-plus"))
        );
    }
    picker.addEventListener("input", () => { draft.color = picker.value.toLowerCase(); paintSwatches(); refreshChrome(); });
    paintSwatches();

    const maxLevel = myLevel() - 1;
    const levelInput = h("input", { class: "input mono", type: draft.owner ? "text" : "number", min: "1", max: String(maxLevel), value: draft.owner ? "MAX" : String(draft.level), disabled: !structural });
    levelInput.addEventListener("input", () => { draft.level = levelInput.value === "" ? "" : Number(levelInput.value); refreshChrome(); });

    const form = h("div", { class: "card" },
        h("div", { class: "fields" },
            h("div", { class: "field" }, h("label", { for: "rank-name" }, "Nom"), nameInput),
            h("div", { class: "field" }, h("label", null, "Couleur"), swatches),
            h("div", { class: "field" }, h("label", null, "Niveau"), levelInput,
                h("span", { class: "hint" }, draft.owner ? "Niveau maximal" : `De 1 à ${maxLevel}, plus haut = prioritaire`))
        )
    );

    // Permissions par famille
    const permSections = state.catalogue.families.map((family) => {
        const perms = state.catalogue.permissions.filter((p) => p.family === family.id);
        if (!perms.length) return null;
        const count = h("span", { class: "count" });
        const updateCount = () => { count.textContent = `${perms.filter((p) => draft.owner || draft.permissions.has(p.id)).length}/${perms.length}`; };
        updateCount();
        return h("div", { class: "section" },
            h("div", { class: "section-head" }, family.label, count),
            h("div", { class: "perm-grid" }, perms.map((perm) => {
                const on = draft.owner || draft.permissions.has(perm.id);
                const locked = !structural || !can(perm.id);
                const row = h("div", {
                    class: `perm${on ? " on" : ""}${locked ? " locked" : ""}`,
                    title: locked && structural ? "Vous ne pouvez pas donner une permission que vous n'avez pas." : null,
                },
                h("span", { class: "switch" }),
                h("span", { class: "txt" }, h("span", null, perm.label), h("code", null, perm.id))
                );
                if (!locked) {
                    row.addEventListener("click", () => {
                        if (draft.permissions.has(perm.id)) draft.permissions.delete(perm.id);
                        else draft.permissions.add(perm.id);
                        row.classList.toggle("on", draft.permissions.has(perm.id));
                        updateCount();
                        refreshChrome();
                    });
                }
                return row;
            }))
        );
    });

    const banner = !editable
        ? h("div", { class: "banner" }, icon("i-lock"), draft.owner
            ? "Seul un Fondateur peut modifier ce rang."
            : can("ranks.manage") ? "Ce rang est égal ou supérieur au vôtre : lecture seule." : "Lecture seule : vous n'avez pas la permission de gérer les rangs.")
        : draft.owner ? h("div", { class: "banner info" }, icon("i-crown"), "Le Fondateur a toutes les permissions. Seuls son nom et sa couleur sont modifiables.")
            : null;

    const membersCard = rank && state.staff ? h("div", { class: "card" },
        h("h3", { class: "card-title" }, `Membres (${members.length})`),
        members.length
            ? h("div", { class: "chips" }, members.map((m) => h("span", { class: "chip" }, h("span", { class: `status${m.online ? " on" : ""}` }), m.name)))
            : h("span", { class: "muted" }, "Aucun membre n'a ce rang.")
    ) : null;

    const content = h("div", { class: "content" },
        h("div", { class: "page-head" },
            h("div", { class: "grow" }, h("h1", { class: "page-title" }, titleDot, titleText), sub),
            actions
        ),
        h("div", { class: "scroll" }, banner, form, h("div", { class: "card" }, h("h3", { class: "card-title" }, "Permissions"), permSections), membersCard)
    );

    queueMicrotask(refreshChrome);
    return content;
}

function resetDraft() {
    draft = null;
    loadDraft();
    renderRanks();
}

async function saveDraft() {
    const payload = {
        name: (draft.name || "").trim(),
        color: draft.color,
        level: Number(draft.level),
        permissions: [...draft.permissions],
    };
    if (draft.id !== null) payload.id = draft.id;

    const creating = draft.id === null;
    const res = await act("rank.save", payload, creating ? "Rang créé." : "Rang enregistré.");
    if (!res) return;
    selectedRankId = res.id;
    draft = null;
    loadDraft();
    render();
}

async function duplicateRank(rank) {
    if (isDirty()) {
        const yes = await confirmBox("Modifications non enregistrées", "Dupliquer annule les changements en cours.", "Continuer", true);
        if (!yes) return;
    }
    const res = await act("rank.duplicate", { id: rank.id }, `« ${rank.name} » dupliqué.`);
    if (!res) return;
    selectedRankId = res.id;
    draft = null;
    loadDraft();
    render();
}

async function deleteRank(rank) {
    const yes = await confirmBox(`Supprimer « ${rank.name} » ?`, "Cette action est définitive. Le rang doit être vide pour être supprimé.", "Supprimer", true);
    if (!yes) return;
    const res = await act("rank.delete", { id: rank.id }, "Rang supprimé.");
    if (!res) return;
    selectedRankId = null;
    draft = null;
    render();
}

// ---------- Membres ----------

function renderMembers() {
    const online = staff().filter((m) => m.online).length;
    const search = h("input", { placeholder: "Rechercher un membre", value: memberFilter.text });
    search.addEventListener("input", () => {
        memberFilter.text = search.value;
        $("members-table").replaceChildren(...memberRows());
    });

    const segmented = h("div", { class: "segmented", role: "radiogroup" },
        h("button", { "aria-checked": String(!memberFilter.onlineOnly), onclick: () => { memberFilter.onlineOnly = false; renderMembers(); } }, "Tous"),
        h("button", { "aria-checked": String(memberFilter.onlineOnly), onclick: () => { memberFilter.onlineOnly = true; renderMembers(); } }, "En ligne")
    );

    function memberRows() {
        const rows = staff()
            .filter((m) => !memberFilter.onlineOnly || m.online)
            .filter((m) => !memberFilter.text || m.name.toLowerCase().includes(memberFilter.text.toLowerCase()))
            .sort((a, b) => ((rankById(b.rankId) || {}).level || 0) - ((rankById(a.rankId) || {}).level || 0) || a.name.localeCompare(b.name))
            .map(memberRow);
        return rows.length ? rows : [h("div", { class: "empty" }, icon("i-users"), "Aucun membre ne correspond.")];
    }

    $("view-members").replaceChildren(h("div", { class: "content" },
        h("div", { class: "page-head" },
            h("div", { class: "grow" },
                h("h1", { class: "page-title" }, "Membres du staff"),
                h("div", { class: "page-sub" }, `${online} en ligne`, h("span", { class: "sep" }), `${staff().length} membre${staff().length > 1 ? "s" : ""}`)
            ),
            can("staff.manage") ? h("button", { class: "btn primary", onclick: openAddMember }, icon("i-user-plus"), "Ajouter un membre") : null
        ),
        h("div", { class: "toolbar" }, h("label", { class: "search" }, icon("i-search"), search), segmented),
        h("div", { class: "scroll" }, h("div", { class: "table", id: "members-table" }, memberRows()))
    ));
}

function memberRow(member) {
    const rank = rankById(member.rankId);
    const isMe = member.license === state.me.license;
    let control;

    if (canManageMember(member)) {
        const select = h("select", { class: "input" },
            ranks().filter(canAssign).map((r) => h("option", { value: String(r.id), selected: r.id === member.rankId }, r.name))
        );
        select.addEventListener("change", async () => {
            const res = await act("staff.setRank", { license: member.license, rankId: Number(select.value) }, `${member.name} est maintenant ${rankById(Number(select.value))?.name || "promu"}.`);
            if (!res) select.value = String(member.rankId);
            else renderMembers();
        });
        control = select;
    } else {
        control = isMe ? h("span", { class: "you" }, "Vous") : h("span", { class: "muted" }, "—");
    }

    return h("div", { class: "row" },
        h("span", { class: `status${member.online ? " on" : ""}`, title: member.online ? "En ligne" : "Hors ligne" }),
        h("div", { class: "who" },
            h("b", null, member.name),
            h("span", null, member.online ? `ID ${member.serverId} · ${shortLicense(member.license)}` : shortLicense(member.license))
        ),
        rankPill(rank),
        control,
        canManageMember(member)
            ? h("button", { class: "btn small ghost", title: "Retirer du staff", onclick: () => removeMember(member) }, icon("i-trash"))
            : h("span")
    );
}

async function removeMember(member) {
    const yes = await confirmBox(`Retirer ${member.name} du staff ?`, "Il perdra immédiatement l'accès au panel et à ses permissions.", "Retirer", true);
    if (!yes) return;
    const res = await act("staff.remove", { license: member.license }, `${member.name} a été retiré du staff.`);
    if (res) renderMembers();
}

function openAddMember() {
    const assignable = ranks().filter(canAssign);
    if (!assignable.length) return toast("Aucun rang inférieur au vôtre à attribuer.", "error");

    let chosen = null;
    let filter = "";
    const list = h("div", { class: "pick-list" });
    const confirmBtn = h("button", { class: "btn primary", disabled: true }, icon("i-user-plus"), "Ajouter");
    const select = h("select", { class: "input" }, assignable.map((r, i) => h("option", { value: String(r.id), selected: i === assignable.length - 1 }, r.name)));
    const search = h("input", { placeholder: "Nom ou ID" });

    function paint() {
        const candidates = (state.candidates || []).filter((c) => !filter || c.name.toLowerCase().includes(filter) || String(c.serverId) === filter);
        list.replaceChildren(...(candidates.length
            ? candidates.map((c) => {
                const b = h("button", { class: `pick${chosen === c.serverId ? " on" : ""}` }, h("span", { class: "id" }, `#${c.serverId}`), c.name);
                b.addEventListener("click", () => { chosen = c.serverId; confirmBtn.disabled = false; paint(); });
                return b;
            })
            : [h("div", { class: "muted" }, "Aucun joueur connecté hors staff.")]));
    }
    search.addEventListener("input", () => { filter = search.value.trim().toLowerCase(); paint(); });
    paint();

    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await act("staff.add", { serverId: chosen, rankId: Number(select.value) }, "Membre ajouté au staff.");
            if (res) { close(); renderMembers(); }
        });
        return [
            h("header", null, h("h3", null, "Ajouter un membre"), h("p", null, "Choisissez un joueur connecté et son rang.")),
            h("div", { class: "body" },
                h("label", { class: "search" }, icon("i-search"), search),
                list,
                h("div", { class: "field" }, h("label", null, "Rang"), select)
            ),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    search.focus();
}

// ---------- Fenêtres de dialogue et notifications ----------

let modalResolve = null;

function openModal(build) {
    const close = (value) => closeModal(value);
    $("modal").replaceChildren(...build(close));
    $("backdrop").classList.add("on");
}

function closeModal(value) {
    $("backdrop").classList.remove("on");
    $("modal").replaceChildren();
    if (modalResolve) {
        const resolve = modalResolve;
        modalResolve = null;
        resolve(value === true);
    }
}

function confirmBox(title, text, label, danger) {
    return new Promise((resolve) => {
        openModal((close) => [
            h("header", null, h("h3", null, title), h("p", null, text)),
            h("footer", null,
                h("button", { class: "btn ghost", onclick: () => close(false) }, "Annuler"),
                h("button", { class: `btn ${danger ? "danger" : "primary"}`, onclick: () => close(true) }, label)
            ),
        ]);
        modalResolve = resolve;
    });
}

$("backdrop").addEventListener("mousedown", (e) => {
    if (e.target === $("backdrop")) closeModal(false);
});

function toast(message, kind) {
    const el = h("div", { class: `toast ${kind || ""}` }, message);
    $("toasts").append(el);
    setTimeout(() => {
        el.classList.add("out");
        setTimeout(() => el.remove(), 300);
    }, 3200);
}

// ---------- Événements ----------

$("close").addEventListener("click", closePanel);

// Touche d'ouverture (F10 par défaut) : la même touche referme le panel
let toggleKey = "F10";

function isToggleKey(e) {
    if (e.key.toUpperCase() !== toggleKey.toUpperCase()) return false;
    // Une touche lettre ne ferme pas le panel pendant la saisie dans un champ
    const typing = ["INPUT", "SELECT", "TEXTAREA"].includes(document.activeElement && document.activeElement.tagName);
    return e.key.length > 1 || !typing;
}

window.addEventListener("keydown", (e) => {
    if (document.body.classList.contains("hidden")) return;
    if (e.key === "Escape") {
        if ($("backdrop").classList.contains("on")) closeModal(false);
        else closePanel();
    } else if (isToggleKey(e)) {
        e.preventDefault();
        closePanel();
    }
});

// Le panel devient transparent quand la souris en sort, pour voir le jeu derrière
const panelWindow = document.querySelector(".window");
panelWindow.addEventListener("mouseleave", () => document.body.classList.add("see-through"));
panelWindow.addEventListener("mouseenter", () => document.body.classList.remove("see-through"));

window.addEventListener("message", (event) => {
    const msg = event.data;
    if (!msg || typeof msg !== "object") return;

    if (msg.action === "open") {
        draft = null;
        if (typeof msg.toggleKey === "string" && msg.toggleKey) toggleKey = msg.toggleKey;
        applyState(msg.state, true);
        document.body.classList.remove("hidden", "see-through");
        render();
    } else if (msg.action === "state") {
        const keptDraft = applyState(msg.state, false);
        if (keptDraft && view === "ranks") renderRanks(true);
        else render();
    } else if (msg.action === "focusPlayer") {
        // Menu contextuel : fiche du joueur visé
        if (!can("players.view")) return;
        go("players");
        if (playersTab !== "online") switchPlayersTab("online");
        selectPlayer(Number(msg.serverId));
    } else if (msg.action === "warning") {
        showWarning(msg.warning);
    } else if (msg.action === "close") {
        closeModal();
        document.body.classList.add("hidden");
    }
});

// ---------- Aperçu hors jeu (navigateur) ----------

function demoState() {
    return {
        me: { serverId: 1, license: "license:aaa111", name: "Kévin", rank: { id: 1, name: "Fondateur", color: "#9650ff", level: 100, owner: true }, permissions: ["companies.manage", "publics.manage", "players.crash", "vehicles.give", "dev.manage", "events.manage", "poles.manage", "server.manage", "premium.manage", "shop.manage", "players.offline", "tools.ghost", "staff.online", "players.licenses", "players.copy_appearance", "players.wipe", "world.weather", "world.time", "sanctions.jail", "players.appearance", "players.recreate", "logs.view", "logs.chat", "economy.money", "economy.black_money", "economy.job", "economy.items", "economy.clear", "tools.noclip", "tools.invisible", "tools.godmode", "tools.names", "tools.coords", "tools.tpm", "tools.vehicles", "sanctions.view", "sanctions.warn", "sanctions.ban", "sanctions.ban_permanent", "sanctions.revoke", "players.view", "players.goto", "players.bring", "players.spectate", "players.freeze", "players.heal", "players.kick", "panel.open", "ranks.view", "ranks.manage", "staff.view", "staff.manage"] },
        ownerLevel: 100,
        catalogue: {
            families: [{ id: "players", label: "Joueurs" }, { id: "sanctions", label: "Sanctions" }, { id: "tools", label: "Outils" }, { id: "manage", label: "Gestion" }],
            permissions: [
                { id: "panel.open", family: "manage", label: "Ouvrir le panel staff" },
                { id: "ranks.view", family: "manage", label: "Voir les rangs et leurs permissions" },
                { id: "ranks.manage", family: "manage", label: "Créer, modifier et supprimer les rangs inférieurs" },
                { id: "staff.view", family: "manage", label: "Voir les membres du staff" },
                { id: "staff.manage", family: "manage", label: "Ajouter, promouvoir et retirer des membres inférieurs" },
            ],
        },
        ranks: [
            { id: 1, name: "Fondateur", color: "#9650ff", level: 100, owner: true, members: 1, permissions: ["panel.open", "ranks.view", "ranks.manage", "staff.view", "staff.manage"] },
            { id: 2, name: "Admin", color: "#ff6b6b", level: 80, owner: false, members: 1, permissions: ["panel.open", "ranks.view", "ranks.manage", "staff.view", "staff.manage"] },
            { id: 3, name: "Responsable staff", color: "#f2c26b", level: 60, owner: false, members: 0, permissions: ["panel.open", "ranks.view", "staff.view", "staff.manage"] },
            { id: 4, name: "Modérateur", color: "#5fd3a0", level: 40, owner: false, members: 2, permissions: ["panel.open", "ranks.view", "staff.view"] },
            { id: 5, name: "Modérateur test", color: "#6bb8f2", level: 20, owner: false, members: 0, permissions: ["panel.open"] },
        ],
        staff: [
            { license: "license:aaa111", name: "Kévin", rankId: 1, online: true, serverId: 1 },
            { license: "license:bbb222", name: "Alex", rankId: 2, online: true, serverId: 4 },
            { license: "license:ccc333", name: "Sam", rankId: 4, online: false },
            { license: "license:ddd444", name: "Léa", rankId: 4, online: true, serverId: 9 },
        ],
        candidates: [{ serverId: 2, name: "Joueur Test" }, { serverId: 7, name: "Marco" }],
        players: [
            { serverId: 1, name: "Ramiro Lotus", job: "Sans emploi", ping: 38, rank: { name: "Fondateur", color: "#9650ff" } },
            { serverId: 2, name: "Jean Dupont", job: "Mécanicien", ping: 54 },
            { serverId: 4, name: "Alex Moreau", job: "Police", ping: 61, rank: { name: "Admin", color: "#ff6b6b" } },
            { serverId: 7, name: "Marco Rossi", job: "Taxi", ping: 112, frozen: true },
        ],
        tools: { noclip: true, names: true },
        world: {
            available: true, weather: "CLOUDS", hour: 18, minute: 42, frozen: false, cycle: true, blackout: false, cycleMinutes: 30,
            weathers: [["EXTRASUNNY", "Grand soleil"], ["CLEAR", "Dégagé"], ["CLOUDS", "Nuageux"], ["OVERCAST", "Couvert"], ["CLEARING", "Éclaircies"], ["RAIN", "Pluie"], ["THUNDER", "Orage"], ["FOGGY", "Brouillard"], ["SMOG", "Smog"], ["SNOWLIGHT", "Neige légère"], ["SNOW", "Neige"], ["BLIZZARD", "Blizzard"], ["XMAS", "Noël"], ["HALLOWEEN", "Halloween"]].map(([id, label]) => ({ id, label })),
        },
        dev: { modes: { debug: true }, canRefresh: false, resourceName: "lunatic_admin" },
        server: { maintenance: false, maintenanceMessage: "Le serveur est en maintenance. Revenez un peu plus tard !", players: 23, restart: null },
        dashboard: {
            players: 23, maxPlayers: 64,
            history: Array.from({ length: 60 }, (_, i) => ({ t: Math.floor(Date.now() / 1000) - (59 - i) * 1440, n: Math.max(0, Math.round(18 + 12 * Math.sin(i / 7) + (i % 5)))})),
            staff: [{ serverId: 1, name: "Ramiro Lotus", rank: { name: "Fondateur", color: "#9650ff" } }, { serverId: 4, name: "Alex Moreau", rank: { name: "Admin", color: "#ff6b6b" } }],
            sanctions: { activeBans: 3, bans24h: 1, warns24h: 4 },
            recent: [
                { id: 120, actor: "Ramiro Lotus", action: "economy.money", target: "Jean Dupont", details: { account: "money", operation: "add", amount: 500, before: 2350, after: 2850, reason: "Remboursement bug garage" }, created: Math.floor(Date.now() / 1000) - 300 },
                { id: 119, actor: "Alex Moreau", action: "sanction.ban", target: "Tony Vega", details: { id: 42, hours: 72, reason: "Freekill répété" }, created: Math.floor(Date.now() / 1000) - 3600 },
                { id: 118, actor: "Ramiro Lotus", action: "tool.noclip.on", details: null, created: Math.floor(Date.now() / 1000) - 5400 },
                { id: 117, actor: "Alex Moreau", action: "player.bring", target: "Marco Rossi", details: { serverId: 7 }, created: Math.floor(Date.now() / 1000) - 7200 },
            ],
        },
        recent: [
            { license: "license:9f1e22aa00bb11", name: "Tony Vega", serverId: 9, droppedAt: Math.floor(Date.now() / 1000) - 240, banned: false },
            { license: "license:77aa00cc11dd22", name: "Sarah Klein", serverId: 5, droppedAt: Math.floor(Date.now() / 1000) - 3600, banned: true },
        ],
    };
}

async function demoNui(name, data) {
    if (name === "action" && data && data.action === "economy.jobs") return { ok: true, jobs: [{ name: "unemployed", label: "Sans emploi", grades: [{ grade: 0, label: "Chômeur" }] }, { name: "mechanic", label: "Mécanicien", grades: [{ grade: 0, label: "Recrue" }, { grade: 1, label: "Employé" }, { grade: 2, label: "Patron" }] }] };
    if (name === "action" && data && data.action === "economy.inventory") return { ok: true, weight: 4300, maxWeight: 24000, items: [{ name: "bread", label: "Pain", count: 3 }, { name: "water", label: "Eau", count: 2 }, { name: "phone", label: "Téléphone", count: 1 }] };
    if (name === "action" && data && data.action === "logs.list") return { ok: true, more: true, staff: [{ license: "license:a", name: "Alex Moreau" }, { license: "license:b", name: "Ramiro Lotus" }], logs: demoState().dashboard.recent };
    if (name === "action" && data && data.action === "logs.chat") return { ok: true, messages: [
        { id: 9, name: "[12] Jean Dupont", channel: "hrp", message: "Quelqu'un sait où est le garage ?", created: Math.floor(Date.now() / 1000) - 120 },
        { id: 8, name: "[4] Léa Martin", channel: "me", message: "sort son téléphone", created: Math.floor(Date.now() / 1000) - 400 },
        { id: 7, name: "[1] Ramiro Lotus", channel: "staff", message: "Je m'occupe du ticket de Marco", created: Math.floor(Date.now() / 1000) - 900 },
    ] };
    if (name === "action" && data && data.action === "offline.search") return { ok: true, players: [
        { identifier: "9f1e22aa00bb11", name: "Tony Vega", lastSeen: Math.floor(Date.now() / 1000) - 7200 },
        { identifier: "77aa00cc11dd22", name: "Sarah Klein", lastSeen: Math.floor(Date.now() / 1000) - 4 * 86400 },
    ] };
    if (name === "action" && data && data.action === "offline.info") return { ok: true, info: {
        identifier: "9f1e22aa00bb11", license: "license:9f1e22aa00bb11", name: "Tony Vega", hasIdentity: true, dateofbirth: "02/08/1993", sex: "m", height: 178,
        money: 820, bank: 15400, blackMoney: 0, job: { name: "mechanic", label: "Mécanicien", grade: "Recrue", level: 0 },
        lastSeen: Math.floor(Date.now() / 1000) - 7200, createdAt: Math.floor(Date.now() / 1000) - 20 * 86400,
        licenses: [{ type: "dmv", label: "Code de la route", owned: true }, { type: "drive", label: "Permis voiture", owned: false }, { type: "weapon", label: "Port d'arme", owned: false }],
    } };
    if (name === "action" && data && data.action === "structures.list") {
        const company = data.payload.kind === "company";
        return { ok: true, orphans: [{ name: "taxi", label: "Taxi" }], types: company
            ? [{ id: "nightclub", label: "Boîte de nuit" }, { id: "dealer", label: "Concessionnaire" }, { id: "business", label: "Entreprise" }, { id: "mechanic", label: "Mécanique" }, { id: "media", label: "Médias" }, { id: "restaurant", label: "Restaurant" }]
            : [{ id: "police", label: "Police" }, { id: "medic", label: "Médecins" }, { id: "administration", label: "Administration" }, { id: "government", label: "Gouvernement" }],
            structures: company
                ? [{ job: "burgershot", label: "Burger Shot", type: "restaurant", typeLabel: "Restaurant", color: "#f2a341", grades: 4, online: 2, total: 7 },
                   { job: "bennys", label: "Benny's", type: "mechanic", typeLabel: "Mécanique", color: "#6bb8f2", grades: 3, online: 1, total: 4 }]
                : [{ job: "lspd", label: "LSPD", type: "police", typeLabel: "Police", grades: 5, online: 3, total: 12 },
                   { job: "ems", label: "EMS", type: "medic", typeLabel: "Médecins", grades: 4, online: 1, total: 6 }] };
    }
    if (name === "action" && data && data.action === "structures.info") {
        const publicKind = data.payload.job === "lspd" || data.payload.job === "ems";
        return { ok: true, job: {
            name: data.payload.job, label: publicKind ? "LSPD" : "Burger Shot", typeLabel: publicKind ? "Police" : "Restaurant", leadName: publicKind ? "Jean Dupont" : null,
            whitelisted: true,
            structure: { job: data.payload.job, kind: publicKind ? "public" : "company", type: publicKind ? "police" : "restaurant", lead: publicKind ? "aa11223344" : null, color: "#f2a341",
                logo: "", radialIcon: "fa-solid fa-burger", banner: "", createdBy: "Ramiro Lotus", createdAt: Math.floor(Date.now() / 1000) - 86400 },
            points: [
                { id: 1, job: data.payload.job, type: "management", typeLabel: "Gestion", label: "Bureau du patron", x: -1193.42, y: -897.31, z: 13.0 },
                { id: 2, job: data.payload.job, type: "storage", typeLabel: "Stockage", label: "Coffre cuisine", x: -1201.1, y: -901.9, z: 13.0 },
                { id: 3, job: data.payload.job, type: "catalog", typeLabel: "Catalogue", label: "Catalogue", x: -1195.8, y: -893.2, z: 13.0 },
            ],
            pointTypes: [{ id: "management", label: "Gestion", ready: true }, { id: "storage", label: "Stockage", ready: true }, { id: "locker", label: "Casier", ready: true }, { id: "wardrobe", label: "Vestiaire", ready: true }, { id: "doorbell", label: "Sonnette", ready: true }, { id: "custom", label: "Custom", ready: true }, { id: "catalog", label: "Catalogue" }, { id: "craft", label: "Craft" }],
            account: { balance: 48250, history: [
                { amount: 12000, balance: 48250, reason: "Dépôt", actor: "Jean Dupont", created: Math.floor(Date.now() / 1000) - 3600 },
                { amount: -2500, balance: 36250, reason: "Retrait", actor: "Jean Dupont", created: Math.floor(Date.now() / 1000) - 7200 },
                { amount: 38750, balance: 38750, reason: "Capital de départ", actor: "Staff : Ramiro Lotus", created: Math.floor(Date.now() / 1000) - 86400 },
            ] },
            grades: [{ grade: 0, label: "Recrue", salary: 200, members: 3 }, { grade: 1, label: "Employé", salary: 300, members: 2 }, { grade: 2, label: "Gérant", salary: 400, members: 1 }, { grade: 3, label: "Patron", salary: 500, members: 1 }],
            members: [
                { identifier: "aa11223344", name: "Jean Dupont", grade: 3, online: 2, playtime: 754 },
                { identifier: "bb22334455", name: "Alex Moreau", grade: 2, online: 4, playtime: 312, protected: true },
                { identifier: "cc33445566", name: "Lina Petit", grade: 1, playtime: 95 },
                { identifier: "dd44556677", name: "Hugo Martin", grade: 0, playtime: 12 },
            ] } };
    }
    if (name === "action" && data && data.action === "dev.resources") return { ok: true, canRefresh: false, resources: [
        { name: "es_extended", state: "started", version: "1.16.2", author: "ESX-Framework", protected: true },
        { name: "illenium-appearance", state: "started", version: "5.7.0", author: "snakewiz & iLLeniumStudios" },
        { name: "lunatic_admin", state: "started", version: "0.6.0", author: "Lunatic RP", description: "Panel staff", protected: true },
        { name: "lunatic_chat", state: "started", version: "0.2.0", author: "Lunatic RP", description: "Tchat Lunatic" },
        { name: "lunatic_world", state: "started", version: "0.1.0", author: "Lunatic RP" },
        { name: "nc_pommes", state: "stopped", version: "1.0.0", author: "NightCraft" },
        { name: "ox_inventory", state: "started", version: "2.48.0", author: "Overextended", protected: true },
    ] };
    if (name === "action" && data && data.action === "events.list") {
        const t = Math.floor(Date.now() / 1000);
        return { ok: true, reminder: 15, events: [
            { id: 4, title: "Course de rue nocturne", description: "Départ devant le garage central, véhicules de série uniquement. Récompense pour les 3 premiers.", place: "Garage central", coords: { x: 215.7, y: -810.1, z: 30.7 }, startsAt: t + 7200, status: "scheduled", createdBy: "Ramiro Lotus" },
            { id: 5, title: "Soirée au Bahama Mamas", description: "", place: "Bahama Mamas", startsAt: t + 3 * 86400, status: "scheduled", createdBy: "Alex Moreau" },
            { id: 3, title: "Chasse au trésor", description: "Indices dans toute la ville.", place: "Plage de Vespucci", coords: { x: -1600, y: -1000, z: 13 }, startsAt: t - 900, status: "started", createdBy: "Ramiro Lotus" },
            { id: 2, title: "Concert au Vinewood Bowl", description: "", place: "Vinewood Bowl", startsAt: t - 2 * 86400, status: "done", createdBy: "Alex Moreau" },
            { id: 1, title: "Rallye du désert", description: "", place: "Sandy Shores", startsAt: t - 5 * 86400, status: "cancelled", createdBy: "Ramiro Lotus" },
        ] };
    }
    if (name === "action" && data && data.action === "poles.list") return { ok: true, jobs: [
        { name: "unemployed", label: "Chômeur", grades: 1, online: 14, total: 212, whitelisted: false, protected: true },
        { name: "mechanic", label: "Mécanicien", grades: 3, online: 2, total: 6, whitelisted: true },
        { name: "realestate", label: "Agent immobilier", grades: 4, online: 0, total: 3, whitelisted: true },
        { name: "taxi", label: "Taxi", grades: 2, online: 1, total: 4, whitelisted: false },
    ] };
    if (name === "action" && data && data.action === "poles.info") return { ok: true, job: data.payload.job === "unemployed"
        ? { name: "unemployed", label: "Chômeur", whitelisted: false, protected: true, membersHidden: true, members: [], grades: [{ grade: 0, name: "unemployed", label: "Chômeur", salary: 200, members: 0 }] }
        : { name: "mechanic", label: "Mécanicien", whitelisted: true, grades: [
            { grade: 0, name: "recrue", label: "Recrue", salary: 250, members: 3 },
            { grade: 1, name: "employe", label: "Employé", salary: 400, members: 2 },
            { grade: 2, name: "boss", label: "Patron", salary: 700, members: 1 },
        ], members: [
            { identifier: "aa11", name: "Jean Dupont", grade: 2, online: 2 },
            { identifier: "bb22", name: "Alex Moreau", grade: 1, online: 4, protected: true },
            { identifier: "cc33", name: "Lina Petit", grade: 1 },
            { identifier: "dd44", name: "Hugo Martin", grade: 0 },
            { identifier: "ee55", name: "Sam Leroy", grade: 0 },
            { identifier: "ff66", name: "Nora Diaz", grade: 0 },
        ] } };
    if (name === "action" && data && data.action === "credits.history") return { ok: true, history: [
        { amount: 1000, after: 1250, reason: "Achat pack Tebex #4412", staff: "Ramiro Lotus", created: Math.floor(Date.now() / 1000) - 3600 },
        { amount: 250, after: 250, reason: "Gagnant de l'event course", staff: "Alex Moreau", created: Math.floor(Date.now() / 1000) - 5 * 86400 },
    ] };
    if (name === "getCoords") return { x: 215.76, y: -810.12, z: 30.73, h: 157.5 };
    if (name === "vehicleSpawn") return { ok: false, error: "Aperçu navigateur : rien n'est créé." };
    if (name === "action" && data && data.action === "player.info") {
        const p = (demoState().players || []).find((x) => x.serverId === data.payload.serverId) || {};
        return { ok: true, info: {
            serverId: p.serverId, name: p.name, pseudo: "Pseudo_FiveM", license: "license:25c2692702c6aa11bb", ping: p.ping,
            rank: p.rank, frozen: !!p.frozen, canReturn: false, isSelf: p.serverId === 1, protected: p.serverId === 4 ? false : false,
            health: 164, maxHealth: 200, armor: 40, job: { name: "mechanic", label: p.job, grade: "Employé", level: 1 }, money: 2350, bank: 48200, blackMoney: 0,
            dateofbirth: "14/03/1996", sex: "m", height: 182, jail: p.serverId === 7 ? { remaining: 540, reason: "Freekill" } : undefined,
            premium: p.serverId === 2 ? { tier: "premium_plus", label: "Premium+", color: "#9650ff", expires: Math.floor(Date.now() / 1000) + 25 * 86400 } : undefined,
            credits: 1250,
            licenses: [{ type: "dmv", label: "Code de la route", owned: true }, { type: "drive", label: "Permis voiture", owned: true }, { type: "drive_bike", label: "Permis moto", owned: false }, { type: "drive_truck", label: "Permis poids lourd", owned: false }, { type: "boat", label: "Permis bateau", owned: false }, { type: "weapon", label: "Port d'arme", owned: false }],
        } };
    }
    if (name === "action" && data && (data.action === "sanctions.list" || data.action === "sanctions.history")) {
        const t = Math.floor(Date.now() / 1000);
        return { ok: true, sanctions: [
            { id: 42, type: "ban", name: "Tony Vega", license: "license:9f1e22aa00bb11", reason: "Freekill répété sur la place des cubes", staff: "Ramiro Lotus", created: t - 7200, expires: t + 3 * 86400, active: true, canRevoke: true },
            { id: 41, type: "warn", name: "Jean Dupont", license: "license:25c2692702c6aa", reason: "Langage HRP en pleine scène", staff: "Alex Moreau", created: t - 86400, active: true, canRevoke: true },
            { id: 37, type: "ban", name: "Marco Rossi", license: "license:abcd1234ef5678", reason: "Cheat (menu)", staff: "Ramiro Lotus", created: t - 9 * 86400, expires: null, active: true, canRevoke: false },
            { id: 30, type: "ban", name: "Léa Martin", license: "license:00ff11ee22dd33", reason: "Insultes", staff: "Alex Moreau", created: t - 20 * 86400, expires: t - 10 * 86400, active: false, revoked: true, revokedBy: "Ramiro Lotus", revokeReason: "Erreur" },
        ] };
    }
    if (name === "action") return { ok: false, error: "Aperçu navigateur : rien n'est envoyé au serveur." };
    return { ok: true };
}

// Démo lancée après le chargement de tous les scripts (sanctions.js compris)
if (!IN_GAME) window.addEventListener("load", () => {
    // ?view=ranks&rank=2 ou ?view=members pour prévisualiser une page précise
    const params = new URLSearchParams(location.search);
    window.postMessage({ action: "open", state: demoState() }, "*");
    setTimeout(() => {
        if (params.get("rank")) selectedRankId = Number(params.get("rank"));
        if (params.get("view")) go(params.get("view"));
        if (params.get("pole")) setTimeout(() => selectPole(params.get("pole")), 300);
        if (params.get("entity")) window.postMessage({ action: "devEntity", entity: { type: "Véhicule", model: "sultan", hash: 970598228, hashHex: "0x39DA2754", coords: { x: 215.7, y: -810.12, z: 30.73 }, heading: 157.5, health: 1000, maxHealth: 1000, engine: 1000, networked: true, netId: 132, owner: 4, plate: "LUNA 123" } }, "*");
        if (params.get("rank")) selectRank(Number(params.get("rank")));
        if (params.get("player")) selectPlayer(Number(params.get("player")));
        if (params.get("offline")) { switchPlayersTab("offline"); playerFilter.text = "to"; scheduleOfflineSearch("to"); setTimeout(() => selectOffline("9f1e22aa00bb11"), 500); }
        if (params.get("logtab")) setTimeout(() => [...document.querySelectorAll("#view-logs .segmented button")].find((b) => b.textContent === "Tchat")?.click(), 300);
        if (params.get("scroll")) setTimeout(() => document.querySelectorAll(".view.on .scroll").forEach((e) => { e.scrollTop = Number(params.get("scroll")); }), 600);
        if (params.get("warning")) window.postMessage({ action: "warning", warning: { id: 41, reason: "Langage HRP en pleine scène, merci de rester dans ton personnage.", date: Math.floor(Date.now() / 1000) } }, "*");
    }, 50);
});
