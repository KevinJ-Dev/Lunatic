"use strict";

// Sélection de personnage (lunatic_characters) : la page affiche, le serveur décide (emplacements, chargement).

const $ = (id) => document.getElementById(id);
const inGame = typeof GetParentResourceName === "function";
const resource = inGame ? GetParentResourceName() : "lunatic_characters";

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
    if (!inGame) return demo(name, payload);
    const res = await fetch(`https://${resource}/${name}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) });
    return res.json();
}

function toast(text) {
    const el = $("toast");
    el.textContent = text;
    el.classList.add("on");
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => el.classList.remove("on"), 3500);
}

let data = null;   // { characters, slots, tiers }
let selected = null; // emplacement choisi
let busy = false;

const money = (n) => `${Math.round(n).toLocaleString("fr-FR")} $`;

// Abonnement nécessaire pour un emplacement verrouillé
function lockLabel(slot) {
    const t = data.tiers;
    if (slot <= t.premium) return "Premium";
    if (slot <= t.premium_plus) return "Premium+";
    return "Sur demande au staff";
}

function paint() {
    const bySlot = new Map(data.characters.map((c) => [c.slot, c]));
    const total = Math.max(data.slots, ...data.characters.map((c) => c.slot));

    $("list").replaceChildren(...Array.from({ length: Math.min(total + 1, data.tiers.max) }, (_, i) => {
        const slot = i + 1;
        const character = bySlot.get(slot);
        const locked = slot > data.slots;
        const name = character && character.firstname ? `${character.firstname} ${character.lastname}` : null;
        let sub;
        if (locked) sub = h("small", { class: "lock" }, `Verrouillé · ${lockLabel(slot)}`);
        else if (!character) sub = h("small", null, "Emplacement libre");
        else if (!name) sub = h("small", null, "Création à terminer");
        else sub = h("small", null, `${character.job}${character.grade ? ` · ${character.grade}` : ""} · ${money(character.money + character.bank)}`);

        return h("button", { class: `slot${selected === slot ? " on" : ""}`, disabled: locked, onclick: () => { selected = slot; paint(); } },
            h("span", { class: "avatar" }, character ? (name ? name[0] : "?") : "+"),
            h("span", { class: "info" }, h("b", null, name || (character ? "Personnage sans identité" : "Nouveau personnage")), sub));
    }));

    const character = bySlot.get(selected);
    const name = character && character.firstname ? character : null;
    $("name").replaceChildren(...(name ? [h("span", null, `${name.firstname} `), name.lastname] : []));
    $("play").disabled = busy || selected === null;
    $("play").textContent = character ? "Jouer" : "Créer ce personnage";
}

$("play").addEventListener("click", async () => {
    if (busy || selected === null) return;
    busy = true;
    paint();
    const res = await nui("play", { slot: selected }).catch(() => null);
    busy = false;
    if (!res || !res.ok) {
        paint();
        return toast((res && res.error) || "Impossible de charger ce personnage.");
    }
});

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "open") {
        data = { characters: msg.characters || [], slots: msg.slots || 1, tiers: msg.tiers };
        // Premier personnage existant, sinon premier emplacement libre
        selected = data.characters.length ? data.characters[0].slot : 1;
        busy = false;
        $("select").classList.remove("hidden");
        paint();
    }
    if (msg.action === "close") $("select").classList.add("hidden");
});

// ---------- Aperçu navigateur ----------

function demo(name) {
    if (name === "play") return { ok: true };
    return {};
}

if (!inGame) {
    window.postMessage({
        action: "open",
        slots: 2,
        tiers: { default: 1, premium: 2, premium_plus: 3, max: 5 },
        characters: [
            { slot: 1, firstname: "Denzel", lastname: "Washington", job: "Chômeur", money: 390, bank: 143650 },
            { slot: 2, firstname: "Camembet", lastname: "Adriana", job: "Mécano", grade: "Apprenti", money: 120, bank: 5400 },
        ],
    }, "*");
}
