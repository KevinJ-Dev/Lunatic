// ====================================================================
//  esx_identity — interface de création d'identité (FR, JJ/MM/AAAA)
// ====================================================================

const RESOURCE = typeof GetParentResourceName === "function" ? GetParentResourceName() : "esx_identity";

// Valeurs par défaut, remplacées par celles du config.lua à l'ouverture
const limits = {
    minAge: 18,
    maxAge: 100,
    minHeight: 120,
    maxHeight: 220,
    maxNameLength: 20,
};

const $ = (id) => document.getElementById(id);
const form = $("register");
const submitBtn = $("submit");
const fields = {
    firstname: $("firstname"),
    lastname: $("lastname"),
    dob: $("dob"),
    height: $("height"),
};

function post(endpoint, data) {
    return fetch(`https://${RESOURCE}/${endpoint}`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

// ---------- Date JJ/MM/AAAA ----------

function maskDate(value) {
    const d = String(value || "").replace(/\D/g, "").slice(0, 8);
    if (d.length <= 2) return d;
    if (d.length <= 4) return `${d.slice(0, 2)}/${d.slice(2)}`;
    return `${d.slice(0, 2)}/${d.slice(2, 4)}/${d.slice(4)}`;
}

// Renvoie un objet Date si "JJ/MM/AAAA" est une vraie date, sinon null (ex : 31/02/2000)
function parseDate(value) {
    const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value || "");
    if (!m) return null;
    const day = +m[1], month = +m[2], year = +m[3];
    const date = new Date(year, month - 1, day);
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return null;
    return date;
}

function getAge(date) {
    const now = new Date();
    let age = now.getFullYear() - date.getFullYear();
    if (now.getMonth() < date.getMonth() || (now.getMonth() === date.getMonth() && now.getDate() < date.getDate())) {
        age--;
    }
    return age;
}

// ---------- Validation ----------

const NAME_REGEX = /^[A-Za-zÀ-ÖØ-öø-ÿ' -]+$/;

function validateName(value, label) {
    const v = value.trim();
    if (!v) return `${label} est obligatoire`;
    if (v.length < 2) return `${label} : 2 caractères minimum`;
    if (v.length >= limits.maxNameLength) return `${label} : ${limits.maxNameLength - 1} caractères maximum`;
    if (!NAME_REGEX.test(v)) return `${label} : lettres uniquement`;
    return null;
}

const validators = {
    firstname: () => validateName(fields.firstname.value, "Le prénom"),
    lastname: () => validateName(fields.lastname.value, "Le nom"),
    dob: () => {
        const v = fields.dob.value;
        if (!v) return "La date de naissance est obligatoire";
        if (!/^\d{2}\/\d{2}\/\d{4}$/.test(v)) return "Format attendu : JJ/MM/AAAA";
        const date = parseDate(v);
        if (!date) return "Cette date n'existe pas";
        const age = getAge(date);
        if (age < limits.minAge) return `Vous devez avoir au moins ${limits.minAge} ans`;
        if (age > limits.maxAge) return `Vous ne pouvez pas avoir plus de ${limits.maxAge} ans`;
        return null;
    },
    gender: () => (form.querySelector('input[name="gender"]:checked') ? null : "Choisissez votre sexe"),
    height: () => {
        const n = +fields.height.value;
        if (!Number.isInteger(n)) return "Taille invalide";
        if (n < limits.minHeight) return `Taille minimum : ${limits.minHeight} cm`;
        if (n > limits.maxHeight) return `Taille maximum : ${limits.maxHeight} cm`;
        return null;
    },
};

function showError(name, message) {
    const group = form.querySelector(`[data-field="${name}"]`);
    group.classList.toggle("is-invalid", !!message);
    group.querySelector(".msg").textContent = message || "";
}

function validate(name) {
    const error = validators[name]();
    showError(name, error);
    return !error;
}

function validateAll() {
    return Object.keys(validators).map(validate).every(Boolean);
}

// ---------- Aperçu de la carte ----------

function mrzPart(str) {
    return str
        .normalize("NFD")
        .replace(/[̀-ͯ]/g, "")
        .toUpperCase()
        .replace(/[^A-Z]/g, "<");
}

function updateCard() {
    const first = fields.firstname.value.trim();
    const last = fields.lastname.value.trim();
    const sexInput = form.querySelector('input[name="gender"]:checked');
    const sex = sexInput ? sexInput.value : null;
    const dob = fields.dob.value;
    const date = parseDate(dob);

    $("card-firstname").textContent = first || "—";
    $("card-lastname").textContent = last ? last.toUpperCase() : "—";
    $("card-sex").textContent = sex === "m" ? "M" : sex === "f" ? "F" : "—";
    $("card-height").textContent = `${fields.height.value} cm`;
    $("card-dob").textContent = dob.length ? dob + "JJ/MM/AAAA".slice(dob.length) : "JJ/MM/AAAA";

    const photo = document.querySelector(".idcard__photo");
    photo.classList.toggle("is-m", sex === "m");
    photo.classList.toggle("is-f", sex === "f");

    // Ligne MRZ façon vraie carte
    const dobMrz = date
        ? String(date.getFullYear()).slice(2) + String(date.getMonth() + 1).padStart(2, "0") + String(date.getDate()).padStart(2, "0")
        : "<<<<<<";
    const line = `IDSAN${mrzPart(last)}<<${mrzPart(first)}<<${dobMrz}${sex ? sex.toUpperCase() : "<"}`;
    $("card-mrz").textContent = (line + "<".repeat(36)).slice(0, 36);

    // Âge affiché dans le champ
    const hint = $("age-hint");
    if (date && !validators.dob()) {
        hint.textContent = `${getAge(date)} ans`;
    } else {
        hint.textContent = "";
    }
}

function updateHeight() {
    const el = fields.height;
    const pct = ((el.value - el.min) / (el.max - el.min)) * 100;
    el.style.setProperty("--fill", `${pct}%`);
    $("height-value").textContent = `${el.value} cm`;
}

// ---------- Événements du formulaire ----------

fields.dob.addEventListener("input", (e) => {
    e.target.value = maskDate(e.target.value);
    // L'erreur n'apparaît qu'une fois la date complète (ou si une erreur est déjà visible)
    if (e.target.value.length === 10 || form.querySelector('[data-field="dob"]').classList.contains("is-invalid")) {
        validate("dob");
    }
    updateCard();
});

fields.height.addEventListener("input", () => {
    updateHeight();
    updateCard();
});

["firstname", "lastname"].forEach((name) => {
    fields[name].addEventListener("input", () => {
        validate(name);
        updateCard();
    });
    fields[name].addEventListener("blur", () => {
        if (fields[name].value) validate(name);
    });
});

fields.dob.addEventListener("blur", () => {
    if (fields.dob.value) validate("dob");
});

form.querySelectorAll('input[name="gender"]').forEach((radio) => {
    radio.addEventListener("change", () => {
        validate("gender");
        updateCard();
    });
});

let submitting = false;

form.addEventListener("submit", (e) => {
    e.preventDefault();
    if (submitting || !validateAll()) return;

    submitting = true;
    submitBtn.disabled = true;

    post("register", {
        firstname: fields.firstname.value.trim(),
        lastname: fields.lastname.value.trim(),
        dateofbirth: fields.dob.value, // JJ/MM/AAAA
        sex: form.querySelector('input[name="gender"]:checked').value,
        height: +fields.height.value,
    }).finally(() => {
        // Si le serveur refuse, le menu reste ouvert : on réactive le bouton
        setTimeout(() => {
            submitting = false;
            submitBtn.disabled = false;
        }, 1000);
    });
});

// ---------- Messages venant du client Lua ----------

function applyLimits() {
    fields.firstname.maxLength = limits.maxNameLength - 1;
    fields.lastname.maxLength = limits.maxNameLength - 1;
    fields.height.min = limits.minHeight;
    fields.height.max = limits.maxHeight;
    $("height-min").textContent = limits.minHeight;
    $("height-max").textContent = limits.maxHeight;
    $("rule-age").textContent = `Âge entre ${limits.minAge} et ${limits.maxAge} ans`;
}

function resetForm() {
    form.reset();
    const mid = Math.round((limits.minHeight + limits.maxHeight) / 2);
    fields.height.value = Math.min(Math.max(175, limits.minHeight), limits.maxHeight) || mid;
    Object.keys(validators).forEach((name) => showError(name, null));
    updateHeight();
    updateCard();
}

window.addEventListener("message", (event) => {
    const data = event.data;
    if (!data || data.type !== "enableui") return;

    // ESX 1.16 envoie les limites dans "settings" (ancien nom : "config")
    const settings = data.settings || data.config;
    if (settings) {
        Object.keys(limits).forEach((key) => {
            if (typeof settings[key] === "number") limits[key] = settings[key];
        });
        applyLimits();
    }

    if (data.enable) {
        resetForm();
        document.body.classList.remove("none");
        setTimeout(() => fields.firstname.focus(), 50);
    } else {
        document.body.classList.add("none");
    }
});

applyLimits();
resetForm();
post("ready");
