"use strict";

// ====================================================================
//  lunatic_admin — tuile Boutique, onglets Packs, Véhicules et Armes (organisation comme Vision)
//  Trois colonnes : catégories, liste des produits, édition (d'un produit, ou de la catégorie choisie).
// ====================================================================

const storeCat = { data: {}, cat: null, sel: null, newCategory: false, draft: null, saved: "" };

const STORE_KINDS = {
    packs: { label: "Packs", one: "pack", add: "Créer un pack", icon: "i-box" },
    vehicles: { label: "Véhicules", one: "véhicule", add: "Ajouter", icon: "i-car" },
    weapons: { label: "Armes", one: "arme", add: "Ajouter", icon: "i-crosshair" },
};
const STORE_VEHICLE_TYPES = [["car", "Voiture"], ["bike", "Moto"], ["boat", "Bateau"], ["heli", "Hélicoptère"], ["plane", "Avion"]];

// Image d'un produit : celle choisie, sinon l'image du jeu (véhicule de base, objet d'ox_inventory)
function storeProductImage(kind, product) {
    if (product.image) return product.image;
    if (kind === "vehicles" && product.data.model) return `https://docs.fivem.net/vehicles/${product.data.model}.webp`;
    if (kind === "weapons" && product.data.item) return `nui://ox_inventory/web/images/${product.data.item}.png`;
    return null;
}

const storePic = (src, fallback) => src
    ? h("img", { src, alt: "", onerror: (e) => { e.target.replaceWith(icon(fallback)); } })
    : icon(fallback);

async function loadStoreCatalog(kind) {
    const res = await nui("action", { action: "storeCatalog.list", payload: { kind } }).catch(() => null);
    if (!res || !res.ok) return;
    storeCat.data[kind] = res.categories || [];
    if (storeCat.cat === null || !storeCat.data[kind].some((c) => c.id === storeCat.cat)) storeCat.cat = storeCat.data[kind][0] ? storeCat.data[kind][0].id : null;
    if (storeState.tab === kind) paintStore();
}

async function storeCatAct(kind, action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) await loadStoreCatalog(kind);
    return res;
}

function storeCatalogSelect(kind, changes) {
    guardUnsaved("shop", () => {
        untrackUnsaved("shop");
        storeCat.draft = null;
        Object.assign(storeCat, changes);
        paintStore();
    });
}

function storeCatalogTab(kind) {
    const conf = STORE_KINDS[kind];
    const categories = storeCat.data[kind];
    if (!categories) {
        loadStoreCatalog(kind);
        return h("div", { class: "empty" }, icon(conf.icon), "Chargement du catalogue…");
    }
    if (!catalogItems) loadCatalogItems().then(() => storeState.tab === kind && paintStore());
    const category = categories.find((c) => c.id === storeCat.cat) || null;

    // 1. Catégories
    const nav = h("aside", { class: "sidebar crew-nav store-nav" },
        h("div", { class: "crew-block" },
            h("div", { class: "crew-block-head" }, icon("i-layers"), "Catégories", h("span", { class: "cnt" }, String(categories.length))),
            categories.map((c) => h("button", { class: `list-row${c.id === storeCat.cat && !storeCat.newCategory ? " active" : ""}`, onclick: () => storeCatalogSelect(kind, { cat: c.id, sel: null, newCategory: false }) },
                h("span", { class: "store-cat-pic" }, storePic(c.image, conf.icon)), h("span", { class: "name" }, c.label), h("span", { class: "cnt" }, String(c.products.length)))),
            h("button", { class: `list-row${storeCat.newCategory ? " active" : ""}`, onclick: () => storeCatalogSelect(kind, { sel: null, newCategory: true }) }, icon("i-plus"), h("span", { class: "name" }, "Nouvelle catégorie"))));

    // 2. Liste des produits de la catégorie
    const products = category ? category.products : [];
    const cards = products.map((p) => kind === "packs" ? storePackCard(p) : h("button", { class: `store-card${p.id === storeCat.sel ? " active" : ""}${p.active ? "" : " off"}`, onclick: () => storeCatalogSelect(kind, { sel: p.id, newCategory: false }) },
        h("span", { class: "store-card-pic" }, storePic(storeProductImage(kind, p), conf.icon)),
        h("b", null, p.label), h("span", { class: "mono" }, `${p.price} ${storeCreditsName()}`)));
    const list = h("section", { class: "crew-col store-list" },
        h("div", { class: "crew-col-head" }, icon(conf.icon), category ? category.label : `Liste des ${conf.label.toLowerCase()}`, h("span", { class: "cnt" }, String(products.length))),
        h("div", { class: "crew-scroll crew-col-body" },
            category ? h("div", { class: kind === "packs" ? "store-packs" : "store-grid" },
                h("button", { class: `store-card store-add${storeCat.sel === "new" ? " active" : ""}`, onclick: () => storeCatalogSelect(kind, { sel: "new", newCategory: false }) }, icon("i-plus"), h("span", null, conf.add)),
                ...cards) : h("div", { class: "empty small" }, "Créez d'abord une catégorie.")));

    // 3. Édition
    let editor;
    if (storeCat.sel !== null && category) editor = storeProductEditor(kind, category);
    else if (storeCat.newCategory || category) editor = storeCategoryEditor(kind, storeCat.newCategory ? null : category);
    else editor = h("div", { class: "empty" }, "Sélectionnez une catégorie ou un produit.");

    return h("div", { class: "store-catalog" }, nav, list, h("section", { class: "crew-col store-editor" }, editor));
}

// Pack : ligne avec son contenu (argent, objets, véhicules)
function storePackCard(p) {
    const chips = [];
    if (p.data.cash) chips.push(h("span", { class: "store-chip" }, icon("i-coins"), money(p.data.cash)));
    if (p.data.bank) chips.push(h("span", { class: "store-chip" }, icon("i-bank"), money(p.data.bank)));
    for (const i of p.data.items || []) chips.push(h("span", { class: "store-chip" }, storePic(`nui://ox_inventory/web/images/${i.item}.png`, "i-box"), `${i.count} × ${(catalogItems || []).find((c) => c.name === i.item)?.label || i.item}`));
    for (const v of p.data.vehicles || []) chips.push(h("span", { class: "store-chip" }, icon("i-car"), v.label));
    return h("button", { class: `store-pack${p.id === storeCat.sel ? " active" : ""}${p.active ? "" : " off"}`, onclick: () => storeCatalogSelect("packs", { sel: p.id, newCategory: false }) },
        h("div", { class: "store-pack-head" }, h("b", null, p.label), h("span", { class: "mono" }, `${p.price} ${storeCreditsName()}`), p.active ? null : h("span", { class: "badge muted" }, "Masqué")),
        h("div", { class: "store-pack-chips" }, chips.length ? chips : h("span", { class: "muted" }, "Vide")));
}

// ---------- Édition d'une catégorie ----------

function storeCategoryEditor(kind, category) {
    const key = category ? `cat:${category.id}` : "cat:new";
    if (!storeCat.draft || storeCat.draft.key !== key) {
        storeCat.draft = { key, label: category ? category.label : "", image: category ? category.image : "", type: category ? category.type || "car" : "car" };
        storeCat.saved = JSON.stringify(storeCat.draft);
        trackUnsaved("shop", {
            label: category ? `Catégorie ${category.label}` : "Nouvelle catégorie",
            isDirty: () => !!storeCat.draft && (storeCat.draft.key === "cat:new" || JSON.stringify(storeCat.draft) !== storeCat.saved),
            save: () => storeSaveCategory(kind, category),
            reset: () => { storeCat.draft = null; paintStore(); },
        });
    }
    const d = storeCat.draft;
    const label = h("input", { class: "input", maxlength: "40", placeholder: "Nom de la catégorie", value: d.label });
    label.addEventListener("input", () => { d.label = label.value; });
    const image = h("input", { class: "input mono", maxlength: "255", placeholder: "Image https (facultatif)", value: d.image });
    image.addEventListener("input", () => { d.image = image.value.trim(); });
    const type = h("select", { class: "input" }, STORE_VEHICLE_TYPES.map(([value, text]) => h("option", { value, selected: d.type === value }, text)));
    type.addEventListener("change", () => { d.type = type.value; });

    return [
        h("div", { class: "crew-col-head" }, icon("i-edit"), category ? "Éditer la catégorie" : "Nouvelle catégorie"),
        h("div", { class: "crew-scroll crew-col-body store-form" },
            h("div", { class: "store-preview" }, storePic(d.image, STORE_KINDS[kind].icon), h("b", null, d.label || "Catégorie"), category ? h("span", { class: "muted" }, `${category.products.length} produit(s)`) : null),
            fieldRow("Nom", label),
            fieldRow("Image", image),
            kind === "vehicles" ? fieldRow("Type", type) : null),
        category ? h("div", { class: "crew-actions store-actions" }, h("button", { class: "btn small danger", onclick: async () => {
            const yes = await confirmBox(`Supprimer « ${category.label} » ?`, category.products.length ? `Ses ${category.products.length} produit(s) sont supprimés aussi.` : "La catégorie est vide.", "Supprimer", true);
            if (!yes) return;
            untrackUnsaved("shop");
            storeCat.draft = null;
            storeCat.cat = null;
            await storeCatAct(kind, "storeCatalog.deleteCategory", { id: category.id }, "Catégorie supprimée.");
        } }, icon("i-trash"), "Supprimer la catégorie")) : null,
    ];
}

async function storeSaveCategory(kind, category) {
    const d = storeCat.draft;
    const res = await act("storeCatalog.saveCategory", { id: category ? category.id : null, kind, label: d.label.trim(), image: d.image, type: d.type }, category ? "Catégorie enregistrée." : "Catégorie créée.");
    if (!res) return;
    untrackUnsaved("shop");
    storeCat.draft = null;
    storeCat.newCategory = false;
    if (res.id) storeCat.cat = res.id;
    await loadStoreCatalog(kind);
}

// ---------- Édition d'un produit ----------

function storeProductEditor(kind, category) {
    const product = storeCat.sel === "new" ? null : category.products.find((p) => p.id === storeCat.sel);
    if (!product && storeCat.sel !== "new") return h("div", { class: "empty" }, "Produit introuvable.");
    const key = product ? `p:${product.id}` : `p:new:${category.id}`;
    if (!storeCat.draft || storeCat.draft.key !== key) {
        const empty = kind === "vehicles" ? { model: "" } : kind === "weapons" ? { item: "", ammo: 0 } : { cash: 0, bank: 0, items: [], vehicles: [] };
        storeCat.draft = { key, category: category.id, label: product ? product.label : "", image: product ? product.image : "", price: product ? product.price : 0, active: product ? product.active : true,
            data: JSON.parse(JSON.stringify(product ? { ...empty, ...product.data } : empty)) };
        storeCat.saved = JSON.stringify(storeCat.draft);
        trackUnsaved("shop", {
            label: product ? `${STORE_KINDS[kind].one} ${product.label}` : `Nouveau ${STORE_KINDS[kind].one}`,
            isDirty: () => !!storeCat.draft && (storeCat.draft.key.startsWith("p:new") || JSON.stringify(storeCat.draft) !== storeCat.saved),
            save: () => storeSaveProduct(kind, product),
            reset: () => { storeCat.draft = null; paintStore(); },
        });
    }
    const d = storeCat.draft;
    const preview = h("div", { class: "store-preview" });
    const paintPreview = () => preview.replaceChildren(storePic(storeProductImage(kind, d), STORE_KINDS[kind].icon), h("b", null, d.label || `Nouveau ${STORE_KINDS[kind].one}`), h("span", { class: "mono muted" }, `${d.price || 0} ${storeCreditsName()}`));
    paintPreview();

    const text = (key, attrs, onInput) => {
        const input = h("input", { class: "input", ...attrs, value: String(d[key] ?? "") });
        input.addEventListener("input", () => { d[key] = attrs.type === "number" ? Number(input.value || 0) : input.value; if (onInput) onInput(); });
        return input;
    };
    const categorySelect = h("select", { class: "input" }, storeCat.data[kind].map((c) => h("option", { value: String(c.id), selected: c.id === d.category }, c.label)));
    categorySelect.addEventListener("change", () => { d.category = Number(categorySelect.value); });

    let specific = [];
    if (kind === "vehicles") {
        const model = h("input", { class: "input mono", maxlength: "30", placeholder: "nom de spawn (ex. sultan)", value: d.data.model });
        model.addEventListener("change", () => { d.data.model = model.value.trim().toLowerCase(); paintPreview(); });
        specific = [fieldRow("Modèle", model)];
    } else if (kind === "weapons") {
        const item = catalogItems ? itemPicker(catalogItems.filter((i) => i.name.startsWith("WEAPON_")), d.data.item) : h("input", { class: "input mono", value: d.data.item });
        item.placeholder = "WEAPON_PISTOL";
        item.addEventListener("change", () => { d.data.item = item.value.trim().toUpperCase(); paintPreview(); });
        const ammo = h("input", { class: "input mono", type: "number", min: "0", max: "1000", value: String(d.data.ammo || 0) });
        ammo.addEventListener("input", () => { d.data.ammo = Number(ammo.value || 0); });
        specific = [fieldRow("Arme", item), fieldRow("Munitions", ammo)];
    } else {
        specific = storePackFields(d.data);
    }

    return [
        h("div", { class: "crew-col-head" }, icon("i-edit"), product ? `Édition ${STORE_KINDS[kind].one}` : `Nouveau ${STORE_KINDS[kind].one}`),
        h("div", { class: "crew-scroll crew-col-body store-form" },
            preview,
            fieldRow("Nom", text("label", { maxlength: "60" }, paintPreview)),
            fieldRow(`Prix (${storeCreditsName()})`, text("price", { type: "number", min: "0", class: "input mono" }, paintPreview)),
            fieldRow("Catégorie", categorySelect),
            ...specific,
            fieldRow("Image", text("image", { maxlength: "255", class: "input mono", placeholder: kind === "packs" ? "Image https (facultatif)" : "Auto (image du jeu)" }, paintPreview)),
            h("div", { class: "mode-list" }, draftToggle(d, "active", "En vente", "Masqué : le produit n'apparaît plus dans la boutique des joueurs."))),
        product ? h("div", { class: "crew-actions store-actions" }, h("button", { class: "btn small danger", onclick: async () => {
            const yes = await confirmBox(`Supprimer « ${product.label} » ?`, "Le produit est retiré de la boutique.", "Supprimer", true);
            if (!yes) return;
            untrackUnsaved("shop");
            storeCat.draft = null;
            storeCat.sel = null;
            await storeCatAct(kind, "storeCatalog.deleteProduct", { id: product.id }, "Produit supprimé.");
        } }, icon("i-trash"), "Supprimer")) : null,
    ];
}

function storePackFields(data) {
    const cash = h("input", { class: "input mono", type: "number", min: "0", value: String(data.cash || 0) });
    cash.addEventListener("input", () => { data.cash = Number(cash.value || 0); });
    const bank = h("input", { class: "input mono", type: "number", min: "0", value: String(data.bank || 0) });
    bank.addEventListener("input", () => { data.bank = Number(bank.value || 0); });

    const items = h("div", { class: "zone-list" });
    const paintItems = () => items.replaceChildren(...data.items.map((entry, index) => {
        const name = catalogItems ? itemPicker(catalogItems, entry.item) : h("input", { class: "input mono", value: entry.item });
        name.addEventListener("input", () => { entry.item = name.value.trim(); });
        const count = h("input", { class: "input mono", type: "number", min: "1", value: String(entry.count) });
        count.addEventListener("input", () => { entry.count = Number(count.value || 1); });
        return h("div", { class: "store-line" }, name, count, h("button", { class: "btn small ghost sq-btn", onclick: () => { data.items.splice(index, 1); paintItems(); } }, icon("i-trash")));
    }));
    paintItems();

    const vehicles = h("div", { class: "zone-list" });
    const paintVehicles = () => vehicles.replaceChildren(...data.vehicles.map((entry, index) => {
        const model = h("input", { class: "input mono", maxlength: "30", placeholder: "modèle", value: entry.model });
        model.addEventListener("input", () => { entry.model = model.value.trim().toLowerCase(); });
        const label = h("input", { class: "input", maxlength: "40", placeholder: "nom affiché", value: entry.label });
        label.addEventListener("input", () => { entry.label = label.value; });
        return h("div", { class: "store-line vehicle" }, model, label, h("button", { class: "btn small ghost sq-btn", onclick: () => { data.vehicles.splice(index, 1); paintVehicles(); } }, icon("i-trash")));
    }));
    paintVehicles();

    return [
        h("div", { class: "crew-sub" }, "Contenu du pack"),
        fieldRow("Argent liquide", cash),
        fieldRow("Banque", bank),
        h("div", { class: "crew-sub" }, "Objets"),
        items,
        h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
            if (data.items.length >= 20) return toast("20 objets au maximum.", "error");
            data.items.push({ item: "", count: 1 });
            paintItems();
        } }, icon("i-plus"), "Ajouter un objet"),
        h("div", { class: "crew-sub" }, "Véhicules"),
        vehicles,
        h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
            if (data.vehicles.length >= 5) return toast("5 véhicules au maximum.", "error");
            data.vehicles.push({ model: "", label: "" });
            paintVehicles();
        } }, icon("i-plus"), "Ajouter un véhicule"),
    ];
}

async function storeSaveProduct(kind, product) {
    const d = storeCat.draft;
    const res = await act("storeCatalog.saveProduct", { id: product ? product.id : null, category: d.category, label: d.label.trim(), image: d.image.trim(), price: d.price, active: d.active, data: d.data },
        product ? "Produit enregistré." : "Produit ajouté.");
    if (!res) return;
    untrackUnsaved("shop");
    storeCat.draft = null;
    storeCat.cat = d.category;
    if (res.id) storeCat.sel = res.id;
    await loadStoreCatalog(kind);
}
