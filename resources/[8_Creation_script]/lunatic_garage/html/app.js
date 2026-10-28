"use strict";

// Garage public (lunatic_garage) : véhicules du joueur pour ce type de garage, places libres, véhicules à récupérer à la
// fourrière, aperçu sur place (géré par le jeu) et sortie. Le serveur revérifie tout.

const $ = (id) => document.getElementById(id);
const inGame = typeof GetParentResourceName === "function";
const resource = inGame ? GetParentResourceName() : "lunatic_garage";

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

let data = null;
let selected = null;

const STATES = { out: "Dehors", impound: "Fourrière" };
const imageOf = (v) => `https://docs.fivem.net/vehicles/${v.name}.webp`;
const vehicleOf = (id) => data.vehicles.find((v) => v.id === id) || null;

function open(msg) {
    data = msg;
    const first = data.vehicles.find((v) => v.state === "stored") || data.vehicles[0];
    selected = first ? first.id : null;
    $("title").textContent = "GARAGE";
    $("sub").textContent = data.label || "Public";
    $("garage").classList.remove("hidden");
    paint();
    if (first) nui("preview", { id: first.id });
}

function choose(v) {
    if (selected === v.id) return;
    selected = v.id;
    nui("preview", { id: v.id });
    paint();
}

function row(v) {
    const img = h("img", { src: imageOf(v), alt: "", loading: "lazy" });
    img.addEventListener("error", () => { img.style.visibility = "hidden"; });
    return h("button", { class: `veh ${v.state}${v.id === selected ? " on" : ""}`, onclick: () => choose(v) },
        h("span", { class: "pic" }, img),
        h("span", null, h("b", null, v.label), h("small", null, v.plate)),
        STATES[v.state] ? h("i", { class: "tag" }, STATES[v.state]) : null);
}

function paint() {
    const kept = data.vehicles.filter((v) => v.state !== "impound");
    const impound = data.vehicles.filter((v) => v.state === "impound");
    // Places libres, tous garages confondus (data.stored = véhicules rangés partout)
    const free = Math.max(0, data.slots - data.stored);
    const empties = Array.from({ length: Math.min(free, 6) }, (_, i) => h("div", { class: "veh empty" },
        h("span", { class: "plus" }, "+"), h("span", null, `Emplacement ${data.stored + i + 1}`)));

    $("list").replaceChildren(...[
        h("div", { class: "section" }, "Véhicules"),
        kept.length ? kept.map(row) : null,
        empties,
        !kept.length && !empties.length ? h("p", { class: "empty-text" }, "Aucun véhicule ici.") : null,
        impound.length ? h("div", { class: "section" }, "Fourrière") : null,
        impound.map(row),
    ].flat().filter(Boolean));

    const v = selected ? vehicleOf(selected) : null;
    const reason = !v ? "Choisissez un véhicule." : v.state === "out" ? "Ce véhicule est déjà dehors." : v.state === "impound" ? "À récupérer à la fourrière." : null;
    $("foot").replaceChildren(...[
        h("div", { class: "places" }, h("span", null, "Places de garage"), h("b", null, `${data.stored} / ${data.slots}`)),
        reason && v ? h("p", { class: "note" }, reason) : null,
        h("button", { class: "btn", disabled: !!reason, onclick: () => { if (!reason) nui("takeOut", { id: v.id }); } }, "Sortir"),
        h("button", { class: "btn ghost", onclick: close }, "Fermer"),
    ].filter(Boolean));
}

function close() {
    $("garage").classList.add("hidden");
    data = null;
    nui("close");
}

document.addEventListener("keydown", (e) => { if (e.key === "Escape" && data) close(); });

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "open") open(msg);
    if (msg.action === "close") {
        data = null;
        $("garage").classList.add("hidden");
    }
});

// ---------- Aperçu navigateur ----------

if (!inGame) {
    window.postMessage({
        action: "open", kind: "garage", label: "Garage de Pillbox Hill", slots: 5, stored: 2,
        vehicles: [
            { id: 1, plate: "ABC 1234", label: "Sultan", name: "sultan", state: "stored" },
            { id: 2, plate: "KLM 0042", label: "Baller", name: "baller", state: "stored" },
            { id: 3, plate: "XYZ 9876", label: "Faggio", name: "faggio", state: "out" },
            { id: 4, plate: "QRT 5521", label: "Landstalker", name: "landstalker", state: "impound" },
        ],
    }, "*");
}
