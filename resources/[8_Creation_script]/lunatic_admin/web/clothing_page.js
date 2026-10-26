"use strict";

// ====================================================================
//  Autres → Magasins de vêtements (jeu : lunatic_clothing) : prix d'une pièce par catégorie, magasins (nom,
//  enseigne, position, blip) et pages proposées à l'accueil de chacun.
// ====================================================================

const clothingState = { data: null, draft: null, saved: "" };
const CLOTHING_PAGES = [
    ["catalogue", "Catalogue", "Toutes les pièces, à essayer librement."],
    ["ready", "Prêt-à-porter", "Tenues préparées par le staff (partie 2)."],
    ["outfits", "Mes tenues", "Tenues enregistrées par le joueur (partie 2)."],
    ["favorites", "Favoris", "Pièces marquées d'une étoile (partie 2)."],
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
    const stores = data.stores && data.stores.length ? data.stores : base.stores || [];
    const d = { key: "clothing", stores: JSON.parse(JSON.stringify(stores)), prices: { ...(base.prices || {}), ...(data.prices || {}) } };
    for (const store of d.stores) {
        if (store.enabled === undefined) store.enabled = true;
        if (store.blip === undefined) store.blip = false;
        store.pages = { catalogue: true, ready: true, outfits: true, favorites: true, ...(store.pages || {}) };
    }
    clothingState.draft = d;
    clothingState.saved = JSON.stringify(d);
    othersTrack("Magasins de vêtements", clothingState, saveClothing, paintClothing);
    return d;
}

function paintClothing() {
    const root = $("view-others");
    const head = othersHead("Magasins de vêtements");
    if (!clothingState.data) return root.replaceChildren(h("div", { class: "content clothing-page" }, head, h("div", { class: "empty" }, icon("i-clock"), "Chargement…")));
    const base = clothingState.data.defaults || {};
    if (!base.brands || !base.brands.length) {
        return root.replaceChildren(h("div", { class: "content clothing-page" }, head,
            h("div", { class: "empty" }, icon("i-warn"), "lunatic_clothing ne tourne pas : démarrez-le pour régler les magasins.")));
    }
    const d = clothingDraft();

    // Prix d'une pièce, par catégorie
    const prices = h("div", { class: "driving-grid" }, base.categories.map((c) => {
        const input = h("input", { class: "input mono", type: "number", min: "0", max: "100000", value: String(d.prices[c.key] ?? 0) });
        input.addEventListener("input", () => { d.prices[c.key] = Number(input.value || 0); });
        return fieldRow(`${c.label} (${currencySymbol()})`, input);
    }));

    const card = (store, index) => {
        const name = h("input", { class: "input", maxlength: "40", placeholder: "Binco de Strawberry", value: store.label || "" });
        name.addEventListener("input", () => { store.label = name.value; });
        const brand = h("select", { class: "input" }, base.brands.map((b) => h("option", { value: b.key, selected: b.key === store.brand }, b.label)));
        brand.addEventListener("change", () => { store.brand = brand.value; });
        const coords = h("span", { class: "mono muted" }, afkCoords(store.x != null ? store : null));
        const move = (delta) => { d.stores.splice(index + delta, 0, d.stores.splice(index, 1)[0]); paintClothing(); };
        return h("div", { class: "card creator-spawn" },
            h("div", { class: "creator-spawn-head" }, h("b", null, `Magasin ${index + 1}`),
                h("div", { class: "creator-spawn-toggle" }, draftToggle(store, "enabled", "Ouvert", "Visible et utilisable en jeu")),
                h("button", { class: "btn small ghost sq-btn", title: "Monter", disabled: index === 0, onclick: () => move(-1) }, "↑"),
                h("button", { class: "btn small ghost sq-btn", title: "Descendre", disabled: index === d.stores.length - 1, onclick: () => move(1) }, "↓"),
                h("button", { class: "btn small danger", onclick: () => { d.stores.splice(index, 1); paintClothing(); } }, icon("i-trash"), "Retirer")),
            fieldRow("Nom", name),
            fieldRow("Enseigne", brand),
            h("div", { class: "driving-spot" }, h("b", null, "Point du magasin ([E])"), coords,
                h("button", { class: "btn small ghost", onclick: async () => {
                    const p = await othersMyPosition();
                    if (!p) return;
                    Object.assign(store, { x: p.x, y: p.y, z: p.z, h: p.h });
                    coords.textContent = afkCoords(p);
                } }, icon("i-crosshair"), "Définir position"),
                h("button", { class: "btn small ghost", onclick: () => (store.x != null ? act("others.tp", { x: store.x, y: store.y, z: store.z, h: store.h }, null) : toast("Position non définie.", "error")) }, icon("i-goto"), "TP")),
            h("div", { class: "mode-list" },
                draftToggle(store, "blip", "Blip sur la carte", "À la couleur de l'enseigne (les 15 magasins d'origine ont déjà le leur dans la tuile Blips)."),
                CLOTHING_PAGES.map(([key, label, hint]) => draftToggle(store.pages, key, `Page « ${label} »`, hint))));
    };

    root.replaceChildren(h("div", { class: "content clothing-page" }, head,
        h("div", { class: "scroll others-editor" },
            h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Prix d'une pièce"), prices,
                h("p", { class: "hint-line" }, "Le joueur paie, en liquide ou par carte, les pièces changées au moment de valider. Retirer un accessoire est gratuit ; 0 = gratuit.")),
            h("div", { class: "card" },
                h("p", { class: "hint-line", style: "margin:0" }, "Chaque magasin a son enseigne (bannière en haut du menu) et ses pages d'accueil. Sans magasin enregistré ici, ceux de la config de lunatic_clothing servent."),
                h("div", { class: "btn-row" }, h("button", { class: "btn small primary", onclick: () => {
                    if (d.stores.length >= 40) return toast("40 magasins au maximum.", "error");
                    d.stores.push({ label: "", brand: base.brands[0].key, enabled: true, blip: false, pages: { catalogue: true, ready: true, outfits: true, favorites: true } });
                    paintClothing();
                } }, icon("i-plus"), "Ajouter un magasin"))),
            d.stores.map(card))));
}

async function saveClothing() {
    const res = await act("clothing.save", { stores: clothingState.draft.stores, prices: clothingState.draft.prices }, "Magasins de vêtements enregistrés.");
    if (!res) return;
    untrackUnsaved("others");
    clothingState.draft = null;
    await loadClothing();
}
