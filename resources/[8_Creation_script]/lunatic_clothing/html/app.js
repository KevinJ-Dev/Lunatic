"use strict";

// Magasins de vêtements et barbiers (lunatic_clothing) : accueil, catalogue par groupe et catégorie, prêt-à-porter,
// mes tenues, favoris et panier ; chez le barbier, coupes et pilosité avec nuancier. L'interface ne fait qu'afficher : le jeu applique les pièces, le serveur vérifie et fait payer.

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

// Icônes (traits SVG, en partie reprises de lunatic_creator)
const ICONS = {
    shirt: "M8 3 3 6l2 4 2-1v12h10V9l2 1 2-4-5-3a4 4 0 0 1-8 0z",
    pants: "M6 3h12l1 18h-5l-2-11-2 11H5z",
    shoe: "M3 17v-6l5-1 3 3 9 2v3H3zM3 17h17",
    hat: "M4 16c0-5 3-9 8-9s8 4 8 9M2 16h20",
    watch: "M9 3h6l1 4M9 3 8 7M8 17l1 4h6l1-4M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 10v2l1 1",
    bag: "M5 8h14l-1 13H6zM9 8V6a3 3 0 0 1 6 0v2",
    glove: "M7 21v-6l-2-4V6a1 1 0 0 1 2 0v4V4a1 1 0 0 1 2 0v6V3a1 1 0 0 1 2 0v7V4a1 1 0 0 1 2 0v8l2-2a1 1 0 0 1 2 1l-4 5v5",
    glasses: "M3 12a3 3 0 1 0 6 0 3 3 0 0 0-6 0M15 12a3 3 0 1 0 6 0 3 3 0 0 0-6 0M9 12h6",
    mask: "M4 8c3-2 13-2 16 0 0 7-3 12-8 12S4 15 4 8zM8 11h2M14 11h2",
    earring: "M12 3v6M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z",
    chain: "M6 4c0 8 3 12 6 12s6-4 6-12M12 16v4",
    bracelet: "M4 12a8 5 0 1 0 16 0 8 5 0 1 0-16 0M7 12a5 2.5 0 1 0 10 0 5 2.5 0 1 0-10 0",
    catalogue: "M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z",
    ready: "M12 3a2 2 0 0 1 2 2c0 1-1 1.5-2 2.5V9l9 7H3l9-7",
    outfits: "M4 7h16v13H4zM9 7V4h6v3M4 12h16",
    star: "M12 3l2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z",
    back: "M15 6l-6 6 6 6",
    arms: "M12 7a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM5 3l3 7h8l3-7M9 10l1 12M15 10l-1 12",
    hair: "M5 15c0-7 3-11 7-11s7 4 7 11M5 15c2-1 3-4 3-7M19 15c-2-1-4-3-5-7M8 20v-5M16 20v-5",
    beard: "M5 5v5c0 6 3 10 7 10s7-4 7-10V5M9 14c1 1 2 1.5 3 1.5s2-.5 3-1.5",
    eyebrows: "M3 10c2-2 5-2 7 0M14 10c2-2 5-2 7 0M5 15h4M15 15h4",
    chest: "M4 8c3-3 13-3 16 0v12H4zM8 12c1 1 2 1 3 0M13 12c1 1 2 1 3 0",
};
const svg = (name) => h("span", { html: `<svg class="i" viewBox="0 0 24 24"><path d="${ICONS[name] || ICONS.shirt}"/></svg>` }).firstChild;

const PAGES = [
    { id: "catalogue", label: "Catalogue", text: "Toutes les pièces, à essayer librement", icon: "catalogue" },
    { id: "ready", label: "Prêt-à-porter", text: "Des tenues complètes, prêtes à porter", icon: "ready" },
    { id: "outfits", label: "Mes tenues", text: "Vos tenues enregistrées, à remettre gratuitement", icon: "outfits" },
    { id: "favorites", label: "Favoris", text: "Les pièces marquées d'une étoile", icon: "star" },
];
const CAMERAS = [["head", "Visage"], ["torso", "Buste"], ["legs", "Jambes"], ["feet", "Pieds"], ["full", "Entier"]];
const BARBER_CAMERAS = [["head", "Visage"], ["headSide", "Profil"], ["headBack", "Arrière"], ["torso", "Buste"]];

let data = null;      // magasin ouvert (envoyé par le jeu)
let worn = {};        // pièces portées : { clé: [modèle, couleur] }
let original = {};    // tenue payée (le panier = les différences)
let view = "home";
let group = null;
let category = null;
let camera = "torso";
let armsUp = false;
let tried = null;     // tenue prêt-à-porter essayée
let favorites = [];   // "clé:modèle:couleur"
let undressed = [];   // boutons « Retirer » actifs (clés de Config.Undress)
let pending = false;
const countsCache = {};

const categories = () => data.groups.flatMap((g) => g.categories);
const categoryOf = (key) => categories().find((c) => c.key === key);
const groupOf = (key) => data.groups.find((g) => g.key === key);
const money = (n) => `${n} ${data.currency}`;

// Fiche d'une pièce (nom, prix, image, bannie) réglée dans la gestion du catalogue
const itemOf = (c, drawable) => (data.items && data.items[c.key] && data.items[c.key][String(drawable)]) || null;
// Prix d'une pièce dans ce magasin : prix de la fiche × coefficient de l'enseigne, sinon prix de la catégorie
function piecePrice(c, drawable) {
    if (drawable < 0) return 0;
    const item = itemOf(c, drawable);
    return item && item.price != null ? Math.floor(item.price * (data.coef || 1) + 0.5) : c.price;
}
const copy = (o) => JSON.parse(JSON.stringify(o));
// Pièce « aucune » : accessoire retiré, calque du visage à opacité nulle (rasé)
const isNone = (c, v) => !v || (c.kind === "prop" && v[0] < 0) || (c.kind === "overlay" && !v[1]);
const barberKind = (c) => c.kind === "hair" || c.kind === "overlay";

// ---------- Ouverture ----------

function open(payload) {
    data = payload;
    worn = copy(payload.worn);
    original = copy(payload.worn);
    favorites = Array.isArray(payload.favorites) ? payload.favorites.slice() : [];
    armsUp = false;
    tried = null;
    undressed = [];
    camera = "torso";

    // Bannière : couleur de l'enseigne, image éventuelle, nom affiché ou non
    const banner = $("banner");
    $("shop").style.setProperty("--brand", payload.brand.color || "#7a3cff");
    banner.style.backgroundImage = payload.brand.image ? `linear-gradient(180deg, #0000 40%, #0008), url("${payload.brand.image}")` : "";
    banner.classList.toggle("with-image", !!payload.brand.image);
    $("brand").textContent = payload.brand.label;
    $("brand").style.color = payload.brand.textColor || "";
    $("brand").className = `brand${payload.brand.label === payload.brand.label.toLowerCase() ? " lower" : ""}`;
    $("brand").classList.toggle("hidden", payload.brand.showText === false);
    $("storeName").textContent = payload.store;
    $("shop").classList.remove("hidden");

    // Barbier : chapeau et masque retirés en entrant (remis en sortant)
    for (const key of payload.autoUndress || []) {
        const u = (payload.undress || []).find((entry) => entry.key === key);
        if (u) undress(u, true);
    }

    const pages = availablePages();
    if (pages.length === 1 && pages[0].id === "catalogue") openGroup(data.groups[0].key);
    else if (pages.length === 1) openPage(pages[0].id);
    else { view = "home"; paint(); }
}

const availablePages = () => PAGES.filter((p) => data.pages[p.id] !== false);

// ---------- Rendu ----------

function paint() {
    const views = { home: homeView, catalogue: catalogueView, ready: readyView, outfits: outfitsView, favorites: favoritesView };
    const grid = $("grid");
    const scroll = grid ? grid.scrollTop : 0;
    $("view").replaceChildren(views[view]());
    if ($("grid")) $("grid").scrollTop = scroll;
    paintCart();
    paintBar();
    paintTools();
    paintUndress();
}

function openPage(id) {
    if (id === "catalogue") return openGroup(data.groups[0].key);
    view = id;
    if ($("grid")) $("grid").scrollTop = 0;
    setCamera(id === "favorites" ? "torso" : "full");
    paint();
}

function viewHead(title) {
    return h("div", { class: "view-head" },
        availablePages().length > 1 ? h("button", { class: "back", title: "Accueil", onclick: () => { view = "home"; paint(); } }, svg("back")) : null,
        h("b", null, title));
}

function homeView() {
    const pages = availablePages();
    if (!pages.length) return h("div", { class: "home" }, h("p", { class: "empty" }, "Ce magasin est fermé pour le moment."));
    return h("div", { class: "home" }, pages.map((p) => h("button", { class: "page-tile", onclick: () => openPage(p.id) },
        h("span", { class: "ico" }, svg(p.icon)), h("span", null, h("b", null, p.label), h("p", null, p.text)))));
}

// ---------- Catalogue ----------

function openGroup(key) {
    const g = groupOf(key);
    if (!g) return;
    if ($("grid")) $("grid").scrollTop = 0;
    view = "catalogue";
    group = g.key;
    category = g.categories[0].key;
    setCamera(g.categories[0].camera || g.camera);
    categoryOpened(g.categories[0]);
    paint();
}

// Catégorie qui demande de retirer une partie de la tenue (pilosité du torse : haut retiré)
function categoryOpened(c) {
    if (!c.undress || undressed.includes(c.undress)) return;
    const u = (data.undress || []).find((entry) => entry.key === c.undress);
    if (u) undress(u, true);
}

function pieceCell(c, drawable, texture, on, extra) {
    const item = drawable >= 0 ? itemOf(c, drawable) : null;
    const fav = `${c.key}:${drawable}:${texture}`;
    const starred = favorites.includes(fav);
    const star = drawable >= 0 && data.pages.favorites !== false ? h("span", {
        class: `star${starred ? " on" : ""}`, title: starred ? "Retirer des favoris" : "Ajouter aux favoris",
        onclick: (e) => { e.stopPropagation(); toggleFavorite(fav); },
    }, starred ? "★" : "☆") : null;
    return h("button", { class: `cell${on ? " on" : ""}${extra || ""}`, onclick: () => pick(c, drawable, texture) }, star,
        drawable < 0 ? h("span", { class: "none" }, "✕")
            : pieceImage(pieceSources(data, c, drawable, itemOf(c, drawable), texture), drawable),
        h("small", null, drawable < 0 ? "Aucun" : (item && item.label) || `N° ${drawable}`));
}

function catalogueView() {
    const g = groupOf(group);
    const c = categoryOf(category);
    const value = worn[c.key] || [0, 0];
    const total = countsCache[`${data.sex}:${c.key}:0`];

    const tabs = g.categories.length > 1 ? h("div", { class: "tabs" }, g.categories.map((entry) => h("button", {
        class: `tab${entry.key === category ? " on" : ""}`, onclick: () => { category = entry.key; setCamera(entry.camera || g.camera); categoryOpened(entry); if ($("grid")) $("grid").scrollTop = 0; paint(); },
    }, entry.label))) : null;
    const current = piecePrice(c, value[0]);
    const none = isNone(c, value);
    const price = h("div", { class: "price-line" }, h("span", null, c.label), h("b", null, none ? "Aucun" : current > 0 ? `${barberKind(c) ? "Prix" : "Cette pièce"} : ${money(current)}` : "Gratuit"));

    if (!total) {
        loadCounts(c, 0).then(() => paint());
        return h("div", { class: "view" }, viewHead(g.label), tabs, price, h("div", { class: "grid" }, h("p", { class: "empty" }, "Chargement…")));
    }

    const paid = (original[c.key] || [])[0];
    const cells = [];
    if (c.kind === "prop" || c.kind === "overlay") cells.push(pieceCell(c, -1, 0, none));
    const paidNone = isNone(c, original[c.key]);
    for (let i = 0; i < total.drawables; i += 1) {
        const item = itemOf(c, i);
        // Pièce bannie : cachée, sauf celle déjà portée
        if (item && item.banned && paid !== i) continue;
        cells.push(pieceCell(c, i, 0, !none && value[0] === i, paid === i && !paidNone ? " worn" : ""));
    }

    return h("div", { class: "view" }, viewHead(g.label), tabs, price, h("div", { class: "grid", id: "grid" }, cells), barberKind(c) ? barberRow(c, value) : colorsRow(c, value));
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
    const fav = `${c.key}:${value[0]}:${value[1]}`;
    return h("div", { class: "colors" }, h("span", null, "Couleur"),
        data.pages.favorites !== false ? h("button", { class: `arrow${favorites.includes(fav) ? " fav" : ""}`, title: "Favori (cette couleur)", onclick: () => toggleFavorite(fav) }, favorites.includes(fav) ? "★" : "☆") : null,
        h("button", { class: "arrow", onclick: () => set(value[1] - 1) }, "‹"),
        h("b", null, `${value[1] + 1} / ${counts.textures}`),
        h("button", { class: "arrow", onclick: () => set(value[1] + 1) }, "›"));
}

async function loadCounts(c, drawable) {
    const key = `${data.sex}:${c.key}:${drawable}`;
    if (!countsCache[key]) countsCache[key] = (await nui("counts", { key: c.key, drawable })) || { drawables: 0, textures: 0 };
    return countsCache[key];
}

// Images d'une pièce, par ordre de préférence : lien de sa fiche, Clothes Renderer (html/renderer/), photo prise en
// jeu (html/clothes/), lien général (panel). cfg = { sex, images, renderer }.
function fillTemplate(template, cfg, c, drawable, texture) {
    return template ? template.replaceAll("{sex}", cfg.sex).replaceAll("{id}", String(c.id))
        .replaceAll("{drawable}", String(drawable)).replaceAll("{texture}", String(texture || 0)) : null;
}

function pieceSources(cfg, c, drawable, item, texture) {
    // Calques du visage (barbe, sourcils…) : pas d'image du jeu, le numéro s'affiche
    if (c.kind === "overlay") return item && item.image ? [item.image] : [];
    const kind = c.kind === "prop" ? "prop" : "component";
    const image = item && item.image;
    const photo = image && image.startsWith("clothes/");
    return [
        image && !photo ? image : null,
        fillTemplate(cfg.renderer && cfg.renderer[kind], cfg, c, drawable, texture),
        photo ? image : null,
        fillTemplate(cfg.images && cfg.images[kind], cfg, c, drawable, texture),
    ].filter(Boolean);
}

// Photo prise en jeu depuis le dernier démarrage de la ressource : son fichier n'est pas encore arrivé, le serveur
// l'envoie (gardée ensuite pour toute la session)
const remoteImages = {};
function remoteImage(path) {
    if (!inGame || !/^clothes\/[\w-]+\.webp$/.test(path)) return Promise.resolve(null);
    if (!(path in remoteImages)) remoteImages[path] = nui("image", { path }).then((res) => (res && res.uri) || null).catch(() => null);
    return remoteImages[path];
}

// Image qui passe à la source suivante si elle est absente (une photo récente est d'abord demandée au serveur), puis au numéro
function pieceImage(sources, drawable) {
    if (!sources.length) return h("span", { class: "num" }, String(drawable));
    let index = 0;
    let asked = false;
    const img = h("img", { src: sources[0], alt: "", loading: "lazy" });
    img.addEventListener("error", async () => {
        if (!asked && !img.src.startsWith("data:")) {
            asked = true;
            const uri = await remoteImage(sources[index]);
            if (uri) { img.src = uri; return; }
        }
        index += 1;
        asked = false;
        if (index < sources.length) img.src = sources[index];
        else img.replaceWith(h("span", { class: "num" }, String(drawable)));
    });
    return img;
}

// Valeur complète d'une pièce choisie dans la grille : chez le barbier, couleurs et opacité gardées
function pieceValue(c, drawable, texture) {
    const current = worn[c.key] || [];
    if (c.kind === "hair") return [drawable, texture, current[2] || 0, current[3] || 0];
    if (c.kind === "overlay") return drawable < 0 ? [current[0] || 0, 0, current[2] || 0] : [drawable, current[1] || 10, current[2] || 0];
    return [drawable, texture];
}

async function pick(c, drawable, texture) {
    await setValue(c, pieceValue(c, drawable, texture));
}

async function setValue(c, value) {
    worn[c.key] = value;
    tried = null;
    // Pièce choisie dans une partie retirée : toute la partie est remise d'abord
    const entry = (data.undress || []).find((u) => undressed.includes(u.key) && u.categories.includes(c.key));
    if (entry) await undress(entry, false);
    nui("apply", { key: c.key, drawable: value[0], texture: value[1], value });
    paint();
}

// ---------- Barbier : variante, opacité et nuancier ----------

function barberRow(c, value) {
    if (isNone(c, value)) return null;
    const rows = [];
    if (c.kind === "hair") {
        const counts = countsCache[`${data.sex}:${c.key}:${value[0]}`];
        if (!counts) loadCounts(c, value[0]).then(() => paint());
        else if (counts.textures > 1) {
            const set = (t) => setValue(c, [value[0], (t + counts.textures) % counts.textures, value[2], value[3]]);
            rows.push(h("div", { class: "colors" }, h("span", null, "Variante"),
                h("button", { class: "arrow", onclick: () => set(value[1] - 1) }, "‹"), h("b", null, `${value[1] + 1} / ${counts.textures}`),
                h("button", { class: "arrow", onclick: () => set(value[1] + 1) }, "›")));
        }
        rows.push(palette("Couleur", value[2], (i) => setValue(c, [value[0], value[1], i, value[3]])));
        rows.push(palette("Reflets", value[3], (i) => setValue(c, [value[0], value[1], value[2], i])));
    } else {
        const set = (o) => setValue(c, [value[0], Math.min(10, Math.max(1, o)), value[2]]);
        rows.push(h("div", { class: "colors" }, h("span", null, "Densité"),
            h("button", { class: "arrow", disabled: value[1] <= 1, onclick: () => set(value[1] - 1) }, "‹"), h("b", null, `${value[1] * 10} %`),
            h("button", { class: "arrow", disabled: value[1] >= 10, onclick: () => set(value[1] + 1) }, "›")));
        rows.push(palette("Couleur", value[2], (i) => setValue(c, [value[0], value[1], i])));
    }
    return h("div", { class: "barber-tools" }, rows);
}

function palette(label, current, set) {
    return h("div", { class: "palette" }, h("span", null, label),
        h("div", { class: "swatches" }, (data.hairColors || []).map((hex, i) => h("button", {
            class: `swatch${i === current ? " on" : ""}`, style: `background:${hex}`, title: `Teinte ${i + 1}`, onclick: () => set(i),
        }))));
}

// ---------- Prêt-à-porter ----------

function readyView() {
    const list = data.ready || [];
    if (!list.length) return h("div", { class: "view" }, viewHead("Prêt-à-porter"), h("p", { class: "empty" }, "Aucune tenue prête dans ce magasin pour le moment."));
    return h("div", { class: "view" }, viewHead("Prêt-à-porter"), h("div", { class: "list", id: "grid" }, list.map((o) => {
        const on = tried === o.id;
        return h("div", { class: `row${on ? " on" : ""}` },
            h("div", { class: "row-main" }, h("b", null, o.label), h("small", null, o.price > 0 ? money(o.price) : "Gratuit")),
            h("div", { class: "row-actions" }, on ? h("span", { class: "tag" }, "Essayée") : h("button", { class: "btn small ghost", onclick: () => tryReady(o) }, "Essayer")));
    })));
}

async function tryReady(o) {
    undressed = [];
    const res = await nui("tryPieces", { pieces: o.pieces });
    if (res && res.worn) worn = res.worn;
    tried = o.id;
    paint();
}

async function buyReady(o, account) {
    pending = true;
    paint();
    const res = await nui("buyReady", { id: o.id, account });
    pending = false;
    if (!res || !res.ok) { paint(); return toast((res && res.error) || "Paiement impossible."); }
    worn = res.worn;
    original = copy(res.worn);
    tried = null;
    undressed = [];
    toast(`Tenue « ${o.label} » achetée.`);
    paint();
}

// ---------- Mes tenues ----------

let editing = null;   // tenue en cours de renommage
let deleting = null;  // tenue dont la suppression attend confirmation

function outfitsView() {
    const list = data.outfits || [];
    const full = list.length >= data.maxOutfits;
    const name = h("input", { class: "input", maxlength: "30", placeholder: "Nom de la tenue (ex. Soirée)" });
    const save = async () => {
        const res = await nui("saveOutfit", { label: name.value });
        if (!res || !res.ok) return toast((res && res.error) || "Enregistrement impossible.");
        data.outfits = res.outfits;
        toast("Tenue enregistrée.");
        paint();
    };
    name.addEventListener("keydown", (e) => { if (e.key === "Enter") save(); });

    return h("div", { class: "view" }, viewHead("Mes tenues"),
        h("div", { class: "save-box" },
            h("div", { class: "save-row" }, name, h("button", { class: "btn small", disabled: full, onclick: save }, "Enregistrer")),
            h("small", null, full ? `${data.maxOutfits} tenues au maximum : supprimez-en une.`
                : `Enregistre la tenue que vous portez déjà (les pièces pas encore payées n'y sont pas). ${list.length} / ${data.maxOutfits}`)),
        h("div", { class: "list", id: "grid" }, list.length ? list.map((o) => outfitRow(o)) : h("p", { class: "empty" }, "Aucune tenue enregistrée.")));
}

function outfitRow(o) {
    const otherSex = o.sex !== data.sex;
    if (editing === o.id) {
        const input = h("input", { class: "input", maxlength: "30", value: o.label });
        const done = async () => {
            const res = await nui("renameOutfit", { id: o.id, label: input.value });
            if (!res || !res.ok) return toast((res && res.error) || "Nom invalide.");
            data.outfits = res.outfits;
            editing = null;
            paint();
        };
        input.addEventListener("keydown", (e) => { if (e.key === "Enter") done(); });
        setTimeout(() => input.focus(), 0);
        return h("div", { class: "row on" }, input, h("div", { class: "row-actions" },
            h("button", { class: "btn small", onclick: done }, "OK"), h("button", { class: "btn small ghost", onclick: () => { editing = null; paint(); } }, "Annuler")));
    }
    return h("div", { class: "row" },
        h("div", { class: "row-main" }, h("b", null, o.label), h("small", null, otherSex ? "Pour l'autre sexe" : "Gratuit à remettre")),
        h("div", { class: "row-actions" },
            h("button", { class: "btn small", disabled: otherSex || pending, onclick: () => wearOutfit(o) }, "Mettre"),
            h("button", { class: "btn small ghost", title: "Renommer", onclick: () => { editing = o.id; deleting = null; paint(); } }, "✎"),
            h("button", { class: `btn small ${deleting === o.id ? "danger" : "ghost"}`, title: "Supprimer", onclick: () => removeOutfit(o) }, deleting === o.id ? "Confirmer" : "🗑")));
}

async function wearOutfit(o) {
    pending = true;
    const res = await nui("wearOutfit", { id: o.id });
    pending = false;
    if (!res || !res.ok) { paint(); return toast((res && res.error) || "Tenue indisponible."); }
    worn = res.worn;
    original = copy(res.worn);
    tried = null;
    undressed = [];
    toast(`Vous portez « ${o.label} ».`);
    paint();
}

async function removeOutfit(o) {
    if (deleting !== o.id) { deleting = o.id; paint(); return; }
    const res = await nui("deleteOutfit", { id: o.id });
    deleting = null;
    if (res && res.ok) data.outfits = res.outfits;
    paint();
}

// ---------- Favoris ----------

function toggleFavorite(fav) {
    const index = favorites.indexOf(fav);
    if (index >= 0) favorites.splice(index, 1);
    else if (favorites.length >= 60) return toast("60 favoris au maximum.");
    else favorites.push(fav);
    nui("favorites", { list: favorites });
    paint();
}

function favoritesView() {
    const entries = favorites.map((fav) => {
        const [key, d, t] = fav.split(":");
        const c = categoryOf(key);
        return c ? { c, drawable: Number(d), texture: Number(t) } : null;
    }).filter(Boolean);
    if (!entries.length) return h("div", { class: "view" }, viewHead("Favoris"), h("p", { class: "empty" }, "Touchez l'étoile d'une pièce dans le catalogue pour la retrouver ici."));
    return h("div", { class: "view" }, viewHead("Favoris"), h("div", { class: "grid", id: "grid" }, entries.map((e) => {
        const value = worn[e.c.key] || [];
        const cell = pieceCell(e.c, e.drawable, e.texture, value[0] === e.drawable && value[1] === e.texture);
        cell.querySelector("small").textContent = `${e.c.label} · ${e.drawable}${e.texture ? `/${e.texture + 1}` : ""}`;
        return cell;
    })));
}

// ---------- Panier ----------

// Même pièce : deux « aucune », ou mêmes valeurs (couleur ignorée pour un accessoire retiré)
function samePiece(c, a, b) {
    if (!a || !b) return false;
    if (isNone(c, a) || isNone(c, b)) return isNone(c, a) && isNone(c, b);
    return a.length === b.length && a.every((value, i) => value === b[i]);
}

function cartLines() {
    return categories().filter((c) => worn[c.key] && !samePiece(c, worn[c.key], original[c.key]))
        .map((c) => ({ c, price: isNone(c, worn[c.key]) ? 0 : piecePrice(c, worn[c.key][0]) }));
}

function paintCart() {
    // Tenue prêt-à-porter essayée : payée à son prix, pas pièce par pièce
    const outfit = tried && (data.ready || []).find((o) => o.id === tried);
    if (outfit) {
        $("cart").replaceChildren(
            h("div", { class: "cart-head" }, h("span", null, `Tenue « ${outfit.label} »`), h("b", null, money(outfit.price))),
            h("div", { class: "pay" },
                h("button", { class: "btn", disabled: pending, onclick: () => buyReady(outfit, "money") }, outfit.price > 0 ? "Payer en liquide" : "Prendre la tenue"),
                outfit.price > 0 ? h("button", { class: "btn", disabled: pending, onclick: () => buyReady(outfit, "bank") }, "Payer par carte") : h("span"),
                h("button", { class: "btn ghost wide", onclick: quit }, "Quitter sans acheter")));
        return;
    }
    const lines = cartLines();
    const total = lines.reduce((sum, l) => sum + l.price, 0);
    const undo = (c) => { setValue(c, original[c.key].slice()); };

    $("cart").replaceChildren(...[
        h("div", { class: "cart-head" }, h("span", null, lines.length ? `Panier · ${lines.length} pièce${lines.length > 1 ? "s" : ""}` : "Panier vide"), h("b", null, money(total))),
        lines.length ? h("div", { class: "cart-list" }, lines.map((l) => h("span", { class: "chip" }, l.c.label, h("i", null, l.price ? money(l.price) : "gratuit"),
            h("button", { title: "Remettre la pièce d'avant", onclick: () => undo(l.c) }, "✕")))) : null,
        h("div", { class: "pay" },
            lines.length ? h("button", { class: "btn", onclick: () => buy("money") }, total ? "Payer en liquide" : "Valider") : null,
            lines.length && total ? h("button", { class: "btn", onclick: () => buy("bank") }, "Payer par carte") : null,
            h("button", { class: "btn ghost wide", onclick: quit }, lines.length ? "Quitter sans acheter" : "Quitter le magasin")),
    ].filter(Boolean));
}

async function buy(account) {
    const changes = {};
    for (const l of cartLines()) changes[l.c.key] = worn[l.c.key];
    const res = await nui("buy", { account, changes });
    if (!res || !res.ok) return toast((res && res.error) || "Paiement impossible.");
    $("shop").classList.add("hidden");
}

// Quitter : direct, les pièces non payées sont retirées par le jeu
function quit() {
    $("shop").classList.add("hidden");
    nui("close");
}

// ---------- Barre des groupes et caméras ----------

function paintBar() {
    const show = data.pages.catalogue !== false;
    $("bar").classList.toggle("hidden", !show);
    if (!show) return;
    $("bar").replaceChildren(...data.groups.map((g) => h("button", { class: view === "catalogue" && g.key === group ? "on" : "", onclick: () => openGroup(g.key) }, svg(g.icon), g.label)));
}

function paintTools() {
    const barber = data.kind === "barber";
    $("tools").replaceChildren(
        ...(barber ? BARBER_CAMERAS : CAMERAS).map(([key, label]) => h("button", { class: `tool${camera === key ? " on" : ""}`, onclick: () => { setCamera(key); paintTools(); } }, label)),
        ...(barber ? [] : [h("button", { class: `tool${armsUp ? " on" : ""}`, onclick: () => { armsUp = !armsUp; nui("armsUp", { on: armsUp }); paintTools(); } }, svg("arms"), "Bras levés")]));
}

// Retirer / remettre une partie de la tenue (vue seulement, rien n'est acheté)
function paintUndress() {
    const list = data.undress || [];
    $("undress").classList.toggle("hidden", !list.length);
    $("undress").replaceChildren(h("small", null, "Retirer"), ...list.map((u) => {
        const off = undressed.includes(u.key);
        return h("button", { class: `tool${off ? " on" : ""}`, title: off ? `Remettre : ${u.label.toLowerCase()}` : `Retirer : ${u.label.toLowerCase()}`, onclick: () => undress(u, !off) },
            svg(u.icon), off ? "Remettre" : u.label);
    }));
}

async function undress(u, on) {
    undressed = undressed.filter((key) => key !== u.key);
    if (on) undressed.push(u.key);
    paintUndress();
    await nui("undress", { key: u.key, on });
}

function setCamera(key) {
    if (camera === key) return;
    camera = key;
    nui("camera", { view: key });
}

// Rotation du personnage : clic maintenu hors du panneau
let dragX = null;
document.addEventListener("mousedown", (e) => { if (!e.target.closest(".panel, .tools, .undress, .bar, .tool-right, .tool-top")) dragX = e.clientX; });
document.addEventListener("mouseup", () => { dragX = null; });
document.addEventListener("mousemove", (e) => {
    if (dragX === null) return;
    const delta = e.clientX - dragX;
    if (Math.abs(delta) < 4) return;
    dragX = e.clientX;
    nui("rotate", { delta: delta * 0.6 });
});

document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && data && !$("shop").classList.contains("hidden") && document.activeElement.tagName !== "INPUT") quit();
    else if (e.key === "Escape" && !$("tool").classList.contains("hidden") && document.activeElement.tagName !== "INPUT") closeTool();
});

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "open") open(msg.data);
    else if (msg.action === "close") $("shop").classList.add("hidden");
});

// ---------- Aperçu hors jeu ----------

function demo(name, payload) {
    if (name === "counts") return Promise.resolve({ drawables: 24, textures: payload.drawable >= 0 ? 6 : 0 });
    if (name === "tryPieces") return Promise.resolve({ worn: { ...worn, ...payload.pieces } });
    if (name === "saveOutfit") return Promise.resolve({ ok: true, outfits: [...data.outfits, { id: Date.now(), label: payload.label, sex: "male" }] });
    if (name === "renameOutfit") return Promise.resolve({ ok: true, outfits: data.outfits.map((o) => (o.id === payload.id ? { ...o, label: payload.label } : o)) });
    if (name === "deleteOutfit") return Promise.resolve({ ok: true, outfits: data.outfits.filter((o) => o.id !== payload.id) });
    if (name === "buy" || name === "buyReady" || name === "wearOutfit") return Promise.resolve({ ok: false, error: "Aperçu : pas d'achat hors jeu." });
    return Promise.resolve({});
}

if (!inGame && location.hash.includes("barber")) {
    const colors = Array.from({ length: 64 }, (_, i) => `hsl(${(i * 23) % 360} 45% ${20 + (i % 8) * 8}%)`);
    open({
        kind: "barber", store: "Herr Kutz de Davis", brand: { label: "BARBER", color: "#1c2a44", textColor: "#f4efe6", image: "", showText: true }, sex: "male", currency: "$",
        pages: { catalogue: true, ready: false, outfits: false, favorites: false }, images: { component: "", prop: "" }, coef: 1, items: {}, ready: [], outfits: [], favorites: [],
        hairColors: colors, autoUndress: ["hat", "mask"],
        undress: [{ key: "top", label: "Haut", icon: "shirt", categories: ["jacket", "undershirt", "arms"] }, { key: "hat", label: "Chapeau", icon: "hat", categories: ["hat"] }, { key: "mask", label: "Masque", icon: "mask", categories: ["mask"] }],
        worn: { hair: [12, 0, 3, 5], beard: [4, 8, 2], eyebrows: [1, 10, 2], chesthair: [0, 0, 0] },
        groups: [
            { key: "hair", label: "Coupes", icon: "hair", camera: "head", categories: [{ key: "hair", label: "Coupes", kind: "hair", id: 2, price: 50, camera: "head" }] },
            { key: "beard", label: "Barbe", icon: "beard", camera: "head", categories: [{ key: "beard", label: "Barbe", kind: "overlay", id: 1, price: 30, camera: "head" }] },
            { key: "eyebrows", label: "Sourcils", icon: "eyebrows", camera: "head", categories: [{ key: "eyebrows", label: "Sourcils", kind: "overlay", id: 2, price: 15, camera: "head" }] },
            { key: "chesthair", label: "Pilosité", icon: "chest", camera: "torso", categories: [{ key: "chesthair", label: "Pilosité du torse", kind: "overlay", id: 10, price: 20, camera: "torso", undress: "top" }] },
        ],
    });
} else if (!inGame && !location.hash.includes("tool")) {
    open({
        store: "Binco de Strawberry", brand: { label: "binco", color: "#f7931e", image: "", showText: true }, sex: "male", currency: "$",
        pages: { catalogue: true, ready: true, outfits: true, favorites: true },
        images: { component: "", prop: "" }, maxOutfits: 10, coef: 1.2,
        items: { jacket: { 3: { label: "Veste en jean", price: 90 }, 5: { banned: true }, 6: { label: "Blouson cuir" } } },
        ready: [{ id: "r1", label: "Décontracté", price: 150, pieces: { jacket: [12, 1], pants: [4, 0] } }, { id: "r2", label: "Costume", price: 450, pieces: { jacket: [4, 0] } }],
        outfits: [{ id: 1, label: "Soirée", sex: "male" }, { id: 2, label: "Sport", sex: "male" }],
        favorites: ["jacket:7:0", "shoes:3:2"],
        worn: { jacket: [4, 0], undershirt: [15, 0], arms: [0, 0], pants: [1, 0], shoes: [1, 0], hat: [-1, 0], glasses: [-1, 0], mask: [0, 0], earrings: [-1, 0], chain: [0, 0], watch: [-1, 0], bracelet: [-1, 0], bag: [0, 0] },
        undress: [
            { key: "top", label: "Haut", icon: "shirt", categories: ["jacket", "undershirt", "arms"] }, { key: "pants", label: "Bas", icon: "pants", categories: ["pants"] },
            { key: "shoes", label: "Chaussures", icon: "shoe", categories: ["shoes"] }, { key: "hat", label: "Chapeau", icon: "hat", categories: ["hat"] },
            { key: "glasses", label: "Lunettes", icon: "glasses", categories: ["glasses"] }, { key: "mask", label: "Masque", icon: "mask", categories: ["mask"] },
            { key: "jewelry", label: "Bijoux", icon: "watch", categories: ["earrings", "chain", "watch", "bracelet"] }, { key: "bag", label: "Sac", icon: "bag", categories: ["bag"] },
        ],
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
