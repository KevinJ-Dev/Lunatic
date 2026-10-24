"use strict";

// ====================================================================
//  lunatic_admin — tuile Interactions
//  Tous les points d'interaction du monde (magasins, location, grossistes, recelleur) : catégories à gauche, grille au
//  centre, fiche à droite (mini-carte, TP, Définir, PNJ, rayon du [E], blip). Mode édition : points visibles en jeu.
//  Les données restent celles des tuiles Catalogues et Illégal (actions shops.* et fence.*).
// ====================================================================

const itState = { data: null, group: "all", search: "", sel: null, draft: null, saved: "", editMode: false, map: null };

function renderInteractions() {
    if (itState.data && $("view-interactions").childElementCount) return;
    paintInteractions();
    loadInteractions();
}

async function loadInteractions() {
    const res = await nui("action", { action: "interactions.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    itState.data = res;
    paintInteractions();
}

function itGo(changes) {
    guardUnsaved("interactions", () => {
        untrackUnsaved("interactions");
        Object.assign(itState, changes, { draft: null });
        paintInteractions();
    });
}

function itEntry() {
    return (itState.data.interactions || []).find((i) => i.key === itState.sel) || null;
}

const itGroupLabel = (id) => ((itState.data.groups || []).find((g) => g.id === id) || {}).label || id;
const itTitle = (i) => `${i.label} · ${i.index ? `n° ${i.index}` : `#${i.id}`}`;

// Action selon la source (magasin ou recelleur), puis rechargement
async function itAct(entry, what, extra, okMessage) {
    const shop = entry.source === "shop";
    const actions = {
        tp: shop ? ["shops.tpLocation", { locationId: entry.id }] : ["fence.tpLocation", { id: entry.id }],
        move: shop ? ["shops.moveLocation", { locationId: entry.id }] : ["fence.moveLocation", { id: entry.id }],
        placePed: shop ? ["shops.placePed", { locationId: entry.id }] : ["fence.moveLocation", { id: entry.id }],
        delete: shop ? ["shops.deleteLocation", { locationId: entry.id }] : ["fence.deleteLocation", { id: entry.id }],
    };
    const [action, payload] = actions[what];
    const res = await act(action, { ...payload, ...(extra || {}) }, okMessage);
    if (res && what !== "tp") await loadInteractions();
    return res;
}

// ---------- Mise en page ----------

function paintInteractions() {
    const root = $("view-interactions");
    const d = itState.data;
    if (!d) return root.replaceChildren(h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-crosshair"), "Chargement des interactions…")));

    const list = d.interactions || [];
    const count = (id) => (id === "all" ? list.length : list.filter((i) => i.group === id).length);
    const groups = [{ id: "all", label: "Tous" }, ...(d.groups || [])];
    const search = h("input", { placeholder: "Rechercher…", value: itState.search });
    search.addEventListener("input", () => {
        itState.search = search.value;
        const pos = search.selectionStart;
        paintInteractions();
        const again = $("view-interactions").querySelector(".it-search input");
        if (again) { again.focus(); again.setSelectionRange(pos, pos); }
    });

    const nav = h("aside", { class: "sidebar crew-nav crew-scroll" },
        h("div", { class: "crew-block" },
            h("div", { class: "crew-block-head" }, icon("i-layers"), "Catégories", h("span", { class: "cnt", style: "margin-left:auto" }, String(list.length))),
            groups.map((g) => h("button", { class: `list-row${itState.group === g.id ? " active" : ""}`, onclick: () => itState.group !== g.id && itGo({ group: g.id }) },
                h("span", { class: "name" }, g.label), g.soon ? h("span", { class: "badge muted" }, "bientôt") : null, h("span", { class: "cnt" }, String(count(g.id))))),
            h("label", { class: "search it-search" }, icon("i-search"), search)));

    const q = fold(itState.search.trim());
    const shown = list.filter((i) => (itState.group === "all" || i.group === itState.group) && (!q || fold(`${i.label} ${itGroupLabel(i.group)} ${i.ped}`).includes(q)));
    const group = groups.find((g) => g.id === itState.group);
    const grid = shown.length
        ? h("div", { class: "it-grid" }, shown.map((i) => h("button", { class: `it-card${i.key === itState.sel ? " on" : ""}`, onclick: () => i.key !== itState.sel && itGo({ sel: i.key }) },
            h("span", { class: "it-icon" }, blipIcon(i.blip ? i.blip.sprite : 1, i.blip ? i.blip.color : 0, 24)),
            h("b", null, itTitle(i)), h("span", null, itGroupLabel(i.group)))))
        : h("div", { class: "empty" }, icon("i-crosshair"), group && group.soon ? "Bientôt : cette catégorie se remplira avec ses systèmes (récoltes, banque, fourrière…)." : "Aucune interaction.");

    const main = h("section", { class: "crew-col" },
        h("div", { class: "crew-col-head" }, icon("i-crosshair"), group ? (group.id === "all" ? "Toutes les interactions" : group.label) : "", h("span", { class: "cnt" }, String(shown.length))),
        h("div", { class: "crew-scroll crew-col-body" }, grid),
        h("div", { class: "it-actions" },
            h("button", { class: "btn small", onclick: openCreateInteraction }, icon("i-plus"), "Créer"),
            h("button", { class: `btn small${itState.editMode ? " primary" : ""}`, title: "Affiche en jeu tous les points avec leur nom, leur rayon et leur PNJ", onclick: toggleInteractionEditMode }, icon("i-eye"), itState.editMode ? "Mode édition : activé" : "Mode édition"),
            h("span", { class: "hint-line", style: "margin:0 0 0 auto" }, "Les modifications s'appliquent en jeu tout de suite.")));

    const keep = [...root.querySelectorAll(".crew-scroll")].map((el) => el.scrollTop);
    root.replaceChildren(h("div", { class: "crew-page it-page" }, nav, main, interactionPreview()));
    root.querySelectorAll(".crew-scroll").forEach((el, index) => { if (keep[index]) el.scrollTop = keep[index]; });
    if (itState.map && itEntry()) {
        const e = itEntry();
        itState.map.clear();
        itState.map.icon(e.x, e.y, blipIcon(e.blip ? e.blip.sprite : 1, e.blip ? e.blip.color : 0, 22), { selected: true, label: itTitle(e) });
        itState.map.focus(e.x, e.y, 4);
    }
}

async function toggleInteractionEditMode() {
    const enabled = !itState.editMode;
    const res = await act("interactions.editMode", { enabled }, null);
    if (!res) return;
    itState.editMode = enabled;
    paintInteractions();
}

// ---------- Fiche ----------

function itDraft(entry) {
    if (itState.draft && itState.draft.key === entry.key) return itState.draft;
    const base = { key: entry.key, ped: entry.ped || "", radius: entry.radius, showBlip: entry.showBlip !== false };
    itState.draft = base;
    itState.saved = JSON.stringify(base);
    trackUnsaved("interactions", {
        label: `Interaction ${itTitle(entry)}`,
        isDirty: () => !!itState.draft && JSON.stringify(itState.draft) !== itState.saved,
        save: () => saveInteraction(),
        reset: () => { itState.draft = null; paintInteractions(); },
    });
    return base;
}

async function saveInteraction() {
    const d = itState.draft;
    const entry = itEntry();
    if (!d || !entry) return;
    let res;
    if (entry.source === "shop") {
        res = await act("shops.locationSettings", { locationId: entry.id, ped: d.ped.trim(), radius: Number(d.radius), showBlip: d.showBlip }, "Interaction enregistrée.");
    } else {
        if (d.ped.trim() !== (entry.ped || "")) {
            res = await act("fence.setPed", { id: entry.id, ped: d.ped.trim() }, null);
            if (!res) return;
        }
        res = await act("fence.locationSettings", { id: entry.id, radius: Number(d.radius), showBlip: d.showBlip }, "Interaction enregistrée.");
    }
    if (!res) return;
    untrackUnsaved("interactions");
    itState.draft = null;
    await loadInteractions();
}

function interactionPreview() {
    const entry = itState.sel && itEntry();
    if (!entry) return h("aside", { class: "crew-col it-preview" }, h("div", { class: "crew-col-head" }, icon("i-eye"), "Aperçu"), h("div", { class: "empty" }, icon("i-crosshair"), "Sélectionnez une interaction."));
    const d = itDraft(entry);
    const limits = itState.data.radius || { min: 1, max: 4 };
    if (!itState.map) itState.map = gtaMap();

    const ped = h("input", { class: "input mono", maxlength: "40", placeholder: entry.source === "fence" ? itState.data.fenceDefaultPed : `vide = marqueur au sol (ex. ${itState.data.defaultPed})`, value: d.ped });
    ped.addEventListener("input", () => { d.ped = ped.value; });
    const radiusValue = h("span", { class: "mono it-radius" }, `${Number(d.radius).toFixed(1)} m`);
    const radius = h("input", { type: "range", min: String(limits.min), max: String(limits.max), step: "0.5", value: String(d.radius) });
    radius.addEventListener("input", () => { d.radius = Number(radius.value); radiusValue.textContent = `${d.radius.toFixed(1)} m`; });

    return h("aside", { class: "crew-col it-preview" },
        h("div", { class: "crew-col-head" }, icon("i-eye"), "Aperçu"),
        h("div", { class: "crew-scroll crew-col-body" },
            h("div", { class: "it-head" }, h("span", { class: "it-icon big" }, blipIcon(entry.blip ? entry.blip.sprite : 1, entry.blip ? entry.blip.color : 0, 30)),
                h("span", null, h("b", null, itTitle(entry)), h("span", { class: "badge muted" }, itGroupLabel(entry.group)))),
            h("div", { class: "it-coords mono" }, h("span", null, entry.x.toFixed(0)), h("span", null, entry.y.toFixed(0)), h("span", null, entry.z.toFixed(0))),
            h("div", { class: "it-map" }, itState.map.el),
            h("div", { class: "btn-row it-buttons" },
                h("button", { class: "btn small", onclick: () => itAct(entry, "tp", null, null) }, icon("i-goto"), "Se téléporter"),
                h("button", { class: "btn small ghost", title: "Le point d'interaction passe à votre position", onclick: () => itAct(entry, "move", null, "Point déplacé à votre position.") }, icon("i-crosshair"), "Définir")),
            h("div", { class: "crew-sub" }, "PNJ"),
            crewField("i-player", "Modèle du ped", ped),
            h("button", { class: "btn small wide it-ped", title: entry.source === "fence" ? "Le recelleur se place à votre position" : "Le PNJ se place à votre position et dans votre direction", onclick: () => itAct(entry, "placePed", null, "PNJ placé à votre position.") }, icon("i-user-plus"), "Placer un ped"),
            entry.pedPos ? h("p", { class: "hint-line" }, `PNJ placé en ${entry.pedPos.x.toFixed(0)}, ${entry.pedPos.y.toFixed(0)}.`) : null,
            h("div", { class: "crew-sub" }, "Rayon d'interaction"),
            h("div", { class: "it-range" }, radius, radiusValue),
            h("div", { class: "crew-sub" }, "Affichage minimap"),
            h("div", { class: "mode-list" }, draftToggle(d, "showBlip", "Afficher le blip", entry.source === "fence" ? "Le recelleur est discret : blip caché par défaut." : "Blip du magasin à cet emplacement.")),
            h("button", { class: "btn small danger wide", style: "margin-top:12px", onclick: async () => {
                if (!(await confirmBox(`Supprimer « ${itTitle(entry)} » ?`, "Le point disparaît en jeu (PNJ et blip compris).", "Supprimer", true))) return;
                untrackUnsaved("interactions");
                itState.draft = null;
                itState.sel = null;
                itAct(entry, "delete", null, "Interaction supprimée.");
            } }, icon("i-trash"), "Supprimer l'interaction")));
}

// ---------- Créer ----------

function openCreateInteraction() {
    const shops = itState.data.shops || [];
    const select = h("select", { class: "input" },
        h("optgroup", { label: "Illégal" }, h("option", { value: "fence" }, "Recelleur")),
        h("optgroup", { label: "Magasins, location, grossistes" }, shops.map((s) => h("option", { value: `shop:${s.id}` }, s.label))));
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-plus"), "Créer à ma position");
        submit.addEventListener("click", async () => {
            const value = select.value;
            const res = value === "fence"
                ? await act("fence.addLocation", { ped: itState.data.fenceDefaultPed }, "Recelleur ajouté à votre position.")
                : await act("shops.addLocation", { id: Number(value.slice(5)) }, "Emplacement ajouté à votre position.");
            if (!res) return;
            close();
            await loadInteractions();
        });
        return [
            h("header", null, h("h3", null, "Nouvelle interaction"), h("p", null, "Le point est posé là où vous êtes en jeu. Réglez ensuite son PNJ, son rayon et son blip.")),
            h("div", { class: "body" }, h("div", { class: "field" }, h("label", null, "Type"), select),
                shops.length ? null : h("p", { class: "hint-line" }, "Créez d'abord des magasins dans la tuile Catalogues.")),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
}
