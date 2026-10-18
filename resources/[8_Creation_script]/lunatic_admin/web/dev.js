"use strict";

// ====================================================================
//  lunatic_admin — lot K : page Développeur
//  Resources (démarrer, arrêter, redémarrer), infos entité, affichage de debug.
// ====================================================================

let devDom = null;
let devResources = null;
let devLoadedAt = 0;
let devFilter = { text: "", state: "all" };
let devCapture = null;

const DEV_MODES = [
    { id: "entity", label: "Infos entité", help: "Visez un ped, un véhicule ou un objet : modèle, id réseau, position, santé. E envoie les infos ici." },
    { id: "debug", label: "Affichage de debug", help: "En haut à gauche : position, rue, intérieur, véhicule, nombre d'entités et FPS." },
];

// Infos envoyées par le jeu quand on appuie sur E en mode « Infos entité »
window.addEventListener("message", (event) => {
    const msg = event.data;
    if (!msg || msg.action !== "devEntity" || typeof msg.entity !== "object") return;
    devCapture = msg.entity;
    if (devDom) paintDevCapture();
});

function renderDev() {
    const root = $("view-dev");

    if (!devDom || !root.contains(devDom.resources)) {
        const search = h("input", { placeholder: "Rechercher une resource", value: devFilter.text });
        search.addEventListener("input", () => { devFilter.text = search.value; paintDevResources(); });
        devDom = {
            modes: h("div", { class: "mode-list" }),
            capture: h("div"),
            filters: h("div", { class: "segmented" }),
            count: h("span", { class: "muted mono" }),
            refreshNote: h("div"),
            resources: h("div", { class: "table" }),
        };
        root.replaceChildren(h("div", { class: "content" },
            h("div", { class: "page-head" }, h("div", { class: "grow" },
                h("h1", { class: "page-title" }, "Développeur"),
                h("div", { class: "page-sub" }, "Resources du serveur et outils de diagnostic en jeu"))),
            h("div", { class: "scroll" },
                h("div", { class: "world-grid dev-grid" },
                    h("div", { class: "card" }, h("h3", { class: "card-title" }, "Outils en jeu"), devDom.modes),
                    h("div", { class: "card" }, h("h3", { class: "card-title" }, "Dernière entité capturée"), devDom.capture)),
                h("div", { class: "card", style: "margin-top:16px" },
                    h("div", { class: "card-head dev-head" },
                        h("h3", { class: "card-title" }, "Resources ", devDom.count),
                        h("div", { class: "btn-row" },
                            h("button", { class: "btn small ghost", onclick: () => loadDevResources() }, icon("i-undo"), "Actualiser"),
                            h("button", { class: "btn small", onclick: devRefresh }, icon("i-search"), "Chercher les nouvelles (refresh)"))),
                    devDom.refreshNote,
                    h("div", { class: "toolbar dev-toolbar" }, h("label", { class: "search" }, icon("i-search"), search), devDom.filters),
                    devDom.resources)
            )
        ));
        paintDevResources();
    }

    paintDevModes();
    paintDevCapture();
    if (Date.now() - devLoadedAt > 10000) loadDevResources();
}

function paintDevModes() {
    const modes = (state.dev && state.dev.modes) || {};
    devDom.modes.replaceChildren(...DEV_MODES.map((m) => {
        const on = !!modes[m.id];
        const row = h("div", { class: `perm${on ? " on" : ""}` },
            h("span", { class: "switch" }),
            h("span", { class: "txt" }, h("span", null, m.label), h("code", null, m.help)));
        row.addEventListener("click", async () => {
            const res = await act("dev.toggle", { mode: m.id, enabled: !on }, null);
            if (!res) return;
            state.dev = { ...(state.dev || {}), modes: res.modes || {} };
            paintDevModes();
        });
        return row;
    }));

    const canRefresh = state.dev && state.dev.canRefresh;
    devDom.refreshNote.replaceChildren(canRefresh ? h("span") : h("div", { class: "banner info", style: "margin-bottom:12px" }, icon("i-lock"),
        h("span", null, "« refresh » demande une ligne dans server.cfg (puis redémarrage du serveur) : ",
            h("code", { class: "mono" }, `add_ace resource.${(state.dev && state.dev.resourceName) || "lunatic_admin"} command.refresh allow`))));
}

function paintDevCapture() {
    const e = devCapture;
    if (!e) {
        devDom.capture.replaceChildren(h("p", { class: "hint-line", style: "margin:0" },
            "Activez « Infos entité », visez quelque chose en jeu et appuyez sur E : les infos s'affichent ici."));
        return;
    }
    const coords = `vector3(${e.coords.x.toFixed(2)}, ${e.coords.y.toFixed(2)}, ${e.coords.z.toFixed(2)})`;
    const text = [
        `${e.type} ${e.model || e.hashHex}`, `hash ${e.hash} (${e.hashHex})`, coords, `heading ${e.heading.toFixed(2)}`,
        e.netId !== undefined ? `netId ${e.netId}` : "entité locale", e.plate ? `plaque ${e.plate}` : null,
    ].filter(Boolean).join("\n");
    devDom.capture.replaceChildren(...[
        infoRow("Type", e.type),
        infoRow("Modèle", e.model || "—"),
        infoRow("Hash", `${e.hash} · ${e.hashHex}`),
        infoRow("Position", coords),
        infoRow("Heading", e.heading.toFixed(2)),
        infoRow("Santé", `${e.health}/${e.maxHealth}${e.engine !== undefined ? ` · moteur ${e.engine}` : ""}`),
        infoRow("Réseau", e.netId !== undefined ? `netId ${e.netId}${e.owner ? ` · géré par le joueur ${e.owner}` : ""}` : "Entité locale"),
        e.plate ? infoRow("Plaque", e.plate) : null,
        e.player ? infoRow("Joueur", `ID ${e.player}`) : null,
        h("div", { class: "btn-row", style: "margin-top:12px" },
            h("button", { class: "btn small", onclick: () => devCopy(coords, "Position copiée.") }, icon("i-copy"), "Copier la position"),
            h("button", { class: "btn small ghost", onclick: () => devCopy(text, "Infos copiées.") }, icon("i-copy"), "Copier tout")),
    ].filter(Boolean));
}

// navigator.clipboard est souvent refusé dans les NUI : on passe par une zone de texte temporaire
function devCopy(text, message) {
    const area = h("textarea", { style: "position:fixed;left:-9999px;top:0" });
    area.value = text;
    document.body.append(area);
    area.select();
    let ok = false;
    try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
    area.remove();
    toast(ok ? message : "Copie impossible : sélectionnez le texte à la main.", ok ? "ok" : "error");
}

async function loadDevResources() {
    devLoadedAt = Date.now();
    const res = await nui("action", { action: "dev.resources", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    devResources = res.resources || [];
    if (state.dev) state.dev.canRefresh = res.canRefresh;
    if (devDom) { paintDevResources(); paintDevModes(); }
}

function paintDevResources() {
    const list = devResources;
    const started = list ? list.filter((r) => r.state === "started").length : 0;
    devDom.count.textContent = list ? `${started}/${list.length}` : "";
    devDom.filters.replaceChildren(...segmentedButtons([
        { value: "all", label: "Toutes" }, { value: "started", label: "Démarrées" }, { value: "stopped", label: "Arrêtées" },
    ], devFilter.state, (value) => { devFilter.state = value; paintDevResources(); }));

    if (!list) return devDom.resources.replaceChildren(h("div", { class: "empty small" }, icon("i-code"), "Chargement des resources…"));

    const text = devFilter.text.trim().toLowerCase();
    const rows = list.filter((r) => (!text || r.name.toLowerCase().includes(text))
        && (devFilter.state === "all" || (devFilter.state === "started" ? r.state === "started" : r.state !== "started")));

    devDom.resources.replaceChildren(...(rows.length ? rows.map(resourceRow)
        : [h("div", { class: "empty small" }, icon("i-code"), "Aucune resource ne correspond.")]));
}

const RESOURCE_STATES = { started: "Démarrée", starting: "Démarrage…", stopped: "Arrêtée", stopping: "Arrêt…", uninitialized: "Jamais lancée", unknown: "Inconnu" };

function resourceRow(r) {
    const running = r.state === "started" || r.state === "starting";
    const lock = r.protected ? "Resource protégée : à gérer depuis la console" : null;
    const button = (label, iconName, operation, danger, blocked) =>
        h("button", { class: `btn small${danger ? " danger" : " ghost"}`, disabled: !!blocked, title: blocked, onclick: () => resourceAction(r, operation) }, icon(iconName), label);

    return h("div", { class: "row dev-row" },
        h("span", { class: `status${running ? " on" : ""}`, title: RESOURCE_STATES[r.state] || r.state }),
        h("div", { class: "who" }, h("b", null, r.name),
            h("span", null, [r.version ? `v${r.version}` : null, r.author, r.description].filter(Boolean).join(" · ") || RESOURCE_STATES[r.state] || r.state)),
        r.protected ? h("span", { class: "badge muted" }, icon("i-lock"), "Protégée") : h("span"),
        h("div", { class: "btn-row" },
            running
                ? [button("Redémarrer", "i-undo", "restart", false, lock), button("Arrêter", "i-x", "stop", true, lock)]
                : button("Démarrer", "i-save", "start", false, null))
    );
}

async function resourceAction(r, operation) {
    const labels = { restart: "Redémarrer", stop: "Arrêter", start: "Démarrer" };
    if (operation !== "start") {
        const yes = await confirmBox(`${labels[operation]} « ${r.name} » ?`,
            operation === "stop" ? "Les scripts qui en dépendent peuvent cesser de fonctionner jusqu'à son redémarrage." : "Les joueurs peuvent subir une courte coupure des fonctions de cette resource.",
            labels[operation], operation === "stop");
        if (!yes) return;
    }
    const res = await act("dev.resource", { name: r.name, operation }, `${r.name} : ${labels[operation].toLowerCase()} effectué.`);
    if (res) loadDevResources();
}

async function devRefresh() {
    const res = await act("dev.refresh", {}, "Liste des resources rechargée (refresh).");
    if (res) loadDevResources();
}
