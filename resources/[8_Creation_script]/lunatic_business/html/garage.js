"use strict";

// Garage des structures (doc Vision) : bannière, grille des véhicules de service (photo et nom), aperçu du véhicule choisi
// posé à la sortie (géré par le jeu), « Sortir le véhicule ». Un véhicule déjà sorti se range d'abord. Glisser : tourner.
// $, h et nui viennent de app.js.

let garageData = null;
let garageSelected = null;
let garageBusy = false;
let garageDrag = null;

const garageImage = (model) => `https://docs.fivem.net/vehicles/${model}.webp`;

function garageToast(text) {
    const el = $("garageToast");
    el.textContent = text;
    el.classList.add("on");
    clearTimeout(garageToast.timer);
    garageToast.timer = setTimeout(() => el.classList.remove("on"), 3500);
}

function openGarage(data) {
    garageData = data;
    garageSelected = data.out ? null : (data.vehicles[0] || {}).id || null;
    garageBusy = false;
    const banner = $("garageBanner");
    $("garage").style.setProperty("--store", data.color || "");
    banner.style.backgroundImage = data.header ? `linear-gradient(180deg, #0000 40%, #0008), url("${data.header}")` : "";
    banner.classList.toggle("with-image", !!data.header);
    $("garageLogo").classList.toggle("hidden", !data.logo);
    if (data.logo) $("garageLogo").src = data.logo;
    $("garageTitle").textContent = data.label || "Garage";
    $("garageSub").textContent = data.point ? `Garage · ${data.point}` : "Garage";
    $("garage").classList.remove("hidden");
    paintGarage();
}

function paintGarage() {
    $("garageGrid").replaceChildren(...(garageData.vehicles.length ? garageData.vehicles.map((v) => {
        const img = h("img", { src: garageImage(v.model), alt: "" });
        img.addEventListener("error", () => img.replaceWith(h("span", { class: "noimg" }, v.label.charAt(0).toUpperCase())));
        return h("button", {
            class: `store-item garage-item${v.id === garageSelected ? " on" : ""}`, title: v.model,
            disabled: !!garageData.out, onclick: () => selectVehicle(v),
        }, img, h("small", null, v.label));
    }) : [h("p", { class: "store-empty" }, "Aucun véhicule pour votre grade dans ce garage (parc réglé par le staff).")]));
    paintGarageFoot();
}

function selectVehicle(vehicle) {
    if (garageData.out || vehicle.id === garageSelected) return;
    garageSelected = vehicle.id;
    nui("garagePreview", { id: vehicle.id });
    paintGarage();
}

function paintGarageFoot() {
    const selected = garageData.vehicles.find((v) => v.id === garageSelected);
    const parts = [];

    if (garageData.out) {
        parts.push(h("p", { class: "store-note" }, `Vous avez déjà sorti : ${garageData.out}. Ramenez-le près du garage pour le ranger avant d'en prendre un autre.`));
        parts.push(h("button", { class: "store-btn garage-go", onclick: () => { closeGarageView(); nui("garageStore"); } }, `Ranger : ${garageData.out}`));
    } else {
        parts.push(h("button", { class: "store-btn garage-go", disabled: !selected || garageBusy, onclick: takeVehicle },
            garageBusy ? "Sortie en cours…" : selected ? `Sortir le véhicule · ${selected.label}` : "Choisissez un véhicule"));
    }

    parts.push(h("div", { class: "store-foot" }, h("button", { class: "store-btn ghost", onclick: () => { closeGarageView(); nui("garageClose"); } }, "Fermer")));
    $("garageFoot").replaceChildren(...parts);
}

async function takeVehicle() {
    if (garageBusy || !garageSelected) return;
    garageBusy = true;
    paintGarageFoot();
    const res = inGame ? await nui("garageTake", { id: garageSelected }) : { ok: false, error: "Aperçu : pas de véhicule hors jeu." };
    garageBusy = false;
    if (!res || !res.ok) {
        if (garageData) paintGarageFoot();
        return garageToast((res && res.error) || "Sortie impossible.");
    }
    closeGarageView();
}

function closeGarageView() {
    $("garage").classList.add("hidden");
    garageData = null;
}

// Glisser hors du panneau : la caméra tourne autour du véhicule
$("garageStage").addEventListener("mousedown", (e) => { garageDrag = e.clientX; });
document.addEventListener("mouseup", () => { garageDrag = null; });
document.addEventListener("mousemove", (e) => {
    if (garageDrag === null || !garageData) return;
    const dx = e.clientX - garageDrag;
    garageDrag = e.clientX;
    if (dx) nui("garageRotate", { dx });
});

document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && garageData && !$("garage").classList.contains("hidden")) {
        closeGarageView();
        nui("garageClose");
    }
});

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "garageOpen") openGarage(msg.garage);
    if (msg.action === "garageClose") closeGarageView();
});

// ---------- Aperçu navigateur (index.html#garage) ----------

if (!inGame && location.hash.includes("garage")) {
    window.postMessage({
        action: "garageOpen", garage: {
            label: "Weazel News", point: "Parking arrière", color: "#c8102e", header: null, logo: null, out: null,
            vehicles: [{ id: 1, label: "Van de reportage", model: "newsvan" }, { id: 2, label: "Rumpo", model: "rumpo" }, { id: 3, label: "Granger", model: "granger" }, { id: 4, label: "Véhicule perso", model: "custom_car_xyz" }],
        },
    }, "*");
}
