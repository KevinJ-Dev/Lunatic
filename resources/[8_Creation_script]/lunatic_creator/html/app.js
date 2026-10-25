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

// Calques du visage (index GTA) : libellé, palette (hair / makeup) ou aucune
const PILOSITY = [
    { key: "hair", label: "Cheveux" },
    { key: "1", label: "Barbe", palette: "hair" },
    { key: "2", label: "Sourcils", palette: "hair" },
    { key: "10", label: "Torse", palette: "hair" },
];
const MAKEUP = [{ key: "4", label: "Yeux" }, { key: "8", label: "Lèvres", palette: "makeup" }];
const DETAILS = [
    { key: "0", label: "Taches cutanées" }, { key: "9", label: "Taches de rousseur" }, { key: "11", label: "Cicatrices" },
    { key: "5", label: "Rougeurs", palette: "makeup" }, { key: "7", label: "Marques de la peau" }, { key: "3", label: "Rides" },
];
const FEATURES = [
    ["Nez", [[0, "Largeur"], [1, "Hauteur du bout"], [2, "Longueur"], [3, "Hauteur de l'arête"], [4, "Pointe"], [5, "Déviation"]]],
    ["Sourcils", [[6, "Hauteur"], [7, "Profondeur"]]],
    ["Pommettes", [[8, "Hauteur"], [9, "Largeur"]]],
    ["Joues", [[10, "Épaisseur"]]],
    ["Yeux", [[11, "Ouverture"]]],
    ["Lèvres", [[12, "Épaisseur"]]],
    ["Mâchoire", [[13, "Largeur"], [14, "Profondeur"]]],
    ["Menton", [[15, "Hauteur"], [16, "Avancée"], [17, "Largeur"], [18, "Fossette"]]],
    ["Cou", [[19, "Épaisseur"]]],
];

// Étapes de la création
const STEPS = [
    { id: "identity", label: "Identité", icon: "M12 3a7 7 0 0 0-7 7v3M19 10a7 7 0 0 0-7-7M8.5 21c.6-2 1-4.3 1-7a2.5 2.5 0 0 1 5 0c0 1.5-.1 3-.4 4.4M5 16c.4-1.2.6-2.6.6-4M12 10v4c0 2.6-.4 5-1.2 7M18.6 17c.3-1.6.4-3.3.4-5" },
    { id: "heritage", label: "Héritage", icon: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21c0-4.4 3.6-8 8-8s8 3.6 8 8" },
    { id: "appearance", label: "Apparence", icon: "M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12zM12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z" },
    { id: "face", label: "Visage", icon: "M18 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM6 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM18 22a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM8.6 13.5l6.8 4M15.4 6.5l-6.8 4" },
    { id: "clothes", label: "Vêtements", icon: "M8 3 3 6l2 4 2-1v12h10V9l2 1 2-4-5-3a4 4 0 0 1-8 0z" },
    { id: "spawn", label: "Lieu d'apparition", icon: "M12 21s-7-6.5-7-12a7 7 0 0 1 14 0c0 5.5-7 12-7 12zM12 11a2 2 0 1 0 0-4 2 2 0 0 0 0 4z" },
];

// ---------- État ----------

let appearance = null;
let options = null;
let settings = null;
let stepIndex = 0;
let openEditor = null; // calque déplié dans Apparence
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
    $("steps").replaceChildren(...STEPS.map((s, i) => h("button", {
        class: `tab${i === stepIndex ? " on" : ""}${s.soon ? " soon" : ""}`, title: s.soon ? `${s.label} (bientôt)` : s.label,
        onclick: () => go(i),
    }, svg(s.icon))));

    const step = STEPS[stepIndex];
    const body = { identity: identityStep, heritage: heritageStep, appearance: appearanceStep, face: faceStep, clothes: clothesStep, spawn: spawnStep }[step.id]();
    $("step").replaceChildren(h("h2", null, step.label === "Visage" ? "Traits du visage" : step.label), body);
    $("prev").style.visibility = stepIndex === 0 ? "hidden" : "visible";
    $("next").textContent = stepIndex === lastStep() ? "Terminer" : "Suivant";

    $("cams").replaceChildren(...Array.from({ length: settings.cameras }, (_, i) => h("button", { class: `cam${camera === i + 1 ? " on" : ""}`, title: ["Visage", "Buste", "Corps"][i], onclick: () => setCamera(i + 1) }, String(i + 1))));
}

const lastStep = () => STEPS.length - 1;

function go(index) {
    if (STEPS[index].soon) return toast("Cette étape arrive bientôt.");
    if (index > stepIndex && stepIndex === 0 && !checkIdentity()) return;
    stepIndex = index;
    openEditor = null;
    paint();
    $("step").scrollTop = 0;
    if (STEPS[index].id === "face" || STEPS[index].id === "heritage") setCamera(1);
    if (STEPS[index].id === "clothes") setCamera(3);
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

// Âge exact à aujourd'hui (même calcul que le serveur d'esx_identity)
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

// ---------- 2. Héritage ----------

const parentStart = { father: 0, mother: 0 };

function heritageStep() {
    const h0 = appearance.heritage;
    const preview = h("div", { class: "parents" },
        portraitImg(h0.father), portraitImg(h0.mother));

    const row = (key, list, label) => {
        const visible = 4;
        const max = Math.max(0, list.length - visible);
        parentStart[key] = Math.min(parentStart[key], max);
        const cells = list.slice(parentStart[key], parentStart[key] + visible).map(([name, id]) => h("button", {
            class: `parent${h0[key] === id ? " on" : ""}`, onclick: () => { h0[key] = id; pushAppearance(); paint(); },
        }, portraitImg(id), h("span", null, name)));
        return h("div", { class: "field" }, h("span", null, label),
            h("div", { class: "carousel" },
                h("button", { class: "arrow", disabled: parentStart[key] === 0, onclick: () => { parentStart[key] = Math.max(0, parentStart[key] - visible); paint(); } }, "‹"),
                h("div", { class: "parent-row" }, cells),
                h("button", { class: "arrow", disabled: parentStart[key] >= max, onclick: () => { parentStart[key] = Math.min(max, parentStart[key] + visible); paint(); } }, "›")));
    };

    const slider = (key, label) => {
        const input = h("input", { type: "range", min: "0", max: "1", step: "0.01", value: String(h0[key]) });
        input.addEventListener("input", () => { h0[key] = Number(input.value); pushAppearance(); });
        return h("div", { class: "field" }, h("span", null, label), h("div", { class: "slider" }, input));
    };

    return h("div", { class: "stack" }, preview, row("father", FATHERS, "Parent 1"), row("mother", MOTHERS, "Parent 2"),
        slider("shape", "Ressemblance (Parent 1 ↔ Parent 2)"), slider("skin", "Peau (Parent 1 ↔ Parent 2)"));
}

// ---------- 3. Apparence ----------

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

function overlayEditor(entry) {
    if (entry.key === "hair") {
        const hair = appearance.hair;
        return h("div", { class: "editor" },
            h("div", { class: "field" }, h("span", null, "Coupe"), stepper(hair.style, 0, Math.max(0, options.hairStyles - 1), (v) => { hair.style = v; pushAppearance(); }, (v) => `${v + 1} / ${options.hairStyles}`)),
            h("div", { class: "field" }, h("span", null, "Couleur"), palette(options.hairColors, hair.color, (i) => { hair.color = i; pushAppearance(); paint(); })),
            h("div", { class: "field" }, h("span", null, "Reflets"), palette(options.hairColors, hair.highlight, (i) => { hair.highlight = i; pushAppearance(); paint(); })));
    }
    const count = options.overlays[entry.key] || 0;
    const o = appearance.overlays[entry.key] || (appearance.overlays[entry.key] = { style: -1, opacity: 1, color: 0 });
    const opacity = h("input", { type: "range", min: "0", max: "1", step: "0.05", value: String(o.opacity) });
    opacity.addEventListener("input", () => { o.opacity = Number(opacity.value); pushAppearance(); });
    return h("div", { class: "editor" },
        h("div", { class: "field" }, h("span", null, "Style"), stepper(o.style, -1, count - 1, (v) => { o.style = v; pushAppearance(); }, (v) => (v < 0 ? "Aucun" : `${v + 1} / ${count}`))),
        h("div", { class: "field" }, h("span", null, "Intensité"), h("div", { class: "slider" }, opacity)),
        entry.palette ? h("div", { class: "field" }, h("span", null, "Couleur"),
            palette(entry.palette === "hair" ? options.hairColors : options.makeupColors, o.color, (i) => { o.color = i; pushAppearance(); paint(); })) : null);
}

function overlayList(entries) {
    return h("div", { class: "list" }, entries.map((entry) => [
        h("button", { class: `row${openEditor === entry.key ? " on" : ""}`, onclick: () => { openEditor = openEditor === entry.key ? null : entry.key; paint(); } }, entry.label),
        openEditor === entry.key ? overlayEditor(entry) : null,
    ]));
}

function appearanceStep() {
    const cards = h("div", { class: "cards" }, PILOSITY.map((entry) => h("button", {
        class: `card${openEditor === entry.key ? " on" : ""}`, onclick: () => { openEditor = openEditor === entry.key ? null : entry.key; paint(); },
    }, h("span", null, entry.label))));
    const pilosityEditor = PILOSITY.find((e) => e.key === openEditor);

    return h("div", { class: "stack" },
        h("div", { class: "field" }, h("span", null, "Pilosité"), cards, pilosityEditor ? overlayEditor(pilosityEditor) : null),
        h("div", { class: "field" }, h("span", null, "Yeux"),
            h("div", { class: "list" },
                h("button", { class: `row${openEditor === "eyes" ? " on" : ""}`, onclick: () => { openEditor = openEditor === "eyes" ? null : "eyes"; paint(); } }, "Couleurs"),
                openEditor === "eyes" ? h("div", { class: "editor" }, h("div", { class: "palette eyes" }, EYE_COLORS.map(([label, color], i) => {
                    const swatch = h("button", { class: `swatch${appearance.eyeColor === i ? " on" : ""}`, title: label, onclick: () => { appearance.eyeColor = i; pushAppearance(); paint(); } });
                    swatch.style.background = color;
                    return swatch;
                }))) : null)),
        h("div", { class: "field" }, h("span", null, "Maquillage"), overlayList(MAKEUP)),
        h("div", { class: "field" }, h("span", null, "Détails"), overlayList(DETAILS)));
}

// ---------- 4. Traits du visage ----------

function faceStep() {
    return h("div", { class: "stack" }, FEATURES.map(([group, list]) => h("div", { class: "field" }, h("span", null, group),
        list.map(([index, label]) => {
            const input = h("input", { type: "range", min: "-1", max: "1", step: "0.05", value: String(appearance.features[index] || 0) });
            input.addEventListener("input", () => { appearance.features[index] = Number(input.value); pushAppearance(); });
            input.addEventListener("dblclick", () => { input.value = "0"; appearance.features[index] = 0; pushAppearance(); });
            return h("div", { class: "feature" }, h("small", null, label), input);
        }))),
        h("p", { class: "note" }, "Double-cliquez sur une barre pour la remettre au milieu."));
}

// ---------- 5. Vêtements ----------

let clothesOpen = null; // index de la catégorie dépliée
const clothesCounts = {}; // "kind:id:drawable" -> { drawables, textures }

function clothesValue(kind, id) {
    const bag = kind === "prop" ? appearance.clothes.props : appearance.clothes.components;
    return bag[id] || (bag[id] = kind === "prop" ? [-1, 0] : [0, 0]);
}

async function counts(kind, id, drawable) {
    const key = `${appearance.sex}:${kind}:${id}:${drawable}`; // les comptes changent avec le modèle homme / femme
    if (!clothesCounts[key]) clothesCounts[key] = await nui("clothesCounts", { kind, id, drawable });
    return clothesCounts[key] || { drawables: 1, textures: 1 };
}

// Réglage d'un vêtement : modèle puis couleur (les comptes viennent du jeu)
function clothesEditor(kind, id, label) {
    const value = clothesValue(kind, id);
    const box = h("div", { class: "field" }, h("span", null, label), h("div", { class: "muted-line" }, "…"));
    const paintBox = async () => {
        const c = await counts(kind, id, value[0]);
        const min = kind === "prop" ? -1 : 0;
        const model = stepper(value[0], min, Math.max(min, c.drawables - 1), async (v) => {
            value[0] = v;
            value[1] = 0;
            pushAppearance();
            paintBox();
        }, (v) => (v < 0 ? "Aucun" : `${v + 1} / ${c.drawables}`));
        const color = c.textures > 1 ? stepper(value[1], 0, c.textures - 1, (v) => { value[1] = v; pushAppearance(); }, (v) => `Couleur ${v + 1} / ${c.textures}`) : null;
        box.replaceChildren(h("span", null, label), model, color);
    };
    paintBox();
    return box;
}

function clothesStep() {
    return h("div", { class: "stack" }, h("div", { class: "field" }, h("span", null, "Catégories"),
        h("div", { class: "clothes" }, settings.clothes.map((entry) => [
            h("button", { class: `clothes-card${clothesOpen === entry.index ? " on" : ""}`, onclick: () => {
                clothesOpen = clothesOpen === entry.index ? null : entry.index;
                if (clothesOpen) setCamera(entry.camera || 2);
                paint();
            } }, h("span", null, entry.label)),
            clothesOpen === entry.index ? h("div", { class: "editor" },
                clothesEditor(entry.kind, entry.id, "Modèle"),
                (entry.extra || []).map((extra) => clothesEditor("component", extra.id, extra.label))) : null,
        ]))),
        h("p", { class: "note" }, "La tenue est enregistrée avec le personnage ; elle se change ensuite dans les magasins de vêtements."));
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
        clothesOpen = null;
        $("creator").classList.remove("hidden");
        paint();
    }
    if (msg.action === "mugshot") mugshot(msg.seconds || 4);
    if (msg.action === "close") {
        $("creator").classList.add("hidden");
        $("creator").classList.remove("shooting");
        document.querySelectorAll(".mugshot").forEach((el) => el.remove());
    }
});

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
            clothes: [{ index: 1, label: "Chapeau", kind: "prop", id: 0, camera: 1 }, { index: 2, label: "Haut", kind: "component", id: 11, camera: 2, extra: [{ label: "Sous-haut", id: 8 }, { label: "Bras", id: 3 }] }, { index: 3, label: "Bas", kind: "component", id: 4, camera: 3 }, { index: 4, label: "Lunettes", kind: "prop", id: 1, camera: 1 }, { index: 5, label: "Cou", kind: "component", id: 7 }, { index: 6, label: "Sac", kind: "component", id: 5 }, { index: 7, label: "Chaussures", kind: "component", id: 6 }],
            spawns: [{ index: 1, group: "Los Santos", label: "Vespucci" }, { index: 2, group: "Los Santos", label: "Place des Cubes" }, { index: 3, group: "Los Santos", label: "Gouvernement" }, { index: 4, group: "Blaine County", label: "Sandy Shores" }, { index: 5, group: "Blaine County", label: "Paleto Bay" }, { index: 6, group: "Aéroport", label: "Aéroport international" }] },
    }, "*");
}
