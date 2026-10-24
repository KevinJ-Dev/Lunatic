"use strict";

// ====================================================================
//  lunatic_admin — tuile Images
//  Catalogue des visuels (onglets par catégorie, grille, aperçu et fiche à droite) et mugshots des personnages.
//  Aussi : conversion du portrait GTA en image (mugshot), photos dans les fiches joueur, choix d'une image dans les fiches.
// ====================================================================

const imgState = { data: null, cat: "all", sel: null, search: "", draft: null, saved: "", mug: { list: [], total: 0, search: "", sel: null, loading: false } };

const IMG_ALL = { id: "all", label: "Tout" };
const IMG_MUGSHOTS = { id: "mugshots", label: "Mugshots" };

// ---------- Mugshots : conversion du portrait GTA (demandée par client/mugshots.lua) ----------

function captureMugshot(url) {
    const send = (payload) => nui("mugshotData", payload).catch(() => null);
    const tryLoad = (cors) => {
        const img = new Image();
        if (cors) img.crossOrigin = "anonymous";
        img.onload = () => {
            try {
                const canvas = document.createElement("canvas");
                canvas.width = img.naturalWidth || 128;
                canvas.height = img.naturalHeight || 128;
                canvas.getContext("2d").drawImage(img, 0, 0);
                send({ image: canvas.toDataURL("image/webp", 0.9) });
            } catch (e) {
                send({ error: String((e && e.message) || e).slice(0, 120) });
            }
        };
        // Sans en-têtes CORS l'image ne charge pas en mode « anonymous » : nouvel essai sans
        img.onerror = () => (cors ? tryLoad(false) : send({ error: "portrait introuvable dans la page" }));
        img.src = url;
    };
    tryLoad(true);
}

// ---------- Mugshots : affichage (fiches et liste des joueurs) ----------

const mugshotCache = new Map(); // identifiant -> image (data URL) ou null

async function loadMugshots(identifiers) {
    const missing = [...new Set(identifiers.filter((id) => id && !mugshotCache.has(id)))].slice(0, 64);
    if (!missing.length || !(can("players.view") || can("images.manage"))) return false;
    for (const id of missing) mugshotCache.set(id, null);
    const res = await nui("action", { action: "mugshots.get", payload: { identifiers: missing } }).catch(() => null);
    if (!res || !res.ok) return false;
    let found = false;
    for (const [id, image] of Object.entries(res.images || {})) {
        mugshotCache.set(id, image);
        found = true;
    }
    return found;
}

function mugshotImg(identifier, className) {
    const box = h("span", { class: `mugshot ${className || ""}` });
    const paint = () => {
        const src = identifier && mugshotCache.get(identifier);
        box.replaceChildren(src ? h("img", { src, alt: "" }) : icon("i-player"));
    };
    paint();
    if (identifier && !mugshotCache.has(identifier)) loadMugshots([identifier]).then((found) => found && paint());
    return box;
}

// ---------- Choix d'une image du catalogue dans une fiche (logo, bannière) ----------

function imageField(input) {
    const pick = h("button", { class: "btn small ghost", type: "button", title: "Choisir une image de la tuile Images" }, icon("i-image"), "Images");
    pick.addEventListener("click", () => openImagePicker(input));
    return h("div", { class: "image-field" }, input, pick);
}

async function openImagePicker(input) {
    const res = await nui("action", { action: "images.choices", payload: {} }).catch(() => null);
    if (!res || !res.ok) return toast((res && res.error) || "Images indisponibles.", "error");
    const max = input.maxLength > 0 ? input.maxLength : 500;
    const list = (res.images || []).filter((i) => i.url.length <= max);
    openModal((close) => [
        h("header", null, h("h3", null, "Choisir une image"), h("p", null, "Images de la tuile Images (ajoutez-en depuis cette tuile).")),
        list.length
            ? h("div", { class: "img-choices" }, list.map((i) => h("button", { class: "img-choice", type: "button", title: i.url, onclick: () => {
                input.value = i.url;
                input.dispatchEvent(new Event("input", { bubbles: true }));
                close(false);
            } }, imgThumb(i.url), h("span", null, i.label))))
            : h("p", { class: "hint-line", style: "margin:0 22px" }, "Aucune image disponible pour l'instant."),
        h("footer", null, h("button", { class: "btn", onclick: () => close(false) }, "Annuler")),
    ]);
}

function imgThumb(url) {
    const box = h("span", { class: "img-thumb" });
    const fallback = () => box.replaceChildren(h("span", { class: "img-missing" }, "?"));
    if (!url) {
        fallback();
        return box;
    }
    const img = h("img", { src: url, alt: "" });
    img.addEventListener("error", fallback);
    box.append(img);
    return box;
}

// ---------- Logo du panel ----------

function applyBrandImages() {
    const url = (state && state.images && state.images.panel_logo) || "logo.png";
    for (const img of document.querySelectorAll(".brand-mini img, #miniPill img")) {
        if (img.dataset.src === url) continue;
        img.dataset.src = url;
        img.onerror = () => { img.onerror = null; img.src = "logo.png"; };
        img.src = url;
    }
}

// ---------- Tuile Images ----------

function renderImages() {
    if (imgState.data && $("view-images").childElementCount) return;
    paintImages();
    loadImages();
}

async function loadImages() {
    const res = await nui("action", { action: "images.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    imgState.data = res;
    paintImages();
    if (imgState.cat === "mugshots" && !imgState.mug.list.length) loadMugshotPage(false);
}

function imgGo(changes) {
    guardUnsaved("images", () => {
        untrackUnsaved("images");
        Object.assign(imgState, changes, { draft: null });
        paintImages();
        if (imgState.cat === "mugshots" && !imgState.mug.list.length) loadMugshotPage(false);
    });
}

function imgCategories() {
    return [IMG_ALL, ...imgState.data.categories, IMG_MUGSHOTS];
}

function imgCount(id) {
    const list = imgState.data.images;
    if (id === "all") return list.length;
    if (id === "mugshots") return imgState.data.mugshots;
    return list.filter((i) => i.category === id).length;
}

function paintImages() {
    const root = $("view-images");
    const d = imgState.data;
    if (!d) return root.replaceChildren(h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-image"), "Chargement des images…")));

    const tabs = h("div", { class: "img-tabs" }, imgCategories().map((c) =>
        h("button", { class: `img-tab${c.id === imgState.cat ? " on" : ""}`, onclick: () => c.id !== imgState.cat && imgGo({ cat: c.id, sel: null }) },
            h("span", null, c.label), h("span", { class: "cnt" }, String(imgCount(c.id))))));

    const body = imgState.cat === "mugshots" ? mugshotsBody() : imagesBody();
    const scroller = root.querySelector(".img-scroll");
    const top = scroller ? scroller.scrollTop : 0;
    root.replaceChildren(h("div", { class: "img-page" }, tabs, body));
    const fresh = root.querySelector(".img-scroll");
    if (fresh && top) fresh.scrollTop = top;
}

function imgEntry() {
    return imgState.data.images.find((i) => i.key === imgState.sel) || null;
}

function imagesBody() {
    const q = fold(imgState.search.trim());
    const list = imgState.data.images.filter((i) => (imgState.cat === "all" || i.category === imgState.cat)
        && (!q || fold(`${i.label} ${i.description} ${i.key}`).includes(q)));

    const search = h("input", { placeholder: "Rechercher une image…", value: imgState.search });
    search.addEventListener("input", () => {
        imgState.search = search.value;
        const pos = search.selectionStart;
        paintImages();
        const again = $("view-images").querySelector(".img-search input");
        if (again) { again.focus(); again.setSelectionRange(pos, pos); }
    });

    const grid = list.length
        ? h("div", { class: "img-grid" }, list.map((i) => h("button", { class: `img-card${i.key === imgState.sel ? " on" : ""}`, onclick: () => i.key !== imgState.sel && imgGo({ sel: i.key }) },
            imgThumb(i.url), h("b", null, i.label), h("span", null, i.description || (i.slot ? "Emplacement d'un script" : "Image ajoutée")))))
        : h("div", { class: "empty" }, icon("i-image"), "Aucune image.");

    return h("div", { class: "img-body" },
        h("section", { class: "img-main" },
            h("div", { class: "img-toolbar" },
                h("label", { class: "search img-search" }, icon("i-search"), search),
                h("button", { class: "btn small primary", onclick: () => imgGo({ sel: "new" }) }, icon("i-plus"), "Ajouter une image")),
            h("div", { class: "img-scroll" }, grid)),
        imageEditor());
}

function imgDraft(entry) {
    if (imgState.draft && imgState.draft.key === imgState.sel) return imgState.draft;
    const base = entry
        ? { key: entry.key, label: entry.label, description: entry.description || "", url: entry.url || "", category: entry.category }
        : { key: "new", label: "", description: "", url: "", category: imgState.cat !== "all" && imgState.cat !== "mugshots" ? imgState.cat : "other" };
    imgState.draft = base;
    imgState.saved = JSON.stringify(base);
    trackUnsaved("images", {
        label: entry ? `Image ${entry.label}` : "Nouvelle image",
        isDirty: () => !!imgState.draft && (imgState.draft.key === "new" || JSON.stringify(imgState.draft) !== imgState.saved),
        save: () => saveImage(),
        reset: () => { imgState.draft = null; if (imgState.sel === "new") imgState.sel = null; paintImages(); },
    });
    return base;
}

function imageEditor() {
    const entry = imgEntry();
    if (!entry && imgState.sel !== "new") {
        return h("aside", { class: "item-editor img-editor" }, h("div", { class: "empty" }, icon("i-image"), "Choisissez une image pour la modifier."));
    }
    const d = imgDraft(entry);
    const slot = entry && entry.slot;
    const preview = h("div", { class: "img-preview" }, imgThumb(d.url));
    const url = h("input", { class: "input mono", maxlength: "500", placeholder: "https://…/image.png", value: d.url && !d.url.startsWith("nui://") ? d.url : "" });
    url.addEventListener("input", () => { d.url = url.value.trim(); preview.replaceChildren(imgThumb(d.url || (entry && entry.default) || "")); });
    const label = h("input", { class: "input", maxlength: "60", value: d.label, disabled: slot });
    label.addEventListener("input", () => { d.label = label.value; });
    const description = h("input", { class: "input", maxlength: "150", value: d.description, disabled: slot });
    description.addEventListener("input", () => { d.description = description.value; });
    const category = h("select", { class: "input", disabled: slot }, imgState.data.categories.map((c) => h("option", { value: c.id, selected: c.id === d.category }, c.label)));
    category.addEventListener("change", () => { d.category = category.value; });

    const remove = slot
        ? (entry.changed ? h("button", { class: "btn small danger", onclick: () => deleteImage(entry, "Remettre l'image d'origine ?", "Le script reprend son image par défaut.") }, icon("i-undo"), "Image d'origine") : null)
        : entry ? deleteButton(() => deleteImage(entry, `Supprimer « ${entry.label} » ?`, "Les fiches qui utilisent cette URL la gardent.")) : null;

    return h("aside", { class: "item-editor img-editor" },
        h("div", { class: "img-editor-head" }, h("span", null, icon("i-eye"), "Aperçu")),
        preview,
        h("div", { class: "item-scroll" },
            fieldRow("Nom", label),
            fieldRow("Description", description),
            fieldRow("URL de l'image", url),
            fieldRow("Catégorie", category),
            slot ? h("p", { class: "hint-line" }, `Emplacement d'un script : seule l'image change. ${entry.changed ? `Modifiée par ${entry.updatedBy || "?"}.` : "Image d'origine."}`) : null,
            h("p", { class: "hint-line" }, "Enregistrez avec la barre du bas : appliqué en jeu tout de suite. Hébergez l'image sur un CDN (Discord, Imgur, Fivemanage…).")),
        remove ? h("div", { class: "item-actions single" }, remove) : null);
}

async function saveImage() {
    const d = imgState.draft;
    if (!d) return;
    const entry = imgEntry();
    const res = await act("images.save", { key: entry ? entry.key : null, label: d.label, description: d.description, url: d.url, category: d.category }, entry ? "Image enregistrée." : "Image ajoutée.");
    if (!res) return;
    untrackUnsaved("images");
    imgState.draft = null;
    imgState.sel = res.key || imgState.sel;
    await loadImages();
}

async function deleteImage(entry, title, text) {
    if (!(await confirmBox(title, text, entry.slot ? "Remettre" : "Supprimer", true))) return;
    const res = await act("images.delete", { key: entry.key }, entry.slot ? "Image d'origine remise." : "Image supprimée.");
    if (!res) return;
    untrackUnsaved("images");
    imgState.draft = null;
    if (!entry.slot) imgState.sel = null;
    await loadImages();
}

// ---------- Onglet Mugshots ----------

async function loadMugshotPage(more) {
    const m = imgState.mug;
    if (m.loading) return;
    m.loading = true;
    const res = await nui("action", { action: "mugshots.list", payload: { offset: more ? m.list.length : 0, search: m.search } }).catch(() => null);
    m.loading = false;
    if (!res || !res.ok) return;
    m.list = more ? [...m.list, ...res.mugshots] : res.mugshots;
    m.total = res.total;
    for (const s of res.mugshots) mugshotCache.set(s.identifier, s.image);
    paintImages();
}

let mugshotSearchTimer = null;

function mugshotsBody() {
    const m = imgState.mug;
    const search = h("input", { placeholder: "Nom RP ou identifiant…", value: m.search });
    search.addEventListener("input", () => {
        m.search = search.value;
        clearTimeout(mugshotSearchTimer);
        mugshotSearchTimer = setTimeout(() => loadMugshotPage(false), 350);
    });

    const grid = m.list.length
        ? h("div", { class: "img-grid mug-grid" }, m.list.map((s) => h("button", { class: `img-card mug-card${s.identifier === m.sel ? " on" : ""}`, onclick: () => { m.sel = s.identifier; paintImages(); } },
            h("span", { class: "img-thumb" }, h("img", { src: s.image, alt: "" })), h("b", null, s.name), h("span", null, s.online ? `En ligne · ID ${s.online}` : ago(s.updatedAt)))))
        : h("div", { class: "empty" }, icon("i-player"), m.loading ? "Chargement…" : "Aucun mugshot pour l'instant : ils sont pris à la première connexion de chaque personnage.");

    const sel = m.list.find((s) => s.identifier === m.sel);
    const side = sel
        ? h("aside", { class: "item-editor img-editor" },
            h("div", { class: "img-editor-head" }, h("span", null, icon("i-player"), "Mugshot")),
            h("div", { class: "img-preview" }, h("span", { class: "img-thumb" }, h("img", { src: sel.image, alt: "" }))),
            h("div", { class: "item-scroll" },
                h("div", { class: "mug-name" }, h("b", null, sel.name), h("span", { class: `badge ${sel.online ? "ok" : "muted"}` }, sel.online ? `En ligne · ID ${sel.online}` : "Hors ligne")),
                h("p", { class: "hint-line" }, `Photo du ${fmtDate(sel.updatedAt)} · ${sel.identifier}`)),
            h("div", { class: "item-actions single" },
                h("button", { class: "btn small primary", disabled: !sel.online, title: sel.online ? null : "Le personnage doit être connecté", onclick: () => retakeMugshot(sel.identifier) }, icon("i-undo"), "Refaire le mugshot")))
        : h("aside", { class: "item-editor img-editor" }, h("div", { class: "empty" }, icon("i-player"), "Choisissez un mugshot."));

    return h("div", { class: "img-body" },
        h("section", { class: "img-main" },
            h("div", { class: "img-toolbar" },
                h("label", { class: "search img-search" }, icon("i-search"), search),
                h("button", { class: "btn small", onclick: retakeAllMugshots }, icon("i-undo"), "Refaire les joueurs connectés")),
            h("div", { class: "img-scroll" }, grid,
                m.list.length < m.total ? h("div", { class: "btn-row", style: "justify-content:center;margin-top:12px" },
                    h("button", { class: "btn small ghost", onclick: () => loadMugshotPage(true) }, `Voir plus (${m.list.length} / ${m.total})`)) : null)),
        side);
}

async function retakeMugshot(identifier) {
    const res = await act("mugshots.retake", { identifier }, null);
    if (!res) return;
    toast(res.message || "Photo demandée.", "ok");
    mugshotCache.delete(identifier);
    setTimeout(() => loadMugshotPage(false), 8000);
}

async function retakeAllMugshots() {
    if (!(await confirmBox("Refaire tous les mugshots ?", "Une nouvelle photo est prise pour chaque joueur connecté (une toutes les demi-secondes).", "Refaire"))) return;
    const res = await act("mugshots.retakeAll", {}, null);
    if (!res) return;
    toast(res.message || "Photos demandées.", "ok");
    mugshotCache.clear();
    setTimeout(() => loadMugshotPage(false), 10000);
}
