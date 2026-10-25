"use strict";

// ====================================================================
//  lunatic_admin — tuile Autres → Récoltes
//  Liste des points à gauche (récoltes, transformations), carte au centre, fiche à droite.
//  Position prise en jeu (« Ma position ») : la hauteur compte pour le [E] des joueurs.
// ====================================================================

const harvestState = { data: null, filter: "all", sel: null, draft: null, saved: "", map: null, focused: null };

const HARVEST_KINDS = { harvest: { label: "Récolte", color: "#5fd3a0", icon: "i-briefcase" }, process: { label: "Transformation", color: "#6bb8f2", icon: "i-tool" } };

function renderHarvest(root) {
    if (harvestState.data && root.querySelector(".harvest-page")) return;
    paintHarvest();
    if (!harvestState.data) loadHarvest();
    if (!catalogItems) loadCatalogItems().then(() => othersState.page === "harvest" && paintHarvest());
}

async function loadHarvest() {
    const res = await nui("action", { action: "harvest.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    harvestState.data = res;
    if (othersState.page === "harvest") paintHarvest();
}

function harvestSelect(sel) {
    guardUnsaved("others", () => {
        untrackUnsaved("others");
        harvestState.draft = null;
        harvestState.sel = sel;
        paintHarvest();
    });
}

const harvestItemLabel = (name) => ((catalogItems || []).find((i) => i.name === name) || {}).label || name || "?";

function harvestSummary(p) {
    if (p.kind === "harvest") return `${p.data.min === p.data.max ? p.data.min : `${p.data.min}-${p.data.max}`} × ${harvestItemLabel(p.data.item)} · ${p.data.duration} s`;
    return `${(p.data.inputs || []).map((i) => `${i.count} ${harvestItemLabel(i.item)}`).join(" + ")} → ${p.data.count} ${harvestItemLabel(p.data.item)}`;
}

function paintHarvest() {
    const root = $("view-others");
    const head = h("div", { class: "driving-head" },
        h("button", { class: "btn small ghost sq-btn", title: "Retour à Autres", onclick: closeOthersPage }, icon("i-back")),
        h("h1", { class: "page-title" }, "Récoltes"));
    if (!harvestState.data) return root.replaceChildren(h("div", { class: "content harvest-page" }, head, h("div", { class: "empty" }, icon("i-briefcase"), "Chargement…")));

    const list = harvestState.data.points.filter((p) => harvestState.filter === "all" || p.kind === harvestState.filter);
    const filters = h("div", { class: "segmented block" }, segmentedButtons([{ value: "all", label: "Tous" }, { value: "harvest", label: "Récoltes" }, { value: "process", label: "Transfo." }], harvestState.filter, (v) => { harvestState.filter = v; paintHarvest(); }));
    const rows = list.map((p) => {
        const dot = h("span", { class: "crew-dot" });
        dot.style.background = HARVEST_KINDS[p.kind].color;
        return h("button", { class: `list-row blip-row${p.id === harvestState.sel ? " active" : ""}`, onclick: () => p.id !== harvestState.sel && harvestSelect(p.id) },
            dot, h("span", { class: "who" }, h("b", null, p.label), h("span", null, `${HARVEST_KINDS[p.kind].label}${p.active ? "" : " · inactif"} · ${harvestSummary(p)}`)));
    });

    const sidebar = h("aside", { class: "sidebar blip-side" },
        h("div", { class: "side-head" }, icon("i-briefcase"), h("h3", null, "Points"), h("span", { class: "cnt" }, String(harvestState.data.points.length))),
        h("div", { class: "side-search" }, filters),
        h("div", { class: "side-scroll" }, rows.length ? rows : h("p", { class: "hint-line", style: "margin:8px" }, "Aucun point.")),
        h("div", { class: "side-foot harvest-new" },
            h("button", { class: "btn primary wide", onclick: () => harvestSelect("new:harvest") }, icon("i-plus"), "Récolte"),
            h("button", { class: "btn wide", onclick: () => harvestSelect("new:process") }, icon("i-plus"), "Transformation")));

    if (!harvestState.map) harvestState.map = gtaMap();
    root.replaceChildren(h("div", { class: "content harvest-page" }, head,
        h("div", { class: "blips-page harvest-body" }, sidebar, h("div", { class: "blip-map" }, harvestState.map.el), harvestEditor())));
    drawHarvest();
}

function drawHarvest() {
    const map = harvestState.map;
    map.clear();
    for (const p of harvestState.data.points) {
        const selected = p.id === harvestState.sel;
        map.point(p.x, p.y, { color: HARVEST_KINDS[p.kind].color, size: selected ? 9 : 6, label: `${p.label} (${HARVEST_KINDS[p.kind].label})` }, () => harvestSelect(p.id));
    }
    const d = harvestState.draft;
    if (d && d.x != null && typeof harvestState.sel === "string") map.point(d.x, d.y, { color: "#f2c26b", size: 9, label: d.label });
    if (harvestState.focused !== harvestState.sel) {
        harvestState.focused = harvestState.sel;
        const p = harvestState.data.points.find((x) => x.id === harvestState.sel);
        requestAnimationFrame(() => (p ? map.focus(p.x, p.y, 5) : map.focus(-300, -700, 2)));
    }
}

function harvestDraft(point, kind) {
    const key = point ? point.id : harvestState.sel;
    if (harvestState.draft && harvestState.draft.key === key) return harvestState.draft;
    const base = point
        ? { key, kind: point.kind, label: point.label, x: point.x, y: point.y, z: point.z, radius: point.radius, active: point.active, blip: point.blip, data: JSON.parse(JSON.stringify(point.data)) }
        : { key, kind, label: kind === "harvest" ? "Nouvelle récolte" : "Nouvelle transformation", x: null, y: null, z: null, radius: 3, active: true, blip: true,
            data: kind === "harvest" ? { item: "", min: 1, max: 2, duration: 5, limit: 0, tool: "", job: "" } : { inputs: [{ item: "", count: 2 }], item: "", count: 1, duration: 8, job: "" } };
    harvestState.draft = base;
    harvestState.saved = JSON.stringify(base);
    trackUnsaved("others", {
        label: point ? `Point ${point.label}` : "Nouveau point",
        isDirty: () => !!harvestState.draft && (typeof harvestState.draft.key === "string" || JSON.stringify(harvestState.draft) !== harvestState.saved),
        save: () => saveHarvest(),
        reset: () => { harvestState.draft = null; paintHarvest(); },
    });
    return base;
}

function harvestEditor() {
    const sel = harvestState.sel;
    const point = typeof sel === "number" ? harvestState.data.points.find((p) => p.id === sel) : null;
    if (sel === null || (typeof sel === "number" && !point)) {
        return h("aside", { class: "item-editor blip-editor" }, h("div", { class: "empty" }, icon("i-briefcase"), "Choisissez un point, ou créez une récolte ou une transformation."));
    }
    const d = harvestDraft(point, point ? point.kind : sel.split(":")[1]);
    const data = d.data;
    const kind = HARVEST_KINDS[d.kind];

    const text = (holder, key, attrs) => {
        const input = h("input", { class: "input", ...attrs, value: String(holder[key] ?? "") });
        input.addEventListener("input", () => { holder[key] = attrs.type === "number" ? Number(input.value || 0) : input.value.trim(); });
        return input;
    };
    const job = h("select", { class: "input" }, h("option", { value: "" }, "Tout le monde"),
        harvestState.data.jobs.map((j) => h("option", { value: j.name, selected: j.name === data.job }, j.label)));
    job.addEventListener("change", () => { data.job = job.value; });

    const where = h("span", { class: "hint-line", style: "margin:0" }, d.x != null ? `${d.x.toFixed(1)}, ${d.y.toFixed(1)}, ${d.z.toFixed(1)}` : "Placez-vous en jeu puis « Ma position ».");
    const position = h("div", { class: "blip-position" },
        h("div", { class: "btn-row" },
            h("button", { class: "btn small", onclick: async () => {
                const c = await nui("getCoords").catch(() => null);
                if (!c || typeof c.x !== "number") return toast("Position indisponible.", "error");
                const r = (n) => Math.round(n * 100) / 100;
                Object.assign(d, { x: r(c.x), y: r(c.y), z: r(c.z) });
                where.textContent = `${d.x.toFixed(1)}, ${d.y.toFixed(1)}, ${d.z.toFixed(1)}`;
                drawHarvest();
            } }, icon("i-player"), "Ma position"),
            point ? h("button", { class: "btn small ghost", onclick: () => act("harvest.tp", { id: point.id }, null) }, icon("i-goto"), "TP") : null),
        where);

    let specific;
    if (d.kind === "harvest") {
        specific = [
            fieldRow("Objet récolté", itemChooserButton(data, "item", { title: "Objet récolté" })),
            fieldRow("Quantité min", text(data, "min", { type: "number", min: "1", class: "input mono" })),
            fieldRow("Quantité max", text(data, "max", { type: "number", min: "1", class: "input mono" })),
            fieldRow("Outil requis", itemChooserButton(data, "tool", { title: "Outil requis", optional: true, placeholder: "Aucun outil" })),
            fieldRow("Limite par heure", text(data, "limit", { type: "number", min: "0", class: "input mono" })),
            h("p", { class: "hint-line" }, "Limite par joueur et par heure (0 = sans limite), multipliée par la « limite farm » des abonnés (tuile Boutique). L'outil n'est pas consommé."),
        ];
    } else {
        const inputs = h("div", { class: "zone-list" });
        const paintInputs = () => inputs.replaceChildren(...data.inputs.map((entry, index) => h("div", { class: "store-line" },
            itemChooserButton(entry, "item", { title: "Objet à transformer" }), text(entry, "count", { type: "number", min: "1", class: "input mono" }),
            h("button", { class: "btn small ghost sq-btn", disabled: data.inputs.length <= 1, onclick: () => { data.inputs.splice(index, 1); paintInputs(); } }, icon("i-trash")))));
        paintInputs();
        specific = [
            h("div", { class: "crew-sub" }, "Objets à transformer"), inputs,
            h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
                if (data.inputs.length >= 6) return toast("6 objets au maximum.", "error");
                data.inputs.push({ item: "", count: 1 });
                paintInputs();
            } }, icon("i-plus"), "Ajouter un objet"),
            h("div", { class: "crew-sub" }, "Résultat"),
            fieldRow("Objet obtenu", itemChooserButton(data, "item", { title: "Objet obtenu" })),
            fieldRow("Quantité", text(data, "count", { type: "number", min: "1", class: "input mono" })),
        ];
    }

    const pic = h("div", { class: "pic" }, icon(kind.icon));
    pic.style.color = kind.color;
    return h("aside", { class: "item-editor blip-editor" },
        h("div", { class: "item-head" }, pic, h("div", { class: "who" }, h("b", null, point ? point.label : d.label), h("span", { class: "mono" }, kind.label))),
        h("div", { class: "item-scroll" },
            fieldRow("Nom", text(d, "label", { maxlength: "40" })),
            fieldRow("Position", position),
            fieldRow("Rayon (m)", text(d, "radius", { type: "number", min: "1", max: "50", step: "0.5", class: "input mono" })),
            fieldRow("Durée (s)", text(data, "duration", { type: "number", min: "1", max: "600", class: "input mono" })),
            fieldRow("Métier requis", job),
            ...specific,
            h("div", { class: "mode-list" },
                draftToggle(d, "active", "Actif", "Inactif : le point disparaît en jeu."),
                draftToggle(d, "blip", "Blip sur la carte", "Icône visible par tous les joueurs."))),
        point ? h("div", { class: "item-actions" }, deleteButton(async () => {
            const yes = await confirmBox(`Supprimer « ${point.label} » ?`, "Le point disparaît en jeu.", "Supprimer", true);
            if (!yes) return;
            const res = await act("harvest.delete", { id: point.id }, "Point supprimé.");
            if (!res) return;
            untrackUnsaved("others");
            harvestState.draft = null;
            harvestState.sel = null;
            await loadHarvest();
        })) : null);
}

async function saveHarvest() {
    const d = harvestState.draft;
    if (!d) return;
    if (d.x == null) return toast("Position manquante : « Ma position » en jeu.", "error");
    const res = await act("harvest.save", { id: typeof d.key === "number" ? d.key : null, kind: d.kind, label: d.label, x: d.x, y: d.y, z: d.z, radius: d.radius, active: d.active, blip: d.blip, data: d.data },
        typeof d.key === "number" ? "Point enregistré." : "Point créé.");
    if (!res) return;
    untrackUnsaved("others");
    harvestState.draft = null;
    if (res.id) harvestState.sel = res.id;
    await loadHarvest();
}
