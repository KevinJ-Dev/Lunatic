"use strict";

// ====================================================================
//  lunatic_admin — lot E3 : tuile Catalogues
//  Boutique (clients), Équipement (membres, payé par la société), Craft (recettes).
// ====================================================================

const CATALOG_KINDS = [
    { value: "shop", label: "Boutique", help: "Ouverte à tous au point Catalogue. Le client paie (liquide ou banque), l'argent va sur le compte de la société." },
    { value: "equipment", label: "Équipement", help: "Réservé aux membres selon leur grade, aux points Catalogue et Armurerie. Payé par le compte de la société (prix 0 = gratuit)." },
    { value: "craft", label: "Craft", help: "Recettes des membres au point Craft : les ingrédients sont consommés, l'objet est fabriqué après la durée indiquée." },
];
const catalogKindLabel = (kind) => (CATALOG_KINDS.find((k) => k.value === kind) || {}).label || kind;

const catState = { dom: null, list: null, filter: "", selected: null, info: null, structures: [], items: null, loadedAt: 0 };

function renderCatalogs() {
    const root = $("view-catalogs");

    if (!catState.dom || !root.contains(catState.dom.list)) {
        const search = h("input", { placeholder: "Rechercher un catalogue", value: catState.filter });
        search.addEventListener("input", () => { catState.filter = search.value; paintCatalogList(); });
        catState.dom = { count: h("span", { class: "muted mono" }), list: h("div", { class: "side-scroll" }), fiche: h("div", { class: "content" }) };
        root.replaceChildren(
            h("aside", { class: "sidebar" },
                h("div", { class: "side-head" }, h("h3", null, "Catalogues"), catState.dom.count),
                h("div", { class: "side-search" }, h("label", { class: "search" }, icon("i-search"), search)),
                catState.dom.list,
                h("div", { class: "side-foot" }, h("button", { class: "btn primary", style: "width:100%", onclick: openCreateCatalog }, icon("i-plus"), "Créer un catalogue"))
            ),
            catState.dom.fiche
        );
        paintCatalogList();
        paintCatalogFiche();
    }

    if (Date.now() - catState.loadedAt > 10000) loadCatalogs();
}

async function loadCatalogs() {
    catState.loadedAt = Date.now();
    const res = await nui("action", { action: "catalogs.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    catState.list = res.catalogs || [];
    if (catState.dom) paintCatalogList();
}

async function loadCatalogItems() {
    if (catState.items) return catState.items;
    const res = await nui("action", { action: "catalogs.items", payload: {} }).catch(() => null);
    catState.items = res && res.ok ? res.items : [];
    return catState.items;
}

function paintCatalogList() {
    if (!catState.dom) return;
    if (!catState.list) return catState.dom.list.replaceChildren(h("div", { class: "muted side-empty" }, "Chargement…"));
    const text = catState.filter.trim().toLowerCase();
    const rows = catState.list.filter((c) => !text || c.label.toLowerCase().includes(text) || (c.kindLabel || "").toLowerCase().includes(text));
    catState.dom.count.textContent = String(catState.list.length);
    catState.dom.list.replaceChildren(...(rows.length ? rows.map((c) =>
        h("button", { class: `list-row player-row${c.id === catState.selected ? " active" : ""}`, onclick: () => selectCatalog(c.id) },
            h("span", { class: "who" }, h("b", null, c.label),
                h("span", null, `${c.kindLabel} · ${c.lines} ligne${c.lines > 1 ? "s" : ""} · ${c.structures} structure${c.structures > 1 ? "s" : ""}`)))
    ) : [h("div", { class: "muted side-empty" }, catState.list.length ? "Aucun résultat." : "Aucun catalogue pour l'instant.")]));
}

function selectCatalog(id) {
    catState.selected = id;
    catState.info = null;
    paintCatalogList();
    paintCatalogFiche();
    loadCatalogInfo();
}

async function loadCatalogInfo() {
    const id = catState.selected;
    if (!id) return;
    const res = await nui("action", { action: "catalogs.info", payload: { id } }).catch(() => null);
    if (id !== catState.selected) return;
    catState.info = res && res.ok ? res.catalog : false;
    catState.structures = res && res.ok ? res.structures || [] : [];
    paintCatalogFiche();
}

async function catalogAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) {
        loadCatalogs();
        loadCatalogInfo();
    }
    return res;
}

function paintCatalogFiche() {
    if (!catState.dom) return;
    const fiche = catState.dom.fiche;
    if (!catState.selected) return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-book"), "Choisissez un catalogue ou créez-en un."));
    if (catState.info === false) return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-book"), "Ce catalogue n'existe plus."));
    if (!catState.info) return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-book"), "Chargement du catalogue…"));

    const c = catState.info;
    const previous = fiche.querySelector(".scroll");
    const keepScroll = previous && fiche.dataset.catalog === String(c.id) ? previous.scrollTop : 0;
    fiche.dataset.catalog = String(c.id);
    const kind = CATALOG_KINDS.find((k) => k.value === c.kind) || {};

    fiche.replaceChildren(
        h("div", { class: "page-head" },
            h("div", { class: "grow" },
                h("h1", { class: "page-title" }, c.label, h("span", { class: "badge muted" }, c.kindLabel)),
                h("div", { class: "page-sub" }, kind.help || "")),
            h("div", { class: "btn-row" },
                h("button", { class: "btn ghost", onclick: () => openRenameCatalog(c) }, icon("i-edit"), "Renommer"),
                h("button", { class: "btn danger", onclick: () => deleteCatalog(c) }, icon("i-trash"), "Supprimer"))
        ),
        h("div", { class: "scroll" }, catalogLinesCard(c), catalogLinksCard(c))
    );

    const scroller = fiche.querySelector(".scroll");
    if (scroller) scroller.scrollTop = keepScroll;
}

function catalogLinesCard(c) {
    const rows = c.lines.map((line) => {
        let details;
        if (c.kind === "craft") {
            details = `${line.ingredients.map((i) => `${i.count} × ${i.label}`).join(" + ")} · ${line.duration} s${line.minGrade ? ` · grade ${line.minGrade}+` : ""}`;
        } else {
            details = `${line.price ? money(line.price) : "Gratuit"}${c.kind === "equipment" && line.minGrade ? ` · grade ${line.minGrade}+` : ""}`;
        }
        return h("div", { class: "row catalog-row" },
            h("img", { class: "item-img", src: `nui://ox_inventory/web/images/${line.item}.png`, alt: "", onerror: (e) => { e.target.style.visibility = "hidden"; } }),
            h("div", { class: "who" }, h("b", null, `${line.count > 1 ? `${line.count} × ` : ""}${line.label}`, line.missing ? h("span", { class: "badge ban" }, "objet inconnu") : null),
                h("span", null, `${line.item} · ${details}`)),
            h("div", { class: "btn-row" },
                h("button", { class: "btn small ghost", onclick: () => openCatalogLine(c, line) }, icon("i-edit"), "Modifier"),
                h("button", { class: "btn small ghost", title: "Supprimer", onclick: async () => {
                    const yes = await confirmBox(`Supprimer « ${line.label} » ?`, "La ligne disparaît du catalogue en jeu.", "Supprimer", true);
                    if (yes) catalogAct("catalogs.deleteLine", { catalogId: c.id, lineId: line.id }, "Ligne supprimée.");
                } }, icon("i-trash")))
        );
    });

    return h("div", { class: "card" },
        h("div", { class: "card-head dev-head" },
            h("h3", { class: "card-title" }, c.kind === "craft" ? `Recettes (${rows.length})` : `Articles (${rows.length})`),
            h("button", { class: "btn small primary", onclick: () => openCatalogLine(c, null) }, icon("i-plus"), c.kind === "craft" ? "Ajouter une recette" : "Ajouter un article")),
        rows.length ? h("div", { class: "table" }, rows) : h("p", { class: "hint-line", style: "margin:0" }, "Catalogue vide.")
    );
}

function catalogLinksCard(c) {
    const byJob = new Map(catState.structures.map((s) => [s.job, s]));
    const linked = c.linked.map((job) => byJob.get(job) || { job, label: job });
    const free = catState.structures.filter((s) => !c.linked.includes(s.job));
    const select = h("select", { class: "input" }, free.length
        ? free.map((s) => h("option", { value: s.job }, `${s.label} (${s.kind === "public" ? "service public" : "entreprise"})`))
        : [h("option", { value: "" }, "Toutes les structures sont rattachées")]);

    return h("div", { class: "card", style: "margin-top:16px" },
        h("h3", { class: "card-title" }, `Structures rattachées (${linked.length})`),
        linked.length ? h("div", { class: "chips" }, linked.map((s) => h("span", { class: "chip" }, s.label,
            h("button", { class: "chip-x", title: "Détacher", onclick: () => catalogAct("catalogs.link", { id: c.id, job: s.job, linked: false }, `Détaché de ${s.label}.`) }, icon("i-x")))))
            : h("p", { class: "hint-line", style: "margin:0" }, "Rattaché à aucune structure : invisible en jeu."),
        h("div", { class: "spawn-row", style: "margin-top:12px" }, select,
            h("button", { class: "btn", disabled: !free.length, onclick: () => select.value && catalogAct("catalogs.link", { id: c.id, job: select.value, linked: true }, "Catalogue rattaché.") }, icon("i-plus"), "Rattacher"))
    );
}

// ---------- Création, renommage, suppression ----------

function openCreateCatalog() {
    let kind = "shop";
    const label = h("input", { class: "input", maxlength: "60", placeholder: "Ex. Carte du Burger Shot" });
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
            const res = await act("catalogs.create", { label: label.value.trim(), kind }, "Catalogue créé.");
            if (!res) return;
            close();
            await loadCatalogs();
            selectCatalog(res.id);
        });
        return [
            h("header", null, h("h3", null, "Nouveau catalogue")),
            h("div", { class: "body event-form" },
                h("div", { class: "field" }, h("label", null, "Nom"), label),
                h("div", { class: "field" }, h("label", null, "Type"), seg, help)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    label.focus();
}

function openRenameCatalog(c) {
    const input = h("input", { class: "input", maxlength: "60", value: c.label });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Renommer");
        submit.addEventListener("click", async () => {
            const res = await catalogAct("catalogs.rename", { id: c.id, label: input.value.trim() }, "Catalogue renommé.");
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

async function deleteCatalog(c) {
    const yes = await confirmBox(`Supprimer « ${c.label} » ?`, "Le catalogue, ses lignes et ses rattachements sont effacés. Action définitive.", "Supprimer", true);
    if (!yes) return;
    const res = await act("catalogs.delete", { id: c.id }, "Catalogue supprimé.");
    if (!res) return;
    catState.selected = null;
    catState.info = null;
    loadCatalogs();
    paintCatalogFiche();
}

// ---------- Ligne : article ou recette ----------

function itemPicker(items, value) {
    const listId = "catalog-items";
    if (!document.getElementById(listId)) {
        document.body.append(h("datalist", { id: listId }, items.map((i) => h("option", { value: i.name }, i.label))));
    }
    return h("input", { class: "input mono", list: listId, maxlength: "60", placeholder: "nom de l'objet (ex. burger)", value: value || "" });
}

async function openCatalogLine(c, line) {
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

    const fields = [h("div", { class: "field" }, h("label", null, craft ? "Objet fabriqué" : "Objet"), item),
        h("div", { class: "event-form-row" },
            h("div", { class: "field" }, h("label", null, craft ? "Quantité fabriquée" : "Quantité par achat"), count),
            craft ? h("div", { class: "field" }, h("label", null, "Durée (secondes)"), duration) : h("div", { class: "field" }, h("label", null, "Prix ($)"), price))];
    if (c.kind !== "shop") fields.push(h("div", { class: "field" }, h("label", null, "Grade minimum (0 = tous les membres)"), grade));
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
            const res = await catalogAct("catalogs.saveLine", {
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

// ---------- Onglet Catalogues de la fiche d'une structure (web/structures.js) ----------

function structureCatalogsCard(info, doAct) {
    const linked = info.catalogs || [];
    const linkedIds = new Set(linked.map((c) => c.id));
    const free = (info.allCatalogs || []).filter((c) => !linkedIds.has(c.id));
    const select = h("select", { class: "input" }, free.length
        ? free.map((c) => h("option", { value: String(c.id) }, `${c.label} (${c.kindLabel})`))
        : [h("option", { value: "" }, "Aucun autre catalogue")]);

    return h("div", null,
        h("div", { class: "card" },
            h("h3", { class: "card-title" }, `Catalogues actifs (${linked.length})`),
            linked.length ? h("div", { class: "table" }, linked.map((c) => h("div", { class: "row point-row" },
                h("span", { class: "status on" }),
                h("div", { class: "who" }, h("b", null, c.label), h("span", null, `${c.kindLabel} · ${c.lines} ligne${c.lines > 1 ? "s" : ""}`)),
                h("button", { class: "btn small ghost", onclick: () => doAct("catalogs.link", { id: c.id, job: info.name, linked: false }, "Catalogue détaché.") }, icon("i-x"), "Détacher"))))
                : h("p", { class: "hint-line", style: "margin:0" }, "Aucun catalogue rattaché."),
            h("div", { class: "spawn-row", style: "margin-top:12px" }, select,
                h("button", { class: "btn", disabled: !free.length, onclick: () => select.value && doAct("catalogs.link", { id: Number(select.value), job: info.name, linked: true }, "Catalogue rattaché.") }, icon("i-plus"), "Rattacher")),
            h("p", { class: "hint-line" }, "Les catalogues se créent et se remplissent dans la tuile Catalogues. Boutique : point Catalogue (tout le monde). Équipement : points Catalogue et Armurerie (membres). Craft : point Craft."))
    );
}
