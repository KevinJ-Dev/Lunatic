"use strict";

// ====================================================================
//  lunatic_admin — tuiles Entreprises et Services publics (organisation en 4 colonnes, comme les Crews)
//  1. Types et structures du type ; 2. Fiche (bannière, logo, identité) ; 3. Catalogues et positions (groupes repliables) ;
//  4. Employés, grades et compte de société, actions (rejoindre, supprimer). Grades : cartes du Pôle emploi (web/poles.js).
// ====================================================================

const STRUCTURE_KINDS = {
    company: { view: "companies", title: "Entreprises", one: "entreprise", create: "Créer une entreprise", icon: "i-store", head: "Fiche d'entreprise", staff: "Employés" },
    public: { view: "publics", title: "Services publics", one: "service public", create: "Créer un service public", icon: "i-shield", head: "Fiche", staff: "Employés" },
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
        structState[kind] = {
            list: null, orphans: [], types: [], typeFilter: null, selected: null, info: null, draft: null, saved: "",
            sideTab: "members", memberSearch: "", openMember: null, candidates: null, catalogs: false, openGroups: new Set(), loadedAt: 0,
        };
    }
    return structState[kind];
}

const NEW_STRUCTURE = "__new";

function renderStructures(kind) {
    const st = structOf(kind);
    if (!$(`view-${STRUCTURE_KINDS[kind].view}`).childElementCount) paintStructures(kind);
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
    if (!st.typeFilter && st.types.length) st.typeFilter = st.types[0].id;
    paintStructures(kind);
}

async function loadStructureInfo(kind) {
    const st = structOf(kind);
    const job = st.selected;
    if (!job || job === NEW_STRUCTURE) return;
    const res = await nui("action", { action: "structures.info", payload: { job } }).catch(() => null);
    if (job !== st.selected) return;
    st.info = res && res.ok ? res.job : false;
    if (res && res.types) st.types = res.types;
    paintStructures(kind);
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

// Change de type, de structure ou de vue (en demandant si la fiche a des modifications)
function structGo(kind, changes) {
    const st = structOf(kind);
    guardUnsaved(STRUCTURE_KINDS[kind].view, () => {
        untrackUnsaved(STRUCTURE_KINDS[kind].view);
        const changed = "selected" in changes && changes.selected !== st.selected;
        Object.assign(st, changes, { draft: null });
        if (changed) {
            Object.assign(st, { info: null, openMember: null, candidates: null, catalogs: false });
            loadStructureInfo(kind);
        }
        paintStructures(kind);
    });
}

function selectStructure(kind, job) {
    const st = structOf(kind);
    const entry = (st.list || []).find((s) => s.job === job);
    structGo(kind, { selected: job, typeFilter: entry ? entry.type : st.typeFilter });
}

const structType = (kind, id) => structOf(kind).types.find((t) => t.id === id) || { id, label: id, color: "#9650ff" };

// ---------- Mise en page ----------

function paintStructures(kind) {
    const st = structOf(kind);
    const meta = STRUCTURE_KINDS[kind];
    const root = $(`view-${meta.view}`);
    if (!st.list) return root.replaceChildren(h("div", { class: "content" }, h("div", { class: "empty" }, icon(meta.icon), "Chargement…")));

    const keep = [...root.querySelectorAll(".crew-scroll")].map((el) => el.scrollTop);
    const empty = (text) => [h("div", { class: "crew-empty" }, h("div", { class: "empty" }, icon(meta.icon), text))];
    let columns;
    if (st.selected === NEW_STRUCTURE) columns = [h("section", { class: "crew-col struct-wide-col" }, ...newStructureForm(kind))];
    else if (!st.selected) columns = empty(`Choisissez un${kind === "public" ? "" : "e"} ${meta.one} dans la liste, ou créez-en un${kind === "public" ? "" : "e"}.`);
    else if (st.info === false) columns = empty("Cette structure n'existe plus.");
    else if (!st.info) columns = empty("Chargement de la fiche…");
    else if (st.catalogs) columns = [structCatalogsColumn(kind, st.info)];
    else columns = [structFicheColumn(kind, st.info), structPointsColumn(kind, st.info), structStaffColumn(kind, st.info)];

    root.replaceChildren(h("div", { class: `crew-page struct-page${columns.length === 1 ? " single" : ""}` }, structNavColumn(kind), ...columns));
    root.querySelectorAll(".crew-scroll").forEach((el, index) => { if (keep[index]) el.scrollTop = keep[index]; });
}

function structLogo(s, size) {
    const box = h("span", { class: "struct-mini" });
    box.style.width = box.style.height = `${size}px`;
    const initial = () => { box.replaceChildren((s.label || s.job || "?").slice(0, 1).toUpperCase()); box.style.background = s.color || "#9650ff"; };
    if (s.logo) {
        const img = h("img", { src: s.logo, alt: "" });
        img.addEventListener("error", initial);
        box.append(img);
    } else {
        initial();
    }
    return box;
}

function structNavColumn(kind) {
    const st = structOf(kind);
    const meta = STRUCTURE_KINDS[kind];
    const counts = {};
    for (const s of st.list) counts[s.type] = (counts[s.type] || 0) + 1;

    const typeRows = st.types.map((t) => {
        const dot = h("span", { class: "crew-dot" });
        dot.style.background = t.color || "#9650ff";
        return h("button", { class: `list-row${st.typeFilter === t.id ? " active" : ""}`, onclick: () => st.typeFilter !== t.id && structGo(kind, { typeFilter: t.id }) },
            dot, h("span", { class: "name" }, t.label), h("span", { class: "cnt" }, String(counts[t.id] || 0)));
    });
    const type = structType(kind, st.typeFilter);
    const ofType = st.list.filter((s) => s.type === type.id);

    return h("aside", { class: "sidebar crew-nav crew-scroll" },
        h("div", { class: "crew-block" }, h("div", { class: "crew-block-head" }, icon("i-layers"), kind === "public" ? "Type" : "Type d'entreprise"), typeRows),
        h("div", { class: "crew-block" },
            h("div", { class: "crew-block-head" }, icon(meta.icon), type.label),
            ofType.map((s) => h("button", { class: `list-row player-row${s.job === st.selected ? " active" : ""}`, onclick: () => s.job !== st.selected && selectStructure(kind, s.job) },
                structLogo(s, 26), h("span", { class: "who" }, h("b", null, s.label || s.job), h("span", null, `${s.total} membre${s.total > 1 ? "s" : ""} · ${s.online} en ligne`)))),
            h("button", { class: `list-row${st.selected === NEW_STRUCTURE ? " active" : ""}`, onclick: () => structGo(kind, { selected: NEW_STRUCTURE }) }, icon("i-plus"), h("span", { class: "name" }, kind === "public" ? "Créer" : "Créer une entreprise"))));
}

// ---------- 2. Fiche ----------

function structDraft(kind, info) {
    const st = structOf(kind);
    const key = `struct:${info.name}`;
    if (st.draft && st.draft.key === key) return st.draft;
    const s = info.structure;
    const base = { key, label: info.label || "", type: s.type, lead: s.lead || "", color: s.color || "#9650ff", logo: s.logo || "", banner: s.banner || "", radialIcon: s.radialIcon || "" };
    st.draft = base;
    st.saved = JSON.stringify(base);
    trackUnsaved(STRUCTURE_KINDS[kind].view, {
        label: `Fiche de ${info.label || info.name}`,
        isDirty: () => !!st.draft && JSON.stringify(st.draft) !== st.saved,
        save: () => saveStructure(kind),
        reset: () => { st.draft = null; paintStructures(kind); },
    });
    return base;
}

async function saveStructure(kind) {
    const st = structOf(kind);
    const d = st.draft;
    const info = st.info;
    if (!d || !info) return;
    const res = await act("structures.save", {
        job: info.name, label: d.label.trim(), type: d.type, lead: kind === "public" ? d.lead : null, color: kind === "company" ? d.color : null,
        logo: d.logo.trim(), banner: d.banner.trim(), radialIcon: d.radialIcon.trim(),
    }, "Fiche enregistrée.");
    if (!res) return;
    untrackUnsaved(STRUCTURE_KINDS[kind].view);
    st.draft = null;
    loadStructures(kind);
    loadStructureInfo(kind);
}

function structFicheColumn(kind, info) {
    const st = structOf(kind);
    const d = structDraft(kind, info);
    const s = info.structure;
    const meta = STRUCTURE_KINDS[kind];
    const bind = (input, key, event = "input") => { input.addEventListener(event, () => { d[key] = input.value; }); return input; };
    const total = info.grades.reduce((sum, g) => sum + g.members, 0);
    const type = structType(kind, d.type);

    const fields = [
        crewField("i-key", "Nom", h("input", { class: "input mono", value: info.name, disabled: true, title: "Identifiant interne (métier ESX)" })),
        crewField("i-edit", "Label", bind(h("input", { class: "input", maxlength: "50", value: d.label }), "label")),
        crewField("i-layers", "Type", bind(h("select", { class: "input" }, st.types.map((t) => h("option", { value: t.id, selected: t.id === d.type }, t.label))), "type", "change")),
    ];
    if (kind === "public") {
        const known = new Set(info.members.map((m) => m.identifier));
        const lead = bind(h("select", { class: "input" }, h("option", { value: "" }, "— Aucun —"),
            info.members.map((m) => h("option", { value: m.identifier, selected: m.identifier === d.lead }, m.name)),
            d.lead && !known.has(d.lead) ? h("option", { value: d.lead, selected: true }, `${info.leadName || d.lead} (plus membre)`) : null), "lead", "change");
        fields.push(crewField("i-crown", "Lead", lead));
    } else {
        fields.push(crewField("i-sparkle", "Couleur", bind(h("input", { class: "input color-input", type: "color", value: d.color }), "color")));
    }

    const banner = s.banner ? h("img", { class: "struct-banner", src: s.banner, alt: "" }) : null;
    if (banner) banner.addEventListener("error", () => banner.remove());
    const typeBadge = h("span", { class: "crew-type-badge" }, type.label);
    typeBadge.style.setProperty("--type", type.color || "#9650ff");

    return h("section", { class: "crew-col" },
        h("div", { class: "crew-col-head" }, icon(meta.icon), meta.head),
        h("div", { class: "crew-scroll crew-col-body" },
            banner,
            h("div", { class: `crew-id${banner ? " under-banner" : ""}` },
                h("div", { class: "crew-pic" }, structLogo({ ...s, label: info.label, job: info.name }, 58)),
                h("div", { class: "crew-id-text" }, h("b", null, info.label || info.name), typeBadge),
                h("div", { class: "crew-stats two" },
                    h("div", null, h("b", null, String(total)), h("span", null, kind === "public" ? "Mbr." : "Empl.")),
                    h("div", null, h("b", null, String((info.points || []).length)), h("span", null, "Pts")))),
            h("div", { class: "crew-sub" }, "Informations"),
            fields,
            h("div", { class: "crew-sub" }, "Logo"),
            crewField("i-image", "URL", imageField(bind(h("input", { class: "input mono", maxlength: "255", placeholder: "https://…/logo.png", value: d.logo }), "logo"))),
            crewField("i-sparkle", "Radial icon", bind(h("input", { class: "input mono", maxlength: "60", placeholder: "fa-solid fa-utensils", value: d.radialIcon }), "radialIcon")),
            h("div", { class: "crew-sub" }, "Bannière"),
            crewField("i-image", "URL", imageField(bind(h("input", { class: "input mono", maxlength: "255", placeholder: "https://…/banniere.png", value: d.banner }), "banner"))),
            h("p", { class: "hint-line" }, `Créé${kind === "public" ? "" : "e"} par ${s.createdBy || "?"}${s.createdAt ? ` le ${new Date(s.createdAt * 1000).toLocaleDateString("fr-FR")}` : ""}. Enregistrez avec la barre du bas.`)));
}

// ---------- 3. Catalogues et positions ----------

function structPointsColumn(kind, info) {
    const st = structOf(kind);
    const doAct = structureActor(kind);
    const types = info.pointTypes || [];
    const points = info.points || [];
    const activeCatalogs = (info.catalogs || []).length;

    const groups = types.map((t) => {
        if (t.fleet) return structFleetGroup(kind, info, t, doAct);
        const list = points.filter((p) => p.type === t.id);
        const open = st.openGroups.has(t.id);
        const toggle = () => {
            if (open) st.openGroups.delete(t.id);
            else st.openGroups.add(t.id);
            paintStructures(kind);
        };
        return h("div", { class: `crew-point-group${open ? " open" : ""}` },
            h("button", { class: "crew-point-title", onclick: toggle },
                h("span", null, t.label), t.ready ? null : h("span", { class: "badge muted" }, "bientôt"),
                h("span", { class: "cnt" }, String(list.length)), h("span", { class: "crew-chevron" }, "▸")),
            open ? [
                ...list.map((p) => structPointCard(p, t, doAct)),
                ...(t.id === "garage" ? (info.vehicleCategories || []).map((c) => [c.id, GARAGE_KINDS[c.id] || c.label]) : [[null, t.label.toLowerCase()]]).map(([variant, what]) =>
                    h("button", { class: "btn small ok-btn wide", onclick: () => {
                        st.openGroups.add(t.id);
                        doAct("structures.addPoint", { job: info.name, type: t.id, label: "", data: variant ? { vehicle: variant } : null }, "Point ajouté à votre position.");
                    } }, icon("i-plus"), `Ajouter : ${what}`)),
                t.id === "garage" ? h("p", { class: "hint-line" }, "Le véhicule sort à 4 m devant vous : placez le point en regardant l'emplacement de sortie (piste, hélipad, ponton).") : null,
                t.ready ? null : h("p", { class: "hint-line" }, "Plaçable dès maintenant, utilisable en jeu quand son système sera prêt."),
            ] : null);
    });

    return h("section", { class: "crew-col" },
        h("div", { class: "crew-col-pad", style: "padding-top:14px" },
            h("button", { class: "struct-catalog-btn", onclick: () => structGo(kind, { catalogs: true }) },
                icon("i-book"), h("span", null, h("b", null, "Catalogues"), h("small", null, `${activeCatalogs} actif${activeCatalogs > 1 ? "s" : ""}`)), h("span", { class: "crew-chevron" }, "▸"))),
        h("div", { class: "crew-col-head", style: "padding-top:4px" }, icon("i-pin"), "Positions", h("span", { class: "cnt" }, String(points.length))),
        h("div", { class: "crew-scroll crew-col-body" }, h("div", { class: "crew-list" }, groups),
            h("p", { class: "hint-line" }, "Les points se placent à votre position en jeu. « Définir » les déplace, « TP » vous y emmène.")));
}

const GARAGE_KINDS = { car: "garage", air: "héliport", sea: "port" };

// Réglages propres au type : catégorie du garage, icône et couleur du blip
function structPointSettings(p, doAct) {
    const data = { ...(p.data || {}) };
    const save = () => doAct("structures.pointData", { id: p.id, data }, null);
    if (p.type === "garage") {
        const info = structOf(p.kind || "company").info || structOf("public").info || {};
        const select = h("select", { class: "input" }, (info.vehicleCategories || [{ id: "car", label: "Véhicules" }, { id: "air", label: "Aérien" }, { id: "sea", label: "Marin" }])
            .map((c) => h("option", { value: c.id, selected: c.id === (data.vehicle || "car") }, `Sort : ${c.label}`)));
        select.addEventListener("change", () => { data.vehicle = select.value; save(); });
        return h("div", { class: "crew-point-row" }, select);
    }
    if (p.type === "blips") {
        const d = { sprite: data.sprite ?? 60, color: data.color ?? 0 };
        const scale = h("input", { class: "input mono", type: "number", min: "0.1", max: "3", step: "0.1", value: String(data.scale ?? 0.8), title: "Taille" });
        scale.addEventListener("change", () => { data.scale = Number(scale.value); save(); });
        const done = () => { data.sprite = d.sprite; data.color = d.color; save(); };
        return h("div", { class: "struct-blip" },
            h("div", { class: "crew-point-row" }, blipIcon(d.sprite, d.color, 26), h("span", { class: "muted" }, `Sprite #${d.sprite} · ${blipColorName(d.color)}`), scale),
            h("details", { class: "blip-fold" }, h("summary", null, icon("i-pin"), "Sprite"), spritePicker(d, done)),
            h("details", { class: "blip-fold" }, h("summary", null, icon("i-sparkle"), "Couleur"), colorPicker(d, done)));
    }
    return null;
}

// Parc de véhicules : par catégorie, modèle, nom, type et grade minimum
function structFleetGroup(kind, info, t, doAct) {
    const st = structOf(kind);
    const fleet = info.vehicles || [];
    const open = st.openGroups.has(t.id);
    const toggle = () => {
        if (open) st.openGroups.delete(t.id);
        else st.openGroups.add(t.id);
        paintStructures(kind);
    };
    const grades = info.grades || [];
    const gradeSelect = (value) => h("select", { class: "input" }, grades.map((g) => h("option", { value: String(g.grade), selected: g.grade === value }, `Dès ${g.label}`)));
    const typeSelect = (value) => h("select", { class: "input" }, (info.vehicleTypes || ["automobile"]).map((id) => h("option", { value: id, selected: id === value }, VEHICLE_TYPE_LABELS[id] || id)));

    const row = (v, category) => {
        const model = h("input", { class: "input mono", maxlength: "40", placeholder: "modèle (ex. police3)", value: v ? v.model : "" });
        const label = h("input", { class: "input", maxlength: "60", placeholder: "Nom affiché", value: v ? v.label : "" });
        const vtype = typeSelect(v ? v.vtype : (category === "air" ? "heli" : category === "sea" ? "boat" : "automobile"));
        const grade = gradeSelect(v ? v.minGrade : (grades[0] || {}).grade || 0);
        const payload = () => ({ job: info.name, id: v ? v.id : null, category, model: model.value.trim(), label: label.value.trim(), vtype: vtype.value, minGrade: Number(grade.value) });
        if (v) for (const el of [model, label, vtype, grade]) el.addEventListener("change", () => doAct("structures.vehicleSave", payload(), "Véhicule enregistré."));
        return h("div", { class: `struct-vehicle${v ? "" : " new"}` }, model, label, vtype, grade,
            v ? h("button", { class: "btn small ghost sq-btn", title: "Retirer du parc", onclick: () => doAct("structures.vehicleDelete", { id: v.id }, "Véhicule retiré.") }, icon("i-trash"))
              : h("button", { class: "btn small ok-btn sq-btn", title: "Ajouter au parc", onclick: () => model.value.trim() && doAct("structures.vehicleSave", payload(), "Véhicule ajouté.") }, icon("i-plus")));
    };

    return h("div", { class: `crew-point-group${open ? " open" : ""}` },
        h("button", { class: "crew-point-title", onclick: toggle },
            h("span", null, t.label), h("span", { class: "cnt" }, String(fleet.length)), h("span", { class: "crew-chevron" }, "▸")),
        open ? [
            ...(info.vehicleCategories || []).map((c) => h("div", { class: "struct-fleet" },
                h("div", { class: "crew-sub", style: "text-align:left;margin:8px 2px 4px" }, c.label),
                ...fleet.filter((v) => v.category === c.id).map((v) => row(v, c.id)),
                row(null, c.id))),
            h("p", { class: "hint-line" }, "Les membres les sortent aux points Garages de la bonne catégorie, selon leur grade. Un véhicule à la fois par membre."),
        ] : null);
}

const VEHICLE_TYPE_LABELS = { automobile: "Voiture", bike: "Moto", heli: "Hélicoptère", plane: "Avion", boat: "Bateau" };

function structPointCard(p, type, doAct) {
    const label = h("input", { class: "input", maxlength: "60", value: p.label });
    label.addEventListener("change", () => {
        if (label.value.trim() !== p.label) doAct("structures.renamePoint", { id: p.id, label: label.value.trim() }, "Point renommé.");
    });
    return h("div", { class: "crew-point" },
        h("div", { class: "crew-point-head" }, h("span", { class: `crew-point-dot${type.ready ? "" : " soon"}` }), label,
            h("button", { class: "btn small ghost sq-btn", title: "Supprimer", onclick: async () => {
                const yes = await confirmBox(`Supprimer « ${p.label} » ?`, p.type === "storage" ? "Le contenu du coffre reste en base, mais il n'est plus accessible." : "Le point disparaît pour tous les membres.", "Supprimer", true);
                if (yes) doAct("structures.deletePoint", { id: p.id }, "Point supprimé.");
            } }, icon("i-trash"))),
        h("div", { class: "crew-point-row" },
            h("span", { class: "crew-coords mono" }, `${p.x.toFixed(0)}  ${p.y.toFixed(0)}  ${p.z.toFixed(0)}`),
            h("button", { class: "btn small ghost", title: "Le point passe à votre position", onclick: () => doAct("structures.movePoint", { id: p.id }, "Point replacé à votre position.") }, icon("i-crosshair"), "Définir"),
            h("button", { class: "btn small ghost", onclick: () => act("structures.tpPoint", { id: p.id }, null) }, icon("i-goto"), "TP")),
        structPointSettings(p, doAct));
}

// Catalogues : l'éditeur de la structure en grand, avec retour à la fiche
function structCatalogsColumn(kind, info) {
    return h("section", { class: "crew-col struct-wide-col" },
        h("div", { class: "crew-col-head" },
            h("button", { class: "btn small ghost", onclick: () => structGo(kind, { catalogs: false }) }, icon("i-back"), "Retour"),
            icon("i-book"), `Catalogues · ${info.label || info.name}`),
        h("div", { class: "crew-scroll crew-col-body" }, structureCatalogsCard(info, structureActor(kind))));
}

// ---------- 4. Employés, grades, compte ----------

function structStaffColumn(kind, info) {
    const st = structOf(kind);
    const doAct = structureActor(kind);
    const total = info.grades.reduce((sum, g) => sum + g.members, 0);
    const tabs = h("div", { class: "segmented block" }, segmentedButtons([
        { value: "members", label: `${STRUCTURE_KINDS[kind].staff} (${total})` }, { value: "grades", label: `Grades (${info.grades.length})` }, { value: "account", label: "Compte" },
    ], st.sideTab, (v) => { st.sideTab = v; paintStructures(kind); }));

    let body;
    if (st.sideTab === "grades") body = gradesCard(info, doAct);
    else if (st.sideTab === "account") body = accountCard(info, doAct);
    else body = structMemberList(kind, info, doAct);

    return h("section", { class: "crew-col struct-staff" },
        h("div", { class: "crew-col-head" }, icon("i-users"), STRUCTURE_KINDS[kind].staff, h("span", { class: "cnt" }, String(total))),
        h("div", { class: "crew-col-pad" }, tabs),
        h("div", { class: "crew-scroll crew-col-body" }, body),
        st.sideTab === "members" ? structAddMember(kind, info) : null,
        h("div", { class: "crew-actions two" },
            h("button", { class: "btn small", onclick: () => doAct("structures.join", { job: info.name }, `Vous rejoignez ${info.label}.`) }, icon("i-user-plus"), "Rejoindre"),
            h("button", { class: "btn small danger", disabled: total > 0, title: total > 0 ? "Renvoyez d'abord tous les membres" : null, onclick: () => deleteStructure(kind, info) }, icon("i-trash"), "Supprimer")));
}

function structMemberList(kind, info, doAct) {
    const st = structOf(kind);
    if (info.membersHidden) return h("p", { class: "hint-line" }, "Membres non listés.");
    const search = h("input", { placeholder: "Rechercher…", value: st.memberSearch });
    search.addEventListener("input", () => {
        st.memberSearch = search.value;
        const pos = search.selectionStart;
        paintStructures(kind);
        const again = $(`view-${STRUCTURE_KINDS[kind].view}`).querySelector(".crew-member-search input");
        if (again) { again.focus(); again.setSelectionRange(pos, pos); }
    });
    const q = fold(st.memberSearch.trim());
    const list = info.members.filter((m) => !q || fold(m.name).includes(q) || String(m.online || "") === q);
    loadMugshots(info.members.map((m) => m.identifier)).then((found) => found && paintStructures(kind));
    const gradeLabel = (grade) => (info.grades.find((g) => g.grade === grade) || {}).label || `Grade ${grade}`;

    const rows = list.map((m) => {
        const open = st.openMember === m.identifier;
        const row = h("button", { class: `crew-member${open ? " open" : ""}`, onclick: () => { st.openMember = open ? null : m.identifier; paintStructures(kind); } },
            mugshotImg(m.identifier, "mug-row"),
            h("span", { class: "who" }, h("b", null, m.online ? `[${m.online}] ${m.name}` : m.name), h("span", null, [gradeLabel(m.grade), m.playtime ? `${playtimeText(m.playtime)} de service` : null].filter(Boolean).join(" · "))),
            h("span", { class: `status${m.online ? " on" : ""}`, title: m.online ? `En ligne · ID ${m.online}` : "Hors ligne" }));
        if (!open) return row;
        const select = h("select", { class: "input", disabled: m.protected, title: m.protected ? "Rang égal ou supérieur au vôtre" : null },
            [...info.grades].reverse().map((g) => h("option", { value: String(g.grade), selected: g.grade === m.grade }, g.label)));
        select.addEventListener("change", async () => {
            const grade = Number(select.value);
            const res = await doAct("poles.setMember", { job: info.name, identifier: m.identifier, grade }, `${m.name} : ${gradeLabel(grade)}.`);
            if (!res) select.value = String(m.grade);
        });
        return h("div", { class: "crew-member-box" }, row,
            h("div", { class: "crew-member-edit" }, select,
                h("button", { class: "btn small ghost", disabled: m.protected, onclick: async () => {
                    if (await confirmBox(`Renvoyer ${m.name} ?`, `Il quitte ${info.label} et devient sans emploi.`, "Renvoyer", true)) doAct("poles.fire", { job: info.name, identifier: m.identifier }, `${m.name} a été renvoyé.`);
                } }, icon("i-door"), "Renvoyer")));
    });

    return h("div", { class: "crew-list" },
        h("label", { class: "search crew-member-search" }, icon("i-search"), search),
        rows.length ? rows : h("p", { class: "hint-line" }, info.members.length ? "Aucun membre ne correspond." : "Aucun membre : ajoutez-en par nom ou ID."));
}

function structAddMember(kind, info) {
    const st = structOf(kind);
    const input = h("input", { class: "input", maxlength: "60", placeholder: "Nom ou ID" });
    const add = async (payload) => {
        const res = await act("structures.addMember", { job: info.name, ...payload }, null);
        if (!res) return;
        if (res.candidates) {
            st.candidates = res.candidates;
            return paintStructures(kind);
        }
        st.candidates = null;
        toast(`${res.name || "Le joueur"} rejoint ${info.label}.`, "ok");
        loadStructures(kind);
        loadStructureInfo(kind);
    };
    input.addEventListener("keydown", (e) => { if (e.key === "Enter" && input.value.trim()) add({ query: input.value.trim() }); });
    return h("div", { class: "crew-add" },
        st.candidates ? h("div", { class: "crew-candidates" }, st.candidates.map((c) => h("button", { class: "crew-line", onclick: () => add({ identifier: c.identifier }) },
            h("span", { class: "who" }, h("b", null, c.name), h("span", null, c.job || "sans métier")), icon("i-plus")))) : null,
        h("div", { class: "spawn-row" }, input, h("button", { class: "btn small primary", onclick: () => input.value.trim() && add({ query: input.value.trim() }) }, icon("i-plus"))));
}

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

async function deleteStructure(kind, info) {
    const yes = await confirmBox(`Supprimer « ${info.label} » ?`, "La fiche, le métier ESX, ses grades et le temps de jeu de ses membres sont effacés. Action définitive.", "Supprimer", true);
    if (!yes) return;
    const res = await act("structures.delete", { job: info.name }, "Structure supprimée.");
    if (!res) return;
    const st = structOf(kind);
    untrackUnsaved(STRUCTURE_KINDS[kind].view);
    Object.assign(st, { selected: null, info: null, draft: null });
    loadStructures(kind);
}

// ---------- Compte de société ----------

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

// ---------- Création ----------

function newStructureForm(kind) {
    const st = structOf(kind);
    const meta = STRUCTURE_KINDS[kind];
    let mode = "new";
    let gradesTouched = false;
    let nameTouched = false;

    const type = h("select", { class: "input" }, st.types.map((t) => h("option", { value: t.id, selected: t.id === st.typeFilter }, t.label)));
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
            h("label", { class: "salary" }, gSalary, h("span", { class: "muted" }, currencySymbol())),
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
