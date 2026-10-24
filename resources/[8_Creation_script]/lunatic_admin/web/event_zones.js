"use strict";

// ====================================================================
//  lunatic_admin — tuile Events, catégorie Zone Events (organisation comme Vision)
//  Liste des events en cartes, puis fiche : résumé et zone sur la carte à gauche, onglets à droite
//  (Informations ; Communication, Items, Points de TP, Props et Tenues dans les parties suivantes).
//  Un event se charge / se décharge depuis sa fiche ; le serveur applique ses règles dans la zone.
// ====================================================================

const zoneState = { version: 0, painted: null, list: null, loadedAt: 0, sel: null, draft: null, saved: "", tab: "info", search: "", map: null, picking: false };

const ZONE_RULES = [
    { key: "noKO", label: "Désactiver coma (KO)", short: "Coma (KO)", hint: "Mort dans la zone : réveil sur place, sans écran d'inconscience ni frais." },
    { key: "godmode", label: "Godmod joueurs", short: "Godmod J.", hint: "Les participants sont invincibles." },
    { key: "vehicleGodmode", label: "Godmod véhicules", short: "Godmod V.", hint: "Le véhicule d'un participant ne prend aucun dégât." },
    { key: "policeCalls", label: "Autoriser les appels police", short: "Police", hint: "Enregistré pour le futur système d'appels (aucun effet pour l'instant)." },
    { key: "respawn", label: "Respawn", short: "Respawn", hint: "Mort dans la zone : respawn au centre de la zone après quelques secondes." },
    { key: "noNeeds", label: "Désactiver faim / soif", short: "Faim / soif", hint: "La faim et la soif ne baissent plus dans la zone." },
];

const ZONE_TABS = [
    { value: "info", label: "Informations" },
    { value: "communication", label: "Communication", soon: true },
    { value: "items", label: "Items", soon: true },
    { value: "tp", label: "Points de TP", soon: true },
    { value: "props", label: "Props", soon: true },
    { value: "outfits", label: "Tenues", soon: true },
];

function zoneDuration(minutes) {
    if (!minutes) return "Illimitée";
    const hours = Math.floor(minutes / 60);
    return hours ? `${hours}h${String(minutes % 60).padStart(2, "0")}` : `${minutes} min`;
}

// La fiche n'est reconstruite que sur demande (repaintZones) : les mises à jour de l'état du panel ne coupent pas la saisie
function renderEventZones(box) {
    // Liste rafraîchie toutes les 10 s (pas pendant l'édition d'une fiche)
    if (!zoneState.list || (zoneState.sel === null && Date.now() - zoneState.loadedAt > 10000)) loadEventZones();
    if (zoneState.painted === zoneState.version && box.firstChild && box.firstChild.dataset.zones) return;
    zoneState.painted = zoneState.version;
    paintEventZones(box);
    if (box.firstChild) box.firstChild.dataset.zones = "1";
}

function repaintZones() {
    zoneState.version += 1;
    if (view === "events") renderEvents();
}

async function loadEventZones() {
    zoneState.loadedAt = Date.now();
    const res = await nui("action", { action: "eventZones.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    zoneState.list = res.events || [];
    if (view === "events" && eventsTab === "zones") repaintZones();
}

async function zoneAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) {
        zoneState.loadedAt = 0;
        await loadEventZones();
    }
    return res;
}

function paintEventZones(box) {
    if (!zoneState.list) return box.replaceChildren(h("div", { class: "empty" }, icon("i-calendar"), "Chargement des events…"));
    if (zoneState.sel !== null) return box.replaceChildren(zoneFiche());

    const search = h("input", { placeholder: "Rechercher…", value: zoneState.search });
    const grid = h("div", { class: "zone-grid" });
    const paintGrid = () => {
        const q = fold(zoneState.search.trim());
        const rows = zoneState.list.filter((e) => !q || fold(e.label).includes(q));
        grid.replaceChildren(
            h("button", { class: "zone-card zone-new", onclick: () => openZone("new") }, icon("i-plus"), h("span", null, "Créer un event")),
            ...rows.map((e) => h("button", { class: `zone-card${e.loaded ? " loaded" : ""}`, onclick: () => openZone(e.id) },
                h("div", { class: "zone-card-head" }, h("b", null, e.label),
                    h("span", { class: `badge ${e.loaded ? "ok" : "muted"}` }, e.loaded ? `Chargé · ${e.players} joueur${e.players > 1 ? "s" : ""}` : "Déchargé")),
                e.description ? h("p", { class: "zone-card-desc" }, e.description) : null,
                h("div", { class: "zone-card-facts" },
                    h("span", null, icon("i-clock"), zoneDuration(e.duration)),
                    h("span", null, icon("i-users"), e.maxPlayers ? `${e.maxPlayers} max` : "Illimité"),
                    h("span", null, icon("i-pin"), e.x != null ? `Zone ${e.radius} m` : "Zone non placée")))));
    };
    search.addEventListener("input", () => { zoneState.search = search.value; paintGrid(); });
    paintGrid();

    box.replaceChildren(h("div", { class: "content" },
        h("div", { class: "crew-col-head" }, icon("i-pin"), "Liste des events", h("span", { class: "cnt" }, String(zoneState.list.length))),
        h("div", { class: "crew-col-pad" }, h("label", { class: "search" }, icon("i-search"), search)),
        h("div", { class: "scroll zone-scroll" }, grid)));
}

function openZone(id) {
    guardUnsaved("events", () => {
        untrackUnsaved("events");
        zoneState.sel = id;
        zoneState.draft = null;
        zoneState.picking = false;
        zoneState.tab = "info";
        repaintZones();
    });
}

function closeZone() {
    guardUnsaved("events", () => {
        untrackUnsaved("events");
        zoneState.sel = null;
        zoneState.draft = null;
        zoneState.picking = false;
        repaintZones();
    });
}

function selectedZone() {
    return zoneState.list ? zoneState.list.find((e) => e.id === zoneState.sel) || null : null;
}

// Brouillon de la fiche, suivi par la barre « non enregistré »
function zoneDraft(event) {
    if (zoneState.draft && zoneState.draft.key === zoneState.sel) return zoneState.draft;
    const rules = {};
    for (const r of ZONE_RULES) rules[r.key] = event ? !!(event.rules && event.rules[r.key]) : false;
    const base = event
        ? { key: event.id, label: event.label, description: event.description, maxPlayers: event.maxPlayers, duration: event.duration, radius: event.radius,
            hour: event.hour ?? null, audio: event.audio || "", volume: event.volume, x: event.x ?? null, y: event.y ?? null, z: event.z ?? null, rules }
        : { key: "new", label: "Nouvel événement", description: "", maxPlayers: 0, duration: 60, radius: 100, hour: null, audio: "", volume: 50, x: null, y: null, z: null, rules };
    zoneState.draft = base;
    zoneState.saved = JSON.stringify(base);
    trackUnsaved("events", {
        label: event ? `Event ${event.label}` : "Nouvel event",
        isDirty: () => !!zoneState.draft && (zoneState.draft.key === "new" || JSON.stringify(zoneState.draft) !== zoneState.saved),
        save: () => saveZone(),
        reset: () => { zoneState.draft = null; repaintZones(); },
    });
    return base;
}

function zoneFiche() {
    const event = selectedZone();
    if (zoneState.sel !== "new" && !event) {
        zoneState.sel = null;
        return h("div", { class: "empty" }, icon("i-calendar"), "Event introuvable.");
    }
    const d = zoneDraft(event);

    const summary = h("div", { class: "zone-summary" });
    const paintSummary = () => summary.replaceChildren(
        h("div", { class: "info-row" }, h("span", null, "Durée"), h("b", null, zoneDuration(d.duration))),
        ...ZONE_RULES.map((r) => h("div", { class: "info-row" }, h("span", null, r.short), h("b", { class: d.rules[r.key] ? "on" : "off" }, d.rules[r.key] ? "Oui" : "Non"))),
        h("div", { class: "info-row" }, h("span", null, "Jour / nuit"), h("b", null, d.hour === null ? "Auto" : `${String(d.hour).padStart(2, "0")}h00`)));
    paintSummary();

    // Zone : carte (clic pour placer), position en jeu, TP
    if (!zoneState.map) zoneState.map = gtaMap();
    const map = zoneState.map;
    const drawZone = () => {
        map.clear();
        if (d.x != null) map.circle(d.x, d.y, d.radius, { color: "#f2c26b", fill: 0.25, label: d.label });
        map.setClick((x, y) => {
            if (!zoneState.picking) return;
            if (!insideGtaMap(x, y)) return toast("Position hors de la carte.", "error");
            d.x = Math.round(x * 10) / 10;
            d.y = Math.round(y * 10) / 10;
            d.z = null;
            zoneState.picking = false;
            repaintZones();
        }, zoneState.picking);
    };
    requestAnimationFrame(() => {
        drawZone();
        if (d.x != null) map.focus(d.x, d.y, d.radius > 300 ? 3 : 4);
        else map.focus(-300, -700, 2);
    });

    const leftCol = h("section", { class: "zone-left crew-scroll" },
        h("div", { class: "card zone-id" },
            h("span", { class: "muted" }, event ? (event.loaded ? `Chargé · ${event.players} joueur(s)` : "Déchargé") : "Aucune bannière"),
            h("b", null, d.label || "Nouvel événement")),
        h("div", { class: "card" }, h("div", { class: "crew-sub" }, "Résumé"), summary),
        h("div", { class: "card zone-map-card" },
            h("div", { class: "crew-sub" }, `Zone de l'event · ${d.radius} m`),
            h("div", { class: "zone-map" }, map.el),
            h("div", { class: "btn-row" },
                h("button", { class: `btn small${zoneState.picking ? " primary" : ""}`, title: "Le prochain clic sur la carte place le centre de la zone", onclick: () => { zoneState.picking = !zoneState.picking; repaintZones(); } }, icon("i-crosshair"), zoneState.picking ? "Cliquez sur la carte" : "Placer"),
                h("button", { class: "btn small ghost", title: "Centre de la zone à votre position en jeu", onclick: async () => {
                    const c = await nui("getCoords").catch(() => null);
                    if (!c || typeof c.x !== "number") return toast("Position indisponible.", "error");
                    d.x = Math.round(c.x * 10) / 10; d.y = Math.round(c.y * 10) / 10; d.z = Math.round(c.z * 10) / 10;
                    repaintZones();
                } }, icon("i-player"), "Ma position"),
                event && event.x != null ? h("button", { class: "btn small ghost", onclick: () => act("eventZones.tp", { id: event.id }, null) }, icon("i-goto"), "TP") : null),
            h("p", { class: "hint-line", style: "margin:0" }, d.x != null ? `Centre : ${d.x.toFixed(0)}, ${d.y.toFixed(0)}` : "Zone pas encore placée : obligatoire pour charger l'event.")));

    const tabs = h("div", { class: "segmented block zone-tabs" }, ZONE_TABS.map((t) => h("button", {
        "aria-checked": String(zoneState.tab === t.value), class: t.soon ? "soon" : null, title: t.soon ? "Prochaine partie" : null,
        onclick: () => { if (!t.soon) { zoneState.tab = t.value; repaintZones(); } },
    }, t.label)));

    const actions = h("div", { class: "zone-actions" },
        event ? h("button", { class: "btn small danger", onclick: async () => {
            const yes = await confirmBox(`Supprimer « ${event.label} » ?`, event.loaded ? "L'event est déchargé et retiré de la base." : "L'event est retiré de la base.", "Supprimer", true);
            if (!yes) return;
            const res = await zoneAct("eventZones.delete", { id: event.id }, "Event supprimé.");
            if (!res) return;
            untrackUnsaved("events");
            zoneState.sel = null;
            zoneState.draft = null;
            repaintZones();
        } }, icon("i-trash"), "Supprimer") : null,
        h("span", { class: "grow" }),
        event ? h("button", { class: "btn small ghost", onclick: async () => {
            const res = await zoneAct("eventZones.duplicate", { id: event.id }, "Event dupliqué.");
            if (res && res.id) openZone(res.id);
        } }, icon("i-copy"), "Dupliquer") : null,
        event ? h("button", { class: `btn small ${event.loaded ? "danger" : "warn"}`, onclick: () => isUnsaved("events")
            ? toast("Enregistrez d'abord vos modifications.", "error")
            : zoneAct("eventZones.load", { id: event.id }, event.loaded ? "Event déchargé : les règles sont retirées." : "Event chargé : la zone est active."),
        }, icon(event.loaded ? "i-x" : "i-sparkle"), event.loaded ? "Décharger l'événement" : "Charger l'événement") : null);

    return h("div", { class: "zone-fiche" },
        h("div", { class: "zone-top" },
            h("button", { class: "btn small ghost sq-btn", title: "Retour à la liste", onclick: closeZone }, icon("i-back")),
            h("b", null, event ? event.label : "Nouvel événement")),
        h("div", { class: "zone-body" },
            leftCol,
            h("section", { class: "zone-right" }, tabs,
                h("div", { class: "crew-scroll zone-pane" }, zoneInfoTab(d, () => { paintSummary(); drawZone(); })),
                actions)));
}

function zoneInfoTab(d, changed) {
    const label = h("input", { class: "input", maxlength: "60", value: d.label });
    label.addEventListener("input", () => { d.label = label.value; });
    const description = h("input", { class: "input", maxlength: "300", placeholder: "Description de l'event", value: d.description });
    description.addEventListener("input", () => { d.description = description.value; });
    const players = h("input", { class: "input mono", type: "number", min: "0", max: "500", value: String(d.maxPlayers) });
    players.addEventListener("input", () => { d.maxPlayers = Number(players.value || 0); });
    const radius = h("input", { class: "input mono", type: "number", min: "10", max: "1000", step: "5", value: String(d.radius) });
    radius.addEventListener("input", () => { d.radius = Number(radius.value || 0); changed(); });

    const durationValue = h("span", { class: "mono zone-value" }, zoneDuration(d.duration));
    const duration = h("input", { type: "range", class: "zone-range", min: "0", max: "480", step: "5", value: String(d.duration) });
    duration.addEventListener("input", () => { d.duration = Number(duration.value); durationValue.textContent = zoneDuration(d.duration); changed(); });

    const rules = ZONE_RULES.map((r) => {
        const row = draftToggle(d.rules, r.key, r.label, r.hint);
        row.addEventListener("click", changed);
        return row;
    });

    const clock = h("select", { class: "input" }, h("option", { value: "", selected: d.hour === null }, "Par défaut (heure du serveur)"),
        ...Array.from({ length: 24 }, (_, hour) => h("option", { value: String(hour), selected: d.hour === hour }, `${String(hour).padStart(2, "0")}h00`)));
    clock.addEventListener("change", () => { d.hour = clock.value === "" ? null : Number(clock.value); changed(); });

    const audio = h("input", { class: "input mono", maxlength: "255", placeholder: "https://…/musique.mp3 (.mp3, .ogg, .wav)", value: d.audio });
    audio.addEventListener("input", () => { d.audio = audio.value.trim(); });
    const volumeValue = h("span", { class: "mono zone-value" }, `${d.volume} %`);
    const volume = h("input", { type: "range", class: "zone-range", min: "0", max: "100", step: "5", value: String(d.volume) });
    volume.addEventListener("input", () => { d.volume = Number(volume.value); volumeValue.textContent = `${d.volume} %`; });

    return h("div", { class: "zone-form" },
        fieldRow("Nom", label),
        fieldRow("Description", description),
        fieldRow("Joueurs max (0 = illimité)", players),
        fieldRow("Durée", h("div", { class: "zone-slider" }, duration, durationValue)),
        fieldRow("Rayon de la zone (m)", radius),
        h("div", { class: "crew-sub" }, "Règles"),
        h("div", { class: "mode-list zone-rules" }, rules),
        fieldRow("Cycle jour / nuit", clock),
        h("div", { class: "crew-sub" }, "Musique d'ambiance"),
        fieldRow("URL audio", audio),
        fieldRow("Volume", h("div", { class: "zone-slider" }, volume, volumeValue)),
        h("p", { class: "hint-line" }, "Les règles s'appliquent aux joueurs qui entrent dans la zone quand l'event est chargé, et sont retirées à la sortie ou au déchargement. Durée 0 : l'event reste chargé jusqu'à ce que vous le déchargiez."));
}

async function saveZone() {
    const d = zoneState.draft;
    if (!d) return;
    const payload = { id: d.key === "new" ? null : d.key, label: d.label.trim(), description: d.description.trim(), maxPlayers: d.maxPlayers, duration: d.duration,
        radius: d.radius, rules: d.rules, hour: d.hour, audio: d.audio, volume: d.volume };
    if (d.x != null) Object.assign(payload, { x: d.x, y: d.y, z: d.z });
    const res = await act("eventZones.save", payload, d.key === "new" ? "Event créé." : "Event enregistré.");
    if (!res) return;
    untrackUnsaved("events");
    zoneState.draft = null;
    zoneState.picking = false;
    if (res.id) zoneState.sel = res.id;
    zoneState.loadedAt = 0;
    await loadEventZones();
}

// Musique d'ambiance de l'event où se trouve le joueur (envoyée par le jeu)
const eventAudio = new Audio();
eventAudio.loop = true;
window.addEventListener("message", (event) => {
    const msg = event.data;
    if (!msg || msg.action !== "eventAudio") return;
    if (!msg.url) {
        eventAudio.pause();
        eventAudio.removeAttribute("src");
        return;
    }
    if (eventAudio.src !== msg.url) eventAudio.src = msg.url;
    eventAudio.volume = Math.max(0, Math.min(1, Number(msg.volume) || 0));
    eventAudio.play().catch(() => {});
});
