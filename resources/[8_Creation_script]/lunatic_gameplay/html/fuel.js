"use strict";

// Pompe à essence (doc Vision) : volume et prix en direct, moyen de paiement, Valider puis Stop.
// Le jeu lance et arrête le plein ; le serveur mesure les litres versés et fait payer à la fin.

const fuelResource = typeof GetParentResourceName === "function" ? GetParentResourceName() : null;
const fuel = { open: false, state: "idle", account: "money", price: 3, rate: 1.5, max: 0, started: 0, liters: 0, data: null, frame: null };

function fuelNui(name, payload) {
    if (!fuelResource) return Promise.resolve({});
    return fetch(`https://${fuelResource}/${name}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) }).then((r) => r.json()).catch(() => ({}));
}

const fuelMoney = (n) => `${Math.round(n).toLocaleString("fr-FR")} ${fuel.data.currency || "$"}`;

function paintFuelCounters() {
    $("fuelVolume").textContent = fuel.liters.toFixed(2);
    $("fuelPrice").textContent = (fuel.liters * fuel.price).toFixed(2);
}

function paintFuel() {
    const d = fuel.data;
    const pay = $("fuelPay");
    pay.replaceChildren();
    for (const [account, label, balance] of [["money", "Espèces", d.cash], ["bank", "Carte bancaire", d.bank]]) {
        const button = document.createElement("button");
        button.className = `fuel-account${fuel.account === account ? " on" : ""}`;
        button.disabled = fuel.state !== "idle";
        button.innerHTML = `<span>${label}</span><small>${fuelMoney(balance || 0)}</small>`;
        button.onclick = () => { fuel.account = account; paintFuel(); };
        pay.append(button);
    }
    const go = $("fuelGo");
    go.disabled = fuel.state === "starting";
    go.className = `fuel-go${fuel.state === "running" ? " stop" : ""}`;
    go.textContent = fuel.state === "running" ? "Stop" : fuel.state === "done" ? "Terminé" : "Valider";
    go.disabled = fuel.state === "starting" || fuel.state === "done";
    $("fuelClose").classList.toggle("hidden", fuel.state === "running" || fuel.state === "starting");
    $("fuelInfo").textContent = fuel.state === "done"
        ? (fuel.liters > 0 ? `Payé : ${fuelMoney(fuel.liters * fuel.price)} pour ${fuel.liters.toFixed(0)} L.` : "Aucun litre versé.")
        : `Réservoir à ${d.level} % · ${String(fuel.price).replace(".", ",")} ${d.currency || "$"} le litre`;
    paintFuelCounters();
}

function tickFuel() {
    if (fuel.state !== "running") return;
    fuel.liters = Math.min(fuel.max, ((Date.now() - fuel.started) / 1000) * fuel.rate);
    paintFuelCounters();
    fuel.frame = requestAnimationFrame(tickFuel);
}

function fuelGo() {
    if (fuel.state === "idle") {
        fuel.state = "starting";
        paintFuel();
        fuelNui("fuelStart", { account: fuel.account });
    } else if (fuel.state === "running") {
        fuel.state = "stopping";
        cancelAnimationFrame(fuel.frame);
        fuelNui("fuelStop", { liters: Math.floor(fuel.liters) });
    }
}

function closeFuel() {
    if (!fuel.open || fuel.state === "running" || fuel.state === "starting") return;
    fuel.open = false;
    $("fuel").classList.add("hidden");
    fuelNui("fuelClose");
}

$("fuelGo").addEventListener("click", fuelGo);
$("fuelClose").addEventListener("click", closeFuel);
document.addEventListener("keydown", (e) => {
    if (!fuel.open) return;
    if (e.key === "Escape") {
        if (fuel.state === "running") fuelGo();
        else closeFuel();
    } else if (e.key === "Enter" && fuel.state === "idle") fuelGo();
});

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "fuelOpen") {
        fuel.open = true;
        fuel.data = msg;
        fuel.state = "idle";
        fuel.price = Number(msg.price) || 0;
        fuel.liters = 0;
        fuel.account = (msg.cash || 0) >= fuel.price ? "money" : "bank";
        const banner = $("fuelBanner");
        banner.style.backgroundImage = msg.banner ? `linear-gradient(180deg, #0000 40%, #0007), url("${msg.banner}")` : "";
        banner.classList.toggle("with-image", !!msg.banner);
        $("fuelCurrency").textContent = msg.currency || "$";
        $("fuel").classList.remove("hidden");
        paintFuel();
    } else if (msg.action === "fuelRunning") {
        fuel.state = "running";
        fuel.max = Number(msg.max) || 0;
        fuel.rate = Number(msg.rate) || 1.5;
        fuel.price = Number(msg.price) || fuel.price;
        fuel.started = Date.now();
        paintFuel();
        tickFuel();
    } else if (msg.action === "fuelDone") {
        cancelAnimationFrame(fuel.frame);
        fuel.state = "done";
        fuel.liters = Number(msg.liters) || 0;
        if (fuel.liters > 0 && msg.cost != null && fuel.liters) fuel.price = msg.cost / fuel.liters;
        paintFuel();
        $("fuelClose").classList.remove("hidden");
    } else if (msg.action === "fuelError") {
        fuel.state = "idle";
        paintFuel();
    } else if (msg.action === "fuelHide") {
        fuel.open = false;
        cancelAnimationFrame(fuel.frame);
        $("fuel").classList.add("hidden");
    }
});

// Aperçu hors jeu : index.html#fuel
if (!fuelResource && location.hash.includes("fuel")) {
    window.postMessage({ action: "fuelOpen", price: 3, level: 42, cash: 420, bank: 15800, currency: "$" }, "*");
}
