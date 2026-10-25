"use strict";

// ====================================================================
//  lunatic_admin — tuile Items
//  Objets d'ox_inventory : catégories, grille, fiche (propriétés, consommation), dupliquer, give, supprimer.
//  Les changements s'appliquent en jeu au prochain redémarrage du serveur (ox_inventory les charge au démarrage).
// ====================================================================

const itemsState = { data: null, category: "consumable", search: "", selected: null, draft: null, saved: "", painted: false, images: {} };

const ITEM_DEFAULTS = { category: "object", name: "", label: "", weight: 100, price: 0, image: "", prop: "", anim: "", premium: false, permanent: false, hunger: 0, thirst: 0, expiration: 0, usetime: 3, description: "", stack: true, close: true };

function itemImageSrc(name, image) {
    if (image && /^[a-z]+:\/\//i.test(image)) return image;
    if (image) return `nui://ox_inventory/web/images/${image}`;
    return itemsState.images[name] || `nui://ox_inventory/web/images/${name}.png`;
}

function renderItems() {
    if (itemsState.painted && $("view-items").childElementCount) return;
    itemsState.painted = true;
    paintItems();
    loadItems();
}

async function loadItems() {
    const [res, images] = await Promise.all([
        nui("action", { action: "items.list", payload: {} }).catch(() => null),
        nui("itemImages", {}).catch(() => null),
    ]);
    if (!res || !res.ok) return;
    if (images && typeof images === "object") itemsState.images = images;
    itemsState.data = res;
    paintItems();
}

function selectItem(name) {
    if (itemsState.selected === name && itemsState.draft) return;
    guardUnsaved("items", () => doSelectItem(name));
}

async function doSelectItem(name) {
    untrackUnsaved("items");
    itemsState.selected = name;
    itemsState.draft = null;
    refreshSelection();
    const res = await nui("action", { action: "items.info", payload: { name } }).catch(() => null);
    if (itemsState.selected !== name) return;
    if (!res || !res.ok) return toast((res && res.error) || "Objet introuvable.", "error");
    startDraft(res.item);
}

function startDraft(item) {
    itemsState.draft = { ...ITEM_DEFAULTS, ...item };
    itemsState.saved = JSON.stringify(itemsState.draft);
    trackUnsaved("items", {
        label: `Objet ${itemsState.draft.label || itemsState.draft.name || "nouveau"}`,
        isDirty: () => !!itemsState.draft && JSON.stringify(itemsState.draft) !== itemsState.saved,
        save: () => saveItem(),
        reset: () => (itemsState.draft.create ? startDraft({ ...ITEM_DEFAULTS, category: itemsState.draft.category, create: true }) : doSelectItem(itemsState.selected)),
    });
    refreshSelection();
}

// Case active dans la grille et fiche à droite, sans reconstruire la grille
function refreshSelection() {
    document.querySelectorAll("#itemsGrid .item-tile").forEach((tile) => tile.classList.toggle("active", tile.dataset.name === itemsState.selected));
    const editor = document.querySelector("#view-items .item-editor");
    if (editor) editor.replaceWith(itemEditor());
}

function newItem() {
    guardUnsaved("items", () => {
        untrackUnsaved("items");
        itemsState.selected = null;
        const category = ["consumable", "object", "drug"].includes(itemsState.category) ? itemsState.category : "object";
        startDraft({ ...ITEM_DEFAULTS, category, create: true });
    });
}

async function saveItem() {
    const d = itemsState.draft;
    if (!d) return;
    const res = await act("items.save", d, d.create ? "Objet créé : en jeu au prochain redémarrage." : "Objet enregistré : en jeu au prochain redémarrage.");
    if (!res) return;
    itemsState.selected = d.name;
    d.create = false;
    itemsState.saved = JSON.stringify(d);
    await loadItems();
    doSelectItem(d.name);
}

// ---------- Rendu ----------

function paintItems() {
    const root = $("view-items");
    const data = itemsState.data;
    if (!data) return root.replaceChildren(h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-box"), "Chargement des objets…")));

    // Colonne de gauche : catégories, recherche, modifications en attente
    const counts = {};
    for (const item of data.items) counts[item.category] = (counts[item.category] || 0) + 1;
    const search = h("input", { placeholder: "Rechercher un objet", value: itemsState.search });
    search.addEventListener("input", () => { itemsState.search = search.value; paintItemGrid(); });

    const pending = data.pending.length ? h("div", { class: "items-pending" },
        h("b", null, icon("i-warn"), `${data.pending.length} modification${data.pending.length > 1 ? "s" : ""} en attente`),
        h("span", null, "Appliquée" + (data.pending.length > 1 ? "s" : "") + " en jeu au prochain redémarrage du serveur."),
        h("div", { class: "items-pending-list" }, data.pending.slice(0, 6).map((p) => h("span", null, `${p.label} · ${p.operation}`))),
        can("server.manage") ? h("button", { class: "btn small", onclick: () => go("server") }, icon("i-server"), "Planifier un redémarrage") : null) : null;

    const sidebar = h("aside", { class: "sidebar items-side" },
        h("div", { class: "side-head" }, h("h3", null, "Catégories")),
        h("div", { class: "side-scroll" },
            data.categories.map((c) => h("button", { class: `list-row${c.id === itemsState.category ? " active" : ""}`, onclick: () => { itemsState.category = c.id; paintItems(); } },
                h("span", { class: "name" }, c.label), h("span", { class: "cnt" }, String(counts[c.id] || 0)))),
            h("div", { class: "side-search", style: "margin-top:8px" }, h("label", { class: "search" }, icon("i-search"), search)),
            pending));

    const grid = h("div", { class: "items-grid", id: "itemsGrid" });
    const center = h("div", { class: "content items-center" },
        h("div", { class: "page-head" }, h("div", { class: "grow" },
            h("h1", { class: "page-title" }, (data.categories.find((c) => c.id === itemsState.category) || {}).label || "Items"),
            h("div", { class: "page-sub" }, "Objets d'ox_inventory. Les changements s'appliquent en jeu au prochain redémarrage du serveur."))),
        h("div", { class: "scroll" }, grid));

    root.replaceChildren(h("div", { class: "items-page" }, sidebar, center, itemEditor()));
    paintItemGrid();
}

function paintItemGrid() {
    const grid = $("itemsGrid");
    const data = itemsState.data;
    if (!grid || !data) return;
    const text = itemsState.search.trim().toLowerCase();
    const editable = (data.categories.find((c) => c.id === itemsState.category) || {}).editable;
    const list = data.items.filter((i) => (text ? (i.label.toLowerCase().includes(text) || i.name.toLowerCase().includes(text)) : i.category === itemsState.category));

    const tiles = list.map((i) => {
        const img = h("img", { src: itemImageSrc(i.name, i.image), alt: "", loading: "lazy" });
        img.addEventListener("error", () => { img.style.visibility = "hidden"; });
        return h("button", { class: `item-tile${i.name === itemsState.selected ? " active" : ""}`, title: i.name, "data-name": i.name, onclick: () => selectItem(i.name) },
            i.pending ? h("span", { class: "item-flag", title: `En attente du redémarrage (${i.pending})` }) : null,
            h("div", { class: "pic" }, img), h("span", null, i.label));
    });

    grid.replaceChildren(
        ...(editable && !text ? [h("button", { class: "item-tile item-new", onclick: newItem }, h("div", { class: "pic" }, icon("i-plus")), h("span", null, "Créer un item"))] : []),
        ...(!editable && !text ? [h("p", { class: "hint-line items-note" }, "Armes et munitions sont définies dans weapons.lua : création et modification à venir. Le Give fonctionne déjà.")] : []),
        ...tiles,
        ...(!tiles.length && (text || !editable) ? [h("div", { class: "empty", style: "grid-column:1/-1" }, "Aucun objet.")] : []));
}

function itemEditor() {
    const d = itemsState.draft;
    const data = itemsState.data;
    if (!d) return h("aside", { class: "item-editor" }, h("div", { class: "empty" }, icon("i-box"), itemsState.selected ? "Chargement…" : "Choisissez un objet ou créez-en un."));

    const editable = ["consumable", "object", "drug"].includes(d.category) && !d.weapon;
    const bind = (input, key, parse) => {
        input.addEventListener("input", () => { d[key] = parse ? parse(input.value) : input.value; });
        input.addEventListener("change", () => { d[key] = parse ? parse(input.value) : input.value; });
        return input;
    };
    const int = (v) => Math.max(0, Math.floor(Number(v) || 0));
    const num = (key, min, max) => bind(h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(d[key]), disabled: !editable }), key, int);
    const row = (label, control) => h("div", { class: "item-field" }, h("label", null, label), control);
    const toggle = (label, hint, key) => {
        const el = h("div", { class: `perm${d[key] ? " on" : ""}${editable ? "" : " locked"}` }, h("span", { class: "switch" }), h("span", { class: "txt" }, h("span", null, label), h("code", null, hint)));
        if (editable) el.addEventListener("click", () => { d[key] = !d[key]; el.classList.toggle("on", d[key]); });
        return el;
    };

    const preview = h("img", { src: itemImageSrc(d.name, d.image), alt: "" });
    preview.addEventListener("error", () => { preview.style.visibility = "hidden"; });
    const refreshPreview = () => { preview.style.visibility = "visible"; preview.src = itemImageSrc(d.name, d.image); };

    const category = bind(h("select", { class: "input", disabled: !editable }, data.categories.filter((c) => c.editable).map((c) => h("option", { value: c.id, selected: c.id === d.category }, c.label))), "category");
    category.addEventListener("change", () => refreshSelection());
    const name = bind(h("input", { class: "input mono", maxlength: "60", value: d.name, disabled: !d.create, placeholder: "ex. cafe_latte" }), "name", (v) => v.trim().toLowerCase());
    name.addEventListener("change", refreshPreview);
    const label = bind(h("input", { class: "input", maxlength: "60", value: d.label, disabled: !editable }), "label");
    const image = bind(h("input", { class: "input mono", maxlength: "255", value: d.image, disabled: !editable, placeholder: `${d.name || "nom"}.png ou https://…` }), "image", (v) => v.trim());
    image.addEventListener("input", refreshPreview);
    const description = bind(h("input", { class: "input", maxlength: "200", value: d.description, disabled: !editable }), "description");

    // Objet en main : liste, ou modèle libre
    const knownProp = !d.prop || data.props.some((p) => p.id === d.prop);
    const propSelect = h("select", { class: "input", disabled: !editable }, [h("option", { value: "" }, "Aucun"), ...data.props.map((p) => h("option", { value: p.id, selected: p.id === d.prop }, p.label)), h("option", { value: "__custom", selected: !knownProp }, "Autre modèle…")]);
    const propCustom = h("input", { class: "input mono", maxlength: "60", value: knownProp ? "" : d.prop, placeholder: "nom du modèle (prop_…)", disabled: !editable });
    propCustom.style.display = knownProp ? "none" : "";
    propSelect.addEventListener("change", () => {
        propCustom.style.display = propSelect.value === "__custom" ? "" : "none";
        d.prop = propSelect.value === "__custom" ? propCustom.value.trim() : propSelect.value;
    });
    propCustom.addEventListener("input", () => { d.prop = propCustom.value.trim(); });
    const anim = bind(h("select", { class: "input", disabled: !editable }, [h("option", { value: "" }, "Aucune"), ...data.anims.map((a) => h("option", { value: a.id, selected: a.id === d.anim }, a.label))]), "anim");

    const listed = data.items.find((i) => i.name === d.name) || {};
    const consumable = d.category === "consumable" || d.category === "drug";

    const actions = editable ? h("div", { class: "item-actions" },
        d.create ? null : h("button", { class: "btn small", onclick: () => duplicateItem(d) }, icon("i-copy"), "Dupliquer"),
        d.create ? null : h("button", { class: "btn small", disabled: listed.pending === "nouveau", title: listed.pending === "nouveau" ? "Pas encore en jeu" : null, onclick: () => giveItem(d) }, icon("i-plus"), "Give"),
        h("button", { class: "btn small primary", onclick: saveItem }, icon("i-save"), d.create ? "Créer" : "Enregistrer"),
        d.create || !listed.modified ? null : h("button", { class: "btn small danger", onclick: () => deleteItem(d, listed) }, icon(listed.created ? "i-trash" : "i-undo"), listed.created ? "Supprimer" : "Réinitialiser"))
        : h("div", { class: "item-actions" }, h("button", { class: "btn small primary", onclick: () => giveItem(d) }, icon("i-plus"), "Give"),
            h("p", { class: "hint-line", style: "margin:0;grid-column:1/-1" }, "Armes et munitions : définies dans weapons.lua, modifiables plus tard."));

    return h("aside", { class: "item-editor" },
        h("div", { class: "item-head" }, h("div", { class: "pic" }, preview),
            h("div", { class: "who" }, h("b", null, d.label || "Nouvel objet"), h("span", { class: "mono" }, d.name || "id à choisir"),
                listed.pending ? h("span", { class: "badge warn", style: "justify-self:start" }, `en attente : ${listed.pending}`) : listed.modified ? h("span", { class: "badge muted", style: "justify-self:start" }, listed.created ? "créé dans le panel" : "modifié dans le panel") : null)),
        h("div", { class: "item-scroll" },
            h("div", { class: "section-head" }, "Propriétés générales"),
            row("Catégorie", category),
            row("ID unique", name),
            row("Label", label),
            row("Poids (grammes)", num("weight", 0, 1000000)),
            row("Prix d'achat ($)", num("price", 0, 10000000)),
            row("Image", image),
            row("Description", description),
            h("div", { class: "mode-list" },
                toggle("VIP", "Achetable seulement par les joueurs VIP (magasins du panel).", "premium"),
                toggle("Permanent", "Ne quitte jamais l'inventaire : ni jeté, ni donné, ni rangé.", "permanent"),
                toggle("Empilable", "Plusieurs exemplaires dans une même case.", "stack")),
            consumable ? h("div", null,
                h("div", { class: "section-head", style: "margin-top:14px" }, "Consommation"),
                row("Faim restaurée (%)", num("hunger", 0, 100)),
                row("Soif restaurée (%)", num("thirst", 0, 100)),
                row("Expiration (heures, 0 = jamais)", num("expiration", 0, 8760)),
                row("Animation", anim),
                row("Objet en main", h("div", { class: "item-prop" }, propSelect, propCustom)),
                row("Durée d'utilisation (s)", num("usetime", 1, 30))) : null),
        actions);
}

// ---------- Actions ----------

function duplicateItem(d) {
    const target = h("input", { class: "input mono", maxlength: "60", value: `${d.name}_2` });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-copy"), "Dupliquer");
        submit.addEventListener("click", async () => {
            const res = await act("items.duplicate", { name: d.name, target: target.value.trim().toLowerCase(), item: { ...d, label: `${d.label} (copie)` } }, "Copie créée : en jeu au prochain redémarrage.");
            if (!res) return;
            close();
            await loadItems();
            doSelectItem(target.value.trim().toLowerCase());
        });
        return [
            h("header", null, h("h3", null, `Dupliquer ${d.label}`), h("p", null, "Nouvel ID de l'objet (lettres minuscules, chiffres, _ et -).")),
            h("div", { class: "body" }, target),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    target.focus();
}

function giveItem(d) {
    const list = (state.players || []).slice().sort((a, b) => a.serverId - b.serverId);
    const player = h("select", { class: "input" }, list.map((p) => h("option", { value: String(p.serverId) }, `[${p.serverId}] ${p.name}`)));
    const count = h("input", { class: "input mono", type: "number", min: "1", value: "1" });
    openModal((close) => {
        const submit = h("button", { class: "btn primary", disabled: !list.length }, icon("i-plus"), "Donner");
        submit.addEventListener("click", async () => {
            const res = await act("items.give", { name: d.name, serverId: Number(player.value), count: Number(count.value) }, `${d.label} donné.`);
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, `Give · ${d.label}`)),
            h("div", { class: "body event-form" },
                list.length ? h("div", { class: "field" }, h("label", null, "Joueur connecté"), player) : h("p", { class: "hint-line" }, "Aucun joueur connecté."),
                h("div", { class: "field" }, h("label", null, "Quantité"), count)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
}

async function deleteItem(d, listed) {
    const yes = await confirmBox(listed.created ? `Supprimer « ${d.label} » ?` : `Réinitialiser « ${d.label} » ?`,
        listed.created ? "L'objet disparaît au prochain redémarrage ; les joueurs qui l'ont le gardent comme objet inconnu." : "L'objet reprend sa définition d'origine (items.lua) au prochain redémarrage.",
        listed.created ? "Supprimer" : "Réinitialiser", true);
    if (!yes) return;
    const res = await act("items.delete", { name: d.name }, listed.created ? "Objet supprimé." : "Objet réinitialisé.");
    if (!res) return;
    untrackUnsaved("items");
    itemsState.draft = null;
    itemsState.selected = listed.created ? null : d.name;
    await loadItems();
    if (!listed.created) doSelectItem(d.name);
}
