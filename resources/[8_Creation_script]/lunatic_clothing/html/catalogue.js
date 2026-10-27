"use strict";

// Gestion du catalogue (staff, ouverte depuis le panel) : grille des pièces par catégorie, fiche de la pièce choisie
// (nom, bannie, prix, image, photo), prix par défaut de la catégorie, homme / femme. Utilise h, nui, svg et toast
// de app.js. Le serveur vérifie la session du staff à chaque enregistrement.

const tool = { data: null, group: null, category: null, selected: null, counts: {}, previews: {}, busy: false };

const toolCategories = () => tool.data.groups.flatMap((g) => g.categories);
const toolCategory = () => toolCategories().find((c) => c.key === tool.category);
const toolGroup = () => tool.data.groups.find((g) => g.key === tool.group);
const toolItem = (c, drawable) => (tool.data.items[c.key] && tool.data.items[c.key][String(drawable)]) || null;

function openTool(payload) {
    tool.data = payload;
    tool.data.items = payload.items || {};
    tool.selected = null;
    $("tool").classList.remove("hidden");
    toolGroupOpen(tool.group && tool.data.groups.some((g) => g.key === tool.group) ? tool.group : tool.data.groups[0].key);
}

function closeTool() {
    $("tool").classList.add("hidden");
    nui("close");
}
$("toolClose").addEventListener("click", closeTool);

function toolGroupOpen(key) {
    const g = tool.data.groups.find((entry) => entry.key === key);
    tool.group = g.key;
    tool.category = g.categories[0].key;
    tool.selected = null;
    nui("camera", { view: g.categories[0].camera || g.camera });
    paintTool();
}

// Images d'une pièce : photo qui vient d'être prise, puis l'ordre du magasin (fiche, Renderer, photo, lien général)
function toolSources(c, drawable) {
    const preview = tool.previews[`${tool.data.sex}:${c.key}:${drawable}`];
    return [preview, ...pieceSources(tool.data, c, drawable, toolItem(c, drawable), 0)].filter(Boolean);
}

async function toolCounts(c, drawable) {
    const key = `${tool.data.sex}:${c.key}:${drawable}`;
    if (!tool.counts[key]) tool.counts[key] = (await nui("counts", { key: c.key, drawable })) || { drawables: 0, textures: 0 };
    return tool.counts[key];
}

// ---------- Rendu ----------

function paintTool() {
    const grid = $("toolGrid");
    const scroll = grid ? grid.scrollTop : 0;
    $("toolSub").textContent = tool.data.sex === "female" ? "Femme" : "Homme";
    $("toolView").replaceChildren(toolLeft());
    if ($("toolGrid")) $("toolGrid").scrollTop = scroll;
    $("toolRight").replaceChildren(...toolRight());
    $("toolBar").replaceChildren(...tool.data.groups.map((g) => h("button", { class: g.key === tool.group ? "on" : "", onclick: () => { if ($("toolGrid")) $("toolGrid").scrollTop = 0; toolGroupOpen(g.key); } }, svg(g.icon), g.label)));
}

function toolLeft() {
    const g = toolGroup();
    const c = toolCategory();
    const total = tool.counts[`${tool.data.sex}:${c.key}:0`];
    const tabs = g.categories.length > 1 ? h("div", { class: "tabs" }, g.categories.map((entry) => h("button", {
        class: `tab${entry.key === tool.category ? " on" : ""}`, onclick: () => { tool.category = entry.key; tool.selected = null; nui("camera", { view: entry.camera || g.camera }); if ($("toolGrid")) $("toolGrid").scrollTop = 0; paintTool(); },
    }, entry.label))) : null;

    if (!total) {
        toolCounts(c, 0).then(() => paintTool());
        return h("div", { class: "view" }, tabs, h("p", { class: "empty" }, "Chargement…"));
    }

    const cells = [];
    for (let i = 0; i < total.drawables; i += 1) {
        const item = toolItem(c, i);
        cells.push(h("button", { class: `cell${tool.selected === i ? " on" : ""}${item && item.banned ? " banned" : ""}`, onclick: () => toolSelect(c, i) },
            item && item.banned ? h("span", { class: "badge-ban" }, "Bannie") : null,
            item && item.price != null ? h("span", { class: "badge-price" }, `${item.price} ${tool.data.currency}`) : null,
            pieceImage(toolSources(c, i), i),
            h("small", null, (item && item.label) || `N° ${i}`)));
    }

    return h("div", { class: "view" }, tabs,
        h("div", { class: "price-line" }, h("span", null, `${c.label} · ${total.drawables} modèles`), h("b", null, `Défaut : ${c.base} ${tool.data.currency}`)),
        h("div", { class: "grid", id: "toolGrid" }, cells));
}

function toolSelect(c, drawable) {
    tool.selected = drawable;
    nui("apply", { key: c.key, drawable, texture: 0 });
    paintTool();
}

function toolRight() {
    const c = toolCategory();
    const sexes = h("div", { class: "sexes" }, [["male", "Homme"], ["female", "Femme"]].map(([sex, label]) => h("button", {
        class: `sex${tool.data.sex === sex ? " on" : ""}`, disabled: tool.busy, onclick: () => toolSex(sex),
    }, label)));

    const base = h("input", { class: "input mono", type: "number", min: "0", value: String(c.base) });
    const defaultPrice = h("div", { class: "box" }, h("div", { class: "box-head" }, `Prix par défaut · ${c.label}`),
        h("div", { class: "save-row" }, base, h("button", { class: "btn small", onclick: async () => {
            const res = await nui("setDefaultPrice", { key: c.key, price: Number(base.value) });
            if (!res || !res.ok) return toast((res && res.error) || "Prix refusé.");
            c.base = Number(base.value);
            toast("Prix par défaut enregistré.");
            paintTool();
        } }, "✓")),
        h("small", null, "Prix des pièces sans prix propre (multiplié par le coefficient de chaque enseigne)."));

    if (tool.selected === null) {
        return [sexes, defaultPrice, batchBox(c), h("div", { class: "box" }, h("p", { class: "empty" }, "Choisissez une pièce dans la grille pour modifier sa fiche."))];
    }

    const drawable = tool.selected;
    const item = toolItem(c, drawable) || {};
    const form = { label: item.label || "", price: item.price != null ? String(item.price) : "", banned: !!item.banned, image: item.image || "" };

    const label = h("input", { class: "input", maxlength: "40", placeholder: `N° ${drawable}`, value: form.label });
    label.addEventListener("input", () => { form.label = label.value; });
    const price = h("input", { class: "input mono", type: "number", min: "0", placeholder: `Défaut : ${c.base}`, value: form.price });
    price.addEventListener("input", () => { form.price = price.value; });
    const image = h("input", { class: "input", maxlength: "300", placeholder: "Lien https (vide : image du Clothes Renderer)", value: form.image });
    image.addEventListener("input", () => { form.image = image.value.trim(); });
    const ban = h("button", { class: `switch${form.banned ? " on" : ""}`, onclick: () => { form.banned = !form.banned; ban.classList.toggle("on", form.banned); } }, h("i"));

    const save = async () => {
        const res = await nui("saveItem", { key: c.key, drawable, item: { label: form.label, price: form.price, banned: form.banned, image: form.image } });
        if (!res || !res.ok) return toast((res && res.error) || "Enregistrement impossible.");
        tool.data.items[c.key] = tool.data.items[c.key] || {};
        tool.data.items[c.key][String(drawable)] = res.item;
        toast("Fiche enregistrée.");
        paintTool();
    };

    const capture = async () => {
        tool.busy = true;
        paintTool();
        const res = await nui("capture", { key: c.key, drawable, view: c.camera || toolGroup().camera });
        tool.busy = false;
        if (!res || !res.ok) { paintTool(); return toast((res && res.error) || "Photo impossible."); }
        tool.previews[`${tool.data.sex}:${c.key}:${drawable}`] = res.preview;
        tool.data.items[c.key] = tool.data.items[c.key] || {};
        tool.data.items[c.key][String(drawable)] = { ...item, image: res.path };
        toast("Photo enregistrée : visible tout de suite dans le catalogue et les magasins.");
        paintTool();
    };

    return [sexes, defaultPrice,
        h("div", { class: "box" }, h("div", { class: "box-head" }, "Aperçu"),
            h("div", { class: "preview" },
                h("div", { class: "preview-img" }, pieceImage(toolSources(c, drawable), drawable)),
                h("div", null, h("b", null, form.label || `N° ${drawable}`), h("small", null, `${c.label} · ID ${drawable}`)))),
        h("div", { class: "box" }, h("div", { class: "box-head" }, "Informations"),
            h("div", { class: "form" },
                h("span", null, "Nom"), label,
                h("span", null, "Bannie"), h("div", { class: "inline" }, ban, h("small", null, "Cachée des magasins")),
                h("span", null, "Prix"), price,
                h("span", null, "Image"), image,
                h("span", null, "Photo"), h("button", { class: "btn small ghost", disabled: !tool.data.screenshot || tool.busy, title: tool.data.screenshot ? "" : "screenshot-basic absent du serveur", onclick: capture }, tool.busy ? "Photo en cours…" : "Prendre la photo")),
            !tool.data.screenshot ? h("small", { class: "warn" }, "Photo indisponible : installez et démarrez screenshot-basic.") : null,
            h("button", { class: "btn save", onclick: save }, "Sauvegarder")), batchBox(c)];
}

// Photos en série : la catégorie affichée ou tout le catalogue (sexe affiché), une pièce à la fois
function batchBox(c) {
    const skip = h("button", { class: `switch${tool.skip ? " on ok" : ""}`, onclick: () => { tool.skip = !tool.skip; skip.classList.toggle("on", tool.skip); skip.classList.toggle("ok", tool.skip); } }, h("i"));
    const run = async (scope) => {
        const res = await nui("batch", { scope, key: c.key, skip: tool.skip });
        if (!res || !res.ok) return toast((res && res.error) || "Série impossible.");
        batchShow({ index: 0, total: res.total, done: 0, failed: 0, label: "Préparation…" });
    };
    return h("div", { class: "box" }, h("div", { class: "box-head" }, "Photos en série"),
        h("small", null, "Chaque pièce photographiée sans le corps (double photo), sur fond transparent, rangée dans sa fiche. Les images du Clothes Renderer restent prioritaires."),
        h("div", { class: "inline" }, skip, h("small", null, "Garder les photos déjà prises (reprise)")),
        h("div", { class: "pay" },
            h("button", { class: "btn small", disabled: !tool.data.screenshot, onclick: () => run("category") }, `Tout « ${c.label} »`),
            h("button", { class: "btn small", disabled: !tool.data.screenshot, onclick: () => run("all") }, "Tout le catalogue")),
        !tool.data.screenshot ? h("small", { class: "warn" }, "Indisponible : screenshot-basic ne tourne pas.") : null);
}

// Progression de la série (hors de l'écran de gestion, caché pendant les photos)
function batchShow(p) {
    const bar = $("batch");
    bar.classList.remove("hidden");
    bar.replaceChildren(
        h("div", null, h("b", null, `Photos : ${p.index} / ${p.total}`), h("small", null, `${p.label} · ${p.done} réussies${p.failed ? `, ${p.failed} ratées` : ""}`)),
        h("button", { class: "btn small ghost", onclick: () => nui("batchStop") }, "Arrêter"),
        h("div", { class: "bar" }, h("i", { style: `width:${p.total ? (p.index / p.total) * 100 : 0}%` })));
}

async function toolSex(sex) {
    if (sex === tool.data.sex) return;
    tool.busy = true;
    const data = await nui("toolSex", { sex });
    tool.busy = false;
    if (!data || !data.groups) return toast("Changement impossible.");
    tool.data = { ...tool.data, ...data, items: data.items || {} };
    tool.selected = null;
    toolGroupOpen(tool.group);
}

// Photo : centre de l'écran (screenshot-basic). Avec la photo de la tenue de base (msg.base), seuls les pixels qui
// changent sont gardés (la pièce : le corps et le fond disparaissent) ; le fond vert est aussi retiré, les reflets verts
// atténués, les points isolés effacés. Recadrage autour de la pièce, réduit en carré, renvoyé au jeu.
function loadShot(src) {
    return new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => resolve(img);
        img.onerror = () => reject(new Error("capture illisible"));
        img.src = src;
    });
}

async function cropShot(msg) {
    const send = (payload) => nui("cropped", payload).catch(() => null);
    try {
        const [shot, base] = await Promise.all([loadShot(msg.image), msg.base ? loadShot(msg.base) : null]);
        const side = Math.round(Math.min(shot.width, shot.height * msg.crop));
        const read = (img) => {
            const canvas = document.createElement("canvas");
            canvas.width = side;
            canvas.height = side;
            const ctx = canvas.getContext("2d");
            ctx.drawImage(img, (img.width - side) / 2, (img.height - side) / 2, side, side, 0, 0, side, side);
            return { canvas, ctx, pixels: ctx.getImageData(0, 0, side, side) };
        };
        const work = read(shot);
        const ref = base ? read(base).pixels.data : null;
        const p = work.pixels.data;
        const limit = msg.threshold || 45;

        for (let i = 0; i < p.length; i += 4) {
            let alpha = 255;
            if (ref) {
                const diff = Math.abs(p[i] - ref[i]) + Math.abs(p[i + 1] - ref[i + 1]) + Math.abs(p[i + 2] - ref[i + 2]);
                if (diff <= limit) alpha = 0;
                else if (diff < limit * 2) alpha = Math.round((255 * (diff - limit)) / limit);
            }
            const other = Math.max(p[i], p[i + 2]);
            const green = p[i + 1] - other;
            if (green > 70) alpha = 0;
            else if (green > 25) { alpha = Math.min(alpha, Math.round(255 * (1 - (green - 25) / 45))); p[i + 1] = other; }
            else if (green > 0) p[i + 1] = other;
            p[i + 3] = alpha;
        }

        // Points isolés (bruit entre les deux photos) effacés, puis cadre de la pièce
        const solid = new Uint8Array(side * side);
        for (let k = 0; k < solid.length; k += 1) solid[k] = p[k * 4 + 3] > 24 ? 1 : 0;
        let minX = side, minY = side, maxX = -1, maxY = -1;
        for (let y = 1; y < side - 1; y += 1) {
            for (let x = 1; x < side - 1; x += 1) {
                const k = y * side + x;
                if (!solid[k]) continue;
                const around = solid[k - 1] + solid[k + 1] + solid[k - side] + solid[k + side] + solid[k - side - 1] + solid[k - side + 1] + solid[k + side - 1] + solid[k + side + 1];
                if (around < 3) { p[k * 4 + 3] = 0; continue; }
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        }
        if (maxX < 0) return send({ error: "pièce invisible sur la photo" });

        work.ctx.putImageData(work.pixels, 0, 0);
        const w = maxX - minX + 1;
        const hgt = maxY - minY + 1;
        const box = Math.max(w, hgt) * 1.08;
        const scale = msg.size / box;
        const out = document.createElement("canvas");
        out.width = msg.size;
        out.height = msg.size;
        out.getContext("2d").drawImage(work.canvas, minX, minY, w, hgt, (msg.size - w * scale) / 2, (msg.size - hgt * scale) / 2, w * scale, hgt * scale);
        send({ image: out.toDataURL("image/webp", msg.quality) });
    } catch (e) {
        send({ error: String((e && e.message) || e).slice(0, 120) });
    }
}

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "tool") openTool(msg.data);
    else if (msg.action === "toolHide") $("tool").classList.toggle("ghosted", msg.hidden === true);
    else if (msg.action === "crop") cropShot(msg);
    else if (msg.action === "batchProgress") batchShow(msg);
    else if (msg.action === "batchDone") {
        $("batch").classList.add("hidden");
        tool.data = { ...tool.data, ...msg.data, items: msg.data.items || {} };
        tool.previews = {};
        toast(`Série terminée : ${msg.done} photos${msg.failed ? `, ${msg.failed} ratées` : ""}, visibles tout de suite dans le catalogue.`);
        paintTool();
    }
    else if (msg.action === "close") $("tool").classList.add("hidden");
});

// Aperçu hors jeu : index.html#tool
if (!inGame && location.hash.includes("tool")) {
    openTool({
        sex: "male", currency: "$", screenshot: true, images: { component: "", prop: "" }, renderer: { component: "renderer/{sex}/{id}/{drawable}.png", prop: "renderer/{sex}/p{id}/{drawable}.png" },
        items: { jacket: { 2: { label: "Veste en jean", price: 90 }, 4: { banned: true } } },
        groups: [
            { key: "tops", label: "Hauts", icon: "shirt", camera: "torso", categories: [{ key: "jacket", label: "Hauts", kind: "component", id: 11, base: 60 }, { key: "undershirt", label: "Sous-hauts", kind: "component", id: 8, base: 30 }, { key: "arms", label: "Bras", kind: "component", id: 3, base: 0 }] },
            { key: "legs", label: "Bas", icon: "pants", camera: "legs", categories: [{ key: "pants", label: "Bas", kind: "component", id: 4, base: 40 }] },
            { key: "feet", label: "Chaussures", icon: "shoe", camera: "feet", categories: [{ key: "shoes", label: "Chaussures", kind: "component", id: 6, base: 40 }] },
            { key: "head", label: "Tête", icon: "hat", camera: "head", categories: [{ key: "hat", label: "Chapeaux", kind: "prop", id: 0, base: 25 }, { key: "glasses", label: "Lunettes", kind: "prop", id: 1, base: 20 }] },
        ],
    });
}
