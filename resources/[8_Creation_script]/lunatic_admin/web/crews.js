"use strict";

// ====================================================================
//  lunatic_admin — tuile Crews (organisation en 4 colonnes)
//  1. Types de crew et demandes, puis les crews du type choisi ; 2. Fiche de groupe ;
//  3. Infrastructure (positions, propriétés, territoires) ; 4. Membres et rangs, actions (rejoindre, wipe, supprimer).
// ====================================================================

const crewState = {
    list: null, types: [], requestsCount: 0, typeFilter: null, selected: null, info: null, draft: null, saved: "",
    infraTab: "positions", sideTab: "members", memberSearch: "", openMember: null, candidates: null,
    territories: null, requests: null, loadedAt: 0,
    openGroups: new Set(), // groupes de positions ouverts (Stockage, Stockage séparé, Garage)
};

function renderCrews() {
    if (!$("view-crews").childElementCount) paintCrews();
    if (Date.now() - crewState.loadedAt > 10000) loadCrews();
}

async function loadCrews() {
    crewState.loadedAt = Date.now();
    const res = await nui("action", { action: "crews.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    crewState.list = res.crews || [];
    crewState.types = res.types || [];
    crewState.requestsCount = res.requests || 0;
    if (!crewState.typeFilter && crewState.types.length) crewState.typeFilter = crewState.types[0].id;
    paintCrews();
}

async function loadCrewInfo() {
    const id = crewState.selected;
    if (!id) return;
    const res = await nui("action", { action: "crews.info", payload: { id } }).catch(() => null);
    if (id !== crewState.selected) return;
    crewState.info = res && res.ok ? res.crew : false;
    paintCrews();
    if (crewState.infraTab === "territories") loadCrewTerritories();
}

async function loadCrewTerritories() {
    const id = crewState.selected;
    const res = await nui("action", { action: "crews.territories", payload: { id } }).catch(() => null);
    if (id !== crewState.selected) return;
    crewState.territories = res && res.ok ? res.territories : [];
    paintCrews();
}

async function loadCrewRequests() {
    const res = await nui("action", { action: "crews.requests", payload: {} }).catch(() => null);
    crewState.requests = res && res.ok ? res : { pending: [], handled: [] };
    crewState.requestsCount = crewState.requests.pending.length;
    paintCrews();
}

async function crewAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) {
        loadCrews();
        loadCrewInfo();
    }
    return res;
}

// Change de type, de crew ou d'onglet (en demandant si la fiche a des modifications)
function crewGo(changes) {
    guardUnsaved("crews", () => {
        untrackUnsaved("crews");
        const crewChanged = "selected" in changes && changes.selected !== crewState.selected;
        Object.assign(crewState, changes, { draft: null });
        if (crewChanged) {
            crewState.info = null;
            crewState.territories = null;
            crewState.openMember = null;
            crewState.candidates = null;
            loadCrewInfo();
        }
        if (crewState.typeFilter === "requests") loadCrewRequests();
        paintCrews();
    });
}

function selectCrew(id) {
    const entry = (crewState.list || []).find((c) => c.id === id);
    crewGo({ selected: id, typeFilter: entry ? entry.type : crewState.typeFilter });
}

const crewType = (id) => crewState.types.find((t) => t.id === id) || { id, label: id, color: "#9650ff" };
const crewLevelOf = (xp, levels) => levels.reduce((level, needed, index) => (xp >= needed ? index + 1 : level), 1);

// ---------- Mise en page ----------

function paintCrews() {
    const root = $("view-crews");
    if (!crewState.list) return root.replaceChildren(h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-flag"), "Chargement des crews…")));

    const keep = [...root.querySelectorAll(".crew-scroll")].map((el) => el.scrollTop);
    let columns;
    if (crewState.typeFilter === "requests") columns = [crewRequestsColumn()];
    else if (!crewState.selected) columns = [h("div", { class: "crew-empty" }, h("div", { class: "empty" }, icon("i-flag"), "Sélectionnez un crew dans la liste, ou créez-en un."))];
    else if (crewState.info === false) columns = [h("div", { class: "crew-empty" }, h("div", { class: "empty" }, icon("i-flag"), "Ce crew n'existe plus."))];
    else if (!crewState.info) columns = [h("div", { class: "crew-empty" }, h("div", { class: "empty" }, icon("i-flag"), "Chargement du crew…"))];
    else columns = [crewFicheColumn(crewState.info), crewInfraColumn(crewState.info), crewMembersColumn(crewState.info)];

    root.replaceChildren(h("div", { class: `crew-page${columns.length === 1 ? " single" : ""}` }, crewNavColumn(), ...columns));
    root.querySelectorAll(".crew-scroll").forEach((el, index) => { if (keep[index]) el.scrollTop = keep[index]; });
}

function crewNavColumn() {
    const counts = {};
    for (const c of crewState.list) counts[c.type] = (counts[c.type] || 0) + 1;

    const typeRows = crewState.types.map((t) => {
        const dot = h("span", { class: "crew-dot" });
        dot.style.background = t.color || "#9650ff";
        return h("button", { class: `list-row${crewState.typeFilter === t.id ? " active" : ""}`, onclick: () => crewState.typeFilter !== t.id && crewGo({ typeFilter: t.id }) },
            dot, h("span", { class: "name" }, t.label), h("span", { class: "cnt" }, String(counts[t.id] || 0)));
    });
    const requests = h("button", { class: `list-row${crewState.typeFilter === "requests" ? " active" : ""}`, onclick: () => crewGo({ typeFilter: "requests", selected: null }) },
        icon("i-user-plus"), h("span", { class: "name" }, "Demandes de crew"),
        crewState.requestsCount ? h("span", { class: "cnt crew-alert" }, String(crewState.requestsCount)) : null);

    const type = crewState.typeFilter !== "requests" ? crewType(crewState.typeFilter) : null;
    const crewsOfType = type ? crewState.list.filter((c) => c.type === type.id) : [];

    return h("aside", { class: "sidebar crew-nav crew-scroll" },
        h("div", { class: "crew-block" },
            h("div", { class: "crew-block-head" }, icon("i-layers"), "Type de crew"),
            typeRows, requests),
        type ? h("div", { class: "crew-block" },
            h("div", { class: "crew-block-head" }, icon("i-flag"), type.label),
            crewsOfType.map((c) => h("button", { class: `list-row player-row${c.id === crewState.selected ? " active" : ""}`, onclick: () => c.id !== crewState.selected && selectCrew(c.id) },
                (() => { const d = h("span", { class: "crew-dot" }); d.style.background = c.color; return d; })(),
                h("span", { class: "who" }, h("b", null, c.label), h("span", null, `Level ${c.level} · ${c.members} membre${c.members > 1 ? "s" : ""}${c.members && !c.leader ? " · sans chef" : ""}`)))),
            h("button", { class: "list-row", onclick: () => openCreateCrew(type.id) }, icon("i-plus"), h("span", { class: "name" }, "Créer un crew"))) : null);
}

// ---------- 2. Fiche de groupe ----------

function crewDraft(c) {
    const key = `crew:${c.id}`;
    if (crewState.draft && crewState.draft.key === key) return crewState.draft;
    const leader = c.members.find((m) => m.rank === c.topRank);
    const base = { key, label: c.label, type: c.type, motto: c.motto || "", color: c.color, leader: leader ? leader.identifier : "", xp: c.xp, lab: c.lab || "", logo: c.logo || "" };
    crewState.draft = base;
    crewState.saved = JSON.stringify(base);
    trackUnsaved("crews", {
        label: `Crew ${c.label}`,
        isDirty: () => !!crewState.draft && JSON.stringify(crewState.draft) !== crewState.saved,
        save: () => saveCrew(),
        reset: () => { crewState.draft = null; paintCrews(); },
    });
    return base;
}

async function saveCrew() {
    const d = crewState.draft;
    const c = crewState.info;
    if (!d || !c) return;
    const res = await act("crews.save", { id: c.id, label: d.label.trim(), type: d.type, motto: d.motto.trim(), color: d.color, leader: d.leader, xp: Number(d.xp), lab: d.lab, logo: d.logo.trim() }, "Crew enregistré.");
    if (!res) return;
    untrackUnsaved("crews");
    crewState.draft = null;
    loadCrews();
    loadCrewInfo();
}

function crewField(iconName, label, input) {
    return h("div", { class: "crew-field" }, h("span", { class: "crew-field-label" }, icon(iconName), label), input);
}

function crewFicheColumn(c) {
    const d = crewDraft(c);
    const type = crewType(d.type);
    const bind = (input, key, event = "input", read = () => input.value) => { input.addEventListener(event, () => { d[key] = read(); }); return input; };

    const label = bind(h("input", { class: "input", maxlength: "60", value: d.label }), "label");
    const typeSelect = bind(h("select", { class: "input" }, crewState.types.map((t) => h("option", { value: t.id, selected: t.id === d.type }, t.label))), "type", "change");
    const motto = bind(h("input", { class: "input", maxlength: "80", placeholder: "Ex. Omertà", value: d.motto }), "motto");
    const color = bind(h("input", { class: "input color-input", type: "color", value: d.color }), "color");
    const leader = bind(h("select", { class: "input" }, h("option", { value: "" }, c.members.length ? "— Choisir un membre —" : "Aucun membre"),
        c.members.map((m) => h("option", { value: m.identifier, selected: m.identifier === d.leader }, m.name))), "leader", "change");
    const levels = c.levels || [0];
    const level = h("input", { class: "input mono", type: "number", min: "1", max: String(levels.length), value: String(crewLevelOf(Number(d.xp) || 0, levels)) });
    const xp = h("input", { class: "input mono", type: "number", min: "0", value: String(d.xp) });
    level.addEventListener("input", () => {
        const lvl = Math.max(1, Math.min(levels.length, Math.trunc(Number(level.value) || 1)));
        d.xp = levels[lvl - 1];
        xp.value = String(d.xp);
    });
    xp.addEventListener("input", () => { d.xp = xp.value === "" ? "" : Number(xp.value); level.value = String(crewLevelOf(Number(xp.value) || 0, levels)); });
    const typeLabOf = crewType(d.type);
    const lab = bind(h("select", { class: "input" },
        h("option", { value: "", selected: d.lab === "" }, d.type === "independent" ? "Selon le type (aucun)" : `Selon le type (${typeLabOf.label})`),
        crewState.types.filter((t) => t.id !== "independent").map((t) => h("option", { value: t.id, selected: d.lab === t.id }, `Labo ${t.label}`)),
        h("option", { value: "none", selected: d.lab === "none" }, "Aucun")), "lab", "change");
    const logo = bind(h("input", { class: "input mono", maxlength: "255", placeholder: "https://…/logo.png", value: d.logo }), "logo");

    const pic = c.logo ? h("img", { src: c.logo, alt: "" }) : icon("i-flag");
    if (c.logo) pic.addEventListener("error", () => pic.replaceWith(icon("i-flag")));
    const typeBadge = h("span", { class: "crew-type-badge" }, type.label);
    typeBadge.style.setProperty("--type", type.color || "#9650ff");

    return h("section", { class: "crew-col" },
        h("div", { class: "crew-col-head" }, icon("i-edit"), "Fiche de groupe"),
        h("div", { class: "crew-scroll crew-col-body" },
            h("div", { class: "crew-id" },
                h("div", { class: "crew-pic" }, pic),
                h("div", { class: "crew-id-text" }, h("b", null, c.label), c.motto ? h("span", { class: "muted" }, `« ${c.motto} »`) : null, typeBadge),
                h("div", { class: "crew-stats" },
                    h("div", null, h("b", null, String(c.level)), h("span", null, "Niv.")),
                    h("div", null, h("b", null, String(c.xp)), h("span", null, "XP")),
                    h("div", null, h("b", null, String(c.members.length)), h("span", null, "Mbs")))),
            h("div", { class: "crew-sub" }, "Informations"),
            crewField("i-key", "Nom", h("input", { class: "input mono", value: c.slug, disabled: true, title: "Identifiant interne (scripts)" })),
            crewField("i-edit", "Label", label),
            crewField("i-layers", "Type", typeSelect),
            crewField("i-flag", "Devise", motto),
            crewField("i-sparkle", "Couleur", color),
            crewField("i-crown", "Chef", leader),
            crewField("i-pulse", "Niveau", level),
            crewField("i-gem", "XP", xp),
            crewField("i-box", "Laboratoire", lab),
            h("div", { class: "crew-sub" }, "Logo"),
            crewField("i-image", "URL", imageField(logo)),
            h("p", { class: "hint-line" }, `Créé par ${c.createdBy || "?"}${c.createdAt ? ` le ${new Date(c.createdAt * 1000).toLocaleDateString("fr-FR")}` : ""}. Enregistrez avec la barre du bas.`)));
}

// ---------- 3. Infrastructure ----------

function crewInfraColumn(c) {
    const tabs = [["positions", "Positions"], ["properties", "Propriétés"], ["territories", "Territoires"]];
    const tabBar = h("div", { class: "crew-tabs" }, tabs.map(([id, label]) => h("button", { class: `crew-tab${crewState.infraTab === id ? " on" : ""}`, onclick: () => {
        if (crewState.infraTab === id) return;
        crewState.infraTab = id;
        paintCrews();
        if (id === "territories") loadCrewTerritories();
    } }, label)));

    let body;
    if (crewState.infraTab === "territories") body = crewTerritoriesTab(c);
    else if (typeof crewInfraTab === "function") body = crewInfraTab(c, crewState.infraTab); // partie infrastructure (positions, planques)
    else body = h("div", { class: "empty" }, icon("i-pin"), "Bientôt disponible.");

    return h("section", { class: "crew-col" },
        h("div", { class: "crew-col-head" }, icon("i-store"), "Infrastructure"),
        tabBar,
        h("div", { class: "crew-scroll crew-col-body" }, body));
}

function crewTerritoriesTab(c) {
    const list = crewState.territories;
    const reset = h("button", { class: "btn small danger wide", onclick: async () => {
        if (!(await confirmBox(`Effacer l'influence de ${c.label} ?`, "Son influence est remise à zéro dans toutes les zones : il perd celles qu'il tient.", "Effacer", true))) return;
        const res = await act("crews.resetInfluence", { id: c.id }, "Influence effacée.");
        if (res) loadCrewTerritories();
    } }, icon("i-undo"), "Reset tous les territoires");
    if (!list) return h("div", { class: "empty" }, icon("i-flag"), "Chargement…");
    return h("div", { class: "crew-list" },
        list.length ? list.map((t) => h("div", { class: "crew-line" },
            h("span", { class: "who" }, h("b", null, t.label), h("span", null, `Influence ${Math.floor(t.influence)} · en tête ${Math.floor(t.leader)} · seuil ${t.minInfluence}`)),
            t.owned ? h("span", { class: `badge ${t.contested ? "warn" : "ok"}` }, t.contested ? "Tenue · contestée" : "Tenue")
                : h("span", { class: "badge muted" }, t.owner ? `Tenue par ${t.owner}` : "Libre")))
            : h("p", { class: "hint-line" }, "Aucune influence pour l'instant : elle se gagne en vendant de la drogue dans les zones."),
        reset);
}

// ---------- 4. Membres, rangs, actions ----------

function crewMembersColumn(c) {
    const tabs = h("div", { class: "segmented block" }, segmentedButtons([
        { value: "members", label: `Membres (${c.members.length})` }, { value: "ranks", label: `Rangs (${c.ranks.length})` },
    ], crewState.sideTab, (v) => { crewState.sideTab = v; paintCrews(); }));

    const body = crewState.sideTab === "ranks" ? crewRanksList(c) : crewMemberList(c);
    return h("section", { class: "crew-col" },
        h("div", { class: "crew-col-head" }, icon("i-users"), "Membres", h("span", { class: "cnt" }, String(c.members.length))),
        h("div", { class: "crew-col-pad" }, tabs),
        h("div", { class: "crew-scroll crew-col-body" }, body),
        crewState.sideTab === "members" ? crewAddMember(c) : null,
        h("div", { class: "crew-actions" },
            h("button", { class: "btn small", onclick: () => crewAct("crews.join", { id: c.id }, `Vous rejoignez ${c.label}.`) }, icon("i-user-plus"), "Rejoindre"),
            h("button", { class: "btn small warn", onclick: () => wipeCrew(c) }, icon("i-undo"), "Wipe"),
            h("button", { class: "btn small danger", onclick: () => deleteCrew(c) }, icon("i-trash"), "Supprimer")));
}

function crewMemberList(c) {
    const search = h("input", { placeholder: "Rechercher un membre…", value: crewState.memberSearch });
    search.addEventListener("input", () => {
        crewState.memberSearch = search.value;
        const pos = search.selectionStart;
        paintCrews();
        const again = $("view-crews").querySelector(".crew-member-search input");
        if (again) { again.focus(); again.setSelectionRange(pos, pos); }
    });
    const q = fold(crewState.memberSearch.trim());
    const list = c.members.filter((m) => !q || fold(m.name).includes(q));
    loadMugshots(c.members.map((m) => m.identifier)).then((found) => found && paintCrews());

    const rows = list.map((m) => {
        const open = crewState.openMember === m.identifier;
        const row = h("button", { class: `crew-member${open ? " open" : ""}`, onclick: () => { crewState.openMember = open ? null : m.identifier; paintCrews(); } },
            mugshotImg(m.identifier, "mug-row"),
            h("span", { class: "who" }, h("b", null, m.name), h("span", null, `${m.rankLabel}${m.rank === c.topRank ? " · Chef" : ""}`)),
            h("span", { class: `status${m.online ? " on" : ""}`, title: m.online ? `En ligne · ID ${m.online}` : "Hors ligne" }));
        if (!open) return row;
        const select = h("select", { class: "input" }, [...c.ranks].reverse().map((r) => h("option", { value: String(r.rank), selected: r.rank === m.rank }, r.label)));
        select.addEventListener("change", async () => {
            const res = await crewAct("crews.setMember", { id: c.id, identifier: m.identifier, rank: Number(select.value) }, `${m.name} : rang modifié.`);
            if (!res) select.value = String(m.rank);
        });
        return h("div", { class: "crew-member-box" }, row,
            h("div", { class: "crew-member-edit" }, select,
                h("button", { class: "btn small ghost", onclick: async () => {
                    if (await confirmBox(`Retirer ${m.name} du crew ?`, "Il quitte le crew immédiatement.", "Retirer", true)) crewAct("crews.setMember", { id: c.id, identifier: m.identifier, remove: true }, `${m.name} a quitté le crew.`);
                } }, icon("i-door"), "Retirer")),
            h("span", { class: "hint-line" }, `${m.online ? `En ligne · ID ${m.online}` : "Hors ligne"} · depuis le ${new Date(m.joined * 1000).toLocaleDateString("fr-FR")}`));
    });

    return h("div", { class: "crew-list" },
        h("label", { class: "search crew-member-search" }, icon("i-search"), search),
        rows.length ? rows : h("p", { class: "hint-line" }, c.members.length ? "Aucun membre ne correspond." : "Aucun membre : ajoutez-en par leur ID en jeu."));
}

function crewAddMember(c) {
    const input = h("input", { class: "input", maxlength: "60", placeholder: "Ajouter (ID en jeu ou nom RP)" });
    const add = async (payload) => {
        const res = await act("crews.addMember", { id: c.id, ...payload }, null);
        if (!res) return;
        if (res.candidates) {
            crewState.candidates = res.candidates;
            return paintCrews();
        }
        crewState.candidates = null;
        toast(`${res.name || "Le joueur"} rejoint ${c.label}.`, "ok");
        loadCrews();
        loadCrewInfo();
    };
    input.addEventListener("keydown", (e) => { if (e.key === "Enter" && input.value.trim()) add({ query: input.value.trim() }); });
    return h("div", { class: "crew-add" },
        crewState.candidates ? h("div", { class: "crew-candidates" }, crewState.candidates.map((cand) => h("button", { class: "crew-line", onclick: () => add({ identifier: cand.identifier }) },
            h("span", { class: "who" }, h("b", null, cand.name), h("span", null, cand.job)), icon("i-plus")))) : null,
        h("div", { class: "spawn-row" }, input, h("button", { class: "btn small primary", onclick: () => input.value.trim() && add({ query: input.value.trim() }) }, icon("i-plus"))));
}

function crewRanksList(c) {
    const rows = [...c.ranks].reverse().map((r) => {
        const input = h("input", { class: "input", maxlength: "40", value: r.label });
        const save = h("button", { class: "btn small", disabled: true, title: "Renommer" }, icon("i-save"));
        input.addEventListener("input", () => { save.disabled = input.value.trim() === r.label || !input.value.trim(); });
        save.addEventListener("click", () => crewAct("crews.rank", { id: c.id, operation: "rename", rank: r.rank, label: input.value.trim() }, "Rang renommé."));
        const count = c.members.filter((m) => m.rank === r.rank).length;
        return h("div", { class: "crew-rank" }, h("span", { class: "eco-rank mono" }, String(r.rank)), input, save,
            h("span", { class: "hint-line" }, `${count} membre${count > 1 ? "s" : ""}${r.rank === c.topRank ? " · rang du chef" : ""}`));
    });
    const newRank = h("input", { class: "input", maxlength: "40", placeholder: "Nouveau rang (au-dessus)" });
    return h("div", { class: "crew-list" },
        rows,
        h("div", { class: "spawn-row" }, newRank,
            h("button", { class: "btn small", onclick: () => newRank.value.trim() && crewAct("crews.rank", { id: c.id, operation: "add", label: newRank.value.trim() }, "Rang ajouté.") }, icon("i-plus"))),
        h("button", { class: "btn small ghost", disabled: c.ranks.length <= 1, onclick: () => crewAct("crews.rank", { id: c.id, operation: "remove" }, "Rang le plus haut retiré.") }, icon("i-trash"), "Retirer le rang le plus haut"),
        h("p", { class: "hint-line" }, "Le rang le plus haut est celui du chef : il gère les membres en jeu depuis la tablette."));
}

async function wipeCrew(c) {
    const withMembers = h("input", { type: "checkbox" });
    const yes = await new Promise((resolve) => {
        openModal((close) => [
            h("header", null, h("h3", null, `Wipe de ${c.label} ?`), h("p", null, "XP remise à 0, influence effacée dans toutes les zones, coffres vidés. Action définitive.")),
            h("div", { class: "body" }, h("label", { class: "check-row" }, withMembers, "Retirer aussi tous les membres")),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => { close(false); resolve(false); } }, "Annuler"),
                h("button", { class: "btn danger", onclick: () => { resolve(true); close(false); } }, icon("i-undo"), "Wipe")),
        ]);
    });
    if (!yes) return;
    crewAct("crews.wipe", { id: c.id, members: withMembers.checked }, "Crew remis à zéro.");
}

function openCreateCrew(typeId) {
    const label = h("input", { class: "input", maxlength: "60", placeholder: "Ex. Ballas" });
    const slug = h("input", { class: "input mono", maxlength: "30", placeholder: "ballas" });
    const type = h("select", { class: "input" }, crewState.types.map((t) => h("option", { value: t.id, selected: t.id === typeId }, t.label)));
    let touched = false;
    label.addEventListener("input", () => { if (!touched) slug.value = poleSlug(label.value); });
    slug.addEventListener("input", () => { touched = true; });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-plus"), "Créer");
        submit.addEventListener("click", async () => {
            const res = await act("crews.create", { label: label.value.trim(), slug: slug.value.trim(), type: type.value }, "Crew créé.");
            if (!res) return;
            close();
            await loadCrews();
            selectCrew(res.id);
        });
        return [
            h("header", null, h("h3", null, "Nouveau crew"), h("p", null, "Rangs créés par défaut, modifiables ensuite. Disponible en jeu tout de suite.")),
            h("div", { class: "body event-form" },
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Nom"), label),
                    h("div", { class: "field" }, h("label", null, "Clé interne"), slug)),
                h("div", { class: "field" }, h("label", null, "Type"), type)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    label.focus();
}

async function deleteCrew(c) {
    const yes = await confirmBox(`Supprimer « ${c.label} » ?`, `Le crew, ses rangs et ses ${c.members.length} membre(s) sont effacés. Action définitive.`, "Supprimer", true);
    if (!yes) return;
    const res = await act("crews.delete", { id: c.id }, "Crew supprimé.");
    if (!res) return;
    untrackUnsaved("crews");
    Object.assign(crewState, { selected: null, info: null, draft: null });
    loadCrews();
}

// ---------- Demandes de crew ----------

function crewRequestsColumn() {
    const r = crewState.requests;
    if (!r) return h("div", { class: "crew-empty" }, h("div", { class: "empty" }, icon("i-user-plus"), "Chargement des demandes…"));
    const answer = async (req, accept) => {
        if (!accept && !(await confirmBox(`Refuser la demande de ${req.name} ?`, "Le joueur est prévenu s'il est connecté.", "Refuser", true))) return;
        const res = await act("crews.handleRequest", { id: req.id, accept }, accept ? "Demande acceptée." : "Demande refusée.");
        if (!res) return;
        loadCrewRequests();
        loadCrews();
    };
    const what = (req) => (req.kind === "join" ? `Rejoindre ${req.label}` : `Créer « ${req.label} » (${req.typeLabel})`);
    return h("section", { class: "crew-col crew-requests" },
        h("div", { class: "crew-col-head" }, icon("i-user-plus"), "Demandes de crew", h("span", { class: "cnt" }, String(r.pending.length))),
        h("div", { class: "crew-scroll crew-col-body" },
            r.pending.length ? r.pending.map((req) => h("div", { class: "crew-request" },
                h("div", { class: "crew-request-head" }, h("b", null, req.name), h("span", { class: `badge ${req.kind === "join" ? "ok" : "warn"}` }, what(req)), h("span", { class: "muted" }, ago(req.createdAt))),
                req.message ? h("p", { class: "crew-request-text" }, req.message) : null,
                req.member ? h("p", { class: "hint-line warn-text" }, `Fait déjà partie de ${req.member} : refusez la demande.`) : null,
                h("div", { class: "btn-row" },
                    h("button", { class: "btn small primary", disabled: !!req.member, onclick: () => answer(req, true) }, icon("i-save"), req.kind === "join" ? "Accepter" : "Créer le crew"),
                    h("button", { class: "btn small ghost", onclick: () => answer(req, false) }, icon("i-x"), "Refuser"))))
                : h("p", { class: "hint-line" }, "Aucune demande en attente. Les joueurs font une demande en jeu avec la commande /crew."),
            r.handled.length ? h("div", { class: "crew-sub" }, "Traitées récemment") : null,
            r.handled.map((req) => h("div", { class: "crew-line" },
                h("span", { class: "who" }, h("b", null, req.name), h("span", null, `${what(req)} · par ${req.handledBy || "?"} ${req.handledAt ? ago(req.handledAt) : ""}`)),
                h("span", { class: `badge ${req.status === "accepted" ? "ok" : "muted"}` }, req.status === "accepted" ? "Acceptée" : "Refusée")))));
}

// ---------- Infrastructure : positions et propriétés (planques) ----------

const CREW_POINT_KINDS = {
    storage: { label: "Stockage", hint: "Coffre commun du crew : même contenu sur tous ses points.", add: "Ajouter un stockage" },
    stash: { label: "Stockage séparé", hint: "Chaque point a son propre coffre.", add: "Ajouter un stockage séparé" },
    garage: { label: "Garage", hint: "Bientôt : utilisable avec le système de garages.", add: "Ajouter un garage", soon: true },
};

async function loadCrewPoints() {
    const id = crewState.selected;
    const res = await nui("action", { action: "crews.points", payload: { id } }).catch(() => null);
    if (id !== crewState.selected) return;
    crewState.points = res && res.ok ? res.points : [];
    crewState.interiors = res && res.ok ? res.interiors : [];
    paintCrews();
}

async function crewPointAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) loadCrewPoints();
    return res;
}

// Carte d'un point : nom modifiable, coordonnées, Définir (ma position), TP, supprimer
function crewPointCard(point, extra) {
    const label = h("input", { class: "input", maxlength: "60", value: point.label });
    const interior = point.kind === "property"
        ? h("select", { class: "input" }, (crewState.interiors || []).map((i) => h("option", { value: i.id, selected: i.id === point.interior }, i.label)))
        : null;
    const save = () => {
        const changed = label.value.trim() && (label.value.trim() !== point.label || (interior && interior.value !== point.interior));
        if (changed) crewPointAct("crews.pointSave", { pointId: point.id, label: label.value.trim(), interior: interior ? interior.value : "" }, "Point enregistré.");
    };
    label.addEventListener("change", save);
    if (interior) interior.addEventListener("change", save);
    return h("div", { class: "crew-point" },
        h("div", { class: "crew-point-head" }, h("span", { class: "crew-point-dot" }), label,
            h("button", { class: "btn small ghost sq-btn", title: "Supprimer", onclick: async () => {
                if (await confirmBox(`Supprimer « ${point.label} » ?`, point.kind === "garage" ? "Le point disparaît." : "Le point disparaît. Le contenu de son coffre reste en base.", "Supprimer", true)) {
                    crewPointAct("crews.pointDelete", { pointId: point.id }, "Point supprimé.");
                }
            } }, icon("i-trash"))),
        interior ? h("div", { class: "crew-point-row" }, h("span", { class: "muted" }, "Intérieur"), interior) : null,
        h("div", { class: "crew-point-row" },
            h("span", { class: "crew-coords mono" }, `${point.x.toFixed(0)}  ${point.y.toFixed(0)}  ${point.z.toFixed(0)}`),
            h("button", { class: "btn small ghost", title: "Le point passe à votre position", onclick: () => crewPointAct("crews.pointMove", { pointId: point.id }, "Point déplacé à votre position.") }, icon("i-crosshair"), "Définir"),
            h("button", { class: "btn small ghost", onclick: () => act("crews.pointTp", { pointId: point.id }, null) }, icon("i-goto"), "Téléporter")),
        extra || null);
}

function crewInfraTab(c, tab) {
    if (!crewState.points || crewState.pointsCrew !== c.id) {
        if (crewState.pointsCrew !== c.id) {
            crewState.pointsCrew = c.id;
            crewState.points = null;
            loadCrewPoints();
        }
        return h("div", { class: "empty" }, icon("i-pin"), "Chargement…");
    }
    const add = (kind, interior) => {
        crewState.openGroups.add(kind); // le groupe s'ouvre pour montrer le nouveau point
        return crewPointAct("crews.pointAdd", { id: c.id, kind, interior }, "Point ajouté à votre position.");
    };

    if (tab === "properties") {
        const list = crewState.points.filter((p) => p.kind === "property");
        return h("div", { class: "crew-list" },
            list.length ? list.map((p) => crewPointCard(p)) : h("p", { class: "hint-line" }, "Aucune propriété. Une planque : une porte (à votre position), un intérieur isolé où seuls les membres entrent, avec un coffre."),
            h("button", { class: "btn small ok-btn wide", onclick: () => add("property", (crewState.interiors[0] || {}).id) }, icon("i-plus"), "Ajouter une propriété"),
            h("p", { class: "hint-line" }, "La porte est placée là où vous êtes en jeu : regardez vers l'extérieur en la plaçant."));
    }

    // Groupes repliables (fermés par défaut) : un clic sur le titre ouvre ou ferme
    return h("div", { class: "crew-list" }, Object.entries(CREW_POINT_KINDS).map(([kind, meta]) => {
        const list = crewState.points.filter((p) => p.kind === kind);
        const open = crewState.openGroups.has(kind);
        const toggle = () => {
            if (open) crewState.openGroups.delete(kind);
            else crewState.openGroups.add(kind);
            paintCrews();
        };
        return h("div", { class: `crew-point-group${open ? " open" : ""}` },
            h("button", { class: "crew-point-title", onclick: toggle },
                h("span", null, meta.label), meta.soon ? h("span", { class: "badge muted" }, "bientôt") : null,
                h("span", { class: "cnt" }, String(list.length)), h("span", { class: "crew-chevron" }, "▸")),
            open ? [
                ...list.map((p) => crewPointCard(p)),
                h("button", { class: "btn small ok-btn wide", onclick: () => add(kind) }, icon("i-plus"), meta.add),
                h("p", { class: "hint-line" }, meta.hint),
            ] : null);
    }));
}
