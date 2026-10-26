"use strict";

// Magasins de vêtements (lunatic_clothing) : accueil, catalogue par groupe et catégorie, essayage en direct, panier.
// L'interface ne fait qu'afficher : le jeu applique les pièces, le serveur recalcule le prix au paiement.

const $ = (id) => document.getElementById(id);
const inGame = typeof GetParentResourceName === "function";
const resource = inGame ? GetParentResourceName() : "lunatic_clothing";

function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
        if (value === null || value === undefined || value === false) continue;
        if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
        else if (key === "class") el.className = value;
        else if (key === "html") el.innerHTML = value;
        else el.setAttribute(key, value === true ? "" : value);
    }
    for (const child of children.flat(Infinity)) {
        if (child === null || child === undefined || child === false) continue;
        el.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return el;
}

async function nui(name, payload) {
    if (!inGame) return demo(name, payload);
    const res = await fetch(`https://${resource}/${name}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) });
    return res.json();
}

function toast(text) {
    const el = $("toast");
    el.textContent = text;
    el.classList.add("on");
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => el.classList.remove("on"), 3500);
}

// Icônes (traits SVG, reprises de lunatic_creator)
const ICONS = {
    shirt: "M8 3 3 6l2 4 2-1v12h10V9l2 1 2-4-5-3a4 4 0 0 1-8 0z",
    pants: "M6 3h12l1 18h-5l-2-11-2 11H5z",
    shoe: "M3 17v-6l5-1 3 3 9 2v3H3zM3 17h17",
    hat: "M4 16c0-5 3-9 8-9s8 4 8 9M2 16h20",
    watch: "M9 3h6l1 4M9 3 8 7M8 17l1 4h6l1-4M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 10v2l1 1",
    bag: "M5 8h14l-1 13H6zM9 8V6a3 3 0 0 1 6 0v2",
    catalogue: "M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z",
    back: "M15 6l-6 6 6 6",
    arms: "M12 7a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM5 3l3 7h8l3-7M9 10l1 12M15 10l-1 12",
};
const svg = (name) => h("span", { html: `<svg class="i" viewBox="0 0 24 24"><path d="${ICONS[name] || ICONS.shirt}"/></svg>` }).firstChild;

// Pages de l'accueil (celles de la partie 2 s'ajouteront ici)
const PAGES = [
    { id: "catalogue", label: "Catalogue", text: "Toutes les pièces, à essayer librement", icon: "catalogue" },
];
const CAMERAS = [["head", "Visage"], ["torso", "Buste"], ["legs", "Jambes"], ["feet", "Pieds"], ["full", "Entier"]];

let data = null;      // magasin ouvert (envoyé par le jeu)
let worn = {};        // pièces portées : { clé: [modèle, couleur] }
let original = {};    // tenue à l'ouverture (le panier = les différences)
let view = "home";
let group = null;
let category = null;
let camera = "torso";
let armsUp = false;
let quitting = false;
const countsCache = {};

const categories = () => data.groups.flatMap((g) => g.categories);
const categoryOf = (key) => categories().find((c) => c.key === key);
const groupOf = (key) => data.groups.find((g) => g.key === key);
const money = (n) => `${n} ${data.currency}`;

// ---------- Ouverture ----------

function open(payload) {
    data = payload;
    worn = JSON.parse(JSON.stringify(payload.worn));
    original = JSON.parse(JSON.stringify(payload.worn));
    armsUp = false;
    quitting = false;
    camera = "torso";

    $("shop").style.setProperty("--brand", payload.brand.color);
    $("brand").textContent = payload.brand.label;
    $("brand").className = `brand${payload.brand.label === payload.brand.label.toLowerCase() ? " binco" : ""}`;
    $("storeName").textContent = payload.store;
    $("shop").classList.remove("hidden");

    const pages = availablePages();
    if (pages.length === 1 && pages[0].id === "catalogue") openGroup(data.groups[0].key);
    else { view = "home"; paint(); }
}

function availablePages() {
    return PAGES.filter((p) => data.pages[p.id] !== false);
}

// ---------- Rendu ----------

function paint() {
    $("view").replaceChildren(view === "home" ? homeView() : catalogueView());
    paintCart();
    paintBar();
    paintTools();
}

function homeView() {
    const pages = availablePages();
    if (!pages.length) return h("div", { class: "home" }, h("p", { class: "muted" }, "Ce magasin est fermé pour le moment."));
    return h("div", { class: "home" }, pages.map((p) => h("button", { class: "page-tile", onclick: () => p.id === "catalogue" && openGroup(data.groups[0].key) },
        h("span", { class: "ico" }, svg(p.icon)), h("span", null, h("b", null, p.label), h("p", null, p.text)))));
}

function openGroup(key) {
    const g = groupOf(key);
    if (!g) return;
    view = "catalogue";
    group = g.key;
    category = g.categories[0].key;
    setCamera(g.camera);
    paint();
}

function catalogueView() {
    const g = groupOf(group);
    const c = categoryOf(category);
    const value = worn[c.key] || [0, 0];
    const total = countsCache[`${data.sex}:${c.key}:0`];

    const head = h("div", { class: "view-head" },
        availablePages().length > 1 ? h("button", { class: "back", title: "Accueil", onclick: () => { view = "home"; paint(); } }, svg("back")) : null,
        h("b", null, g.label));
    const tabs = g.categories.length > 1 ? h("div", { class: "tabs" }, g.categories.map((entry) => h("button", {
        class: `tab${entry.key === category ? " on" : ""}`, onclick: () => { category = entry.key; paint(); },
    }, entry.label))) : null;
    const price = h("div", { class: "price-line" }, h("span", null, c.label), h("span", null, c.price > 0 ? h("b", null, `${money(c.price)} la pièce`) : h("b", null, "Gratuit")));

    if (!total) {
        loadCounts(c, 0).then(() => paint());
        return h("div", { class: "view" }, head, tabs, price, h("div", { class: "grid" }, h("p", null, "Chargement…")));
    }

    const isProp = c.kind === "prop";
    const cells = [];
    if (isProp) cells.push(h("button", { class: `cell${value[0] < 0 ? " on" : ""}`, onclick: () => pick(c, -1, 0) }, h("span", { class: "none" }, "✕"), h("small", null, "Aucun")));
    const wornAtOpen = (original[c.key] || [])[0];
    for (let i = 0; i < total.drawables; i += 1) {
        const url = imageOf(c, i, 0);
        cells.push(h("button", { class: `cell${value[0] === i ? " on" : ""}${wornAtOpen === i ? " worn" : ""}`, onclick: () => pick(c, i, 0) },
            url ? h("img", { src: url, alt: "", loading: "lazy", onerror: (e) => e.target.replaceWith(h("span", { class: "num" }, String(i))) }) : h("span", { class: "num" }, String(i)),
            h("small", null, `N° ${i}`)));
    }

    return h("div", { class: "view" }, head, tabs, price, h("div", { class: "grid", id: "grid" }, cells), colorsRow(c, value));
}

// Couleurs du modèle porté (lues dans le jeu)
function colorsRow(c, value) {
    if (value[0] < 0) return null;
    const counts = countsCache[`${data.sex}:${c.key}:${value[0]}`];
    if (!counts) {
        loadCounts(c, value[0]).then(() => paint());
        return null;
    }
    if (counts.textures <= 1) return null;
    const set = (texture) => pick(c, value[0], (texture + counts.textures) % counts.textures);
    return h("div", { class: "colors" }, h("span", null, "Couleur"),
        h("button", { class: "arrow", onclick: () => set(value[1] - 1) }, "‹"),
        h("b", null, `${value[1] + 1} / ${counts.textures}`),
        h("button", { class: "arrow", onclick: () => set(value[1] + 1) }, "›"));
}

async function loadCounts(c, drawable) {
    const key = `${data.sex}:${c.key}:${drawable}`;
    if (!countsCache[key]) countsCache[key] = (await nui("counts", { key: c.key, drawable })) || { drawables: 0, textures: 0 };
    return countsCache[key];
}

function imageOf(c, drawable, texture) {
    const template = c.kind === "prop" ? data.images.prop : data.images.component;
    if (!template) return null;
    return template.replaceAll("{sex}", data.sex).replaceAll("{id}", String(c.id))
        .replaceAll("{drawable}", String(drawable)).replaceAll("{texture}", String(texture));
}

function pick(c, drawable, texture) {
    worn[c.key] = [drawable, texture];
    quitting = false;
    nui("apply", { key: c.key, drawable, texture });
    const grid = $("grid");
    const scroll = grid ? grid.scrollTop : 0;
    paint();
    if ($("grid")) $("grid").scrollTop = scroll;
}

// ---------- Panier ----------

const sameAs = (a, b) => a && b && a[0] === b[0] && (a[0] < 0 || a[1] === b[1]);

function cartLines() {
    return categories().filter((c) => !sameAs(worn[c.key], original[c.key]))
        .map((c) => ({ c, price: worn[c.key][0] < 0 ? 0 : c.price }));
}

function paintCart() {
    const lines = cartLines();
    const total = lines.reduce((sum, l) => sum + l.price, 0);
    const undo = (c) => { pick(c, original[c.key][0], original[c.key][1]); };

    $("cart").replaceChildren(
        h("div", { class: "cart-head" }, h("span", null, lines.length ? `Panier · ${lines.length} pièce${lines.length > 1 ? "s" : ""}` : "Panier vide"), h("b", null, money(total))),
        lines.length ? h("div", { class: "cart-list" }, lines.map((l) => h("span", { class: "chip" }, l.c.label, h("i", null, l.price ? money(l.price) : "gratuit"),
            h("button", { title: "Remettre la pièce d'avant", onclick: () => undo(l.c) }, "✕")))) : null,
        lines.length ? h("div", { class: "pay" },
            h("button", { class: "btn", onclick: () => buy("money") }, total ? "Payer en liquide" : "Valider"),
            total ? h("button", { class: "btn", onclick: () => buy("bank") }, "Payer par carte") : null,
            h("button", { class: "btn ghost wide", onclick: quit }, "Quitter sans acheter"))
            : h("div", { class: "pay" }, h("button", { class: "btn ghost wide", onclick: quit }, "Quitter le magasin")));
}

async function buy(account) {
    const changes = {};
    for (const l of cartLines()) changes[l.c.key] = worn[l.c.key];
    const res = await nui("buy", { account, changes });
    if (!res || !res.ok) return toast((res && res.error) || "Paiement impossible.");
    $("shop").classList.add("hidden");
}

function quit() {
    if (cartLines().length && !quitting) {
        quitting = true;
        return toast("Les pièces non payées seront retirées : recliquez (ou Échap) pour quitter.");
    }
    $("shop").classList.add("hidden");
    nui("close");
}

// ---------- Barre des groupes et caméras ----------

function paintBar() {
    $("bar").replaceChildren(...data.groups.map((g) => h("button", { class: view === "catalogue" && g.key === group ? "on" : "", onclick: () => openGroup(g.key) }, svg(g.icon), g.label)));
}

function paintTools() {
    $("tools").replaceChildren(
        ...CAMERAS.map(([key, label]) => h("button", { class: `tool${camera === key ? " on" : ""}`, onclick: () => { setCamera(key); paintTools(); } }, label)),
        h("button", { class: `tool${armsUp ? " on" : ""}`, onclick: () => { armsUp = !armsUp; nui("armsUp", { on: armsUp }); paintTools(); } }, svg("arms"), "Bras levés"));
}

function setCamera(key) {
    if (camera === key) return;
    camera = key;
    nui("camera", { view: key });
}

// Rotation du personnage : clic maintenu hors du panneau
let dragX = null;
document.addEventListener("mousedown", (e) => { if (!e.target.closest(".panel, .tools, .bar")) dragX = e.clientX; });
document.addEventListener("mouseup", () => { dragX = null; });
document.addEventListener("mousemove", (e) => {
    if (dragX === null) return;
    const delta = e.clientX - dragX;
    if (Math.abs(delta) < 4) return;
    dragX = e.clientX;
    nui("rotate", { delta: delta * 0.6 });
});

document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && data && !$("shop").classList.contains("hidden")) quit();
});

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "open") open(msg.data);
    else if (msg.action === "close") $("shop").classList.add("hidden");
});

// ---------- Aperçu hors jeu ----------

function demo(name, payload) {
    if (name === "counts") return Promise.resolve({ drawables: 24, textures: payload.drawable >= 0 ? 6 : 0 });
    if (name === "buy") return Promise.resolve({ ok: false, error: "Aperçu : pas de paiement hors jeu." });
    return Promise.resolve({});
}

if (!inGame) {
    open({
        store: "Binco de Strawberry", brand: { label: "binco", color: "#f7931e" }, pages: { catalogue: true }, sex: "male", currency: "$",
        images: { component: "", prop: "" },
        worn: { jacket: [4, 0], undershirt: [15, 0], arms: [0, 0], pants: [1, 0], shoes: [1, 0], hat: [-1, 0], glasses: [-1, 0], mask: [0, 0], earrings: [-1, 0], chain: [0, 0], watch: [-1, 0], bracelet: [-1, 0], bag: [0, 0] },
        groups: [
            { key: "tops", label: "Hauts", icon: "shirt", camera: "torso", categories: [{ key: "jacket", label: "Hauts", kind: "component", id: 11, price: 60 }, { key: "undershirt", label: "Sous-hauts", kind: "component", id: 8, price: 30 }, { key: "arms", label: "Bras", kind: "component", id: 3, price: 0 }] },
            { key: "legs", label: "Bas", icon: "pants", camera: "legs", categories: [{ key: "pants", label: "Bas", kind: "component", id: 4, price: 40 }] },
            { key: "feet", label: "Chaussures", icon: "shoe", camera: "feet", categories: [{ key: "shoes", label: "Chaussures", kind: "component", id: 6, price: 40 }] },
            { key: "head", label: "Tête", icon: "hat", camera: "head", categories: [{ key: "hat", label: "Chapeaux", kind: "prop", id: 0, price: 25 }, { key: "glasses", label: "Lunettes", kind: "prop", id: 1, price: 20 }, { key: "mask", label: "Masques", kind: "component", id: 1, price: 30 }, { key: "earrings", label: "Boucles d'oreilles", kind: "prop", id: 2, price: 20 }] },
            { key: "accessories", label: "Accessoires", icon: "watch", camera: "torso", categories: [{ key: "chain", label: "Chaînes et cravates", kind: "component", id: 7, price: 25 }, { key: "watch", label: "Montres", kind: "prop", id: 6, price: 30 }, { key: "bracelet", label: "Bracelets", kind: "prop", id: 7, price: 20 }] },
            { key: "bags", label: "Sacs", icon: "bag", camera: "torso", categories: [{ key: "bag", label: "Sacs", kind: "component", id: 5, price: 35 }] },
        ],
    });
}
