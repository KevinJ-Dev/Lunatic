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
    { value: "communication", label: "Communication" },
    { value: "items", label: "Items" },
    { value: "tp", label: "Points de TP" },
    { value: "props", label: "Props" },
    { value: "outfits", label: "Tenues" },
    { value: "vehicles", label: "Véhicules" },
];

const ZONE_VEHICLE_TYPES = [["automobile", "Voiture"], ["bike", "Moto / vélo"], ["boat", "Bateau"], ["heli", "Hélicoptère"], ["plane", "Avion"], ["submarine", "Sous-marin"], ["trailer", "Remorque"]];

// Bibliothèque de props (modèles GTA de base) ; un autre modèle peut être saisi à la main
const ZONE_PROPS = [
    ["Barrières et sécurité", [["prop_barrier_work05", "Barrière de chantier"], ["prop_mp_barrier_02b", "Barrière de course"], ["prop_mp_arrow_barrier_01", "Barrière flèche"], ["prop_trafficdiv_01a", "Séparateur de voie"], ["prop_roadcone02a", "Cône"], ["prop_mp_cone_02", "Grand cône"], ["prop_mb_sandblock_01", "Sacs de sable"], ["prop_barrier_wat_03b", "Barrière béton"]]],
    ["Course et cascade", [["prop_tri_start_banner", "Arche de départ"], ["prop_tri_finish_banner", "Arche d'arrivée"], ["prop_mp_ramp_02", "Rampe"], ["prop_mp_ramp_03", "Grande rampe"], ["prop_skate_flatramp", "Rampe plate"], ["prop_offroad_tyres02", "Pile de pneus"]]],
    ["Fête et scène", [["prop_speaker_06", "Enceinte"], ["prop_portable_hifi_01", "Radio portable"], ["prop_gazebo_02", "Tonnelle"], ["prop_beach_parasol_02", "Parasol"], ["prop_beach_fire", "Feu de camp"], ["prop_bbq_1", "Barbecue"], ["prop_worklight_03b", "Projecteur"], ["prop_food_van_01", "Food truck"]]],
    ["Mobilier", [["prop_table_03", "Table"], ["prop_chair_01a", "Chaise"], ["prop_bench_01a", "Banc"], ["prop_table_para_comb_04", "Table et parasol"], ["prop_portaloo_01a", "Toilettes de chantier"], ["prop_tool_bench02", "Établi"]]],
    ["Décor", [["prop_box_wood02a", "Caisse en bois"], ["prop_container_01a", "Conteneur"], ["prop_haybale_01", "Botte de foin"], ["prop_gold_cont_01", "Chariot de convoi"]]],
];
const zonePropLabel = (model) => { for (const [, list] of ZONE_PROPS) for (const [m, label] of list) if (m === model) return label; return model; };

const POSTER_TYPES = [["news", "News", "#c4242b"], ["media", "Média", "#2c5ec4"], ["event", "Event", "#7a3fd6"], ["ad", "Annonce", "#c99a2e"]];

const emptyZoneContent = () => ({ items: [], outfits: { male: null, female: null }, tp: [], vehicles: [], props: [], communication: emptyPoster() });
const emptyPoster = () => ({ enabled: false, type: "event", title: "", text: "", image: "", gps: true, slots: [] });

// Copie modifiable du contenu enregistré (objets, tenues, points de TP, véhicules)
function zoneContentDraft(content) {
    const c = content ? JSON.parse(JSON.stringify(content)) : emptyZoneContent();
    return { items: c.items || [], outfits: { male: (c.outfits && c.outfits.male) || null, female: (c.outfits && c.outfits.female) || null }, tp: c.tp || [], vehicles: c.vehicles || [],
        props: c.props || [], communication: c.communication || emptyPoster() };
}

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
            hour: event.hour ?? null, audio: event.audio || "", volume: event.volume, x: event.x ?? null, y: event.y ?? null, z: event.z ?? null, rules, content: zoneContentDraft(event.content) }
        : { key: "new", label: "Nouvel événement", description: "", maxPlayers: 0, duration: 60, radius: 100, hour: null, audio: "", volume: 50, x: null, y: null, z: null, rules, content: emptyZoneContent() };
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
        h("div", { class: "info-row" }, h("span", null, "Jour / nuit"), h("b", null, d.hour === null ? "Auto" : `${String(d.hour).padStart(2, "0")}h00`)),
        h("div", { class: "info-row" }, h("span", null, "Contenu"), h("b", null, `${d.content.items.length} obj. · ${d.content.tp.length} TP · ${d.content.vehicles.length} véh. · ${(d.content.outfits.male ? 1 : 0) + (d.content.outfits.female ? 1 : 0)} tenue(s)`)));
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
                h("div", { class: "crew-scroll zone-pane" }, zonePane(d, () => { paintSummary(); drawZone(); })),
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

function zonePane(d, changed) {
    if (zoneState.tab === "items") return zoneItemsTab(d.content);
    if (zoneState.tab === "tp") return zoneTpTab(d.content);
    if (zoneState.tab === "outfits") return zoneOutfitsTab(d.content);
    if (zoneState.tab === "vehicles") return zoneVehiclesTab(d.content);
    if (zoneState.tab === "props") return zonePropsTab(d.content);
    if (zoneState.tab === "communication") return zoneCommunicationTab(d);
    return zoneInfoTab(d, changed);
}

// Position du staff en jeu (x, y, z, cap)
async function zoneMyPosition() {
    const c = await nui("getCoords").catch(() => null);
    if (!c || typeof c.x !== "number") {
        toast("Position indisponible.", "error");
        return null;
    }
    const r = (n, f = 100) => Math.round(n * f) / f;
    return { x: r(c.x), y: r(c.y), z: r(c.z), h: r(c.h || 0, 10) };
}

const zoneCoords = (p) => (p ? `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}` : "non défini");

// ---------- Items : donnés à l'entrée dans la zone, repris à la sortie ----------

function zoneItemsTab(content) {
    if (!catalogItems) {
        loadCatalogItems().then(() => repaintZones());
        return h("div", { class: "empty small" }, "Chargement des objets…");
    }
    const list = h("div", { class: "zone-list" });
    const paint = () => list.replaceChildren(...(content.items.length ? content.items.map((entry, index) => {
        const name = itemPicker(catalogItems, entry.item);
        const count = h("input", { class: "input mono", type: "number", min: "1", max: "1000", value: String(entry.count) });
        const pic = h("span", { class: "zone-item-pic" }, itemImage(entry.item));
        name.addEventListener("input", () => { entry.item = name.value.trim(); });
        name.addEventListener("change", () => pic.replaceChildren(itemImage(entry.item)));
        count.addEventListener("input", () => { entry.count = Number(count.value || 1); });
        return h("div", { class: "zone-item-row" }, pic, name, count,
            h("button", { class: "btn small ghost sq-btn", title: "Retirer", onclick: () => { content.items.splice(index, 1); paint(); } }, icon("i-trash")));
    }) : [h("p", { class: "hint-line" }, "Aucun objet : les participants gardent seulement leur inventaire.")]));
    paint();
    return h("div", { class: "zone-form" },
        h("p", { class: "hint-line" }, "Donnés à chaque joueur qui entre dans la zone, repris à la sortie ou à la fin de l'event. Marqués « [Event] » dans l'inventaire : ils ne peuvent être ni donnés, ni jetés, ni rangés."),
        list,
        h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
            if (content.items.length >= 20) return toast("20 objets au maximum.", "error");
            content.items.push({ item: "", count: 1 });
            paint();
        } }, icon("i-plus"), "Ajouter un objet"));
}

// ---------- Points de TP : départ (marqueur, [E]) vers arrivée ----------

function zoneTpTab(content) {
    const list = h("div", { class: "zone-list" });
    const paint = () => list.replaceChildren(...(content.tp.length ? content.tp.map((point, index) => {
        const label = h("input", { class: "input", maxlength: "40", value: point.label });
        label.addEventListener("input", () => { point.label = label.value; });
        const spot = (key, text) => h("div", { class: "zone-tp-spot" },
            h("span", { class: "muted" }, text), h("b", { class: "mono" }, zoneCoords(point[key])),
            h("button", { class: "btn small ghost", onclick: async () => {
                const p = await zoneMyPosition();
                if (!p) return;
                point[key] = key === "from" ? { x: p.x, y: p.y, z: p.z } : p;
                paint();
            } }, icon("i-player"), "Ma position"));
        return h("div", { class: "card zone-tp" },
            h("div", { class: "zone-tp-head" }, label, h("button", { class: "btn small ghost sq-btn", title: "Retirer", onclick: () => { content.tp.splice(index, 1); paint(); } }, icon("i-trash"))),
            spot("from", "Départ"), spot("to", "Arrivée"));
    }) : [h("p", { class: "hint-line" }, "Aucun point de TP.")]));
    paint();
    return h("div", { class: "zone-form" },
        h("p", { class: "hint-line" }, "Un marqueur apparaît au départ pour les participants : [E] les téléporte à l'arrivée. Placez-vous en jeu puis « Ma position »."),
        list,
        h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
            if (content.tp.length >= 10) return toast("10 points de TP au maximum.", "error");
            content.tp.push({ label: `Point ${content.tp.length + 1}`, from: null, to: null });
            paint();
        } }, icon("i-plus"), "Ajouter un point"));
}

// ---------- Tenues : capturées sur votre personnage ----------

function zoneOutfitsTab(content) {
    const box = h("div", { class: "zone-outfits" });
    const card = (sex, label) => {
        const outfit = content.outfits[sex];
        const worn = outfit ? outfit.components.filter((c) => c.component_id !== 0 && c.component_id !== 2).length + outfit.props.filter((p) => p.drawable >= 0).length : 0;
        return h("div", { class: `card zone-outfit${outfit ? " on" : ""}` },
            h("div", { class: "zone-outfit-icon" }, icon("i-shirt")),
            h("b", null, label),
            h("span", { class: "muted" }, outfit ? `Définie · ${worn} vêtement(s) et accessoire(s)` : "Aucune tenue : le joueur garde la sienne"),
            outfit ? h("button", { class: "btn small ghost", onclick: () => { content.outfits[sex] = null; paint(); } }, icon("i-trash"), "Retirer") : null);
    };
    const paint = () => box.replaceChildren(card("male", "Homme"), card("female", "Femme"));
    paint();
    return h("div", { class: "zone-form" },
        h("p", { class: "hint-line" }, "Appliquée à chaque joueur qui entre dans la zone (selon son personnage, homme ou femme), et rendue à la sortie. Habillez votre personnage en jeu, puis capturez."),
        box,
        h("button", { class: "btn small primary", style: "justify-self:start", onclick: async () => {
            const res = await nui("captureOutfit").catch(() => null);
            if (!res || !res.ok) return toast((res && res.error) || "Capture impossible.", "error");
            content.outfits[res.sex] = { components: res.components, props: res.props };
            paint();
            toast(`Tenue ${res.sex === "male" ? "homme" : "femme"} capturée : enregistrez l'event.`, "ok");
        } }, icon("i-shirt"), "Capturer ma tenue actuelle"));
}

// ---------- Véhicules : posés au chargement, supprimés au déchargement ----------

function zoneVehiclesTab(content) {
    const list = h("div", { class: "zone-list" });
    const paint = () => list.replaceChildren(...(content.vehicles.length ? content.vehicles.map((v, index) => {
        const model = h("input", { class: "input mono", maxlength: "30", placeholder: "modèle (ex. adder)", value: v.model });
        model.addEventListener("input", () => { v.model = model.value.trim().toLowerCase(); });
        const type = h("select", { class: "input" }, ZONE_VEHICLE_TYPES.map(([value, label]) => h("option", { value, selected: v.type === value }, label)));
        type.addEventListener("change", () => { v.type = type.value; });
        return h("div", { class: "zone-vehicle-row" }, icon("i-car"), model, type,
            h("span", { class: "mono muted" }, v.x != null ? `${zoneCoords(v)} · ${Math.round(v.h || 0)}°` : "position non définie"),
            h("button", { class: "btn small ghost", title: "Position et orientation de votre personnage (ou de votre véhicule)", onclick: async () => {
                const p = await zoneMyPosition();
                if (!p) return;
                Object.assign(v, p);
                paint();
            } }, icon("i-player"), "Ma position"),
            h("button", { class: "btn small ghost sq-btn", title: "Retirer", onclick: () => { content.vehicles.splice(index, 1); paint(); } }, icon("i-trash")));
    }) : [h("p", { class: "hint-line" }, "Aucun véhicule.")]));
    paint();
    return h("div", { class: "zone-form" },
        h("p", { class: "hint-line" }, "Posés quand l'event est chargé (plaque EVENT, plein fait), supprimés quand il est déchargé. Enregistrer un event chargé les repose."),
        list,
        h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
            if (content.vehicles.length >= 20) return toast("20 véhicules au maximum.", "error");
            content.vehicles.push({ model: "", type: "automobile", x: null, y: null, z: null, h: 0 });
            paint();
        } }, icon("i-plus"), "Ajouter un véhicule"));
}

// ---------- Props : posés autour de la zone tant que l'event est chargé ----------

function zonePropsTab(content) {
    const placed = h("div", { class: "zone-list" });
    const paintPlaced = () => placed.replaceChildren(...(content.props.length ? content.props.map((p, index) => {
        const num = (key, step) => {
            const input = h("input", { class: "input mono", type: "number", step, value: String(p[key]) });
            input.addEventListener("input", () => { p[key] = Number(input.value || 0); });
            return input;
        };
        return h("div", { class: "zone-prop-row" }, icon("i-box"),
            h("span", { class: "who" }, h("b", null, zonePropLabel(p.model)), h("span", { class: "mono" }, p.model)),
            num("x", "0.1"), num("y", "0.1"), num("z", "0.05"), num("h", "5"),
            h("button", { class: "btn small ghost sq-btn", title: "Retirer", onclick: () => { content.props.splice(index, 1); paintPlaced(); } }, icon("i-trash")));
    }) : [h("p", { class: "hint-line" }, "Aucun prop posé.")]));
    paintPlaced();

    // Ajout : devant votre personnage (1,5 m), au sol, orienté comme vous
    const add = async (model) => {
        if (content.props.length >= 50) return toast("50 props au maximum.", "error");
        const p = await zoneMyPosition();
        if (!p) return;
        const rad = (p.h * Math.PI) / 180;
        const r = (n) => Math.round(n * 100) / 100;
        content.props.push({ model, x: r(p.x - Math.sin(rad) * 1.5), y: r(p.y + Math.cos(rad) * 1.5), z: r(p.z - 0.98), h: p.h });
        paintPlaced();
        toast(`${zonePropLabel(model)} ajouté devant vous : enregistrez l'event.`, "ok");
    };

    const search = h("input", { placeholder: "Rechercher un prop…" });
    const library = h("div", { class: "zone-prop-library" });
    const paintLibrary = () => {
        const q = fold(search.value.trim());
        library.replaceChildren(...ZONE_PROPS.flatMap(([group, list]) => {
            const rows = list.filter(([model, label]) => !q || fold(label).includes(q) || model.includes(q));
            return rows.length ? [h("div", { class: "crew-sub" }, group), h("div", { class: "zone-prop-grid" }, rows.map(([model, label]) =>
                h("button", { class: "zone-prop-cell", title: `${model} : ajouter devant vous`, onclick: () => add(model) }, icon("i-box"), h("span", null, label))))] : [];
        }));
    };
    search.addEventListener("input", paintLibrary);
    paintLibrary();

    const custom = h("input", { class: "input mono", maxlength: "50", placeholder: "autre modèle (ex. prop_flag_france)" });
    return h("div", { class: "zone-form" },
        h("p", { class: "hint-line" }, "Visibles autour de la zone tant que l'event est chargé, retirés au déchargement. Placez-vous en jeu : le prop est posé 1,5 m devant vous, puis ajustez x, y, z et l'orientation."),
        h("div", { class: "crew-sub" }, `Props posés (${content.props.length}/50)`),
        placed,
        h("div", { class: "crew-sub" }, "Bibliothèque de props"),
        h("label", { class: "search" }, icon("i-search"), search),
        library,
        h("div", { class: "zone-custom-prop" }, custom, h("button", { class: "btn small ghost", onclick: () => {
            const model = custom.value.trim().toLowerCase();
            if (!/^[a-z0-9_]+$/.test(model)) return toast("Nom de modèle invalide.", "error");
            add(model);
        } }, icon("i-plus"), "Ajouter ce modèle")));
}

// ---------- Communication : affiche façon Weazel News, créneaux de diffusion ----------

function eventPosterNode(p, preview) {
    const type = POSTER_TYPES.find((t) => t[0] === p.type) || POSTER_TYPES[2];
    const head = h("div", { class: "poster-head" }, h("span", { class: "poster-brand" }, "WEAZEL"), h("span", { class: "poster-tag" }, type[1].toUpperCase()));
    head.style.background = type[2];
    return h("div", { class: `event-poster${preview ? " preview" : ""}` },
        head,
        p.image ? h("img", { class: "poster-media", src: p.image, alt: "", onerror: (e) => { e.target.style.display = "none"; } }) : h("div", { class: "poster-media empty" }, icon("i-image"), "Aucun média"),
        h("div", { class: "poster-body" }, h("b", null, p.title || "Titre de l'event"), p.text ? h("p", null, p.text) : null),
        p.gps ? h("div", { class: "poster-foot" }, h("kbd", null, "Y"), "Itinéraire vers l'event") : null);
}

function zoneCommunicationTab(d) {
    if (!d.content.communication) d.content.communication = emptyPoster();
    const com = d.content.communication;
    const preview = h("div", { class: "zone-poster-preview" });
    const paintPreview = () => preview.replaceChildren(h("div", { class: "crew-sub" }, "Aperçu"), eventPosterNode({ ...com, title: com.title || d.label }, true));
    paintPreview();

    const typeSeg = h("div", { class: "segmented block zone-poster-types" });
    const paintTypes = () => typeSeg.replaceChildren(...segmentedButtons(POSTER_TYPES.map(([value, label]) => ({ value, label })), com.type, (v) => { com.type = v; paintTypes(); paintPreview(); }));
    paintTypes();

    const title = h("input", { class: "input", maxlength: "60", placeholder: d.label, value: com.title });
    title.addEventListener("input", () => { com.title = title.value; paintPreview(); });
    const text = h("textarea", { class: "input textarea", maxlength: "300", placeholder: "Programme, horaires, récompenses…" });
    text.value = com.text;
    text.addEventListener("input", () => { com.text = text.value; paintPreview(); });
    const image = h("input", { class: "input mono", maxlength: "255", placeholder: "https://…/affiche.png", value: com.image });
    image.addEventListener("change", () => { com.image = image.value.trim(); paintPreview(); });

    const slots = h("div", { class: "zone-slots" });
    const slotInput = h("input", { class: "input mono", type: "time" });
    const paintSlots = () => slots.replaceChildren(...(com.slots.length ? com.slots.map((slot, index) => h("span", { class: "zone-slot" }, slot,
        h("button", { class: "btn small ghost sq-btn", title: "Retirer", onclick: () => { com.slots.splice(index, 1); paintSlots(); } }, icon("i-x")))) : [h("span", { class: "hint-line", style: "margin:0" }, "Aucun créneau : diffusion à la demande seulement.")]));
    paintSlots();

    const enabled = draftToggle(com, "enabled", "Diffuser aux créneaux", "Affiche et annonce au tchat envoyées à tous les joueurs aux heures choisies (heure du serveur).");
    const gps = draftToggle(com, "gps", "Itinéraire avec [Y]", "Le joueur qui appuie sur Y pendant l'affichage reçoit un point GPS vers la zone.");
    gps.addEventListener("click", paintPreview);
    const event = selectedZone();

    return h("div", { class: "zone-com" },
        h("div", { class: "zone-form" },
            fieldRow("Type d'annonce", typeSeg),
            fieldRow("Titre", title),
            fieldRow("Texte", text),
            fieldRow("Image (URL)", image),
            h("div", { class: "mode-list zone-rules" }, enabled, gps),
            h("div", { class: "crew-sub" }, `Créneaux de diffusion (${com.slots.length}/5)`),
            slots,
            h("div", { class: "zone-custom-prop" }, slotInput, h("button", { class: "btn small ghost", onclick: () => {
                const v = slotInput.value;
                if (!/^\d\d:\d\d$/.test(v)) return toast("Choisissez une heure.", "error");
                if (com.slots.includes(v)) return toast("Ce créneau existe déjà.", "error");
                if (com.slots.length >= 5) return toast("5 créneaux au maximum.", "error");
                com.slots.push(v);
                com.slots.sort();
                paintSlots();
            } }, icon("i-plus"), "Ajouter")),
            h("button", { class: "btn small warn", style: "justify-self:start", disabled: !event, title: event ? null : "Enregistrez d'abord l'event", onclick: () => {
                if (isUnsaved("events")) return toast("Enregistrez d'abord vos modifications.", "error");
                act("eventZones.broadcast", { id: event.id }, "Affiche diffusée à tous les joueurs.");
            } }, icon("i-sparkle"), "Diffuser maintenant")),
        preview);
}

async function saveZone() {
    const d = zoneState.draft;
    if (!d) return;
    const payload = { id: d.key === "new" ? null : d.key, label: d.label.trim(), description: d.description.trim(), maxPlayers: d.maxPlayers, duration: d.duration,
        radius: d.radius, rules: d.rules, hour: d.hour, audio: d.audio, volume: d.volume, content: d.content };
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

// Affiche d'un event diffusée à tous (en haut à droite, quelques secondes)
let posterTimer = null;
window.addEventListener("message", (event) => {
    const msg = event.data;
    if (!msg || msg.action !== "eventPoster") return;
    const old = document.getElementById("eventPoster");
    if (old) old.remove();
    clearTimeout(posterTimer);
    if (!msg.poster) return;
    const node = eventPosterNode(msg.poster, false);
    node.id = "eventPoster";
    document.body.append(node);
    posterTimer = setTimeout(() => node.remove(), Number(msg.duration) || 15000);
});

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
