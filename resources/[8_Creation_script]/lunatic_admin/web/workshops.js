"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, page Craft (ateliers à gauche, recettes au centre, fiche à droite)
//  Ateliers (types de crew, level minimum, alerte police, emplacements) et leurs recettes.
// ====================================================================

const workshopState = { data: null, staffView: false };

async function loadWorkshops() {
    const res = await nui("action", { action: "workshops.info", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    workshopState.data = res;
    if (illegalState.tab === "craft") paintIllegal();
}

async function workshopAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) await loadWorkshops();
    return res;
}

const crewTypeLabel = (id) => ((workshopState.data && workshopState.data.crewTypes) || []).find((t) => t.id === id)?.label || id;

// Ce qui empêche un atelier de servir en jeu
function workshopProblems(w) {
    const problems = [];
    const counts = workshopState.data.crewCounts || {};
    if (!w.locations.length) problems.push("aucun emplacement");
    if (!w.recipes.length) problems.push("aucune recette");
    if (!w.crewTypes.some((t) => counts[t])) problems.push("aucun crew des types autorisés");
    const unknown = w.recipes.filter((r) => r.missing || r.ingredients.some((i) => i.missing)).length;
    if (unknown) problems.push(`${unknown} recette${unknown > 1 ? "s" : ""} avec un objet inconnu`);
    return problems;
}

function workshopsPage() {
    const d = workshopState.data;
    if (!d) {
        loadWorkshops();
        return illegalLoading("Craft", "i-tool", "Chargement des ateliers…");
    }
    // Atelier affiché : celui choisi, sinon le premier
    const w = d.workshops.find((entry) => entry.id === illegalState.craftWorkshop) || d.workshops[0] || null;
    if (w) illegalState.craftWorkshop = w.id;
    const sel = illegalState.craftRecipe;
    const recipe = w && w.recipes.find((r) => r.id === sel);

    const workshops = d.workshops.map((entry) => h("button", { class: `list-row${w && entry.id === w.id ? " active" : ""}`, onclick: () => entry.id !== w.id && illegalSwitch(() => { illegalState.craftWorkshop = entry.id; illegalState.craftRecipe = null; }) },
        readyDot(workshopProblems(entry)), h("span", { class: "name" }, entry.label), h("span", { class: "cnt" }, String(entry.recipes.length))));

    const side = [sideBlock(`Ateliers (${d.workshops.length})`, iconButton("i-plus", "Nouvel atelier", () => openWorkshop(null)),
        workshops.length ? workshops : h("p", { class: "hint-line" }, "Aucun atelier : « Atelier de départ » en crée un tout prêt."))];

    if (w) {
        const problems = workshopProblems(w);
        const locations = w.locations.map((l, i) => pointLine(i + 1, null, l, [
            iconButton("i-crosshair", "Replacer à votre position", () => workshopAct("workshops.moveLocation", { locationId: l.id }, "Emplacement replacé à votre position.")),
            iconButton("i-goto", "TP", () => act("workshops.tpLocation", { locationId: l.id }, null)),
            iconButton("i-trash", "Supprimer", () => workshopAct("workshops.deleteLocation", { locationId: l.id }, "Emplacement supprimé.")),
        ]));
        side.push(
            sideBlock("Atelier", h("div", { class: "btn-row" },
                iconButton("i-edit", "Modifier l'atelier", () => openWorkshop(w)),
                iconButton("i-trash", "Supprimer l'atelier", async () => {
                    const yes = await confirmBox(`Supprimer « ${w.label} » ?`, "L'atelier, ses recettes et ses emplacements sont effacés.", "Supprimer", true);
                    if (!yes) return;
                    illegalSaved();
                    illegalState.craftWorkshop = null;
                    illegalState.craftRecipe = null;
                    workshopAct("workshops.delete", { id: w.id }, "Atelier supprimé.");
                })),
                h("div", { class: "side-facts" },
                    h("span", null, "Types de crew"), h("b", null, w.crewTypes.map(crewTypeLabel).join(", ") || "aucun"),
                    h("span", null, "Level minimum"), h("b", null, String(w.minLevel)),
                    h("span", null, "Alerte police"), h("b", null, w.alert ? "possible" : "non")),
                problems.length ? h("span", { class: "side-card-warn" }, `À compléter : ${problems.join(" · ")}`) : null),
            sideBlock(`Points de craft (${w.locations.length})`, iconButton("i-plus", "Ajouter un point à votre position", () => workshopAct("workshops.addLocation", { id: w.id }, "Emplacement ajouté à votre position.")),
                locations.length ? locations : h("p", { class: "hint-line" }, "Aucun point : personne ne peut fabriquer ici.")));
    }

    const tiles = w ? w.recipes.map((r) => illegalTile({
        item: r.item, label: `${r.count > 1 ? `${r.count} × ` : ""}${r.label}`, badge: `Lv ${Math.max(w.minLevel, r.minLevel)}`, active: r.id === sel, warn: r.missing || r.ingredients.some((i) => i.missing),
        onclick: () => r.id !== sel && illegalSwitch(() => { illegalState.craftRecipe = r.id; }),
    })) : [];

    // Ingrédients de la recette choisie, en cases sous la grille
    const ingredients = recipe ? h("div", null,
        h("div", { class: "section-head", style: "margin-top:22px" }, `Ingrédients · ${recipe.label}`),
        h("div", { class: "items-grid" }, recipe.ingredients.map((i) => illegalTile({ item: i.item, label: i.label, badge: `× ${i.count}`, warn: i.missing, onclick: null })))) : null;

    return {
        title: w ? w.label : "Craft",
        sub: "Les membres des crews autorisés fabriquent au point de craft ([E]) : ingrédients consommés, objet donné à la fin, XP au crew. Armes sans numéro de série.",
        actions: [
            h("button", { class: `btn small${workshopState.staffView ? " primary" : ""}`, title: "Affiche en jeu tous les ateliers (en orange), même sans être dans un crew autorisé", onclick: async () => {
                const enabled = !workshopState.staffView;
                const res = await act("workshops.staffView", { enabled }, null);
                if (!res) return;
                workshopState.staffView = enabled;
                paintIllegal();
            } }, icon("i-eye"), workshopState.staffView ? "Masquer les ateliers" : "Voir les ateliers en jeu"),
            h("button", { class: "btn small", title: "Crée un atelier avec pistolets, mitraillette, fusil et munitions (pièces d'armes et ferraille)", onclick: async () => {
                const res = await workshopAct("workshops.seed", {}, null);
                if (res) toast(`Atelier de départ créé (${res.created} recette${res.created > 1 ? "s" : ""}) : placez son point de craft.`, "ok");
            } }, icon("i-sparkle"), "Atelier de départ"),
        ],
        side,
        center: w ? h("div", null,
            h("div", { class: "items-grid" }, newTile("Nouvelle recette", () => illegalSwitch(() => { illegalState.craftRecipe = "new"; }), sel === "new"), tiles),
            ingredients)
            : h("div", { class: "empty" }, icon("i-tool"), "Aucun atelier. Créez-en un avec le + à gauche, ou « Atelier de départ »."),
        editor: w ? recipeEditor(w, recipe) : null,
    };
}

function recipeEditor(w, r) {
    if (!r && illegalState.craftRecipe !== "new") return emptySelection("i-tool", "Choisissez une recette ou créez-en une.");
    const max = workshopState.data.maxLevel;
    const d = illegalDraft("recipe", r ? r.id : "new", r ? `Recette ${r.label}` : "Nouvelle recette",
        () => (r ? { item: r.item, count: r.count, duration: r.duration, minLevel: r.minLevel, xp: r.xp, ingredients: r.ingredients.map((i) => ({ item: i.item, count: i.count })) }
            : { item: "", count: 1, duration: 60, minLevel: 1, xp: 10, ingredients: [{ item: "", count: 1 }] }),
        saveRecipe);

    return selectionPanel({
        item: d.item, title: r ? r.label : "Nouvelle recette", sub: d.item || "objet à choisir",
        badges: h("span", { class: "badge muted", style: "justify-self:start" }, w.label),
        body: [
            h("div", { class: "section-head" }, "Informations"),
            fieldRow("Objet fabriqué", draftItem(d, "item", () => paintIllegal())),
            fieldRow("Quantité", draftNumber(d, "count", 1, 500)),
            fieldRow("Durée (secondes)", draftNumber(d, "duration", 1, 900)),
            fieldRow(`Level min (1 à ${max})`, draftNumber(d, "minLevel", 1, max)),
            fieldRow("XP du crew", draftNumber(d, "xp", 0, 10000)),
            h("p", { class: "hint-line" }, `Level requis : le plus haut entre celui de l'atelier (${w.minLevel}) et celui de la recette.`),
            h("div", { class: "section-head", style: "margin-top:10px" }, `Ingrédients (${d.ingredients.length}/10)`),
            draftIngredients(d),
        ],
        actions: [
            r ? deleteButton(async () => {
                const yes = await confirmBox(`Retirer « ${r.label} » ?`, "La recette disparaît de l'atelier.", "Retirer", true);
                if (!yes) return;
                const res = await act("workshops.deleteRecipe", { recipeId: r.id }, "Recette retirée.");
                if (!res) return;
                illegalSaved();
                illegalState.craftRecipe = null;
                await loadWorkshops();
            }) : null,
            r ? duplicateButton(() => illegalSwitch(() => { illegalState.craftRecipe = "new"; illegalState.prefill = { ...d, ingredients: d.ingredients.map((i) => ({ ...i })) }; })) : null,
            saveButton(saveRecipe, !r),
        ],
    });
}

async function saveRecipe() {
    const draft = illegalState.draft;
    if (!draft || draft.kind !== "recipe") return;
    const d = draft.data;
    if (!knownItem(d.item)) return toast(`L'objet « ${d.item} » n'existe pas dans ox_inventory.`, "error");
    if (d.ingredients.some((i) => !knownItem(i.item))) return toast("Un ingrédient n'existe pas dans ox_inventory.", "error");
    const creating = draft.key === "new";
    const workshopId = illegalState.craftWorkshop;
    const res = await act("workshops.saveRecipe", { workshopId, recipeId: creating ? null : draft.key, ...d }, creating ? "Recette ajoutée." : "Recette enregistrée.");
    if (!res) return;
    illegalSaved();
    await loadWorkshops();
    if (creating) {
        const w = workshopState.data.workshops.find((entry) => entry.id === workshopId);
        const added = w && latestOf(w.recipes.filter((r) => r.item === d.item));
        illegalState.craftRecipe = added ? added.id : null;
    }
    paintIllegal();
}

function openWorkshop(w) {
    const d = workshopState.data;
    const label = h("input", { class: "input", maxlength: "60", placeholder: "Ex. Atelier du port", value: w ? w.label : "" });
    const minLevel = h("input", { class: "input mono", type: "number", min: "1", max: String(d.maxLevel), value: String(w ? w.minLevel : 1) });
    const types = new Set(w ? w.crewTypes : d.crewTypes.map((t) => t.id));
    let alert = w ? w.alert : true;

    const typeRows = d.crewTypes.map((t) => {
        const row = h("div", { class: `perm${types.has(t.id) ? " on" : ""}` }, h("span", { class: "switch" }), h("span", { class: "txt" }, h("span", null, t.label), h("code", null, `${(d.crewCounts || {})[t.id] || 0} crew(s)`)));
        row.addEventListener("click", () => {
            if (types.has(t.id)) types.delete(t.id);
            else types.add(t.id);
            row.classList.toggle("on", types.has(t.id));
        });
        return row;
    });
    const alertRow = h("div", { class: `perm${alert ? " on" : ""}` }, h("span", { class: "switch" }), h("span", { class: "txt" }, h("span", null, "Alerte police possible"), h("code", null, "Une fabrication peut signaler le secteur à la police.")));
    alertRow.addEventListener("click", () => { alert = !alert; alertRow.classList.toggle("on", alert); });

    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), w ? "Enregistrer" : "Créer");
        submit.addEventListener("click", async () => {
            const res = await workshopAct("workshops.save", { id: w ? w.id : null, label: label.value.trim(), crewTypes: [...types], minLevel: Number(minLevel.value), alert },
                w ? "Atelier enregistré." : "Atelier créé : ajoutez un emplacement et des recettes.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, w ? `Modifier ${w.label}` : "Nouvel atelier")),
            h("div", { class: "body event-form" },
                h("div", { class: "field" }, h("label", null, "Nom"), label),
                h("div", { class: "field" }, h("label", null, `Level de crew minimum (1 à ${d.maxLevel})`), minLevel),
                h("div", { class: "field" }, h("label", null, "Types de crew autorisés"), h("div", { class: "mode-list" }, typeRows)),
                h("div", { class: "mode-list" }, alertRow)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    label.focus();
}

