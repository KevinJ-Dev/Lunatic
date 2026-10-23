"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, page Braquages
//  Magasins braqués avec un PNJ au comptoir : types à gauche, liste des points au centre,
//  fiche (label, type, modèle du PNJ, position, TP) et mini-carte à droite. Un clic sur la carte place le PNJ.
//  « Cibles détectées » garde l'ancien écran (coffres, vitrines, Fleeca, lieux braqués récemment).
// ====================================================================

const holdupState = { data: null, map: null, fitted: false, focused: null };

async function loadHoldups() {
    const res = await nui("action", { action: "holdups.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    holdupState.data = res;
    if (illegalState.tab === "heists" || illegalState.tab === "missions") paintIllegal();
}

async function holdupAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) await loadHoldups();
    return res;
}

const holdupType = (id) => (holdupState.data ? holdupState.data.types.find((t) => t.id === id) : null) || { id, label: id, short: id };
const holdupCompany = (job) => ((holdupState.data && holdupState.data.companies) || []).find((c) => c.job === job);

function holdupsPage() {
    const d = holdupState.data;
    if (!d) {
        loadHoldups();
        return illegalLoading("Braquages", "i-gem", "Chargement des braquages…");
    }
    const filter = illegalState.holdupType || null;

    // Ancien écran : cibles détectées par leur modèle (coffres, vitrines, Fleeca) et lieux braqués récemment
    if (filter === "detected") {
        return { title: "Cibles détectées", sub: "Coffres des supérettes, vitrines de Vangelico et banques Fleeca, détectés par leur modèle sur toute la carte.", side: [holdupTypesBlock(d, filter)], center: heistsPanel() };
    }

    const sel = illegalState.holdupSel;
    const list = d.points.filter((p) => !filter || p.type === filter);
    const rows = list.map((p) => h("button", { class: `list-row mission-row${p.id === sel ? " active" : ""}${p.active ? "" : " soon"}`, onclick: () => selectHoldup(p.id) },
        h("span", { class: "mission-tag" }, holdupType(p.type).short),
        h("span", { class: "name" }, p.type === "company" && holdupCompany(p.company) ? `${p.label} · ${holdupCompany(p.company).label}` : p.label),
        p.active ? null : h("span", { class: "badge muted" }, "inactif"),
        h("span", { class: "lvl" }, `#${p.id}`)));

    const type = filter ? holdupType(filter) : null;
    return {
        title: type ? `Braquages · ${type.label}` : "Braquages",
        sub: type && type.house
            ? "Maisons à cambrioler : « Définir » devant la porte, tourné vers elle. Outil, horaire, fouille et butin : page Missions → Cambriolage."
            : "Un PNJ au comptoir de chaque point, à menacer avec l'arme demandée. Statut, policiers, gain, XP et limite par jour : page Missions.",
        actions: [
            type && type.house ? h("button", { class: "btn small", title: "Outil, horaire, fouille, réveil du propriétaire, délai, butin", onclick: () => illegalSwitch(() => { illegalState.tab = "missions"; illegalState.missionSel = "burglary"; }) }, icon("i-tool"), "Réglages du cambriolage") : null,
            type && !type.house ? h("button", { class: "btn small", title: "Arme exigée, durée, délai, alarme, résistance du vendeur, butin", onclick: () => openHoldupSettings(type.id) },
                icon("i-tool"), `Réglages ${type.label}`, h("span", { class: "badge muted", style: "margin-left:4px" }, WEAPON_RULES[type.settings ? type.settings.weapon : "any"])) : null,
            h("button", { class: "btn small", title: "Remet les magasins de la carte de base qui manquent", onclick: async () => {
                const res = await holdupAct("holdups.seed", {}, null);
                if (res) toast(res.created ? `${res.created} magasin(s) ajouté(s).` : "Tous les magasins de la carte sont déjà là.", "ok");
            } }, icon("i-sparkle"), "Magasins de la carte"),
        ],
        side: [holdupTypesBlock(d, filter)],
        center: h("div", null,
            type && type.soon ? h("p", { class: "ready-hint" }, icon("i-warn"), h("span", null, `${type.label} : pas encore disponible en jeu. Les points peuvent déjà être placés.`)) : null,
            h("div", { class: "zone-list" }, rows.length ? rows : h("p", { class: "hint-line" }, "Aucun point pour ce type.")),
            h("button", { class: "btn small primary", style: "margin-top:12px", onclick: () => newHoldup(null) }, icon("i-plus"), "Ajouter un braquage")),
        layout: "holdup-layout",
        editor: holdupEditor(d.points.find((p) => p.id === sel)),
        mounted: () => drawHoldups(),
    };
}

function holdupTypesBlock(d, filter) {
    const count = (id) => d.points.filter((p) => !id || p.type === id).length;
    const rows = [{ id: null, label: "Tous" }, ...d.types].map((t) => h("button", { class: `list-row${t.id === filter ? " active" : ""}`, onclick: () => t.id !== filter && illegalSwitch(() => { illegalState.holdupType = t.id; illegalState.holdupSel = null; }) },
        h("span", { class: "name" }, t.label, t.soon ? h("span", { class: "badge muted", style: "margin-left:6px" }, "bientôt") : null), h("span", { class: "cnt" }, String(count(t.id)))));
    rows.push(h("button", { class: `list-row${filter === "detected" ? " active" : ""}`, onclick: () => filter !== "detected" && illegalSwitch(() => { illegalState.holdupType = "detected"; illegalState.holdupSel = null; }) },
        h("span", { class: "name" }, "Cibles détectées"), icon("i-eye")));
    return sideBlock("Type de braquage", null, rows);
}

function selectHoldup(id) {
    if (id === illegalState.holdupSel) return;
    illegalSwitch(() => { illegalState.holdupSel = id; });
}

function newHoldup(position) {
    const filter = illegalState.holdupType;
    const type = holdupType(filter && filter !== "detected" ? filter : "store");
    illegalSwitch(() => {
        illegalState.holdupSel = "new";
        illegalState.prefill = { type: type.id, ped: type.ped || "", interior: "low", ...(position || {}) };
    });
}

const holdupDraft = () => (illegalState.draft && illegalState.draft.kind === "holdup" ? illegalState.draft.data : null);

function holdupEditor(p) {
    if (!p && illegalState.holdupSel !== "new") return h("aside", { class: "item-editor holdup-editor" }, h("div", { class: "empty" }, icon("i-gem"), "Choisissez un braquage, ou cliquez sur la carte pour en placer un."), holdupMapPane());
    const d = illegalDraft("holdup", p ? p.id : "new", p ? `Braquage ${p.label}` : "Nouveau braquage",
        () => (p ? { type: p.type, label: p.label, ped: p.ped, company: p.company || "", interior: p.interior || "low", active: p.active } : { type: "store", label: "", ped: holdupType("store").ped || "", company: "", interior: "low", active: true }),
        saveHoldup);
    const data = holdupState.data;

    const type = h("select", { class: "input" }, data.types.map((t) => h("option", { value: t.id, selected: t.id === d.type }, t.soon ? `${t.label} (pas encore disponible)` : t.label)));
    type.addEventListener("change", () => {
        // Le modèle par défaut suit le type, sauf s'il a été changé à la main
        if (d.ped === holdupType(d.type).ped) d.ped = holdupType(type.value).ped;
        d.type = type.value;
        paintIllegal();
    });
    const company = h("select", { class: "input" }, h("option", { value: "" }, "Choisir…"),
        data.companies.map((c) => h("option", { value: c.job, selected: c.job === d.company }, c.label)));
    company.addEventListener("change", () => { d.company = company.value; });
    const isHouse = holdupType(d.type).house;
    const interior = h("select", { class: "input" }, (data.interiors || []).map((i) => h("option", { value: i.id, selected: i.id === d.interior }, i.label)));
    interior.addEventListener("change", () => { d.interior = interior.value; });

    const placed = d.x != null ? { x: d.x, y: d.y, z: null } : p ? { x: p.x, y: p.y, z: p.z } : null;
    const where = !placed ? "Votre position en jeu à la création (ou cliquez sur la carte)."
        : `${placed.x.toFixed(1)}  ${placed.y.toFixed(1)}  ${placed.z == null || placed.z < -100 ? "hauteur inconnue" : placed.z.toFixed(1)}`;

    return h("aside", { class: "item-editor holdup-editor" },
        h("div", { class: "item-head" }, h("div", { class: "pic" }, icon("i-gem")),
            h("div", { class: "who" }, h("b", null, p ? p.label : "Nouveau braquage"), h("span", { class: "mono" }, p ? `#${p.id} · ${holdupType(p.type).label}` : holdupType(d.type).label))),
        h("div", { class: "holdup-form" },
            fieldRow("Label", draftText(d, "label", { placeholder: "Ex. LTD Grove Street" })),
            fieldRow("Type", type),
            d.type === "company" ? fieldRow("Entreprise", company) : null,
            isHouse ? fieldRow("Intérieur", interior) : fieldRow("Modèle PED", draftText(d, "ped", { class: "input mono", maxlength: "40", placeholder: "mp_m_shopkeep_01" })),
            fieldRow(isHouse ? "Porte" : "Position PED", h("div", { class: "btn-row" },
                p ? h("button", { class: "btn small primary", title: isHouse ? "Place la porte là où vous êtes, tourné vers elle" : "Place le PNJ là où vous êtes, tourné dans votre direction", onclick: () => holdupAct("holdups.move", { id: p.id }, isHouse ? "Porte placée à votre position." : "PNJ placé à votre position.") }, icon("i-crosshair"), "Définir") : null,
                p ? h("button", { class: "btn small", onclick: () => act("holdups.tp", { id: p.id }, null) }, icon("i-goto"), "TP") : null)),
            h("p", { class: "hint-line", style: "margin:0" }, where, d.x != null ? " · placée sur la carte, pensez à « Définir » sur place pour la hauteur et l'orientation" : ""),
            h("div", { class: "mode-list" }, draftToggle(d, "active", "Actif", d.type === "company" ? "Désactivé : cette entreprise ne peut pas être braquée." : isHouse ? "Désactivé : cette maison ne peut pas être cambriolée." : "Désactivé : pas de PNJ ni de braquage ici.")),
            h("div", { class: "item-actions", style: "padding:0;border:0" },
                saveButton(saveHoldup, !p),
                p ? deleteButton(async () => {
                    const yes = await confirmBox(`Supprimer « ${p.label} » ?`, "Le point et son PNJ disparaissent.", "Supprimer", true);
                    if (!yes) return;
                    const res = await act("holdups.delete", { id: p.id }, "Braquage supprimé.");
                    if (!res) return;
                    illegalSaved();
                    illegalState.holdupSel = null;
                    await loadHoldups();
                }) : h("button", { class: "btn small", onclick: () => illegalSwitch(() => { illegalState.holdupSel = null; }) }, "Annuler"))),
        holdupMapPane());
}

// ---------- Réglages d'un type (arme exigée, durée, délai, alarme, résistance, butin) ----------

async function openHoldupSettings(typeId) {
    const t = holdupType(typeId);
    if (!t.settings) return toast("Chargement des braquages…", "info");
    const items = await loadCatalogItems();
    const known = new Set(items.map((i) => i.name));
    const s = JSON.parse(JSON.stringify(t.settings));
    const num = (value, min, max) => h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(value) });
    const weapon = h("select", { class: "input" }, Object.entries(WEAPON_RULES).filter(([id]) => id !== "none").map(([id, label]) => h("option", { value: id, selected: id === s.weapon }, label)));
    const duration = num(s.duration, 5, 180);
    const cooldown = num(s.cooldown, 5, 1440);
    const alert = num(s.alert, 0, 100);
    const resist = num(s.resist, 0, 100);

    const loot = (s.loot || []).map((l) => ({ item: l.item, min: l.min, max: l.max, chance: l.chance }));
    const list = h("div", { class: "ingredient-list" });
    const paint = () => list.replaceChildren(...loot.map((entry, index) => {
        const name = itemPicker(items, entry.item);
        const field = (key, min, max, title) => {
            const input = h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(entry[key]), title });
            input.addEventListener("input", () => { entry[key] = Number(input.value || 0); });
            return input;
        };
        name.addEventListener("input", () => { entry.item = name.value.trim(); });
        return h("div", { class: "ingredient-row loot-row" }, name, field("min", 1, 1000, "Minimum"), field("max", 1, 1000, "Maximum"), field("chance", 1, 100, "Chance (%)"),
            h("button", { class: "btn small ghost", onclick: () => { loot.splice(index, 1); paint(); } }, icon("i-trash")));
    }));
    paint();

    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Enregistrer");
        submit.addEventListener("click", async () => {
            if (loot.some((l) => !known.has(l.item))) return toast("Un objet du butin n'existe pas dans ox_inventory.", "error");
            const res = await holdupAct("holdups.saveSettings", { type: t.id, settings: {
                weapon: weapon.value, duration: Number(duration.value), cooldown: Number(cooldown.value), alert: Number(alert.value), resist: Number(resist.value), loot,
            } }, "Réglages enregistrés.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, `Réglages · Braquage ${t.label}`),
                h("p", null, "Le vendeur se menace avec l'arme demandée (jamais les poings). Statut, policiers, gain, XP, influence et level : page Missions.")),
            h("div", { class: "body event-form" },
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Arme exigée"), weapon),
                    h("div", { class: "field" }, h("label", null, "Durée pour remplir le sac (s)"), duration)),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Délai avant de rebraquer le magasin (min)"), cooldown),
                    h("div", { class: "field" }, h("label", null, "Alarme silencieuse (%)"), alert)),
                h("div", { class: "field" }, h("label", null, "Le vendeur résiste à une arme blanche (%)"), resist),
                h("div", { class: "field" }, h("label", null, "Butin en plus du gain (objet · min · max · chance %)"), list,
                    h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
                        if (loot.length >= 8) return toast("8 objets maximum.", "error");
                        loot.push({ item: "", min: 1, max: 1, chance: 50 });
                        paint();
                    } }, icon("i-plus"), "Ajouter un objet"))),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
}

// ---------- Mini-carte ----------

function holdupMapPane() {
    if (!holdupState.map) holdupState.map = gtaMap();
    return h("div", { class: "holdup-map" }, h("div", { class: "section-head" }, "Localisation"), holdupState.map.el);
}

function drawHoldups() {
    const map = holdupState.map;
    const d = holdupState.data;
    if (!map || !d) return;
    const filter = illegalState.holdupType;
    const sel = illegalState.holdupSel;
    const draft = holdupDraft();
    map.clear();

    for (const p of d.points) {
        if (filter && p.type !== filter && p.id !== sel) continue;
        const editing = p.id === sel && draft && draft.x != null;
        map.point(editing ? draft.x : p.x, editing ? draft.y : p.y,
            { color: p.id === sel ? "#9650ff" : p.active ? "#ffffff" : "#777777", size: p.id === sel ? 8 : 5, label: `${p.label} (#${p.id})` }, () => selectHoldup(p.id));
    }
    if (sel === "new" && draft && draft.x != null) map.point(draft.x, draft.y, { color: "#9650ff", size: 8, label: draft.label || "Nouveau braquage" });

    map.setClick(placeHoldup, true);

    const point = d.points.find((p) => p.id === sel);
    if (!holdupState.fitted) {
        holdupState.fitted = true;
        holdupState.focused = sel;
        requestAnimationFrame(() => (point ? map.focus(point.x, point.y, 5) : map.fit()));
    } else if (holdupState.focused !== sel) {
        holdupState.focused = sel;
        if (point) map.focus(point.x, point.y, 5);
    }
}

// Clic sur la carte : déplace le point choisi, sinon en crée un à cet endroit
function placeHoldup(x, y) {
    if (!insideGtaMap(x, y)) return toast("Position hors de la carte.", "error");
    const position = { x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10 };
    const draft = holdupDraft();
    if (draft) {
        Object.assign(draft, position);
        paintIllegal();
        return;
    }
    newHoldup(position);
}

async function saveHoldup() {
    const draft = illegalState.draft;
    if (!draft || draft.kind !== "holdup") return;
    const creating = draft.key === "new";
    const res = await act("holdups.save", { id: creating ? null : draft.key, ...draft.data },
        creating ? (draft.data.x != null ? "Braquage créé." : "Braquage créé à votre position.") : "Braquage enregistré.");
    if (!res) return;
    illegalSaved();
    if (res.id) illegalState.holdupSel = res.id;
    await loadHoldups();
    paintIllegal();
}
