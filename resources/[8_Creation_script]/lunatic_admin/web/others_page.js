"use strict";

// ====================================================================
//  lunatic_admin — tuile Autres (configuration étendue, comme Vision)
//  Grille de sous-pages : Auto-école (ici), Récoltes, Ascenseurs, Heal Items (EMS), Prix custom (mécano) à venir ;
//  Logs et Zone AFK renvoient vers leurs tuiles.
// ====================================================================

const othersState = { page: null };
const drivingState = { data: null, draft: null, saved: "", exam: "car", questions: false };

const OTHERS_TILES = [
    { id: "logs", label: "Logs", icon: "i-list", go: "logs", show: () => can("logs.view") || can("logs.chat") },
    { id: "driving", label: "Auto-école", icon: "i-car", show: () => can("others.manage") },
    { id: "harvest", label: "Récoltes", icon: "i-briefcase", show: () => can("others.manage") },
    { id: "elevators", label: "Ascenseurs", icon: "i-layers", show: () => can("others.manage") },
    { id: "heal", label: "Heal Items (EMS)", icon: "i-heart", show: () => can("others.manage") },
    { id: "mechanic", label: "Prix custom (mécano)", icon: "i-tool", show: () => can("others.manage") },
    { id: "afk", label: "Zone AFK", icon: "i-clock", show: () => can("others.manage") },
    { id: "creator", label: "Création perso", icon: "i-player", show: () => can("others.manage") },
    { id: "hospitals", label: "Hôpitaux", icon: "i-heart", show: () => can("others.manage") },
    { id: "offices", label: "Guichets de documents", icon: "i-book", show: () => can("others.manage") },
    { id: "banks", label: "Banques", icon: "i-bank", show: () => can("others.manage") },
    { id: "clothing", label: "Magasins de vêtements", icon: "i-shirt", show: () => can("others.manage") },
];

const DRIVING_EXAMS = [["car", "Voiture"], ["bike", "Moto"], ["truck", "Camion"], ["plane", "Avion"], ["heli", "Hélicoptère"], ["boat", "Bateau"]];

function renderOthers() {
    const root = $("view-others");
    if (othersState.page === "harvest") return renderHarvest(root);
    if (othersState.page === "elevators") return renderElevators(root);
    if (othersState.page === "heal") return renderHealItems(root);
    if (othersState.page === "mechanic") return renderMechanic(root);
    if (othersState.page === "afk") return renderAfkZone(root);
    if (othersState.page === "creator") return renderCreatorSettings(root);
    if (othersState.page === "hospitals") return renderHospitals(root);
    if (othersState.page === "offices") return renderOffices(root);
    if (othersState.page === "banks") return renderBanks(root);
    if (othersState.page === "clothing") return renderClothing(root);
    if (othersState.page === "driving") {
        if (drivingState.data && root.querySelector(".driving-page")) return;
        paintDriving();
        if (!drivingState.data) loadDriving();
        return;
    }
    root.replaceChildren(h("div", { class: "content" },
        h("div", { class: "page-head" }, h("div", { class: "grow" }, h("h1", { class: "page-title" }, "Autres"), h("div", { class: "page-sub" }, "Configuration étendue"))),
        h("div", { class: "scroll" }, h("div", { class: "tiles others-tiles" }, OTHERS_TILES.filter((t) => t.show()).map((t) => h("button", {
            class: `tile${t.soon ? " soon" : ""}`,
            onclick: () => {
                if (t.soon) return toast(`${t.label} : arrive dans la prochaine partie.`, "info");
                if (t.go) return go(t.go);
                othersState.page = t.id;
                renderOthers();
            },
        }, icon(t.icon), h("span", null, t.label), t.soon ? h("small", { class: "tile-count" }, "bientôt") : null))))));
}

function closeOthersPage() {
    guardUnsaved("others", () => {
        untrackUnsaved("others");
        drivingState.draft = null;
        harvestState.draft = null;
        elevatorState.draft = null;
        healState.draft = null;
        mechanicState.draft = null;
        afkState.draft = null;
        creatorState.draft = null;
        pointStates.hospitals.draft = null;
        pointStates.offices.draft = null;
        pointStates.banks.draft = null;
        clothingState.draft = null;
        othersState.page = null;
        renderOthers();
    });
}

// ---------- Auto-école ----------

async function loadDriving() {
    const res = await nui("action", { action: "driving.info", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    drivingState.data = res;
    if (!isUnsaved("others")) drivingState.draft = null;
    if (othersState.page === "driving") paintDriving();
}

function drivingDraft() {
    if (drivingState.draft) return drivingState.draft;
    const d = JSON.parse(JSON.stringify(drivingState.data.settings));
    for (const [id] of DRIVING_EXAMS) d.exams[id].spawn = d.exams[id].spawn || null;
    drivingState.draft = d;
    drivingState.saved = JSON.stringify(d);
    trackUnsaved("others", {
        label: "Auto-école",
        isDirty: () => !!drivingState.draft && JSON.stringify(drivingState.draft) !== drivingState.saved,
        save: () => saveDriving(),
        reset: () => { drivingState.draft = null; paintDriving(); },
    });
    return d;
}

async function saveDriving() {
    const res = await act("driving.save", drivingState.draft, "Auto-école enregistrée.");
    if (!res) return;
    untrackUnsaved("others");
    drivingState.draft = null;
    await loadDriving();
}

const drivingCoords = (p) => (p ? `${p.x.toFixed(2)}, ${p.y.toFixed(2)}, ${p.z.toFixed(2)}${p.h !== undefined ? ` · ${Math.round(p.h)}°` : ""}` : "non définie");

async function drivingMyPosition() {
    const c = await nui("getCoords").catch(() => null);
    if (!c || typeof c.x !== "number") {
        toast("Position indisponible.", "error");
        return null;
    }
    const r = (n) => Math.round(n * 100) / 100;
    return { x: r(c.x), y: r(c.y), z: r(c.z), h: Math.round((c.h || 0) * 10) / 10 };
}

// Ligne « position » : coordonnées, Définir (position actuelle), TP
function drivingSpot(label, holder, key) {
    const coords = h("span", { class: "mono muted" }, drivingCoords(holder[key]));
    return h("div", { class: "driving-spot" }, h("b", null, label), coords,
        h("button", { class: "btn small ghost", onclick: async () => {
            const p = await drivingMyPosition();
            if (!p) return;
            holder[key] = p;
            coords.textContent = drivingCoords(p);
        } }, icon("i-crosshair"), "Définir position"),
        h("button", { class: "btn small ghost", onclick: () => holder[key] ? act("driving.tp", holder[key], null) : toast("Position non définie.", "error") }, icon("i-goto"), "TP"));
}

function drivingNumber(holder, key, attrs) {
    const input = h("input", { class: "input mono", type: "number", ...attrs, value: String(holder[key] ?? 0) });
    input.addEventListener("input", () => { holder[key] = Number(input.value || 0); });
    return input;
}

function paintDriving() {
    const root = $("view-others");
    const head = h("div", { class: "driving-head" },
        h("button", { class: "btn small ghost sq-btn", title: "Retour à Autres", onclick: closeOthersPage }, icon("i-back")),
        h("h1", { class: "page-title" }, "Auto-école"));
    if (!drivingState.data) return root.replaceChildren(h("div", { class: "content driving-page" }, head, h("div", { class: "empty" }, icon("i-car"), "Chargement…")));
    const d = drivingDraft();

    const ped = h("input", { class: "input mono", maxlength: "40", value: d.ped });
    ped.addEventListener("input", () => { d.ped = ped.value.trim(); });

    const general = h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Général"),
        h("div", { class: "driving-grid" },
            fieldRow("Erreurs max", drivingNumber(d, "maxErrors", { min: "0", max: "20" })),
            fieldRow("Santé moteur min", drivingNumber(d, "minEngine", { min: "0", max: "1000", step: "50" })),
            fieldRow("PNJ (modèle)", ped),
            h("div", { class: "mode-list" }, draftToggle(d, "blip", "Blip sur la carte", "Icône de l'auto-école visible par tous."),
                draftToggle(d, "majorFail", "Faute grave = échec", "Accident violent, piéton percuté, sortie du véhicule en marche ou grand excès de vitesse : examen échoué aussitôt."))),
        drivingSpot("Point auto-école (permis)", d, "school"),
        drivingSpot("Téléportation finale", d, "finalTp"),
        h("p", { class: "hint-line" }, "Erreurs : excès de vitesse, choc, STOP non marqué. L'examen échoue au-delà des erreurs max ou si le moteur passe sous la santé minimale (sur 1000)."));

    root.replaceChildren(h("div", { class: "content driving-page" }, head,
        h("div", { class: "scroll driving-body" }, general, drivingTheoryCard(d), drivingExamCard(d))));
}

// ---------- Code de la route ----------

function drivingTheoryCard(d) {
    const t = d.theory;
    const list = h("div", { class: "driving-questions" });
    const paintList = () => list.replaceChildren(...t.questions.map((q, index) => {
        const text = h("input", { class: "input", maxlength: "200", value: q.q });
        text.addEventListener("input", () => { q.q = text.value; });
        const answers = q.a.map((answer, i) => {
            const input = h("input", { class: "input", maxlength: "100", value: answer });
            input.addEventListener("input", () => { q.a[i] = input.value; });
            const good = h("button", { class: `driving-good${q.c === i + 1 ? " on" : ""}`, title: "Bonne réponse", onclick: () => { q.c = i + 1; paintList(); } }, "✓");
            return h("div", { class: "driving-answer" }, good, input,
                h("button", { class: "btn small ghost sq-btn", title: "Retirer la réponse", disabled: q.a.length <= 2, onclick: () => { q.a.splice(i, 1); if (q.c > q.a.length) q.c = 1; paintList(); } }, icon("i-x")));
        });
        return h("div", { class: "driving-question" },
            h("div", { class: "driving-question-head" }, h("span", { class: "mono muted" }, `${index + 1}.`), text,
                h("button", { class: "btn small ghost sq-btn", title: "Supprimer la question", disabled: t.questions.length <= 1, onclick: () => { t.questions.splice(index, 1); paintList(); } }, icon("i-trash"))),
            ...answers,
            q.a.length < 4 ? h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => { q.a.push(""); paintList(); } }, icon("i-plus"), "Réponse") : null);
    }));
    paintList();

    const details = h("details", { class: "blip-fold driving-fold", open: drivingState.questions || null },
        h("summary", null, icon("i-list"), `Questions (${t.questions.length})`), list,
        h("button", { class: "btn small ghost", style: "margin-top:8px", onclick: () => {
            if (t.questions.length >= 60) return toast("60 questions au maximum.", "error");
            t.questions.push({ q: "", a: ["", ""], c: 1 });
            paintList();
        } }, icon("i-plus"), "Ajouter une question"));
    details.addEventListener("toggle", () => { drivingState.questions = details.open; });

    return h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Code de la route"),
        h("div", { class: "driving-grid" },
            fieldRow(`Prix (${currencySymbol()})`, drivingNumber(t, "price", { min: "0" })),
            fieldRow("Questions posées", drivingNumber(t, "count", { min: "1", max: "60" })),
            fieldRow("Bonnes réponses min", drivingNumber(t, "pass", { min: "1", max: "60" }))),
        h("p", { class: "hint-line" }, "Le code est obligatoire avant tout examen pratique. Les questions sont tirées au hasard parmi la liste."),
        details);
}

// ---------- Examens pratiques ----------

function drivingExamCard(d) {
    const id = drivingState.exam;
    const exam = d.exams[id];
    const tabs = h("div", { class: "segmented" }, segmentedButtons(DRIVING_EXAMS.map(([value, label]) => ({ value, label: d.exams[value].active ? label : `${label} (off)` })), id, (v) => { drivingState.exam = v; paintDriving(); }));

    const license = h("select", { class: "input" }, drivingState.data.licenses.map((l) => h("option", { value: l.type, selected: l.type === exam.license }, `${l.label} (${l.type})`)));
    license.addEventListener("change", () => { exam.license = license.value; });
    const model = h("input", { class: "input mono", maxlength: "30", value: exam.model });
    model.addEventListener("input", () => { exam.model = model.value.trim().toLowerCase(); });

    const points = h("div", { class: "driving-points" });
    const title = h("b", null);
    const paintPoints = () => {
        title.textContent = `Points de trajet (${exam.points.length})`;
        points.replaceChildren(...(exam.points.length ? exam.points.map((p, index) => {
            const speed = h("input", { class: "input mono", type: "number", min: "10", max: "500", title: "Vitesse autorisée (km/h)", value: String(p.speed) });
            speed.addEventListener("input", () => { p.speed = Number(speed.value || exam.speed); });
            const move = (delta) => {
                const target = index + delta;
                if (target < 0 || target >= exam.points.length) return;
                [exam.points[index], exam.points[target]] = [exam.points[target], exam.points[index]];
                paintPoints();
            };
            const stop = h("button", { class: `btn small ${p.stop ? "stop-on" : "ghost"}`, title: "Point STOP : arrêt complet obligatoire (sinon faute)", onclick: () => { p.stop = !p.stop; paintPoints(); } }, "STOP");
            return h("div", { class: "driving-point" }, h("span", { class: "mono muted" }, String(index + 1)), h("span", { class: "mono" }, drivingCoords({ x: p.x, y: p.y, z: p.z })),
                speed, h("span", { class: "muted" }, "km/h"), stop,
                h("button", { class: "btn small ghost", onclick: () => act("driving.tp", p, null) }, "TP"),
                h("button", { class: "btn small ghost sq-btn", title: "Monter", disabled: index === 0, onclick: () => move(-1) }, "↑"),
                h("button", { class: "btn small ghost sq-btn", title: "Descendre", disabled: index === exam.points.length - 1, onclick: () => move(1) }, "↓"),
                h("button", { class: "btn small ghost sq-btn", title: "Supprimer", onclick: () => { exam.points.splice(index, 1); paintPoints(); } }, icon("i-x")));
        }) : [h("p", { class: "hint-line" }, "Aucun point : conduisez le trajet en jeu et ajoutez un point à chaque étape (2 minimum).")]));
    };
    paintPoints();

    return h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Type d'examen"), tabs,
        h("div", { class: "driving-exam" },
            h("div", { class: "mode-list" }, draftToggle(exam, "active", `Examen ${exam.label} ouvert`, "Proposé au PNJ quand le spawn et 2 points de trajet au moins sont définis.")),
            drivingSpot("Spawn véhicule", exam, "spawn"),
            h("div", { class: "driving-grid" },
                fieldRow("Permis délivré", license),
                fieldRow(`Prix (${currencySymbol()})`, drivingNumber(exam, "price", { min: "0" })),
                fieldRow("Véhicule (modèle)", model),
                fieldRow("Vitesse par défaut (km/h)", drivingNumber(exam, "speed", { min: "10", max: "500" }))),
            h("div", { class: "driving-points-head" }, title,
                h("button", { class: "btn small ghost", onclick: async () => {
                    if (exam.points.length >= 60) return toast("60 points au maximum.", "error");
                    const p = await drivingMyPosition();
                    if (!p) return;
                    exam.points.push({ x: p.x, y: p.y, z: p.z, speed: exam.speed });
                    paintPoints();
                } }, icon("i-plus"), "Ajouter (position actuelle)")),
            points));
}
