"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, page Drogues (laboratoires à gauche, drogues au centre, fiche à droite)
//  Drogues (prix, XP, influence, policiers, volumes), laboratoires (type de crew, recette) et leurs emplacements.
// ====================================================================

const drugState = { data: null, staffView: false };

async function loadDrugs() {
    const res = await nui("action", { action: "drugs.info", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    drugState.data = res;
    if (illegalState.tab === "drugs") paintIllegal();
}

async function drugAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) await loadDrugs();
    return res;
}

// Ce qui empêche un laboratoire de fonctionner en jeu
function labProblems(lab) {
    const problems = [];
    if (!lab.locations.length) problems.push("aucun emplacement");
    const unknown = lab.ingredients.filter((i) => i.missing).length;
    if (unknown) problems.push(`${unknown} ingrédient${unknown > 1 ? "s" : ""} inconnu${unknown > 1 ? "s" : ""}`);
    const counts = (drugState.data && drugState.data.crewCounts) || {};
    if (!counts[lab.crewType]) problems.push(`aucun crew de type ${lab.crewTypeLabel}`);
    return problems;
}

function drugProblems(drug) {
    const problems = [];
    if (drug.missing) problems.push("objet inconnu dans ox_inventory");
    if (!drug.labs.length) problems.push("aucun laboratoire");
    const broken = drug.labs.filter((lab) => labProblems(lab).length).length;
    if (broken) problems.push(`${broken} laboratoire${broken > 1 ? "s" : ""} incomplet${broken > 1 ? "s" : ""}`);
    return problems;
}

function drugsPage() {
    const d = drugState.data;
    if (!d) {
        loadDrugs();
        return illegalLoading("Drogues", "i-sparkle", "Chargement des drogues…");
    }
    const sel = illegalState.drugSel;
    const selected = d.drugs.find((drug) => drug.id === sel);
    const readyCount = d.drugs.filter((drug) => drug.active && !drugProblems(drug).length).length;

    const tiles = d.drugs.map((drug) => illegalTile({
        item: drug.item, label: drug.label, badge: drug.active ? null : "off", active: drug.id === sel, warn: drugProblems(drug).length > 0, off: !drug.active,
        onclick: () => drug.id !== sel && illegalSwitch(() => { illegalState.drugSel = drug.id; }),
    }));

    // Laboratoires de la drogue choisie
    const labs = selected ? selected.labs.map((lab) => {
        const problems = labProblems(lab);
        const locations = lab.locations.map((l, i) => pointLine(i + 1, null, l, [
            iconButton("i-crosshair", "Replacer à votre position", () => drugAct("drugs.moveLocation", { locationId: l.id }, "Emplacement replacé à votre position.")),
            iconButton("i-goto", "TP", () => act("drugs.tpLocation", { locationId: l.id }, null)),
            iconButton("i-trash", "Supprimer", () => drugAct("drugs.deleteLocation", { locationId: l.id }, "Emplacement supprimé.")),
        ]));
        return h("div", { class: "side-card" },
            h("div", { class: "side-card-head" }, readyDot(problems), h("b", null, lab.crewTypeLabel),
                iconButton("i-plus", "Ajouter un emplacement à votre position", () => drugAct("drugs.addLocation", { labId: lab.id }, "Emplacement ajouté à votre position.")),
                iconButton("i-edit", "Modifier le laboratoire", () => openDrugLab(selected, lab)),
                iconButton("i-trash", "Supprimer le laboratoire", async () => {
                    const yes = await confirmBox("Supprimer ce laboratoire ?", "Sa recette et ses emplacements sont effacés.", "Supprimer", true);
                    if (yes) drugAct("drugs.deleteLab", { labId: lab.id }, "Laboratoire supprimé.");
                })),
            h("span", { class: "side-card-sub" }, `${lab.ingredients.map((i) => `${i.count} × ${i.label}`).join(" + ")} → ${lab.output} en ${lab.duration} s`),
            locations,
            problems.length ? h("span", { class: "side-card-warn" }, `À compléter : ${problems.join(" · ")}`) : null);
    }) : [];

    return {
        title: "Drogues",
        sub: "Vente aux passants ([E] près d'un PNJ), production dans les laboratoires réservés à un type de crew. Prix ±15 %, payé en argent sale.",
        actions: [
            d.drugs.length ? h("span", { class: `badge ${readyCount ? "ok" : "warn"}` }, `${readyCount} prête${readyCount > 1 ? "s" : ""} en jeu`) : null,
            h("button", { class: `btn small${drugState.staffView ? " primary" : ""}`, title: "Affiche en jeu tous les points de laboratoire (en orange), même sans être dans un crew du bon type", onclick: async () => {
                const enabled = !drugState.staffView;
                const res = await act("drugs.staffView", { enabled }, null);
                if (!res) return;
                drugState.staffView = enabled;
                paintIllegal();
            } }, icon("i-eye"), drugState.staffView ? "Masquer les labos" : "Voir les labos en jeu"),
            h("button", { class: "btn small", title: "Ajoute weed, cocaïne, meth et fentanyl (avec leurs laboratoires) s'ils n'existent pas encore", onclick: async () => {
                const res = await drugAct("drugs.seed", {}, null);
                if (res) toast(`${res.created} drogue(s) de départ ajoutée(s) : placez leurs laboratoires.`, "ok");
            } }, icon("i-sparkle"), "Drogues de départ"),
        ],
        side: [selected
            ? sideBlock(`Laboratoires (${selected.labs.length})`, iconButton("i-plus", "Nouveau laboratoire", () => openDrugLab(selected, null)),
                labs.length ? labs : h("p", { class: "hint-line" }, "Aucun laboratoire : la drogue ne peut pas être produite."))
            : sideBlock("Laboratoires", null, h("p", { class: "hint-line" }, "Choisissez une drogue pour voir ses laboratoires."))],
        center: h("div", { class: "items-grid" }, newTile("Nouvelle drogue", () => illegalSwitch(() => { illegalState.drugSel = "new"; }), sel === "new"), tiles),
        editor: drugEditor(selected),
    };
}

function drugEditor(drug) {
    if (!drug && illegalState.drugSel !== "new") return emptySelection("i-sparkle", "Choisissez une drogue ou créez-en une.");
    const d = illegalDraft("drug", drug ? drug.id : "new", drug ? `Drogue ${drug.label}` : "Nouvelle drogue",
        () => (drug ? { item: drug.item, active: drug.active, price: drug.price, xp: drug.xp, influence: drug.influence, cops: drug.cops, volumeMin: drug.volumeMin, volumeMax: drug.volumeMax }
            : { item: "", active: true, price: 100, xp: 5, influence: 1, cops: 0, volumeMin: 1, volumeMax: 5 }),
        saveDrug);
    const problems = drug ? drugProblems(drug) : [];

    return selectionPanel({
        item: d.item, title: drug ? drug.label : "Nouvelle drogue", sub: d.item || "objet à choisir",
        badges: drug ? readyBadge(problems) : null,
        body: [
            readyHint(problems),
            h("div", { class: "section-head" }, "Informations"),
            fieldRow("Objet vendu", draftItem(d, "item", () => paintIllegal())),
            fieldRow("Prix à l'unité ($)", draftNumber(d, "price", 0, 1000000)),
            fieldRow("XP du crew / vente", draftNumber(d, "xp", 0, 10000)),
            fieldRow("Influence / vente", draftNumber(d, "influence", 0, 10000)),
            fieldRow("Policiers en service", draftNumber(d, "cops", 0, 50)),
            fieldRow("Volume min", draftNumber(d, "volumeMin", 1, 100)),
            fieldRow("Volume max", draftNumber(d, "volumeMax", 1, 100)),
            h("div", { class: "mode-list" }, draftToggle(d, "active", "Active", "Désactivée : ni vente ni production.")),
        ],
        actions: [
            drug ? deleteButton(async () => {
                const yes = await confirmBox(`Supprimer ${drug.label} ?`, "La drogue, ses laboratoires et leurs emplacements sont effacés.", "Supprimer", true);
                if (!yes) return;
                const res = await act("drugs.delete", { id: drug.id }, "Drogue supprimée.");
                if (!res) return;
                illegalSaved();
                illegalState.drugSel = null;
                await loadDrugs();
            }) : null,
            drug ? duplicateButton(async () => {
                const res = await act("drugs.duplicate", { id: drug.id }, "Drogue dupliquée (désactivée, sans emplacements).");
                if (!res) return;
                illegalSaved();
                if (res.id) illegalState.drugSel = res.id;
                await loadDrugs();
            }) : null,
            saveButton(saveDrug, !drug),
        ],
    });
}

async function saveDrug() {
    const draft = illegalState.draft;
    if (!draft || draft.kind !== "drug") return;
    const d = draft.data;
    if (!knownItem(d.item)) return toast(`L'objet « ${d.item} » n'existe pas dans ox_inventory.`, "error");
    const creating = draft.key === "new";
    const res = await act("drugs.save", { id: creating ? null : draft.key, ...d }, creating ? "Drogue créée." : "Drogue enregistrée.");
    if (!res) return;
    illegalSaved();
    if (res.id) illegalState.drugSel = res.id;
    await loadDrugs();
    paintIllegal();
}

async function openDrugLab(drug, lab) {
    const items = await loadCatalogItems();
    const known = new Set(items.map((i) => i.name));
    const crewType = h("select", { class: "input" }, drugState.data.crewTypes.map((t) => h("option", { value: t.id, selected: lab && lab.crewType === t.id }, t.label)));
    const output = h("input", { class: "input mono", type: "number", min: "1", value: String(lab ? lab.output : 5) });
    const duration = h("input", { class: "input mono", type: "number", min: "1", value: String(lab ? lab.duration : 30) });
    const ingredients = (lab ? lab.ingredients : [{ item: "", count: 1 }]).map((i) => ({ item: i.item, count: i.count }));
    const list = h("div", { class: "ingredient-list" });
    const paint = () => list.replaceChildren(...ingredients.map((entry, index) => {
        const name = itemPicker(items, entry.item);
        const amount = h("input", { class: "input mono", type: "number", min: "1", value: String(entry.count) });
        name.addEventListener("input", () => { entry.item = name.value.trim(); });
        amount.addEventListener("input", () => { entry.count = Number(amount.value || 1); });
        return h("div", { class: "ingredient-row" }, name, amount,
            h("button", { class: "btn small ghost", disabled: ingredients.length <= 1, onclick: () => { ingredients.splice(index, 1); paint(); } }, icon("i-trash")));
    }));
    paint();

    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), lab ? "Enregistrer" : "Créer");
        submit.addEventListener("click", async () => {
            if (ingredients.some((i) => !known.has(i.item))) return toast("Un ingrédient n'existe pas dans ox_inventory.", "error");
            const res = await drugAct("drugs.saveLab", { drugId: drug.id, labId: lab ? lab.id : null, crewType: crewType.value, output: Number(output.value), duration: Number(duration.value), ingredients },
                lab ? "Laboratoire enregistré." : "Laboratoire créé.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, lab ? "Modifier le laboratoire" : "Nouveau laboratoire"), h("p", null, `${drug.label} · production réservée au type de crew choisi`)),
            h("div", { class: "body event-form" },
                h("div", { class: "field" }, h("label", null, "Type de crew autorisé"), crewType),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, `Quantité produite (${drug.label})`), output),
                    h("div", { class: "field" }, h("label", null, "Durée (secondes)"), duration)),
                h("div", { class: "field" }, h("label", null, "Ingrédients consommés"), list,
                    h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
                        if (ingredients.length >= 10) return toast("10 ingrédients maximum.", "error");
                        ingredients.push({ item: "", count: 1 });
                        paint();
                    } }, icon("i-plus"), "Ajouter un ingrédient"))),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
}
