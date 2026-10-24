"use strict";

// ====================================================================
//  lunatic_admin — tuile Blips
//  Icônes de la carte du jeu : liste à gauche, carte au centre (vraie icône GTA dans sa couleur), fiche à droite
//  (nom, taille, position, affichage, sprite, couleur). Appliqué en jeu tout de suite.
//  Les blips des magasins (tuile Catalogues) apparaissent aussi : nom, icône, couleur et taille modifiables ici.
// ====================================================================

const blipState = { data: null, search: "", sel: null, draft: null, saved: "", picking: false, map: null, fitted: false, focused: null };

// Mots-clés français pour retrouver une icône (le nom des fichiers GTA est en anglais)
const BLIP_KEYWORDS = {
    1: "point rond", 52: "supérette magasin 24/7 ltd épicerie", 59: "supérette magasin épicerie", 71: "coiffeur barber",
    73: "vêtements habits magasin", 366: "vêtements habits magasin", 75: "tatouage tattoo", 110: "armurerie ammunation armes",
    60: "police commissariat shérif", 61: "hôpital médecin santé", 108: "banque argent fleeca", 500: "banque argent",
    361: "essence station carburant pompe", 72: "garage mécanique customs carrosserie", 100: "lavage auto",
    357: "parking garage", 68: "fourrière dépanneuse", 326: "concession voiture vente", 225: "voiture véhicule",
    90: "aéroport avion", 359: "aérodrome avion", 419: "mairie gouvernement", 407: "emploi travail job",
    188: "prison", 93: "bar boisson boîte", 121: "strip club", 436: "pompiers caserne", 498: "auto-école permis",
    56: "taxi", 50: "garage", 51: "pharmacie médicament", 102: "chirurgien", 140: "cannabis weed drogue",
    403: "bateau", 410: "bateau port", 427: "bateau", 477: "camion", 67: "camion livraison", 318: "poubelle éboueur",
    431: "vigne vin", 351: "chasse", 141: "chasse", 280: "ami", 40: "maison", 374: "maison appartement",
    475: "immeuble", 476: "entrepôt", 478: "entrepôt", 89: "golf", 109: "golf", 122: "tennis", 197: "tennis",
    205: "vélo", 226: "moto", 348: "moto", 371: "mine", 251: "pêche", 106: "restaurant nourriture burger",
    77: "cinéma", 135: "cinéma",
};

const blipImage = (sprite) => (BLIP_SPRITES[sprite] ? BLIP_IMAGE_BASE + BLIP_SPRITES[sprite] : null);
const blipColor = (color) => (BLIP_COLORS[color] ? BLIP_COLORS[color][0] : "#ffffff");
const blipColorName = (color) => (BLIP_COLORS[color] ? BLIP_COLORS[color][1] : `couleur ${color}`);

// Icône recolorée comme en jeu (masque de l'image GTA, fond de la couleur du blip)
function blipIcon(sprite, color, size = 22) {
    const el = h("span", { class: "blip-icon" });
    const url = blipImage(sprite);
    el.style.width = el.style.height = `${size}px`;
    el.style.backgroundColor = blipColor(color);
    if (url) {
        el.style.webkitMaskImage = el.style.maskImage = `url("${url}")`;
    } else {
        el.classList.add("no-image");
    }
    return el;
}

function renderBlips() {
    if (blipState.data && $("view-blips").childElementCount) return;
    paintBlips();
    loadBlips();
}

async function loadBlips() {
    const res = await nui("action", { action: "blips.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    blipState.data = res;
    paintBlips();
}

async function blipAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) await loadBlips();
    return res;
}

// Liste unique : blips libres (id) et blips de magasins (« shop:<id> »)
function blipEntries() {
    const d = blipState.data;
    if (!d) return [];
    const own = d.blips.map((b) => ({ key: b.id, label: b.label, sprite: b.sprite, color: b.color, scale: b.scale, sub: `#${b.id}${b.active ? "" : " · inactif"}`, blip: b }));
    const shops = d.shops.map((s) => ({ key: `shop:${s.id}`, label: s.blip.label || s.label, sprite: s.blip.sprite, color: s.blip.color, scale: s.blip.scale, sub: `Magasin · ${s.locations.length} emplacement(s)`, shop: s }));
    return [...own, ...shops].sort((a, b) => a.label.localeCompare(b.label));
}

function paintBlips() {
    const root = $("view-blips");
    const d = blipState.data;
    if (!d) return root.replaceChildren(h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-pin"), "Chargement des blips…")));

    const keep = root.querySelector(".blip-list");
    const scrollTop = keep ? keep.scrollTop : 0;
    const search = h("input", { placeholder: "Rechercher…", value: blipState.search });
    search.addEventListener("input", () => { blipState.search = search.value; paintBlipList(); });

    const sidebar = h("aside", { class: "sidebar blip-side" },
        h("div", { class: "side-head" }, icon("i-pin"), h("h3", null, "Blips"), h("span", { class: "cnt" }, String(blipEntries().length))),
        h("div", { class: "side-search" }, h("label", { class: "search" }, icon("i-search"), search)),
        h("div", { class: "side-scroll blip-list", id: "blipList" }),
        h("div", { class: "side-foot" }, h("button", { class: "btn primary wide", onclick: () => newBlip(null) }, icon("i-plus"), "Créer un blip")));

    if (!blipState.map) blipState.map = gtaMap();
    const center = h("div", { class: "blip-map" }, blipState.map.el);

    root.replaceChildren(h("div", { class: "blips-page" }, sidebar, center, blipEditor()));
    paintBlipList();
    $("blipList").scrollTop = scrollTop;
    drawBlips();
}

function paintBlipList() {
    const list = $("blipList");
    if (!list) return;
    const q = fold(blipState.search.trim());
    const rows = blipEntries().filter((e) => !q || fold(e.label).includes(q) || String(e.key).includes(q)).map((e) =>
        h("button", { class: `list-row blip-row${e.key === blipState.sel ? " active" : ""}`, onclick: () => selectBlip(e.key) },
            blipIcon(e.sprite, e.color, 20), h("span", { class: "who" }, h("b", null, e.label), h("span", null, e.sub))));
    list.replaceChildren(...(rows.length ? rows : [h("p", { class: "hint-line", style: "margin:8px" }, "Aucun blip.")]));
}

function selectBlip(key) {
    if (key === blipState.sel) return;
    guardUnsaved("blips", () => {
        untrackUnsaved("blips");
        blipState.sel = key;
        blipState.draft = null;
        blipState.picking = false;
        paintBlips();
    });
}

function newBlip(position) {
    guardUnsaved("blips", () => {
        untrackUnsaved("blips");
        blipState.sel = "new";
        blipState.draft = null;
        blipState.picking = false;
        blipState.prefill = position;
        paintBlips();
    });
}

function selectedEntry() {
    return blipEntries().find((e) => e.key === blipState.sel) || null;
}

// Brouillon de la fiche, suivi par la barre « non enregistré »
function blipDraft(entry) {
    if (blipState.draft && blipState.draft.key === blipState.sel) return blipState.draft;
    const base = entry
        ? { key: entry.key, label: entry.label, sprite: entry.sprite, color: entry.color, scale: entry.scale, short: entry.blip ? entry.blip.short : true, active: entry.blip ? entry.blip.active : true }
        : { key: "new", label: "Nouveau blip", sprite: 1, color: 0, scale: 0.8, short: true, active: true, ...(blipState.prefill || {}) };
    blipState.prefill = null;
    blipState.draft = base;
    blipState.saved = JSON.stringify(base);
    trackUnsaved("blips", {
        label: `Blip ${base.label}`,
        isDirty: () => !!blipState.draft && JSON.stringify(blipState.draft) !== blipState.saved,
        save: () => saveBlip(),
        reset: () => { blipState.draft = null; paintBlips(); },
    });
    return base;
}

function blipEditor() {
    const entry = selectedEntry();
    if (!entry && blipState.sel !== "new") {
        return h("aside", { class: "item-editor blip-editor" }, h("div", { class: "empty" }, icon("i-pin"), "Choisissez un blip, ou « Créer un blip »."));
    }
    const d = blipDraft(entry);
    const shop = entry && entry.shop;
    const own = entry && entry.blip;

    const headIcon = h("div", { class: "pic" }, blipIcon(d.sprite, d.color, 40));
    const headSub = h("span", { class: "mono" }, `Sprite #${d.sprite} · ${blipColorName(d.color)}`);
    const spriteSub = h("span", { class: "muted" }, ` #${d.sprite}`);
    const colorDot = h("span", { class: "blip-dot", style: `background:${blipColor(d.color)}` });
    const colorSub = h("span", { class: "muted" }, ` ${blipColorName(d.color)}`);
    const refreshHead = () => {
        headIcon.replaceChildren(blipIcon(d.sprite, d.color, 40));
        headSub.textContent = `Sprite #${d.sprite} · ${blipColorName(d.color)}`;
        spriteSub.textContent = ` #${d.sprite}`;
        colorDot.style.background = blipColor(d.color);
        colorSub.textContent = ` ${blipColorName(d.color)}`;
        drawBlips();
    };

    const label = h("input", { class: "input", maxlength: "60", value: d.label });
    label.addEventListener("input", () => { d.label = label.value; });
    const scale = h("input", { class: "input mono", type: "number", min: "0.1", max: "3", step: "0.1", value: String(d.scale) });
    scale.addEventListener("input", () => { d.scale = Number(scale.value); drawBlips(); });
    const display = h("select", { class: "input" }, h("option", { value: "1", selected: d.short }, "Seulement à proximité"), h("option", { value: "0", selected: !d.short }, "Toujours visible"));
    display.addEventListener("change", () => { d.short = display.value === "1"; });

    // Position : déplacer sur la carte (prochain clic), à sa position en jeu, TP
    const where = d.x != null ? `Placé sur la carte : ${d.x.toFixed(0)}, ${d.y.toFixed(0)}` : own ? `${own.x.toFixed(0)}, ${own.y.toFixed(0)}` : shop ? "Emplacements du magasin (tuile Catalogues)" : "Votre position en jeu (ou cliquez sur la carte)";
    const position = shop ? h("span", { class: "hint-line", style: "margin:0" }, where) : h("div", { class: "blip-position" },
        h("div", { class: "btn-row" },
            h("button", { class: `btn small${blipState.picking ? " primary" : ""}`, title: "Le prochain clic sur la carte place le blip", onclick: () => { blipState.picking = !blipState.picking; paintBlips(); } }, icon("i-crosshair"), "Déplacer"),
            own ? h("button", { class: "btn small ghost", title: "Place le blip là où vous êtes en jeu", onclick: () => blipAct("blips.move", { id: own.id }, "Blip placé à votre position.") }, icon("i-player"), "Ma position") : null,
            own ? h("button", { class: "btn small ghost", onclick: () => act("blips.tp", { id: own.id }, null) }, icon("i-goto"), "TP") : null),
        h("span", { class: "hint-line", style: "margin:0" }, where));

    // Sprite : grille d'icônes avec recherche ; couleur : palette
    const spriteBox = h("details", { class: "blip-fold" }, h("summary", null, icon("i-pin"), "Sprite", spriteSub), spritePicker(d, refreshHead));
    const colorBox = h("details", { class: "blip-fold" }, h("summary", null, colorDot, "Couleur", colorSub), colorPicker(d, refreshHead));

    return h("aside", { class: "item-editor blip-editor" },
        h("div", { class: "item-head" }, headIcon, h("div", { class: "who" }, h("b", null, entry ? entry.label : "Nouveau blip"), headSub)),
        h("div", { class: "item-scroll" },
            fieldRow("Nom", label),
            fieldRow("Taille", scale),
            fieldRow("Position", position),
            shop ? null : fieldRow("Affichage", display),
            shop ? null : h("div", { class: "mode-list" }, draftToggle(d, "active", "Actif", "Désactivé : le blip n'apparaît plus en jeu.")),
            spriteBox, colorBox,
            shop ? h("p", { class: "hint-line" }, "Blip de magasin : le nom, l'icône, la couleur et la taille valent pour tous ses emplacements.") : null),
        h("div", { class: "item-actions" },
            h("button", { class: "btn small primary", onclick: saveBlip }, icon("i-save"), blipState.sel === "new" ? "Créer" : "Sauvegarder"),
            own ? deleteButton(async () => {
                const yes = await confirmBox(`Supprimer « ${own.label} » ?`, "Le blip disparaît de la carte de tous les joueurs.", "Supprimer", true);
                if (!yes) return;
                const res = await act("blips.delete", { id: own.id }, "Blip supprimé.");
                if (!res) return;
                untrackUnsaved("blips");
                blipState.sel = null;
                blipState.draft = null;
                await loadBlips();
            }) : null),
        h("p", { class: "hint-line", style: "margin:0 18px 14px" }, "Les modifications s'appliquent en jeu tout de suite."));
}

function spritePicker(d, done) {
    const search = h("input", { class: "input", placeholder: "Rechercher (ex. coiffeur, banque, 71)" });
    const grid = h("div", { class: "sprite-grid" });
    const paint = () => {
        const q = fold(search.value.trim());
        const ids = Object.keys(BLIP_SPRITES).map(Number).filter((id) => !q || String(id) === q || fold(BLIP_SPRITES[id]).includes(q) || fold(BLIP_KEYWORDS[id] || "").includes(q));
        grid.replaceChildren(...ids.slice(0, 240).map((id) => {
            const b = h("button", { class: `sprite-cell${id === d.sprite ? " on" : ""}`, title: `#${id} ${BLIP_SPRITES[id].replace(/^radar_|\.(png|gif)$/g, "")}` }, blipIcon(id, d.color, 22), h("span", null, String(id)));
            b.addEventListener("click", () => { d.sprite = id; paint(); done(); });
            return b;
        }));
    };
    search.addEventListener("input", paint);
    paint();
    return h("div", { class: "blip-picker" }, search, grid);
}

function colorPicker(d, done) {
    const grid = h("div", { class: "color-grid" });
    const paint = () => grid.replaceChildren(...Object.keys(BLIP_COLORS).map(Number).map((id) => {
        const b = h("button", { class: `color-cell${id === d.color ? " on" : ""}`, title: `${id} · ${BLIP_COLORS[id][1]}` });
        b.style.background = BLIP_COLORS[id][0];
        b.addEventListener("click", () => { d.color = id; paint(); done(); });
        return b;
    }));
    paint();
    return grid;
}

async function saveBlip() {
    const d = blipState.draft;
    if (!d) return;
    const entry = selectedEntry();
    let res;
    if (entry && entry.shop) {
        res = await act("blips.saveShop", { shop: entry.shop.id, label: d.label, sprite: d.sprite, color: d.color, scale: d.scale }, "Blip du magasin enregistré.");
    } else {
        res = await act("blips.save", { id: entry ? entry.blip.id : null, label: d.label, sprite: d.sprite, color: d.color, scale: d.scale, short: d.short, active: d.active, x: d.x, y: d.y },
            entry ? "Blip enregistré." : (d.x != null ? "Blip créé." : "Blip créé à votre position."));
    }
    if (!res) return;
    untrackUnsaved("blips");
    blipState.draft = null;
    blipState.picking = false;
    if (res.id) blipState.sel = res.id;
    await loadBlips();
}

// ---------- Carte ----------

function drawBlips() {
    const map = blipState.map;
    if (!map || !blipState.data) return;
    map.clear();
    const d = blipState.draft;

    for (const e of blipEntries()) {
        const selected = e.key === blipState.sel;
        const sprite = selected && d ? d.sprite : e.sprite;
        const color = selected && d ? d.color : e.color;
        const scale = selected && d ? d.scale : e.scale;
        const spots = e.shop ? e.shop.locations : [{ x: selected && d && d.x != null ? d.x : e.blip.x, y: selected && d && d.x != null ? d.y : e.blip.y }];
        for (const spot of spots) map.icon(spot.x, spot.y, blipIcon(sprite, color, Math.round(18 + scale * 8)), { label: e.label, selected, faded: e.blip && !e.blip.active }, () => selectBlip(e.key));
    }
    if (blipState.sel === "new" && d && d.x != null) map.icon(d.x, d.y, blipIcon(d.sprite, d.color, Math.round(18 + d.scale * 8)), { label: d.label, selected: true });

    map.setClick(placeBlip, blipState.picking || blipState.sel === null);

    const entry = selectedEntry();
    const spot = entry && (entry.blip || (entry.shop && entry.shop.locations[0]));
    if (!blipState.fitted) {
        blipState.fitted = true;
        blipState.focused = blipState.sel;
        requestAnimationFrame(() => map.focus(spot ? spot.x : -300, spot ? spot.y : -700, spot ? 5 : 2));
    } else if (blipState.focused !== blipState.sel) {
        blipState.focused = blipState.sel;
        if (spot) map.focus(spot.x, spot.y, Math.max(map.map.getZoom(), 4));
    }
}

// Clic sur la carte : place le blip en cours (« Déplacer »), ou crée un blip à cet endroit si rien n'est choisi
function placeBlip(x, y) {
    if (!insideGtaMap(x, y)) return toast("Position hors de la carte.", "error");
    const position = { x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10 };
    const entry = selectedEntry();
    if (blipState.picking && blipState.draft && !(entry && entry.shop)) {
        Object.assign(blipState.draft, position);
        blipState.picking = false;
        paintBlips();
        return;
    }
    if (blipState.sel === null) newBlip(position);
}
