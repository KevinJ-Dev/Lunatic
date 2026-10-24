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

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "idcard" && msg.identity) show(msg.identity);
    if (msg.action === "idcardHide") $("card").classList.add("hidden");
});
