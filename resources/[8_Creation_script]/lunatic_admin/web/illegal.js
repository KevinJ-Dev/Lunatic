"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal
//  Trois colonnes : pages et blocs propres à la page à gauche, liste ou grille au centre, fiche « Sélection » à droite.
//  Pages : Territoires, Craft, Tablette, Drogues, Missions, Braquages, Recelleur (un fichier par page).
// ====================================================================

const ILLEGAL_PAGES = [
    { value: "territories", label: "Zones de territoires", icon: "i-flag" },
    { value: "craft", label: "Craft", icon: "i-tool" },
    { value: "tablet", label: "Tablette", icon: "i-box" },
    { value: "drugs", label: "Drogues", icon: "i-sparkle" },
    { value: "missions", label: "Missions", icon: "i-crosshair" },
    { value: "heists", label: "Braquages", icon: "i-gem" },
    { value: "fence", label: "Recelleur", icon: "i-mask" },
];

// draft : fiche en cours de modification { kind, key, data } ; prefill : valeurs d'une fiche « nouvelle » (copie, position cliquée)
const illegalState = { tab: "territories", fence: null, painted: false, draft: null, saved: "", prefill: null, fenceSel: null, fenceCategory: null };

function renderIllegal() {
    if (illegalState.painted && $("view-illegal").childElementCount) return;
    illegalState.painted = true;
    paintIllegal();
    loadFence();
    // Liste des objets (champs « objet ») et vraies images d'ox_inventory
    loadCatalogItems().then(() => paintIllegal());
    nui("itemImages", {}).catch(() => null).then((images) => {
        if (images && typeof images === "object") itemsState.images = images;
        paintIllegal();
    });
}

async function loadFence() {
    const res = await nui("action", { action: "fence.info", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    illegalState.fence = res;
    if (illegalState.tab === "fence") paintIllegal();
}

async function fenceAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) await loadFence();
    return res;
}

// ---------- Fiche en cours : brouillon et changement de sélection ----------

// Change de page ou de sélection, après confirmation si la fiche a des modifications non enregistrées
function illegalSwitch(change) {
    guardUnsaved("illegal", () => {
        untrackUnsaved("illegal");
        illegalState.draft = null;
        change();
        paintIllegal();
    });
}

// Brouillon de la fiche affichée : créé à son premier affichage, suivi par la barre « non enregistré »
function illegalDraft(kind, key, label, init, save) {
    const current = illegalState.draft;
    if (current && current.kind === kind && current.key === key) return current.data;
    const prefill = illegalState.prefill;
    illegalState.prefill = null;
    const data = { ...init(), ...(key === "new" && prefill ? prefill : {}) };
    illegalState.draft = { kind, key, data };
    illegalState.saved = JSON.stringify(data);
    trackUnsaved("illegal", {
        label,
        isDirty: () => !!illegalState.draft && JSON.stringify(illegalState.draft.data) !== illegalState.saved,
        save,
        reset: () => { illegalState.draft = null; paintIllegal(); },
    });
    return data;
}

// Après un enregistrement ou une suppression : la fiche repart des données du serveur
function illegalSaved() {
    untrackUnsaved("illegal");
    illegalState.draft = null;
}

const knownItem = (name) => !catalogItems || catalogItems.some((i) => i.name === name);
const latestOf = (list) => list.reduce((best, entry) => (!best || entry.id > best.id ? entry : best), null);

// ---------- Rendu commun ----------

function paintIllegal() {
    const root = $("view-illegal");
    const sameTab = root.dataset.tab === illegalState.tab;
    const keep = sameTab ? [...root.querySelectorAll("[data-keep-scroll]")].map((el) => [el.dataset.keepScroll, el.scrollTop]) : [];
    root.dataset.tab = illegalState.tab;
    const page = illegalPage();

    const pages = ILLEGAL_PAGES.map((p) => h("button", { class: `list-row page-row${p.value === illegalState.tab ? " active" : ""}`, onclick: () => p.value !== illegalState.tab && illegalSwitch(() => { illegalState.tab = p.value; }) },
        icon(p.icon), h("span", { class: "name" }, p.label)));

    const sidebar = h("aside", { class: "sidebar illegal-side" },
        h("div", { class: "side-scroll", "data-keep-scroll": "side" }, sideBlock("Pages", null, pages), page.side || []));

    const center = h("div", { class: "content illegal-center" },
        h("div", { class: "page-head illegal-head" },
            h("div", { class: "illegal-title-row" }, h("h1", { class: "page-title" }, page.title), page.actions ? h("div", { class: "btn-row" }, page.actions) : null),
            page.sub ? h("div", { class: "page-sub" }, page.sub) : null),
        h("div", { class: "scroll", "data-keep-scroll": "center" }, page.center));

    root.replaceChildren(h("div", { class: `illegal-page ${page.layout || (page.editor ? "" : "no-editor")}` }, sidebar, center, page.editor || null));
    for (const [key, top] of keep) {
        const el = root.querySelector(`[data-keep-scroll="${key}"]`);
        if (el) el.scrollTop = top;
    }
    if (page.mounted) page.mounted();
}

function illegalPage() {
    switch (illegalState.tab) {
        case "territories": return territoriesPage();
        case "craft": return workshopsPage();
        case "tablet": return marketPage();
        case "drugs": return drugsPage();
        case "missions": return missionsPage();
        case "heists": return holdupsPage();
        default: return fencePage();
    }
}

const illegalLoading = (title, iconName, text) => ({ title, center: h("div", { class: "empty" }, icon(iconName), text) });

// Bloc de la colonne de gauche (titre, bouton facultatif, contenu)
function sideBlock(title, action, ...children) {
    return h("div", { class: "side-block" }, h("div", { class: "side-block-head" }, h("span", null, title), action || null), children.flat(Infinity));
}

// Petit bouton icône (colonne de gauche, lignes compactes)
const iconButton = (name, title, onclick, extra) => h("button", { class: `btn small ghost sq-btn${extra ? ` ${extra}` : ""}`, title, onclick }, icon(name));

// Ligne d'emplacement : numéro, nom ou coordonnées, boutons Définir / TP / Supprimer…
function pointLine(index, title, coords, buttons) {
    return h("div", { class: "side-point" },
        h("span", { class: "pid mono" }, String(index)),
        h("div", { class: "who" }, title ? h("b", null, title) : null, h("span", { class: "mono" }, `${coords.x.toFixed(0)}  ${coords.y.toFixed(0)}  ${coords.z.toFixed(0)}`)),
        h("div", { class: "btn-row" }, buttons));
}

// Case de la grille avec l'image de l'objet
function illegalTile({ item, label, badge, active, warn, off, onclick }) {
    const img = h("img", { src: itemImageSrc(item), alt: "", loading: "lazy" });
    img.addEventListener("error", () => { img.style.visibility = "hidden"; });
    return h("button", { class: `item-tile${active ? " active" : ""}${off ? " off" : ""}`, title: item, onclick },
        badge ? h("span", { class: "tile-badge" }, badge) : null,
        warn ? h("span", { class: "item-flag", title: "À compléter" }) : null,
        h("div", { class: "pic" }, img), h("span", null, label));
}

const newTile = (label, onclick, active) => h("button", { class: `item-tile item-new${active ? " active" : ""}`, onclick }, h("div", { class: "pic" }, icon("i-plus")), h("span", null, label));

// Fiche « Sélection » : aperçu, informations, boutons en bas
function selectionPanel({ item, title, sub, badges, body, actions }) {
    const preview = h("img", { src: itemImageSrc(item || ""), alt: "" });
    preview.addEventListener("error", () => { preview.style.visibility = "hidden"; });
    return h("aside", { class: "item-editor" },
        h("div", { class: "item-head" }, h("div", { class: "pic" }, item ? preview : icon("i-box")),
            h("div", { class: "who" }, h("b", null, title), sub ? h("span", { class: "mono" }, sub) : null, badges || null)),
        h("div", { class: "item-scroll" }, body),
        h("div", { class: `item-actions${actions.filter(Boolean).length > 2 ? " three" : ""}` }, actions));
}

const emptySelection = (iconName, text) => h("aside", { class: "item-editor" }, h("div", { class: "empty" }, icon(iconName), text));

const fieldRow = (label, control) => h("div", { class: "item-field" }, h("label", null, label), control);

// Champs liés au brouillon
function draftNumber(d, key, min, max) {
    const input = h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(d[key]) });
    input.addEventListener("input", () => { d[key] = Number(input.value); });
    return input;
}

function draftText(d, key, attrs = {}) {
    const input = h("input", { class: "input", maxlength: "60", ...attrs, value: d[key] ?? "" });
    input.addEventListener("input", () => { d[key] = input.value; });
    return input;
}

function draftItem(d, key, onChange) {
    const input = catalogItems ? itemPicker(catalogItems, d[key]) : h("input", { class: "input mono", maxlength: "60", value: d[key] || "" });
    input.addEventListener("input", () => { d[key] = input.value.trim(); });
    if (onChange) input.addEventListener("change", onChange);
    return input;
}

function draftToggle(d, key, label, hint) {
    const row = h("div", { class: `perm${d[key] ? " on" : ""}` }, h("span", { class: "switch" }), h("span", { class: "txt" }, h("span", null, label), hint ? h("code", null, hint) : null));
    row.addEventListener("click", () => { d[key] = !d[key]; row.classList.toggle("on", d[key]); });
    return row;
}

// Liste d'ingrédients modifiable (objet + quantité), dans le brouillon
function draftIngredients(d) {
    const list = h("div", { class: "ingredient-list" });
    const paint = () => list.replaceChildren(...d.ingredients.map((entry, index) => {
        const name = catalogItems ? itemPicker(catalogItems, entry.item) : h("input", { class: "input mono", value: entry.item });
        const amount = h("input", { class: "input mono", type: "number", min: "1", value: String(entry.count) });
        name.addEventListener("input", () => { entry.item = name.value.trim(); });
        amount.addEventListener("input", () => { entry.count = Number(amount.value || 1); });
        return h("div", { class: "ingredient-row" }, name, amount,
            h("button", { class: "btn small ghost", disabled: d.ingredients.length <= 1, onclick: () => { d.ingredients.splice(index, 1); paint(); } }, icon("i-trash")));
    }));
    paint();
    return h("div", { class: "field" }, list,
        h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
            if (d.ingredients.length >= 10) return toast("10 ingrédients maximum.", "error");
            d.ingredients.push({ item: "", count: 1 });
            paint();
        } }, icon("i-plus"), "Ajouter un ingrédient"));
}

// Boutons standard de la fiche
const deleteButton = (onclick) => h("button", { class: "btn small danger", onclick }, icon("i-trash"), "Supprimer");
const duplicateButton = (onclick) => h("button", { class: "btn small", onclick }, icon("i-copy"), "Dupliquer");
const saveButton = (onclick, create) => h("button", { class: "btn small primary", onclick }, icon("i-save"), create ? "Créer" : "Enregistrer");

// ---------- Recelleur ----------

function fenceProblems(f) {
    const problems = [];
    if (!f.items.length) problems.push("aucun objet racheté");
    if (!f.locations.length) problems.push("aucun recelleur placé");
    const unknown = f.items.filter((i) => i.missing).length;
    if (unknown) problems.push(`${unknown} objet${unknown > 1 ? "s" : ""} inconnu${unknown > 1 ? "s" : ""}`);
    return problems;
}

function fencePage() {
    const f = illegalState.fence;
    if (!f) return illegalLoading("Recelleur", "i-mask", "Chargement du recelleur…");
    const problems = fenceProblems(f);
    const filter = f.categories.includes(illegalState.fenceCategory) ? illegalState.fenceCategory : null;

    const chips = h("div", { class: "chip-row" }, [null, ...f.categories].map((c) =>
        h("button", { class: `chip${c === filter ? " on" : ""}`, onclick: () => { illegalState.fenceCategory = c; paintIllegal(); } }, c || `Tous (${f.items.length})`)));

    const tiles = f.items.filter((i) => !filter || i.category === filter).map((i) => illegalTile({
        item: i.item, label: i.label, badge: money(i.price), active: illegalState.fenceSel === i.id, warn: i.missing,
        onclick: () => illegalState.fenceSel !== i.id && illegalSwitch(() => { illegalState.fenceSel = i.id; }),
    }));

    const locations = f.locations.map((l, index) => pointLine(index + 1, l.ped, l, [
        iconButton("i-crosshair", "Placer le PNJ à votre position et orientation", () => fenceAct("fence.moveLocation", { id: l.id }, "Recelleur replacé à votre position.")),
        iconButton("i-goto", "TP", () => act("fence.tpLocation", { id: l.id }, null)),
        iconButton("i-player", "Modèle du PNJ", () => openFencePed(l)),
        iconButton("i-trash", "Supprimer", () => fenceAct("fence.deleteLocation", { id: l.id }, "Recelleur supprimé.")),
    ]));

    return {
        title: "Recelleur",
        sub: "Objets rachetés aux joueurs (argent sale) et emplacements des PNJ.",
        actions: [readyBadge(problems)],
        side: [sideBlock(`Emplacements (${f.locations.length})`,
            iconButton("i-plus", "Ajouter un recelleur à votre position", () => fenceAct("fence.addLocation", { ped: f.defaultPed }, "Recelleur ajouté à votre position.")),
            locations.length ? locations : h("p", { class: "hint-line" }, "Aucun recelleur placé : personne ne peut revendre."),
            h("p", { class: "hint-line" }, "Le PNJ apparaît là où vous vous tenez, tourné dans votre direction. Pas de blip."))],
        center: h("div", null, readyHint(problems), chips,
            h("div", { class: "items-grid" }, newTile("Ajouter un objet", () => illegalSwitch(() => { illegalState.fenceSel = "new"; }), illegalState.fenceSel === "new"), tiles)),
        editor: fenceEditor(),
    };
}

function fenceEditor() {
    const f = illegalState.fence;
    const sel = illegalState.fenceSel;
    const entry = f.items.find((i) => i.id === sel);
    if (!entry && sel !== "new") return emptySelection("i-mask", "Choisissez un objet ou ajoutez-en un.");

    const d = illegalDraft("fence", sel, entry ? `Recelleur : ${entry.label}` : "Nouvel objet du recelleur",
        () => (entry ? { item: entry.item, price: entry.price, category: entry.category } : { item: "", price: 0, category: illegalState.fenceCategory || f.categories[0] || "Objets volés" }),
        saveFence);

    const listId = "fence-categories";
    document.getElementById(listId)?.remove();
    document.body.append(h("datalist", { id: listId }, f.categories.map((c) => h("option", { value: c }))));

    return selectionPanel({
        item: d.item, title: entry ? entry.label : "Nouvel objet", sub: d.item || "objet à choisir",
        badges: entry && entry.missing ? h("span", { class: "badge ban", style: "justify-self:start" }, "objet inconnu") : null,
        body: [
            h("div", { class: "section-head" }, "Informations"),
            fieldRow("Objet", draftItem(d, "item", () => paintIllegal())),
            fieldRow("Prix de rachat ($)", draftNumber(d, "price", 0, 10000000)),
            fieldRow("Catégorie", draftText(d, "category", { list: listId, maxlength: "40" })),
            h("p", { class: "hint-line" }, "Prix payé au joueur pour une unité."),
        ],
        actions: [
            entry ? deleteButton(async () => {
                const yes = await confirmBox(`Retirer « ${entry.label} » du recelleur ?`, "Il ne sera plus racheté.", "Retirer", true);
                if (!yes) return;
                const res = await act("fence.deleteItem", { id: entry.id }, "Objet retiré.");
                if (!res) return;
                illegalSaved();
                illegalState.fenceSel = null;
                await loadFence();
            }) : null,
            entry ? duplicateButton(() => illegalSwitch(() => { illegalState.fenceSel = "new"; illegalState.prefill = { ...d }; })) : null,
            saveButton(saveFence, !entry),
        ],
    });
}

async function saveFence() {
    const draft = illegalState.draft;
    if (!draft || draft.kind !== "fence") return;
    const d = draft.data;
    if (!knownItem(d.item)) return toast(`L'objet « ${d.item} » n'existe pas dans ox_inventory.`, "error");
    const creating = draft.key === "new";
    const res = await act("fence.saveItem", { id: creating ? null : draft.key, item: d.item, price: Number(d.price), category: String(d.category || "").trim() }, creating ? "Objet ajouté." : "Objet modifié.");
    if (!res) return;
    illegalSaved();
    await loadFence();
    if (creating) {
        const added = latestOf(illegalState.fence.items.filter((i) => i.item === d.item));
        illegalState.fenceSel = added ? added.id : null;
    }
    paintIllegal();
}

function openFencePed(location) {
    const input = h("input", { class: "input mono", maxlength: "40", value: location.ped });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Changer");
        submit.addEventListener("click", async () => {
            const res = await fenceAct("fence.setPed", { id: location.id, ped: input.value.trim() }, "Modèle du PNJ changé.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, "Modèle du PNJ"), h("p", null, "Nom d'un modèle de PNJ du jeu (ex. s_m_y_dealer_01, g_m_y_ballasout_01). Vérifié par votre jeu.")),
            h("div", { class: "body" }, input),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    input.focus();
}
