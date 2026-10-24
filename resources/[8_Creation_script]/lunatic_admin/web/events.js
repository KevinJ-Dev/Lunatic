"use strict";

// ====================================================================
//  lunatic_admin — lot J : page Events (planning d'events)
//  Création, modification, annulation ; rappels et annonces gérés par le serveur.
// ====================================================================

let eventsDom = null;
let eventsList = null;
let eventsLoadedAt = 0;
let eventsReminder = 15;

const EVENT_DATE = new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" });

function eventDate(ts) {
    return EVENT_DATE.format(new Date(ts * 1000)).replace(", ", " à ").replace(/^./, (c) => c.toUpperCase());
}

// « dans 2 h 15 », « dans 3 jours », « il y a 20 min »
function eventDelay(ts) {
    const diff = ts - Date.now() / 1000;
    const abs = Math.abs(diff);
    let text;
    if (abs < 3600) text = `${Math.max(1, Math.round(abs / 60))} min`;
    else if (abs < 86400) text = `${Math.floor(abs / 3600)} h ${String(Math.floor((abs % 3600) / 60)).padStart(2, "0")}`;
    else text = `${Math.round(abs / 86400)} jour${Math.round(abs / 86400) > 1 ? "s" : ""}`;
    return diff >= 0 ? `dans ${text}` : `il y a ${text}`;
}

// Valeur d'un champ datetime-local (heure du PC du staff)
function toLocalInput(ts) {
    const d = new Date(ts * 1000);
    const p = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

// Catégories de la tuile : events à zone (event_zones.js) et planning des annonces
let eventsTab = "zones";

function renderEvents() {
    const root = $("view-events");

    if (!eventsDom || !root.contains(eventsDom.nav)) {
        eventsDom = { nav: h("aside", { class: "sidebar crew-nav events-nav" }), main: h("div", { class: "events-main" }), list: h("div", { class: "scroll" }), sub: h("div", { class: "page-sub" }) };
        eventsDom.planning = h("div", { class: "content" },
            h("div", { class: "page-head" },
                h("div", { class: "grow" }, h("h1", { class: "page-title" }, "Planning"), eventsDom.sub),
                h("button", { class: "btn primary", onclick: () => openEventForm(null) }, icon("i-plus"), "Nouvel event")
            ),
            eventsDom.list
        );
        root.replaceChildren(h("div", { class: "events-page" }, eventsDom.nav, eventsDom.main));
        paintEvents();
    }

    const zonesCount = zoneState.list ? zoneState.list.length : "…";
    const planned = eventsList ? eventsList.filter((e) => e.status === "scheduled" || e.status === "started").length : "…";
    const row = (tab, iconName, label, count) => h("button", { class: `list-row${eventsTab === tab ? " active" : ""}`, onclick: () => eventsTab !== tab && guardUnsaved("events", () => {
        untrackUnsaved("events");
        zoneState.draft = null;
        eventsTab = tab;
        repaintZones();
    }) }, icon(iconName), h("span", { class: "name" }, label), h("span", { class: "cnt" }, String(count)));
    eventsDom.nav.replaceChildren(h("div", { class: "crew-block" },
        h("div", { class: "crew-block-head" }, icon("i-layers"), "Catégories"),
        row("zones", "i-pin", "Zone Events", zonesCount),
        row("planning", "i-calendar", "Planning", planned)));

    if (eventsTab === "planning") {
        if (eventsDom.main.firstChild !== eventsDom.planning) eventsDom.main.replaceChildren(eventsDom.planning);
        if (Date.now() - eventsLoadedAt > 10000) loadEvents();
        return;
    }
    if (!eventsList && Date.now() - eventsLoadedAt > 10000) loadEvents();
    renderEventZones(eventsDom.main);
}

async function loadEvents() {
    eventsLoadedAt = Date.now();
    const res = await nui("action", { action: "events.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    eventsList = res.events || [];
    eventsReminder = res.reminder || eventsReminder;
    if (eventsDom) paintEvents();
    if (view === "events") renderEvents();
}

function paintEvents() {
    if (!eventsList) {
        eventsDom.list.replaceChildren(h("div", { class: "empty" }, icon("i-calendar"), "Chargement du planning…"));
        return;
    }

    const upcoming = eventsList.filter((e) => e.status === "scheduled" || e.status === "started").sort((a, b) => a.startsAt - b.startsAt);
    const past = eventsList.filter((e) => !upcoming.includes(e)).sort((a, b) => b.startsAt - a.startsAt);
    eventsDom.sub.textContent = `${upcoming.length} à venir ou en cours · rappel automatique ${eventsReminder} min avant`;

    eventsDom.list.replaceChildren(...[
        h("div", { class: "section-head" }, "À venir"),
        upcoming.length ? h("div", { class: "event-list" }, upcoming.map(eventCard))
            : h("div", { class: "empty small" }, icon("i-calendar"), "Aucun event programmé. Créez-en un avec « Nouvel event »."),
        past.length ? h("div", { class: "section-head", style: "margin-top:22px" }, "Passés et annulés (30 derniers jours)") : null,
        past.length ? h("div", { class: "event-list past" }, past.map(eventCard)) : null,
    ].filter(Boolean));
}

function eventStatus(e) {
    if (e.status === "cancelled") return h("span", { class: "badge ban" }, "Annulé");
    if (e.status === "started") return h("span", { class: "badge ok" }, "En cours");
    if (e.status === "done") return h("span", { class: "badge muted" }, "Terminé");
    return h("span", { class: "badge jail" }, eventDelay(e.startsAt));
}

function eventCard(e) {
    const actions = [];
    if (e.status === "scheduled") {
        actions.push(h("button", { class: "btn small ghost", onclick: () => openEventForm(e) }, icon("i-edit"), "Modifier"));
        actions.push(h("button", { class: "btn small danger", onclick: () => cancelEvent(e) }, icon("i-x"), "Annuler"));
    } else if (e.status === "started") {
        actions.push(h("button", { class: "btn small", onclick: () => cancelEvent(e) }, icon("i-save"), "Terminer"));
    }

    return h("div", { class: "card event-card" },
        h("div", { class: "event-date" },
            h("b", null, new Date(e.startsAt * 1000).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })),
            h("span", null, new Date(e.startsAt * 1000).toLocaleDateString("fr-FR", { day: "numeric", month: "short" }))),
        h("div", { class: "event-main" },
            h("div", { class: "event-title" }, h("b", null, e.title), eventStatus(e)),
            h("div", { class: "muted" }, eventDate(e.startsAt),
                e.place ? [h("span", { class: "sep" }), e.place] : null,
                e.coords ? [h("span", { class: "sep" }), icon("i-crosshair"), "Point sur la carte"] : null),
            e.description ? h("p", { class: "event-desc" }, e.description) : null,
            h("div", { class: "hint-line" }, `Créé par ${e.createdBy || "?"}`)
        ),
        h("div", { class: "btn-row event-actions" }, actions)
    );
}

async function cancelEvent(e) {
    const started = e.status === "started";
    const yes = await confirmBox(started ? `Terminer « ${e.title} » ?` : `Annuler « ${e.title} » ?`,
        started ? "Le point disparaît de la carte et les joueurs sont remerciés dans le tchat." : "L'annulation est annoncée à tous les joueurs.",
        started ? "Terminer l'event" : "Annuler l'event", !started);
    if (!yes) return;
    const res = await act("events.cancel", { id: e.id }, started ? "Event terminé." : "Event annulé.");
    if (res) loadEvents();
}

// ---------- Formulaire de création / modification ----------

function openEventForm(event) {
    const editing = !!event;
    const defaultStart = Math.ceil((Date.now() / 1000 + 3600) / 900) * 900; // dans 1 h, arrondi au quart d'heure
    let coords = event && event.coords ? { ...event.coords } : null;
    let announce = !editing;

    const title = h("input", { class: "input", maxlength: "80", placeholder: "Ex. Course de rue", value: event ? event.title : "" });
    const when = h("input", { class: "input mono", type: "datetime-local", value: toLocalInput(event ? event.startsAt : defaultStart) });
    const place = h("input", { class: "input", maxlength: "80", placeholder: "Ex. Plage de Vespucci", value: event ? event.place : "" });
    const description = h("textarea", { class: "input textarea", maxlength: "500", placeholder: "Programme, règles, récompenses… (facultatif)" });
    description.value = event ? event.description : "";

    const coordsBox = h("div", { class: "coords-line" });
    const paintCoords = () => coordsBox.replaceChildren(...[
        h("span",{ class: coords ? "mono" : "muted" }, coords ? `${coords.x.toFixed(1)}, ${coords.y.toFixed(1)}, ${coords.z.toFixed(1)}` : "Aucun point sur la carte"),
        h("button", { class: "btn small", onclick: async () => {
            const c = await nui("getCoords").catch(() => null);
            if (!c || typeof c.x !== "number") return toast("Position indisponible.", "error");
            coords = { x: c.x, y: c.y, z: c.z };
            paintCoords();
        } }, icon("i-crosshair"), "Ma position actuelle"),
        coords ? h("button", { class: "btn small ghost", onclick: () => { coords = null; paintCoords(); } }, icon("i-x"), "Retirer") : null,
    ].filter(Boolean));
    paintCoords();

    const announceRow = h("div", { class: `perm${announce ? " on" : ""}` },
        h("span", { class: "switch" }),
        h("span", { class: "txt" }, h("span", null, editing ? "Annoncer la modification" : "Annoncer maintenant"),
            h("code", null, "Message dans le tchat de tous les joueurs (le rappel et le début sont toujours annoncés).")));
    announceRow.addEventListener("click", () => { announce = !announce; announceRow.classList.toggle("on", announce); });

    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon(editing ? "i-save" : "i-plus"), editing ? "Enregistrer" : "Programmer l'event");
        submit.addEventListener("click", async () => {
            const startsAt = Math.floor(new Date(when.value).getTime() / 1000);
            if (!Number.isFinite(startsAt)) return toast("Indiquez une date et une heure.", "error");
            const payload = { title: title.value.trim(), startsAt, place: place.value.trim(), description: description.value.trim(), coords, announce };
            if (editing) payload.id = event.id;
            const res = await act(editing ? "events.update" : "events.create", payload, editing ? "Event modifié." : "Event programmé.");
            if (!res) return;
            close();
            loadEvents();
        });
        return [
            h("header", null, h("h3", null, editing ? "Modifier l'event" : "Nouvel event"),
                h("p", null, "Date et heure de votre PC : chaque joueur les voit à son heure locale.")),
            h("div", { class: "body event-form" },
                h("div", { class: "field" }, h("label", null, "Titre"), title),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Date et heure"), when),
                    h("div", { class: "field" }, h("label", null, "Lieu (nom)"), place)),
                h("div", { class: "field" }, h("label", null, "Point sur la carte (facultatif)"), coordsBox),
                h("div", { class: "field" }, h("label", null, "Description"), description),
                h("div", { class: "mode-list" }, announceRow)
            ),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    title.focus();
}
