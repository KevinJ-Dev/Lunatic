"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, onglet Drogues (étape 3)
//  Drogues (prix, XP, influence, policiers, volumes), laboratoires (type de crew, recette) et leurs emplacements.
// ====================================================================

const drugState = { data: null };

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

function drugsPanel() {
    const d = drugState.data;
    if (!d) {
        loadDrugs();
        return h("div", { class: "empty" }, icon("i-mask"), "Chargement des drogues…");
    }

    const cards = d.drugs.map((drug) => {
        const labs = drug.labs.map((lab) => {
            const problems = labProblems(lab);
            const recipe = `${lab.ingredients.map((i) => `${i.count} × ${i.label}`).join(" + ")} → ${lab.output} × ${drug.label} en ${lab.duration} s`;
            const locations = lab.locations.map((l, i) => h("div", { class: "row point-row lab-location" },
                h("span", { class: "pid mono" }, String(i + 1)),
                h("div", { class: "who" }, h("span", null, `${l.x.toFixed(1)}, ${l.y.toFixed(1)}, ${l.z.toFixed(1)}`)),
                h("div", { class: "btn-row" },
                    h("button", { class: "btn small", onclick: () => drugAct("drugs.moveLocation", { locationId: l.id }, "Emplacement replacé à votre position.") }, icon("i-crosshair"), "Définir"),
                    h("button", { class: "btn small ghost", onclick: () => act("drugs.tpLocation", { locationId: l.id }, null) }, icon("i-goto"), "TP"),
                    h("button", { class: "btn small ghost", title: "Supprimer", onclick: () => drugAct("drugs.deleteLocation", { locationId: l.id }, "Emplacement supprimé.") }, icon("i-trash")))));
            return h("div", { class: "lab-block" },
                h("div", { class: "row point-row" },
                    readyDot(problems),
                    h("div", { class: "who" }, h("b", null, `Laboratoire · ${lab.crewTypeLabel}`, readyBadge(problems)), h("span", null, recipe)),
                    h("div", { class: "btn-row" },
                        h("button", { class: "btn small", onclick: () => drugAct("drugs.addLocation", { labId: lab.id }, "Emplacement ajouté à votre position.") }, icon("i-plus"), "Emplacement"),
                        h("button", { class: "btn small ghost", onclick: () => openDrugLab(drug, lab) }, icon("i-edit")),
                        h("button", { class: "btn small ghost", title: "Supprimer le laboratoire", onclick: async () => {
                            const yes = await confirmBox("Supprimer ce laboratoire ?", "Sa recette et ses emplacements sont effacés.", "Supprimer", true);
                            if (yes) drugAct("drugs.deleteLab", { labId: lab.id }, "Laboratoire supprimé.");
                        } }, icon("i-trash")))),
                locations.length ? h("div", { class: "table lab-locations" }, locations) : null,
                problems.length ? h("p", { class: "hint-line", style: "margin:4px 0 0 40px" }, `À compléter : ${problems.join(" · ")}`) : null);
        });

        return h("div", { class: "card", style: "margin-top:16px" },
            h("div", { class: "card-head dev-head" },
                h("div", { class: "drug-title" }, itemImage(drug.item),
                    h("div", { class: "who" }, h("b", null, drug.label, h("span", { class: `badge ${drug.active ? "ok" : "muted"}`, style: "margin-left:8px" }, drug.active ? "Active" : "Désactivée"),
                        drug.missing ? h("span", { class: "badge ban", style: "margin-left:6px" }, "objet inconnu") : null, readyBadge(drugProblems(drug))),
                        h("span", { class: "muted" }, `${drug.item} · ${money(drug.price)} l'unité · ${drug.volumeMin} à ${drug.volumeMax} par vente · ${drug.xp} XP · ${drug.influence} influence · ${drug.cops} policier${drug.cops > 1 ? "s" : ""} min.`))),
                h("div", { class: "btn-row" },
                    h("button", { class: "btn small primary", onclick: () => openDrugLab(drug, null) }, icon("i-plus"), "Laboratoire"),
                    h("button", { class: "btn small ghost", onclick: () => openDrug(drug) }, icon("i-edit"), "Modifier"),
                    h("button", { class: "btn small ghost", title: "Dupliquer (désactivée, sans emplacements)", onclick: () => drugAct("drugs.duplicate", { id: drug.id }, "Drogue dupliquée (désactivée).") }, icon("i-copy")),
                    h("button", { class: "btn small ghost", title: "Supprimer", onclick: async () => {
                        const yes = await confirmBox(`Supprimer ${drug.label} ?`, "La drogue, ses laboratoires et leurs emplacements sont effacés.", "Supprimer", true);
                        if (yes) drugAct("drugs.delete", { id: drug.id }, "Drogue supprimée.");
                    } }, icon("i-trash")))),
            readyHint(drugProblems(drug)),
            labs.length ? h("div", { class: "table" }, labs) : null);
    });

    const readyCount = d.drugs.filter((drug) => drug.active && !drugProblems(drug).length).length;
    return h("div", null,
        h("div", { class: "card" },
            h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, `Drogues (${d.drugs.length})`,
                d.drugs.length ? h("span", { class: `badge ${readyCount ? "ok" : "warn"} ready-badge` }, `${readyCount} prête${readyCount > 1 ? "s" : ""} en jeu`) : null),
                h("div", { class: "btn-row" },
                    h("button", { class: "btn small", title: "Ajoute weed, cocaïne, meth et fentanyl (avec leurs laboratoires) s'ils n'existent pas encore", onclick: async () => {
                        const res = await drugAct("drugs.seed", {}, null);
                        if (res) toast(`${res.created} drogue(s) de départ ajoutée(s) : placez leurs laboratoires (« Emplacement »).`, "ok");
                    } }, icon("i-sparkle"), "Drogues de départ"),
                    h("button", { class: "btn small primary", onclick: () => openDrug(null) }, icon("i-plus"), "Nouvelle drogue"))),
            h("p", { class: "hint-line", style: "margin:0" }, "Vente aux passants en jeu ([E] près d'un PNJ qui marche) ; production dans les laboratoires, réservés à un type de crew. Prix variable de ±15 %, payé en argent sale.")),
        cards);
}

function openDrug(drug) {
    loadCatalogItems().then((items) => {
        const known = new Set(items.map((i) => i.name));
        const item = itemPicker(items, drug ? drug.item : "");
        const num = (value) => h("input", { class: "input mono", type: "number", min: "0", value: String(value) });
        const price = num(drug ? drug.price : 100);
        const xp = num(drug ? drug.xp : 5);
        const influence = num(drug ? drug.influence : 1);
        const cops = num(drug ? drug.cops : 0);
        const volumeMin = num(drug ? drug.volumeMin : 1);
        const volumeMax = num(drug ? drug.volumeMax : 5);
        let active = drug ? drug.active : true;
        const activeRow = h("div", { class: `perm${active ? " on" : ""}` }, h("span", { class: "switch" }), h("span", { class: "txt" }, h("span", null, "Active"), h("code", null, "Désactivée : ni vente ni production.")));
        activeRow.addEventListener("click", () => { active = !active; activeRow.classList.toggle("on", active); });

        openModal((close) => {
            const submit = h("button", { class: "btn primary" }, icon("i-save"), drug ? "Enregistrer" : "Créer");
            submit.addEventListener("click", async () => {
                const name = item.value.trim();
                if (!known.has(name)) return toast(`L'objet « ${name} » n'existe pas dans ox_inventory.`, "error");
                const res = await drugAct("drugs.save", {
                    id: drug ? drug.id : null, item: name, active, price: Number(price.value), xp: Number(xp.value), influence: Number(influence.value),
                    cops: Number(cops.value), volumeMin: Number(volumeMin.value), volumeMax: Number(volumeMax.value),
                }, drug ? "Drogue enregistrée." : "Drogue créée.");
                if (res) close();
            });
            return [
                h("header", null, h("h3", null, drug ? `Modifier ${drug.label}` : "Nouvelle drogue")),
                h("div", { class: "body event-form" },
                    h("div", { class: "field" }, h("label", null, "Objet vendu"), item),
                    h("div", { class: "event-form-row" },
                        h("div", { class: "field" }, h("label", null, "Prix de base à l'unité ($)"), price),
                        h("div", { class: "field" }, h("label", null, "Policiers en service requis"), cops)),
                    h("div", { class: "event-form-row" },
                        h("div", { class: "field" }, h("label", null, "Volume min par vente"), volumeMin),
                        h("div", { class: "field" }, h("label", null, "Volume max par vente"), volumeMax)),
                    h("div", { class: "event-form-row" },
                        h("div", { class: "field" }, h("label", null, "XP du crew par vente"), xp),
                        h("div", { class: "field" }, h("label", null, "Influence par vente"), influence)),
                    h("div", { class: "mode-list" }, activeRow)),
                h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
            ];
        });
        item.focus();
    });
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
