"use strict";

// ====================================================================
//  lunatic_admin — tuile Autres : Ascenseurs, Heal Items (EMS), Prix custom (mécano)
// ====================================================================

const elevatorState = { data: null, sel: null, draft: null, saved: "" };
const healState = { data: null, draft: null, saved: "" };
const mechanicState = { data: null, draft: null, saved: "", sel: "default", newModel: "" };

function othersHead(title) {
    return h("div", { class: "driving-head" },
        h("button", { class: "btn small ghost sq-btn", title: "Retour à Autres", onclick: closeOthersPage }, icon("i-back")),
        h("h1", { class: "page-title" }, title));
}

async function othersMyPosition() {
    const c = await nui("getCoords").catch(() => null);
    if (!c || typeof c.x !== "number") {
        toast("Position indisponible.", "error");
        return null;
    }
    const r = (n) => Math.round(n * 100) / 100;
    return { x: r(c.x), y: r(c.y), z: r(c.z), h: Math.round((c.h || 0) * 10) / 10 };
}

function othersTrack(label, state, save, repaint) {
    trackUnsaved("others", {
        label,
        isDirty: () => !!state.draft && (state.draft.key === "new" || JSON.stringify(state.draft) !== state.saved),
        save,
        reset: () => { state.draft = null; repaint(); },
    });
}

// ====================================================================
//  Ascenseurs
// ====================================================================

function renderElevators(root) {
    if (elevatorState.data && root.querySelector(".elevators-page")) return;
    paintElevators();
    if (!elevatorState.data) loadElevators();
}

async function loadElevators() {
    const res = await nui("action", { action: "elevators.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    elevatorState.data = res;
    if (othersState.page === "elevators") paintElevators();
}

function elevatorSelect(sel) {
    guardUnsaved("others", () => {
        untrackUnsaved("others");
        elevatorState.draft = null;
        elevatorState.sel = sel;
        paintElevators();
    });
}

function paintElevators() {
    const root = $("view-others");
    if (!elevatorState.data) return root.replaceChildren(h("div", { class: "content elevators-page" }, othersHead("Ascenseurs"), h("div", { class: "empty" }, icon("i-layers"), "Chargement…")));
    const list = elevatorState.data.elevators;
    const sidebar = h("aside", { class: "sidebar blip-side" },
        h("div", { class: "side-head" }, icon("i-layers"), h("h3", null, "Ascenseurs"), h("span", { class: "cnt" }, String(list.length))),
        h("div", { class: "side-scroll" }, list.length ? list.map((e) => h("button", { class: `list-row blip-row${e.id === elevatorState.sel ? " active" : ""}`, onclick: () => e.id !== elevatorState.sel && elevatorSelect(e.id) },
            icon("i-layers"), h("span", { class: "who" }, h("b", null, e.label), h("span", null, `${e.floors.length} étage(s)${e.job ? ` · ${e.job}` : ""}${e.active ? "" : " · inactif"}`)))) : h("p", { class: "hint-line", style: "margin:8px" }, "Aucun ascenseur.")),
        h("div", { class: "side-foot" }, h("button", { class: "btn primary wide", onclick: () => elevatorSelect("new") }, icon("i-plus"), "Créer un ascenseur")));
    root.replaceChildren(h("div", { class: "content elevators-page" }, othersHead("Ascenseurs"), h("div", { class: "others-split" }, sidebar, elevatorEditor())));
}

function elevatorEditor() {
    const sel = elevatorState.sel;
    const elevator = typeof sel === "number" ? elevatorState.data.elevators.find((e) => e.id === sel) : null;
    if (sel === null || (typeof sel === "number" && !elevator)) return h("div", { class: "empty" }, icon("i-layers"), "Choisissez un ascenseur ou créez-en un.");
    if (!elevatorState.draft || elevatorState.draft.key !== (elevator ? elevator.id : "new")) {
        elevatorState.draft = elevator ? { key: elevator.id, label: elevator.label, job: elevator.job, active: elevator.active, floors: JSON.parse(JSON.stringify(elevator.floors)) } : { key: "new", label: "Nouvel ascenseur", job: "", active: true, floors: [] };
        elevatorState.saved = JSON.stringify(elevatorState.draft);
        othersTrack(elevator ? `Ascenseur ${elevator.label}` : "Nouvel ascenseur", elevatorState, saveElevator, paintElevators);
    }
    const d = elevatorState.draft;
    const label = h("input", { class: "input", maxlength: "40", value: d.label });
    label.addEventListener("input", () => { d.label = label.value; });
    const job = h("select", { class: "input" }, h("option", { value: "" }, "Tout le monde"), elevatorState.data.jobs.map((j) => h("option", { value: j.name, selected: j.name === d.job }, j.label)));
    job.addEventListener("change", () => { d.job = job.value; });

    const floors = h("div", { class: "driving-points" });
    const paintFloors = () => floors.replaceChildren(...(d.floors.length ? d.floors.map((f, index) => {
        const name = h("input", { class: "input", maxlength: "30", value: f.label });
        name.addEventListener("input", () => { f.label = name.value; });
        const move = (delta) => {
            const target = index + delta;
            if (target < 0 || target >= d.floors.length) return;
            [d.floors[index], d.floors[target]] = [d.floors[target], d.floors[index]];
            paintFloors();
        };
        return h("div", { class: "elevator-floor" }, h("span", { class: "mono muted" }, String(index + 1)), name,
            h("span", { class: "mono muted" }, `${f.x.toFixed(1)}, ${f.y.toFixed(1)}, ${f.z.toFixed(1)}`),
            h("button", { class: "btn small ghost", title: "Remplacer par votre position", onclick: async () => { const p = await othersMyPosition(); if (p) { Object.assign(f, p); paintFloors(); } } }, icon("i-crosshair")),
            h("button", { class: "btn small ghost", onclick: () => act("others.tp", f, null) }, "TP"),
            h("button", { class: "btn small ghost sq-btn", disabled: index === 0, onclick: () => move(-1) }, "↑"),
            h("button", { class: "btn small ghost sq-btn", disabled: index === d.floors.length - 1, onclick: () => move(1) }, "↓"),
            h("button", { class: "btn small ghost sq-btn", onclick: () => { d.floors.splice(index, 1); paintFloors(); } }, icon("i-x")));
    }) : [h("p", { class: "hint-line" }, "Aucun étage : placez-vous devant chaque porte d'ascenseur en jeu et ajoutez l'étage (2 minimum).")]));
    paintFloors();

    return h("div", { class: "scroll others-editor" },
        h("div", { class: "card" },
            h("div", { class: "driving-grid" }, fieldRow("Nom", label), fieldRow("Accès", job)),
            h("div", { class: "mode-list" }, draftToggle(d, "active", "Actif", "Inactif : l'ascenseur ne fonctionne plus en jeu."))),
        h("div", { class: "card" },
            h("div", { class: "driving-points-head" }, h("b", null, `Étages (${d.floors.length})`),
                h("button", { class: "btn small ghost", onclick: async () => {
                    if (d.floors.length >= 20) return toast("20 étages au maximum.", "error");
                    const p = await othersMyPosition();
                    if (!p) return;
                    d.floors.push({ label: `Étage ${d.floors.length + 1}`, ...p });
                    paintFloors();
                } }, icon("i-plus"), "Ajouter (position actuelle)")),
            floors,
            h("p", { class: "hint-line" }, "En jeu : [E] devant un étage ouvre la liste des étages ; le joueur arrive à la position et dans l'orientation enregistrées.")),
        elevator ? h("div", { class: "btn-row" }, deleteButton(async () => {
            const yes = await confirmBox(`Supprimer « ${elevator.label} » ?`, "L'ascenseur disparaît en jeu.", "Supprimer", true);
            if (!yes) return;
            const res = await act("elevators.delete", { id: elevator.id }, "Ascenseur supprimé.");
            if (!res) return;
            untrackUnsaved("others");
            elevatorState.draft = null;
            elevatorState.sel = null;
            await loadElevators();
        })) : null);
}

async function saveElevator() {
    const d = elevatorState.draft;
    const res = await act("elevators.save", { id: d.key === "new" ? null : d.key, label: d.label, job: d.job, active: d.active, floors: d.floors }, d.key === "new" ? "Ascenseur créé." : "Ascenseur enregistré.");
    if (!res) return;
    untrackUnsaved("others");
    elevatorState.draft = null;
    if (res.id) elevatorState.sel = res.id;
    await loadElevators();
}

// ====================================================================
//  Heal Items (EMS)
// ====================================================================

const HEAL_TARGETS = [["self", "Soi-même"], ["other", "Autre joueur"], ["both", "Les deux"]];

function renderHealItems(root) {
    if (healState.data && root.querySelector(".heal-page")) return;
    paintHealItems();
    if (!healState.data) loadHealItems();
}

async function loadHealItems() {
    const res = await nui("action", { action: "healItems.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    healState.data = res;
    if (othersState.page === "heal") paintHealItems();
}

function paintHealItems() {
    const root = $("view-others");
    if (!healState.data) return root.replaceChildren(h("div", { class: "content heal-page" }, othersHead("Heal Items (EMS)"), h("div", { class: "empty" }, icon("i-heart"), "Chargement…")));
    if (!healState.draft) {
        healState.draft = { key: "heal", items: JSON.parse(JSON.stringify(healState.data.items)) };
        healState.saved = JSON.stringify(healState.draft);
        othersTrack("Heal Items", healState, saveHealItems, paintHealItems);
    }
    const d = healState.draft;
    const list = h("div", { class: "heal-list" });
    const paint = () => list.replaceChildren(...(d.items.length ? d.items.map((entry, index) => {
        const num = (key, max) => {
            const input = h("input", { class: "input mono", type: "number", min: "0", max: String(max), value: String(entry[key]) });
            input.addEventListener("input", () => { entry[key] = Number(input.value || 0); });
            return input;
        };
        const target = h("select", { class: "input" }, HEAL_TARGETS.map(([v, l]) => h("option", { value: v, selected: entry.target === v }, l)));
        target.addEventListener("change", () => { entry.target = target.value; });
        const access = h("select", { class: "input" }, h("option", { value: "all", selected: entry.access === "all" }, "Tout le monde"), h("option", { value: "medic", selected: entry.access === "medic" }, "Médecins (services publics)"),
            healState.data.jobs.map((j) => h("option", { value: j.name, selected: entry.access === j.name }, j.label)));
        access.addEventListener("change", () => { entry.access = access.value; });
        return h("div", { class: "card heal-card" },
            h("div", { class: "heal-card-head" }, itemChooserButton(entry, "item", { title: "Objet de soin" }),
                h("button", { class: "btn small ghost sq-btn", title: "Retirer", onclick: () => { d.items.splice(index, 1); paint(); } }, icon("i-trash"))),
            h("div", { class: "heal-grid" },
                fieldRow("Vie rendue (%)", num("heal", 100)),
                fieldRow("Armure (%)", num("armor", 100)),
                fieldRow("Durée (s)", num("duration", 60)),
                fieldRow("Cible", target),
                fieldRow("Accès", access)),
            h("div", { class: "mode-list heal-toggles" },
                draftToggle(entry, "revive", "Réanime", "Relève un joueur inconscient (cible : autre joueur)."),
                draftToggle(entry, "consume", "Consommé", "L'objet est retiré à l'utilisation.")));
    }) : [h("p", { class: "hint-line" }, "Aucun objet de soin.")]));
    paint();
    root.replaceChildren(h("div", { class: "content heal-page" }, othersHead("Heal Items (EMS)"),
        h("div", { class: "scroll others-editor" },
            h("p", { class: "hint-line" }, "Objets utilisables depuis l'inventaire : soin de soi ou du joueur le plus proche (3 m), réanimation, barre de progression. Le serveur vérifie la distance, l'accès et retire l'objet."),
            list,
            h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
                if (d.items.length >= 30) return toast("30 objets au maximum.", "error");
                d.items.push({ item: "", heal: 25, armor: 0, revive: false, target: "both", duration: 4, access: "all", consume: true });
                paint();
            } }, icon("i-plus"), "Ajouter un objet de soin"))));
}

async function saveHealItems() {
    const res = await act("healItems.save", { items: healState.draft.items }, "Objets de soin enregistrés.");
    if (!res) return;
    untrackUnsaved("others");
    healState.draft = null;
    await loadHealItems();
}

// ====================================================================
//  Prix custom (mécano) : défaut, puis classe GTA, puis modèle
// ====================================================================

const MECH_CLASSES = ["Compactes", "Berlines", "SUV", "Coupés", "Muscle", "Sport classiques", "Sport", "Super", "Motos", "Tout-terrain", "Industriels", "Utilitaires", "Vans", "Vélos", "Bateaux", "Hélicoptères", "Avions", "Service", "Urgence", "Militaires", "Commerciaux", "Trains", "Open wheel"];
const MECH_SECTIONS = [
    ["Performance (prix par niveau)", [["engine", "Moteur"], ["brakes", "Freins"], ["transmission", "Transmission"], ["suspension", "Suspension"], ["turbo", "Turbo"], ["armor", "Blindage"]]],
    ["Global", [["paint1", "Peinture principale"], ["paint2", "Peinture secondaire"], ["pearl", "Nacrage"], ["wheels", "Jantes"], ["windowtint", "Teinte des vitres"], ["neon", "Néons"], ["tyresmoke", "Fumée des pneus"], ["xenon", "Phares xénon"]]],
    ["Esthétique", [["spoiler", "Aileron"], ["frontbumper", "Pare-choc avant"], ["rearbumper", "Pare-choc arrière"], ["skirts", "Bas de caisse"], ["exhaust", "Échappement"], ["rollcage", "Arceau"], ["grille", "Calandre"], ["hood", "Capot"], ["fenders", "Ailes"], ["roof", "Toit"], ["livery", "Livrée"], ["horn", "Klaxon"]]],
    ["Intérieur", [["interior", "Garnitures"], ["dashboard", "Tableau de bord"], ["dial", "Cadrans"], ["seats", "Sièges"], ["steering", "Volant"], ["shifter", "Levier de vitesse"], ["speakers", "Haut-parleurs"]]],
    ["Plaque", [["platecolor", "Couleur de plaque"], ["plateholder", "Support de plaque"]]],
];

function renderMechanic(root) {
    if (mechanicState.data && root.querySelector(".mechanic-page")) return;
    paintMechanic();
    if (!mechanicState.data) loadMechanic();
}

async function loadMechanic() {
    const res = await nui("action", { action: "mechanic.get", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    mechanicState.data = res.prices;
    if (othersState.page === "mechanic") paintMechanic();
}

function paintMechanic() {
    const root = $("view-others");
    if (!mechanicState.data) return root.replaceChildren(h("div", { class: "content mechanic-page" }, othersHead("Tarification mécanique"), h("div", { class: "empty" }, icon("i-tool"), "Chargement…")));
    if (!mechanicState.draft) {
        const p = mechanicState.data;
        mechanicState.draft = { key: "mechanic", default: { ...(p.default || {}) }, classes: JSON.parse(JSON.stringify(p.classes || {})), models: JSON.parse(JSON.stringify(p.models || {})) };
        mechanicState.saved = JSON.stringify(mechanicState.draft);
        othersTrack("Tarification mécanique", mechanicState, saveMechanic, paintMechanic);
    }
    const d = mechanicState.draft;
    const sel = mechanicState.sel;
    const row = (key, label, sub) => h("button", { class: `list-row${sel === key ? " active" : ""}`, onclick: () => { mechanicState.sel = key; paintMechanic(); } }, h("span", { class: "name" }, label), sub ? h("span", { class: "cnt" }, sub) : null);
    const modelInput = h("input", { class: "input mono", placeholder: "modèle (ex. sultan)", value: mechanicState.newModel });
    modelInput.addEventListener("input", () => { mechanicState.newModel = modelInput.value.trim().toLowerCase(); });

    const nav = h("aside", { class: "sidebar crew-nav mechanic-nav" },
        h("div", { class: "crew-block" }, row("default", "Défaut", String(Object.keys(d.default).length))),
        h("div", { class: "crew-block" }, h("div", { class: "crew-block-head" }, icon("i-car"), "Classes GTA"),
            MECH_CLASSES.map((label, id) => row(`class:${id}`, label, d.classes[id] ? String(Object.keys(d.classes[id]).length) : null))),
        h("div", { class: "crew-block" }, h("div", { class: "crew-block-head" }, icon("i-edit"), "Modèles"),
            Object.keys(d.models).sort().map((m) => row(`model:${m}`, m, String(Object.keys(d.models[m]).length))),
            h("div", { class: "mechanic-add" }, modelInput, h("button", { class: "btn small ghost sq-btn", title: "Ajouter un modèle", onclick: () => {
                const m = mechanicState.newModel;
                if (!/^[a-z0-9_]{2,30}$/.test(m)) return toast("Nom de modèle invalide.", "error");
                d.models[m] = d.models[m] || {};
                mechanicState.sel = `model:${m}`;
                mechanicState.newModel = "";
                paintMechanic();
            } }, icon("i-plus")))));

    // Prix de la sélection ; vide = hérité (classe → défaut)
    let target, inherit, title, attach = () => {};
    if (sel === "default") { target = d.default; inherit = () => null; title = "Défaut : prix utilisé quand ni la classe ni le modèle n'en ont"; }
    else if (sel.startsWith("class:")) {
        const id = sel.slice(6);
        target = d.classes[id] || {};
        attach = () => { d.classes[id] = target; };
        inherit = (part) => d.default[part];
        title = `Classe ${MECH_CLASSES[id]} : remplace le défaut`;
    } else {
        const m = sel.slice(6);
        target = d.models[m];
        inherit = (part) => d.default[part];
        title = `Modèle ${m} : remplace la classe et le défaut`;
    }

    const sections = MECH_SECTIONS.map(([label, parts]) => h("div", { class: "card" }, h("div", { class: "crew-sub" }, label),
        h("div", { class: "mechanic-grid" }, parts.map(([part, text]) => {
            const fallback = inherit(part);
            const input = h("input", { class: "input mono", type: "number", min: "0", placeholder: fallback !== null && fallback !== undefined ? `${fallback} (hérité)` : "0", value: target[part] !== undefined ? String(target[part]) : "" });
            input.addEventListener("input", () => {
                attach();
                if (input.value === "") delete target[part];
                else target[part] = Math.max(0, Math.floor(Number(input.value) || 0));
            });
            return h("label", { class: "mechanic-part" }, h("span", null, text), input);
        }))));

    root.replaceChildren(h("div", { class: "content mechanic-page" }, othersHead("Tarification mécanique"),
        h("div", { class: "others-split mechanic-split" }, nav,
            h("div", { class: "scroll others-editor" },
                h("p", { class: "hint-line" }, `${title}. Vide = prix hérité. Enregistré pour le futur script de customisation (exports.lunatic_admin:getMechanicPrice).`),
                sel.startsWith("model:") ? h("button", { class: "btn small danger", style: "justify-self:start", onclick: () => { delete d.models[sel.slice(6)]; mechanicState.sel = "default"; paintMechanic(); } }, icon("i-trash"), "Retirer ce modèle") : null,
                ...sections))));
}

async function saveMechanic() {
    const d = mechanicState.draft;
    const res = await act("mechanic.save", { default: d.default, classes: d.classes, models: d.models }, "Tarifs enregistrés.");
    if (!res) return;
    untrackUnsaved("others");
    mechanicState.draft = null;
    await loadMechanic();
}
