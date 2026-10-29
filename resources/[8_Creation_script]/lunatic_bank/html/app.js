"use strict";

// Banque : vue globale (analyse, retrait / dépôt, transactions récentes, virement), historique complet, carte et plafonds.
// Distributeur : écran « Mon compte » (solde, carte, retrait, dépôt).
// Le jeu envoie l'état du compte ("open") ; chaque opération passe par le serveur, qui renvoie l'état à jour.

const $ = (id) => document.getElementById(id);
const all = (selector) => document.querySelectorAll(selector);
const resource = typeof GetParentResourceName === "function" ? GetParentResourceName() : null;

const KINDS = {
    deposit: "Dépôt", withdraw: "Retrait", transfer_in: "Virement reçu", transfer_out: "Virement émis", credit: "Crédit", debit: "Débit",
};
const LIMITS = [["withdraw", "Retraits"], ["deposit", "Dépôts"], ["transfer", "Virements émis"]];

let state = null;
let filter = "all";
let busy = false;

function nui(name, payload) {
    if (!resource) return Promise.resolve(demoReply(name, payload));
    return fetch(`https://${resource}/${name}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) })
        .then((r) => r.json()).catch(() => ({ error: "Banque indisponible." }));
}

function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
}

const money = (value) => `${Math.round(Number(value) || 0).toLocaleString("fr-FR")} $`;
const date = (seconds) => new Date(seconds * 1000).toLocaleDateString("fr-FR", { day: "2-digit", month: "2-digit", year: "2-digit" });
const time = (seconds) => new Date(seconds * 1000).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
const spacedIban = (iban) => String(iban || "").replace(/^(\D+)(\d{4})(\d{4})$/, "$1 $2 $3");

// ---------- Rendu ----------

function render() {
    if (!state) return;
    $("agency").textContent = state.bank;
    $("owner").textContent = state.name;
    $("avatar").textContent = (state.name || "?").split(" ").map((w) => w[0]).join("").slice(0, 2).toUpperCase();
    all("[data-balance]").forEach((n) => { n.textContent = money(state.balance); });
    all("[data-cash]").forEach((n) => { n.textContent = money(state.cash); });
    all("[data-card]").forEach(renderCard);
    all("[data-shortcuts]").forEach(renderShortcuts);
    renderLimits();
    if (state.atm) return;
    renderChart();
    renderTable($("recent"), state.history.slice(0, 8), false);
    renderTable($("history"), state.history.filter((t) => filter === "all" || (filter === "credit" ? t.amount > 0 : t.amount < 0)), true);
}

// Carte bancaire : couleur selon l'abonnement, IBAN, nom
function renderCard(node) {
    const card = state.card || { color: "green", label: "Carte verte" };
    node.classList.remove("green", "gold", "black");
    node.classList.add(card.color);
    const top = el("div", "card-top");
    const logo = el("span", "card-logo");
    logo.append("FL", el("b", null, "EE"), "CA");
    top.append(el("span", "chip"), logo);
    const bottom = el("div", "card-bottom");
    bottom.append(el("span", null, state.name), el("span", "card-tier", card.label));
    node.replaceChildren(top, el("div", "card-number", spacedIban(state.iban)), bottom);
}

function renderShortcuts(box) {
    const input = box.parentElement.querySelector("[data-amount]");
    box.replaceChildren(...(state.shortcuts || []).map((value) => {
        const button = el("button", null, money(value));
        button.addEventListener("click", () => { input.value = value; });
        return button;
    }));
}

function renderLimits() {
    const card = state.card;
    if (!card) return;
    $("tier").textContent = card.label;
    $("limits").replaceChildren(...LIMITS.map(([key, label]) => {
        const limit = card.limits[key] || { used: 0, max: 0 };
        const ratio = limit.max > 0 ? Math.min(1, limit.used / limit.max) : 1;
        const row = el("div", "limit");
        const head = el("div", "limit-head");
        head.append(el("strong", null, label), el("span", null, `${money(limit.used)} / ${money(limit.max)}`));
        const gauge = el("div", "gauge");
        const fill = el("i", ratio >= 1 ? "full" : null);
        fill.style.width = `${ratio * 100}%`;
        gauge.append(fill);
        row.append(head, gauge);
        return row;
    }));
}

// Échelle arrondie : 1, 2 ou 5 × une puissance de 10
function niceMax(value) {
    if (value <= 0) return 100;
    const power = Math.pow(10, Math.floor(Math.log10(value)));
    for (const step of [1, 2, 5, 10]) if (step * power >= value) return step * power;
    return 10 * power;
}

function renderChart() {
    const chart = $("chart");
    const bars = state.chart || [];
    const max = niceMax(Math.max(0, ...bars.map((b) => Math.max(b.credit, b.debit))));
    const axis = el("div", "axis");
    const children = [axis];

    for (let i = 0; i <= 4; i++) {
        axis.append(el("span", null, max * i / 4 >= 1000 ? `${(max * i / 4 / 1000).toLocaleString("fr-FR")} k` : String(max * i / 4)));
        const line = el("div", "grid-line");
        line.style.bottom = `calc(22px + (100% - 22px) * ${i / 4})`;
        children.push(line);
    }

    for (const bar of bars) {
        const group = el("div", "group");
        for (const kind of ["credit", "debit"]) {
            const column = el("div", `bar ${kind}`);
            column.style.height = `${(bar[kind] / max) * 100}%`;
            group.append(column);
        }
        group.append(el("span", "label", bar.label));
        const tip = el("div", "tip");
        tip.append(el("div", null, `Crédit : ${money(bar.credit)}`), el("div", null, `Débit : ${money(bar.debit)}`));
        group.append(tip);
        children.push(group);
    }

    chart.replaceChildren(...children);
    all("#periods button").forEach((b) => b.classList.toggle("on", b.dataset.period === state.period));
}

function renderTable(box, rows, detailed) {
    const head = el("div", "tr th");
    head.append(el("span", null, "Libellé"), el("span", null, "Date"), el("span", null, "Montant"), el("span", null, "Type"));
    if (!rows.length) return box.replaceChildren(head, el("div", "empty", "Aucune transaction."));

    box.replaceChildren(head, ...rows.map((t) => {
        const row = el("div", "tr");
        const who = el("div", "who");
        const credit = t.amount > 0;
        const text = el("div");
        text.append(el("span", null, t.label));
        const extra = [t.counterpart, detailed ? t.message : null].filter(Boolean).join(" · ");
        if (extra) text.append(el("small", null, extra));
        who.append(el("span", `icon ${credit ? "in" : "out"}`, credit ? "+" : "−"), text);
        row.append(who, el("span", "muted", `${date(t.at)} ${time(t.at)}`), el("span", credit ? "plus" : "minus", `${credit ? "+" : "−"}${money(Math.abs(t.amount))}`), el("span", "muted", KINDS[t.kind] || t.kind));
        return row;
    }));
}

function show(name) {
    for (const view of ["global", "transactions", "cards"]) $(`view-${view}`).classList.toggle("hidden", name !== view);
    all("#nav button").forEach((b) => b.classList.toggle("on", b.dataset.view === name));
}

// ---------- Opérations ----------

async function operate(name, payload) {
    if (busy) return null;
    busy = true;
    all(".btn").forEach((b) => { b.disabled = true; });
    const result = await nui(name, { ...payload, period: state.period });
    busy = false;
    all(".btn").forEach((b) => { b.disabled = false; });
    if (result && result.state) { state = result.state; render(); }
    return result && result.ok ? result : null;
}

// Retrait / dépôt : le montant est celui du champ du même bloc (guichet ou distributeur)
for (const [attribute, action] of [["data-withdraw", "withdraw"], ["data-deposit", "deposit"]]) {
    all(`[${attribute}]`).forEach((button) => button.addEventListener("click", async () => {
        const input = button.closest(".cash, .atm").querySelector("[data-amount]");
        if (await operate(action, { amount: Math.floor(Number(input.value) || 0) })) input.value = "";
    }));
}

$("send").addEventListener("click", async () => {
    const done = await operate("transfer", { iban: $("t-iban").value, amount: Math.floor(Number($("t-amount").value) || 0), message: $("t-message").value });
    if (done) ["t-iban", "t-amount", "t-message"].forEach((id) => { $(id).value = ""; });
});

all("#periods button").forEach((button) => button.addEventListener("click", async () => {
    const result = await nui("chart", { period: button.dataset.period });
    if (result && result.chart) { state.chart = result.chart; state.period = result.period; renderChart(); }
}));

all("#filters button").forEach((button) => button.addEventListener("click", () => {
    filter = button.dataset.filter;
    all("#filters button").forEach((b) => b.classList.toggle("on", b === button));
    render();
}));

all("#nav button").forEach((b) => b.addEventListener("click", () => show(b.dataset.view)));
all("[data-go]").forEach((b) => b.addEventListener("click", () => show(b.dataset.go)));
$("t-iban").addEventListener("input", (e) => { e.target.value = e.target.value.toUpperCase().replace(/\s/g, ""); });

// ---------- Ouverture / fermeture ----------

function close() {
    $("bank").classList.add("hidden");
    $("atm").classList.add("hidden");
    all("[data-amount]").forEach((input) => { input.value = ""; });
    state = null;
}

const closeAndTell = () => { close(); nui("close"); };
$("close").addEventListener("click", closeAndTell);
$("atm-close").addEventListener("click", closeAndTell);
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && state) closeAndTell(); });

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "open") {
        state = msg.state;
        filter = "all";
        show("global");
        $("bank").classList.toggle("hidden", !!state.atm);
        $("atm").classList.toggle("hidden", !state.atm);
        render();
    }
    if (msg.action === "close") close();
});

// ---------- Aperçu hors jeu (?atm pour le distributeur, ?gold / ?black pour les cartes) ----------

function demoReply(name, payload) {
    if (name === "chart") return { period: payload.period, chart: demoChart(payload.period === "year" ? 12 : payload.period === "month" ? 4 : 7) };
    return { error: "Aperçu hors jeu." };
}

function demoChart(count) {
    return Array.from({ length: count }, (_, i) => ({ label: `${String(20 + i).padStart(2, "0")}/10`, credit: 2000 + ((i * 3793) % 9000), debit: 800 + ((i * 2741) % 4000) }));
}

if (!resource) {
    const now = Math.floor(Date.now() / 1000);
    const query = location.search;
    const color = query.includes("black") ? "black" : query.includes("gold") ? "gold" : "green";
    const labels = { green: "Carte verte", gold: "Carte jaune", black: "Carte noire" };
    window.postMessage({ action: "open", state: {
        atm: query.includes("atm"), bank: "Fleeca Legion Square", name: "Bryan Anderson", iban: "LN04821937", balance: 25510, cash: 1340, period: "week", shortcuts: [100, 500, 1000, 5000], max: 1000000,
        card: { tier: "standard", color, label: labels[color], limits: { withdraw: { used: 1500, max: 5000 }, deposit: { used: 2000, max: 2000 }, transfer: { used: 2500, max: 10000 } } },
        chart: demoChart(7),
        history: [
            { kind: "transfer_out", amount: -2500, label: "Virement à Emma Clarke", counterpart: "LN55120387", message: "Loyer octobre", at: now - 3600 },
            { kind: "credit", amount: 1200, label: "Salaire : Mécano", at: now - 7200 },
            { kind: "withdraw", amount: -500, label: "Retrait au distributeur", at: now - 86400 },
            { kind: "debit", amount: -89, label: "Achat : LTD Gasoline", at: now - 90000 },
            { kind: "transfer_in", amount: 3000, label: "Virement de Lucas Moreau", counterpart: "LN88001234", message: "Remboursement", at: now - 172800 },
            { kind: "deposit", amount: 750, label: "Dépôt au guichet", at: now - 259200 },
        ],
    } }, "*");
}
