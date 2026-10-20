"use strict";

// ====================================================================
//  lunatic_admin — lot E3 : onglet Catalogues de la fiche d'une structure
//  Équipement (membres selon le grade, payé par la société) et Craft (recettes).
//  Utilisé par web/structures.js ; les magasins automatiques sont dans web/shops.js.
// ====================================================================

const CATALOG_KINDS = [
    { value: "equipment", label: "Équipement", help: "Membres seulement, aux points Catalogue et Armurerie, selon un grade minimum. Payé par le compte de la société (prix 0 = gratuit)." },
    { value: "craft", label: "Craft", help: "Recettes des membres au point Craft : ingrédients consommés, objet fabriqué après la durée indiquée." },
];
const catalogKindLabel = (kind) => (CATALOG_KINDS.find((k) => k.value === kind) || {}).label || kind;

let catalogItems = null;

async function loadCatalogItems() {
    if (catalogItems) return catalogItems;
    const res = await nui("action", { action: "catalogs.items", payload: {} }).catch(() => null);
    catalogItems = res && res.ok ? res.items : [];
    return catalogItems;
}

// Champ objet avec la liste des objets d'ox_inventory (datalist partagée)
function itemPicker(items, value) {
    const listId = "catalog-items";
    if (!document.getElementById(listId)) {
        document.body.append(h("datalist", { id: listId }, items.map((i) => h("option", { value: i.name }, i.label))));
    }
    return h("input", { class: "input mono", list: listId, maxlength: "60", placeholder: "nom de l'objet (ex. burger)", value: value || "" });
}

const itemImage = (name) => h("img", { class: "item-img", src: `nui://ox_inventory/web/images/${name}.png`, alt: "", onerror: (e) => { e.target.style.visibility = "hidden"; } });

function structureCatalogsCard(info, doAct) {
    const linked = info.catalogs || [];
    const linkedIds = new Set(linked.map((c) => c.id));
    const shared = (info.allCatalogs || []).filter((c) => !linkedIds.has(c.id));

    const header = h("div", { class: "card" },
        h("div", { class: "card-head dev-head" },
            h("h3", { class: "card-title" }, `Catalogues (${linked.length})`),
            h("button", { class: "btn small primary", onclick: () => openCreateStructureCatalog(info, doAct) }, icon("i-plus"), "Nouveau catalogue")),
        h("p", { class: "hint-line", style: "margin:0" }, "Équipement : points Catalogue et Armurerie. Craft : point Craft. Un catalogue peut être partagé entre plusieurs structures (ex. armurerie commune à la police)."),
        shared.length ? h("div", { class: "spawn-row", style: "margin-top:12px" },
            (() => {
                const select = h("select", { class: "input" }, shared.map((c) => h("option", { value: String(c.id) }, `${c.label} (${c.kindLabel})`)));
                return [select, h("button", { class: "btn", onclick: () => doAct("catalogs.link", { id: Number(select.value), job: info.name, linked: true }, "Catalogue partagé rattaché.") }, icon("i-plus"), "Rattacher un catalogue existant")];
            })()) : null
    );

    return h("div", null, header, linked.map((c) => catalogCard(info, c, doAct)));
}

// Équipement : il faut un point Catalogue ou Armurerie ; Craft : un point Craft
function catalogProblems(info, c) {
    const problems = [];
    const types = new Set((info.points || []).map((p) => p.type));
    if (!c.lines.length) problems.push("catalogue vide");
    if (c.kind === "craft" && !types.has("craft")) problems.push("aucun point Craft placé");
    if (c.kind !== "craft" && !types.has("catalog") && !types.has("armory")) problems.push("aucun point Catalogue ou Armurerie placé");
    const unknown = c.lines.filter((l) => l.missing).length;
    if (unknown) problems.push(`${unknown} objet${unknown > 1 ? "s" : ""} inconnu${unknown > 1 ? "s" : ""}`);
    return problems;
}

function catalogCard(info, c, doAct) {
    const craft = c.kind === "craft";
    const problems = catalogProblems(info, c);
    const rows = c.lines.map((line) => {
        const details = craft
            ? `${line.ingredients.map((i) => `${i.count} × ${i.label}`).join(" + ")} · ${line.duration} s${line.minGrade ? ` · grade ${line.minGrade}+` : ""}`
            : `${line.price ? money(line.price) : "Gratuit"}${line.minGrade ? ` · grade ${line.minGrade}+` : ""}`;
        return h("div", { class: "row catalog-row" },
            itemImage(line.item),
            h("div", { class: "who" }, h("b", null, `${line.count > 1 ? `${line.count} × ` : ""}${line.label}`, line.missing ? h("span", { class: "badge ban" }, "objet inconnu") : null),
                h("span", null, `${line.item} · ${details}`)),
            h("div", { class: "btn-row" },
                h("button", { class: "btn small ghost", onclick: () => openCatalogLine(c, line, doAct) }, icon("i-edit"), "Modifier"),
                h("button", { class: "btn small ghost", title: "Supprimer", onclick: async () => {
                    const yes = await confirmBox(`Supprimer « ${line.label} » ?`, "La ligne disparaît du catalogue en jeu.", "Supprimer", true);
                    if (yes) doAct("catalogs.deleteLine", { catalogId: c.id, lineId: line.id }, "Ligne supprimée.");
                } }, icon("i-trash")))
        );
    });

    return h("div", { class: "card", style: "margin-top:16px" },
        h("div", { class: "card-head dev-head" },
            h("h3", { class: "card-title" }, c.label, h("span", { class: "badge muted", style: "margin-left:8px" }, c.kindLabel), readyBadge(problems),
                c.shared ? h("span", { class: "badge jail", style: "margin-left:6px" }, `partagé avec ${c.shared} autre${c.shared > 1 ? "s" : ""}`) : null),
            h("div", { class: "btn-row" },
                h("button", { class: "btn small primary", onclick: () => openCatalogLine(c, null, doAct) }, icon("i-plus"), craft ? "Recette" : "Article"),
                h("button", { class: "btn small ghost", title: "Renommer", onclick: () => renameStructureCatalog(c, doAct) }, icon("i-edit")),
                c.shared ? h("button", { class: "btn small ghost", title: "Détacher de cette structure", onclick: () => doAct("catalogs.link", { id: c.id, job: info.name, linked: false }, "Catalogue détaché.") }, icon("i-x")) : null,
                h("button", { class: "btn small ghost", title: "Supprimer le catalogue", onclick: async () => {
                    const yes = await confirmBox(`Supprimer « ${c.label} » ?`, c.shared ? "Il est partagé : il disparaît aussi pour les autres structures. Action définitive." : "Le catalogue et ses lignes sont effacés. Action définitive.", "Supprimer", true);
                    if (yes) doAct("catalogs.delete", { id: c.id }, "Catalogue supprimé.");
                } }, icon("i-trash")))),
        readyHint(problems),
        rows.length ? h("div", { class: "table" }, rows) : null
    );
}

function openCreateStructureCatalog(info, doAct) {
    let kind = "equipment";
    const label = h("input", { class: "input", maxlength: "60", placeholder: "Ex. Armurerie, Cuisine" });
    const seg = h("div", { class: "segmented" });
    const help = h("p", { class: "hint-line" });
    const paint = () => {
        seg.replaceChildren(...segmentedButtons(CATALOG_KINDS.map((k) => ({ value: k.value, label: k.label })), kind, (v) => { kind = v; paint(); }));
        help.textContent = CATALOG_KINDS.find((k) => k.value === kind).help;
    };
    paint();
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-plus"), "Créer");
        submit.addEventListener("click", async () => {
            const res = await doAct("catalogs.create", { job: info.name, label: label.value.trim(), kind }, "Catalogue créé.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, "Nouveau catalogue"), h("p", null, info.label)),
            h("div", { class: "body event-form" },
                h("div", { class: "field" }, h("label", null, "Nom"), label),
                h("div", { class: "field" }, h("label", null, "Type"), seg, help)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    label.focus();
}

function renameStructureCatalog(c, doAct) {
    const input = h("input", { class: "input", maxlength: "60", value: c.label });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Renommer");
        submit.addEventListener("click", async () => {
            const res = await doAct("catalogs.rename", { id: c.id, label: input.value.trim() }, "Catalogue renommé.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, "Renommer le catalogue")),
            h("div", { class: "body" }, input),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    input.focus();
}

// Article (équipement) ou recette (craft)
async function openCatalogLine(c, line, doAct) {
    const items = await loadCatalogItems();
    const known = new Set(items.map((i) => i.name));
    const craft = c.kind === "craft";

    const item = itemPicker(items, line && line.item);
    const count = h("input", { class: "input mono", type: "number", min: "1", value: String(line ? line.count : 1) });
    const price = h("input", { class: "input mono", type: "number", min: "0", value: String(line ? line.price : 0) });
    const grade = h("input", { class: "input mono", type: "number", min: "0", value: String(line ? line.minGrade : 0) });
    const duration = h("input", { class: "input mono", type: "number", min: "1", value: String(line ? line.duration : 10) });

    const ingredients = (line ? line.ingredients : []).map((i) => ({ item: i.item, count: i.count }));
    if (craft && !ingredients.length) ingredients.push({ item: "", count: 1 });
    const ingredientList = h("div", { class: "ingredient-list" });
    const paintIngredients = () => ingredientList.replaceChildren(...ingredients.map((entry, index) => {
        const name = itemPicker(items, entry.item);
        const amount = h("input", { class: "input mono", type: "number", min: "1", value: String(entry.count) });
        name.addEventListener("input", () => { entry.item = name.value.trim(); });
        amount.addEventListener("input", () => { entry.count = Number(amount.value || 1); });
        return h("div", { class: "ingredient-row" }, name, amount,
            h("button", { class: "btn small ghost", disabled: ingredients.length <= 1, onclick: () => { ingredients.splice(index, 1); paintIngredients(); } }, icon("i-trash")));
    }));
    paintIngredients();

    const fields = [
        h("div", { class: "field" }, h("label", null, craft ? "Objet fabriqué" : "Objet"), item),
        h("div", { class: "event-form-row" },
            h("div", { class: "field" }, h("label", null, craft ? "Quantité fabriquée" : "Quantité donnée"), count),
            craft ? h("div", { class: "field" }, h("label", null, "Durée (secondes)"), duration) : h("div", { class: "field" }, h("label", null, "Prix pour la société ($)"), price)),
        h("div", { class: "field" }, h("label", null, "Grade minimum (0 = tous les membres)"), grade),
    ];
    if (craft) {
        fields.push(h("div", { class: "field" }, h("label", null, "Ingrédients consommés"), ingredientList,
            h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
                if (ingredients.length >= 10) return toast("10 ingrédients maximum.", "error");
                ingredients.push({ item: "", count: 1 });
                paintIngredients();
            } }, icon("i-plus"), "Ajouter un ingrédient")));
    }

    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), line ? "Enregistrer" : "Ajouter");
        submit.addEventListener("click", async () => {
            const name = item.value.trim();
            if (!known.has(name)) return toast(`L'objet « ${name} » n'existe pas dans ox_inventory.`, "error");
            if (craft && ingredients.some((i) => !known.has(i.item))) return toast("Un ingrédient n'existe pas dans ox_inventory.", "error");
            const res = await doAct("catalogs.saveLine", {
                catalogId: c.id, lineId: line ? line.id : null, item: name, count: Number(count.value), price: Number(price.value),
                minGrade: Number(grade.value), duration: Number(duration.value), ingredients,
            }, line ? "Ligne enregistrée." : "Ligne ajoutée.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, line ? "Modifier la ligne" : craft ? "Nouvelle recette" : "Nouvel article"), h("p", null, `${c.label} · ${catalogKindLabel(c.kind)}`)),
            h("div", { class: "body event-form" }, fields),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    item.focus();
}
