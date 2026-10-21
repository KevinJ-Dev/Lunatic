"use strict";

// ====================================================================
//  lunatic_illegal — tablette des crews (NUI)
//  Onglets : Crew, Territoires, Marché noir, Missions (bientôt). Tout passe par le client puis le serveur,
//  qui revérifie le crew, le rang et la tablette.
// ====================================================================

const IN_GAME = typeof GetParentResourceName === "function";
const RESOURCE = IN_GAME ? GetParentResourceName() : "lunatic_illegal";
const $ = (id) => document.getElementById(id);

const TABS = [
    { id: "crew", label: "Crew", icon: "i-users" },
    { id: "territories", label: "Territoires", icon: "i-map" },
    { id: "market", label: "Marché noir", icon: "i-cart" },
    { id: "missions", label: "Missions", icon: "i-target", soon: true },
];

let tab = "crew";
let data = null; // { crew, me, territories, market }
let clockTimer = null;

function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
        if (value === null || value === undefined || value === false) continue;
        if (key === "class") el.className = value;
        else if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
        else if (value === true) el.setAttribute(key, "");
        else el.setAttribute(key, value);
    }
    for (const child of children.flat()) {
        if (child === null || child === undefined || child === false) continue;
        el.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return el;
}

function icon(name) {
    const ns = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(ns, "svg");
    svg.setAttribute("class", "i");
    const use = document.createElementNS(ns, "use");
    use.setAttribute("href", `#${name}`);
    svg.append(use);
    return svg;
}

const money = (n) => `${new Intl.NumberFormat("fr-FR").format(Math.floor(n || 0))} $`;
const minutes = (s) => (s < 60 ? `${Math.max(1, Math.round(s))} s` : `${Math.round(s / 60)} min`);
const itemImage = (name) => h("img", { src: `nui://ox_inventory/web/images/${name}.png`, alt: "", onerror: (e) => { e.target.style.visibility = "hidden"; } });

async function nui(name, payload) {
    if (!IN_GAME) return demo(name, payload);
    const response = await fetch(`https://${RESOURCE}/${name}`, { method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8" }, body: JSON.stringify(payload || {}) });
    return response.json();
}

function toast(message, kind) {
    const el = h("div", { class: `toast ${kind || ""}` }, message);
    $("toasts").append(el);
    setTimeout(() => el.remove(), 3500);
}

function confirmBox(title, text, label, danger) {
    return new Promise((resolve) => {
        const done = (value) => { $("modalBack").classList.remove("on"); resolve(value); };
        $("modal").replaceChildren(h("h3", null, title), h("p", null, text),
            h("div", { class: "foot" }, h("button", { class: "btn", onclick: () => done(false) }, "Annuler"),
                h("button", { class: `btn ${danger ? "danger" : "primary"}`, onclick: () => done(true) }, label)));
        $("modalBack").classList.add("on");
    });
}

// Résultat d'une action : message d'erreur ou rechargement des données
async function run(name, payload, okMessage) {
    const res = await nui(name, payload).catch(() => null);
    if (!res || !res.ok) {
        toast((res && res.error) || "Action impossible.", "error");
        return null;
    }
    if (okMessage) toast(typeof okMessage === "function" ? okMessage(res) : okMessage, "ok");
    await load();
    return res;
}

async function load() {
    const res = await nui("load").catch(() => null);
    if (!res || !res.ok) {
        toast((res && res.error) || "Tablette indisponible.", "error");
        return;
    }
    data = res;
    render();
}

// ---------- Rendu ----------

function render() {
    if (!data || !data.crew) return;
    const crew = data.crew;
    const dot = h("span", { class: "dot" });
    dot.style.background = crew.color;
    $("crewChip").replaceChildren(dot, crew.label, h("small", null, `${crew.typeLabel} · level ${crew.level}`));
    $("nav").replaceChildren(...TABS.map((t) => h("button", { class: `${t.id === tab ? "active" : ""}${t.soon ? " soon" : ""}`, onclick: () => {
        if (t.soon) return toast(`${t.label} : bientôt disponible.`, "");
        tab = t.id;
        render();
    } }, icon(t.icon), t.label)));

    const page = tab === "territories" ? territoriesPage() : tab === "market" ? marketPage() : crewPage();
    const scroll = $("page").scrollTop;
    $("page").replaceChildren(page);
    $("page").scrollTop = scroll;
}

function crewPage() {
    const crew = data.crew;
    const me = data.me;
    const logo = h("div", { class: "logo" }, crew.label.slice(0, 1).toUpperCase());
    logo.style.background = crew.color;
    const pct = crew.nextLevelXp ? Math.min(100, (crew.xp / crew.nextLevelXp) * 100) : 100;
    const fill = h("i");
    fill.style.width = `${pct}%`;
    const online = crew.members.filter((m) => m.online).length;

    const rows = crew.members.map((m) => {
        const isMe = m.identifier === me.identifier;
        const index = crew.ranks.findIndex((r) => r.rank === m.rank);
        const up = crew.ranks[index + 1];
        const down = crew.ranks[index - 1];
        const manage = me.leader && !isMe && m.rank < crew.topRank;
        return h("div", { class: "row" },
            h("span", { class: `online${m.online ? " on" : ""}` }),
            h("div", { class: "who" }, h("b", null, isMe ? `${m.name} (vous)` : m.name), h("span", null, `${m.rankLabel}${m.online ? " · en ligne" : ""}`)),
            manage ? h("div", { class: "actions" },
                up && up.rank < crew.topRank ? h("button", { class: "btn small icon", title: `Promouvoir : ${up.label}`, onclick: () => run("setRank", { identifier: m.identifier, rank: up.rank }, `${m.name} est maintenant ${up.label}.`) }, icon("i-up")) : null,
                down ? h("button", { class: "btn small icon", title: `Rétrograder : ${down.label}`, onclick: () => run("setRank", { identifier: m.identifier, rank: down.rank }, `${m.name} est maintenant ${down.label}.`) }, icon("i-down")) : null,
                h("button", { class: "btn small icon danger", title: "Renvoyer du crew", onclick: async () => {
                    if (await confirmBox(`Renvoyer ${m.name} ?`, "Il quitte le crew immédiatement.", "Renvoyer", true)) run("kick", { identifier: m.identifier }, `${m.name} a été renvoyé.`);
                } }, icon("i-door"))) : null);
    });

    return h("div", null,
        h("h2", null, "Crew"), h("p", { class: "sub" }, "Informations et membres de votre crew"),
        h("div", { class: "card" }, h("div", { class: "hero" }, logo,
            h("div", { class: "grow" }, h("b", null, crew.label), h("div", { class: "sub", style: "margin:2px 0 0" }, `${crew.typeLabel} · level ${crew.level} · ${crew.nextLevelXp ? `${crew.xp} / ${crew.nextLevelXp} XP` : `${crew.xp} XP (level maximum)`}`),
                h("div", { class: "xp" }, fill)))),
        h("div", { class: "card" },
            h("div", { class: "card-title" }, `Membres (${crew.members.length}) · ${online} en ligne`, h("span", { class: "grow" }),
                me.leader ? h("button", { class: "btn small primary", onclick: openInvite }, icon("i-plus"), "Inviter un joueur proche")
                    : h("button", { class: "btn small danger", onclick: async () => {
                        if (await confirmBox(`Quitter ${crew.label} ?`, "Vous ne pourrez revenir que sur invitation du chef.", "Quitter", true)) {
                            const res = await nui("leave").catch(() => null);
                            if (res && res.ok) { toast(`Vous avez quitté ${res.crew}.`, "ok"); close(); } else toast((res && res.error) || "Action impossible.", "error");
                        }
                    } }, icon("i-door"), "Quitter le crew")),
            rows));
}

async function openInvite() {
    const res = await nui("nearby").catch(() => null);
    const list = (res && res.players) || [];
    const done = () => $("modalBack").classList.remove("on");
    $("modal").replaceChildren(
        h("h3", null, "Inviter un joueur proche"),
        h("p", null, "Le joueur doit être juste à côté de vous et ne faire partie d'aucun crew."),
        list.length ? h("div", null, list.map((p) => h("div", { class: "row" },
            h("div", { class: "who" }, h("b", null, p.name), h("span", null, `ID ${p.id}${p.inCrew ? " · déjà dans un crew" : ""}`)),
            h("button", { class: "btn small primary", disabled: p.inCrew, onclick: async () => {
                done();
                await run("invite", { serverId: p.id }, (r) => `Invitation envoyée à ${r.name}.`);
            } }, "Inviter")))) : h("div", { class: "empty" }, "Personne à proximité."),
        h("div", { class: "foot" }, h("button", { class: "btn", onclick: done }, "Fermer")));
    $("modalBack").classList.add("on");
}

function territoriesPage() {
    const list = data.territories || [];
    const cards = list.map((t) => {
        const top = Math.max(t.leader, t.minInfluence, t.influence, 1);
        const lead = h("i", { class: "lead" });
        lead.style.width = `${(t.leader / top) * 100}%`;
        const mine = h("i", { class: "mine" });
        mine.style.width = `${(t.influence / top) * 100}%`;
        const seuil = h("span", { class: "seuil" });
        seuil.style.left = `${Math.min(100, (t.minInfluence / top) * 100)}%`;
        return h("div", { class: `terr${t.owned ? " owned" : ""}` },
            h("div", { class: "head" }, icon(t.owned ? "i-flag" : "i-map"), h("b", null, t.label),
                t.owned ? h("span", { class: "badge ok" }, "Tenu par votre crew") : h("span", { class: "badge muted" }, t.owner ? `Tenu par ${t.owner}` : "Libre"),
                t.contested ? h("span", { class: "badge warn" }, "Disputé") : null,
                h("button", { class: "btn small", onclick: () => nui("gps", { x: t.x, y: t.y }).then(() => toast(`GPS : ${t.label}.`, "ok")) }, icon("i-gps"), "GPS")),
            h("div", { class: "bar" }, lead, mine, seuil),
            h("div", { class: "meta" }, `Votre influence : ${Math.floor(t.influence)} · en tête : ${Math.floor(t.leader)} · seuil : ${t.minInfluence} · bonus +${t.priceBonus} % au prix, +${t.xpBonus} % d'XP pour le crew qui tient la zone`));
    });
    return h("div", null,
        h("h2", null, "Territoires"), h("p", { class: "sub" }, "Vendre de la drogue dans une zone donne de l'influence à votre crew. Le crew en tête au-dessus du seuil tient la zone."),
        cards.length ? h("div", null, cards) : h("div", { class: "card" }, h("div", { class: "empty" }, "Aucun territoire pour le moment.")));
}

function marketPage() {
    const m = data.market;
    if (!m || !m.ok) {
        return h("div", null, h("h2", null, "Marché noir"), h("div", { class: "card" }, h("div", { class: "empty" }, (m && m.error) || "Marché indisponible.")));
    }

    const articles = m.items.map((a) => {
        const qty = h("input", { type: "number", min: "1", max: String(Math.max(1, a.stock)), value: "1" });
        return h("div", { class: `article${a.locked ? " locked" : ""}` },
            h("div", { class: "pic" }, itemImage(a.item)),
            h("b", null, a.label),
            h("div", { class: "meta" }, h("span", { class: "price" }, money(a.price)), h("span", null, a.locked ? `level ${a.minLevel}` : `stock ${a.stock}`)),
            a.locked ? h("button", { class: "btn small", disabled: true }, icon("i-lock"), `Level ${a.minLevel} requis`)
                : h("div", { class: "buy" }, qty, h("button", { class: "btn small primary", disabled: a.stock < 1 || !m.dropoffs, onclick: async () => {
                    const count = Math.floor(Number(qty.value) || 0);
                    if (count < 1) return;
                    if (!(await confirmBox(`Commander ${count} × ${a.label} ?`, `${money(a.price * count)} en argent sale, payés tout de suite. La commande arrivera à un point de livraison discret.`, "Commander"))) return;
                    await run("buy", { itemId: a.id, count }, (r) => `Commande passée : arrivée dans ${minutes(r.readyIn)} environ.`);
                } }, icon("i-cart"), a.stock < 1 ? "Épuisé" : "Commander")));
    });

    const orders = m.orders.map((o) => h("div", { class: `order${o.ready ? " ready" : ""}` },
        icon(o.ready ? "i-box" : "i-clock"),
        h("div", { class: "who" }, h("b", null, `${o.count} × ${o.label}`),
            h("span", null, o.ready ? `Prête : ${o.dropoff ? o.dropoff.label : "?"} · à récupérer dans ${minutes(o.expiresIn)} · commandée par ${o.buyer}` : `Arrive dans ${minutes(o.readyIn)} · commandée par ${o.buyer}`)),
        o.ready && o.dropoff ? h("button", { class: "btn small primary", onclick: () => nui("gps", { x: o.dropoff.x, y: o.dropoff.y }).then(() => toast(`GPS : ${o.dropoff.label}.`, "ok")) }, icon("i-gps"), "GPS") : null));

    return h("div", null,
        h("h2", null, "Marché noir"), h("p", { class: "sub" }, "Paiement en argent sale. La marchandise est livrée plus tard à un point discret : récupérez-la sur place avant qu'elle ne soit perdue."),
        h("div", { class: "money-line" },
            h("div", { class: "pill" }, "Argent sale :", h("b", null, money(m.money))),
            h("div", { class: "pill" }, "Level du crew :", h("b", null, String(m.level))),
            h("div", { class: "pill" }, "Commandes en cours :", h("b", null, `${m.orders.length} / ${m.maxPending}`))),
        m.orders.length ? h("div", { class: "card" }, h("div", { class: "card-title" }, "Commandes du crew"), orders) : null,
        h("div", { class: "card" }, h("div", { class: "card-title" }, "Catalogue"),
            !m.dropoffs ? h("div", { class: "empty" }, "Le marché est fermé pour le moment.")
                : articles.length ? h("div", { class: "shop" }, articles) : h("div", { class: "empty" }, "Rien à vendre pour le moment.")));
}

// ---------- Ouverture / fermeture ----------

function updateClock() {
    $("clock").textContent = new Date().toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
}

function open() {
    document.body.classList.remove("hidden");
    updateClock();
    clearInterval(clockTimer);
    clockTimer = setInterval(updateClock, 10000);
    load();
}

function close() {
    document.body.classList.add("hidden");
    $("modalBack").classList.remove("on");
    clearInterval(clockTimer);
    nui("close");
}

$("close").addEventListener("click", close);
window.addEventListener("keydown", (e) => {
    if (e.key !== "Escape" || document.body.classList.contains("hidden")) return;
    if ($("modalBack").classList.contains("on")) $("modalBack").classList.remove("on");
    else close();
});
window.addEventListener("message", (event) => {
    const msg = event.data;
    if (!msg || typeof msg !== "object") return;
    if (msg.action === "openTablet") open();
    else if (msg.action === "closeTablet") document.body.classList.add("hidden");
});

// ---------- Démo (aperçu hors jeu) ----------

function demo(name, payload) {
    if (name === "load") return { ok: true,
        me: { identifier: "aa", rank: 3, leader: true },
        crew: { id: 1, label: "Ballas", type: "gang", typeLabel: "Gang", color: "#9b59b6", level: 3, xp: 3200, nextLevelXp: 5000, topRank: 3,
            ranks: [{ rank: 0, label: "Rang C" }, { rank: 1, label: "Rang B" }, { rank: 2, label: "Rang A" }, { rank: 3, label: "Rang S" }],
            members: [{ identifier: "aa", name: "Jean Dupont", online: true, rank: 3, rankLabel: "Rang S" }, { identifier: "bb", name: "Lina Petit", online: false, rank: 1, rankLabel: "Rang B" }, { identifier: "cc", name: "Tony Vega", online: true, rank: 0, rankLabel: "Rang C" }] },
        territories: [
            { label: "Grove Street", owned: true, owner: "Ballas", influence: 42.5, leader: 42.5, minInfluence: 10, priceBonus: 20, xpBonus: 20, contested: true, x: 105, y: -1940 },
            { label: "Port de Los Santos", owned: false, owner: null, influence: 4, leader: 12.4, minInfluence: 25, priceBonus: 30, xpBonus: 10, contested: false, x: 1000, y: -3000 },
        ],
        market: { ok: true, money: 18450, level: 3, maxPending: 3, dropoffs: 2,
            items: [
                { id: 1, item: "gun_barrel", label: "Canon d'arme", price: 2500, minLevel: 1, stock: 8, stockMax: 10 },
                { id: 2, item: "gun_slide", label: "Culasse", price: 2000, minLevel: 1, stock: 0, stockMax: 10 },
                { id: 3, item: "gun_stock", label: "Crosse", price: 1500, minLevel: 3, stock: 10, stockMax: 10 },
                { id: 4, item: "chemicals", label: "Produits chimiques", price: 300, minLevel: 4, stock: 30, stockMax: 30, locked: true },
            ],
            orders: [
                { id: 7, label: "Douille", count: 48, buyer: "Jean Dupont", ready: true, readyIn: 0, expiresIn: 5400, dropoff: { label: "Hangar abandonné", x: 1, y: 2 } },
                { id: 8, label: "Canon d'arme", count: 2, buyer: "Tony Vega", ready: false, readyIn: 420, expiresIn: 7620, dropoff: null },
            ] } };
    if (name === "nearby") return { ok: true, players: [{ id: 12, name: "Sarah Klein", inCrew: false }, { id: 14, name: "Marco Rossi", inCrew: true }] };
    if (name === "buy") return { ok: true, readyIn: 540 };
    return { ok: true };
}

if (!IN_GAME) open();
