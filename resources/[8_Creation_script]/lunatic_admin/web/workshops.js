"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, onglet Craft d'armes (étape 5)
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

function workshopsPanel() {
    const d = workshopState.data;
    if (!d) {
        loadWorkshops();
        return h("div", { class: "empty" }, icon("i-tool"), "Chargement des ateliers…");
    }

    const cards = d.workshops.map((w) => {
        const problems = workshopProblems(w);
        const recipes = w.recipes.map((r) => h("div", { class: "row catalog-row" },
            itemImage(r.item),
            h("div", { class: "who" },
                h("b", null, `${r.count > 1 ? `${r.count} × ` : ""}${r.label}`, r.missing ? h("span", { class: "badge ban", style: "margin-left:6px" }, "objet inconnu") : null,
                    h("span", { class: "badge muted ready-badge" }, `level ${Math.max(w.minLevel, r.minLevel)}+`)),
                h("span", null, `${r.ingredients.map((i) => `${i.count} × ${i.label}`).join(" + ")} · ${r.duration} s · ${r.xp} XP`)),
            h("div", { class: "btn-row" },
                h("button", { class: "btn small ghost", onclick: () => openWorkshopRecipe(w, r) }, icon("i-edit"), "Modifier"),
                h("button", { class: "btn small ghost", title: "Supprimer", onclick: async () => {
                    const yes = await confirmBox(`Retirer « ${r.label} » ?`, "La recette disparaît de l'atelier.", "Retirer", true);
                    if (yes) workshopAct("workshops.deleteRecipe", { recipeId: r.id }, "Recette retirée.");
                } }, icon("i-trash")))));

        const locations = w.locations.map((l, i) => h("div", { class: "row point-row" },
            h("span", { class: "pid mono" }, String(i + 1)),
            h("div", { class: "who" }, h("span", null, `${l.x.toFixed(1)}, ${l.y.toFixed(1)}, ${l.z.toFixed(1)}`)),
            h("div", { class: "btn-row" },
                h("button", { class: "btn small", onclick: () => workshopAct("workshops.moveLocation", { locationId: l.id }, "Emplacement replacé à votre position.") }, icon("i-crosshair"), "Définir"),
                h("button", { class: "btn small ghost", onclick: () => act("workshops.tpLocation", { locationId: l.id }, null) }, icon("i-goto"), "TP"),
                h("button", { class: "btn small ghost", title: "Supprimer", onclick: () => workshopAct("workshops.deleteLocation", { locationId: l.id }, "Emplacement supprimé.") }, icon("i-trash")))));

        return h("div", { class: "card", style: "margin-top:16px" },
            h("div", { class: "card-head dev-head" },
                h("div", { class: "drug-title" },
                    h("div", { class: "who" },
                        h("b", null, w.label, readyBadge(problems)),
                        h("span", { class: "muted" }, `${w.crewTypes.map(crewTypeLabel).join(", ")} · level ${w.minLevel}+ · ${w.alert ? "alerte police possible" : "sans alerte police"}`))),
                h("div", { class: "btn-row" },
                    h("button", { class: "btn small primary", onclick: () => openWorkshopRecipe(w, null) }, icon("i-plus"), "Recette"),
                    h("button", { class: "btn small", onclick: () => workshopAct("workshops.addLocation", { id: w.id }, "Emplacement ajouté à votre position.") }, icon("i-plus"), "Emplacement"),
                    h("button", { class: "btn small ghost", onclick: () => openWorkshop(w) }, icon("i-edit"), "Modifier"),
                    h("button", { class: "btn small ghost", title: "Supprimer l'atelier", onclick: async () => {
                        const yes = await confirmBox(`Supprimer « ${w.label} » ?`, "L'atelier, ses recettes et ses emplacements sont effacés.", "Supprimer", true);
                        if (yes) workshopAct("workshops.delete", { id: w.id }, "Atelier supprimé.");
                    } }, icon("i-trash")))),
            readyHint(problems),
            recipes.length ? h("div", { class: "table" }, recipes) : null,
            locations.length ? h("div", null, h("div", { class: "section-head", style: "margin-top:14px" }, "Emplacements"), h("div", { class: "table" }, locations)) : null);
    });

    return h("div", null,
        h("div", { class: "card" },
            h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, `Ateliers (${d.workshops.length})`),
                h("div", { class: "btn-row" },
                    h("button", { class: `btn small${workshopState.staffView ? " primary" : ""}`, title: "Affiche en jeu tous les ateliers (en orange), même sans être dans un crew autorisé", onclick: async () => {
                        const enabled = !workshopState.staffView;
                        const res = await act("workshops.staffView", { enabled }, null);
                        if (!res) return;
                        workshopState.staffView = enabled;
                        paintIllegal();
                    } }, icon("i-eye"), workshopState.staffView ? "Masquer les ateliers en jeu" : "Voir les ateliers en jeu"),
                    h("button", { class: "btn small", title: "Crée un atelier avec pistolets, mitraillette, fusil et munitions (pièces d'armes et ferraille)", onclick: async () => {
                        const res = await workshopAct("workshops.seed", {}, null);
                        if (res) toast(`Atelier de départ créé (${res.created} recette${res.created > 1 ? "s" : ""}) : placez son emplacement.`, "ok");
                    } }, icon("i-sparkle"), "Atelier de départ"),
                    h("button", { class: "btn small primary", onclick: () => openWorkshop(null) }, icon("i-plus"), "Nouvel atelier"))),
            h("p", { class: "hint-line", style: "margin:0" }, "Les membres des crews autorisés fabriquent à l'atelier ([E]) : ingrédients consommés, objet donné à la fin, XP au crew. Les armes fabriquées n'ont pas de numéro de série. Le level requis d'une recette est le plus haut entre celui de l'atelier et le sien.")),
        d.workshops.length ? cards : h("div", { class: "card", style: "margin-top:16px" }, h("p", { class: "hint-line", style: "margin:0" }, "Aucun atelier : « Atelier de départ » en crée un tout prêt, ou « Nouvel atelier »."))
    );
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

async function openWorkshopRecipe(w, r) {
    const items = await loadCatalogItems();
    const known = new Set(items.map((i) => i.name));
    const d = workshopState.data;
    const item = itemPicker(items, r ? r.item : "");
    const num = (value, min, max) => h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(value) });
    const count = num(r ? r.count : 1, 1, 500);
    const duration = num(r ? r.duration : 60, 1, 900);
    const minLevel = num(r ? r.minLevel : 1, 1, d.maxLevel);
    const xp = num(r ? r.xp : 10, 0, 10000);
    const ingredients = (r ? r.ingredients : [{ item: "", count: 1 }]).map((i) => ({ item: i.item, count: i.count }));
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
        const submit = h("button", { class: "btn primary" }, icon("i-save"), r ? "Enregistrer" : "Ajouter");
        submit.addEventListener("click", async () => {
            const name = item.value.trim();
            if (!known.has(name)) return toast(`L'objet « ${name} » n'existe pas dans ox_inventory.`, "error");
            if (ingredients.some((i) => !known.has(i.item))) return toast("Un ingrédient n'existe pas dans ox_inventory.", "error");
            const res = await workshopAct("workshops.saveRecipe", {
                workshopId: w.id, recipeId: r ? r.id : null, item: name, count: Number(count.value), duration: Number(duration.value),
                minLevel: Number(minLevel.value), xp: Number(xp.value), ingredients,
            }, r ? "Recette enregistrée." : "Recette ajoutée.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, r ? "Modifier la recette" : "Nouvelle recette"), h("p", null, `${w.label} · armes (WEAPON_…), munitions (ammo-…) ou tout autre objet`)),
            h("div", { class: "body event-form" },
                h("div", { class: "field" }, h("label", null, "Objet fabriqué"), item),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Quantité"), count),
                    h("div", { class: "field" }, h("label", null, "Durée (secondes)"), duration)),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Level de crew minimum"), minLevel),
                    h("div", { class: "field" }, h("label", null, "XP du crew par fabrication"), xp)),
                h("div", { class: "field" }, h("label", null, "Ingrédients consommés"), list,
                    h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
                        if (ingredients.length >= 10) return toast("10 ingrédients maximum.", "error");
                        ingredients.push({ item: "", count: 1 });
                        paint();
                    } }, icon("i-plus"), "Ajouter un ingrédient"))),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    item.focus();
}
