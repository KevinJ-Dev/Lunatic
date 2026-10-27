"use strict";

// ====================================================================
//  Autres → Magasins de vêtements (jeu : lunatic_clothing). Accueil en tuiles :
//  - une tuile par enseigne : bannière et prix (coefficient, catégories vendues), ses magasins, son prêt-à-porter ;
//  - Catalogue des vêtements : prix par défaut et gestion en jeu des fiches (nom, prix, image, bannie, photo) ;
//  - Réglages : nombre de tenues enregistrables.
// ====================================================================

const clothingState = { data: null, draft: null, saved: "", view: "home", brand: null, tab: "banner" };
const CLOTHING_PAGES = [
    ["catalogue", "Catalogue", "Toutes les pièces, à essayer librement."],
    ["ready", "Prêt-à-porter", "Tenues de l'enseigne (onglet Prêt-à-porter)."],
    ["outfits", "Mes tenues", "Tenues enregistrées par le joueur, remises gratuitement."],
    ["favorites", "Favoris", "Pièces marquées d'une étoile dans le catalogue."],
];

function renderClothing(root) {
    if (clothingState.data && root.querySelector(".clothing-page")) return;
    paintClothing();
    if (!clothingState.data) loadClothing();
}

async function loadClothing() {
    const res = await nui("action", { action: "clothing.get", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    clothingState.data = res;
    if (othersState.page === "clothing") paintClothing();
}

function clothingDraft() {
    if (clothingState.draft) return clothingState.draft;
    const data = clothingState.data;
    const base = data.defaults || {};
    const zone = base.storeDefaults || { radius: 2, marker: true, ped: "" };
    const stores = data.stores && data.stores.length ? data.stores : base.stores || [];
    const brands = data.brands && data.brands.length ? data.brands : base.brands || [];
    const d = {
        key: "clothing",
        stores: JSON.parse(JSON.stringify(stores)),
        brands: JSON.parse(JSON.stringify(brands)),
        prices: { ...(base.prices || {}), ...(data.prices || {}) },
        ready: JSON.parse(JSON.stringify(data.ready || [])),
        maxOutfits: data.maxOutfits ?? base.maxOutfits ?? 10,
    };
    for (const store of d.stores) {
        if (store.enabled === undefined) store.enabled = true;
        if (store.blip === undefined) store.blip = false;
        if (store.radius === undefined) store.radius = zone.radius;
        if (store.marker === undefined) store.marker = zone.marker;
        if (store.ped === undefined) store.ped = zone.ped;
        store.pages = { catalogue: true, ready: true, outfits: true, favorites: true, ...(store.pages || {}) };
    }
    for (const brand of d.brands) {
        if (brand.showText === undefined) brand.showText = true;
        if (brand.image === undefined) brand.image = "";
        if (brand.coef === undefined) brand.coef = 1;
        if (!brand.textColor) brand.textColor = "";
        if (brand.flat === undefined) brand.flat = false;
        if (!brand.exclude || Array.isArray(brand.exclude)) brand.exclude = {};
    }
    for (const outfit of d.ready) if (!outfit.brands || Array.isArray(outfit.brands)) outfit.brands = {};
    clothingState.draft = d;
    clothingState.saved = JSON.stringify(d);
    othersTrack("Magasins de vêtements", clothingState, saveClothing, paintClothing);
    return d;
}

function clothingInput(holder, key, attrs, number) {
    const input = h("input", { class: `input${number ? " mono" : ""}`, ...attrs, value: String(holder[key] ?? "") });
    input.addEventListener("input", () => { holder[key] = number ? Number(input.value || 0) : input.value; });
    return input;
}

function clothingGo(view, brand) {
    clothingState.view = view;
    clothingState.brand = brand || null;
    if (view === "brand") clothingState.tab = "banner";
    paintClothing();
}

// Bannière d'une enseigne (tuile de l'accueil et aperçu)
function clothingBanner(brand, sub) {
    const el = h("div", { class: "clothing-banner" }, brand.showText !== false ? h("b", { style: brand.textColor ? `color:${brand.textColor}` : null }, brand.label || "Enseigne") : null, h("small", null, sub));
    el.style.background = brand.color || "#7a3cff";
    if (/^https?:\/\//.test(brand.image || "")) el.style.backgroundImage = `linear-gradient(180deg, #0000 40%, #0008), url("${brand.image}")`;
    return el;
}

function paintClothing() {
    const root = $("view-others");
    if (!clothingState.data) return root.replaceChildren(h("div", { class: "content clothing-page" }, othersHead("Magasins de vêtements"), h("div", { class: "empty" }, icon("i-clock"), "Chargement…")));
    const base = clothingState.data.defaults || {};
    if (!base.categories || !base.categories.length) {
        return root.replaceChildren(h("div", { class: "content clothing-page" }, othersHead("Magasins de vêtements"),
            h("div", { class: "empty" }, icon("i-warn"), "lunatic_clothing ne tourne pas : démarrez-le pour régler les magasins.")));
    }
    const d = clothingDraft();
    let brand = clothingState.view === "brand" && d.brands.find((b) => b.key === clothingState.brand);
    if (clothingState.view === "brand" && !brand) clothingState.view = "home";

    const views = {
        home: () => [othersHead("Magasins de vêtements"), clothingHome(d)],
        brand: () => [clothingSubHead(brand.label || "Nouvelle enseigne"), clothingBrandPage(d, brand, base)],
        catalogue: () => [clothingSubHead("Catalogue des vêtements"), clothingCatalogue(d, base)],
        settings: () => [clothingSubHead("Réglages"), clothingSettings(d)],
    };
    const [head, body] = views[clothingState.view]();
    root.replaceChildren(h("div", { class: "content clothing-page" }, head, h("div", { class: "scroll others-editor" }, ...[body].flat(2).filter(Boolean))));
}

function clothingSubHead(title) {
    return h("div", { class: "driving-head" },
        h("button", { class: "btn small ghost sq-btn", title: "Retour aux magasins de vêtements", onclick: () => clothingGo("home") }, icon("i-back")),
        h("h1", { class: "page-title" }, title));
}

// ---------- Accueil ----------

function clothingHome(d) {
    const brandTile = (brand) => {
        const stores = d.stores.filter((s) => s.brand === brand.key);
        const open = stores.filter((s) => s.enabled !== false).length;
        const ready = d.ready.filter((o) => o.brands[brand.key] || !Object.keys(o.brands).length).length;
        return h("button", { class: "clothing-tile", onclick: () => clothingGo("brand", brand.key) },
            clothingBanner(brand, `${open} / ${stores.length} magasin${stores.length > 1 ? "s" : ""} ouverts`),
            h("span", { class: "clothing-tile-info" }, `Prix ×${Number(brand.coef || 1).toFixed(2).replace(".", ",")}`, ` · ${ready} tenue${ready > 1 ? "s" : ""} prêtes`,
                Object.keys(brand.exclude || {}).length ? ` · ${Object.keys(brand.exclude).length} catégorie(s) non vendue(s)` : ""));
    };
    const addBrand = h("button", { class: "clothing-tile clothing-tile-add", onclick: () => {
        if (d.brands.length >= 20) return toast("20 enseignes au maximum.", "error");
        const key = `brand_${Date.now().toString(36)}`;
        d.brands.push({ key, label: "", color: "#7a3cff", image: "", showText: true, blip: 0, coef: 1, exclude: {} });
        clothingGo("brand", key);
    } }, icon("i-plus"), h("span", null, "Nouvelle enseigne"));

    return [
        h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Enseignes"),
            h("p", { class: "hint-line", style: "margin:0" }, "Chaque enseigne a sa bannière, son coefficient de prix, ses catégories vendues, ses magasins et ses tenues prêt-à-porter."),
            h("div", { class: "clothing-tiles" }, d.brands.map(brandTile), addBrand)),
        h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Commun à tous les magasins"),
            h("div", { class: "tiles others-tiles" },
                h("button", { class: "tile", onclick: () => clothingGo("catalogue") }, icon("i-shirt"), h("span", null, "Catalogue des vêtements")),
                h("button", { class: "tile", onclick: () => clothingGo("settings") }, icon("i-tool"), h("span", null, "Réglages")))),
    ];
}

// ---------- Page d'une enseigne ----------

function clothingBrandPage(d, brand, base) {
    const stores = d.stores.filter((s) => s.brand === brand.key);
    const ready = d.ready.filter((o) => o.brands[brand.key] || !Object.keys(o.brands).length);
    const tabs = h("div", { class: "segmented" }, segmentedButtons([
        { value: "banner", label: "Bannière et prix" }, { value: "stores", label: `Magasins (${stores.length})` }, { value: "ready", label: `Prêt-à-porter (${ready.length})` },
    ], clothingState.tab, (v) => { clothingState.tab = v; paintClothing(); }));
    const body = { banner: clothingBrandBanner, stores: clothingBrandStores, ready: clothingBrandReady }[clothingState.tab](d, brand, base);
    return [h("div", { class: "card" }, tabs), body];
}

function clothingBrandBanner(d, brand, base) {
    const preview = h("div");
    const paintPreview = () => preview.replaceChildren(clothingBanner(brand, "Nom du magasin"));
    paintPreview();
    const color = h("input", { class: "input clothing-color", type: "color", value: brand.color || "#7a3cff" });
    color.addEventListener("input", () => { brand.color = color.value; paintPreview(); });
    const label = clothingInput(brand, "label", { maxlength: "30", placeholder: "binco" });
    label.addEventListener("input", paintPreview);
    const image = clothingInput(brand, "image", { maxlength: "300", placeholder: "https://… ou clé de la tuile Images (vide : couleur seule)" });
    image.addEventListener("input", paintPreview);
    const text = draftToggle(brand, "showText", "Nom sur la bannière", "Décochez si l'image contient déjà le logo.");
    text.addEventListener("click", paintPreview);
    const textColor = h("input", { class: "input clothing-color", type: "color", value: brand.textColor || "#ffffff" });
    textColor.addEventListener("input", () => { brand.textColor = textColor.value; paintPreview(); });
    const flat = draftToggle(brand, "flat", "Une catégorie par bouton", "La barre du bas montre chaque catégorie vendue (Montres, Bracelets…) au lieu des groupes. Idéal pour une bijouterie.");
    const used = d.stores.filter((s) => s.brand === brand.key).length;

    // Catégories vendues : interrupteur allumé = vendue (enregistré comme liste des catégories exclues)
    const sells = {};
    const toggles = base.categories.map((c) => {
        sells[c.key] = !brand.exclude[c.key];
        const row = draftToggle(sells, c.key, c.label, c.group);
        row.addEventListener("click", () => { if (sells[c.key]) delete brand.exclude[c.key]; else brand.exclude[c.key] = true; });
        return row;
    });

    return [
        h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Bannière du menu"), preview,
            h("div", { class: "driving-grid" },
                fieldRow("Nom", label),
                fieldRow("Couleur", color),
                fieldRow("Couleur du nom", textColor),
                fieldRow("Couleur du blip (0-85)", clothingInput(brand, "blip", { type: "number", min: "0", max: "85" }, true))),
            fieldRow("Image de bannière", image),
            h("div", { class: "mode-list" }, text, flat)),
        h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Prix et catégories vendues"),
            fieldRow("Coefficient de prix", clothingInput(brand, "coef", { type: "number", min: "0.1", max: "10", step: "0.05" }, true)),
            h("p", { class: "hint-line" }, "Prix d'une pièce dans cette enseigne = prix de sa fiche (ou de sa catégorie) × coefficient. Ex. 0,8 pour un discount, 2 pour du luxe."),
            h("div", { class: "mode-list clothing-sells" }, toggles)),
        h("div", { class: "card" }, h("div", { class: "btn-row" },
            h("button", { class: "btn small danger", disabled: used > 0 || d.brands.length <= 1, title: used ? "Déplacez ou retirez d'abord ses magasins" : "", onclick: () => {
                d.brands.splice(d.brands.indexOf(brand), 1);
                for (const outfit of d.ready) delete outfit.brands[brand.key];
                clothingGo("home");
            } }, icon("i-trash"), "Supprimer l'enseigne")),
            used ? h("p", { class: "hint-line" }, "Une enseigne avec des magasins ne peut pas être supprimée.") : null),
    ];
}

function clothingBrandStores(d, brand) {
    const stores = d.stores.filter((s) => s.brand === brand.key);
    const card = (store, index) => {
        const move = h("select", { class: "input" }, d.brands.map((b) => h("option", { value: b.key, selected: b.key === store.brand }, b.label || b.key)));
        move.addEventListener("change", () => { store.brand = move.value; paintClothing(); });
        const coords = h("span", { class: "mono muted" }, afkCoords(store.x != null ? store : null));
        return h("div", { class: "card creator-spawn" },
            h("div", { class: "creator-spawn-head" }, h("b", null, store.label || `Magasin ${index + 1}`),
                h("div", { class: "creator-spawn-toggle" }, draftToggle(store, "enabled", "Ouvert", "Visible et utilisable en jeu")),
                h("button", { class: "btn small danger", onclick: () => { d.stores.splice(d.stores.indexOf(store), 1); paintClothing(); } }, icon("i-trash"), "Retirer")),
            fieldRow("Nom", clothingInput(store, "label", { maxlength: "40", placeholder: "Binco de Strawberry" })),
            fieldRow("Enseigne", move),
            h("div", { class: "driving-spot" }, h("b", null, "Centre de la zone"), coords,
                h("button", { class: "btn small ghost", onclick: async () => {
                    const p = await othersMyPosition();
                    if (!p) return;
                    Object.assign(store, { x: p.x, y: p.y, z: p.z, h: p.h });
                    coords.textContent = afkCoords(p);
                } }, icon("i-crosshair"), "Définir position"),
                h("button", { class: "btn small ghost", onclick: () => (store.x != null ? act("others.tp", { x: store.x, y: store.y, z: store.z, h: store.h }, null) : toast("Position non définie.", "error")) }, icon("i-goto"), "TP")),
            h("div", { class: "driving-grid" },
                fieldRow("Rayon de la zone (m)", clothingInput(store, "radius", { type: "number", min: "1", max: "30", step: "0.5" }, true)),
                fieldRow("PNJ au centre", clothingInput(store, "ped", { maxlength: "40", placeholder: "s_f_y_shop_mid (vide : aucun)" }))),
            h("div", { class: "mode-list" },
                draftToggle(store, "marker", "Marqueur au sol", "Cercle à la taille de la zone (désactivez-le pour une zone couvrant tout le magasin)."),
                draftToggle(store, "blip", "Blip sur la carte", "À la couleur de l'enseigne (les 15 magasins d'origine ont déjà le leur dans la tuile Blips)."),
                CLOTHING_PAGES.map(([key, label, hint]) => draftToggle(store.pages, key, `Page « ${label} »`, hint))));
    };

    return [
        h("div", { class: "card" },
            h("p", { class: "hint-line", style: "margin:0" }, "Le [E] s'affiche dans toute la zone : 2 m pour un point précis, 8 à 15 m pour tout le magasin."),
            h("div", { class: "btn-row" }, h("button", { class: "btn small primary", onclick: () => {
                if (d.stores.length >= 40) return toast("40 magasins au maximum.", "error");
                d.stores.push({ label: "", brand: brand.key, enabled: true, blip: false, radius: 2, marker: true, ped: "", pages: { catalogue: true, ready: true, outfits: true, favorites: true } });
                paintClothing();
            } }, icon("i-plus"), "Ajouter un magasin"))),
        stores.length ? stores.map(card) : h("div", { class: "card" }, h("p", { class: "hint-line", style: "margin:0" }, "Aucun magasin pour cette enseigne.")),
    ];
}

function clothingBrandReady(d, brand) {
    const capture = async () => {
        const res = await act("clothing.capture", {}, null);
        return res && res.ok ? res : null;
    };
    const list = d.ready.filter((o) => o.brands[brand.key] || !Object.keys(o.brands).length);
    const card = (outfit) => {
        const pieces = Object.keys(outfit.pieces || {}).length;
        const everywhere = !Object.keys(outfit.brands).filter((k) => outfit.brands[k]).length;
        return h("div", { class: "card creator-spawn" },
            h("div", { class: "creator-spawn-head" }, h("b", null, outfit.label || "Nouvelle tenue"), h("span", { class: "muted" }, `${outfit.sex === "female" ? "Femme" : "Homme"} · ${pieces} pièces${everywhere ? " · vendue partout" : ""}`),
                h("button", { class: "btn small ghost", title: "Remplacer par la tenue que vous portez", onclick: async () => {
                    const res = await capture();
                    if (!res) return;
                    Object.assign(outfit, { sex: res.sex, pieces: res.pieces });
                    toast("Tenue reprise : pensez à enregistrer.", "info");
                    paintClothing();
                } }, icon("i-shirt"), "Reprendre ma tenue"),
                h("button", { class: "btn small danger", onclick: () => { d.ready.splice(d.ready.indexOf(outfit), 1); paintClothing(); } }, icon("i-trash"), "Retirer")),
            h("div", { class: "driving-grid" },
                fieldRow("Nom", clothingInput(outfit, "label", { maxlength: "30", placeholder: "Costume trois pièces" })),
                fieldRow(`Prix (${currencySymbol()})`, clothingInput(outfit, "price", { type: "number", min: "0" }, true))),
            h("div", { class: "crew-sub" }, "Vendue chez (aucune cochée : partout)"),
            h("div", { class: "mode-list" }, d.brands.map((b) => draftToggle(outfit.brands, b.key, b.label || b.key, null))));
    };

    return [
        h("div", { class: "card" },
            h("p", { class: "hint-line", style: "margin:0" }, "Habillez-vous en jeu (le catalogue d'un magasin sert d'essayage), puis ajoutez la tenue portée. Elle n'est proposée qu'aux personnages du même sexe."),
            h("div", { class: "btn-row" }, h("button", { class: "btn small primary", onclick: async () => {
                if (d.ready.length >= 60) return toast("60 tenues au maximum.", "error");
                const res = await capture();
                if (!res) return;
                d.ready.push({ id: `r${Date.now().toString(36)}`, label: "", price: 100, sex: res.sex, brands: { [brand.key]: true }, pieces: res.pieces });
                paintClothing();
            } }, icon("i-plus"), "Ajouter ma tenue actuelle"))),
        list.length ? list.map(card) : h("div", { class: "card" }, h("p", { class: "hint-line", style: "margin:0" }, "Aucune tenue pour cette enseigne.")),
    ];
}

// ---------- Catalogue des vêtements ----------

function clothingCatalogue(d, base) {
    const dirty = () => JSON.stringify(clothingState.draft) !== clothingState.saved;
    return [
        h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Fiches des pièces"),
            h("p", { class: "hint-line", style: "margin:0" }, "En jeu, sur votre personnage : grille de chaque catégorie, homme ou femme, et pour chaque pièce son nom, son prix, son image, sa photo ou son retrait des magasins (bannie)."),
            h("p", { class: "hint-line", style: "margin:0" }, base.screenshot ? "Photos : screenshot-basic est démarré."
                : "Photos indisponibles : installez et démarrez screenshot-basic (le reste fonctionne sans)."),
            h("div", { class: "btn-row" }, h("button", { class: "btn small primary", onclick: () => {
                if (dirty()) return toast("Enregistrez d'abord vos changements.", "error");
                act("clothing.catalogue", {}, null);
            } }, icon("i-shirt"), "Ouvrir la gestion du catalogue en jeu"))),
        h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Prix par défaut d'une pièce"),
            h("div", { class: "driving-grid" }, base.categories.map((c) => fieldRow(`${c.label} (${currencySymbol()})`, clothingInput(d.prices, c.key, { type: "number", min: "0", max: "1000000" }, true)))),
            h("p", { class: "hint-line" }, "Prix d'une pièce sans prix propre dans sa fiche, avant le coefficient de l'enseigne. Retirer un accessoire est gratuit ; 0 = gratuit.")),
    ];
}

// ---------- Réglages ----------

function clothingSettings(d) {
    return h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Mes tenues"),
        fieldRow("Tenues enregistrables par personnage", clothingInput(d, "maxOutfits", { type: "number", min: "0", max: "50" }, true)),
        h("p", { class: "hint-line" }, "Une tenue enregistrée se remet gratuitement dans n'importe quel magasin ayant la page « Mes tenues »."));
}

async function saveClothing() {
    const d = clothingState.draft;
    const res = await act("clothing.save", { stores: d.stores, brands: d.brands, prices: d.prices, ready: d.ready, maxOutfits: d.maxOutfits }, "Magasins de vêtements enregistrés.");
    if (!res) return;
    untrackUnsaved("others");
    clothingState.draft = null;
    await loadClothing();
}
