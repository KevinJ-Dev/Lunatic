"use strict";

// Création de personnage (lunatic_creator) : l'interface tient l'état, le jeu l'applique en direct.

const $ = (id) => document.getElementById(id);
const inGame = typeof GetParentResourceName === "function";
const resource = inGame ? GetParentResourceName() : "lunatic_creator";

function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
        if (value === null || value === undefined || value === false) continue;
        if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
        else if (key === "class") el.className = value;
        else el.setAttribute(key, value === true ? "" : value);
    }
    for (const child of children.flat(Infinity)) {
        if (child === null || child === undefined || child === false) continue;
        el.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return el;
}

async function nui(name, payload) {
    if (!inGame) return demo(name, payload);
    const res = await fetch(`https://${resource}/${name}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) });
    return res.json();
}

function toast(text) {
    const el = $("toast");
    el.textContent = text;
    el.classList.add("on");
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => el.classList.remove("on"), 3500);
}

// ---------- Données GTA ----------

// Portrait d'un parent (masqué tant que la texture du jeu n'est pas chargée)
const portraitImg = (id) => h("img", { src: portrait(id), alt: "", onerror: (e) => { e.target.style.visibility = "hidden"; } });

const FATHERS = [["Benjamin", 0], ["Daniel", 1], ["Joshua", 2], ["Noah", 3], ["Andrew", 4], ["Juan", 5], ["Alex", 6], ["Isaac", 7], ["Evan", 8], ["Ethan", 9], ["Vincent", 10], ["Angel", 11], ["Diego", 12], ["Adrian", 13], ["Gabriel", 14], ["Michael", 15], ["Santiago", 16], ["Kevin", 17], ["Louis", 18], ["Samuel", 19], ["Anthony", 20], ["Claude", 42], ["Niko", 43], ["John", 44]];
const MOTHERS = [["Hannah", 21], ["Aubrey", 22], ["Jasmine", 23], ["Gisele", 24], ["Amelia", 25], ["Isabella", 26], ["Zoe", 27], ["Ava", 28], ["Camila", 29], ["Violet", 30], ["Sophia", 31], ["Evelyn", 32], ["Nicole", 33], ["Ashley", 34], ["Grace", 35], ["Brianna", 36], ["Natalie", 37], ["Olivia", 38], ["Elizabeth", 39], ["Charlotte", 40], ["Emma", 41], ["Misty", 45]];

// Portraits du jeu (dictionnaire char_creator_portraits)
function portrait(id) {
    let key;
    if (id <= 20) key = `male_${id}`;
    else if (id <= 41) key = `female_${id - 21}`;
    else if (id <= 44) key = `special_male_${id - 42}`;
    else key = "special_female_0";
    return `https://nui-img/char_creator_portraits/${key}`;
}

const EYE_COLORS = [["Vert", "#3f7a3a"], ["Émeraude", "#2d8c62"], ["Bleu clair", "#7fb4d8"], ["Bleu océan", "#2f6aa3"], ["Brun clair", "#9a6b3b"], ["Brun foncé", "#5a3a22"], ["Noisette", "#8a6a2c"], ["Gris foncé", "#5c6066"], ["Gris clair", "#9aa1a8"], ["Rose", "#c98aa3"], ["Jaune", "#c9b13a"], ["Violet", "#7a4fa8"], ["Noir", "#151515"], ["Gris", "#7d7d7d"]];

// Étapes de la création
const STEPS = [
    { id: "identity", label: "Identité", icon: "M12 3a7 7 0 0 0-7 7v3M19 10a7 7 0 0 0-7-7M8.5 21c.6-2 1-4.3 1-7a2.5 2.5 0 0 1 5 0c0 1.5-.1 3-.4 4.4M5 16c.4-1.2.6-2.6.6-4M12 10v4c0 2.6-.4 5-1.2 7M18.6 17c.3-1.6.4-3.3.4-5" },
    { id: "look", label: "Apparence", icon: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21c0-4.4 3.6-8 8-8s8 3.6 8 8" },
    { id: "style", label: "Coiffure et style", icon: "M5 13c0-5 3-9 7-9s7 4 7 9v6M5 13v6M9 8c1 2 4 3 8 3" },
    { id: "clothes", label: "Vêtements", icon: "M8 3 3 6l2 4 2-1v12h10V9l2 1 2-4-5-3a4 4 0 0 1-8 0z" },
    { id: "spawn", label: "Lieu d'apparition", icon: "M12 21s-7-6.5-7-12a7 7 0 0 1 14 0c0 5.5-7 12-7 12zM12 11a2 2 0 1 0 0-4 2 2 0 0 0 0 4z" },
];

// ---------- État ----------

let appearance = null;
let options = null;
let settings = null;
let stepIndex = 0;
const category = { look: "parents", style: "hair", clothes: "1" }; // catégorie ouverte dans chaque étape à panneaux
const PANEL_STEPS = ["look", "style", "clothes"]; // étapes avec cartes à gauche et styles à droite
let thumbs = {}; // miniatures disponibles : { male: { hair: Set }, ... } (thumbs/index.json, outil photo staff)
const identity = { lastname: "", firstname: "", day: 0, month: 0, year: 2000, nationality: "", height: 178 };
let identityErrors = {}; // section -> message, rempli quand l'identité est refusée

let sendTimer = null;
function pushAppearance() {
    clearTimeout(sendTimer);
    sendTimer = setTimeout(() => nui("appearance", appearance), 40);
}

const svg = (path) => {
    const el = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    el.setAttribute("viewBox", "0 0 24 24");
    el.innerHTML = `<path d="${path}"/>`;
    return el;
};

// ---------- Rendu ----------

function paint() {
    $("steps").replaceChildren(...STEPS.map((s, i) => h("span", {
        class: `tab${i === stepIndex ? " on" : ""}${i < stepIndex ? " done" : ""}`,
    }, svg(s.icon), h("b", null, s.label))));

    const step = STEPS[stepIndex];
    const stepScroll = $("step").scrollTop;
    const body = { identity: identityStep, look: lookStep, style: styleStep, clothes: clothesStep, spawn: spawnStep }[step.id]();
    $("step").replaceChildren(h("h2", null, step.label), body);
    $("step").scrollTop = stepScroll;
    paintSide();
    $("prev").style.visibility = stepIndex === 0 ? "hidden" : "visible";
    $("next").textContent = stepIndex === lastStep() ? "Terminer" : "Suivant";

    $("cams").replaceChildren(...Array.from({ length: settings.cameras }, (_, i) => h("button", { class: `cam${camera === i + 1 ? " on" : ""}`, title: ["Visage", "Buste", "Corps"][i], onclick: () => setCamera(i + 1) }, String(i + 1))));
}

const lastStep = () => STEPS.length - 1;

function go(index) {
    if (index > stepIndex && stepIndex === 0 && !checkIdentity()) return;
    stepIndex = index;
    paint();
    $("step").scrollTop = 0;
    stepCamera();
    saveDraft();
}

function stepCamera() {
    const id = STEPS[stepIndex].id;
    if (PANEL_STEPS.includes(id)) setCamera(categoryOf(id).camera || 1);
}

// Brouillon envoyé au serveur à chaque étape : la création reprend là après un crash ou une déconnexion
function saveDraft() {
    const { lastname, firstname, day, month, year, nationality, height } = identity;
    nui("draft", { step: stepIndex, identity: { lastname, firstname, day, month, year, nationality, height } });
}

// Reprise d'un brouillon : seuls les champs connus, avec le bon type
function restoreDraft(draft) {
    const saved = draft && typeof draft.identity === "object" && draft.identity ? draft.identity : {};
    for (const key of ["lastname", "firstname", "nationality"]) if (typeof saved[key] === "string") identity[key] = saved[key].slice(0, 40);
    for (const key of ["day", "month", "year", "height"]) if (Number.isInteger(saved[key])) identity[key] = saved[key];
    if (!settings.nationalities.includes(identity.nationality)) identity.nationality = "";
    if (identity.month < 0 || identity.month > 11) identity.month = 0;
    const step = Number.isInteger(draft && draft.step) ? Math.max(0, Math.min(lastStep(), draft.step)) : 0;
    // Au-delà de l'identité, elle doit toujours être valide (sinon retour à la fiche)
    stepIndex = step > 0 && checkIdentity() ? step : 0;
}

// Bannière et logo réglés dans le panel staff
function applyBranding(branding) {
    const banner = document.querySelector(".banner");
    const logo = document.querySelector(".banner-logo");
    banner.style.backgroundImage = branding && branding.banner ? `linear-gradient(90deg, #100c18e6, #100c1866), url("${branding.banner}")` : "";
    banner.classList.toggle("with-image", !!(branding && branding.banner));
    logo.classList.toggle("hidden", !(branding && branding.logo));
    if (branding && branding.logo) logo.src = branding.logo;
}

let camera = 2;
function setCamera(index) {
    if (camera === index) return;
    camera = index;
    nui("camera", { index });
    paint();
}

// ---------- 1. Identité ----------

const MONTHS = ["Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"];
const NAME_RULE = /^[A-Za-zÀ-ÖØ-öø-ÿ]+(?:[ '-][A-Za-zÀ-ÖØ-öø-ÿ]+)*$/;
let nationalityOpen = false;

const pick = (list) => list[Math.floor(Math.random() * list.length)];
const randomInt = (min, max) => min + Math.floor(Math.random() * (max - min + 1));
const pad = (n) => String(n).padStart(2, "0");
const daysIn = (year, month) => new Date(year, month + 1, 0).getDate();
const dateOfBirth = () => `${pad(identity.day)}/${pad(identity.month + 1)}/${identity.year}`;

// Âge exact à aujourd'hui (même calcul que le serveur)
function ageAt(year, month, day) {
    const now = new Date();
    let age = now.getFullYear() - year;
    if (now.getMonth() < month || (now.getMonth() === month && now.getDate() < day)) age -= 1;
    return age;
}
const ageOk = (year, month, day) => { const age = ageAt(year, month, day); return age >= settings.age.min && age <= settings.age.max; };
const yearBounds = () => { const now = new Date().getFullYear(); return { min: now - settings.age.max - 1, max: now - settings.age.min }; };

function field(label, input) {
    return h("label", { class: "field" }, h("span", null, label), input);
}

// Une section de la fiche : titre, bouton Aléatoire, aide, contenu, message d'erreur
function idSection(key, title, help, randomize, ...content) {
    return h("section", { class: `id-section${identityErrors[key] ? " bad" : ""}`, "data-key": key },
        h("header", null, h("h3", null, title), h("button", { class: "dice", onclick: async () => {
            await randomize();
            delete identityErrors[key];
            paint();
        } }, "Aléatoire")),
        h("p", { class: "note" }, help),
        content,
        identityErrors[key] ? h("p", { class: "id-error" }, identityErrors[key]) : null);
}

// L'erreur d'une section disparaît dès qu'on la corrige
function clearError(key, el) {
    if (!identityErrors[key]) return;
    delete identityErrors[key];
    const section = el.closest(".id-section");
    section.classList.remove("bad");
    section.querySelector(".id-error")?.remove();
}

function spinner(label, onPrev, onNext, prevOff, nextOff, onLabel) {
    return h("div", { class: "spin" },
        h("button", { class: "spin-arrow", disabled: prevOff, onclick: onPrev }, "‹"),
        onLabel ? h("button", { class: "spin-label", onclick: onLabel }, label) : h("b", { class: "spin-label" }, label),
        h("button", { class: "spin-arrow", disabled: nextOff, onclick: onNext }, "›"));
}

function setBirth(year, month) {
    const bounds = yearBounds();
    identity.year = Math.min(bounds.max, Math.max(bounds.min, year));
    identity.month = (month + 12) % 12;
    if (identity.day > daysIn(identity.year, identity.month)) identity.day = 0;
    if (identity.day && !ageOk(identity.year, identity.month, identity.day)) identity.day = 0;
    paint();
}

function calendar() {
    const bounds = yearBounds();
    const offset = (new Date(identity.year, identity.month, 1).getDay() + 6) % 7; // semaine du lundi au dimanche
    const cells = Array.from({ length: offset }, () => h("span"));
    for (let day = 1; day <= daysIn(identity.year, identity.month); day += 1) {
        cells.push(h("button", {
            class: `day${identity.day === day ? " on" : ""}`, disabled: !ageOk(identity.year, identity.month, day),
            onclick: (e) => { identity.day = day; clearError("birth", e.target); paint(); },
        }, String(day)));
    }
    return h("div", { class: "calendar" },
        h("div", { class: "cal-head" },
            spinner(MONTHS[identity.month], () => setBirth(identity.year, identity.month - 1), () => setBirth(identity.year, identity.month + 1)),
            spinner(String(identity.year), () => setBirth(identity.year - 1, identity.month), () => setBirth(identity.year + 1, identity.month),
                identity.year <= bounds.min, identity.year >= bounds.max)),
        h("div", { class: "cal-grid" }, ["L", "M", "M", "J", "V", "S", "D"].map((d) => h("small", null, d)), cells),
        h("p", { class: "cal-picked" }, identity.day ? `Né(e) le ${identity.day} ${MONTHS[identity.month].toLowerCase()} ${identity.year} (${ageAt(identity.year, identity.month, identity.day)} ans)` : "Aucun jour choisi"));
}

function randomBirth() {
    const bounds = yearBounds();
    for (let tries = 0; tries < 50; tries += 1) {
        const year = randomInt(Math.max(bounds.min, bounds.max - 30), bounds.max);
        const month = randomInt(0, 11);
        const day = randomInt(1, daysIn(year, month));
        if (ageOk(year, month, day)) return Object.assign(identity, { year, month, day });
    }
}

function nationalityPicker() {
    const list = settings.nationalities;
    const index = list.indexOf(identity.nationality);
    const choose = (name) => { identity.nationality = name; nationalityOpen = false; delete identityErrors.nationality; paint(); };
    return h("div", { class: "nationality" },
        spinner(identity.nationality || "Choisir…",
            () => choose(list[index <= 0 ? list.length - 1 : index - 1]),
            () => choose(list[(index + 1) % list.length]),
            false, false, () => { nationalityOpen = !nationalityOpen; paint(); }),
        nationalityOpen ? h("div", { class: "nat-list" }, list.map((name) =>
            h("button", { class: `nat${name === identity.nationality ? " on" : ""}`, onclick: () => choose(name) }, name))) : null);
}

function identityStep() {
    const text = (key, placeholder) => {
        const input = h("input", { maxlength: "19", placeholder, value: identity[key] });
        input.addEventListener("input", () => { identity[key] = input.value; clearError("name", input); });
        return input;
    };
    const heightValue = h("b", null, `${identity.height} cm`);
    const height = h("input", { type: "range", min: String(settings.height.min), max: String(settings.height.max), value: String(identity.height) });
    height.addEventListener("input", () => { identity.height = Number(height.value); heightValue.textContent = `${identity.height} cm`; });
    const gender = (sex, label) => h("button", { class: `gender${appearance.sex === sex ? " on" : ""}`, onclick: () => chooseSex(sex) }, label);

    return h("div", { class: "id-sheet" },
        idSection("name", "Prénom et nom", "Le nom de votre personnage, tel qu'il figurera sur ses papiers.", () => {
            identity.firstname = pick(settings.names[appearance.sex] || settings.names.male);
            identity.lastname = pick(settings.names.last);
        }, h("div", { class: "id-names" }, text("firstname", "Prénom"), text("lastname", "Nom"))),
        idSection("birth", "Date de naissance", `Choisissez le mois, l'année puis le jour (de ${settings.age.min} à ${settings.age.max} ans).`, randomBirth, calendar()),
        idSection("nationality", "Nationalité", "Le pays d'origine de votre personnage.", () => { identity.nationality = pick(settings.nationalities); nationalityOpen = false; }, nationalityPicker()),
        idSection("gender", "Genre et taille", "Changer de genre remet l'apparence par défaut.", async () => {
            identity.height = randomInt(Math.max(settings.height.min, 160), Math.min(settings.height.max, 195));
            await chooseSex(Math.random() < 0.5 ? "male" : "female");
        }, h("div", { class: "genders" }, gender("male", "Homme"), gender("female", "Femme")),
            h("div", { class: "slider" }, height, heightValue)));
}

async function chooseSex(sex) {
    if (appearance.sex === sex) return paint();
    const res = await nui("sex", { sex });
    if (res && res.appearance) {
        appearance = res.appearance;
        options = res.options || options;
        starterOutfit = JSON.parse(JSON.stringify(appearance.clothes));
    }
    paint();
}

// Tout doit être rempli et valide pour passer à l'étape suivante
function checkIdentity() {
    const errors = {};
    identity.firstname = identity.firstname.trim().replace(/\s+/g, " ");
    identity.lastname = identity.lastname.trim().replace(/\s+/g, " ");
    if (!identity.firstname || !identity.lastname) errors.name = "Renseignez le prénom et le nom.";
    else if (identity.firstname.length < 2 || !NAME_RULE.test(identity.firstname)) errors.name = "Prénom invalide : lettres, espaces, tirets ou apostrophes, 2 caractères minimum.";
    else if (identity.lastname.length < 2 || !NAME_RULE.test(identity.lastname)) errors.name = "Nom invalide : lettres, espaces, tirets ou apostrophes, 2 caractères minimum.";
    if (!identity.day) errors.birth = "Choisissez le jour de naissance dans le calendrier.";
    else if (!ageOk(identity.year, identity.month, identity.day)) errors.birth = `Âge accepté : de ${settings.age.min} à ${settings.age.max} ans.`;
    if (!settings.nationalities.includes(identity.nationality)) errors.nationality = "Choisissez une nationalité.";
    if (!(identity.height >= settings.height.min && identity.height <= settings.height.max)) errors.gender = "Taille invalide.";

    identityErrors = errors;
    const count = Object.keys(errors).length;
    if (!count) return true;
    toast(count === 1 ? Object.values(errors)[0] : `Identité incomplète : ${count} informations à corriger.`);
    stepIndex = 0;
    paint();
    $("step").querySelector(".id-section.bad")?.scrollIntoView({ block: "center" });
    return false;
}

// ---------- Outils communs ----------

function palette(colors, current, onPick) {
    return h("div", { class: "palette" }, colors.map(([r, g, b], i) => {
        const swatch = h("button", { class: `swatch${i === current ? " on" : ""}`, title: String(i), onclick: () => onPick(i) });
        swatch.style.background = `rgb(${r},${g},${b})`;
        return swatch;
    }));
}

function stepper(value, min, max, onChange, labelOf) {
    const display = h("b", null, labelOf(value));
    const set = (v) => { value = v; display.textContent = labelOf(v); onChange(v); };
    return h("div", { class: "stepper" },
        h("button", { onclick: () => set(value <= min ? max : value - 1) }, "‹"), display,
        h("button", { onclick: () => set(value >= max ? min : value + 1) }, "›"));
}

function rangeField(label, value, min, max, step, onInput) {
    const input = h("input", { type: "range", min: String(min), max: String(max), step: String(step), value: String(value) });
    input.addEventListener("input", () => onInput(Number(input.value)));
    return h("div", { class: "field" }, h("span", null, label), h("div", { class: "slider" }, input));
}

const randomFloat = (min, max) => Math.round((min + Math.random() * (max - min)) * 100) / 100;

// Icônes des catégories (remplacées par une miniature quand l'outil photo en a fait une)
const ICONS = {
    parents: "M8 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM16 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM2 20c0-3 3-5 6-5s6 2 6 5M14 15c3 0 8 1 8 5",
    eyes: "M2 12s4-6 10-6 10 6 10 6-4 6-10 6-10-6-10-6zM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z",
    nose: "M12 4v9l-3 3c1 1.3 5 1.3 6 0",
    brows: "M3 10c2-2 5-2 7-1M14 9c2-1 5-1 7 1",
    cheeks: "M4 12a8 9 0 1 0 16 0 8 9 0 1 0-16 0M7 14h.01M17 14h.01",
    lips: "M3 12c3-3 6-4 9-2 3-2 6-1 9 2-3 4-6 5-9 5s-6-1-9-5zM3 12h18",
    jaw: "M5 7c0 7 3 13 7 13s7-6 7-13",
    chin: "M8 15c0 3 2 5 4 5s4-2 4-5M6 6c0 5 2 9 6 9s6-4 6-9",
    neck: "M9 3v8c0 2-3 3-5 5M15 3v8c0 2 3 3 5 5",
    hair: "M5 13c0-5 3-9 7-9s7 4 7 9v6M5 13v6M9 8c1 2 4 3 8 3",
    beard: "M6 8v4a6 6 0 0 0 12 0V8M9 14c1 1 5 1 6 0M9 18l3 3 3-3",
    chest: "M4 5c3 2 13 2 16 0v15H4zM12 9v7M9 12h6",
    makeup: "M2 12s4-6 10-6 10 6 10 6-4 6-10 6-10-6-10-6zM5 7l2 2M12 4v3M19 7l-2 2",
    face: "M12 3a8 9 0 1 0 0 18 8 9 0 1 0 0-18zM9 10h.01M15 10h.01M9 15c2 1 4 1 6 0",
    jacket: "M8 3 3 6l2 5 2-1v11h10V10l2 1 2-5-5-3-4 5zM12 8v13",
    shirt: "M8 3 3 6l2 4 2-1v12h10V9l2 1 2-4-5-3a4 4 0 0 1-8 0z",
    glove: "M7 21v-6l-2-4V6a1 1 0 0 1 2 0v4V4a1 1 0 0 1 2 0v6V3a1 1 0 0 1 2 0v7V4a1 1 0 0 1 2 0v8l2-2a1 1 0 0 1 2 1l-4 5v5",
    pants: "M6 3h12l1 18h-5l-2-11-2 11H5z",
    shoe: "M3 17v-6l5-1 3 3 9 2v3H3zM3 17h17",
    hat: "M4 16c0-5 3-9 8-9s8 4 8 9M2 16h20",
    glasses: "M3 12a3 3 0 1 0 6 0 3 3 0 0 0-6 0M15 12a3 3 0 1 0 6 0 3 3 0 0 0-6 0M9 12h6",
    mask: "M4 8c3-2 13-2 16 0 0 7-3 12-8 12S4 15 4 8zM8 11h2M14 11h2",
    chain: "M6 4c0 8 3 12 6 12s6-4 6-12M12 16v4",
    bag: "M5 8h14l-1 13H6zM9 8V6a3 3 0 0 1 6 0v2",
    earring: "M12 3v6M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z",
    watch: "M9 3h6l1 4M9 3 8 7M8 17l1 4h6l1-4M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 10v2l1 1",
};

// Apparence : parents, yeux et traits du visage (index GTA des traits)
const LOOK = [
    { key: "parents", label: "Parents", icon: "parents" },
    { key: "eyes", label: "Yeux", icon: "eyes", features: [[11, "Ouverture"]] },
    { key: "nose", label: "Nez", icon: "nose", features: [[0, "Largeur"], [1, "Hauteur du bout"], [2, "Longueur"], [3, "Hauteur de l'arête"], [4, "Pointe"], [5, "Déviation"]] },
    { key: "brow", label: "Arcades", icon: "brows", features: [[6, "Hauteur"], [7, "Profondeur"]] },
    { key: "cheeks", label: "Pommettes et joues", icon: "cheeks", features: [[8, "Hauteur des pommettes"], [9, "Largeur des pommettes"], [10, "Épaisseur des joues"]] },
    { key: "lips", label: "Lèvres", icon: "lips", features: [[12, "Épaisseur"]] },
    { key: "jaw", label: "Mâchoire", icon: "jaw", features: [[13, "Largeur"], [14, "Profondeur"]] },
    { key: "chin", label: "Menton", icon: "chin", features: [[15, "Hauteur"], [16, "Avancée"], [17, "Largeur"], [18, "Fossette"]] },
    { key: "neck", label: "Cou", icon: "neck", camera: 2, features: [[19, "Épaisseur"]] },
];

// Coiffure et style : cheveux et calques du visage (index GTA des calques), palette de couleurs éventuelle
const STYLE = [
    { key: "hair", label: "Cheveux", icon: "hair", thumb: "hair" },
    { key: "1", label: "Barbe", icon: "beard", palette: "hair" },
    { key: "2", label: "Sourcils", icon: "brows", palette: "hair" },
    { key: "10", label: "Pilosité du torse", icon: "chest", palette: "hair", camera: 2 },
    { key: "4", label: "Maquillage", icon: "makeup" },
    { key: "5", label: "Blush", icon: "cheeks", palette: "makeup" },
    { key: "8", label: "Rouge à lèvres", icon: "lips", palette: "makeup" },
    { key: "0", label: "Imperfections", icon: "face" },
    { key: "9", label: "Taches de rousseur", icon: "face" },
    { key: "3", label: "Rides", icon: "face" },
    { key: "6", label: "Teint", icon: "face" },
    { key: "7", label: "Marques du soleil", icon: "face" },
    { key: "11", label: "Marques du corps", icon: "chest", camera: 2 },
];

const thumbKey = (entry) => (entry.key === "hair" ? "hair" : `overlay-${entry.key}`);
const clothesCategories = () => settings.clothes.map((entry) => ({ ...entry, key: String(entry.index) }));
const categoriesOf = (stepId) => (stepId === "look" ? LOOK : stepId === "style" ? STYLE : clothesCategories());
const categoryOf = (stepId) => categoriesOf(stepId).find((c) => c.key === category[stepId]) || categoriesOf(stepId)[0];

// Miniature d'un style (outil photo staff), sinon null
function thumbUrl(key, index) {
    const list = thumbs[appearance.sex] && thumbs[appearance.sex][key];
    return list && list.has(index) ? `thumbs/${appearance.sex}-${key}-${index}.webp` : null;
}

// Cartes des catégories (panneau de gauche)
function categoryCards(stepId) {
    return h("div", { class: "cat-grid" }, categoriesOf(stepId).map((entry) => {
        const current = category[stepId] === entry.key;
        let visual;
        if (entry.key === "parents") visual = h("div", { class: "cat-parents" }, portraitImg(appearance.heritage.father), portraitImg(appearance.heritage.mother));
        else {
            let url = null;
            if (stepId === "style") url = thumbUrl(thumbKey(entry), entry.key === "hair" ? 4 : 2);
            if (stepId === "clothes") {
                const worn = clothesValue(entry.kind, entry.id);
                url = worn[0] >= 0 ? clothesImage(entry, worn[0], worn[1]) : null;
            }
            const icon = svg(ICONS[entry.icon] || ICONS.shirt);
            visual = url ? h("img", { src: url, alt: "", onerror: (e) => e.target.replaceWith(icon) }) : icon;
        }
        return h("button", { class: `cat-card${current ? " on" : ""}`, onclick: () => {
            category[stepId] = entry.key;
            setCamera(entry.camera || 1);
            paint();
            $("side-body").scrollTop = 0;
        } }, h("span", { class: "cat-visual" }, visual), h("span", { class: "cat-label" }, entry.label));
    }));
}

function lookStep() {
    return h("div", { class: "stack" }, categoryCards("look"), h("p", { class: "note" }, "Choisissez une catégorie : ses réglages s'ouvrent à droite."));
}

function styleStep() {
    return h("div", { class: "stack" }, categoryCards("style"), h("p", { class: "note" }, "Les couleurs et l'intensité se règlent sous les styles, à droite."));
}

// ---------- Panneau de droite ----------

let sideShown = null; // dernier état envoyé au jeu (cadrage de la caméra)
function setSideShown(shown) {
    if (sideShown === shown) return;
    sideShown = shown;
    nui("layout", { side: shown });
}

function paintSide() {
    const stepId = STEPS[stepIndex].id;
    const side = $("side");
    if (!PANEL_STEPS.includes(stepId)) {
        side.classList.add("hidden");
        setSideShown(false);
        return;
    }
    const entry = categoryOf(stepId);
    const body = $("side-body");
    const scroll = body.dataset.key === `${stepId}:${entry.key}` ? body.scrollTop : 0;
    const { content, randomize, reset } = { look: lookEditor, style: styleEditor, clothes: clothesEditor }[stepId](entry);

    $("side-head").replaceChildren(h("h3", null, entry.label),
        h("button", { class: "dice", onclick: () => { randomize(); pushAppearance(); paint(); } }, "Aléatoire"),
        h("button", { class: "reset", title: "Revenir au réglage par défaut", onclick: () => { reset(); pushAppearance(); paint(); } }, "↺ Réinitialiser"));
    body.replaceChildren(...[content].flat(Infinity).filter(Boolean));
    body.dataset.key = `${stepId}:${entry.key}`;
    body.scrollTop = scroll;
    side.classList.remove("hidden");
    setSideShown(true);
}

// Grille de styles en cercles : miniature si elle existe, sinon numéro
function styleGrid(urlOf, count, current, withNone, onPick) {
    const cells = [];
    if (withNone) cells.push(h("button", { class: `style-cell${current < 0 ? " on" : ""}`, onclick: () => onPick(-1) }, h("span", { class: "style-dot none" }, "∅"), h("small", null, "Aucun")));
    for (let i = 0; i < count; i += 1) {
        const url = urlOf(i);
        cells.push(h("button", { class: `style-cell${current === i ? " on" : ""}`, onclick: () => onPick(i) },
            h("span", { class: "style-dot" }, url ? h("img", { src: url, alt: "", loading: "lazy", onerror: (e) => e.target.replaceWith(String(i + 1)) }) : String(i + 1)),
            h("small", null, `Style ${i + 1}`)));
    }
    return h("div", { class: "style-grid" }, cells);
}

function lookEditor(entry) {
    const h0 = appearance.heritage;
    if (entry.key === "parents") {
        const parentGrid = (key, list) => h("div", { class: "style-grid" }, list.map(([name, id]) =>
            h("button", { class: `style-cell${h0[key] === id ? " on" : ""}`, onclick: () => { h0[key] = id; pushAppearance(); paint(); } },
                h("span", { class: "style-dot portrait" }, portraitImg(id)), h("small", null, name))));
        return {
            content: [h("div", { class: "side-sub" }, "Parent 1"), parentGrid("father", FATHERS), h("div", { class: "side-sub" }, "Parent 2"), parentGrid("mother", MOTHERS),
                h("div", { class: "side-sub" }, "Mélange"),
                rangeField("Ressemblance (Parent 1 ↔ Parent 2)", h0.shape, 0, 1, 0.01, (v) => { h0.shape = v; pushAppearance(); }),
                rangeField("Peau (Parent 1 ↔ Parent 2)", h0.skin, 0, 1, 0.01, (v) => { h0.skin = v; pushAppearance(); })],
            randomize: () => { h0.father = pick(FATHERS)[1]; h0.mother = pick(MOTHERS)[1]; h0.shape = randomFloat(0.1, 0.9); h0.skin = randomFloat(0.1, 0.9); },
            reset: () => { Object.assign(h0, { father: 0, mother: 21, shape: appearance.sex === "female" ? 0.8 : 0.5, skin: 0.5 }); },
        };
    }
    const features = (entry.features || []).map(([index, label]) => {
        const input = h("input", { type: "range", min: "-1", max: "1", step: "0.05", value: String(appearance.features[index] || 0) });
        input.addEventListener("input", () => { appearance.features[index] = Number(input.value); pushAppearance(); });
        input.addEventListener("dblclick", () => { input.value = "0"; appearance.features[index] = 0; pushAppearance(); });
        return h("div", { class: "field" }, h("span", null, label), h("div", { class: "slider" }, input));
    });
    const eyes = entry.key === "eyes" ? [h("div", { class: "side-sub" }, "Couleur"), h("div", { class: "palette eyes" }, EYE_COLORS.map(([label, color], i) => {
        const swatch = h("button", { class: `swatch${appearance.eyeColor === i ? " on" : ""}`, title: label, onclick: () => { appearance.eyeColor = i; pushAppearance(); paint(); } });
        swatch.style.background = color;
        return swatch;
    })), h("div", { class: "side-sub" }, "Forme")] : [];
    return {
        content: [eyes, features, h("p", { class: "note" }, "Double-cliquez sur une barre pour la remettre au milieu.")],
        randomize: () => {
            for (const [index] of entry.features || []) appearance.features[index] = randomFloat(-0.6, 0.6);
            if (entry.key === "eyes") appearance.eyeColor = randomInt(0, 7);
        },
        reset: () => {
            for (const [index] of entry.features || []) appearance.features[index] = 0;
            if (entry.key === "eyes") appearance.eyeColor = 0;
        },
    };
}

function styleEditor(entry) {
    if (entry.key === "hair") {
        const hair = appearance.hair;
        return {
            content: [h("div", { class: "side-sub" }, "Couleur"), palette(options.hairColors, hair.color, (i) => { hair.color = i; pushAppearance(); paint(); }),
                h("div", { class: "side-sub" }, "Reflets"), palette(options.hairColors, hair.highlight, (i) => { hair.highlight = i; pushAppearance(); paint(); }),
                h("div", { class: "side-sub" }, "Coupes"), styleGrid((i) => thumbUrl("hair", i), options.hairStyles, hair.style, false, (i) => { hair.style = i; pushAppearance(); paint(); })],
            randomize: () => { hair.style = randomInt(0, Math.max(0, options.hairStyles - 1)); hair.color = randomInt(0, Math.min(options.hairColors.length - 1, 20)); hair.highlight = hair.color; },
            reset: () => Object.assign(hair, { style: 0, color: 0, highlight: 0 }),
        };
    }
    const count = options.overlays[entry.key] || 0;
    const o = appearance.overlays[entry.key] || (appearance.overlays[entry.key] = { style: -1, opacity: 1, color: 0 });
    const colors = entry.palette === "hair" ? options.hairColors : options.makeupColors;
    return {
        content: [o.style >= 0 ? rangeField("Intensité", o.opacity, 0, 1, 0.05, (v) => { o.opacity = v; pushAppearance(); }) : null,
            o.style >= 0 && entry.palette ? [h("div", { class: "side-sub" }, "Couleur"), palette(colors, o.color, (i) => { o.color = i; pushAppearance(); paint(); })] : null,
            h("div", { class: "side-sub" }, "Styles"), styleGrid((i) => thumbUrl(thumbKey(entry), i), count, o.style, true, (i) => { o.style = i; pushAppearance(); paint(); })],
        randomize: () => {
            o.style = randomInt(-1, count - 1);
            o.opacity = randomFloat(0.5, 1);
            if (entry.palette) o.color = randomInt(0, Math.min(colors.length - 1, 20));
        },
        reset: () => Object.assign(o, { style: -1, opacity: 1, color: 0 }),
    };
}

// ---------- 4. Vêtements ----------

const clothesCounts = {}; // "sexe:kind:id:drawable" -> { drawables, textures }
let starterOutfit = null; // tenue de départ (bouton Réinitialiser)

function clothesValue(kind, id) {
    const bag = kind === "prop" ? appearance.clothes.props : appearance.clothes.components;
    return bag[id] || (bag[id] = kind === "prop" ? [-1, 0] : [0, 0]);
}

function starterValue(entry) {
    const bag = (starterOutfit && (entry.kind === "prop" ? starterOutfit.props : starterOutfit.components)) || {};
    return bag[entry.id] || (entry.kind === "prop" ? [-1, 0] : [0, 0]);
}

// Nombre de modèles et de textures, lu dans le jeu (selon le modèle homme / femme)
const countsKey = (kind, id, drawable) => `${appearance.sex}:${kind}:${id}:${drawable}`;
async function loadCounts(kind, id, drawable) {
    const key = countsKey(kind, id, drawable);
    if (!clothesCounts[key]) clothesCounts[key] = (await nui("clothesCounts", { kind, id, drawable })) || { drawables: 1, textures: 1 };
    return clothesCounts[key];
}

// Image d'un vêtement (lien réglé dans le panel ou la config), sinon null
function clothesImage(entry, drawable, texture) {
    const links = settings.clothesImages || {};
    const template = entry.kind === "prop" ? links.prop : links.component;
    if (!template) return null;
    return template.replaceAll("{sex}", appearance.sex).replaceAll("{id}", String(entry.id))
        .replaceAll("{drawable}", String(drawable)).replaceAll("{texture}", String(texture));
}

function clothesStep() {
    return h("div", { class: "stack" }, categoryCards("clothes"),
        h("p", { class: "note" }, "La tenue est enregistrée avec le personnage ; elle se change ensuite dans les magasins de vêtements."));
}

function clothesEditor(entry) {
    const value = clothesValue(entry.kind, entry.id);
    const isProp = entry.kind === "prop";
    const total = clothesCounts[countsKey(entry.kind, entry.id, 0)];
    const worn = value[0] >= 0 ? clothesCounts[countsKey(entry.kind, entry.id, value[0])] : { textures: 0 };

    // Comptes pas encore lus : chargement puis nouveau rendu
    if (!total || !worn) {
        Promise.all([loadCounts(entry.kind, entry.id, 0), value[0] >= 0 ? loadCounts(entry.kind, entry.id, value[0]) : null]).then(() => paint());
        return { content: [h("p", { class: "note" }, "Chargement des styles…")], randomize: () => {}, reset: () => {} };
    }

    const textures = worn.textures || 0;
    let texture = null;
    if (textures > 1) {
        const shown = h("b", null, `${value[1] + 1} / ${textures}`);
        const input = h("input", { type: "range", min: "0", max: String(textures - 1), step: "1", value: String(value[1]) });
        input.addEventListener("input", () => { value[1] = Number(input.value); shown.textContent = `${value[1] + 1} / ${textures}`; pushAppearance(); });
        texture = h("div", { class: "field" }, h("span", null, "Texture"), h("div", { class: "slider" }, input, shown));
    }

    return {
        content: [texture, h("div", { class: "side-sub" }, "Styles"),
            styleGrid((i) => clothesImage(entry, i, 0), total.drawables, value[0], isProp, (i) => { value[0] = i; value[1] = 0; pushAppearance(); paint(); })],
        randomize: () => { value[0] = randomInt(isProp ? -1 : 0, Math.max(0, total.drawables - 1)); value[1] = 0; },
        reset: () => { const start = starterValue(entry); value[0] = start[0]; value[1] = start[1]; },
    };
}

// ---------- 6. Lieu d'apparition ----------

let spawnChoice = null;

function spawnStep() {
    const groups = [];
    for (const spawn of settings.spawns) {
        let group = groups.find((g) => g.name === spawn.group);
        if (!group) groups.push(group = { name: spawn.group, list: [] });
        group.list.push(spawn);
    }
    return h("div", { class: "stack" }, groups.map((g) => h("div", { class: "field" }, h("span", null, g.name),
        h("div", { class: "spawns" }, g.list.map((spawn) => {
            const card = h("button", { class: `spawn-card${spawnChoice === spawn.index ? " on" : ""}`, onclick: () => {
                spawnChoice = spawn.index;
                nui("spawn", { index: spawn.index });
                paint();
            } }, h("span", null, spawn.label));
            if (spawn.image) card.style.backgroundImage = `url("${spawn.image}")`;
            return card;
        })))),
        h("p", { class: "note" }, "Votre personnage est montré sur place. « Terminer » : photo d'identité, puis arrivée en ville."));
}

// ---------- Photo d'identité ----------

function mugshot(seconds) {
    const left = h("b", null, String(seconds));
    const screen = h("div", { class: "mugshot" },
        h("div", { class: "mugshot-frame" }),
        h("div", { class: "mugshot-text" }, h("span", null, "Photo d'identité"), h("small", null, "Regardez l'objectif"), left),
        h("div", { class: "flash" }));
    document.body.append(screen);
    $("creator").classList.add("shooting");
    let n = seconds;
    const timer = setInterval(() => {
        n -= 1;
        left.textContent = n > 0 ? String(n) : "";
        if (n === Math.floor(seconds / 2)) screen.classList.add("flashing");
        if (n <= 0) clearInterval(timer);
    }, 1000);
}

// ---------- Navigation et fin ----------

$("prev").addEventListener("click", () => stepIndex > 0 && go(stepIndex - 1));
$("next").addEventListener("click", async () => {
    if (stepIndex < lastStep()) return go(stepIndex + 1);
    if (!checkIdentity()) return;
    if (!spawnChoice) return toast("Choisissez un lieu d'apparition.");
    $("next").disabled = true;
    $("next").textContent = "Création…";
    const res = await nui("finish", { identity: { firstname: identity.firstname, lastname: identity.lastname, dateofbirth: dateOfBirth(), nationality: identity.nationality, height: identity.height } });
    $("next").disabled = false;
    if (!res || !res.ok) {
        paint();
        return toast((res && res.error) || "Création impossible.");
    }
});

// Rotation du personnage : glisser sur la scène
let dragging = null;
$("stage").addEventListener("mousedown", (e) => { if (!e.target.closest(".cams")) dragging = e.clientX; });
window.addEventListener("mouseup", () => { dragging = null; });
window.addEventListener("mousemove", (e) => {
    if (dragging === null) return;
    const delta = (e.clientX - dragging) * 0.5;
    dragging = e.clientX;
    if (Math.abs(delta) >= 0.5) nui("rotate", { delta });
});

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "open") {
        appearance = msg.appearance;
        options = msg.options;
        settings = msg.config;
        Object.assign(identity, { lastname: "", firstname: "", day: 0, month: 0, year: new Date().getFullYear() - settings.age.min - 7, nationality: "", height: settings.height.default });
        identityErrors = {};
        nationalityOpen = false;
        stepIndex = 0;
        camera = 2;
        spawnChoice = null;
        sideShown = null;
        applyBranding(msg.branding);
        category.look = "parents";
        category.style = "hair";
        category.clothes = String(settings.clothes[0] ? settings.clothes[0].index : 1);
        starterOutfit = JSON.parse(JSON.stringify(appearance.clothes));
        loadThumbs();
        if (msg.draft) restoreDraft(msg.draft);
        identityErrors = {};
        $("creator").classList.remove("hidden");
        paint();
        stepCamera();
    }
    if (msg.action === "mugshot") mugshot(msg.seconds || 4);
    if (msg.action === "thumbCapture" && typeof msg.url === "string") captureThumb(msg.url);
    if (msg.action === "close") {
        $("creator").classList.add("hidden");
        $("creator").classList.remove("shooting");
        document.querySelectorAll(".mugshot").forEach((el) => el.remove());
    }
});

// Outil photo staff : portrait GTA (fond transparent) converti en miniature webp, renvoyé au jeu
function captureThumb(url) {
    const send = (payload) => nui("thumbData", payload).catch(() => null);
    const img = new Image();
    img.onload = () => {
        try {
            const canvas = document.createElement("canvas");
            canvas.width = 160;
            canvas.height = 160;
            canvas.getContext("2d").drawImage(img, 0, 0, 160, 160);
            send({ image: canvas.toDataURL("image/webp", 0.85) });
        } catch (e) {
            send({ error: String((e && e.message) || e).slice(0, 120) });
        }
    };
    img.onerror = () => send({ error: "portrait introuvable" });
    img.src = url;
}

// Index des miniatures prises par l'outil photo staff (absent tant qu'aucune photo n'a été faite)
async function loadThumbs() {
    try {
        const res = await fetch("thumbs/index.json");
        const data = await res.json();
        thumbs = {};
        for (const [sex, list] of Object.entries(data || {})) {
            thumbs[sex] = {};
            for (const [key, indexes] of Object.entries(list || {})) thumbs[sex][key] = new Set(indexes);
        }
        if (settings) paint();
    } catch {
        thumbs = {};
    }
}

// ---------- Aperçu navigateur ----------

function demo(name) {
    if (name === "sex") return { appearance: { ...appearance, sex: appearance.sex === "male" ? "female" : "male" }, options };
    if (name === "finish") { setTimeout(() => window.postMessage({ action: "mugshot", seconds: 4 }, "*"), 100); return { ok: true }; }
    if (name === "clothesCounts") return { drawables: 120, textures: 6 };
    return {};
}

if (!inGame) {
    const colors = Array.from({ length: 64 }, (_, i) => [40 + (i * 13) % 200, 30 + (i * 7) % 150, 20 + (i * 5) % 100]);
    window.postMessage({
        action: "open",
        appearance: { sex: "male", heritage: { father: 0, mother: 21, shape: 0.5, skin: 0.5 }, hair: { style: 0, color: 0, highlight: 0 }, eyeColor: 0, overlays: {}, features: {}, clothes: { components: { 11: [0, 0], 4: [0, 0] }, props: {} } },
        options: { hairStyles: 76, overlays: { 0: 24, 1: 29, 2: 34, 3: 15, 4: 75, 5: 7, 7: 11, 8: 10, 9: 18, 10: 17, 11: 12 }, hairColors: colors, makeupColors: colors },
        config: { height: { min: 150, max: 210, default: 178 }, age: { min: 18, max: 90 }, cameras: 3, mugshot: 4,
            nationalities: ["Américaine", "Française", "Canadienne", "Mexicaine", "Britannique", "Italienne", "Espagnole", "Allemande", "Marocaine", "Brésilienne", "Japonaise", "Australienne"],
            names: { male: ["James", "Lucas", "Hugo"], female: ["Emma", "Léa", "Mia"], last: ["Smith", "Garcia", "Dubois"] },
            clothes: [{ index: 1, label: "Vestes", kind: "component", id: 11, camera: 2, icon: "jacket" }, { index: 2, label: "Sous-haut", kind: "component", id: 8, camera: 2, icon: "shirt" }, { index: 3, label: "Bras et gants", kind: "component", id: 3, camera: 2, icon: "glove" }, { index: 4, label: "Bas", kind: "component", id: 4, camera: 3, icon: "pants" }, { index: 5, label: "Chaussures", kind: "component", id: 6, camera: 3, icon: "shoe" }, { index: 6, label: "Chapeaux", kind: "prop", id: 0, camera: 1, icon: "hat" }, { index: 7, label: "Lunettes", kind: "prop", id: 1, camera: 1, icon: "glasses" }, { index: 8, label: "Masques", kind: "component", id: 1, camera: 1, icon: "mask" }, { index: 9, label: "Accessoires", kind: "component", id: 7, camera: 2, icon: "chain" }, { index: 10, label: "Sacs", kind: "component", id: 5, camera: 3, icon: "bag" }, { index: 11, label: "Boucles d'oreilles", kind: "prop", id: 2, camera: 1, icon: "earring" }, { index: 12, label: "Montres", kind: "prop", id: 6, camera: 2, icon: "watch" }],
            clothesImages: { component: "", prop: "" },
            spawns: [{ index: 1, group: "Los Santos", label: "Vespucci" }, { index: 2, group: "Los Santos", label: "Place des Cubes" }, { index: 3, group: "Los Santos", label: "Gouvernement" }, { index: 4, group: "Blaine County", label: "Sandy Shores" }, { index: 5, group: "Blaine County", label: "Paleto Bay" }, { index: 6, group: "Aéroport", label: "Aéroport international" }] },
    }, "*");
}
