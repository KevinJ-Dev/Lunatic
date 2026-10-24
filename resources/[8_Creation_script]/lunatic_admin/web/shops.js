"use strict";

// ====================================================================
//  lunatic_admin — lot C1 : tuile Catalogues = magasins automatiques
//  Grille des catégories (LTD, Ammunation, Grossistes…), puis magasins d'une catégorie :
//  label, clé, blip, image d'en-tête, jobs autorisés, articles (prix, permis), emplacements.
// ====================================================================

const SHOP_ICONS = {
    ltd: "i-store", binco: "i-shirt", vangelico: "i-gem", barber: "i-scissors", ammunation: "i-crosshair", rental: "i-key",
    masquerade: "i-mask", shenails: "i-sparkle", skateshop: "i-skate", tattoo: "i-edit", wholesale: "i-truck",
};

const shopState = { category: null, categories: null, shops: null, selected: null, draft: null, licenses: [], jobs: [] };

function renderShops() {
    // Rendu seulement à l'ouverture de la page (un rafraîchissement d'état ne doit pas effacer la saisie)
    if ($("view-catalogs").childElementCount && shopState.painted) return;
    shopState.painted = true;
    if (shopState.category) paintShopCategory();
    else paintShopCategories();
    if (!shopState.categories) loadShopCategories();
}

async function loadShopCategories() {
    const res = await nui("action", { action: "shops.categories", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    shopState.categories = res.categories || [];
    if (!shopState.category) paintShopCategories();
}

function paintShopCategories() {
    const root = $("view-catalogs");
    if (!shopState.categories) return root.replaceChildren(h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-book"), "Chargement…")));
    root.replaceChildren(h("div", { class: "content" },
        h("div", { class: "page-head" }, h("div", { class: "grow" },
            h("h1", { class: "page-title" }, "Liste des catalogues"),
            h("div", { class: "page-sub" }, "Magasins automatiques : prix, articles, emplacements et blips. Tout s'applique en jeu sans redémarrage."))),
        h("div", { class: "scroll" }, h("div", { class: "tiles" }, shopState.categories.map((c) => {
            const tile = h("button", { class: `tile${c.ready ? "" : " soon"}`, onclick: () => openShopCategory(c) },
                icon(SHOP_ICONS[c.id] || "i-store"), h("span", null, c.label),
                h("small", { class: "tile-count" }, c.ready ? `${c.count} magasin${c.count > 1 ? "s" : ""}` : "bientôt"));
            return tile;
        })))
    ));
}

function openShopCategory(category) {
    if (!category.ready) return toast(`${category.label} : arrive dans un prochain lot (magasins d'apparence ou location).`, "info");
    shopState.category = category;
    shopState.shops = null;
    shopState.selected = null;
    shopState.draft = null;
    paintShopCategory();
    loadShopList();
}

function closeShopCategory() {
    guardUnsaved("catalogs", doCloseShopCategory);
}

function doCloseShopCategory() {
    untrackUnsaved("catalogs");
    shopState.selected = null;
    shopState.draft = null;
    shopState.category = null;
    shopState.categories = null;
    paintShopCategories();
    loadShopCategories();
}

async function loadShopList() {
    const res = await nui("action", { action: "shops.list", payload: { category: shopState.category.id } }).catch(() => null);
    if (!res || !res.ok) return;
    shopState.shops = res.shops || [];
    paintShopCategory();
}

// Partie de la fiche enregistrée par « Enregistrer » (les emplacements sont enregistrés tout de suite)
function shopSnapshot(d) {
    return JSON.stringify([d.label, d.slug, d.blip, d.header || "", d.jobs, (d.items || []).map((e) => [e.item, e.price, e.license || null]), d.defaultPrice || 0]);
}

// Image d'un véhicule : celle du panel, sinon la photo officielle des véhicules du jeu (docs FiveM)
const vehicleImage = (v) => v.image || `https://docs.fivem.net/vehicles/${v.model}.webp`;

function selectShop(id) {
    if (shopState.selected === id && shopState.draft) return;
    guardUnsaved("catalogs", () => doSelectShop(id));
}

async function doSelectShop(id) {
    untrackUnsaved("catalogs");
    shopState.selected = id;
    shopState.draft = null;
    paintShopCategory();
    const res = await nui("action", { action: "shops.info", payload: { id } }).catch(() => null);
    if (id !== shopState.selected) return;
    if (!res || !res.ok) return toast((res && res.error) || "Magasin introuvable.", "error");
    shopState.draft = JSON.parse(JSON.stringify(res.shop));
    shopState.saved = shopSnapshot(shopState.draft);
    trackUnsaved("catalogs", {
        label: `Magasin ${res.shop.label}`,
        isDirty: () => !!shopState.draft && shopSnapshot(shopState.draft) !== shopState.saved,
        save: () => document.querySelector("#view-catalogs .shop-save")?.click(),
        reset: () => doSelectShop(id),
    });
    shopState.licenses = res.licenses || [];
    shopState.jobs = res.jobs || [];
    paintShopCategory();
}

// Action qui recharge la liste et la fiche (emplacements, suppression)
async function shopAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) {
        await loadShopList();
        if (shopState.selected && action !== "shops.delete") {
            // Les emplacements changent côté serveur : on garde la saisie en cours, on recharge seulement leur liste
            const info = await nui("action", { action: "shops.info", payload: { id: shopState.selected } }).catch(() => null);
            if (info && info.ok && shopState.draft) {
                shopState.draft.locations = info.shop.locations;
                paintShopCategory();
            }
        }
    }
    return res;
}

// Ce qui empêche un magasin de fonctionner en jeu (counts = nombres, ou la fiche en cours d'édition)
function shopProblems(counts, rental) {
    const problems = [];
    if (!counts.locations) problems.push("aucun emplacement");
    if (rental && !counts.vehicles) problems.push("aucun véhicule à louer");
    if (!rental && !counts.items) problems.push("aucun article");
    if (counts.missing) problems.push(`${counts.missing} objet${counts.missing > 1 ? "s" : ""} inconnu${counts.missing > 1 ? "s" : ""}`);
    return problems;
}

function paintShopCategory() {
    const body = $("view-catalogs");
    const category = shopState.category;
    const list = shopState.shops;

    const sidebar = h("aside", { class: "sidebar shops-side" },
        h("button", { class: "shops-back", onclick: closeShopCategory }, icon("i-back"), category.label),
        h("div", { class: "side-scroll" }, !list ? h("div", { class: "muted side-empty" }, "Chargement…")
            : list.length ? list.map((s) => h("div", { class: `list-row shop-row${s.id === shopState.selected ? " active" : ""}`, onclick: () => selectShop(s.id) },
                readyDot(shopProblems(s, category.kind === "rental")),
                h("span", { class: "name" }, s.label),
                h("span", { class: "cnt", title: "Articles" }, String(s.items)),
                h("button", { class: "shop-x", title: "Supprimer", onclick: (e) => { e.stopPropagation(); deleteShop(s); } }, icon("i-x"))))
                : h("div", { class: "muted side-empty" }, "Aucun magasin.")),
        h("div", { class: "side-foot" }, h("button", { class: "btn primary", style: "width:100%", onclick: openCreateShop }, icon("i-plus"), "Nouveau magasin"))
    );

    let content;
    if (!shopState.selected) content = h("div", { class: "content" }, h("div", { class: "empty" }, icon(SHOP_ICONS[category.id] || "i-store"), `Choisissez un magasin ${category.label} ou créez-en un.`));
    else if (!shopState.draft) content = h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-store"), "Chargement du magasin…"));
    else content = shopForm();

    const previous = body.querySelector(".shop-form .scroll");
    const keepScroll = previous && body.dataset.shop === String(shopState.selected) ? previous.scrollTop : 0;
    body.dataset.shop = String(shopState.selected);
    body.replaceChildren(sidebar, content);
    const scroller = body.querySelector(".shop-form .scroll");
    if (scroller) scroller.scrollTop = keepScroll;
}

function shopForm() {
    const d = shopState.draft;
    const bind = (input, setter) => { input.addEventListener("input", () => setter(input.value)); return input; };
    const field = (label, ...control) => h("div", { class: "shop-field" }, h("label", null, label), ...control);

    const label = bind(h("input", { class: "input", maxlength: "60", value: d.label }), (v) => { d.label = v; });
    const slug = bind(h("input", { class: "input mono", maxlength: "30", value: d.slug }), (v) => { d.slug = v.toLowerCase(); });
    const sprite = bind(h("input", { class: "input mono", type: "number", min: "0", value: String(d.blip.sprite) }), (v) => { d.blip.sprite = Number(v); });
    const color = bind(h("input", { class: "input mono", type: "number", min: "0", value: String(d.blip.color) }), (v) => { d.blip.color = Number(v); });
    const scale = bind(h("input", { class: "input mono", type: "number", step: "0.1", min: "0.1", value: String(d.blip.scale) }), (v) => { d.blip.scale = Number(v); });
    const blipLabel = bind(h("input", { class: "input", maxlength: "60", value: d.blip.label || "", placeholder: d.label }), (v) => { d.blip.label = v; });
    const header = bind(h("input", { class: "input mono", maxlength: "255", value: d.header || "", placeholder: "assets/catalogues/headers/... ou https://…" }), (v) => { d.header = v; });
    const defaultPrice = bind(h("input", { class: "input mono", type: "number", min: "0", value: String(d.defaultPrice || 0) }), (v) => { d.defaultPrice = Math.max(0, Math.floor(Number(v) || 0)); });
    const applyDefault = h("button", { class: "btn small ghost", title: "Met ce prix sur tous les articles (pensez à « Enregistrer »)", onclick: () => {
        d.items.forEach((e) => { e.price = d.defaultPrice || 0; });
        paintShopCategory();
    } }, icon("i-copy"), "Appliquer à tous");

    // Jobs autorisés : vide = tout le monde
    const jobLabel = (name) => (shopState.jobs.find((j) => j.name === name) || {}).label || name;
    const jobSelect = h("select", { class: "input shop-job-add" }, [h("option", { value: "" }, "Ajouter un job…"),
        ...shopState.jobs.filter((j) => !d.jobs.includes(j.name)).map((j) => h("option", { value: j.name }, j.label))]);
    jobSelect.addEventListener("change", () => { if (jobSelect.value) { d.jobs.push(jobSelect.value); paintShopCategory(); } });
    const jobs = h("div", { class: "chips" },
        d.jobs.length ? d.jobs.map((name, i) => h("span", { class: "chip" }, jobLabel(name),
            h("button", { class: "chip-x", onclick: () => { d.jobs.splice(i, 1); paintShopCategory(); } }, icon("i-x")))) : h("span", { class: "muted" }, "tout le monde peut acheter"),
        jobSelect);

    // Agence de location : véhicules proposés, rangés par catégorie
    const rental = shopState.category.kind === "rental";
    const buyback = shopState.category.kind === "buyback";
    const vehicleRow = (v) => {
        const img = h("img", { class: "vehicle-img", src: vehicleImage(v), alt: "" });
        img.addEventListener("error", () => { img.style.visibility = "hidden"; });
        return h("div", { class: "row point-row vehicle-row" }, img,
            h("div", { class: "who" }, h("b", null, v.label), h("span", null, `${v.model} · ${v.price ? money(v.price) : "gratuit"} pour ${v.duration} min`)),
            h("div", { class: "btn-row" },
                h("button", { class: "btn small ghost", onclick: () => openRentalVehicle(d, v) }, icon("i-edit"), "Modifier"),
                h("button", { class: "btn small ghost", title: "Retirer", onclick: () => shopAct("shops.deleteVehicle", { id: d.id, vehicleId: v.id }, "Véhicule retiré.") }, icon("i-trash"))));
    };
    const vehicleGroups = new Map();
    for (const v of d.vehicles || []) {
        const key = v.category || "Sans catégorie";
        if (!vehicleGroups.has(key)) vehicleGroups.set(key, []);
        vehicleGroups.get(key).push(v);
    }
    const vehicles = [...vehicleGroups.entries()].sort((a, b) => a[0].localeCompare(b[0])).flatMap(([name, list]) => [
        vehicleGroups.size > 1 ? h("div", { class: "section-head", style: "margin-top:10px" }, `${name} (${list.length})`) : null,
        h("div", { class: "table" }, list.map(vehicleRow)),
    ]).filter(Boolean);

    // Articles
    const licenseOptions = (value) => [h("option", { value: "" }, "Aucun permis"), ...shopState.licenses.map((l) => h("option", { value: l.type, selected: l.type === value }, l.label))];
    const items = d.items.map((entry, i) => {
        const price = h("input", { class: "input mono", type: "number", min: "0", value: String(entry.price) });
        price.addEventListener("input", () => { entry.price = Number(price.value || 0); });
        const license = h("select", { class: "input" }, licenseOptions(entry.license));
        license.addEventListener("change", () => { entry.license = license.value || null; });
        // Grossiste : pas de permis, le prix est celui payé au joueur
        if (buyback) license.style.visibility = "hidden";
        return h("div", { class: "row shop-item-row" },
            itemImage(entry.item),
            h("div", { class: "who" }, h("b", null, entry.item, entry.missing ? h("span", { class: "badge ban", style: "margin-left:6px" }, "objet inconnu") : null), h("span", null, entry.label)),
            license,
            h("label", { class: "salary" }, price, h("span", { class: "muted" }, "$")),
            h("button", { class: "btn small ghost", title: "Retirer", onclick: () => { d.items.splice(i, 1); paintShopCategory(); } }, icon("i-x")));
    });

    // Emplacements (enregistrés tout de suite, à la position du staff)
    const locations = d.locations.map((l, i) => h("div", { class: "row point-row" },
        h("span", { class: "pid mono" }, String(i + 1)),
        h("div", { class: "who" }, h("b", null, `Emplacement ${i + 1}`), h("span", null, `${l.x.toFixed(1)}, ${l.y.toFixed(1)}, ${l.z.toFixed(1)}${rental ? (l.spawn ? " · sortie définie" : " · sortie : devant le comptoir") : ""}`)),
        h("div", { class: "btn-row" },
            rental ? h("button", { class: "btn small", title: "Placez-vous là où le véhicule doit apparaître, dans le sens de sortie", onclick: () => shopAct("shops.setSpawn", { locationId: l.id }, "Sortie des véhicules définie à votre position.") }, icon("i-car"), "Sortie") : null,
            h("button", { class: "btn small", onclick: () => shopAct("shops.moveLocation", { locationId: l.id }, "Emplacement replacé à votre position.") }, icon("i-crosshair"), "Définir"),
            h("button", { class: "btn small ghost", onclick: () => act("shops.tpLocation", { locationId: l.id }, null) }, icon("i-goto"), "TP"),
            h("button", { class: "btn small ghost", title: "Supprimer", onclick: () => shopAct("shops.deleteLocation", { locationId: l.id }, "Emplacement supprimé.") }, icon("i-trash")))));

    const save = h("button", { class: "btn primary shop-save" }, icon("i-save"), "Enregistrer");
    save.addEventListener("click", async () => {
        const snapshot = shopSnapshot(d);
        const res = await shopAct("shops.save", {
        id: d.id, label: d.label.trim(), slug: d.slug.trim(), blipSprite: d.blip.sprite, blipColor: d.blip.color, blipScale: d.blip.scale,
        blipLabel: (d.blip.label || "").trim(), header: (d.header || "").trim(), jobs: d.jobs, defaultPrice: d.defaultPrice || 0,
        items: d.items.map((e) => ({ item: e.item, price: e.price, license: e.license || null })),
    }, "Magasin enregistré.");
        if (res) shopState.saved = snapshot;
        paintUnsaved();
    });

    const problems = shopProblems({ locations: d.locations.length, vehicles: (d.vehicles || []).length, items: d.items.length, missing: d.items.filter((e) => e.missing).length }, rental);
    return h("div", { class: "content shop-form" },
        h("div", { class: "page-head" }, h("div", { class: "grow" }, h("h1", { class: "page-title" }, d.label, readyBadge(problems)), h("div", { class: "page-sub mono" }, d.slug))),
        h("div", { class: "scroll" },
            readyHint(problems),
            h("div", { class: "card shop-fields" },
                field("Label (affiché en jeu)", label),
                field("Clé interne (slug)", slug),
                field("Blip sprite / couleur / taille", h("div", { class: "blip-row" }, sprite, color, scale)),
                field("Blip label (sur la carte)", blipLabel),
                field("Image (en-tête)", header),
                rental ? null : field(buyback ? "Prix de rachat par défaut" : "Prix par défaut des articles", h("div", { class: "blip-row" }, defaultPrice, applyDefault)),
                field(buyback ? "Jobs autorisés à revendre" : "Jobs autorisés", jobs)),
            rental ? h("div", { class: "card", style: "margin-top:16px" },
                h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, `Véhicules (${(d.vehicles || []).length})`),
                    h("button", { class: "btn small primary", onclick: () => openRentalVehicle(d, null) }, icon("i-plus"), "Ajouter")),
                vehicles.length ? vehicles : h("p", { class: "hint-line", style: "margin:0" }, "Aucun véhicule à louer."),
                h("p", { class: "hint-line" }, "Le client paie en liquide ou par carte, garde le véhicule le temps indiqué, puis le véhicule est repris. Il peut le rendre plus tôt au comptoir."))
            : h("div", { class: "card", style: "margin-top:16px" },
                h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, buyback ? `Objets rachetés (${d.items.length})` : `Articles (${d.items.length})`),
                    h("button", { class: "btn small primary", onclick: openAddShopItem }, icon("i-plus"), "Ajouter")),
                items.length ? h("div", { class: "table" }, items) : h("p", { class: "hint-line", style: "margin:0" }, buyback ? "Aucun objet racheté." : "Aucun article."),
                buyback ? h("p", { class: "hint-line" }, "Les joueurs revendent ici leurs récoltes et produits : le prix indiqué leur est payé en liquide, par unité.") : null),
            h("div", { class: "card", style: "margin-top:16px" },
                h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, `Emplacements (${d.locations.length})`),
                    h("button", { class: "btn small", onclick: () => shopAct("shops.addLocation", { id: d.id }, "Emplacement ajouté à votre position.") }, icon("i-plus"), "Ajouter à ma position")),
                locations.length ? h("div", { class: "table" }, locations) : h("p", { class: "hint-line", style: "margin:0" }, "Aucun emplacement : le magasin n'apparaît pas en jeu."),
                h("p", { class: "hint-line" }, "Les emplacements sont enregistrés tout de suite. Articles et réglages : bouton « Enregistrer ».")),
            h("div", { class: "btn-row", style: "margin-top:16px;justify-content:flex-end" }, save))
    );
}

function openRentalVehicle(d, v) {
    const model = h("input", { class: "input mono", maxlength: "32", placeholder: "Modèle, ex. faggio", value: v ? v.model : "", disabled: !!v });
    const label = h("input", { class: "input", maxlength: "60", placeholder: "Nom affiché, ex. Scooter Faggio", value: v ? v.label : "" });
    const price = h("input", { class: "input mono", type: "number", min: "0", value: String(v ? v.price : 100) });
    const duration = h("input", { class: "input mono", type: "number", min: "1", value: String(v ? v.duration : 30) });
    const categories = [...new Set((d.vehicles || []).map((x) => x.category).filter(Boolean))];
    document.getElementById("rental-categories")?.remove();
    document.body.append(h("datalist", { id: "rental-categories" }, categories.map((c) => h("option", { value: c }))));
    const category = h("input", { class: "input", maxlength: "40", list: "rental-categories", placeholder: "Ex. Scooters, Citadines, Utilitaires", value: v ? v.category : "" });
    const image = h("input", { class: "input mono", maxlength: "255", placeholder: "Vide = photo officielle du modèle", value: v ? v.image : "" });
    const preview = h("img", { class: "vehicle-preview", alt: "" });
    const paintPreview = () => {
        preview.style.visibility = "visible";
        preview.src = image.value.trim() || (model.value.trim() ? `https://docs.fivem.net/vehicles/${model.value.trim().toLowerCase()}.webp` : "");
    };
    preview.addEventListener("error", () => { preview.style.visibility = "hidden"; });
    image.addEventListener("input", paintPreview);
    model.addEventListener("change", paintPreview);
    paintPreview();

    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon(v ? "i-save" : "i-plus"), v ? "Enregistrer" : "Ajouter");
        submit.addEventListener("click", async () => {
            const payload = { id: d.id, label: label.value.trim(), price: Number(price.value), duration: Number(duration.value), category: category.value.trim(), image: image.value.trim() };
            const res = v
                ? await shopAct("shops.updateVehicle", { ...payload, vehicleId: v.id }, "Véhicule modifié.")
                : await shopAct("shops.addVehicle", { ...payload, model: model.value.trim().toLowerCase() }, "Véhicule ajouté.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, v ? `Modifier ${v.label}` : "Ajouter un véhicule à louer"), h("p", null, v ? "Le modèle ne change pas : retirez le véhicule pour en mettre un autre." : "Le modèle est vérifié par votre jeu : soyez connecté.")),
            h("div", { class: "body event-form" },
                preview,
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Modèle"), model),
                    h("div", { class: "field" }, h("label", null, "Nom affiché"), label)),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Prix ($)"), price),
                    h("div", { class: "field" }, h("label", null, "Durée (minutes)"), duration)),
                h("div", { class: "field" }, h("label", null, "Catégorie"), category),
                h("div", { class: "field" }, h("label", null, "Image (adresse https, facultative)"), image)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    (v ? label : model).focus();
}

async function openAddShopItem() {
    const items = await loadCatalogItems();
    const known = new Map(items.map((i) => [i.name, i.label]));
    const input = itemPicker(items, "");
    const price = h("input", { class: "input mono", type: "number", min: "0", value: String(shopState.draft.defaultPrice || 0) });
    // Prix de base de l'objet (tuile Items) proposé quand il en a un
    input.addEventListener("change", () => {
        const found = items.find((i) => i.name === input.value.trim());
        if (found && found.price > 0) price.value = String(found.price);
    });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-plus"), "Ajouter");
        submit.addEventListener("click", () => {
            const name = input.value.trim();
            if (!known.has(name)) return toast(`L'objet « ${name} » n'existe pas dans ox_inventory.`, "error");
            if (shopState.draft.items.some((e) => e.item === name)) return toast("Cet objet est déjà dans le magasin.", "error");
            shopState.draft.items.push({ item: name, label: known.get(name), price: Math.max(0, Math.floor(Number(price.value) || 0)), license: null });
            close();
            paintShopCategory();
        });
        return [
            h("header", null, h("h3", null, "Ajouter un article"), h("p", null, "Pensez à « Enregistrer » ensuite.")),
            h("div", { class: "body event-form" },
                h("div", { class: "field" }, h("label", null, "Objet"), input),
                h("div", { class: "field" }, h("label", null, "Prix ($)"), price)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    input.focus();
}

function openCreateShop() {
    const category = shopState.category;
    const label = h("input", { class: "input", maxlength: "60", placeholder: `Ex. ${category.label} Vinewood` });
    const slug = h("input", { class: "input mono", maxlength: "30", placeholder: `${category.id}_vinewood` });
    let touched = false;
    label.addEventListener("input", () => { if (!touched) slug.value = poleSlug(label.value); });
    slug.addEventListener("input", () => { touched = true; });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-plus"), "Créer");
        submit.addEventListener("click", async () => {
            const res = await act("shops.create", { category: category.id, label: label.value.trim(), slug: slug.value.trim() }, "Magasin créé.");
            if (!res) return;
            close();
            await loadShopList();
            selectShop(res.id);
        });
        return [
            h("header", null, h("h3", null, `Nouveau magasin · ${category.label}`)),
            h("div", { class: "body event-form" },
                h("div", { class: "field" }, h("label", null, "Label (affiché en jeu)"), label),
                h("div", { class: "field" }, h("label", null, "Clé interne (slug)"), slug)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    label.focus();
}

async function deleteShop(s) {
    const yes = await confirmBox(`Supprimer « ${s.label} » ?`, "Le magasin, ses articles et ses emplacements sont effacés. Action définitive.", "Supprimer", true);
    if (!yes) return;
    const res = await shopAct("shops.delete", { id: s.id }, "Magasin supprimé.");
    if (res && shopState.selected === s.id) {
        shopState.selected = null;
        shopState.draft = null;
        paintShopCategory();
    }
}
