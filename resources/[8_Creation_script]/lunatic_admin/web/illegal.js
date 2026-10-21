"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal
//  Onglets ajoutés au fil des étapes : Recelleur (étape 2), Drogues (étape 3), Territoires (étape 4), Craft d'armes (étape 5), Tablette et marché noir (étape 6), Missions (étape 7a), puis braquages.
// ====================================================================

const ILLEGAL_TABS = [
    { value: "fence", label: "Recelleur" },
    { value: "drugs", label: "Drogues" },
    { value: "territories", label: "Territoires" },
    { value: "craft", label: "Craft d'armes" },
    { value: "tablet", label: "Tablette" },
    { value: "missions", label: "Missions" },
];

const illegalState = { tab: "fence", fence: null, painted: false };

function renderIllegal() {
    if (illegalState.painted && $("view-illegal").childElementCount) return;
    illegalState.painted = true;
    paintIllegal();
    loadFence();
}

async function loadFence() {
    const res = await nui("action", { action: "fence.info", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    illegalState.fence = res;
    paintIllegal();
}

async function fenceAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) await loadFence();
    return res;
}

function paintIllegal() {
    const root = $("view-illegal");
    const previous = root.querySelector(".scroll");
    const keepScroll = previous ? previous.scrollTop : 0;

    const tabs = h("div", { class: "segmented" }, ILLEGAL_TABS.map((t) =>
        h("button", { "aria-checked": String(illegalState.tab === t.value), class: t.soon ? "soon" : "", title: t.soon ? "Étape suivante de l'illégal" : null,
            onclick: () => t.soon ? toast(`${t.label} : arrive dans une prochaine étape.`, "info") : (illegalState.tab = t.value, paintIllegal()) }, t.label)));

    root.replaceChildren(h("div", { class: "content" },
        h("div", { class: "page-head" }, h("div", { class: "grow" },
            h("h1", { class: "page-title" }, "Illégal"),
            h("div", { class: "page-sub" }, "Gestion des activités illégales, appliquée en jeu sans redémarrage"))),
        h("div", { class: "struct-tabs", style: "padding-left:0" }, tabs),
        h("div", { class: "scroll" }, illegalState.tab === "drugs" ? drugsPanel() : illegalState.tab === "territories" ? territoriesPanel() : illegalState.tab === "craft" ? workshopsPanel() : illegalState.tab === "tablet" ? marketPanel() : illegalState.tab === "missions" ? contractsPanel() : fencePanel())
    ));

    const scroller = root.querySelector(".scroll");
    if (scroller) scroller.scrollTop = keepScroll;
}

// ---------- Recelleur ----------

function fenceProblems(f) {
    const problems = [];
    if (!f.items.length) problems.push("aucun objet racheté");
    if (!f.locations.length) problems.push("aucun recelleur placé");
    const unknown = f.items.filter((i) => i.missing).length;
    if (unknown) problems.push(`${unknown} objet${unknown > 1 ? "s" : ""} inconnu${unknown > 1 ? "s" : ""}`);
    return problems;
}

function fencePanel() {
    const f = illegalState.fence;
    if (!f) return h("div", { class: "empty" }, icon("i-mask"), "Chargement du recelleur…");
    const problems = fenceProblems(f);

    // Catalogue regroupé par catégorie
    const groups = [];
    for (const category of f.categories) {
        const rows = f.items.filter((i) => i.category === category).map((i) => h("div", { class: "row catalog-row" },
            itemImage(i.item),
            h("div", { class: "who" }, h("b", null, i.label, i.missing ? h("span", { class: "badge ban", style: "margin-left:6px" }, "objet inconnu") : null),
                h("span", null, `${i.item} · racheté ${money(i.price)} l'unité`)),
            h("div", { class: "btn-row" },
                h("button", { class: "btn small ghost", onclick: () => openFenceItem(i, false) }, icon("i-edit"), "Modifier"),
                h("button", { class: "btn small ghost", title: "Dupliquer", onclick: () => openFenceItem(i, true) }, icon("i-copy")),
                h("button", { class: "btn small ghost", title: "Supprimer", onclick: async () => {
                    const yes = await confirmBox(`Retirer « ${i.label} » du recelleur ?`, "Il ne sera plus racheté.", "Retirer", true);
                    if (yes) fenceAct("fence.deleteItem", { id: i.id }, "Objet retiré.");
                } }, icon("i-trash")))));
        groups.push(h("div", { class: "section-head", style: "margin-top:14px" }, category), h("div", { class: "table" }, rows));
    }

    const locations = f.locations.map((l, index) => h("div", { class: "row point-row" },
        h("span", { class: "pid mono" }, String(index + 1)),
        h("div", { class: "who" }, h("b", null, `Recelleur ${index + 1}`), h("span", null, `${l.ped} · ${l.x.toFixed(1)}, ${l.y.toFixed(1)}, ${l.z.toFixed(1)}`)),
        h("div", { class: "btn-row" },
            h("button", { class: "btn small", title: "Placer le PNJ à votre position et orientation", onclick: () => fenceAct("fence.moveLocation", { id: l.id }, "Recelleur replacé à votre position.") }, icon("i-crosshair"), "Définir"),
            h("button", { class: "btn small ghost", onclick: () => act("fence.tpLocation", { id: l.id }, null) }, icon("i-goto"), "TP"),
            h("button", { class: "btn small ghost", title: "Modèle du PNJ", onclick: () => openFencePed(l) }, icon("i-player")),
            h("button", { class: "btn small ghost", title: "Supprimer", onclick: () => fenceAct("fence.deleteLocation", { id: l.id }, "Recelleur supprimé.") }, icon("i-trash")))));

    return h("div", null,
        h("div", { class: "card" },
            h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, `Catalogue du recelleur (${f.items.length})`, readyBadge(problems)),
                h("button", { class: "btn small primary", onclick: () => openFenceItem(null, false) }, icon("i-plus"), "Ajouter un objet")),
            readyHint(problems),
            f.items.length ? groups : h("p", { class: "hint-line", style: "margin:0" }, "Aucun objet racheté pour l'instant.")),
        h("div", { class: "card", style: "margin-top:16px" },
            h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, `Emplacements (${f.locations.length})`),
                h("button", { class: "btn small", onclick: () => fenceAct("fence.addLocation", { ped: f.defaultPed }, "Recelleur ajouté à votre position.") }, icon("i-plus"), "Ajouter à ma position")),
            locations.length ? h("div", { class: "table" }, locations) : h("p", { class: "hint-line", style: "margin:0" }, "Aucun recelleur placé : personne ne peut revendre."),
            h("p", { class: "hint-line" }, "Le PNJ apparaît là où vous vous tenez, tourné dans votre direction. Pas de blip : il faut connaître l'endroit."))
    );
}

async function openFenceItem(entry, duplicate) {
    const items = await loadCatalogItems();
    const known = new Set(items.map((i) => i.name));
    const f = illegalState.fence;
    const item = itemPicker(items, entry ? entry.item : "");
    const price = h("input", { class: "input mono", type: "number", min: "0", value: String(entry ? entry.price : 0) });
    const listId = "fence-categories";
    document.getElementById(listId)?.remove();
    document.body.append(h("datalist", { id: listId }, f.categories.map((c) => h("option", { value: c }))));
    const category = h("input", { class: "input", list: listId, maxlength: "40", value: entry ? entry.category : (f.categories[0] || "Objets volés") });
    const editing = entry && !duplicate;

    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), editing ? "Enregistrer" : "Ajouter");
        submit.addEventListener("click", async () => {
            const name = item.value.trim();
            if (!known.has(name)) return toast(`L'objet « ${name} » n'existe pas dans ox_inventory.`, "error");
            const res = await fenceAct("fence.saveItem", { id: editing ? entry.id : null, item: name, price: Number(price.value), category: category.value.trim() }, editing ? "Objet modifié." : "Objet ajouté.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, editing ? "Modifier l'objet" : duplicate ? "Dupliquer l'objet" : "Ajouter un objet"), h("p", null, "Prix payé au joueur pour une unité.")),
            h("div", { class: "body event-form" },
                h("div", { class: "field" }, h("label", null, "Objet"), item),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Prix de rachat ($)"), price),
                    h("div", { class: "field" }, h("label", null, "Catégorie"), category))),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    item.focus();
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
