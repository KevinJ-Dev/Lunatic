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
    nui("camera", { view: g.camera });
    paintTool();
}

function toolImage(c, drawable) {
    const preview = tool.previews[`${tool.data.sex}:${c.key}:${drawable}`];
    if (preview) return preview;
    const item = toolItem(c, drawable);
    if (item && item.image) return item.image;
    const template = c.kind === "prop" ? tool.data.images.prop : tool.data.images.component;
    if (!template) return null;
    return template.replaceAll("{sex}", tool.data.sex).replaceAll("{id}", String(c.id)).replaceAll("{drawable}", String(drawable)).replaceAll("{texture}", "0");
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
        class: `tab${entry.key === tool.category ? " on" : ""}`, onclick: () => { tool.category = entry.key; tool.selected = null; if ($("toolGrid")) $("toolGrid").scrollTop = 0; paintTool(); },
    }, entry.label))) : null;

    if (!total) {
        toolCounts(c, 0).then(() => paintTool());
        return h("div", { class: "view" }, tabs, h("p", { class: "empty" }, "Chargement…"));
    }

    const cells = [];
    for (let i = 0; i < total.drawables; i += 1) {
        const item = toolItem(c, i);
        const url = toolImage(c, i);
        cells.push(h("button", { class: `cell${tool.selected === i ? " on" : ""}${item && item.banned ? " banned" : ""}`, onclick: () => toolSelect(c, i) },
            item && item.banned ? h("span", { class: "badge-ban" }, "Bannie") : null,
            item && item.price != null ? h("span", { class: "badge-price" }, `${item.price} ${tool.data.currency}`) : null,
            url ? h("img", { src: url, alt: "", loading: "lazy", onerror: (e) => e.target.replaceWith(h("span", { class: "num" }, String(i))) }) : h("span", { class: "num" }, String(i)),
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
        return [sexes, defaultPrice, h("div", { class: "box" }, h("p", { class: "empty" }, "Choisissez une pièce dans la grille pour modifier sa fiche."))];
    }

    const drawable = tool.selected;
    const item = toolItem(c, drawable) || {};
    const url = toolImage(c, drawable);
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
        const res = await nui("capture", { key: c.key, drawable, view: toolGroup().camera });
        tool.busy = false;
        if (!res || !res.ok) { paintTool(); return toast((res && res.error) || "Photo impossible."); }
        tool.previews[`${tool.data.sex}:${c.key}:${drawable}`] = res.preview;
        tool.data.items[c.key] = tool.data.items[c.key] || {};
        tool.data.items[c.key][String(drawable)] = { ...item, image: res.path };
        toast("Photo enregistrée (envoyée aux joueurs au prochain « ensure lunatic_clothing »).");
        paintTool();
    };

    return [sexes, defaultPrice,
        h("div", { class: "box" }, h("div", { class: "box-head" }, "Aperçu"),
            h("div", { class: "preview" },
                h("div", { class: "preview-img" }, url ? h("img", { src: url, alt: "", onerror: (e) => e.target.replaceWith(h("span", { class: "num" }, String(drawable))) }) : h("span", { class: "num" }, String(drawable))),
                h("div", null, h("b", null, form.label || `N° ${drawable}`), h("small", null, `${c.label} · ID ${drawable}`)))),
        h("div", { class: "box" }, h("div", { class: "box-head" }, "Informations"),
            h("div", { class: "form" },
                h("span", null, "Nom"), label,
                h("span", null, "Bannie"), h("div", { class: "inline" }, ban, h("small", null, "Cachée des magasins")),
                h("span", null, "Prix"), price,
                h("span", null, "Image"), image,
                h("span", null, "Photo"), h("button", { class: "btn small ghost", disabled: !tool.data.screenshot || tool.busy, title: tool.data.screenshot ? "" : "screenshot-basic absent du serveur", onclick: capture }, tool.busy ? "Photo en cours…" : "Prendre la photo")),
            !tool.data.screenshot ? h("small", { class: "warn" }, "Photo indisponible : installez et démarrez screenshot-basic.") : null,
            h("button", { class: "btn save", onclick: save }, "Sauvegarder"))];
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

// Photo : l'image plein écran (screenshot-basic) est recadrée en carré au centre, puis renvoyée au jeu
function cropShot(msg) {
    const send = (payload) => nui("cropped", payload).catch(() => null);
    const img = new Image();
    img.onload = () => {
        try {
            const side = Math.min(img.width, img.height * msg.crop);
            const canvas = document.createElement("canvas");
            canvas.width = msg.size;
            canvas.height = msg.size;
            canvas.getContext("2d").drawImage(img, (img.width - side) / 2, (img.height - side) / 2, side, side, 0, 0, msg.size, msg.size);
            send({ image: canvas.toDataURL("image/webp", msg.quality) });
        } catch (e) {
            send({ error: String((e && e.message) || e).slice(0, 120) });
        }
    };
    img.onerror = () => send({ error: "capture illisible" });
    img.src = msg.image;
}

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "tool") openTool(msg.data);
    else if (msg.action === "toolHide") $("tool").classList.toggle("ghosted", msg.hidden === true);
    else if (msg.action === "crop") cropShot(msg);
    else if (msg.action === "close") $("tool").classList.add("hidden");
});

// Aperçu hors jeu : index.html#tool
if (!inGame && location.hash.includes("tool")) {
    openTool({
        sex: "male", currency: "$", screenshot: false, images: { component: "", prop: "" },
        items: { jacket: { 2: { label: "Veste en jean", price: 90 }, 4: { banned: true } } },
        groups: [
            { key: "tops", label: "Hauts", icon: "shirt", camera: "torso", categories: [{ key: "jacket", label: "Hauts", kind: "component", id: 11, base: 60 }, { key: "undershirt", label: "Sous-hauts", kind: "component", id: 8, base: 30 }, { key: "arms", label: "Bras", kind: "component", id: 3, base: 0 }] },
            { key: "legs", label: "Bas", icon: "pants", camera: "legs", categories: [{ key: "pants", label: "Bas", kind: "component", id: 4, base: 40 }] },
            { key: "feet", label: "Chaussures", icon: "shoe", camera: "feet", categories: [{ key: "shoes", label: "Chaussures", kind: "component", id: 6, base: 40 }] },
            { key: "head", label: "Tête", icon: "hat", camera: "head", categories: [{ key: "hat", label: "Chapeaux", kind: "prop", id: 0, base: 25 }, { key: "glasses", label: "Lunettes", kind: "prop", id: 1, base: 20 }] },
        ],
    });
}
