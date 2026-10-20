"use strict";

// ====================================================================
//  lunatic_admin — recherche globale (Ctrl+K ou bouton « Rechercher »)
//  Pages, joueurs en ligne et hors ligne, entreprises, services publics, magasins, crews.
//  Seules les pages autorisées par le rang sont proposées.
// ====================================================================

const searchCache = { at: 0, structures: {}, shops: [], categories: [], crews: [] };
let searchOfflineTimer = null;

const pageVisible = (id) => {
    const page = NAV.find((n) => n.id === id);
    return !!page && page.show();
};

// Texte comparable : minuscules, sans accents
const fold = (text) => String(text || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");

// Listes chargées au plus toutes les 30 s (elles changent peu)
async function loadSearchSources() {
    if (Date.now() - searchCache.at < 30000) return;
    searchCache.at = Date.now();
    const call = (action, payload) => nui("action", { action, payload: payload || {} }).catch(() => null);
    const jobs = [];

    for (const kind of Object.keys(STRUCTURE_KINDS)) {
        if (!pageVisible(STRUCTURE_KINDS[kind].view)) continue;
        jobs.push(call("structures.list", { kind }).then((res) => { searchCache.structures[kind] = res && res.ok ? res.structures || [] : []; }));
    }
    if (pageVisible("catalogs")) {
        jobs.push(call("shops.categories").then((res) => { searchCache.categories = res && res.ok ? res.categories || [] : []; }));
        jobs.push(call("shops.list", { all: true }).then((res) => { searchCache.shops = res && res.ok ? res.shops || [] : []; }));
    }
    if (pageVisible("crews")) {
        jobs.push(call("crews.list").then((res) => { searchCache.crews = res && res.ok ? res.crews || [] : []; }));
    }
    await Promise.all(jobs);
}

// Résultats groupés : [{ group, items: [{ icon, label, sub, open }] }]
function searchResults(query, offline) {
    const q = fold(query.trim());
    const match = (...texts) => texts.some((t) => fold(t).includes(q));
    const groups = [];
    const add = (group, items) => {
        // Ceux qui commencent par la recherche d'abord
        const sorted = items.sort((a, b) => Number(!fold(a.label).startsWith(q)) - Number(!fold(b.label).startsWith(q)));
        if (sorted.length) groups.push({ group, items: sorted.slice(0, 6) });
    };

    add("Pages", NAV.filter((n) => n.id !== "home" && n.show() && (!q || match(n.label, n.group && GROUPS[n.group].label)))
        .map((n) => ({ icon: n.icon, label: n.label, sub: n.group ? GROUPS[n.group].label : "Page", open: () => go(n.id) })));

    if (!q) return groups;

    if (pageVisible("players")) {
        add("Joueurs en ligne", (state.players || []).filter((p) => match(p.name, p.job) || String(p.serverId) === q)
            .map((p) => ({ icon: "i-player", label: p.name, sub: [`ID ${p.serverId}`, p.job].filter(Boolean).join(" · "), open: () => openOnlinePlayer(p.serverId) })));
        if (offline) {
            add("Joueurs en base", offline.map((p) => ({
                icon: "i-search", label: p.name, sub: p.online ? `En ligne (ID ${p.online})` : p.lastSeen ? `Vu ${ago(p.lastSeen)}` : "Jamais revu",
                open: () => openOfflinePlayer(query.trim(), offline, p.identifier),
            })));
        }
    }

    for (const kind of Object.keys(STRUCTURE_KINDS)) {
        const meta = STRUCTURE_KINDS[kind];
        add(meta.title, (searchCache.structures[kind] || []).filter((s) => match(s.label, s.job, s.typeLabel))
            .map((s) => ({ icon: meta.icon, label: s.label || s.job, sub: `${s.typeLabel} · ${s.job}`, open: () => openSearchStructure(kind, s.job) })));
    }

    const categoryOf = (id) => searchCache.categories.find((c) => c.id === id);
    add("Magasins", searchCache.shops.filter((s) => match(s.label, s.slug, (categoryOf(s.category) || {}).label))
        .map((s) => ({ icon: SHOP_ICONS[s.category] || "i-store", label: s.label, sub: `${(categoryOf(s.category) || {}).label || s.category} · ${s.slug}`, open: () => openSearchShop(s) })));

    add("Crews", searchCache.crews.filter((c) => match(c.label, c.typeLabel))
        .map((c) => ({ icon: "i-flag", label: c.label, sub: `${c.typeLabel} · level ${c.level}`, open: () => openSearchCrew(c.id) })));

    return groups;
}

// ---------- Ouverture d'un résultat ----------

function openOnlinePlayer(serverId) {
    go("players");
    if (playersTab !== "online") switchPlayersTab("online");
    selectPlayer(serverId);
}

function openOfflinePlayer(query, results, identifier) {
    go("players");
    if (playersTab !== "offline") switchPlayersTab("offline");
    // La liste de gauche reprend la recherche
    playerFilter.text = query;
    if (playersDom) playersDom.search.value = query;
    offlineResults = results;
    selectOffline(identifier);
}

function openSearchStructure(kind, job) {
    go(STRUCTURE_KINDS[kind].view);
    selectStructure(kind, job);
}

function openSearchShop(shop) {
    const category = searchCache.categories.find((c) => c.id === shop.category);
    if (!category) return toast("Catégorie du magasin introuvable.", "error");
    go("catalogs");
    guardUnsaved("catalogs", () => {
        untrackUnsaved("catalogs");
        if (!shopState.category || shopState.category.id !== category.id) openShopCategory(category);
        selectShop(shop.id);
    });
}

function openSearchCrew(id) {
    go("crews");
    selectCrew(id);
}

// ---------- Fenêtre de recherche ----------

function openSearch() {
    const input = h("input", { placeholder: "Joueur, page, entreprise, magasin, crew…", spellcheck: "false" });
    const list = h("div", { class: "search-results" });
    let rows = [];
    let active = 0;
    let offline = null;
    let offlineQuery = "";

    const highlight = () => rows.forEach((row, i) => row.el.classList.toggle("active", i === active));
    const choose = (row) => {
        closeModal();
        row.open();
    };

    const paint = () => {
        const groups = searchResults(input.value, offlineQuery === input.value.trim() ? offline : null);
        rows = [];
        const nodes = [];
        for (const g of groups) {
            nodes.push(h("div", { class: "search-group" }, g.group));
            for (const item of g.items) {
                const row = { open: item.open };
                const index = rows.length;
                row.el = h("button", { class: "search-row", onclick: () => choose(row), onmousemove: () => { if (active !== index) { active = index; highlight(); } } },
                    icon(item.icon), h("span", { class: "who" }, h("b", null, item.label), h("span", null, item.sub)));
                rows.push(row);
                nodes.push(row.el);
            }
        }
        active = Math.min(active, Math.max(0, rows.length - 1));
        list.replaceChildren(...(nodes.length ? nodes : [h("div", { class: "search-empty" }, "Aucun résultat.")]));
        highlight();
    };

    // Joueurs hors ligne : recherche en base après une courte pause de frappe
    const searchOffline = () => {
        clearTimeout(searchOfflineTimer);
        const query = input.value.trim();
        if (!can("players.offline") || query.length < 2) return;
        searchOfflineTimer = setTimeout(async () => {
            const res = await nui("action", { action: "offline.search", payload: { query } }).catch(() => null);
            if (input.value.trim() !== query) return;
            offlineQuery = query;
            // Les joueurs connectés apparaissent déjà dans « Joueurs en ligne »
            offline = res && res.ok && Array.isArray(res.players) ? res.players.filter((p) => !p.online) : [];
            paint();
        }, 300);
    };

    input.addEventListener("input", () => {
        active = 0;
        paint();
        searchOffline();
    });
    input.addEventListener("keydown", (e) => {
        if (e.key === "ArrowDown" || e.key === "ArrowUp") {
            e.preventDefault();
            if (!rows.length) return;
            active = (active + (e.key === "ArrowDown" ? 1 : rows.length - 1)) % rows.length;
            highlight();
            rows[active].el.scrollIntoView({ block: "nearest" });
        } else if (e.key === "Enter") {
            e.preventDefault();
            if (rows[active]) choose(rows[active]);
        }
    });

    openModal(() => [
        h("div", { class: "search-input" }, icon("i-search"), input, h("kbd", null, "Échap")),
        list,
        h("div", { class: "search-foot" }, h("span", null, h("kbd", null, "↑"), " ", h("kbd", null, "↓"), " naviguer"), h("span", null, h("kbd", null, "Entrée"), " ouvrir"), h("span", null, h("kbd", null, "Ctrl K"), " rechercher partout")),
    ]);
    $("modal").classList.add("search-modal");
    paint();
    input.focus();
    loadSearchSources().then(() => { if (document.body.contains(input)) paint(); });
}
