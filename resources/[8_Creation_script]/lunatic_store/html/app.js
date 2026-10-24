"use strict";

// Boutique des joueurs (lunatic_store) : affichage seulement, chaque achat est vérifié par le serveur.

const $ = (id) => document.getElementById(id);
const inGame = typeof GetParentResourceName === "function";
const resource = inGame ? GetParentResourceName() : "lunatic_store";

let data = null;
let tab = null;
let categoryOf = {}; // catalogue -> catégorie choisie

function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
        if (value === null || value === undefined || value === false) continue;
        if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
        else if (key === "class") el.className = value;
        else el.setAttribute(key, value === true ? "" : value);
    }
    for (const child of children.flat()) {
        if (child === null || child === undefined || child === false) continue;
        el.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return el;
}

async function nui(name, payload) {
    if (!inGame) return demoNui(name, payload);
    const res = await fetch(`https://${resource}/${name}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) });
    return res.json();
}

const fmt = (n) => new Intl.NumberFormat("fr-FR").format(n || 0);
const creditsName = () => (data.credits && data.credits.name) || "Crédits";
const creditsIcon = () => data.credits && data.credits.image ? h("img", { src: data.credits.image, alt: "", onerror: (e) => e.target.remove() }) : h("span", { class: "coin" }, "◆");
const price = (n) => h("span", { class: "price" }, creditsIcon(), n > 0 ? fmt(n) : "Gratuit");

function toast(text, kind) {
    const el = $("toast");
    el.textContent = text;
    el.className = `toast on ${kind || ""}`;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { el.className = "toast"; }, 4000);
}

// ---------- Ouverture / fermeture ----------

function openStore(payload) {
    data = payload;
    const tabs = availableTabs();
    if (!tabs.some((t) => t.id === tab)) tab = tabs[0] ? tabs[0].id : null;
    $("store").classList.remove("hidden");
    paint();
}

function closeStore() {
    $("store").classList.add("hidden");
    $("modal").classList.add("hidden");
    nui("close");
}

$("close").addEventListener("click", closeStore);
document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape" || $("store").classList.contains("hidden")) return;
    if (!$("modal").classList.contains("hidden")) return $("modal").classList.add("hidden");
    closeStore();
});

// ---------- Rendu ----------

function availableTabs() {
    const c = data.categories || {};
    const list = [];
    if (c.premium || c.premium_plus) list.push({ id: "premium", label: "Abonnements", icon: "★" });
    if (data.catalogs.vehicles) list.push({ id: "vehicles", label: "Véhicules", icon: "🚗" });
    if (data.catalogs.packs) list.push({ id: "packs", label: "Packs", icon: "🎁" });
    if (data.catalogs.weapons) list.push({ id: "weapons", label: "Armes", icon: "🔫" });
    if (c.credits) list.push({ id: "credits", label: creditsName(), icon: "◆" });
    return list;
}

function paint() {
    $("balance").replaceChildren(h("span", { class: "muted" }, "Solde"), price(data.balance), h("small", null, creditsName()));
    $("banners").replaceChildren(...data.banners.map((b) => {
        const el = h("div", { class: "banner" }, b.image ? h("img", { src: b.image, alt: "", onerror: (e) => e.target.remove() }) : null, h("span", null, b.text));
        el.style.setProperty("--c", b.color);
        return el;
    }));
    $("banners").classList.toggle("empty", !data.banners.length);

    const tabs = availableTabs();
    $("nav").replaceChildren(...tabs.map((t) => h("button", { class: t.id === tab ? "on" : null, onclick: () => { tab = t.id; paint(); } }, h("i", null, t.icon), t.label)));

    let content;
    if (!tab) content = h("div", { class: "empty" }, "La boutique est fermée pour le moment.");
    else if (tab === "premium") content = premiumTab();
    else if (tab === "credits") content = creditsTab();
    else content = catalogTab(tab);
    $("main").replaceChildren(content);
}

// ---------- Abonnements ----------

function premiumTab() {
    const current = data.premium;
    const card = (tier) => {
        const t = data.tiers[tier];
        if (!t || !t.open) return null;
        const mine = current && current.tier === tier;
        const perks = [
            t.salaryMultiplier > 1 ? `Salaire +${Math.round((t.salaryMultiplier - 1) * 100)} %` : null,
            t.allowance > 0 ? `Aide de l'État : ${fmt(t.allowance)} ${data.currency} par paie` : null,
            t.characters > 1 ? `${t.characters} personnages` : null,
            t.garageSlots > 0 ? `${t.garageSlots} places de garage public` : null,
            t.farmMultiplier > 1 ? `Limite de farm ×${t.farmMultiplier}` : null,
            t.outfits > 0 ? `${t.outfits} tenues sauvegardées` : null,
        ].filter(Boolean);
        const el = h("div", { class: `tier${mine ? " mine" : ""}` },
            h("div", { class: "tier-head" }, h("b", null, t.label), mine ? h("span", { class: "tag" }, current.expires ? `Actif jusqu'au ${new Date(current.expires * 1000).toLocaleDateString("fr-FR")}` : "Actif à vie") : null),
            h("ul", null, perks.map((p) => h("li", null, p))),
            h("div", { class: "tier-foot" }, price(t.price), h("span", { class: "muted" }, `· ${data.days} jours`),
                h("button", { class: "buy", disabled: t.price <= 0, onclick: () => confirmBuy({ kind: "premium", tier }, `${t.label} (${data.days} jours)`, t.price, mine ? `Les ${data.days} jours s'ajoutent à votre abonnement.` : null) }, mine ? "Prolonger" : "Acheter")));
        el.style.setProperty("--c", t.color);
        return el;
    };
    return h("div", { class: "section" }, h("h2", null, "Abonnements"),
        h("p", { class: "muted" }, current ? `Vous êtes ${current.label}.` : "Soutenez le serveur et profitez d'avantages en jeu."),
        h("div", { class: "tiers" }, card("premium"), card("premium_plus")));
}

// ---------- Catalogues (véhicules, packs, armes) ----------

function productImage(kind, p) {
    if (p.image) return p.image;
    if (kind === "vehicles" && p.data.model) return `https://docs.fivem.net/vehicles/${p.data.model}.webp`;
    if (kind === "weapons" && p.data.item) return `nui://ox_inventory/web/images/${p.data.item}.png`;
    return null;
}

function catalogTab(kind) {
    const categories = (data.catalogs[kind] || []).filter((c) => c.products.length);
    if (!categories.length) return h("div", { class: "empty" }, "Rien à vendre ici pour le moment.");
    if (!categories.some((c) => c.id === categoryOf[kind])) categoryOf[kind] = categories[0].id;
    const category = categories.find((c) => c.id === categoryOf[kind]);

    const chips = h("div", { class: "cats" }, categories.map((c) => h("button", { class: c.id === category.id ? "on" : null, onclick: () => { categoryOf[kind] = c.id; paint(); } }, c.label, h("small", null, String(c.products.length)))));

    let list;
    if (kind === "packs") {
        list = h("div", { class: "packs" }, category.products.map((p) => {
            const content = [];
            if (p.data.cash) content.push(`${fmt(p.data.cash)} ${data.currency} en liquide`);
            if (p.data.bank) content.push(`${fmt(p.data.bank)} ${data.currency} en banque`);
            for (const i of p.data.items || []) content.push(`${i.count} × ${i.label || i.item}`);
            for (const v of p.data.vehicles || []) content.push(`Véhicule : ${v.label}`);
            return h("div", { class: "pack" },
                p.image ? h("img", { src: p.image, alt: "", onerror: (e) => e.target.remove() }) : null,
                h("div", { class: "pack-main" }, h("b", null, p.label), h("ul", null, content.map((c) => h("li", null, c)))),
                h("div", { class: "pack-foot" }, price(p.price), h("button", { class: "buy", onclick: () => confirmBuy({ kind, id: p.id }, p.label, p.price, content.join(" · ")) }, "Acheter")));
        }));
    } else {
        list = h("div", { class: "grid" }, category.products.map((p) => {
            const src = productImage(kind, p);
            return h("div", { class: "card" },
                h("div", { class: "pic" }, src ? h("img", { src, alt: "", onerror: (e) => e.target.remove() }) : null),
                h("b", null, p.label),
                kind === "weapons" && p.data.ammo ? h("span", { class: "muted" }, `+ ${p.data.ammo} munitions`) : null,
                h("div", { class: "card-foot" }, price(p.price), h("button", { class: "buy", onclick: () => confirmBuy({ kind, id: p.id }, p.label, p.price, kind === "vehicles" ? "Livré à votre garage." : "Livré dans votre inventaire.") }, "Acheter")));
        }));
    }
    return h("div", { class: "section" }, chips, list);
}

function creditsTab() {
    return h("div", { class: "section credits" },
        h("div", { class: "big-coin" }, creditsIcon()),
        h("h2", null, creditsName()),
        h("p", null, `Votre solde : ${fmt(data.balance)} ${creditsName()}.`),
        h("p", { class: "muted" }, `Les ${creditsName()} s'obtiennent auprès du staff (events, soutien du serveur). L'achat direct arrivera bientôt.`));
}

// ---------- Achat ----------

function confirmBuy(request, label, cost, detail) {
    const modal = $("modal");
    const after = data.balance - cost;
    const confirm = h("button", { class: "buy", disabled: after < 0 }, after < 0 ? "Solde insuffisant" : "Confirmer l'achat");
    confirm.addEventListener("click", async () => {
        confirm.disabled = true;
        confirm.textContent = "Achat en cours…";
        const res = await nui("buy", request).catch(() => null);
        modal.classList.add("hidden");
        if (!res || !res.ok) return toast((res && res.error) || "Achat impossible.", "error");
        data.balance = res.balance;
        if (res.premium !== undefined) data.premium = res.premium;
        toast(res.message, "ok");
        paint();
    });
    modal.replaceChildren(h("div", { class: "modal-card" },
        h("h3", null, label),
        detail ? h("p", { class: "muted" }, detail) : null,
        h("div", { class: "modal-rows" },
            h("div", null, h("span", null, "Prix"), price(cost)),
            h("div", null, h("span", null, "Solde après l'achat"), h("b", { class: after < 0 ? "bad" : null }, `${fmt(after)} ${creditsName()}`))),
        h("div", { class: "modal-actions" }, h("button", { class: "ghost", onclick: () => modal.classList.add("hidden") }, "Annuler"), confirm)));
    modal.classList.remove("hidden");
}

// ---------- Notification de la boutique ----------

let notifTimer = null;
function showNotif(n, duration) {
    const el = $("notif");
    const ends = n.endsAt ? new Date(n.endsAt * 1000).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" }) : null;
    el.style.setProperty("--c", n.color);
    el.replaceChildren(...[
        n.image ? h("img", { src: n.image, alt: "", onerror: (e) => e.target.remove() }) : null,
        h("div", null, h("b", null, n.title), h("span", null, n.text), h("small", null, `Boutique : [${n.key}] ou /boutique${ends ? ` · jusqu'à ${ends}` : ""}`)),
    ].filter(Boolean));
    el.classList.remove("hidden");
    clearTimeout(notifTimer);
    notifTimer = setTimeout(() => el.classList.add("hidden"), duration || 12000);
}

window.addEventListener("message", (event) => {
    const msg = event.data;
    if (!msg) return;
    if (msg.action === "open") openStore(msg.data);
    if (msg.action === "close") { $("store").classList.add("hidden"); $("modal").classList.add("hidden"); }
    if (msg.action === "notify") showNotif(msg.notification, msg.duration);
});

// ---------- Aperçu dans un navigateur (hors jeu) ----------

function demoNui(name, payload) {
    if (name === "buy") return { ok: true, message: "Achat réussi (aperçu).", balance: 1250 };
    return { ok: true };
}

if (!inGame) {
    openStore({
        credits: { name: "LCoins", image: "" }, currency: "$", days: 30, balance: 2750,
        banners: [{ text: "Nouveautés", color: "#f2c26b", image: "" }, { text: "-30 % sur les véhicules", color: "#ff6b6b", image: "" }],
        categories: { premium: true, premium_plus: true, vehicles: true, packs: true, weapons: true, credits: true },
        premium: { tier: "premium", label: "Premium", expires: Math.floor(Date.now() / 1000) + 12 * 86400 },
        tiers: {
            premium: { label: "Premium", color: "#f2c26b", open: true, price: 1000, salaryMultiplier: 1.1, allowance: 35, characters: 2, garageSlots: 5, farmMultiplier: 1, outfits: 10 },
            premium_plus: { label: "Premium+", color: "#9650ff", open: true, price: 2000, salaryMultiplier: 1.25, allowance: 70, characters: 3, garageSlots: 10, farmMultiplier: 1.25, outfits: 20 },
        },
        catalogs: {
            vehicles: [{ id: 6, label: "Sportive", products: [
                { id: 3, label: "Banshee", image: "", price: 2500, data: { model: "banshee" } },
                { id: 4, label: "Sultan RS", image: "", price: 1800, data: { model: "sultanrs" } },
                { id: 7, label: "Elegy RH8", image: "", price: 2000, data: { model: "elegy2" } },
            ] }, { id: 9, label: "Moto", products: [{ id: 8, label: "Bati 801", image: "", price: 1200, data: { model: "bati" } }] }],
            packs: [{ id: 1, label: "Starter", products: [
                { id: 1, label: "Pack Débutant", image: "", price: 500, data: { cash: 5000, items: [{ item: "phone", count: 1 }], vehicles: [] } },
                { id: 2, label: "Pack Essentiel", image: "", price: 1500, data: { cash: 10000, items: [{ item: "phone", count: 1 }], vehicles: [{ model: "sultan", label: "Sultan Classic" }] } },
            ] }],
            weapons: [{ id: 11, label: "Armes de poing", products: [{ id: 6, label: "Pistolet", image: "", price: 800, data: { item: "WEAPON_PISTOL", ammo: 24 } }] }],
        },
    });
    showNotif({ title: "Nouvelle offre", text: "Découvrez les dernières nouveautés dans la boutique !", color: "#f2c26b", key: "F1", endsAt: Math.floor(Date.now() / 1000) + 7200 }, 600000);
}
