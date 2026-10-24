"use strict";

// ====================================================================
//  lunatic_admin — tuile Boutique (organisation comme Vision)
//  Onglet Boutique : statistiques, catégories, bandeaux, notification en jeu, monnaie, transactions.
//  Onglet Premium : prix et avantages de Premium / Premium+ (l'aide de l'État est celle de la tuile Économie).
//  Packs, Véhicules et Armes : partie 2. La boutique des joueurs : partie 3.
// ====================================================================

const storeState = { data: null, tab: "shop", tier: "premium", draft: null, saved: "" };

const STORE_TABS = [
    { value: "shop", label: "Boutique" },
    { value: "premium", label: "Premium" },
    { value: "packs", label: "Packs", soon: true },
    { value: "vehicles", label: "Véhicules", soon: true },
    { value: "weapons", label: "Armes", soon: true },
];

const STORE_CATEGORIES = [["premium", "Premium"], ["premium_plus", "Premium+"], ["vehicles", "Véhicules"], ["packs", "Packs"], ["weapons", "Armes"], ["credits", null]];

// Avantages des abonnements : [clé, libellé, pas, appliqué en jeu ?]
const STORE_PERKS = [
    ["priceEuro", "Prix (€)", "1", "Affiché dans la boutique (achat en euros : plus tard, avec Tebex)."],
    ["priceCredits", "Prix en crédits (30 jours)", "1", "Achat de l'abonnement avec des crédits dans la boutique."],
    ["includedCredits", "Crédits inclus", "1", "Offerts à l'achat en euros (plus tard, avec Tebex)."],
    ["salaryMultiplier", "Multiplicateur salaire", "0.05", "Appliqué : bonus versé par l'État à chaque paie."],
    ["characters", "Personnages", "1", "Enregistré pour le futur multi-personnage."],
    ["garageSlots", "Places garage public", "1", "Enregistré pour le futur script de garage."],
    ["farmMultiplier", "Limite farm", "0.05", "Enregistré pour les futurs scripts de récolte."],
    ["outfits", "Limite de tenues", "1", "Enregistré pour le futur vestiaire."],
];

const storeCreditsName = () => (storeState.draft && storeState.draft.credits.name) || "Crédits";

function renderStore() {
    const root = $("view-shop");
    if (storeState.data && root.childElementCount) return;
    paintStore();
    loadStore();
}

async function loadStore() {
    const res = await nui("action", { action: "shop.info", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    storeState.data = res;
    if (!isUnsaved("shop")) storeState.draft = null;
    paintStore();
}

function storeDraft() {
    if (storeState.draft) return storeState.draft;
    const s = storeState.data.settings;
    const base = {
        categories: { ...s.categories },
        banners: s.banners.map((b) => ({ ...b })),
        notification: { enabled: s.notification.enabled, title: s.notification.title, text: s.notification.text, color: s.notification.color, image: s.notification.image, hours: s.notification.hours },
        credits: { ...s.credits },
        tiers: { premium: { ...s.tiers.premium }, premium_plus: { ...s.tiers.premium_plus } },
        allowances: { ...s.allowances },
    };
    storeState.draft = base;
    storeState.saved = JSON.stringify(base);
    trackUnsaved("shop", {
        label: "Réglages de la boutique",
        isDirty: () => !!storeState.draft && JSON.stringify(storeState.draft) !== storeState.saved,
        save: () => saveStore(),
        reset: () => { storeState.draft = null; paintStore(); },
    });
    return base;
}

async function saveStore() {
    const res = await act("shop.save", storeState.draft, "Boutique enregistrée.");
    if (!res) return;
    untrackUnsaved("shop");
    storeState.draft = null;
    await loadStore();
}

function paintStore() {
    const root = $("view-shop");
    if (!storeState.data) return root.replaceChildren(h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-gem"), "Chargement de la boutique…")));
    const d = storeDraft();

    const tabs = h("div", { class: "segmented shop-tabs" }, STORE_TABS.map((t) => h("button", {
        "aria-checked": String(storeState.tab === t.value), class: t.soon ? "soon" : null, title: t.soon ? "Partie 2" : null,
        onclick: () => { if (!t.soon) { storeState.tab = t.value; paintStore(); } },
    }, t.label)));

    root.replaceChildren(h("div", { class: "shop-page" }, h("div", { class: "shop-top" }, tabs),
        h("div", { class: "shop-body crew-scroll" }, storeState.tab === "premium" ? storePremiumTab(d) : storeMainTab(d))));
}

// ---------- Onglet Boutique ----------

function storeMainTab(d) {
    const st = storeState.data.stats;
    const stat = (iconName, value, label) => h("div", { class: "shop-stat" }, icon(iconName), h("b", { class: "mono" }, new Intl.NumberFormat("fr-FR").format(value)), h("span", null, label));

    const transactions = storeState.data.transactions;
    const catLabel = (c) => (c === "credits" ? storeCreditsName() : (STORE_CATEGORIES.find((x) => x[0] === c) || [c, c])[1]);
    const txTable = h("div", { class: "shop-tx" },
        h("div", { class: "shop-tx-row head" }, h("span", null, "Utilisateur"), h("span", null, "Catégorie"), h("span", null, "Produit"), h("span", null, "Date"), h("span", null, storeCreditsName())),
        ...(transactions.length ? transactions.map((t) => h("div", { class: "shop-tx-row" },
            h("span", null, t.name || "?"), h("span", null, catLabel(t.category)), h("span", null, t.product), h("span", { class: "muted" }, fmtDate(t.created)), h("b", { class: "mono" }, String(t.amount))))
            : [h("div", { class: "empty small" }, "Aucune transaction : les achats de la boutique joueur s'afficheront ici.")]));

    const left = h("div", { class: "shop-col" },
        h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Statistiques"),
            h("div", { class: "shop-stats" },
                stat("i-coins", st.credits, `${storeCreditsName()} en circulation`),
                stat("i-crown", st.subscriptions, "Abonnements actifs"),
                stat("i-car", st.vehicles, "Véhicules vendus"),
                stat("i-crosshair", st.weapons, "Armes vendues"))),
        h("div", { class: "card shop-tx-card" }, h("div", { class: "crew-sub" }, `Transactions (${transactions.length})`), txTable));

    return h("div", { class: "shop-grid" }, left, h("div", { class: "shop-col" },
        h("div", { class: "card shop-settings" },
            h("div", null, h("div", { class: "crew-sub" }, "Catégories"),
                h("div", { class: "mode-list" }, STORE_CATEGORIES.map(([key, label]) => draftToggle(d.categories, key, label || d.credits.name, null)))),
            storeBanners(d),
            storeNotification(d)),
        storeCredits(d)));
}

function storeBanners(d) {
    const list = h("div", { class: "shop-banners" });
    const paint = () => list.replaceChildren(...(d.banners.length ? d.banners.map((b, index) => {
        const color = h("input", { type: "color", class: "shop-color", value: b.color });
        color.addEventListener("input", () => { b.color = color.value; });
        const text = h("input", { class: "input", maxlength: "120", placeholder: "Texte du bandeau (ex. -30 % sur les véhicules)", value: b.text });
        text.addEventListener("input", () => { b.text = text.value; });
        const image = h("input", { class: "input mono", maxlength: "255", placeholder: "Image https (facultatif)", value: b.image });
        image.addEventListener("input", () => { b.image = image.value.trim(); });
        const active = h("button", { class: `shop-switch${b.active ? " on" : ""}`, title: b.active ? "Affiché" : "Masqué", onclick: () => { b.active = !b.active; active.classList.toggle("on", b.active); } });
        return h("div", { class: "shop-banner" }, h("div", { class: "shop-banner-line" }, color, text, active,
            h("button", { class: "btn small ghost sq-btn", title: "Retirer", onclick: () => { d.banners.splice(index, 1); paint(); } }, icon("i-trash"))), image);
    }) : [h("p", { class: "hint-line" }, "Aucun bandeau.")]));
    paint();
    return h("div", null, h("div", { class: "crew-sub" }, "Bandeaux"), list,
        h("button", { class: "btn small ghost", style: "margin-top:6px", onclick: () => {
            if (d.banners.length >= 6) return toast("6 bandeaux au maximum.", "error");
            d.banners.push({ text: "Nouveautés", color: "#f2c26b", image: "", active: true });
            paint();
        } }, icon("i-plus"), "Ajouter un bandeau"));
}

function storeNotification(d) {
    const n = d.notification;
    const preview = h("div", { class: "shop-notif" });
    const paintPreview = () => {
        preview.style.background = n.color;
        preview.replaceChildren(...[n.image ? h("img", { src: n.image, alt: "", onerror: (e) => { e.target.remove(); } }) : null, h("div", null, h("b", null, n.title || "Titre"), h("span", null, n.text))].filter(Boolean));
    };
    paintPreview();
    const title = h("input", { class: "input", maxlength: "60", value: n.title });
    title.addEventListener("input", () => { n.title = title.value; paintPreview(); });
    const text = h("input", { class: "input", maxlength: "200", value: n.text });
    text.addEventListener("input", () => { n.text = text.value; paintPreview(); });
    const color = h("input", { type: "color", class: "shop-color", value: n.color });
    color.addEventListener("input", () => { n.color = color.value; paintPreview(); });
    const image = h("input", { class: "input mono", maxlength: "255", placeholder: "Image https", value: n.image });
    image.addEventListener("change", () => { n.image = image.value.trim(); paintPreview(); });
    const hoursValue = h("span", { class: "mono zone-value" }, `${n.hours} h`);
    const hours = h("input", { type: "range", class: "zone-range", min: "1", max: "72", value: String(n.hours) });
    hours.addEventListener("input", () => { n.hours = Number(hours.value); hoursValue.textContent = `${n.hours} h`; });
    const s = storeState.data.settings.notification;
    return h("div", null, h("div", { class: "crew-sub" }, "Notification"),
        h("div", { class: "mode-list" }, draftToggle(n, "enabled", "Statut", s.live ? "En cours d'affichage en jeu." : "Activée : affichée en jeu pendant la durée choisie.")),
        h("div", { class: "shop-fields" },
            fieldRow("Compte à rebours", h("div", { class: "zone-slider" }, hours, hoursValue)),
            fieldRow("Couleur", color),
            fieldRow("Titre", title),
            fieldRow("Texte", text),
            fieldRow("Image", image)),
        preview);
}

function storeCredits(d) {
    const preview = h("div", { class: "shop-currency" });
    const paintPreview = () => preview.replaceChildren(d.credits.image ? h("img", { src: d.credits.image, alt: "", onerror: (e) => { e.target.remove(); } }) : icon("i-coins"), h("b", null, d.credits.name || "Crédits"));
    paintPreview();
    const name = h("input", { class: "input", maxlength: "20", value: d.credits.name });
    name.addEventListener("input", () => { d.credits.name = name.value; paintPreview(); });
    const image = h("input", { class: "input mono", maxlength: "255", placeholder: "Image https (icône de la monnaie)", value: d.credits.image });
    image.addEventListener("change", () => { d.credits.image = image.value.trim(); paintPreview(); });
    return h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Monnaie de la boutique"),
        h("div", { class: "shop-fields" }, fieldRow("Nom", name), fieldRow("Image", image)), preview,
        h("p", { class: "hint-line", style: "margin:0" }, "Les crédits se donnent depuis la fiche joueur (onglet Personnage). Achat en euros : plus tard, avec Tebex."));
}

// ---------- Onglet Premium ----------

function storePremiumTab(d) {
    const tier = storeState.tier;
    const perks = d.tiers[tier];
    const label = tier === "premium_plus" ? "Premium+" : "Premium";
    const tierSeg = h("div", { class: "segmented" }, segmentedButtons([{ value: "premium", label: "Premium" }, { value: "premium_plus", label: "Premium+" }], tier, (v) => { storeState.tier = v; paintStore(); }));

    const price = h("b", { class: "shop-price" });
    const paintPrice = () => price.replaceChildren(`${perks.priceEuro} €`, h("span", { class: "muted" }, ` · ${perks.priceCredits} ${storeCreditsName()}`));
    paintPrice();

    const field = ([key, text, step, hint]) => {
        const input = h("input", { class: "input mono", type: "number", min: "0", step, value: String(perks[key]) });
        input.addEventListener("input", () => { perks[key] = Number(input.value || 0); paintPrice(); });
        return h("div", { class: "shop-perk" }, h("label", null, text), input, h("span", { class: "hint-line" }, hint));
    };
    const allowance = h("input", { class: "input mono", type: "number", min: "0", step: "1", value: String(d.allowances[tier] ?? 0) });
    allowance.addEventListener("input", () => { d.allowances[tier] = Number(allowance.value || 0); });

    return h("div", { class: "shop-premium" },
        h("div", { class: "shop-premium-top" }, tierSeg),
        h("div", { class: "card" },
            h("div", { class: "shop-premium-head" }, h("h3", { class: "card-title" }, label), price),
            h("div", { class: "crew-sub" }, "Configuration"),
            h("div", { class: "shop-perks" },
                ...STORE_PERKS.map(field),
                h("div", { class: "shop-perk" }, h("label", null, `Aide de l'État (${currencySymbol()} par paie)`), allowance,
                    h("span", { class: "hint-line" }, "Appliqué : même réglage que la tuile Économie (versé à chaque paie).")))),
        h("p", { class: "hint-line" }, "Les scripts lisent les avantages d'un joueur avec exports.lunatic_admin:getPremiumPerks(source)."));
}
