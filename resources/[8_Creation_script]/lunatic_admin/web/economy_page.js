"use strict";

// ====================================================================
//  lunatic_admin — tuile Économie
//  Catégories à gauche : salaires (Entreprises, Services publics, Pôle emploi), Autre (aide de l'État, banque,
//  fourrière), Devise et Paycheck. Enregistrement par la barre du bas ; tout s'applique en jeu sans redémarrage.
// ====================================================================

const ecoState = { data: null, cat: "company", job: null, otherTab: "aid", draft: null, saved: "" };

const ECO_CATEGORIES = [
    { id: "company", label: "Entreprises", icon: "i-store" },
    { id: "public", label: "Services publics", icon: "i-shield" },
    { id: "interim", label: "Pôle emploi", icon: "i-briefcase" },
    { id: "other", label: "Autre", icon: "i-bank" },
    { id: "currency", label: "Devise", icon: "i-coins" },
    { id: "paycheck", label: "Paycheck", icon: "i-clock" },
];
const ECO_OTHER_TABS = [
    { id: "aid", label: "Aide de l'État", sub: "Allocations et subventions", color: "#3ecf8e" },
    { id: "bank", label: "Banque", sub: "Plafonds de dépôt", color: "#7c8cff" },
    { id: "impound", label: "Fourrière", sub: "Frais par type de véhicule", color: "#f2994a" },
];
const ECO_CURRENCIES = [
    { symbol: "$", label: "Dollar" },
    { symbol: "€", label: "Euro" },
    { symbol: "£", label: "Livre" },
    { symbol: "¥", label: "Yen" },
    { symbol: "د.إ", label: "Dirham" },
    { symbol: "₽", label: "Rouble" },
];
const ECO_BANK = [
    { key: "standard", label: "Plafond de dépôt" },
    { key: "premium", label: "Plafond de dépôt VIP" },
    { key: "premium_plus", label: "Plafond de dépôt VIP+" },
];
const ECO_IMPOUND = [
    { key: "car", label: "Voiture" },
    { key: "bike", label: "Moto" },
    { key: "truck", label: "Camion" },
    { key: "boat", label: "Bateau" },
    { key: "heli", label: "Hélicoptère" },
    { key: "plane", label: "Avion" },
];

function renderEconomy() {
    if (ecoState.data && $("view-economy").childElementCount) return;
    paintEconomy();
    loadEconomy();
}

async function loadEconomy() {
    const res = await nui("action", { action: "economy.overview", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    ecoState.data = res;
    paintEconomy();
}

// Ce qui est affiché à droite : un métier, un onglet d'« Autre », la devise ou la paie
function ecoContext() {
    const c = ecoState.cat;
    if (c === "other") return `other:${ecoState.otherTab}`;
    if (c === "currency" || c === "paycheck") return c;
    return ecoState.job ? `job:${ecoState.job}` : null;
}

function ecoJob() {
    const list = (ecoState.data.jobs || {})[ecoState.cat] || [];
    return list.find((j) => j.job === ecoState.job) || null;
}

// Change de catégorie, de métier ou d'onglet (en demandant si des modifications ne sont pas enregistrées)
function ecoGo(changes) {
    guardUnsaved("economy", () => {
        untrackUnsaved("economy");
        Object.assign(ecoState, changes, { draft: null });
        paintEconomy();
    });
}

// Brouillon de la section affichée, suivi par la barre « non enregistré »
function ecoDraft() {
    const key = ecoContext();
    if (!key) {
        untrackUnsaved("economy");
        return null;
    }
    if (ecoState.draft && ecoState.draft.key === key) return ecoState.draft;

    const d = ecoState.data;
    const s = d.settings;
    let base = null;
    let label = "Économie";
    if (key.startsWith("job:")) {
        const job = ecoJob();
        if (!job) return null;
        const salaries = {};
        for (const g of job.grades) salaries[g.grade] = g.salary;
        base = { key, salaries };
        label = `Salaires ${job.label}`;
    } else if (key === "other:aid") {
        base = { key, unemployed: d.unemployed, allowances: { ...s.allowances } };
        label = "Aide de l'État";
    } else if (key === "other:bank") {
        base = { key, bank: { ...s.bank } };
        label = "Plafonds de banque";
    } else if (key === "other:impound") {
        base = { key, impound: { ...s.impound } };
        label = "Frais de fourrière";
    } else if (key === "currency") {
        base = { key, currency: s.currency };
        label = "Devise";
    } else if (key === "paycheck") {
        base = { key, paycheckMinutes: s.paycheckMinutes };
        label = "Intervalle de paie";
    }

    ecoState.draft = base;
    ecoState.saved = JSON.stringify(base);
    trackUnsaved("economy", {
        label,
        isDirty: () => !!ecoState.draft && JSON.stringify(ecoState.draft) !== ecoState.saved,
        save: () => saveEconomy(),
        reset: () => { ecoState.draft = null; paintEconomy(); },
    });
    return base;
}

async function saveEconomy() {
    const d = ecoState.draft;
    if (!d) return;
    let res;
    if (d.key.startsWith("job:")) {
        res = await act("economy.salaries", { job: d.key.slice(4), salaries: d.salaries }, "Salaires enregistrés.");
    } else {
        const section = d.key.startsWith("other:") ? d.key.slice(6) : d.key;
        res = await act("economy.saveSettings", { section, ...d, key: undefined }, "Réglages enregistrés.");
    }
    if (!res) return;
    untrackUnsaved("economy");
    ecoState.draft = null;
    await loadEconomy();
}

// ---------- Mise en page ----------

function paintEconomy() {
    const root = $("view-economy");
    const d = ecoState.data;
    if (!d) return root.replaceChildren(h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-coins"), "Chargement de l'économie…")));

    const count = (id) => (d.jobs[id] ? d.jobs[id].length : id === "other" ? 3 : null);
    const sidebar = h("aside", { class: "sidebar eco-side" },
        h("div", { class: "side-head" }, icon("i-coins"), h("h3", null, "Catégories")),
        h("div", { class: "side-scroll" }, ECO_CATEGORIES.map((c) =>
            h("button", { class: `list-row${c.id === ecoState.cat ? " active" : ""}`, onclick: () => c.id !== ecoState.cat && ecoGo({ cat: c.id, job: null }) },
                icon(c.icon), h("span", { class: "name" }, c.label), count(c.id) !== null ? h("span", { class: "cnt" }, String(count(c.id))) : null))));

    let main;
    if (ecoState.cat === "other") main = ecoOther();
    else if (ecoState.cat === "currency") main = ecoCurrency();
    else if (ecoState.cat === "paycheck") main = ecoPaycheck();
    else main = ecoSalaries();

    const scroller = root.querySelector(".eco-scroll");
    const top = scroller ? scroller.scrollTop : 0;
    root.replaceChildren(h("div", { class: "eco-page" }, sidebar, main));
    const fresh = root.querySelector(".eco-scroll");
    if (fresh && top) fresh.scrollTop = top;
}

// Logo de la structure, sinon initiale sur sa couleur
function ecoLogo(job, size) {
    const box = h("span", { class: "eco-logo" });
    box.style.width = box.style.height = `${size}px`;
    const initial = () => {
        box.replaceChildren((job.label || job.job).slice(0, 1).toUpperCase());
        box.style.background = job.color || "#9650ff";
    };
    if (job.logo) {
        const img = h("img", { src: job.logo, alt: "" });
        img.addEventListener("error", initial);
        box.append(img);
    } else {
        initial();
    }
    return box;
}

function ecoSalaries() {
    const cat = ECO_CATEGORIES.find((c) => c.id === ecoState.cat);
    const list = ecoState.data.jobs[ecoState.cat] || [];
    const grid = list.length
        ? h("div", { class: "eco-grid" }, list.map((j) =>
            h("button", { class: `eco-job${j.job === ecoState.job ? " on" : ""}`, onclick: () => j.job !== ecoState.job && ecoGo({ job: j.job }) },
                ecoLogo(j, 54), h("b", null, j.label), h("span", null, j.typeLabel))))
        : h("div", { class: "empty" }, icon(cat.icon), ecoState.cat === "interim" ? "Aucun métier du Pôle emploi (hors entreprises et services publics)." : `Aucune structure dans « ${cat.label} ».`);

    return h("div", { class: "eco-jobs" },
        h("section", { class: "eco-main eco-scroll" }, h("div", { class: "eco-title" }, icon("i-coins"), "Salaire", h("span", { class: "muted" }, ` · ${cat.label}`)), grid),
        ecoSelection());
}

function ecoAmount(value, max, onChange, suffix) {
    const input = h("input", { class: "input mono", type: "number", min: "0", max: String(max), step: "1", value: String(value) });
    input.addEventListener("input", () => onChange(input.value === "" ? "" : Number(input.value)));
    return h("label", { class: "eco-amount" }, input, h("span", { class: "muted" }, suffix ?? currencySymbol()));
}

function ecoSelection() {
    const job = ecoState.job && ecoJob();
    if (!job) {
        return h("aside", { class: "item-editor eco-selection" }, h("div", { class: "empty" }, icon("i-briefcase"), "Choisissez un métier pour régler ses salaires."));
    }
    const d = ecoDraft();
    const minutes = ecoState.data.settings.paycheckMinutes;
    const rows = job.grades.map((g) => h("div", { class: "eco-grade" },
        h("span", { class: "eco-rank mono" }, String(g.grade)),
        h("span", { class: "eco-grade-name" }, g.label),
        ecoAmount(d.salaries[g.grade], ecoState.data.limits.salary, (v) => { d.salaries[g.grade] = v; })));

    return h("aside", { class: "item-editor eco-selection" },
        h("div", { class: "item-head" }, h("div", { class: "pic" }, ecoLogo(job, 64)),
            h("div", { class: "who" }, h("b", null, job.label), h("span", { class: "mono" }, job.typeLabel))),
        h("div", { class: "item-scroll" },
            h("div", { class: "eco-sub" }, `Salaire toutes les ${minutes} minutes`),
            rows.length ? rows : h("p", { class: "hint-line" }, "Ce métier n'a pas de grade."),
            h("p", { class: "hint-line" }, "Versé sur le compte en banque à chaque paie, réduit hors service (config ESX). Enregistrez avec la barre du bas.")));
}

// Carte « libellé + montant » (Autre)
function ecoCard(label, value, max, onChange, hint) {
    return h("div", { class: "eco-card" }, h("span", { class: "eco-card-label" }, label), hint ? h("span", { class: "hint-line" }, hint) : null, ecoAmount(value, max, onChange));
}

function ecoOther() {
    const d = ecoDraft();
    const data = ecoState.data;
    const tab = ecoState.otherTab;
    const tabs = h("div", { class: "eco-tabs" }, ECO_OTHER_TABS.map((t) => {
        const b = h("button", { class: `eco-tab${t.id === tab ? " on" : ""}`, onclick: () => t.id !== tab && ecoGo({ otherTab: t.id }) },
            h("span", { class: "eco-dot" }), h("span", null, h("b", null, t.label), h("small", null, t.sub)));
        b.style.setProperty("--tab", t.color);
        return b;
    }));

    let cards;
    let defaults;
    if (tab === "aid") {
        cards = [
            ecoCard("Allocation chômage", d.unemployed, data.limits.salary, (v) => { d.unemployed = v; }, "Joueurs sans emploi, à chaque paie"),
            ecoCard("Allocation VIP", d.allowances.premium, data.limits.allowance, (v) => { d.allowances.premium = v; }, "En plus du salaire, à chaque paie"),
            ecoCard("Allocation VIP+", d.allowances.premium_plus, data.limits.allowance, (v) => { d.allowances.premium_plus = v; }, "En plus du salaire, à chaque paie"),
        ];
        defaults = () => { d.unemployed = data.defaultUnemployed; d.allowances = { ...data.defaults.allowances }; };
    } else if (tab === "bank") {
        cards = ECO_BANK.map((b) => ecoCard(b.label, d.bank[b.key], data.limits.bank, (v) => { d.bank[b.key] = v; }));
        defaults = () => { d.bank = { ...data.defaults.bank }; };
    } else {
        cards = ECO_IMPOUND.map((i) => ecoCard(i.label, d.impound[i.key], data.limits.impound, (v) => { d.impound[i.key] = v; }));
        defaults = () => { d.impound = { ...data.defaults.impound }; };
    }
    const pending = tab === "aid" ? null : h("p", { class: "hint-line" }, tab === "bank"
        ? "Enregistré pour le futur script de banque : pas encore utilisé en jeu."
        : "Enregistré pour le futur script de garage / fourrière : pas encore utilisé en jeu.");

    return h("section", { class: "eco-main eco-scroll eco-wide" },
        tabs,
        h("div", { class: "eco-cards" }, cards),
        pending,
        h("div", { class: "btn-row" }, h("button", { class: "btn small ghost", onclick: () => { defaults(); paintEconomy(); } }, icon("i-undo"), "Valeurs par défaut")));
}

function ecoCurrency() {
    const d = ecoDraft();
    const choose = (symbol) => { d.currency = symbol; paintEconomy(); };
    const known = ECO_CURRENCIES.find((c) => c.symbol === d.currency);
    const custom = h("input", { class: "input eco-symbol", maxlength: "4", value: d.currency });
    custom.addEventListener("change", () => { if (custom.value.trim()) choose(custom.value.trim()); });

    return h("section", { class: "eco-main eco-scroll eco-wide" },
        h("div", { class: "eco-title" }, icon("i-coins"), "Symbole monétaire", h("span", { class: "muted" }, " · affiché dans nos menus (panel, entreprises, illégal…)")),
        h("div", { class: "eco-preview" }, h("span", { class: "eco-big" }, d.currency),
            h("span", null, h("b", null, known ? known.label : "Symbole personnalisé"), h("small", null, `Exemple : 1 250 ${d.currency}`))),
        h("div", { class: "eco-currencies" }, ECO_CURRENCIES.map((c) =>
            h("button", { class: `eco-currency${c.symbol === d.currency ? " on" : ""}`, onclick: () => choose(c.symbol) }, h("span", { class: "eco-big" }, c.symbol), h("span", null, c.label)))),
        h("div", { class: "eco-card eco-row" }, h("span", { class: "eco-card-label" }, "Symbole personnalisé (4 caractères maximum)"), custom),
        h("p", { class: "hint-line" }, "L'icône d'argent de l'inventaire (ox_inventory) ne change pas."));
}

function ecoPaycheck() {
    const d = ecoDraft();
    const limits = ecoState.data.limits;
    return h("section", { class: "eco-main eco-scroll eco-wide" },
        h("div", { class: "eco-title" }, icon("i-clock"), "Configuration du versement"),
        h("div", { class: "eco-cards" },
            h("div", { class: "eco-card" }, h("span", { class: "eco-card-label" }, "Intervalle de paie"),
                h("span", { class: "hint-line" }, `Temps entre deux salaires pour tous les joueurs (de ${limits.paycheckMin} à ${limits.paycheckMax} min)`),
                ecoAmount(d.paycheckMinutes, limits.paycheckMax, (v) => { d.paycheckMinutes = v; }, "min"))),
        h("p", { class: "hint-line" }, "Pris en compte tout de suite par la paie d'ESX, avec les allocations de l'onglet Autre."),
        h("div", { class: "btn-row" }, h("button", { class: "btn small ghost", onclick: () => { d.paycheckMinutes = ecoState.data.defaults.paycheckMinutes; paintEconomy(); } }, icon("i-undo"), "Valeur par défaut")));
}
