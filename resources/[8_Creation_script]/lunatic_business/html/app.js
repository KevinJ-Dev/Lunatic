"use strict";

// Location de véhicules : catalogue de l'agence, aperçu 3D (géré par le jeu), durée par périodes, paiement.
// Vente de véhicules (data.sale, Vespucci Bike) : même vitrine, caractéristiques du modèle, achat sans durée.
// Le serveur revérifie tout au moment de louer (véhicule, périodes, solde).

const $ = (id) => document.getElementById(id);
const inGame = typeof GetParentResourceName === "function";
const resource = inGame ? GetParentResourceName() : "lunatic_business";

function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
        if (value === null || value === undefined || value === false) continue;
        if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
        else if (key === "class") el.className = value;
        else el.setAttribute(key, value === true ? "" : value);
    }
    for (const child of children.flat(Infinity)) {
        if (child === null || child === undefined || child === false) continue;
        el.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return el;
}

async function nui(name, payload) {
    if (!inGame) return {};
    try {
        const res = await fetch(`https://${resource}/${name}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) });
        return await res.json();
    } catch {
        return {};
    }
}

function toast(text) {
    const el = $("toast");
    el.textContent = text;
    el.classList.add("on");
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => el.classList.remove("on"), 3500);
}

let data = null;
const state = { category: null, selected: null, periods: 1, account: "money", cam: "orbit", auto: false, primary: -1, secondary: -1 };

// Couleurs proposées à la vente (numéro GTA, nom, teinte approchée pour la pastille)
const SALE_COLORS = [
    [0, "Noir", "#0d1116"], [1, "Graphite", "#1c1d21"], [4, "Argent", "#8f969c"], [111, "Blanc", "#f4f4f0"],
    [27, "Rouge", "#c00e1a"], [28, "Rouge vif", "#da1918"], [38, "Orange", "#f78616"], [89, "Jaune", "#fbe212"],
    [53, "Vert", "#155c2d"], [92, "Vert citron", "#98d223"], [61, "Bleu nuit", "#222e46"], [64, "Bleu", "#47578f"],
    [70, "Bleu vif", "#0b9cf1"], [71, "Violet", "#2f2d52"], [135, "Rose", "#f21f99"], [96, "Marron", "#3f2a1e"],
];

const money = (n) => `${Math.round(n).toLocaleString("fr-FR")} ${data.currency || "$"}`;
const minutes = (m) => (m >= 60 ? `${Math.floor(m / 60)} h${m % 60 ? ` ${String(m % 60).padStart(2, "0")}` : ""}` : `${m} min`);
const imageOf = (v) => v.image || `https://docs.fivem.net/vehicles/${v.model}.webp`;
const categoryOf = (v) => v.category || "Autres";

function selectedVehicle() {
    return data.vehicles.find((v) => v.id === state.selected) || null;
}

function choose(vehicle) {
    if (state.selected === vehicle.id) return;
    state.selected = vehicle.id;
    nui("rentalPreview", { id: vehicle.id });
    paint();
}

function paint() {
    const categories = [...new Set(data.vehicles.map(categoryOf))].sort();
    if (!categories.includes(state.category)) state.category = categories[0] || null;
    const list = data.vehicles.filter((v) => categoryOf(v) === state.category);
    const vehicle = selectedVehicle();

    $("count").textContent = `${data.vehicles.length} disponible${data.vehicles.length > 1 ? "s" : ""}`;

    // Location en cours : on peut regarder, pas louer une deuxième
    const active = $("active");
    active.classList.toggle("hidden", !data.active);
    if (data.active) {
        active.replaceChildren(
            h("div", null, h("b", null, `Location en cours : ${data.active.label}`), `Plaque ${data.active.plate} · reste ${minutes(Math.ceil(data.active.remaining / 60))}`),
            h("button", { class: "ghost-btn", title: "Le véhicule doit être garé près du comptoir", onclick: () => nui("rentalReturn") }, "Rendre"));
    }

    $("tabs").classList.toggle("hidden", categories.length < 2);
    $("tabs").replaceChildren(...categories.map((c) => h("button", { class: `tab${c === state.category ? " on" : ""}`, onclick: () => {
        state.category = c;
        const first = data.vehicles.find((v) => categoryOf(v) === c);
        if (first && (!vehicle || categoryOf(vehicle) !== c)) return choose(first);
        paint();
    } }, c)));

    $("grid").replaceChildren(...(list.length ? list.map((v) => h("button", { class: `card${v.id === state.selected ? " on" : ""}`, onclick: () => choose(v) },
        h("span", { class: "pic" }, h("img", { src: imageOf(v), alt: "", loading: "lazy", onerror: (e) => { e.target.style.visibility = "hidden"; } })),
        h("b", null, v.label),
        h("small", null, data.sale ? (v.price > 0 ? money(v.price) : "Gratuit") : v.price > 0 ? `${money(v.price)} · ${minutes(v.duration)}` : `Gratuit · ${minutes(v.duration)}`))) : [h("p", { class: "empty" }, "Aucun véhicule disponible.")]));

    $("name").replaceChildren(...(vehicle ? [h("b", null, vehicle.label),
        h("small", null, data.sale ? (vehicle.price > 0 ? money(vehicle.price) : "Gratuit") : `${vehicle.price > 0 ? money(vehicle.price) : "Gratuit"} pour ${minutes(vehicle.duration)}`),
        data.sale ? statsOf(vehicle) : null] : []));
    paintFoot(vehicle);
}

// Vente : caractéristiques du modèle (lues par le jeu)
function statsOf(vehicle) {
    const stats = data.stats && data.stats[String(vehicle.id)];
    if (!stats) return null;
    return h("div", { class: "stats" },
        h("div", { class: "stat-speed" }, h("b", null, String(stats.speed)), h("small", null, "km/h max")),
        stats.bars.map((bar) => h("div", { class: "stat" }, h("span", null, bar.label),
            h("i", null, h("em", { style: `width:${Math.round(Math.max(0.04, bar.value) * 100)}%` })))));
}

// Caméras de la vitrine : extérieur, intérieur, rotation automatique
function paintCams() {
    const set = (cam, auto) => { state.cam = cam; state.auto = auto; nui("rentalCamera", { mode: cam, auto }); paintCams(); };
    $("cams").replaceChildren(
        h("button", { class: state.cam === "orbit" && !state.auto ? "on" : "", onclick: () => set("orbit", false) }, "Extérieur"),
        h("button", { class: state.cam === "inside" ? "on" : "", onclick: () => set("inside", false) }, "Intérieur"),
        h("button", { class: state.auto ? "on" : "", onclick: () => set("orbit", !state.auto) }, "Rotation"));
}

// Vente : couleur principale ou secondaire (-1 = d'origine)
function colorRow(label, key) {
    const pick = (id) => { state[key] = id; nui("rentalColor", { primary: state.primary, secondary: state.secondary }); paintFoot(selectedVehicle()); };
    return h("div", { class: "colors" }, h("span", null, label), h("div", { class: "swatches" },
        h("button", { class: `swatch origin${state[key] < 0 ? " on" : ""}`, title: "Couleur d'origine", onclick: () => pick(-1) }, "∅"),
        SALE_COLORS.map(([id, name, hex]) => h("button", { class: `swatch${state[key] === id ? " on" : ""}`, title: name, style: `background:${hex}`, onclick: () => pick(id) }))));
}

function paintFoot(vehicle) {
    const max = Math.max(1, data.maxPeriods || 1);
    state.periods = Math.min(Math.max(1, state.periods), max);
    const total = vehicle ? vehicle.price * state.periods : 0;
    const canPay = (account) => total <= (account === "bank" ? data.bank : data.cash);
    if (total > 0 && !canPay(state.account) && canPay(state.account === "bank" ? "money" : "bank")) state.account = state.account === "bank" ? "money" : "bank";

    const payButton = (account, label, balance) => h("button", {
        class: state.account === account ? "on" : "", disabled: total > 0 && !canPay(account),
        onclick: () => { state.account = account; paintFoot(vehicle); },
    }, label, h("small", null, money(balance)));

    const blocked = !vehicle || !!data.active || (total > 0 && !canPay(state.account));
    $("foot").replaceChildren(...[
        data.sale ? colorRow("Couleur", "primary") : null,
        data.sale ? colorRow("Secondaire", "secondary") : null,
        data.sale ? null : h("div", { class: "row" }, h("span", null, "Durée"),
            h("div", { class: "stepper" },
                h("button", { disabled: state.periods <= 1, onclick: () => { state.periods -= 1; paintFoot(vehicle); } }, "−"),
                h("b", null, vehicle ? minutes(vehicle.duration * state.periods) : "—"),
                h("button", { disabled: state.periods >= max, onclick: () => { state.periods += 1; paintFoot(vehicle); } }, "+"))),
        h("div", { class: "row" }, h("span", null, "Total"), h("b", { class: "total" }, total > 0 ? money(total) : "Gratuit")),
        total > 0 ? h("div", { class: "pay" }, payButton("money", "Liquide", data.cash), payButton("bank", "Carte", data.bank)) : null,
        data.sale ? h("button", { class: "ghost-btn test", disabled: !vehicle, onclick: () => vehicle && nui("rentalTest", { id: vehicle.id }) }, "Essai routier") : null,
        h("button", { class: "go", disabled: blocked, onclick: () => {
            if (blocked) return;
            nui("rentalRent", { id: vehicle.id, periods: state.periods, account: state.account, primary: state.primary, secondary: state.secondary });
        } }, data.active ? "Location déjà en cours" : data.sale ? "Acheter" : "Louer")].filter(Boolean));
}

// Glisser sur la scène : tourner la caméra ; molette : zoom
let drag = null;
$("stage").addEventListener("mousedown", (e) => { if (!e.target.closest("button")) drag = { x: e.clientX, y: e.clientY }; });
window.addEventListener("mouseup", () => { drag = null; });
window.addEventListener("mousemove", (e) => {
    if (!drag) return;
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    drag = { x: e.clientX, y: e.clientY };
    if (Math.abs(dx) + Math.abs(dy) >= 1) nui("rentalRotate", { dx, dy });
});
$("stage").addEventListener("wheel", (e) => nui("rentalRotate", { zoom: e.deltaY > 0 ? 0.6 : -0.6 }), { passive: true });

$("close").addEventListener("click", () => nui("rentalClose"));
window.addEventListener("keydown", (e) => { if (e.key === "Escape" && data) nui("rentalClose"); });

// Compte à rebours de la location en cours (placé par le jeu à droite de la minimap)
function paintTimer(msg) {
    const timer = $("timer");
    if (!msg.label || msg.hidden) return timer.classList.add("hidden");
    const left = Math.max(0, msg.remaining);
    timer.classList.remove("hidden");
    timer.classList.toggle("late", left <= 60);
    timer.title = msg.label;
    timer.querySelector("small").textContent = msg.test ? "Essai" : left > 0 ? "Location" : "À rendre";
    $("timer-time").textContent = `${String(Math.floor(left / 60)).padStart(2, "0")}:${String(left % 60).padStart(2, "0")}`;
    timer.style.left = `calc(${msg.left * 100}% + 8px)`;
    timer.style.top = `${msg.bottom * 100}%`;
}

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "rentalTimer") paintTimer(msg);
    if (msg.action === "rentalOpen") {
        data = msg;
        state.category = null;
        state.periods = 1;
        state.account = "money";
        state.selected = null;
        state.cam = "orbit";
        state.auto = false;
        state.primary = -1;
        state.secondary = -1;
        paintCams();
        $("agency").textContent = data.label;
        document.querySelector("#rental .head small").textContent = data.sale ? "Vente" : "Location";
        $("rental").classList.remove("hidden");
        // Premier véhicule du premier onglet : montré tout de suite dans la vitrine
        const first = [...data.vehicles].sort((a, b) => categoryOf(a).localeCompare(categoryOf(b)))[0];
        if (first) choose(first);
        else paint();
    }
    if (msg.action === "rentalClose") {
        data = null;
        $("rental").classList.add("hidden");
    }
});

// ---------- Aperçu navigateur ----------

if (!inGame && location.hash.includes("sale")) {
    const bars = (a, b, c, d) => [{ label: "Vitesse", value: a }, { label: "Accélération", value: b }, { label: "Freinage", value: c }, { label: "Traction", value: d }];
    window.postMessage({
        action: "rentalOpen", sale: true, label: "Concessionnaire Premium Deluxe", currency: "$", cash: 420, bank: 15800, active: null,
        vehicles: [
            { id: 1, model: "bmx", label: "BMX", price: 350, category: "BMX" },
            { id: 2, model: "scorcher", label: "Scorcher", price: 900, category: "VTT" },
            { id: 3, model: "tribike", label: "Whippet", price: 1200, category: "Route" },
            { id: 4, model: "cruiser", label: "Cruiser", price: 500, category: "Ville" },
        ],
        stats: { 1: { speed: 38, bars: bars(0.3, 0.5, 0.4, 0.6) }, 2: { speed: 45, bars: bars(0.4, 0.45, 0.5, 0.7) }, 3: { speed: 52, bars: bars(0.5, 0.4, 0.4, 0.5) }, 4: { speed: 35, bars: bars(0.28, 0.3, 0.35, 0.55) } },
    }, "*");
} else if (!inGame && !location.hash.includes("store")) {
    window.postMessage({
        action: "rentalOpen", label: "Location Vespucci", currency: "$", cash: 420, bank: 15800, maxPeriods: 4,
        active: null,
        vehicles: [
            { id: 1, model: "faggio", label: "Faggio", price: 50, duration: 30, category: "Scooters" },
            { id: 2, model: "blista", label: "Blista", price: 120, duration: 30, category: "Citadines" },
            { id: 3, model: "panto", label: "Panto", price: 90, duration: 30, category: "Citadines" },
            { id: 4, model: "issi2", label: "Issi", price: 110, duration: 30, category: "Citadines" },
            { id: 5, model: "rumpo", label: "Rumpo", price: 250, duration: 60, category: "Utilitaires" },
        ],
    }, "*");
}
