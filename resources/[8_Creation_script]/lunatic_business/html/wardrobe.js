"use strict";

// Vestiaire (doc Vision) : bannière de la structure, onglets Homme / Femme, grille des tenues. Cliquer une tenue l'essaie
// sur le personnage (caméra du jeu), « Récupérer » la garde, fermer remet la tenue d'avant. Glisser à droite : tourner.
// Patron : nouvelle tenue (celle qu'il portait en ouvrant), modifier, remplacer, supprimer. Le serveur revérifie tout.
// $, h et nui viennent de app.js.

let wardrobeData = null;
let wardrobeTab = "m";
let wardrobeSelected = null; // id de la tenue choisie
let wardrobeForm = null;     // { id } (modification) ou { } (création)
let wardrobeConfirm = null;  // id de la tenue à supprimer (second clic)
let wardrobeBusy = false;
let wardrobeDrag = null;

const WARDROBE_TABS = [["m", "Homme"], ["f", "Femme"]];
const wardrobeOutfit = (id) => (wardrobeData.outfits || []).find((o) => o.id === id);

function wardrobeToast(text) {
    const el = $("wardrobeToast");
    el.textContent = text;
    el.classList.add("on");
    clearTimeout(wardrobeToast.timer);
    wardrobeToast.timer = setTimeout(() => el.classList.remove("on"), 3500);
}

// Vignette : le haut de la tenue rendu par le Clothes Renderer (lunatic_clothing), sinon un t-shirt à la couleur de la structure
function wardrobeThumb(outfit) {
    const shirt = () => h("span", { class: "wardrobe-shirt" });
    if (outfit.top === undefined || outfit.top === null) return shirt();
    const img = h("img", { src: `nui://lunatic_clothing/html/renderer/${outfit.model === "f" ? "female" : "male"}/11/${outfit.top}.png`, alt: "" });
    img.addEventListener("error", () => img.replaceWith(shirt()));
    return img;
}

function openWardrobe(data) {
    wardrobeData = data;
    wardrobeTab = data.model || "m";
    wardrobeSelected = null;
    wardrobeForm = null;
    wardrobeConfirm = null;
    const banner = $("wardrobeBanner");
    $("wardrobe").style.setProperty("--store", data.color || "");
    banner.style.backgroundImage = data.header ? `linear-gradient(180deg, #0000 40%, #0008), url("${data.header}")` : "";
    banner.classList.toggle("with-image", !!data.header);
    $("wardrobeLogo").classList.toggle("hidden", !data.logo);
    if (data.logo) $("wardrobeLogo").src = data.logo;
    $("wardrobeTitle").textContent = data.label || "Vestiaire";
    $("wardrobe").classList.remove("hidden");
    paintWardrobe();
}

function paintWardrobe() {
    paintWardrobeTabs();
    paintWardrobeGrid();
    paintWardrobeFoot();
}

function paintWardrobeTabs() {
    $("wardrobeTabs").replaceChildren(...WARDROBE_TABS.map(([model, label]) => {
        const count = wardrobeData.outfits.filter((o) => o.model === model).length;
        return h("button", { class: model === wardrobeTab ? "on" : "", onclick: () => { wardrobeTab = model; wardrobeForm = null; wardrobeConfirm = null; paintWardrobe(); } }, `${label} (${count})`);
    }));
}

function paintWardrobeGrid() {
    const list = wardrobeData.outfits.filter((o) => o.model === wardrobeTab);
    const other = wardrobeData.model && wardrobeTab !== wardrobeData.model;
    $("wardrobeGrid").replaceChildren(...(list.length ? list.map((o) => h("button", {
        class: `store-item wardrobe-item${o.id === wardrobeSelected ? " on" : ""}${o.wearable ? "" : " locked"}`,
        title: o.wearable ? o.label : `Tenue pour un personnage ${o.model === "f" ? "femme" : "homme"}`,
        onclick: () => selectOutfit(o),
    }, h("span", { class: "count" }, o.gradeLabel), wardrobeThumb(o), h("small", null, o.label))) : [
        h("p", { class: "store-empty" }, other ? "Aucune tenue de ce côté." : "Aucune tenue pour votre grade pour le moment."),
    ]));
}

function selectOutfit(outfit) {
    wardrobeSelected = outfit.id;
    wardrobeForm = null;
    wardrobeConfirm = null;
    if (outfit.wearable) nui("wardrobePreview", { id: outfit.id });
    paintWardrobe();
}

// Bas du panneau : récupérer, tenue civile, fermer ; outils du patron
function paintWardrobeFoot() {
    const selected = wardrobeSelected && wardrobeOutfit(wardrobeSelected);
    const parts = [];

    if (wardrobeForm) {
        parts.push(wardrobeFormView(selected));
    } else {
        parts.push(h("button", { class: "store-btn wardrobe-take", disabled: !selected || !selected.wearable || wardrobeBusy, onclick: takeOutfit },
            selected ? (selected.wearable ? `Récupérer « ${selected.label} »` : "Tenue d'un autre personnage") : "Choisissez une tenue"));

        if (wardrobeData.isBoss && wardrobeData.model) {
            const boss = [h("button", { class: "store-btn ghost", disabled: wardrobeBusy, onclick: () => { wardrobeForm = {}; paintWardrobeFoot(); } }, "Nouvelle tenue")];
            if (selected) {
                boss.push(h("button", { class: "store-btn ghost", disabled: wardrobeBusy, onclick: () => { wardrobeForm = { id: selected.id }; paintWardrobeFoot(); } }, "Modifier"));
                if (selected.model === wardrobeData.model) {
                    boss.push(h("button", { class: "store-btn ghost", disabled: wardrobeBusy, title: "Les vêtements portés en ouvrant le vestiaire deviennent ceux de cette tenue", onclick: () => bossDo("wardrobeReplace", { id: selected.id }, "Tenue mise à jour.") }, "Remplacer"));
                }
                boss.push(h("button", { class: `store-btn ghost${wardrobeConfirm === selected.id ? " danger" : ""}`, disabled: wardrobeBusy, onclick: () => deleteOutfit(selected) },
                    wardrobeConfirm === selected.id ? "Confirmer ?" : "Supprimer"));
            }
            parts.push(h("div", { class: "store-foot wardrobe-boss" }, boss));
        }
    }

    parts.push(h("div", { class: "store-foot" },
        h("button", { class: "store-btn ghost", onclick: () => { closeWardrobeView(); nui("wardrobeCivil"); } }, "Tenue civile"),
        h("button", { class: "store-btn ghost", onclick: () => { closeWardrobeView(); nui("wardrobeClose"); } }, "Fermer")));

    $("wardrobeFoot").replaceChildren(...parts);
}

// Formulaire du patron : nouvelle tenue (celle portée à l'ouverture) ou modification (nom, grade minimum)
function wardrobeFormView(selected) {
    const editing = wardrobeForm.id ? wardrobeOutfit(wardrobeForm.id) : null;
    const name = h("input", { class: "store-search wardrobe-input", maxlength: "40", placeholder: "Nom de la tenue (ex. Uniforme caisse)", value: editing ? editing.label : "" });
    const grade = h("select", { class: "store-search wardrobe-input" }, wardrobeData.grades.map((g) => {
        const option = h("option", { value: String(g.grade) }, `À partir de : ${g.label}`);
        if (editing ? g.grade === editing.minGrade : g === wardrobeData.grades[0]) option.selected = true;
        return option;
    }));
    const save = () => {
        const label = name.value.trim();
        if (label.length < 2) return wardrobeToast("Nom de 2 à 40 caractères.");
        if (editing) bossDo("wardrobeEdit", { id: editing.id, label, minGrade: Number(grade.value) }, "Tenue modifiée.");
        else bossDo("wardrobeCreate", { label, minGrade: Number(grade.value) }, "Tenue enregistrée.");
    };
    setTimeout(() => name.focus(), 0);
    return h("div", { class: "wardrobe-form" },
        h("b", null, editing ? `Modifier « ${editing.label} »` : `Nouvelle tenue ${wardrobeData.model === "f" ? "femme" : "homme"} (celle que vous portiez)`),
        name, grade,
        h("div", { class: "store-foot" },
            h("button", { class: "store-btn", disabled: wardrobeBusy, onclick: save }, "Enregistrer"),
            h("button", { class: "store-btn ghost", onclick: () => { wardrobeForm = null; paintWardrobeFoot(); } }, "Annuler")));
}

async function bossDo(action, payload, success) {
    if (wardrobeBusy) return;
    wardrobeBusy = true;
    paintWardrobeFoot();
    const res = inGame ? await nui(action, payload) : { ok: false, error: "Aperçu : pas d'enregistrement hors jeu." };
    wardrobeBusy = false;
    if (!res || !res.ok) {
        paintWardrobeFoot();
        return wardrobeToast((res && res.error) || "Action impossible.");
    }
    wardrobeForm = null;
    wardrobeConfirm = null;
    wardrobeToast(success);
    paintWardrobe();
}

function deleteOutfit(outfit) {
    if (wardrobeConfirm !== outfit.id) {
        wardrobeConfirm = outfit.id;
        return paintWardrobeFoot();
    }
    wardrobeSelected = null;
    bossDo("wardrobeDelete", { id: outfit.id }, "Tenue supprimée.");
}

function takeOutfit() {
    const outfit = wardrobeSelected && wardrobeOutfit(wardrobeSelected);
    if (!outfit || !outfit.wearable) return;
    closeWardrobeView();
    nui("wardrobeTake", { id: outfit.id });
}

function closeWardrobeView() {
    $("wardrobe").classList.add("hidden");
    wardrobeData = null;
}

// Glisser hors du panneau : le personnage tourne
$("wardrobeStage").addEventListener("mousedown", (e) => { wardrobeDrag = e.clientX; });
document.addEventListener("mouseup", () => { wardrobeDrag = null; });
document.addEventListener("mousemove", (e) => {
    if (wardrobeDrag === null || !wardrobeData) return;
    const dx = e.clientX - wardrobeDrag;
    wardrobeDrag = e.clientX;
    if (dx) nui("wardrobeRotate", { dx });
});

document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && wardrobeData && !$("wardrobe").classList.contains("hidden")) {
        closeWardrobeView();
        nui("wardrobeClose");
    }
});

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "wardrobeOpen") openWardrobe(msg.wardrobe);
    if (msg.action === "wardrobeData" && wardrobeData) {
        wardrobeData = msg.wardrobe;
        if (wardrobeSelected && !wardrobeOutfit(wardrobeSelected)) wardrobeSelected = null;
        paintWardrobe();
    }
    if (msg.action === "wardrobeClose") closeWardrobeView();
});

// ---------- Aperçu navigateur (index.html#wardrobe) ----------

if (!inGame && location.hash.includes("wardrobe")) {
    window.postMessage({
        action: "wardrobeOpen", wardrobe: {
            label: "Burger Shot", color: "#d3122a", header: null, logo: null, model: "m", isBoss: true, max: 40,
            grades: [{ grade: 0, label: "Recrue" }, { grade: 1, label: "Employé" }, { grade: 2, label: "Manager" }, { grade: 3, label: "Patron" }],
            outfits: [
                { id: 1, label: "Uniforme caisse", model: "m", minGrade: 0, gradeLabel: "Recrue", wearable: true, top: 15 },
                { id: 2, label: "Maillot Burger Shot", model: "m", minGrade: 1, gradeLabel: "Employé", wearable: true },
                { id: 3, label: "Tenue manager", model: "m", minGrade: 2, gradeLabel: "Manager", wearable: true },
                { id: 4, label: "Uniforme caisse", model: "f", minGrade: 0, gradeLabel: "Recrue", wearable: false },
            ],
        },
    }, "*");
}
