"use strict";

// ====================================================================
//  lunatic_admin — lot E1 : tuiles Entreprises et Services publics
//  Une même page pour les deux : liste, création, fiche (identité, grades, membres).
//  Grades et membres réutilisent les cartes du Pôle emploi (web/poles.js).
// ====================================================================

const STRUCTURE_KINDS = {
    company: { view: "companies", title: "Entreprises", one: "entreprise", create: "Créer une entreprise", icon: "i-store" },
    public: { view: "publics", title: "Services publics", one: "service public", create: "Créer un service public", icon: "i-shield" },
};

// Grades proposés à la création selon le type (modifiables avant de valider)
const DEFAULT_GRADES = {
    police: [["Cadet", 400], ["Officier", 600], ["Sergent", 800], ["Lieutenant", 1000], ["Capitaine", 1200]],
    medic: [["Stagiaire", 400], ["Ambulancier", 600], ["Médecin", 800], ["Chef de service", 1000]],
    administration: [["Agent", 400], ["Responsable", 700], ["Directeur", 1000]],
    government: [["Conseiller", 500], ["Ministre", 900], ["Gouverneur", 1200]],
    default: [["Recrue", 200], ["Employé", 300], ["Gérant", 400], ["Patron", 500]],
};

const structState = {};

function structOf(kind) {
    if (!structState[kind]) {
        structState[kind] = { dom: null, list: null, orphans: [], types: [], filter: "", selected: null, info: null, tab: "identity", loadedAt: 0, candidates: null };
    }
    return structState[kind];
}

const NEW_STRUCTURE = "__new";

function renderStructures(kind) {
    const st = structOf(kind);
    const meta = STRUCTURE_KINDS[kind];
    const root = $(`view-${meta.view}`);

    if (!st.dom || !root.contains(st.dom.list)) {
        const search = h("input", { placeholder: `Rechercher un${kind === "public" ? "" : "e"} ${meta.one}`, value: st.filter });
        search.addEventListener("input", () => { st.filter = search.value; paintStructureList(kind); });
        st.dom = { count: h("span", { class: "muted mono" }), list: h("div", { class: "side-scroll" }), fiche: h("div", { class: "content" }) };
        root.replaceChildren(
            h("aside", { class: "sidebar" },
                h("div", { class: "side-head" }, h("h3", null, meta.title), st.dom.count),
                h("div", { class: "side-search" }, h("label", { class: "search" }, icon("i-search"), search)),
                st.dom.list,
                h("div", { class: "side-foot" }, h("button", { class: "btn primary", style: "width:100%", onclick: () => selectStructure(kind, NEW_STRUCTURE) }, icon("i-plus"), meta.create))
            ),
            st.dom.fiche
        );
        paintStructureList(kind);
        paintStructureFiche(kind);
    }

    if (Date.now() - st.loadedAt > 10000) loadStructures(kind);
}

async function loadStructures(kind) {
    const st = structOf(kind);
    st.loadedAt = Date.now();
    const res = await nui("action", { action: "structures.list", payload: { kind } }).catch(() => null);
    if (!res || !res.ok) return;
    st.list = res.structures || [];
    st.orphans = res.orphans || [];
    st.types = res.types || [];
    if (st.dom) paintStructureList(kind);
}

function paintStructureList(kind) {
    const st = structOf(kind);
    if (!st.dom) return;
    if (!st.list) return st.dom.list.replaceChildren(h("div", { class: "muted side-empty" }, "Chargement…"));

    const text = st.filter.trim().toLowerCase();
    const rows = st.list.filter((s) => !text || (s.label || "").toLowerCase().includes(text) || s.job.includes(text) || (s.typeLabel || "").toLowerCase().includes(text));
    st.dom.count.textContent = String(st.list.length);
    st.dom.list.replaceChildren(...(rows.length ? rows.map((s) => {
        const badge = h("span", { class: "struct-dot" });
        badge.style.background = s.color || "#9650ff";
        return h("button", { class: `list-row player-row${s.job === st.selected ? " active" : ""}`, onclick: () => selectStructure(kind, s.job) },
            kind === "company" ? badge : null,
            h("span", { class: "who" }, h("b", null, s.label || s.job),
                h("span", null, `${s.typeLabel} · ${s.online} en ligne · ${s.total} membre${s.total > 1 ? "s" : ""}`)));
    }) : [h("div", { class: "muted side-empty" }, st.list.length ? "Aucun résultat." : `Aucun${kind === "public" ? "" : "e"} ${STRUCTURE_KINDS[kind].one} pour l'instant.`)]));
}

function selectStructure(kind, job) {
    const st = structOf(kind);
    st.selected = job;
    st.info = null;
    st.candidates = null;
    paintStructureList(kind);
    paintStructureFiche(kind);
    if (job !== NEW_STRUCTURE) loadStructureInfo(kind);
}

async function loadStructureInfo(kind) {
    const st = structOf(kind);
    const job = st.selected;
    if (!job || job === NEW_STRUCTURE) return;
    const res = await nui("action", { action: "structures.info", payload: { job } }).catch(() => null);
    if (job !== st.selected) return;
    st.info = res && res.ok ? res.job : false;
    if (res && res.types) st.types = res.types;
    paintStructureFiche(kind);
}

// Action sur une structure : recharge la liste et la fiche après succès
function structureActor(kind) {
    return async (action, payload, okMessage) => {
        const res = await act(action, payload, okMessage);
        if (res) {
            loadStructures(kind);
            loadStructureInfo(kind);
        }
        return res;
    };
}

function paintStructureFiche(kind) {
    const st = structOf(kind);
    if (!st.dom) return;
    const fiche = st.dom.fiche;
    const meta = STRUCTURE_KINDS[kind];

    if (st.selected === NEW_STRUCTURE) return fiche.replaceChildren(...newStructureForm(kind));
    if (!st.selected) return fiche.replaceChildren(h("div", { class: "empty" }, icon(meta.icon), `Choisissez un${kind === "public" ? "" : "e"} ${meta.one} ou créez-en un${kind === "public" ? "" : "e"}.`));
    if (st.info === false) return fiche.replaceChildren(h("div", { class: "empty" }, icon(meta.icon), "Cette structure n'existe plus."));
    if (!st.info) return fiche.replaceChildren(h("div", { class: "empty" }, icon(meta.icon), "Chargement de la fiche…"));

    const info = st.info;
    const s = info.structure;
    const previous = fiche.querySelector(".scroll");
    const keepScroll = previous && fiche.dataset.structure === info.name ? previous.scrollTop : 0;
    fiche.dataset.structure = info.name;

    const total = info.grades.reduce((sum, g) => sum + g.members, 0);
    const online = info.members.filter((m) => m.online).length;
    const doAct = structureActor(kind);
    const logo = s.logo ? h("img", { class: "struct-logo", src: s.logo, alt: "" }) : null;
    if (logo) logo.addEventListener("error", () => logo.remove());

    const tabs = h("div", { class: "segmented" }, segmentedButtons([
        { value: "identity", label: "Identité" }, { value: "grades", label: `Grades (${info.grades.length})` }, { value: "members", label: `Membres (${total})` },
        { value: "points", label: `Points (${(info.points || []).length})` }, { value: "account", label: "Compte" },
    ], st.tab, (value) => { st.tab = value; paintStructureFiche(kind); }));

    let body;
    if (st.tab === "grades") body = gradesCard(info, doAct);
    else if (st.tab === "points") body = pointsCard(info, doAct);
    else if (st.tab === "account") body = accountCard(info, doAct);
    else if (st.tab === "members") body = h("div", null, addMemberCard(kind, info, doAct), membersCard(info, doAct, "Aucun membre : ajoutez-en un ci-dessus."));
    else body = identityCard(kind, info, doAct);

    fiche.replaceChildren(
        h("div", { class: "page-head" },
            logo,
            h("div", { class: "grow" },
                h("h1", { class: "page-title" }, info.label || info.name, h("span", { class: "badge muted" }, info.typeLabel)),
                h("div", { class: "page-sub" }, h("span", { class: "mono" }, info.name), h("span", { class: "sep" }), `${total} membre${total > 1 ? "s" : ""}`,
                    h("span", { class: "sep" }), `${online} en ligne`, kind === "public" && info.leadName ? [h("span", { class: "sep" }), `Lead : ${info.leadName}`] : null)
            ),
            h("button", { class: "btn danger", disabled: total > 0, title: total > 0 ? "Renvoyez d'abord tous les membres" : null, onclick: () => deleteStructure(kind, info) }, icon("i-trash"), "Supprimer")
        ),
        h("div", { class: "struct-tabs" }, tabs),
        h("div", { class: "scroll" }, body)
    );

    const scroller = fiche.querySelector(".scroll");
    if (scroller) scroller.scrollTop = keepScroll;
}

// ---------- Onglet Identité ----------

function urlPreview(input, className) {
    const img = h("img", { class: className, alt: "" });
    const paint = () => {
        const value = input.value.trim();
        img.style.display = /^https?:\/\//.test(value) ? "" : "none";
        if (/^https?:\/\//.test(value)) img.src = value;
    };
    img.addEventListener("error", () => { img.style.display = "none"; });
    input.addEventListener("input", paint);
    paint();
    return img;
}

function identityCard(kind, info, doAct) {
    const s = info.structure;
    const label = h("input", { class: "input", maxlength: "50", value: info.label || "" });
    const type = h("select", { class: "input" }, structOf(kind).types.map((t) => h("option", { value: t.id, selected: t.id === s.type }, t.label)));
    const logo = h("input", { class: "input mono", maxlength: "255", placeholder: "https://…/logo.png", value: s.logo || "" });
    const banner = h("input", { class: "input mono", maxlength: "255", placeholder: "https://…/banniere.png", value: s.banner || "" });
    const radial = h("input", { class: "input mono", maxlength: "60", placeholder: "fa-solid fa-utensils", value: s.radialIcon || "" });

    const fields = [
        h("div", { class: "field" }, h("label", null, "Nom (identifiant interne)"), h("input", { class: "input mono", value: info.name, disabled: true })),
        h("div", { class: "field" }, h("label", null, "Label (nom affiché aux joueurs)"), label),
        h("div", { class: "field" }, h("label", null, "Type"), type),
    ];

    let lead = null;
    let color = null;
    if (kind === "public") {
        const options = [h("option", { value: "" }, "— Aucun —")];
        const known = new Set();
        for (const m of info.members) {
            known.add(m.identifier);
            options.push(h("option", { value: m.identifier, selected: m.identifier === s.lead }, m.name));
        }
        if (s.lead && !known.has(s.lead)) options.push(h("option", { value: s.lead, selected: true }, `${info.leadName || s.lead} (n'est plus membre)`));
        lead = h("select", { class: "input" }, options);
        fields.push(h("div", { class: "field" }, h("label", null, "Lead (personnage responsable)"), lead));
    } else {
        color = h("input", { class: "input color-input", type: "color", value: s.color || "#9650ff" });
        fields.push(h("div", { class: "field" }, h("label", null, "Couleur (carte et menus)"), color));
    }

    const submit = h("button", { class: "btn primary" }, icon("i-save"), "Enregistrer la fiche");
    submit.addEventListener("click", () => doAct("structures.save", {
        job: info.name, label: label.value.trim(), type: type.value, lead: lead ? lead.value : null, color: color ? color.value : null,
        logo: logo.value.trim(), banner: banner.value.trim(), radialIcon: radial.value.trim(),
    }, "Fiche enregistrée."));

    return h("div", null,
        h("div", { class: "card" },
            h("h3", { class: "card-title" }, "Fiche d'identité"),
            h("div", { class: "struct-fields" }, fields),
            h("div", { class: "struct-fields", style: "margin-top:14px" },
                h("div", { class: "field" }, h("label", null, "Logo (URL)"), logo, urlPreview(logo, "struct-logo-preview")),
                h("div", { class: "field" }, h("label", null, "Icône du menu radial"), radial,
                    h("span", { class: "hint" }, "Nom d'icône Font Awesome, utilisée par le futur menu radial.")),
                h("div", { class: "field struct-wide" }, h("label", null, "Bannière (URL)"), banner, urlPreview(banner, "struct-banner-preview"))),
            h("div", { class: "btn-row", style: "margin-top:16px" }, submit)
        ),
        h("p", { class: "hint-line" }, `Créé${kind === "public" ? "" : "e"} par ${s.createdBy || "?"}${s.createdAt ? ` le ${new Date(s.createdAt * 1000).toLocaleDateString("fr-FR")}` : ""}.`)
    );
}

// ---------- Onglet Points ----------

function pointsCard(info, doAct) {
    const types = info.pointTypes || [];
    const typeLabel = (id) => (types.find((t) => t.id === id) || {}).label || id;
    const select = h("select", { class: "input" }, types.map((t) => h("option", { value: t.id }, t.ready ? t.label : `${t.label} (bientôt)`)));
    const label = h("input", { class: "input", maxlength: "60", placeholder: "Nom facultatif, ex. Coffre cuisine" });
    const add = h("button", { class: "btn primary" }, icon("i-plus"), "Ajouter à ma position");
    add.addEventListener("click", async () => {
        const res = await doAct("structures.addPoint", { job: info.name, type: select.value, label: label.value.trim() }, "Point ajouté à votre position.");
        if (res) label.value = "";
    });

    const rows = (info.points || []).map((p) => {
        const ready = (types.find((t) => t.id === p.type) || {}).ready;
        return h("div", { class: "row point-row" },
            h("span", { class: `status${ready ? " on" : ""}`, title: ready ? "Utilisable en jeu" : "Bientôt disponible en jeu" }),
            h("div", { class: "who" }, h("b", null, p.label), h("span", null, `${typeLabel(p.type)} · ${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}`)),
            h("div", { class: "btn-row" },
                h("button", { class: "btn small", title: "Placer le point à votre position et orientation actuelles", onclick: () => doAct("structures.movePoint", { id: p.id }, "Point replacé à votre position.") }, icon("i-crosshair"), "Définir"),
                h("button", { class: "btn small ghost", onclick: () => act("structures.tpPoint", { id: p.id }, null) }, icon("i-goto"), "TP"),
                h("button", { class: "btn small ghost", title: "Renommer", onclick: () => renamePoint(p, doAct) }, icon("i-edit")),
                h("button", { class: "btn small ghost", title: "Supprimer", onclick: async () => {
                    const yes = await confirmBox(`Supprimer « ${p.label} » ?`, p.type === "storage" ? "Le contenu du coffre reste en base, mais il n'est plus accessible." : "Le point disparaît pour tous les membres.", "Supprimer", true);
                    if (yes) doAct("structures.deletePoint", { id: p.id }, "Point supprimé.");
                } }, icon("i-trash")))
        );
    });

    return h("div", null,
        h("div", { class: "card" },
            h("h3", { class: "card-title" }, "Ajouter un point"),
            h("div", { class: "point-add" }, select, label, add),
            h("p", { class: "hint-line" }, "Le point est posé au sol, sous vos pieds. « Définir » le déplace à votre position, « TP » vous y emmène. Plusieurs points du même type sont possibles.")),
        h("div", { class: "card", style: "margin-top:16px" },
            h("h3", { class: "card-title" }, `Points (${rows.length})`),
            rows.length ? h("div", { class: "table" }, rows) : h("p", { class: "hint-line", style: "margin:0" }, "Aucun point pour l'instant."),
            h("p", { class: "hint-line" }, "Pastille verte : utilisable en jeu (Gestion, Stockage, Casier, Vestiaire, Sonnette, Custom). Les autres types sont déjà plaçables et s'activeront avec leur système."))
    );
}

function renamePoint(p, doAct) {
    const input = h("input", { class: "input", maxlength: "60", value: p.label });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Renommer");
        submit.addEventListener("click", async () => {
            const res = await doAct("structures.renamePoint", { id: p.id, label: input.value.trim() }, "Point renommé.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, "Renommer le point"), h("p", null, "Nom affiché aux membres avec [E]. Vide = nom du type.")),
            h("div", { class: "body" }, input),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    input.focus();
}

// ---------- Onglet Compte de société ----------

function accountCard(info, doAct) {
    const account = info.account;
    if (!account) {
        return h("div", { class: "card" }, h("div", { class: "empty small" }, icon("i-lock"), "La resource lunatic_business n'est pas démarrée : compte indisponible."));
    }

    let operation = "add";
    const seg = h("div", { class: "segmented" });
    const amount = h("input", { class: "input mono", type: "number", min: "1", placeholder: "Montant" });
    const reason = h("input", { class: "input", maxlength: "120", placeholder: "Motif (obligatoire)" });
    const paint = () => seg.replaceChildren(...segmentedButtons([{ value: "add", label: "Ajouter" }, { value: "remove", label: "Retirer" }], operation, (v) => { operation = v; paint(); }));
    paint();
    const submit = h("button", { class: "btn primary" }, icon("i-save"), "Valider");
    submit.addEventListener("click", () => {
        const value = Math.floor(Number(amount.value));
        if (!value || value < 1) return toast("Indiquez un montant.", "error");
        doAct("structures.account", { job: info.name, amount: operation === "add" ? value : -value, reason: reason.value.trim() }, "Compte mis à jour.");
    });

    const history = account.history || [];
    return h("div", null,
        h("div", { class: "kpis", style: "margin-top:0" }, h("div", { class: "kpi" }, h("span", null, "Solde du compte"), h("b", null, money(account.balance)), h("small", null, "Dépôts et retraits du patron au point Gestion"))),
        h("div", { class: "card", style: "margin-top:16px" },
            h("h3", { class: "card-title" }, "Opération staff"),
            h("div", { class: "account-form" }, seg, amount, reason, submit)),
        h("div", { class: "card", style: "margin-top:16px" },
            h("h3", { class: "card-title" }, "Historique (30 dernières opérations)"),
            history.length ? h("div", { class: "table" }, history.map((e) => h("div", { class: "row account-row" },
                h("b", { class: `mono ${e.amount > 0 ? "plus" : "minus"}` }, `${e.amount > 0 ? "+" : "−"}${money(Math.abs(e.amount))}`),
                h("div", { class: "who" }, h("b", null, e.reason || "—"), h("span", null, `${e.actor || "?"} · ${new Date(e.created * 1000).toLocaleString("fr-FR")}`)),
                h("span", { class: "muted mono" }, `solde ${money(e.balance)}`)))) : h("p", { class: "hint-line", style: "margin:0" }, "Aucune opération."))
    );
}

// ---------- Onglet Membres : ajout ----------

function addMemberCard(kind, info, doAct) {
    const st = structOf(kind);
    const input = h("input", { class: "input", maxlength: "60", placeholder: "ID en jeu (ex. 12) ou nom RP (ex. Jean Dupont)" });
    const add = async (payload) => {
        const res = await act("structures.addMember", { job: info.name, ...payload }, null);
        if (!res) return;
        if (res.candidates) {
            st.candidates = res.candidates;
            return paintStructureFiche(kind);
        }
        st.candidates = null;
        toast(`${res.name || "Le joueur"} rejoint ${info.label}.`, "ok");
        loadStructures(kind);
        loadStructureInfo(kind);
    };
    const submit = h("button", { class: "btn primary", onclick: () => input.value.trim() && add({ query: input.value.trim() }) }, icon("i-user-plus"), "Ajouter");
    input.addEventListener("keydown", (e) => { if (e.key === "Enter" && input.value.trim()) add({ query: input.value.trim() }); });

    return h("div", { class: "card" },
        h("h3", { class: "card-title" }, "Ajouter un membre"),
        h("div", { class: "spawn-row" }, input, submit),
        h("p", { class: "hint-line" }, "Il est embauché au grade le plus bas. Un joueur qui a déjà un métier le quitte."),
        st.candidates ? h("div", { class: "table", style: "margin-top:12px" }, st.candidates.map((c) =>
            h("div", { class: "row candidate-row" },
                h("div", { class: "who" }, h("b", null, c.name), h("span", null, `${c.job || "sans métier"} · perso ${c.identifier.slice(0, 8)}…`)),
                h("button", { class: "btn small", onclick: () => add({ identifier: c.identifier }) }, icon("i-plus"), "Ajouter")))) : null
    );
}

async function deleteStructure(kind, info) {
    const yes = await confirmBox(`Supprimer « ${info.label} » ?`, "La fiche, le métier ESX, ses grades et le temps de jeu de ses membres sont effacés. Action définitive.", "Supprimer", true);
    if (!yes) return;
    const res = await act("structures.delete", { job: info.name }, "Structure supprimée.");
    if (!res) return;
    const st = structOf(kind);
    st.selected = null;
    st.info = null;
    loadStructures(kind);
    paintStructureFiche(kind);
}

// ---------- Création ----------

function newStructureForm(kind) {
    const st = structOf(kind);
    const meta = STRUCTURE_KINDS[kind];
    let mode = "new";
    let gradesTouched = false;
    let nameTouched = false;

    const type = h("select", { class: "input" }, st.types.map((t) => h("option", { value: t.id }, t.label)));
    const label = h("input", { class: "input", maxlength: "50", placeholder: kind === "public" ? "Ex. LSPD" : "Ex. Burger Shot" });
    const name = h("input", { class: "input mono", maxlength: "30", placeholder: kind === "public" ? "lspd" : "burgershot" });
    const existing = h("select", { class: "input" }, st.orphans.length
        ? st.orphans.map((o) => h("option", { value: o.name }, `${o.label} (${o.name})`))
        : [h("option", { value: "" }, "Aucun métier disponible au Pôle emploi")]);
    label.addEventListener("input", () => { if (!nameTouched) name.value = poleSlug(label.value); });
    name.addEventListener("input", () => { nameTouched = true; });

    let grades = [];
    const gradeList = h("div", { class: "table" });
    const fillGrades = () => {
        grades = (DEFAULT_GRADES[type.value] || DEFAULT_GRADES.default).map(([l, salary]) => ({ label: l, salary }));
        paintGrades();
    };
    const paintGrades = () => gradeList.replaceChildren(...grades.map((g, index) => {
        const gLabel = h("input", { class: "input", maxlength: "50", value: g.label });
        const gSalary = h("input", { class: "input mono", type: "number", min: "0", value: String(g.salary) });
        gLabel.addEventListener("input", () => { g.label = gLabel.value; gradesTouched = true; });
        gSalary.addEventListener("input", () => { g.salary = Number(gSalary.value || 0); gradesTouched = true; });
        return h("div", { class: "row grade-row" },
            h("span", { class: "pid mono" }, String(index)),
            gLabel,
            h("label", { class: "salary" }, gSalary, h("span", { class: "muted" }, "$")),
            h("span", { class: "muted" }, index === grades.length - 1 ? "Patron" : index === 0 ? "Embauche" : ""),
            h("button", { class: "btn small ghost", disabled: grades.length <= 1, title: "Retirer ce grade", onclick: () => { grades.splice(index, 1); gradesTouched = true; paintGrades(); } }, icon("i-trash"))
        );
    }));
    type.addEventListener("change", () => { if (!gradesTouched) fillGrades(); });
    fillGrades();

    const newPart = h("div", null,
        h("div", { class: "card", style: "margin-top:16px" },
            h("div", { class: "fields pole-fields" },
                h("div", { class: "field" }, h("label", null, "Label (nom affiché)"), label),
                h("div", { class: "field" }, h("label", null, "Nom (identifiant interne)"), name))),
        h("div", { class: "card", style: "margin-top:16px" },
            h("h3", { class: "card-title" }, "Grades, du plus bas au plus haut"),
            gradeList,
            h("div", { class: "btn-row", style: "margin-top:12px" },
                h("button", { class: "btn ghost", onclick: () => {
                    if (grades.length >= 20) return toast("20 grades maximum.", "error");
                    grades.push({ label: "", salary: 0 });
                    gradesTouched = true;
                    paintGrades();
                } }, icon("i-plus"), "Ajouter un grade"))));
    const existingPart = h("div", { class: "card", style: "margin-top:16px" },
        h("div", { class: "field" }, h("label", null, "Métier du Pôle emploi"), existing),
        h("p", { class: "hint-line" }, "Le métier garde ses grades et ses membres ; il quitte la liste du Pôle emploi."));

    const modeTabs = h("div", { class: "segmented" });
    const paintMode = () => {
        modeTabs.replaceChildren(...segmentedButtons([{ value: "new", label: "Nouveau métier" }, { value: "existing", label: "Métier existant" }], mode, (v) => { mode = v; paintMode(); }));
        newPart.style.display = mode === "new" ? "" : "none";
        existingPart.style.display = mode === "existing" ? "" : "none";
    };
    paintMode();

    const submit = h("button", { class: "btn primary" }, icon("i-plus"), meta.create);
    submit.addEventListener("click", async () => {
        const payload = mode === "existing"
            ? { kind, mode, job: existing.value, type: type.value }
            : { kind, mode, type: type.value, name: name.value.trim(), label: label.value.trim(), grades: grades.map((g) => ({ label: g.label.trim(), salary: g.salary })) };
        if (mode === "existing" && !existing.value) return toast("Aucun métier à rattacher.", "error");
        const res = await act("structures.create", payload, `${meta.one[0].toUpperCase()}${meta.one.slice(1)} créé${kind === "public" ? "" : "e"}.`);
        if (!res) return;
        await loadStructures(kind);
        selectStructure(kind, res.job);
    });

    return [
        h("div", { class: "page-head" }, h("div", { class: "grow" },
            h("h1", { class: "page-title" }, kind === "public" ? "Nouveau service public" : "Nouvelle entreprise"),
            h("div", { class: "page-sub" }, "Disponible tout de suite en jeu, sans redémarrage"))),
        h("div", { class: "scroll" },
            h("div", { class: "card" },
                h("div", { class: "struct-fields" },
                    h("div", { class: "field" }, h("label", null, "Type"), type),
                    h("div", { class: "field" }, h("label", null, "Métier"), modeTabs))),
            newPart,
            existingPart,
            h("div", { class: "btn-row", style: "margin-top:16px" }, submit))
    ];
}
