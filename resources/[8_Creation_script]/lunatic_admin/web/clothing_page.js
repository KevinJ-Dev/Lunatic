"use strict";

// ====================================================================
//  Autres → Magasins de vêtements (jeu : lunatic_clothing), en quatre onglets :
//  magasins (nom, enseigne, zone, marqueur, PNJ, blip, pages de l'accueil), enseignes (bannière du menu),
//  prix d'une pièce par catégorie et tenues prêt-à-porter (prises sur la tenue portée par le staff).
// ====================================================================

const clothingState = { data: null, draft: null, saved: "", tab: "stores" };
const CLOTHING_PAGES = [
    ["catalogue", "Catalogue", "Toutes les pièces, à essayer librement."],
    ["ready", "Prêt-à-porter", "Tenues préparées par le staff (onglet Prêt-à-porter)."],
    ["outfits", "Mes tenues", "Tenues enregistrées par le joueur, remises gratuitement."],
    ["favorites", "Favoris", "Pièces marquées d'une étoile dans le catalogue."],
];
const CLOTHING_TABS = [["stores", "Magasins"], ["brands", "Enseignes"], ["prices", "Prix"], ["ready", "Prêt-à-porter"]];

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

function paintClothing() {
    const root = $("view-others");
    const head = othersHead("Magasins de vêtements");
    if (!clothingState.data) return root.replaceChildren(h("div", { class: "content clothing-page" }, head, h("div", { class: "empty" }, icon("i-clock"), "Chargement…")));
    const base = clothingState.data.defaults || {};
    if (!base.categories || !base.categories.length) {
        return root.replaceChildren(h("div", { class: "content clothing-page" }, head,
            h("div", { class: "empty" }, icon("i-warn"), "lunatic_clothing ne tourne pas : démarrez-le pour régler les magasins.")));
    }
    const d = clothingDraft();
    const tabs = h("div", { class: "segmented" }, segmentedButtons(CLOTHING_TABS.map(([value, label]) => ({ value, label })), clothingState.tab, (v) => { clothingState.tab = v; paintClothing(); }));
    const body = { stores: clothingStoresTab, brands: clothingBrandsTab, prices: clothingPricesTab, ready: clothingReadyTab }[clothingState.tab](d, base);
    root.replaceChildren(h("div", { class: "content clothing-page" }, head, h("div", { class: "scroll others-editor" }, h("div", { class: "card" }, tabs), ...body.flat().filter(Boolean))));
}

// ---------- Magasins ----------

function clothingStoresTab(d) {
    const card = (store, index) => {
        const brand = h("select", { class: "input" }, d.brands.map((b) => h("option", { value: b.key, selected: b.key === store.brand }, b.label)));
        brand.addEventListener("change", () => { store.brand = brand.value; });
        const coords = h("span", { class: "mono muted" }, afkCoords(store.x != null ? store : null));
        const move = (delta) => { d.stores.splice(index + delta, 0, d.stores.splice(index, 1)[0]); paintClothing(); };
        return h("div", { class: "card creator-spawn" },
            h("div", { class: "creator-spawn-head" }, h("b", null, `Magasin ${index + 1}`),
                h("div", { class: "creator-spawn-toggle" }, draftToggle(store, "enabled", "Ouvert", "Visible et utilisable en jeu")),
                h("button", { class: "btn small ghost sq-btn", title: "Monter", disabled: index === 0, onclick: () => move(-1) }, "↑"),
                h("button", { class: "btn small ghost sq-btn", title: "Descendre", disabled: index === d.stores.length - 1, onclick: () => move(1) }, "↓"),
                h("button", { class: "btn small danger", onclick: () => { d.stores.splice(index, 1); paintClothing(); } }, icon("i-trash"), "Retirer")),
            fieldRow("Nom", clothingInput(store, "label", { maxlength: "40", placeholder: "Binco de Strawberry" })),
            fieldRow("Enseigne", brand),
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
            h("p", { class: "hint-line", style: "margin:0" }, "Le [E] s'affiche dans toute la zone : 2 m pour un point précis, 8 à 15 m pour tout le magasin. Sans magasin enregistré ici, ceux de la config de lunatic_clothing servent."),
            h("div", { class: "btn-row" }, h("button", { class: "btn small primary", onclick: () => {
                if (d.stores.length >= 40) return toast("40 magasins au maximum.", "error");
                d.stores.push({ label: "", brand: d.brands[0].key, enabled: true, blip: false, radius: 2, marker: true, ped: "", pages: { catalogue: true, ready: true, outfits: true, favorites: true } });
                paintClothing();
            } }, icon("i-plus"), "Ajouter un magasin"))),
        d.stores.map(card),
    ];
}

// ---------- Enseignes (bannière du menu) ----------

function clothingBrandsTab(d) {
    const card = (brand, index) => {
        const preview = h("div", { class: "clothing-banner" });
        const paintPreview = () => {
            preview.style.background = brand.color;
            preview.style.backgroundImage = /^https?:\/\//.test(brand.image || "") ? `linear-gradient(180deg, #0000 40%, #0008), url("${brand.image}")` : "";
            preview.replaceChildren(brand.showText !== false ? h("b", null, brand.label || "Enseigne") : null, h("small", null, "Nom du magasin"));
        };
        paintPreview();
        const color = h("input", { class: "input clothing-color", type: "color", value: brand.color || "#7a3cff" });
        color.addEventListener("input", () => { brand.color = color.value; paintPreview(); });
        const label = clothingInput(brand, "label", { maxlength: "30" });
        label.addEventListener("input", paintPreview);
        const image = clothingInput(brand, "image", { maxlength: "300", placeholder: "https://… ou clé de la tuile Images (vide : couleur seule)" });
        image.addEventListener("input", paintPreview);
        const text = draftToggle(brand, "showText", "Nom sur la bannière", "Décochez si l'image contient déjà le logo.");
        text.addEventListener("click", paintPreview);
        const used = d.stores.filter((s) => s.brand === brand.key).length;
        return h("div", { class: "card creator-spawn" },
            h("div", { class: "creator-spawn-head" }, h("b", null, brand.label || "Nouvelle enseigne"), h("span", { class: "muted" }, `${used} magasin${used > 1 ? "s" : ""}`),
                h("button", { class: "btn small danger", disabled: used > 0 || d.brands.length <= 1, title: used ? "Utilisée par des magasins" : "", onclick: () => { d.brands.splice(index, 1); paintClothing(); } }, icon("i-trash"), "Retirer")),
            preview,
            h("div", { class: "driving-grid" },
                fieldRow("Nom", label),
                fieldRow("Couleur", color),
                fieldRow("Couleur du blip (0-85)", clothingInput(brand, "blip", { type: "number", min: "0", max: "85" }, true))),
            fieldRow("Image de bannière", image),
            h("div", { class: "mode-list" }, text));
    };

    return [
        h("div", { class: "card" },
            h("p", { class: "hint-line", style: "margin:0" }, "La bannière en haut du menu du magasin : couleur, image (lien https, ou clé d'une image ajoutée dans la tuile Images) et nom. Chaque magasin choisit son enseigne."),
            h("div", { class: "btn-row" }, h("button", { class: "btn small primary", onclick: () => {
                if (d.brands.length >= 20) return toast("20 enseignes au maximum.", "error");
                d.brands.push({ key: `brand_${Date.now().toString(36)}`, label: "", color: "#7a3cff", image: "", showText: true, blip: 0 });
                paintClothing();
            } }, icon("i-plus"), "Ajouter une enseigne"))),
        d.brands.map(card),
    ];
}

// ---------- Prix ----------

function clothingPricesTab(d, base) {
    return [
        h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Prix d'une pièce"),
            h("div", { class: "driving-grid" }, base.categories.map((c) => fieldRow(`${c.label} (${currencySymbol()})`, clothingInput(d.prices, c.key, { type: "number", min: "0", max: "1000000" }, true)))),
            h("p", { class: "hint-line" }, "Le joueur paie, en liquide ou par carte, les pièces changées au moment de valider. Retirer un accessoire est gratuit ; 0 = gratuit.")),
        h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Mes tenues"),
            fieldRow("Tenues enregistrables par personnage", clothingInput(d, "maxOutfits", { type: "number", min: "0", max: "50" }, true)),
            h("p", { class: "hint-line" }, "Une tenue enregistrée se remet gratuitement dans n'importe quel magasin ayant la page « Mes tenues »."))];
}

// ---------- Prêt-à-porter ----------

function clothingReadyTab(d) {
    const capture = async () => {
        const res = await act("clothing.capture", {}, null);
        if (!res || !res.ok) return null;
        return res;
    };
    const card = (outfit, index) => {
        const pieces = Object.keys(outfit.pieces || {}).length;
        return h("div", { class: "card creator-spawn" },
            h("div", { class: "creator-spawn-head" }, h("b", null, outfit.label || "Nouvelle tenue"), h("span", { class: "muted" }, `${outfit.sex === "female" ? "Femme" : "Homme"} · ${pieces} pièces`),
                h("button", { class: "btn small ghost", title: "Remplacer par la tenue que vous portez", onclick: async () => {
                    const res = await capture();
                    if (!res) return;
                    Object.assign(outfit, { sex: res.sex, pieces: res.pieces });
                    toast("Tenue reprise : pensez à enregistrer.", "info");
                    paintClothing();
                } }, icon("i-shirt"), "Reprendre ma tenue"),
                h("button", { class: "btn small danger", onclick: () => { d.ready.splice(index, 1); paintClothing(); } }, icon("i-trash"), "Retirer")),
            h("div", { class: "driving-grid" },
                fieldRow("Nom", clothingInput(outfit, "label", { maxlength: "30", placeholder: "Costume trois pièces" })),
                fieldRow(`Prix (${currencySymbol()})`, clothingInput(outfit, "price", { type: "number", min: "0" }, true))),
            h("div", { class: "crew-sub" }, "Vendue chez (aucune cochée : partout)"),
            h("div", { class: "mode-list" }, d.brands.map((b) => draftToggle(outfit.brands, b.key, b.label, null))));
    };

    return [
        h("div", { class: "card" },
            h("p", { class: "hint-line", style: "margin:0" }, "Habillez-vous en jeu (le catalogue d'un magasin sert d'essayage), puis ajoutez la tenue portée. Elle n'est proposée qu'aux personnages du même sexe."),
            h("div", { class: "btn-row" }, h("button", { class: "btn small primary", onclick: async () => {
                if (d.ready.length >= 60) return toast("60 tenues au maximum.", "error");
                const res = await capture();
                if (!res) return;
                d.ready.push({ id: `r${Date.now().toString(36)}`, label: "", price: 100, sex: res.sex, brands: {}, pieces: res.pieces });
                paintClothing();
            } }, icon("i-plus"), "Ajouter ma tenue actuelle"))),
        d.ready.length ? d.ready.map(card) : h("div", { class: "card" }, h("p", { class: "hint-line", style: "margin:0" }, "Aucune tenue pour le moment.")),
    ];
}

async function saveClothing() {
    const d = clothingState.draft;
    const res = await act("clothing.save", { stores: d.stores, brands: d.brands, prices: d.prices, ready: d.ready, maxOutfits: d.maxOutfits }, "Magasins de vêtements enregistrés.");
    if (!res) return;
    untrackUnsaved("others");
    clothingState.draft = null;
    await loadClothing();
}
