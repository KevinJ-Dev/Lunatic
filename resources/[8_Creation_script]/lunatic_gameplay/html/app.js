"use strict";

// Documents de l'État de San Andreas : carte d'identité et permis de conduire (libellés américains)

const $ = (id) => document.getElementById(id);
const pad = (n) => String(n).padStart(2, "0");

// JJ/MM/AAAA (identité ESX) -> MM/DD/YYYY
function usDate(value) {
    const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(value || "");
    return m ? `${pad(m[2])}/${pad(m[1])}/${m[3]}` : "—";
}

// Date de remise (secondes) -> MM/DD/YYYY, avec des années en plus pour l'expiration
function stamp(seconds, years) {
    if (!seconds) return "—";
    const d = new Date(seconds * 1000);
    d.setFullYear(d.getFullYear() + (years || 0));
    return `${pad(d.getMonth() + 1)}/${pad(d.getDate())}/${d.getFullYear()}`;
}

// Centimètres -> pieds et pouces (5'-11")
function feet(cm) {
    const inches = Math.round(Number(cm) / 2.54);
    return inches ? `${Math.floor(inches / 12)}'-${pad(inches % 12)}"` : "—";
}

function show(identity) {
    const license = identity.kind === "license";
    const card = $("card");
    card.className = `card${license ? " license" : ""}`;
    $("doc").textContent = license ? "DRIVER LICENSE" : "IDENTIFICATION CARD";
    $("lNumber").textContent = license ? "DL" : "ID";
    $("number").textContent = `${license ? "D" : "I"}${String(identity.number || "").slice(-7)}`;
    $("exp").textContent = stamp(identity.issued, license ? 5 : 8);
    $("iss").textContent = stamp(identity.issued, 0);
    $("last").textContent = identity.lastName || "—";
    $("first").textContent = identity.firstName || "—";
    $("birth").textContent = usDate(identity.dateofbirth);
    $("sex").textContent = identity.sex === "m" ? "M" : identity.sex === "f" ? "F" : "—";
    $("height").textContent = feet(identity.height);
    $("nation").textContent = identity.nationality || "—";
    $("sign").textContent = `${identity.firstName || ""} ${identity.lastName || ""}`.trim();

    // Permis : classes (C voiture, M moto, A camion) et mentions (bateau, avion, hélico) à la place de la nationalité
    $("rowNation").classList.toggle("hidden", license);
    $("rowClass").classList.toggle("hidden", !license);
    if (license) {
        const owned = (identity.categories || []).filter((c) => c.owned);
        $("classes").textContent = owned.filter((c) => c.kind !== "end").map((c) => c.code).join(" ") || "NONE";
        $("ends").textContent = owned.filter((c) => c.kind === "end").map((c) => c.code).join(" ") || "NONE";
    }

    for (const id of ["photo", "ghost"]) {
        const holder = $(id);
        holder.replaceChildren();
        if (identity.photo) {
            const img = document.createElement("img");
            img.src = identity.photo;
            holder.append(img);
        }
    }
}

// ---------- Écran de mort ----------
// Le jeu envoie l'état (temps restant, secours, secouriste en route) ; les touches [G] et [E] sont lues par le jeu.

const death = { remaining: 0, timer: null };

// Distance du secouriste : en mètres sous 1 km, sinon en kilomètres
const distanceText = (m) => (m < 1000 ? `${Math.max(0, Math.round(m / 10) * 10)} m` : `${(m / 1000).toLocaleString("fr-FR", { maximumFractionDigits: 1 })} km`);

function paintDeath() {
    const left = Math.max(0, death.remaining);
    $("death-time").textContent = `${String(Math.floor(left / 60)).padStart(2, "0")}:${String(left % 60).padStart(2, "0")}`;
    $("death-rise").classList.toggle("ready", left <= 0);
    $("death-rise-label").textContent = left > 0 ? "Se relever" : "Se relever à l'hôpital";
}

function updateDeath(state) {
    if (typeof state.remaining === "number") death.remaining = state.remaining;
    const alert = $("death-alert");
    alert.classList.toggle("hidden", state.callMedic === false);
    alert.classList.toggle("done", state.called === true);
    alert.querySelector("span").textContent = state.called ? "Secours alertés" : "Alerter les secours";

    $("death-shade").classList.toggle("hidden", state.shade !== true);

    // Titre réglé dans le panel : le dernier mot en rouge
    if (typeof state.title === "string" && state.title.trim()) {
        const words = state.title.trim().split(/\s+/);
        const last = words.pop();
        const red = document.createElement("b");
        red.textContent = last;
        $("death-title").replaceChildren(words.length ? `${words.join(" ")} ` : "", red);
    }

    // Ligne au-dessus des touches : EMS en route, sinon état des secours (nombre d'EMS si le panel l'autorise)
    const info = $("death-info");
    const medics = Number(state.medics) || 0;
    const count = state.showMedics !== false;
    info.classList.toggle("coming", !!state.responder);
    if (state.responder) {
        info.innerHTML = state.showDistance !== false ? `Un EMS a pris votre appel · <b>à ${distanceText(state.responder.distance)}</b>` : "Un EMS a pris votre appel";
    } else if (state.medics === undefined) {
        info.textContent = ""; // pas encore de réponse du serveur
    } else if (state.called) {
        info.innerHTML = medics === 0 ? "Secours alertés : aucun EMS en service" : count ? `Secours alertés : en attente d'un EMS (<b>${medics}</b> en service)` : "Secours alertés : en attente d'un EMS";
    } else if (medics === 0) {
        info.textContent = "Aucun secouriste en service : délai réduit";
    } else {
        info.innerHTML = count ? `<b>${medics}</b> secouriste${medics > 1 ? "s" : ""} en service` : "";
    }
    paintDeath();
}

function showDeath(state) {
    $("death").classList.remove("hidden");
    updateDeath(state);
    clearInterval(death.timer);
    death.timer = setInterval(() => { death.remaining -= 1; paintDeath(); }, 1000);
}

function hideDeath() {
    clearInterval(death.timer);
    $("death").classList.add("hidden");
}

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "death") showDeath(msg);
    if (msg.action === "deathUpdate") updateDeath(msg);
    if (msg.action === "deathHide") hideDeath();
    if (msg.action === "idcard" && msg.identity) show(msg.identity);
    if (msg.action === "idcardHide") $("card").classList.add("hidden");
});
