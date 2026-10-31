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
            d.floors.length < 2 || !d.active ? h("div", { class: "banner" }, icon("i-warn"), "Inactif en jeu : il faut l'activer et enregistrer au moins 2 étages.") : null,
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
                h("div", { class: "mechanic-top" }, h("p", { class: "hint-line", style: "margin:0" }, `${title}. Vide = prix hérité. Enregistré pour le futur script de customisation (exports.lunatic_admin:getMechanicPrice).`),
                    h("button", { class: "btn small primary", onclick: prefillMechanic }, icon("i-sparkle"), "Pré-remplir les tarifs")),
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

// ====================================================================
//  Zone AFK : endroit où l'on va avec /afk, sans expulsion pour inactivité
// ====================================================================

const afkState = { data: null, draft: null, saved: "" };

function renderAfkZone(root) {
    if (afkState.data && root.querySelector(".afk-page")) return;
    paintAfkZone();
    if (!afkState.data) loadAfkZone();
}

async function loadAfkZone() {
    const res = await nui("action", { action: "afkZone.get", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    afkState.data = res;
    if (othersState.page === "afk") paintAfkZone();
}

const afkCoords = (p) => (p ? `${p.x.toFixed(2)}, ${p.y.toFixed(2)}, ${p.z.toFixed(2)} · ${Math.round(p.h)}°` : "non défini");

function paintAfkZone() {
    const root = $("view-others");
    if (!afkState.data) return root.replaceChildren(h("div", { class: "content afk-page" }, othersHead("Zone AFK"), h("div", { class: "empty" }, icon("i-clock"), "Chargement…")));
    if (!afkState.draft) {
        afkState.draft = { key: "afk", ...JSON.parse(JSON.stringify(afkState.data.settings)) };
        afkState.draft.point = afkState.draft.point || null;
        afkState.saved = JSON.stringify(afkState.draft);
        othersTrack("Zone AFK", afkState, saveAfkZone, paintAfkZone);
    }
    const d = afkState.draft;
    const num = (key, attrs) => {
        const input = h("input", { class: "input mono", type: "number", ...attrs, value: String(d[key]) });
        input.addEventListener("input", () => { d[key] = Number(input.value || 0); });
        return input;
    };
    const coords = h("span", { class: "mono muted" }, afkCoords(d.point));
    const minutes = afkState.data.afk.minutes;

    root.replaceChildren(h("div", { class: "content afk-page" }, othersHead("Zone AFK"),
        h("div", { class: "scroll others-editor" },
            h("div", { class: "card" },
                h("div", { class: "mode-list" }, draftToggle(d, "enabled", "Zone AFK active", "Les joueurs peuvent s'y mettre ; ils n'y sont jamais expulsés pour inactivité.")),
                h("div", { class: "driving-spot" }, h("b", null, "Point d'arrivée"), coords,
                    h("button", { class: "btn small ghost", onclick: async () => {
                        const p = await othersMyPosition();
                        if (!p) return;
                        d.point = p;
                        coords.textContent = afkCoords(p);
                    } }, icon("i-crosshair"), "Définir position"),
                    h("button", { class: "btn small ghost", onclick: () => (d.point ? act("others.tp", d.point, null) : toast("Position non définie.", "error")) }, icon("i-goto"), "TP")),
                h("div", { class: "driving-grid" }, fieldRow("Rayon de la zone (m)", num("radius", { min: "5", max: "300" })))),
            h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Fonctionnement"),
                h("div", { class: "mode-list heal-toggles" },
                    draftToggle(d, "command", "Commande /afk", "Aller dans la zone, puis /afk à nouveau pour revenir là où l'on était."),
                    draftToggle(d, "autoSend", "Envoyer les inactifs", `Au lieu d'être expulsés, les inactifs (${minutes || "?"} min, réglage anti-AFK de Fonctionnalités) arrivent dans la zone.`),
                    draftToggle(d, "invincible", "Invincible dans la zone", "Personne ne peut blesser un joueur AFK."))),
            h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Récompense"),
                h("div", { class: "driving-grid" },
                    fieldRow(`Montant (${currencySymbol()}, 0 = aucune)`, num("rewardAmount", { min: "0" })),
                    fieldRow("Toutes les (min)", num("rewardMinutes", { min: "1", max: "120" }))),
                h("p", { class: "hint-line" }, "Versée en banque aux joueurs présents dans la zone.")),
            h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => go("features") }, icon("i-tool"), "Réglages anti-AFK (tuile Fonctionnalités)"))));
}

async function saveAfkZone() {
    const { key, ...payload } = afkState.draft;
    const res = await act("afkZone.save", payload, "Zone AFK enregistrée.");
    if (!res) return;
    untrackUnsaved("others");
    afkState.draft = null;
    await loadAfkZone();
}

// ---------- Tarifs mécano : pré-remplissage ----------

const MECH_PRESET = {
    engine: 2500, brakes: 1500, transmission: 2000, suspension: 1200, turbo: 5000, armor: 3500,
    paint1: 500, paint2: 400, pearl: 750, wheels: 900, windowtint: 300, neon: 1200, tyresmoke: 400, xenon: 600,
    spoiler: 800, frontbumper: 700, rearbumper: 700, skirts: 600, exhaust: 500, rollcage: 900, grille: 400, hood: 700, fenders: 600, roof: 600, livery: 1000, horn: 200,
    interior: 400, dashboard: 350, dial: 250, seats: 600, steering: 300, shifter: 200, speakers: 450,
    platecolor: 150, plateholder: 250,
};
// Coefficient par classe GTA (même ordre que MECH_CLASSES) ; 1 = prix du défaut
const MECH_CLASS_FACTORS = [0.8, 0.9, 1.1, 1.1, 1.0, 1.3, 1.5, 2.0, 0.7, 1.0, 1.3, 1.0, 0.9, 0.3, 1.5, 2.5, 3.0, 1.0, 1.2, 2.0, 1.2, 1.0, 2.0];

async function prefillMechanic() {
    const yes = await confirmBox("Pré-remplir les tarifs ?", "Le défaut reçoit des prix de base et chaque classe GTA un prix ajusté (ex. Super ×2, Compactes ×0,8). Les modèles ne changent pas. Rien n'est enregistré avant « Enregistrer ».", "Pré-remplir", false);
    if (!yes) return;
    const d = mechanicState.draft;
    d.default = { ...MECH_PRESET };
    d.classes = {};
    MECH_CLASS_FACTORS.forEach((factor, id) => {
        if (factor === 1) return;
        d.classes[id] = {};
        for (const [part, price] of Object.entries(MECH_PRESET)) d.classes[id][part] = Math.round((price * factor) / 10) * 10;
    });
    paintMechanic();
    paintUnsaved();
}

// ====================================================================
//  Création perso : lieux d'apparition et visuels du créateur de personnage (lunatic_creator)
// ====================================================================

const creatorState = { data: null, draft: null, saved: "" };

function renderCreatorSettings(root) {
    if (creatorState.data && root.querySelector(".creator-page")) return;
    paintCreatorSettings();
    if (!creatorState.data) loadCreatorSettings();
}

async function loadCreatorSettings() {
    const res = await nui("action", { action: "creator.get", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    creatorState.data = res;
    if (othersState.page === "creator") paintCreatorSettings();
}

function paintCreatorSettings() {
    const root = $("view-others");
    if (!creatorState.data) return root.replaceChildren(h("div", { class: "content creator-page" }, othersHead("Création perso"), h("div", { class: "empty" }, icon("i-clock"), "Chargement…")));
    if (!creatorState.draft) {
        creatorState.draft = { key: "creator", ...JSON.parse(JSON.stringify(creatorState.data.settings)) };
        creatorState.draft.spawns = creatorState.draft.spawns && creatorState.draft.spawns.length
            ? creatorState.draft.spawns
            : JSON.parse(JSON.stringify(creatorState.data.defaults || []));
        for (const spawn of creatorState.draft.spawns) if (spawn.enabled === undefined) spawn.enabled = true;
        creatorState.draft.clothesImages = creatorState.draft.clothesImages || { component: "", prop: "" };
        creatorState.saved = JSON.stringify(creatorState.draft);
        othersTrack("Création perso", creatorState, saveCreatorSettings, paintCreatorSettings);
    }
    const d = creatorState.draft;

    const text = (spawn, key, placeholder, max) => {
        const input = h("input", { class: "input", placeholder, maxlength: String(max), value: spawn[key] || "" });
        input.addEventListener("input", () => { spawn[key] = input.value; });
        return input;
    };
    const spawnCard = (spawn, index) => {
        const coords = h("span", { class: "mono muted" }, afkCoords(spawn.x != null ? spawn : null));
        const image = text(spawn, "image", "https://… (facultatif)", 300);
        return h("div", { class: "card creator-spawn" },
            h("div", { class: "creator-spawn-head" }, h("b", null, `Lieu ${index + 1}`),
                h("div", { class: "creator-spawn-toggle" }, draftToggle(spawn, "enabled", "Actif", "Proposé aux joueurs")),
                h("button", { class: "btn small ghost sq-btn", title: "Monter", disabled: index === 0, onclick: () => { d.spawns.splice(index - 1, 0, d.spawns.splice(index, 1)[0]); paintCreatorSettings(); } }, "↑"),
                h("button", { class: "btn small ghost sq-btn", title: "Descendre", disabled: index === d.spawns.length - 1, onclick: () => { d.spawns.splice(index + 1, 0, d.spawns.splice(index, 1)[0]); paintCreatorSettings(); } }, "↓"),
                h("button", { class: "btn small danger", onclick: () => { d.spawns.splice(index, 1); paintCreatorSettings(); } }, icon("i-trash"), "Retirer")),
            h("div", { class: "driving-grid" },
                fieldRow("Groupe (ex. Los Santos)", text(spawn, "group", "Los Santos", 30)),
                fieldRow("Nom du lieu", text(spawn, "label", "Vespucci", 40))),
            fieldRow("Image derrière le nom", imageField(image)),
            h("div", { class: "driving-spot" }, h("b", null, "Point d'apparition"), coords,
                h("button", { class: "btn small ghost", onclick: async () => {
                    const p = await othersMyPosition();
                    if (!p) return;
                    Object.assign(spawn, { x: p.x, y: p.y, z: p.z, h: p.h });
                    coords.textContent = afkCoords(p);
                } }, icon("i-crosshair"), "Définir position"),
                h("button", { class: "btn small ghost", onclick: () => (spawn.x != null ? act("others.tp", { x: spawn.x, y: spawn.y, z: spawn.z, h: spawn.h }, null) : toast("Position non définie.", "error")) }, icon("i-goto"), "TP")));
    };

    root.replaceChildren(h("div", { class: "content creator-page" }, othersHead("Création perso"),
        h("div", { class: "scroll others-editor" },
            h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Visuels du créateur"),
                h("div", { class: "mode-list heal-toggles" },
                    draftToggle(d, "showBanner", "Afficher la bannière", "Image de fond du haut du panneau de création."),
                    draftToggle(d, "showLogo", "Afficher le logo", "Logo à gauche du titre « Nouveau personnage ».")),
                h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => go("images") }, icon("i-image"), "Changer la bannière et le logo (tuile Images, catégorie Création perso)")),
            h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Images des vêtements"),
                h("p", { class: "hint-line", style: "margin:0" }, "Images de Lunatic Clothes Renderer (option « Numéros du jeu »), hébergées en https ou copiées dans lunatic_creator/html/clothes/. Repères : {sex} (male / female), {id} (numéro GTA), {drawable}, {texture}. Vide : numéro du style."),
                h("div", { class: "driving-grid" },
                    fieldRow("Vêtements", text(d.clothesImages, "component", "https://…/clothes/{sex}/{id}/{drawable}.png", 300)),
                    fieldRow("Accessoires", text(d.clothesImages, "prop", "https://…/props/{sex}/{id}/{drawable}.png", 300)))),
            h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Miniatures des styles"),
                h("p", { class: "hint-line", style: "margin:0" }, "Votre personnage prend tour à tour chaque coupe, barbe, sourcils, maquillage… le temps d'un portrait (une dizaine de minutes, restez immobile). Ensuite : « ensure lunatic_creator » pour que les joueurs reçoivent les images."),
                h("div", { class: "btn-row" },
                    h("button", { class: "btn small primary", onclick: () => creatorPhotos("male") }, icon("i-image"), "Photographier (homme)"),
                    h("button", { class: "btn small primary", onclick: () => creatorPhotos("female") }, icon("i-image"), "Photographier (femme)"))),
            h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Lieux d'apparition"),
                h("p", { class: "hint-line", style: "margin:0" }, "Les lieux actifs sont proposés à la fin de la création, regroupés par groupe, dans cet ordre. Placez-vous en jeu puis « Définir position »."),
                h("div", { class: "btn-row" },
                    h("button", { class: "btn small primary", onclick: () => {
                        if (d.spawns.length >= 20) return toast("20 lieux au maximum.", "error");
                        d.spawns.push({ group: d.spawns.length ? d.spawns[d.spawns.length - 1].group : "Los Santos", label: "", image: "", enabled: true });
                        paintCreatorSettings();
                    } }, icon("i-plus"), "Ajouter un lieu"))),
            d.spawns.map(spawnCard))));
}

async function creatorPhotos(sex) {
    const yes = await confirmBox("Lancer la séance photo ?", "Votre personnage change de modèle pendant les photos puis reprend son apparence. Fermez le panel et ne bougez pas jusqu'à la fin (compteur en bas de l'écran).", "Lancer", false);
    if (yes) act("creator.photos", { sex }, "Séance photo lancée : fermez le panel.");
}

async function saveCreatorSettings() {
    const { key, ...payload } = creatorState.draft;
    const res = await act("creator.save", payload, "Création perso enregistrée.");
    if (!res) return;
    untrackUnsaved("others");
    creatorState.draft = null;
    await loadCreatorSettings();
}

// ====================================================================
//  Listes de points : hôpitaux et guichets de documents (lunatic_gameplay), agences bancaires (lunatic_bank). Même page :
//  points de la config affichés d'office, actifs ou non, position prise en jeu, ordre, PNJ éventuel.
// ====================================================================

const POINT_PAGES = {
    hospitals: {
        title: "Hôpitaux", item: "Hôpital", placeholder: "Pillbox Hill", spot: "Point de réveil", toggle: "Peut accueillir les réveils",
        hint: "Après l'inconscience, le joueur se réveille à l'hôpital actif le plus proche de l'endroit où il est tombé (frais et règles : Fonctionnalités → Gameplay → Mort & Respawn).",
    },
    offices: {
        title: "Guichets de documents", item: "Guichet", placeholder: "Commissariat de Mission Row", spot: "Guichet ([E])", toggle: "Ouvert aux joueurs", ped: true,
        hint: "Les joueurs y retirent leur carte d'identité (première gratuite, puis duplicata) et leur permis. Réglages : Fonctionnalités → Carte d'identité.",
    },
    banks: {
        title: "Banques", item: "Agence", placeholder: "Fleeca Legion Square", spot: "Guichet ([E])", toggle: "Ouverte aux joueurs", saved: "Agences bancaires enregistrées.",
        hint: "Au guichet, les joueurs consultent leur compte (IBAN, historique, analyse), retirent, déposent et font des virements. Blips des agences : tuile Blips.",
    },
    jobcenters: {
        title: "Job Center", item: "Job Center", placeholder: "Job Center", spot: "Comptoir ([E])", toggle: "Ouvert aux joueurs", saved: "Job Centers enregistrés.",
        hint: "Les joueurs y choisissent un métier d'intérim (Mineur, Éboueur, Pilote…). Images et logos des métiers : tuile Images, catégorie Job Center. Tenues : en jeu, au comptoir (staff).",
    },
};
const pointStates = { hospitals: { data: null, draft: null, saved: "" }, offices: { data: null, draft: null, saved: "" }, banks: { data: null, draft: null, saved: "" }, jobcenters: { data: null, draft: null, saved: "" } };

function renderPoints(root, kind) {
    if (pointStates[kind].data && root.querySelector(`.points-page-${kind}`)) return;
    paintPoints(kind);
    if (!pointStates[kind].data) loadPoints(kind);
}

const renderHospitals = (root) => renderPoints(root, "hospitals");
const renderOffices = (root) => renderPoints(root, "offices");
const renderBanks = (root) => renderPoints(root, "banks");
const renderJobCenters = (root) => renderPoints(root, "jobcenters");

async function loadPoints(kind) {
    const res = await nui("action", { action: `${kind}.get`, payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    pointStates[kind].data = res;
    if (othersState.page === kind) paintPoints(kind);
}

function paintPoints(kind) {
    const page = POINT_PAGES[kind];
    const st = pointStates[kind];
    const root = $("view-others");
    const pageClass = `content points-page-${kind}`;
    if (!st.data) return root.replaceChildren(h("div", { class: pageClass }, othersHead(page.title), h("div", { class: "empty" }, icon("i-clock"), "Chargement…")));
    if (!st.draft) {
        const list = st.data.points && st.data.points.length ? st.data.points : st.data.defaults || [];
        st.draft = { key: kind, points: JSON.parse(JSON.stringify(list)) };
        for (const point of st.draft.points) if (point.enabled === undefined) point.enabled = true;
        st.saved = JSON.stringify(st.draft);
        othersTrack(page.title, st, () => savePoints(kind), () => paintPoints(kind));
    }
    const d = st.draft;

    const card = (point, index) => {
        const name = h("input", { class: "input", maxlength: "40", placeholder: page.placeholder, value: point.label || "" });
        name.addEventListener("input", () => { point.label = name.value; });
        const ped = h("input", { class: "input mono", maxlength: "40", placeholder: "s_m_y_cop_01 (vide : aucun)", value: point.ped || "" });
        ped.addEventListener("input", () => { point.ped = ped.value.trim(); });
        const coords = h("span", { class: "mono muted" }, afkCoords(point.x != null ? point : null));
        const move = (delta) => { d.points.splice(index + delta, 0, d.points.splice(index, 1)[0]); paintPoints(kind); };
        return h("div", { class: "card creator-spawn" },
            h("div", { class: "creator-spawn-head" }, h("b", null, `${page.item} ${index + 1}`),
                h("div", { class: "creator-spawn-toggle" }, draftToggle(point, "enabled", "Actif", page.toggle)),
                h("button", { class: "btn small ghost sq-btn", title: "Monter", disabled: index === 0, onclick: () => move(-1) }, "↑"),
                h("button", { class: "btn small ghost sq-btn", title: "Descendre", disabled: index === d.points.length - 1, onclick: () => move(1) }, "↓"),
                h("button", { class: "btn small danger", onclick: () => { d.points.splice(index, 1); paintPoints(kind); } }, icon("i-trash"), "Retirer")),
            fieldRow("Nom", name),
            page.ped ? fieldRow("PNJ au guichet", ped) : null,
            h("div", { class: "driving-spot" }, h("b", null, page.spot), coords,
                h("button", { class: "btn small ghost", onclick: async () => {
                    const p = await othersMyPosition();
                    if (!p) return;
                    Object.assign(point, { x: p.x, y: p.y, z: p.z, h: p.h });
                    coords.textContent = afkCoords(p);
                } }, icon("i-crosshair"), "Définir position"),
                h("button", { class: "btn small ghost", onclick: () => (point.x != null ? act("others.tp", { x: point.x, y: point.y, z: point.z, h: point.h }, null) : toast("Position non définie.", "error")) }, icon("i-goto"), "TP")));
    };

    root.replaceChildren(h("div", { class: pageClass }, othersHead(page.title),
        h("div", { class: "scroll others-editor" },
            h("div", { class: "card" },
                h("p", { class: "hint-line", style: "margin:0" }, page.hint),
                h("div", { class: "btn-row" }, h("button", { class: "btn small primary", onclick: () => {
                    if (d.points.length >= 20) return toast("20 au maximum.", "error");
                    d.points.push({ label: "", enabled: true });
                    paintPoints(kind);
                } }, icon("i-plus"), `Ajouter (${page.item.toLowerCase()})`))),
            d.points.map(card))));
}

// ====================================================================
//  Métiers d'intérim (lunatic_interim) : un bloc par métier, réglages communs + dépôt et sortie du véhicule
// ====================================================================

const interimState = { data: null, draft: null, saved: "" };

function renderInterim(root) {
    if (interimState.data && root.querySelector(".interim-page")) return;
    paintInterim();
    if (!interimState.data) loadInterim();
}

async function loadInterim() {
    const res = await nui("action", { action: "interim.get", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    interimState.data = res;
    if (othersState.page === "interim") paintInterim();
}

function paintInterim() {
    const st = interimState;
    const root = $("view-others");
    if (!st.data) return root.replaceChildren(h("div", { class: "content interim-page" }, othersHead("Métiers d'intérim"), h("div", { class: "empty" }, icon("i-clock"), "Chargement…")));
    if (!st.data.jobs.length) return root.replaceChildren(h("div", { class: "content interim-page" }, othersHead("Métiers d'intérim"), h("div", { class: "empty" }, icon("i-warn"), "lunatic_interim n'est pas démarré.")));
    if (!st.draft) {
        const jobs = {};
        for (const job of st.data.jobs) {
            const saved = (st.data.settings || {})[job.id] || {};
            jobs[job.id] = {
                enabled: saved.enabled !== false, salary: saved.salary ?? job.salary, stops: saved.stops ?? job.stops, vehicle: saved.vehicle ?? job.vehicle ?? "",
                depot: saved.depot || null, spawn: saved.spawn || null,
            };
        }
        st.draft = { key: "interim", jobs };
        st.saved = JSON.stringify(st.draft);
        othersTrack("Métiers d'intérim", st, saveInterim, paintInterim);
    }
    const d = st.draft;

    const spot = (entry, key, label) => {
        const coords = h("span", { class: "mono muted" }, afkCoords(entry[key]));
        return h("div", { class: "driving-spot" }, h("b", null, label), coords,
            h("button", { class: "btn small ghost", onclick: async () => {
                const p = await othersMyPosition();
                if (!p) return;
                entry[key] = p;
                coords.textContent = afkCoords(p);
            } }, icon("i-crosshair"), "Définir position"),
            h("button", { class: "btn small ghost", onclick: () => (entry[key] ? act("others.tp", entry[key], null) : toast("Position non définie.", "error")) }, icon("i-goto"), "TP"));
    };

    const number = (entry, key, min, max) => {
        const input = h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(entry[key]) });
        input.addEventListener("input", () => { entry[key] = Math.floor(Number(input.value) || 0); });
        return input;
    };

    const card = (job) => {
        const entry = d.jobs[job.id];
        const vehicle = h("input", { class: "input mono", maxlength: "40", placeholder: job.vehicle || "modèle", value: entry.vehicle || "" });
        vehicle.addEventListener("input", () => { entry.vehicle = vehicle.value.trim(); });
        const ready = job.kind === "route";
        return h("div", { class: "card creator-spawn" },
            h("div", { class: "creator-spawn-head" }, h("b", null, `${job.label} · ${job.company}`),
                ready ? null : h("span", { class: "badge muted" }, "missions à venir"),
                h("div", { class: "creator-spawn-toggle" }, draftToggle(entry, "enabled", "Actif", "Proposé au Job Center"))),
            h("div", { class: "event-form-row" },
                fieldRow(`Salaire par mission (${currencySymbol()})`, number(entry, "salary", 0, 100000)),
                ready ? fieldRow("Arrêts par tournée", number(entry, "stops", 1, 15)) : null,
                ready ? fieldRow("Véhicule de service", vehicle) : null),
            ready ? spot(entry, "depot", "Dépôt ([E] : commencer / terminer)") : null,
            ready ? spot(entry, "spawn", "Sortie du véhicule (dans le sens de départ)") : null);
    };

    root.replaceChildren(h("div", { class: "content interim-page" }, othersHead("Métiers d'intérim"),
        h("div", { class: "scroll others-editor" },
            h("div", { class: "card" }, h("p", { class: "hint-line", style: "margin:0" },
                "Les joueurs prennent ces métiers au Job Center (page Job Center). Tournées (Livreur, Facteur, Éboueur) : placez-vous au dépôt puis « Définir position », et de même pour la sortie du véhicule. Les arrêts sont tirés au hasard sur les routes de la carte ; la paie va sur le compte bancaire à la fin de la tournée.")),
            st.data.jobs.map(card))));
}

async function saveInterim() {
    const res = await act("interim.save", { jobs: interimState.draft.jobs }, "Métiers d'intérim enregistrés.");
    if (!res) return;
    untrackUnsaved("others");
    interimState.draft = null;
    interimState.data = null;
    await loadInterim();
}

async function savePoints(kind) {
    const st = pointStates[kind];
    const res = await act(`${kind}.save`, { points: st.draft.points }, POINT_PAGES[kind].saved || `${POINT_PAGES[kind].title} enregistrés.`);
    if (!res) return;
    untrackUnsaved("others");
    st.draft = null;
    await loadPoints(kind);
}
