"use strict";

// ====================================================================
//  lunatic_admin — tuile Joueurs (organisation comme Vision)
//  Onglets Joueurs / Map influence. Liste avec filtres (connectés, staff, premium, temps de jeu, bannis, base) et
//  sélection multiple ; fiche en 3 colonnes : profil, actions / inventaire / véhicules, logs / sanctions.
//  Les fiches (paintFiche dans app.js, paintOfflineFiche dans offline.js) passent par playerColumns().
// ====================================================================

const playersView = { mode: "players", filter: "online", selection: new Set(), banned: null, pane: "actions", side: "logs" };
let playerLogs = null; // { license, list }
let influenceMap = null;

const PLAYER_FILTERS = [
    { value: "online", label: "Connectés", icon: "i-player" },
    { value: "staff", label: "Staff", icon: "i-shield" },
    { value: "premium", label: "Premium", icon: "i-gem" },
    { value: "playtime", label: "Temps de jeu", icon: "i-clock" },
    { value: "banned", label: "Bannis", icon: "i-ban", perm: "sanctions.view" },
    { value: "offline", label: "Recherche en base", icon: "i-search", perm: "players.offline" },
];

function playtimeShort(minutes) {
    if (!minutes) return "0 min";
    const hours = Math.floor(minutes / 60);
    return hours > 0 ? `${hours} h ${String(minutes % 60).padStart(2, "0")}` : `${minutes} min`;
}

function renderPlayers() {
    const root = $("view-players");

    if (!playersDom || !root.contains(playersDom.list)) {
        const search = h("input", { placeholder: "Nom ou ID", value: playerFilter.text });
        search.addEventListener("input", () => {
            playerFilter.text = search.value;
            if (playersTab === "offline" && playersView.filter !== "banned") scheduleOfflineSearch(search.value);
            else paintPlayerList();
        });
        playersDom = {
            title: h("h3", null, "Joueurs"),
            count: h("span", { class: "cnt" }),
            tabs: h("div", { class: "player-filters" }),
            search,
            selectBar: h("div", { class: "player-select" }),
            list: h("div", { class: "side-scroll" }),
            fiche: h("div", { class: "player-fiche" }),
            mode: h("div", { class: "segmented" }),
            map: h("div", { class: "player-map" }),
        };
        root.replaceChildren(h("div", { class: "players-page" },
            h("div", { class: "players-top" }, playersDom.mode),
            h("div", { class: "players-body" },
                h("aside", { class: "sidebar" },
                    h("div", { class: "side-head" }, icon("i-users"), playersDom.title, playersDom.count),
                    h("div", { class: "side-search" }, playersDom.tabs),
                    h("div", { class: "side-search" }, h("label", { class: "search" }, icon("i-search"), search)),
                    playersDom.selectBar,
                    playersDom.list),
                playersDom.fiche),
            playersDom.map));
    }

    if (!can("illegal.manage")) playersView.mode = "players";
    const modes = [{ value: "players", label: "Joueurs" }];
    if (can("illegal.manage")) modes.push({ value: "map", label: "Map influence" });
    playersDom.mode.replaceChildren(...segmentedButtons(modes, playersView.mode, (value) => {
        playersView.mode = value;
        influenceAt = 0;
        renderPlayers();
    }));
    const onMap = playersView.mode === "map";
    root.querySelector(".players-body").style.display = onMap ? "none" : "";
    playersDom.map.style.display = onMap ? "" : "none";
    if (onMap) return paintInfluenceMap();

    // Filtres (la recherche en base remplace l'ancien onglet « Hors ligne »)
    const filters = PLAYER_FILTERS.filter((f) => !f.perm || can(f.perm));
    if (playersTab === "offline" && playersView.filter !== "banned") playersView.filter = "offline";
    else if (playersTab !== "offline" && playersView.filter === "offline") playersView.filter = "online";
    playersDom.tabs.replaceChildren(...filters.map((f) => h("button", { class: `player-filter${playersView.filter === f.value ? " on" : ""}`, title: f.label, onclick: () => setPlayerFilter(f.value) }, icon(f.icon))));
    const current = filters.find((f) => f.value === playersView.filter) || filters[0];
    playersDom.title.textContent = current.label;
    playersDom.search.placeholder = playersTab === "offline" ? "Nom RP ou licence (2 caractères min.)" : "Nom ou ID";

    paintPlayerList();
    paintFiche();
}

// Bannis : la liste reste affichée, la fiche ouverte est celle en base (onglet « offline »)
function setPlayerFilter(value) {
    playersView.filter = value;
    if (value === "banned") loadBannedPlayers();
    const tab = value === "offline" ? "offline" : value === "banned" ? playersTab : "online";
    if (tab !== playersTab) return switchPlayersTab(tab);
    renderPlayers();
}

function openBaseFiche(identifier) {
    if (!can("players.offline")) return toast("Fiche en base : permission Joueurs hors ligne requise.", "error");
    if (playersTab !== "offline") switchPlayersTab("offline");
    selectOffline(identifier);
}

async function loadBannedPlayers() {
    const res = await nui("action", { action: "players.banned", payload: {} }).catch(() => null);
    playersView.banned = res && res.ok ? res.players : [];
    if (playersView.filter === "banned") paintPlayerList();
}

function filteredPlayers() {
    const text = playerFilter.text.trim().toLowerCase();
    let list = players().filter((p) => !text || p.name.toLowerCase().includes(text) || String(p.serverId) === text);
    if (playersView.filter === "staff") list = list.filter((p) => p.rank);
    if (playersView.filter === "premium") list = list.filter((p) => p.premium);
    if (playersView.filter === "playtime") list = [...list].sort((a, b) => (b.playtime || 0) - (a.playtime || 0));
    return list;
}

function paintPlayerList() {
    if (playersView.filter === "banned") return paintBannedList();
    if (playersTab === "offline") return paintOfflineList();

    const rows = filteredPlayers();
    playersDom.count.textContent = String(rows.length);
    loadMugshots(players().map((p) => p.identifier)).then((found) => found && paintPlayerList());

    // Sélection : seulement des joueurs encore connectés
    const online = new Set(players().map((p) => p.serverId));
    for (const id of playersView.selection) if (!online.has(id)) playersView.selection.delete(id);
    paintSelectBar(rows);

    playersDom.list.replaceChildren(...(rows.length ? rows.map((p) => {
        const check = h("input", { type: "checkbox", class: "player-check", checked: playersView.selection.has(p.serverId) });
        check.addEventListener("click", (e) => {
            e.stopPropagation();
            if (check.checked) playersView.selection.add(p.serverId); else playersView.selection.delete(p.serverId);
            paintSelectBar(rows);
        });
        const row = h("div", { class: `list-row player-row${p.serverId === selectedPlayerId ? " active" : ""}`, onclick: () => selectPlayer(p.serverId) },
            check,
            mugshotImg(p.identifier, "mug-row"),
            h("span", { class: "who" },
                h("b", null, p.name),
                h("span", null, [playersView.filter === "playtime" ? playtimeShort(p.playtime) : p.job, p.premium ? "Premium" : null].filter(Boolean).join(" · "))),
            p.frozen ? icon("i-snow") : null,
            p.jailed ? icon("i-lock") : null,
            h("span", { class: "status on" }),
            h("span", { class: "pid" }, `${p.serverId}`));
        if (p.rank) row.title = p.rank.name;
        return row;
    }) : [h("div", { class: "muted side-empty" }, "Aucun joueur ne correspond.")]));
}

function paintBannedList() {
    playersDom.selectBar.replaceChildren();
    const list = playersView.banned;
    const text = playerFilter.text.trim().toLowerCase();
    if (!list) return playersDom.list.replaceChildren(h("div", { class: "muted side-empty" }, "Chargement…"));
    const rows = list.filter((b) => !text || (b.name || "").toLowerCase().includes(text));
    playersDom.count.textContent = String(rows.length);
    playersDom.list.replaceChildren(...(rows.length ? rows.map((b) => h("button", { class: `list-row player-row${playersTab === "offline" && b.identifier === offlineSelected ? " active" : ""}`, onclick: () => openBaseFiche(b.identifier) },
        mugshotImg(b.identifier, "mug-row"),
        h("span", { class: "who" }, h("b", null, b.name || "?"), h("span", null, b.expires ? `jusqu'au ${fmtDate(b.expires)}` : "définitif")),
        h("span", { class: "status ban" }))) : [h("div", { class: "muted side-empty" }, "Aucun joueur banni.")]));
}

// Actions groupées sur la sélection
function paintSelectBar(rows) {
    const count = playersView.selection.size;
    const all = h("label", { class: "player-select-all" }, h("input", { type: "checkbox", checked: count > 0 && rows.every((p) => playersView.selection.has(p.serverId)) }), "Tout sélect.");
    all.querySelector("input").addEventListener("change", (e) => {
        if (e.target.checked) rows.forEach((p) => playersView.selection.add(p.serverId)); else playersView.selection.clear();
        paintPlayerList();
    });
    const groupAct = async (action, label, perm) => {
        if (!can(perm)) return toast("Permission manquante.", "error");
        const ids = [...playersView.selection];
        let done = 0;
        for (const serverId of ids) {
            const res = await nui("action", { action, payload: { serverId } }).catch(() => null);
            if (res && res.ok) done += 1;
        }
        toast(`${label} : ${done}/${ids.length} joueur(s).`, done ? "ok" : "error");
    };
    playersDom.selectBar.replaceChildren(all, h("div", { class: "player-group" }, !count ? h("span", { class: "muted" }, "Actions groupées") : [
        h("span", { class: "muted" }, `${count} sélectionné(s)`),
        h("button", { class: "btn small ghost sq-btn", title: "Soigner", onclick: () => groupAct("player.heal", "Soignés", "players.heal") }, icon("i-heart")),
        h("button", { class: "btn small ghost sq-btn", title: "Réanimer", onclick: () => groupAct("player.revive", "Réanimés", "players.heal") }, icon("i-pulse")),
        h("button", { class: "btn small ghost sq-btn", title: "Ramener à moi", onclick: () => groupAct("player.bring", "Ramenés", "players.bring") }, icon("i-bring")),
        h("button", { class: "btn small ghost sq-btn", title: "Figer / libérer", onclick: () => groupAct("player.freeze", "Figés ou libérés", "players.freeze") }, icon("i-snow"))]));
}

// ---------- Fiche en 3 colonnes ----------

async function loadPlayerLogs(license) {
    if (!license || !can("logs.view")) return;
    const res = await nui("action", { action: "logs.player", payload: { license } }).catch(() => null);
    playerLogs = { license, list: res && res.ok ? res.logs : [] };
    if (view === "players" && playersDom) paintFiche();
}

function profileCard(info) {
    const p = info.profile || {};
    const sex = info.sex === "m" ? "Homme" : info.sex === "f" ? "Femme" : null;
    return h("div", { class: "card profile-card" },
        h("div", { class: "crew-sub" }, "Informations"),
        infoRow("Discord", p.discord ? h("span", { class: "mono" }, p.discord) : null),
        infoRow("Date de création", p.firstSeen ? fmtDate(p.firstSeen) : info.createdAt ? fmtDate(info.createdAt) : null),
        infoRow("Dernière connexion", info.serverId ? "En ligne" : p.lastSeen ? fmtDate(p.lastSeen) : info.lastSeen ? fmtDate(info.lastSeen) : null),
        infoRow("Temps de jeu", playtimeShort(p.playtime || 0)),
        infoRow("Nombre de warns", String(p.warns || 0)),
        infoRow("Crew", p.crew ? `${p.crew.label}${p.crew.rank ? ` · ${p.crew.rank}` : ""}` : "Aucun"),
        infoRow("Job", info.job ? `${info.job.label || info.job.name}${info.job.grade ? ` · ${info.job.grade}` : ""}` : null),
        info.serverId ? infoRow("En service", info.onDuty ? "Oui" : "Non") : null,
        infoRow("Argent banque", money(info.bank)),
        infoRow("Argent espèces", money(info.money)),
        infoRow("Statut", p.banned ? h("span", { class: "badge ban" }, "Banni") : h("span", { class: "badge ok" }, "Actif")),
        h("div", { class: "crew-sub" }, "Identité"),
        infoRow("Naissance", info.dateofbirth), infoRow("Sexe", sex), infoRow("Taille", info.height ? `${info.height} cm` : null),
        h("div", { class: "crew-sub" }, "Personnages liés au compte Discord"),
        (p.linked || []).length
            ? (p.linked || []).map((l) => h("button", { class: "linked-row", onclick: () => openBaseFiche(l.identifier) },
                mugshotImg(l.identifier, "mug-row"), h("span", null, l.name), h("span", { class: "muted" }, l.lastSeen ? ago(l.lastSeen) : "")))
            : h("p", { class: "hint-line" }, p.discord ? "Aucun autre compte avec ce Discord." : "Discord non lié."));
}

function assetsCard(info) {
    const p = info.profile || {};
    return h("div", null,
        h("div", { class: "card" }, h("h3", { class: "card-title" }, `Véhicules (${(p.vehicles || []).length})`),
            (p.vehicles || []).length ? h("div", { class: "crew-list" }, p.vehicles.map((v) => h("div", { class: "crew-line" },
                icon("i-car"), h("span", { class: "who" }, h("b", { class: "mono" }, v.plate), h("span", null, [v.model ? `modèle ${v.model}` : null, v.type, v.stored ? "au garage" : "sorti"].filter(Boolean).join(" · "))))))
                : h("p", { class: "hint-line", style: "margin:0" }, "Aucun véhicule (table ESX owned_vehicles).")),
        h("div", { class: "card", style: "margin-top:12px" }, h("h3", { class: "card-title" }, `Instances (${(p.instances || []).length})`),
            (p.instances || []).length ? h("div", { class: "crew-list" }, p.instances.map((i) => h("div", { class: "crew-line" },
                icon("i-door"), h("span", { class: "who" }, h("b", null, i.label), h("span", null, i.kind)))))
                : h("p", { class: "hint-line", style: "margin:0" }, "Aucune propriété (planques de son crew ; logements des joueurs à venir).")));
}

function playerLogsList(info) {
    if (!can("logs.view")) return h("p", { class: "hint-line" }, "Permission Logs requise.");
    const loaded = playerLogs && playerLogs.license === info.license;
    if (!loaded) {
        if (!playerLogs || playerLogs.license !== info.license) { playerLogs = { license: info.license, list: null }; loadPlayerLogs(info.license); }
        return h("div", { class: "empty" }, "Chargement…");
    }
    if (!playerLogs.list) return h("div", { class: "empty" }, "Chargement…");
    if (!playerLogs.list.length) return h("p", { class: "hint-line" }, "Aucun log pour ce joueur.");
    return h("div", { class: "player-logs" }, playerLogs.list.map((log) => {
        const { verb, summary } = describeLog(log);
        const [day, time] = logTime(log.created);
        const dot = h("span", { class: "log-dot" });
        dot.style.background = levelOf(log.level).color;
        return h("div", { class: "player-log" }, h("span", { class: "log-when mono" }, h("small", null, day), time), dot,
            h("span", { class: "log-line" }, `${verb}${log.target ? ` ${log.target}` : ""}${summary ? ` · ${summary}` : ""}`));
    }));
}

// parts : { head, actions, money, extra, sanctions : { ban, warn } }
function playerColumns(fiche, info, parts) {
    const keep = [...fiche.querySelectorAll(".crew-scroll")].map((el) => el.scrollTop);
    const same = fiche.dataset.key === info.license;
    fiche.dataset.key = info.license;

    const paneTabs = h("div", { class: "segmented block" }, segmentedButtons([
        { value: "actions", label: "Actions" }, { value: "money", label: "Inventaire" }, { value: "assets", label: "Véhicules" },
    ], playersView.pane, (v) => { playersView.pane = v; paintFiche(); }));
    const sideTabs = [{ value: "logs", label: "Logs serveur" }];
    if (can("sanctions.view")) sideTabs.push({ value: "history", label: "Sanctions" });
    if (!sideTabs.some((t) => t.value === playersView.side)) playersView.side = "logs";
    const sideTabBar = h("div", { class: "segmented block" }, segmentedButtons(sideTabs, playersView.side, (v) => { playersView.side = v; paintFiche(); }));

    const pane = playersView.pane === "money" ? parts.money : playersView.pane === "assets" ? [assetsCard(info)] : parts.actions;
    const activeBan = playerHistory && playerHistory.license === info.license ? playerHistory.list.find((s) => s.type === "ban" && s.canRevoke) : null;

    fiche.replaceChildren(
        h("section", { class: "crew-col player-col" },
            h("div", { class: "crew-col-head" }, icon("i-player"), "Fiche du joueur"),
            h("div", { class: "crew-scroll crew-col-body" }, parts.head, profileCard(info), parts.extra)),
        h("section", { class: "crew-col player-col" },
            h("div", { class: "crew-col-pad", style: "padding-top:14px" }, paneTabs),
            h("div", { class: "crew-scroll crew-col-body" }, pane)),
        h("section", { class: "crew-col player-col" },
            h("div", { class: "crew-col-pad", style: "padding-top:14px" }, sideTabBar),
            h("div", { class: "crew-scroll crew-col-body" }, playersView.side === "history" ? historyCard(info) : playerLogsList(info)),
            h("div", { class: "crew-actions" },
                h("button", { class: "btn small ok-btn", disabled: !activeBan, title: activeBan ? `Révoquer le ban #${activeBan.id}` : "Aucun ban actif", onclick: () => activeBan && openRevoke(activeBan) }, icon("i-undo"), "Déban"),
                h("button", { class: "btn small danger", disabled: !parts.sanctions.ban, onclick: parts.sanctions.ban }, icon("i-ban"), "Bannir"),
                h("button", { class: "btn small warn", disabled: !parts.sanctions.warn, title: parts.sanctions.warn ? null : "Joueur connecté seulement", onclick: parts.sanctions.warn }, icon("i-warn"), "Warn"))));

    if (same) fiche.querySelectorAll(".crew-scroll").forEach((el, index) => { if (keep[index]) el.scrollTop = keep[index]; });
}

// ---------- Map influence ----------

// Rechargée à l'ouverture de l'onglet, puis au plus toutes les 30 s (pas à chaque mise à jour de l'état du panel)
let influenceAt = 0;

async function paintInfluenceMap() {
    if (Date.now() - influenceAt < 30000) return;
    influenceAt = Date.now();
    const box = playersDom.map;
    if (!influenceMap) influenceMap = gtaMap();
    if (!box.childElementCount) box.replaceChildren(h("div", { class: "influence-layout" }, h("div", { class: "influence-map" }, influenceMap.el), h("aside", { class: "influence-side crew-scroll" })));
    const side = box.querySelector(".influence-side");
    const res = await nui("action", { action: "territories.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return side.replaceChildren(h("p", { class: "hint-line" }, (res && res.error) || "Territoires indisponibles."));
    influenceMap.clear();
    for (const t of res.territories) {
        influenceMap.circle(t.x, t.y, t.radius, { color: t.owner ? t.owner.color : "#9aa3b2", fill: t.owner ? 0.35 : 0.12, dashed: !t.owner, label: `${t.label} · ${t.owner ? t.owner.label : "libre"}` });
    }
    influenceMap.fit();
    side.replaceChildren(h("div", { class: "crew-col-head" }, icon("i-flag"), "Territoires", h("span", { class: "cnt" }, String(res.territories.length))),
        ...res.territories.map((t) => h("div", { class: "influence-card" },
            h("div", { class: "influence-head" }, h("b", null, t.label), h("span", { class: `badge ${t.owner ? "ok" : "muted"}` }, t.owner ? t.owner.label : "Libre")),
            t.ranking.length ? t.ranking.slice(0, 4).map((r) => {
                const fill = h("i");
                fill.style.width = `${Math.round((r.score / Math.max(1, t.ranking[0].score)) * 100)}%`;
                fill.style.background = r.color;
                return h("div", { class: "bar-row" }, h("div", { class: "info-row" }, h("span", null, r.label), h("b", null, String(Math.floor(r.score)))), h("div", { class: "bar" }, fill));
            }) : h("p", { class: "hint-line", style: "margin:0" }, "Aucune influence."),
            h("button", { class: "btn small ghost", onclick: () => influenceMap.focus(t.x, t.y, 4) }, icon("i-pin"), "Voir sur la carte"))));
}
