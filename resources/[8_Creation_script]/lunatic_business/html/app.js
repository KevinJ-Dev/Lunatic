"use strict";

// Location de véhicules : catalogue de l'agence, aperçu 3D (géré par le jeu), durée par périodes, paiement.
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
const state = { category: null, selected: null, periods: 1, account: "money" };

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
        h("small", null, v.price > 0 ? `${money(v.price)} · ${minutes(v.duration)}` : `Gratuit · ${minutes(v.duration)}`))) : [h("p", { class: "empty" }, "Aucun véhicule disponible.")]));

    $("name").replaceChildren(...(vehicle ? [h("b", null, vehicle.label), h("small", null, `${vehicle.price > 0 ? money(vehicle.price) : "Gratuit"} pour ${minutes(vehicle.duration)}`)] : []));
    paintFoot(vehicle);
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
    $("foot").replaceChildren(
        h("div", { class: "row" }, h("span", null, "Durée"),
            h("div", { class: "stepper" },
                h("button", { disabled: state.periods <= 1, onclick: () => { state.periods -= 1; paintFoot(vehicle); } }, "−"),
                h("b", null, vehicle ? minutes(vehicle.duration * state.periods) : "—"),
                h("button", { disabled: state.periods >= max, onclick: () => { state.periods += 1; paintFoot(vehicle); } }, "+"))),
        h("div", { class: "row" }, h("span", null, "Total"), h("b", { class: "total" }, total > 0 ? money(total) : "Gratuit")),
        total > 0 ? h("div", { class: "pay" }, payButton("money", "Liquide", data.cash), payButton("bank", "Carte", data.bank)) : null,
        h("button", { class: "go", disabled: blocked, onclick: () => {
            if (blocked) return;
            nui("rentalRent", { id: vehicle.id, periods: state.periods, account: state.account });
        } }, data.active ? "Location déjà en cours" : "Louer"));
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

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "rentalOpen") {
        data = msg;
        state.category = null;
        state.periods = 1;
        state.account = "money";
        state.selected = null;
        $("agency").textContent = data.label;
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

if (!inGame) {
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
