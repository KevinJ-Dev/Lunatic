"use strict";

// Banque : vue globale (analyse, retrait / dépôt, transactions récentes, virement) et historique complet.
// Le jeu envoie l'état du compte ("open") ; chaque opération passe par le serveur, qui renvoie l'état à jour.

const $ = (id) => document.getElementById(id);
const resource = typeof GetParentResourceName === "function" ? GetParentResourceName() : null;

const KINDS = {
    deposit: "Dépôt", withdraw: "Retrait", transfer_in: "Virement reçu", transfer_out: "Virement émis", credit: "Crédit", debit: "Débit",
};

let state = null;
let view = "global";
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
    $("balance").textContent = money(state.balance);
    $("cash").textContent = money(state.cash);
    $("card-iban").textContent = spacedIban(state.iban);
    $("card-name").textContent = state.name;
    renderShortcuts();
    renderChart();
    renderTable($("recent"), state.history.slice(0, 8), false);
    renderTable($("history"), state.history.filter((t) => filter === "all" || (filter === "credit" ? t.amount > 0 : t.amount < 0)), true);
}

function renderShortcuts() {
    const box = $("shortcuts");
    box.replaceChildren(...(state.shortcuts || []).map((value) => {
        const button = el("button", null, money(value));
        button.addEventListener("click", () => { $("amount").value = value; });
        return button;
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
    document.querySelectorAll("#periods button").forEach((b) => b.classList.toggle("on", b.dataset.period === state.period));
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
    view = name;
    $("view-global").classList.toggle("hidden", name !== "global");
    $("view-transactions").classList.toggle("hidden", name !== "transactions");
    document.querySelectorAll("#nav button").forEach((b) => b.classList.toggle("on", b.dataset.view === name));
}

// ---------- Opérations ----------

async function operate(name, payload) {
    if (busy) return null;
    busy = true;
    document.querySelectorAll(".btn").forEach((b) => { b.disabled = true; });
    const result = await nui(name, { ...payload, period: state.period });
    busy = false;
    document.querySelectorAll(".btn").forEach((b) => { b.disabled = false; });
    if (result && result.state) { state = result.state; render(); }
    return result && result.ok ? result : null;
}

const amountValue = (id) => Math.floor(Number($(id).value) || 0);

$("withdraw").addEventListener("click", async () => { if (await operate("withdraw", { amount: amountValue("amount") })) $("amount").value = ""; });
$("deposit").addEventListener("click", async () => { if (await operate("deposit", { amount: amountValue("amount") })) $("amount").value = ""; });
$("send").addEventListener("click", async () => {
    const done = await operate("transfer", { iban: $("t-iban").value, amount: amountValue("t-amount"), message: $("t-message").value });
    if (done) ["t-iban", "t-amount", "t-message"].forEach((id) => { $(id).value = ""; });
});

document.querySelectorAll("#periods button").forEach((button) => button.addEventListener("click", async () => {
    const result = await nui("chart", { period: button.dataset.period });
    if (result && result.chart) { state.chart = result.chart; state.period = result.period; renderChart(); }
}));

document.querySelectorAll("#filters button").forEach((button) => button.addEventListener("click", () => {
    filter = button.dataset.filter;
    document.querySelectorAll("#filters button").forEach((b) => b.classList.toggle("on", b === button));
    render();
}));

document.querySelectorAll("#nav button").forEach((b) => b.addEventListener("click", () => show(b.dataset.view)));
document.querySelectorAll("[data-go]").forEach((b) => b.addEventListener("click", () => show(b.dataset.go)));
$("t-iban").addEventListener("input", (e) => { e.target.value = e.target.value.toUpperCase().replace(/\s/g, ""); });

// ---------- Ouverture / fermeture ----------

function close() {
    $("bank").classList.add("hidden");
    state = null;
}

$("close").addEventListener("click", () => { close(); nui("close"); });
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && state) { close(); nui("close"); } });

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "open") {
        state = msg.state;
        filter = "all";
        show("global");
        $("bank").classList.remove("hidden");
        render();
    }
    if (msg.action === "close") close();
});

// ---------- Aperçu hors jeu ----------

function demoReply(name, payload) {
    if (name === "chart") return { period: payload.period, chart: demoChart(payload.period === "year" ? 12 : payload.period === "month" ? 4 : 7) };
    return { error: "Aperçu hors jeu." };
}

function demoChart(count) {
    return Array.from({ length: count }, (_, i) => ({ label: `${String(20 + i).padStart(2, "0")}/10`, credit: 2000 + ((i * 3793) % 9000), debit: 800 + ((i * 2741) % 4000) }));
}

if (!resource) {
    const now = Math.floor(Date.now() / 1000);
    window.postMessage({ action: "open", state: {
        bank: "Fleeca Legion Square", name: "Bryan Anderson", iban: "LN04821937", balance: 25510, cash: 1340, period: "week", shortcuts: [100, 500, 1000, 5000], max: 1000000,
        chart: demoChart(7),
        history: [
            { kind: "transfer_out", amount: -2500, label: "Virement à Emma Clarke", counterpart: "LN55120387", message: "Loyer octobre", at: now - 3600 },
            { kind: "credit", amount: 1200, label: "Salaire : Mécano", at: now - 7200 },
            { kind: "withdraw", amount: -500, label: "Retrait au guichet", at: now - 86400 },
            { kind: "debit", amount: -89, label: "Achat : LTD Gasoline", at: now - 90000 },
            { kind: "transfer_in", amount: 3000, label: "Virement de Lucas Moreau", counterpart: "LN88001234", message: "Remboursement", at: now - 172800 },
            { kind: "deposit", amount: 750, label: "Dépôt au guichet", at: now - 259200 },
        ],
    } }, "*");
}
