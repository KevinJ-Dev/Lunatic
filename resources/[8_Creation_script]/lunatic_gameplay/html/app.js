"use strict";

// Carte d'identité : modèles français, américain (San Andreas), belge et canadien

const MODELS = {
    fr: { title: "RÉPUBLIQUE FRANÇAISE", sub: "CARTE NATIONALE D'IDENTITÉ", foot: "IDFRA", labels: ["Nom", "Prénom(s)", "Sexe", "Taille", "Né(e) le", "N° du document", "Nationalité"] },
    us: { title: "STATE OF SAN ANDREAS", sub: "DRIVER LICENSE", foot: "USA · LOS SANTOS DMV", labels: ["Last name", "First name", "Sex", "Height", "Date of birth", "DL number", "Nationality"] },
    be: { title: "BELGIQUE · BELGIË · BELGIEN", sub: "CARTE D'IDENTITÉ · IDENTITEITSKAART", foot: "IDBEL", labels: ["Nom", "Prénoms", "Sexe", "Taille", "Date de naissance", "N° de carte", "Nationalité"] },
    ca: { title: "CANADA", sub: "PERMIS DE CONDUIRE · DRIVER'S LICENCE", foot: "CAN", labels: ["Nom / Last name", "Prénom / First name", "Sexe / Sex", "Taille / Height", "Naissance / Birth", "N° / No.", "Nationalité"] },
};

const $ = (id) => document.getElementById(id);

function show(identity) {
    const model = MODELS[identity.model] ? identity.model : "fr";
    const m = MODELS[model];
    const card = $("card");
    card.className = `card model-${model}`;
    $("title").textContent = m.title;
    $("sub").textContent = m.sub;
    $("foot").textContent = `${m.foot}<<${String(identity.lastName || "").toUpperCase()}<<${String(identity.firstName || "").toUpperCase()}<<<<<<${identity.number || ""}`;
    ["lLast", "lFirst", "lSex", "lHeight", "lBirth", "lNumber", "lNation"].forEach((id, i) => { $(id).textContent = m.labels[i]; });
    $("last").textContent = String(identity.lastName || "—").toUpperCase();
    $("first").textContent = identity.firstName || "—";
    $("sex").textContent = identity.sex === "m" ? "M" : identity.sex === "f" ? "F" : "—";
    $("height").textContent = identity.height ? `${identity.height} cm` : "—";
    $("birth").textContent = identity.dateofbirth || "—";
    $("nation").textContent = identity.nationality || "—";
    $("number").textContent = identity.number || "—";
    const photo = $("photo");
    photo.replaceChildren();
    if (identity.photo) {
        const img = document.createElement("img");
        img.src = identity.photo;
        photo.append(img);
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
