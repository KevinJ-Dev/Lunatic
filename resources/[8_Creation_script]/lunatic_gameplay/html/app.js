"use strict";

// Carte d'identité : modèles français, américain (San Andreas), belge et canadien

const MODELS = {
    fr: { title: "RÉPUBLIQUE FRANÇAISE", sub: "CARTE NATIONALE D'IDENTITÉ", foot: "IDFRA", labels: ["Nom", "Prénom(s)", "Sexe", "Taille", "Né(e) le", "N° du document"] },
    us: { title: "STATE OF SAN ANDREAS", sub: "DRIVER LICENSE", foot: "USA · LOS SANTOS DMV", labels: ["Last name", "First name", "Sex", "Height", "Date of birth", "DL number"] },
    be: { title: "BELGIQUE · BELGIË · BELGIEN", sub: "CARTE D'IDENTITÉ · IDENTITEITSKAART", foot: "IDBEL", labels: ["Nom", "Prénoms", "Sexe", "Taille", "Date de naissance", "N° de carte"] },
    ca: { title: "CANADA", sub: "PERMIS DE CONDUIRE · DRIVER'S LICENCE", foot: "CAN", labels: ["Nom / Last name", "Prénom / First name", "Sexe / Sex", "Taille / Height", "Naissance / Birth", "N° / No."] },
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
    ["lLast", "lFirst", "lSex", "lHeight", "lBirth", "lNumber"].forEach((id, i) => { $(id).textContent = m.labels[i]; });
    $("last").textContent = String(identity.lastName || "—").toUpperCase();
    $("first").textContent = identity.firstName || "—";
    $("sex").textContent = identity.sex === "m" ? "M" : identity.sex === "f" ? "F" : "—";
    $("height").textContent = identity.height ? `${identity.height} cm` : "—";
    $("birth").textContent = identity.dateofbirth || "—";
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
// Le jeu envoie l'état (temps restant, secouristes en service) ; les boutons renvoient au jeu, qui décide.

const death = { remaining: 0, timer: null };

async function post(name, payload) {
    try {
        await fetch(`https://${GetParentResourceName()}/${name}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) });
    } catch { /* aperçu navigateur */ }
}

function paintDeath() {
    const left = Math.max(0, death.remaining);
    $("death-time").textContent = `${String(Math.floor(left / 60)).padStart(2, "0")}:${String(left % 60).padStart(2, "0")}`;
    $("death-rise").disabled = left > 0;
    $("death-rise-label").textContent = left > 0 ? "Se relever" : "Se relever à l'hôpital";
}

function updateDeath(state) {
    if (typeof state.remaining === "number") death.remaining = state.remaining;
    const alert = $("death-alert");
    alert.classList.toggle("hidden", state.callMedic === false);
    alert.classList.toggle("done", state.called === true);
    alert.querySelector("span").textContent = state.called ? "Secours alertés" : "Alerter les secours";
    const medics = Number(state.medics) || 0;
    // Pas encore de réponse du serveur : rien d'affiché sous le bouton
    if (state.medics === undefined) $("death-medics").textContent = "";
    else $("death-medics").innerHTML = medics > 0
        ? `<b>${medics}</b> secouriste${medics > 1 ? "s" : ""} en service`
        : "Aucun secouriste en service : délai réduit";
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

$("death-alert").addEventListener("click", () => { if (!$("death-alert").classList.contains("done")) post("deathAlert"); });
$("death-rise").addEventListener("click", () => { if (!$("death-rise").disabled) post("deathRise"); });

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "death") showDeath(msg);
    if (msg.action === "deathUpdate") updateDeath(msg);
    if (msg.action === "deathHide") hideDeath();
    if (msg.action === "idcard" && msg.identity) show(msg.identity);
    if (msg.action === "idcardHide") $("card").classList.add("hidden");
});
