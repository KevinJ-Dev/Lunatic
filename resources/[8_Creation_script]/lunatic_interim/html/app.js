"use strict";

// Job Center (doc Vision « Jobs de farm ») : fiche du métier choisi (image, missions, salaire, durée, participants),
// tenue essayée sur le personnage par le jeu, Accepter / Quitter le métier ; logos des métiers en bas à droite.
// Staff : enregistrer la tenue portée en ouvrant comme tenue du métier.

const $ = (id) => document.getElementById(id);
const inGame = typeof GetParentResourceName === "function";
const resource = inGame ? GetParentResourceName() : "lunatic_interim";

let data = null;
let selected = null;
let busy = false;

function nui(name, payload) {
    if (!inGame) return Promise.resolve({ ok: false, error: "Aperçu hors jeu." });
    return fetch(`https://${resource}/${name}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) })
        .then((r) => r.json()).catch(() => ({ ok: false, error: "Job Center indisponible." }));
}

function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
        if (value === null || value === undefined || value === false) continue;
        if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
        else if (key === "class") el.className = value;
        else if (key === "style") el.style.cssText = value;
        else el.setAttribute(key, value === true ? "" : value);
    }
    for (const child of children.flat(Infinity)) {
        if (child === null || child === undefined || child === false) continue;
        el.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return el;
}

function toast(text) {
    const el = $("toast");
    el.textContent = text;
    el.classList.add("on");
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => el.classList.remove("on"), 3500);
}

const money = (n) => `${Math.round(n).toLocaleString("fr-FR")} ${data.currency || "$"}`;
const initials = (label) => label.split(/\s+/).filter((w) => w.length > 2 || /^[A-Z]/.test(w)).map((w) => w[0]).join("").slice(0, 2).toUpperCase() || label[0];
const jobOf = (id) => data.jobs.find((j) => j.id === id);

function open(payload) {
    data = payload;
    busy = false;
    // Bannière réglable (tuile Images : Job Center), sinon le bandeau Job Center / Intérim
    $("brand").style.backgroundImage = data.banner ? `linear-gradient(90deg, #000a, #0003), url("${data.banner}")` : "";
    $("brand").classList.toggle("with-image", !!data.banner);
    $("center").classList.remove("hidden");
    select(data.current || data.jobs[0].id);
}

function select(id) {
    selected = id;
    nui("preview", { id });
    paint();
}

function paint() {
    paintSheet();
    paintLogos();
}

function paintSheet() {
    const job = jobOf(selected);
    const mine = data.current === job.id;
    const picture = h("div", { class: "picture", style: `--job:${job.color}` });
    if (job.image) picture.style.backgroundImage = `linear-gradient(180deg, #0000 55%, #0008), url("${job.image}")`;
    else picture.append(h("span", null, initials(job.company)));

    const actions = [];
    if (mine) {
        actions.push(h("div", { class: "current" }, "✓ Votre métier actuel"));
        actions.push(h("button", { class: "btn ghost", disabled: busy, onclick: quit }, "Quitter le métier"));
    } else {
        if (data.current) actions.push(h("p", { class: "note" }, `Il remplacera votre métier d'intérim actuel (${jobOf(data.current).label}).`));
        if (data.mainJob) actions.push(h("p", { class: "note ok" }, `Votre poste fixe (${data.mainJob}) est conservé : l'intérim s'y ajoute.`));
        actions.push(h("button", { class: "btn", disabled: busy, onclick: accept }, "Accepter le métier"));
    }
    if (data.staff) {
        actions.push(h("div", { class: "staff-row" },
            h("button", { class: "btn ghost small", disabled: busy, title: "Magasin de vêtements libre, homme ou femme ; validez pour revenir ici", onclick: dress }, "Staff : habiller (homme / femme)"),
            data.model ? h("button", { class: "btn ghost small", disabled: busy, title: "La tenue que vous portiez en ouvrant le Job Center devient celle du métier", onclick: saveOutfit },
                `Enregistrer ma tenue (${data.model === "f" ? "femme" : "homme"})${job.hasOutfit ? " · déjà réglée" : ""}`) : null));
    }

    $("sheet").replaceChildren(
        h("div", { class: "title" }, h("b", null, job.label), h("small", null, job.company)),
        picture,
        h("div", { class: "card", style: `--job:${job.color}` }, h("h4", null, h("i"), "Missions"), h("ol", null, job.missions.map((m) => h("li", null, m)))),
        h("div", { class: "facts" },
            h("div", { class: "card", style: `--job:${job.color}` }, h("h4", null, h("i"), "Salaire"), h("div", { class: "value money" }, `${money(job.salary)} / mission`)),
            h("div", { class: "card", style: `--job:${job.color}` }, h("h4", null, h("i"), "Durée approximative"), h("div", { class: "value" }, `${job.duration} minutes`))),
        h("div", { class: "card", style: `--job:${job.color}` }, h("h4", null, h("i"), "Nombre de participants"), h("div", { class: "value" }, job.participants)),
        h("div", { class: "actions" }, actions),
    );
}

function paintLogos() {
    $("logos").replaceChildren(...data.jobs.map((job) => {
        const content = job.logo ? h("img", { src: job.logo, alt: "" }) : h("span", { class: "dot", style: `--job:${job.color}` }, initials(job.company));
        if (job.logo) content.addEventListener("error", () => content.replaceWith(h("span", { class: "dot", style: `--job:${job.color}` }, initials(job.company))));
        return h("button", { class: `logo${job.id === selected ? " on" : ""}`, title: `${job.label} · ${job.company}`, onclick: () => select(job.id) },
            content, data.current === job.id ? h("span", { class: "mine" }) : null);
    }));
}

async function accept() {
    if (busy) return;
    busy = true;
    paintSheet();
    const res = await nui("accept", { id: selected });
    busy = false;
    if (!res || !res.ok) {
        if (data) paintSheet();
        return toast((res && res.error) || "Action impossible.");
    }
    hide();
}

async function quit() {
    if (busy) return;
    busy = true;
    paintSheet();
    const res = await nui("quit");
    busy = false;
    if (!res || !res.ok) {
        if (data) paintSheet();
        return toast((res && res.error) || "Action impossible.");
    }
    hide();
}

async function saveOutfit() {
    if (busy) return;
    busy = true;
    paintSheet();
    const res = await nui("saveOutfit", { id: selected });
    busy = false;
    if (res && res.center) data = Object.assign(res.center, { current: data.current });
    paintSheet();
    toast(res && res.ok ? "Tenue du métier enregistrée." : (res && res.error) || "Enregistrement impossible.");
}

async function dress() {
    if (busy) return;
    hide();
    const res = await nui("dress");
    if (res && !res.ok && res.error) toast(res.error);
}

function hide() {
    $("center").classList.add("hidden");
    data = null;
}

$("close").addEventListener("click", () => { hide(); nui("close"); });
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && data) { hide(); nui("close"); } });

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "open") open(msg.center);
    if (msg.action === "close") hide();
});

// ---------- Aperçu navigateur ----------

if (!inGame) {
    const job = (id, label, company, color, salary, duration, participants, missions) => ({ id, label, company, color, salary, duration, participants, missions, hasOutfit: false });
    window.postMessage({ action: "open", center: { currency: "$", staff: true, model: "m", current: "miner", otherJob: null, jobs: [
        job("pilot", "Pilote d'avion", "Adios Airlines", "#f5b301", 400, 12, "1 personne", ["Récupère un avion au terminal de l'aéroport.", "Effectue un vol de transport vers une autre piste.", "Atterris en toute sécurité pour encaisser ta paie."]),
        job("miner", "Mineur", "LS Mining", "#a0784a", 280, 10, "1 personne", ["Prends ton équipement et descends dans la mine.", "Récolte un maximum de minerais.", "Remonte à la surface pour être payé."]),
        job("garbage", "Éboueur", "Hobo", "#2f9e44", 300, 15, "1 à 4 personnes", ["Récupère un camion poubelle au dépôt.", "Parcours la ville pour vider les bacs.", "Dépose les déchets à la décharge."]),
        job("fuel", "Pompiste", "Globe Oil", "#1c7ed6", 340, 12, "1 personne", ["Récupère le camion-citerne.", "Ravitaille les stations.", "Ramène la citerne."]),
        job("gopostal", "Facteur", "GoPostal", "#d6336c", 240, 10, "1 personne", ["Fourgon.", "Courrier.", "Retour."]),
        job("fisher", "Pêcheur", "Pêcheries de Paleto", "#1098ad", 260, 12, "1 personne", ["Canne.", "Pêche.", "Marché."]),
    ] } }, "*");
}
