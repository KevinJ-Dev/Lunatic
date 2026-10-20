"use strict";

// ====================================================================
//  lunatic_admin — Illégal, étape 1 : tuile Crews
//  Liste des crews, création, fiche (identité, rangs, membres, progression).
// ====================================================================

const crewState = { dom: null, list: null, types: [], filter: "", selected: null, info: null, tab: "identity", candidates: null, loadedAt: 0 };

function renderCrews() {
    const root = $("view-crews");

    if (!crewState.dom || !root.contains(crewState.dom.list)) {
        const search = h("input", { placeholder: "Rechercher un crew", value: crewState.filter });
        search.addEventListener("input", () => { crewState.filter = search.value; paintCrewList(); });
        crewState.dom = { count: h("span", { class: "muted mono" }), list: h("div", { class: "side-scroll" }), fiche: h("div", { class: "content" }) };
        root.replaceChildren(
            h("aside", { class: "sidebar" },
                h("div", { class: "side-head" }, h("h3", null, "Crews"), crewState.dom.count),
                h("div", { class: "side-search" }, h("label", { class: "search" }, icon("i-search"), search)),
                crewState.dom.list,
                h("div", { class: "side-foot" }, h("button", { class: "btn primary", style: "width:100%", onclick: openCreateCrew }, icon("i-plus"), "Créer un crew"))
            ),
            crewState.dom.fiche
        );
        paintCrewList();
        paintCrewFiche();
    }

    if (Date.now() - crewState.loadedAt > 10000) loadCrews();
}

async function loadCrews() {
    crewState.loadedAt = Date.now();
    const res = await nui("action", { action: "crews.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    crewState.list = res.crews || [];
    crewState.types = res.types || [];
    if (crewState.dom) paintCrewList();
}

function crewProblems(entry) {
    const problems = [];
    if (!entry.members) problems.push("aucun membre");
    else if (!entry.leader) problems.push("aucun chef (membre au rang le plus haut)");
    return problems;
}

function paintCrewList() {
    if (!crewState.dom) return;
    if (!crewState.list) return crewState.dom.list.replaceChildren(h("div", { class: "muted side-empty" }, "Chargement…"));
    const text = crewState.filter.trim().toLowerCase();
    const rows = crewState.list.filter((c) => !text || c.label.toLowerCase().includes(text) || c.typeLabel.toLowerCase().includes(text));
    crewState.dom.count.textContent = String(crewState.list.length);
    crewState.dom.list.replaceChildren(...(rows.length ? rows.map((c) => {
        const dotEl = h("span", { class: "struct-dot" });
        dotEl.style.background = c.color;
        return h("button", { class: `list-row player-row${c.id === crewState.selected ? " active" : ""}`, onclick: () => selectCrew(c.id) },
            dotEl, readyDot(crewProblems(c)),
            h("span", { class: "who" }, h("b", null, c.label), h("span", null, `${c.typeLabel} · level ${c.level} · ${c.members} membre${c.members > 1 ? "s" : ""}`)));
    }) : [h("div", { class: "muted side-empty" }, crewState.list.length ? "Aucun résultat." : "Aucun crew pour l'instant.")]));
}

function selectCrew(id) {
    if (crewState.selected === id) return;
    guardUnsaved("crews", () => doSelectCrew(id));
}

function doSelectCrew(id) {
    untrackUnsaved("crews");
    crewState.selected = id;
    crewState.info = null;
    crewState.candidates = null;
    paintCrewList();
    paintCrewFiche();
    loadCrewInfo();
}

async function loadCrewInfo() {
    const id = crewState.selected;
    if (!id) return;
    const res = await nui("action", { action: "crews.info", payload: { id } }).catch(() => null);
    if (id !== crewState.selected) return;
    crewState.info = res && res.ok ? res.crew : false;
    if (crewState.info) rememberRecent({ type: "crew", id, label: crewState.info.label, sub: crewState.info.typeLabel });
    if (res && res.types) crewState.types = res.types;
    paintCrewFiche();
}

async function crewAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) {
        loadCrews();
        loadCrewInfo();
    }
    return res;
}

function paintCrewFiche() {
    if (!crewState.dom) return;
    const fiche = crewState.dom.fiche;
    if (!crewState.selected) return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-flag"), "Choisissez un crew ou créez-en un."));
    if (crewState.info === false) return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-flag"), "Ce crew n'existe plus."));
    if (!crewState.info) return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-flag"), "Chargement du crew…"));

    const c = crewState.info;
    const previous = fiche.querySelector(".scroll");
    const keepScroll = previous && fiche.dataset.crew === String(c.id) ? previous.scrollTop : 0;
    fiche.dataset.crew = String(c.id);
    const logo = c.logo ? h("img", { class: "struct-logo", src: c.logo, alt: "" }) : null;
    if (logo) logo.addEventListener("error", () => logo.remove());

    const tabs = h("div", { class: "segmented" }, segmentedButtons([
        { value: "identity", label: "Identité" }, { value: "ranks", label: `Rangs (${c.ranks.length})` },
        { value: "members", label: `Membres (${c.members.length})` }, { value: "progress", label: "Progression" },
    ], crewState.tab, (v) => guardUnsaved("crews", () => { crewState.tab = v; paintCrewFiche(); })));

    let body;
    if (crewState.tab === "ranks") body = crewRanksCard(c);
    else if (crewState.tab === "members") body = crewMembersCard(c);
    else if (crewState.tab === "progress") body = crewProgressCard(c);
    else body = crewIdentityCard(c);
    if (crewState.tab !== "identity") untrackUnsaved("crews");

    fiche.replaceChildren(
        h("div", { class: "page-head" }, logo,
            h("div", { class: "grow" },
                h("h1", { class: "page-title" }, c.label, h("span", { class: "badge muted" }, c.typeLabel), h("span", { class: "badge jail" }, `Level ${c.level}`),
                    (() => { const entry = (crewState.list || []).find((x) => x.id === c.id); return entry ? readyBadge(crewProblems(entry)) : null; })()),
                h("div", { class: "page-sub" }, h("span", { class: "mono" }, c.slug), h("span", { class: "sep" }), `${c.members.length} membre${c.members.length > 1 ? "s" : ""}`,
                    h("span", { class: "sep" }), `${c.members.filter((m) => m.online).length} en ligne`)),
            h("button", { class: "btn danger", onclick: () => deleteCrew(c) }, icon("i-trash"), "Supprimer")),
        h("div", { class: "struct-tabs" }, tabs),
        h("div", { class: "scroll" }, body)
    );

    const scroller = fiche.querySelector(".scroll");
    if (scroller) scroller.scrollTop = keepScroll;
}

function crewIdentityCard(c) {
    const label = h("input", { class: "input", maxlength: "60", value: c.label });
    const type = h("select", { class: "input" }, crewState.types.map((t) => h("option", { value: t.id, selected: t.id === c.type }, t.label)));
    const color = h("input", { class: "input color-input", type: "color", value: c.color });
    const logo = h("input", { class: "input mono", maxlength: "255", placeholder: "https://…/logo.png", value: c.logo || "" });
    const save = h("button", { class: "btn primary" }, icon("i-save"), "Enregistrer");
    save.addEventListener("click", () => crewAct("crews.save", { id: c.id, label: label.value.trim(), type: type.value, color: color.value, logo: logo.value.trim() }, "Crew enregistré."));
    const values = () => JSON.stringify([label.value, type.value, color.value, logo.value]);
    const saved = values();
    trackUnsaved("crews", { label: `Crew ${c.label}`, isDirty: () => document.body.contains(save) && values() !== saved, save: () => save.click(), reset: () => paintCrewFiche() });

    return h("div", null,
        h("div", { class: "card" },
            h("h3", { class: "card-title" }, "Identité du crew"),
            h("div", { class: "struct-fields" },
                h("div", { class: "field" }, h("label", null, "Nom"), label),
                h("div", { class: "field" }, h("label", null, "Type"), type),
                h("div", { class: "field" }, h("label", null, "Couleur"), color),
                h("div", { class: "field struct-wide" }, h("label", null, "Logo (URL)"), logo, urlPreview(logo, "struct-logo-preview"))),
            h("div", { class: "btn-row", style: "margin-top:16px" }, save)),
        h("p", { class: "hint-line" }, `Créé par ${c.createdBy || "?"}${c.createdAt ? ` le ${new Date(c.createdAt * 1000).toLocaleDateString("fr-FR")}` : ""}. Le type décide des recettes, laboratoires et commandes accessibles (étapes suivantes de l'illégal).`)
    );
}

function crewRanksCard(c) {
    const rows = [...c.ranks].reverse().map((r) => {
        const input = h("input", { class: "input", maxlength: "40", value: r.label });
        const save = h("button", { class: "btn small", disabled: true }, icon("i-save"), "Renommer");
        input.addEventListener("input", () => { save.disabled = input.value.trim() === r.label || !input.value.trim(); });
        save.addEventListener("click", () => crewAct("crews.rank", { id: c.id, operation: "rename", rank: r.rank, label: input.value.trim() }, "Rang renommé."));
        const count = c.members.filter((m) => m.rank === r.rank).length;
        return h("div", { class: "row grade-row" },
            h("span", { class: "pid mono" }, String(r.rank)),
            input,
            h("span", { class: "muted" }, `${count} membre${count > 1 ? "s" : ""}${r.rank === c.topRank ? " · Chef" : ""}`),
            h("span"),
            save);
    });
    const newRank = h("input", { class: "input", maxlength: "40", placeholder: "Nouveau rang (au-dessus des autres)" });

    return h("div", { class: "card" },
        h("h3", { class: "card-title" }, "Rangs, du plus haut au plus bas"),
        h("p", { class: "hint-line", style: "margin:0 0 12px" }, "Le rang le plus haut est celui du chef : il gère les membres en jeu (/crew)."),
        h("div", { class: "table" }, rows),
        h("div", { class: "spawn-row", style: "margin-top:12px" }, newRank,
            h("button", { class: "btn", onclick: () => newRank.value.trim() && crewAct("crews.rank", { id: c.id, operation: "add", label: newRank.value.trim() }, "Rang ajouté.") }, icon("i-plus"), "Ajouter"),
            h("button", { class: "btn ghost", disabled: c.ranks.length <= 1, onclick: () => crewAct("crews.rank", { id: c.id, operation: "remove" }, "Rang le plus haut retiré.") }, icon("i-trash"), "Retirer le plus haut"))
    );
}

function crewMembersCard(c) {
    const input = h("input", { class: "input", maxlength: "60", placeholder: "ID en jeu (ex. 12) ou nom RP (ex. Jean Dupont)" });
    const add = async (payload) => {
        const res = await act("crews.addMember", { id: c.id, ...payload }, null);
        if (!res) return;
        if (res.candidates) {
            crewState.candidates = res.candidates;
            return paintCrewFiche();
        }
        crewState.candidates = null;
        toast(`${res.name || "Le joueur"} rejoint ${c.label}.`, "ok");
        loadCrews();
        loadCrewInfo();
    };
    input.addEventListener("keydown", (e) => { if (e.key === "Enter" && input.value.trim()) add({ query: input.value.trim() }); });

    const rows = c.members.map((m) => {
        const select = h("select", { class: "input" }, [...c.ranks].reverse().map((r) => h("option", { value: String(r.rank), selected: r.rank === m.rank }, r.label)));
        select.addEventListener("change", async () => {
            const res = await crewAct("crews.setMember", { id: c.id, identifier: m.identifier, rank: Number(select.value) }, `${m.name} : rang modifié.`);
            if (!res) select.value = String(m.rank);
        });
        return h("div", { class: "row member-job-row" },
            h("span", { class: `status${m.online ? " on" : ""}`, title: m.online ? "En ligne" : "Hors ligne" }),
            h("div", { class: "who" }, h("b", null, m.name), h("span", null, `${m.online ? `ID ${m.online}` : "Hors ligne"} · perso ${m.identifier.slice(0, 8)}… · depuis le ${new Date(m.joined * 1000).toLocaleDateString("fr-FR")}`)),
            select,
            h("button", { class: "btn small ghost", onclick: async () => {
                const yes = await confirmBox(`Retirer ${m.name} du crew ?`, "Il quitte le crew immédiatement.", "Retirer", true);
                if (yes) crewAct("crews.setMember", { id: c.id, identifier: m.identifier, remove: true }, `${m.name} a quitté le crew.`);
            } }, icon("i-door"), "Retirer"));
    });

    return h("div", null,
        h("div", { class: "card" },
            h("h3", { class: "card-title" }, "Ajouter un membre"),
            h("div", { class: "spawn-row" }, input, h("button", { class: "btn primary", onclick: () => input.value.trim() && add({ query: input.value.trim() }) }, icon("i-user-plus"), "Ajouter")),
            h("p", { class: "hint-line" }, "Il entre au rang le plus bas. Un personnage déjà dans un autre crew le quitte."),
            crewState.candidates ? h("div", { class: "table", style: "margin-top:12px" }, crewState.candidates.map((cand) => h("div", { class: "row candidate-row" },
                h("div", { class: "who" }, h("b", null, cand.name), h("span", null, `${cand.job} · perso ${cand.identifier.slice(0, 8)}…`)),
                h("button", { class: "btn small", onclick: () => add({ identifier: cand.identifier }) }, icon("i-plus"), "Ajouter")))) : null),
        h("div", { class: "card", style: "margin-top:16px" },
            h("h3", { class: "card-title" }, `Membres (${c.members.length})`),
            rows.length ? h("div", { class: "table" }, rows) : h("p", { class: "hint-line", style: "margin:0" }, "Aucun membre."))
    );
}

function crewProgressCard(c) {
    const amount = h("input", { class: "input mono", type: "number", placeholder: "ex. 500 ou -200" });
    const pct = c.nextLevelXp ? Math.min(100, Math.round((c.xp / c.nextLevelXp) * 100)) : 100;
    return h("div", null,
        h("div", { class: "kpis", style: "margin-top:0" },
            h("div", { class: "kpi" }, h("span", null, "Level"), h("b", null, String(c.level)), h("small", null, c.nextLevelXp ? `prochain level à ${c.nextLevelXp} XP` : "level maximum")),
            h("div", { class: "kpi" }, h("span", null, "Expérience"), h("b", null, `${c.xp} XP`), h("small", null, `${pct} % vers le level suivant`)),
            h("div", { class: "kpi" }, h("span", null, "Influence"), h("b", null, "—"), h("small", null, "arrive avec les territoires"))),
        h("div", { class: "card", style: "margin-top:16px" },
            h("h3", { class: "card-title" }, "Ajuster l'XP"),
            h("div", { class: "spawn-row" }, amount,
                h("button", { class: "btn primary", onclick: () => Number(amount.value) && crewAct("crews.xp", { id: c.id, amount: Math.trunc(Number(amount.value)) }, "XP mise à jour.") }, icon("i-save"), "Appliquer")),
            h("p", { class: "hint-line" }, "Positif pour ajouter, négatif pour retirer. En jeu, l'XP viendra des ventes de drogue et des missions."))
    );
}

function openCreateCrew() {
    const label = h("input", { class: "input", maxlength: "60", placeholder: "Ex. Ballas" });
    const slug = h("input", { class: "input mono", maxlength: "30", placeholder: "ballas" });
    const type = h("select", { class: "input" }, crewState.types.map((t) => h("option", { value: t.id }, t.label)));
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
            h("header", null, h("h3", null, "Nouveau crew"), h("p", null, "Rangs créés par défaut, modifiables ensuite.")),
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
    crewState.selected = null;
    crewState.info = null;
    loadCrews();
    paintCrewFiche();
}
