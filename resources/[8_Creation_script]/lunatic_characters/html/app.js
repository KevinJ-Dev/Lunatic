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

let data = null;   // { characters, slots, max, tiers, vip }
let selected = null; // emplacement choisi
let busy = false;

const money = (n) => `${Math.round(n).toLocaleString("fr-FR")} $`;
const lastSeen = (time) => (time ? new Date(time * 1000).toLocaleDateString("fr-FR", { day: "numeric", month: "long", year: "numeric" }) : "—");

// Choix d'un emplacement : le jeu montre ce personnage sur le décor
function choose(slot) {
    if (selected === slot) return;
    selected = slot;
    nui("preview", { slot });
    paint();
}

// Abonnement qui débloque un emplacement verrouillé (le moins cher qui suffit)
function lockLabel(slot) {
    const tiers = Object.values(data.tiers || {}).filter((t) => Number(t.characters) >= slot).sort((a, b) => a.characters - b.characters);
    return tiers.length ? tiers[0].label : "Sur demande au staff";
}

function paint() {
    const bySlot = new Map(data.characters.map((c) => [c.slot, c]));
    const total = Math.max(data.slots, ...data.characters.map((c) => c.slot));

    $("list").replaceChildren(...Array.from({ length: Math.min(total + 1, data.max) }, (_, i) => {
        const slot = i + 1;
        const character = bySlot.get(slot);
        const locked = slot > data.slots;
        const name = character && character.firstname ? `${character.firstname} ${character.lastname}` : null;
        let sub;
        if (locked) sub = h("small", { class: "lock" }, `Verrouillé · ${lockLabel(slot)}`);
        else if (!character) sub = h("small", null, "Emplacement libre");
        else if (!name) sub = h("small", null, "Création à terminer");
        else sub = h("small", null, `${character.job}${character.grade ? ` · ${character.grade}` : ""} · ${money(character.money + character.bank)}`);

        const avatar = character && character.mugshot
            ? h("img", { src: character.mugshot, alt: "" })
            : (character ? (name ? name[0] : "?") : "+");
        return h("button", { class: `slot${selected === slot ? " on" : ""}`, disabled: locked, onclick: () => choose(slot) },
            h("span", { class: "avatar" }, avatar),
            h("span", { class: "info" }, h("b", null, name || (character ? "Personnage sans identité" : "Nouveau personnage")), sub));
    }));

    const character = bySlot.get(selected);
    const name = character && character.firstname ? character : null;
    $("name").replaceChildren(...(name ? [h("span", null, `${name.firstname} `), name.lastname] : []));

    // Fiche du personnage choisi
    const row = (label, value) => h("div", { class: "detail" }, h("small", null, label), h("b", null, value));
    $("details").classList.toggle("hidden", !name);
    $("details").replaceChildren(...(name ? [
        row("Métier", `${character.job}${character.grade ? ` · ${character.grade}` : ""}`),
        row("Liquide", money(character.money)),
        row("Banque", money(character.bank)),
        row("Naissance", character.dateofbirth || "—"),
        row("Nationalité", character.nationality || "—"),
        row("Dernière connexion", lastSeen(character.lastSeen)),
    ] : []));
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
        data = { characters: msg.characters || [], slots: msg.slots || 1, max: msg.max || 5, tiers: msg.tiers || {}, vip: msg.vip };
        const badge = $("vip");
        badge.classList.toggle("hidden", !data.vip);
        if (data.vip) {
            badge.textContent = data.vip.label;
            badge.style.background = data.vip.color || "";
        }
        $("server-id").replaceChildren("ID ", h("b", null, String(msg.serverId || "")));
        // Premier personnage existant, sinon premier emplacement libre
        selected = null;
        busy = false;
        choose(data.characters.length ? data.characters[0].slot : 1);
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
        max: 5,
        tiers: { premium: { label: "VIP", color: "#f2c26b", characters: 2 }, premium_plus: { label: "VIP+", color: "#9650ff", characters: 3 } },
        vip: { label: "VIP", color: "#f2c26b" },
        serverId: 2,
        characters: [
            { slot: 1, firstname: "Denzel", lastname: "Washington", job: "Chômeur", money: 390, bank: 143650, dateofbirth: "12/04/1992", nationality: "Américaine", lastSeen: 1792000000 },
            { slot: 2, firstname: "Camembet", lastname: "Adriana", job: "Mécano", grade: "Apprenti", money: 120, bank: 5400, dateofbirth: "03/09/1998", nationality: "Française", lastSeen: 1791500000 },
        ],
    }, "*");
}
