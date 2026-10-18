"use strict";

// ====================================================================
//  lunatic_admin — lot 4 : page Outils (modes, téléportation, coordonnées, véhicules)
//  Chargé après app.js, dont il utilise les outils (h, icon, nui, act, can, toast…).
// ====================================================================

const TOOL_MODES = [
    { id: "noclip", label: "Noclip", help: "Vol libre à travers les murs, invisible et invincible. Raccourci : F2." },
    { id: "invisible", label: "Invisibilité", help: "Les autres joueurs ne vous voient plus." },
    { id: "godmode", label: "Invincibilité", help: "Vous ne prenez plus aucun dégât." },
    { id: "ghost", label: "Mode fantôme (godmod invisible)", help: "Invisible et invincible en un clic. Touche à choisir dans les raccourcis FiveM." },
    { id: "names", label: "Noms au-dessus des têtes", help: "[ID] Prénom Nom des joueurs proches, couleur du rang pour le staff." },
    { id: "coords", label: "Coordonnées à l'écran", help: "Position et orientation affichées en haut de l'écran." },
];
const QUICK_VEHICLES = ["adder", "sultan", "police", "bati", "sanchez", "buzzard2"];
const DELETE_RADII = [10, 25, 50];

let toolsDom = null;
let coordsTimer = null;
let deleteRadius = 25;
let careRadius = 25;
const pendingModes = new Set();

function hasAnyTool() {
    return can("players.heal") || ["noclip", "invisible", "godmode", "names", "coords", "tpm", "vehicles"].some((t) => can(`tools.${t}`));
}

function renderTools() {
    const root = $("view-tools");

    // Structure gardée entre deux rafraîchissements (champ du modèle conservé)
    if (!toolsDom || !root.contains(toolsDom.modes)) {
        toolsDom = {
            modes: h("div", { class: "mode-list" }),
            right: h("div", { class: "tools-col" }),
            coords: null,
        };
        root.replaceChildren(h("div", { class: "content" },
            h("div", { class: "page-head" }, h("div", { class: "grow" },
                h("h1", { class: "page-title" }, "Outils"),
                h("div", { class: "page-sub" }, "Les modes restent actifs jusqu'à ce que vous les coupiez, même panel fermé.")
            )),
            h("div", { class: "scroll" }, h("div", { class: "tools-grid" },
                h("div", { class: "tools-col" }, h("div", { class: "card" }, h("h3", { class: "card-title" }, "Modes"), toolsDom.modes)),
                toolsDom.right
            ))
        ));
    }

    paintModes();

    // Reconstruit la colonne de droite si les permissions ont changé
    const signature = ["tpm", "coords", "vehicles"].map((tool) => (can(`tools.${tool}`) ? 1 : 0)).join("") + (can("players.heal") ? 1 : 0);
    if (toolsDom.signature !== signature) {
        toolsDom.signature = signature;
        toolsDom.coords = null;
        buildToolsRight();
    }

    startCoordsPolling();
}

function paintModes() {
    const active = state.tools || {};
    toolsDom.modes.replaceChildren(...TOOL_MODES.map((mode) => {
        const allowed = can(`tools.${mode.id}`);
        const on = active[mode.id] === true;
        const row = h("div", {
            class: `perm${on ? " on" : ""}${allowed ? "" : " locked"}${pendingModes.has(mode.id) ? " pending" : ""}`,
            title: allowed ? null : "Permission manquante",
        },
        h("span", { class: "switch" }),
        h("span", { class: "txt" }, h("span", null, mode.label), h("code", null, mode.help))
        );
        if (allowed) row.addEventListener("click", () => toggleMode(mode.id, !on));
        return row;
    }));
}

async function toggleMode(mode, enabled) {
    if (pendingModes.has(mode)) return;
    pendingModes.add(mode);
    paintModes();
    const res = await act("tool.toggle", { tool: mode, enabled }, null);
    pendingModes.delete(mode);
    if (res && res.tools && typeof res.tools === "object" && !Array.isArray(res.tools)) state.tools = res.tools;
    else if (res) state.tools = {};
    paintModes();
}

function buildToolsRight() {
    const cards = [];

    if (can("players.heal")) {
        const radius = h("div", { class: "segmented" });
        const paintCare = () => radius.replaceChildren(...DELETE_RADII.map((r) =>
            h("button", { "aria-checked": String(careRadius === r), onclick: () => { careRadius = r; paintCare(); } }, `${r} m`)));
        paintCare();
        cards.push(h("div", { class: "card" },
            h("h3", { class: "card-title" }, "Soins de zone"),
            h("div", { class: "btn-row", style: "align-items:center" },
                radius,
                h("button", { class: "btn primary", onclick: async () => {
                    const res = await act("player.careZone", { radius: careRadius }, null);
                    if (res) toast(`${res.count || 0} joueur(s) soigné(s), réanimé(s) et nourri(s).`, "ok");
                } }, icon("i-heart"), "Soigner la zone")
            ),
            h("p", { class: "hint-line" }, "Relève, soigne et nourrit tous les joueurs dans le rayon, vous compris.")
        ));
    }

    if (can("tools.tpm")) {
        cards.push(h("div", { class: "card" },
            h("h3", { class: "card-title" }, "Téléportation"),
            h("button", { class: "btn primary", onclick: () => act("tool.tpm", {}, "Téléportation au marqueur.") }, icon("i-goto"), "Aller au marqueur"),
            h("p", { class: "hint-line" }, "Posez d'abord un marqueur sur la carte. Une touche peut aussi être assignée dans les raccourcis FiveM.")
        ));
    }

    if (can("tools.coords")) {
        toolsDom.coords = h("div", { class: "coords-box" });
        cards.push(h("div", { class: "card" },
            h("h3", { class: "card-title" }, "Coordonnées"),
            toolsDom.coords,
            h("div", { class: "btn-row" },
                h("button", { class: "btn small", onclick: () => copyCoords(false) }, icon("i-copy"), "Copier vector3"),
                h("button", { class: "btn small", onclick: () => copyCoords(true) }, icon("i-copy"), "Copier vector4")
            )
        ));
    }

    if (can("tools.vehicles")) {
        const model = h("input", { class: "input mono", placeholder: "Nom du modèle (ex. adder)", maxlength: "32" });
        const spawnBtn = h("button", { class: "btn primary" }, icon("i-car"), "Faire apparaître");
        const spawn = async () => {
            const name = model.value.trim().toLowerCase();
            if (!name) return toast("Entrez un nom de modèle.", "error");
            spawnBtn.disabled = true;
            try {
                const res = await nui("vehicleSpawn", { model: name });
                if (res && res.ok) toast(`Véhicule « ${name} » apparu.`, "ok");
                else toast((res && res.error) || "Le véhicule n'a pas pu apparaître.", "error");
            } finally {
                spawnBtn.disabled = false;
            }
        };
        spawnBtn.addEventListener("click", spawn);
        model.addEventListener("keydown", (e) => { if (e.key === "Enter") spawn(); });

        const quick = h("div", { class: "durations" }, QUICK_VEHICLES.map((name) => {
            const chip = h("button", null, name);
            chip.addEventListener("click", () => { model.value = name; spawn(); });
            return chip;
        }));

        const radius = h("div", { class: "segmented" });
        const paintRadius = () => radius.replaceChildren(...DELETE_RADII.map((r) =>
            h("button", { "aria-checked": String(deleteRadius === r), onclick: () => { deleteRadius = r; paintRadius(); } }, `${r} m`)));
        paintRadius();

        cards.push(h("div", { class: "card" },
            h("h3", { class: "card-title" }, "Véhicules"),
            h("div", { class: "spawn-row" }, model, spawnBtn),
            quick,
            h("div", { class: "btn-row" },
                h("button", { class: "btn small", onclick: () => act("vehicle.repair", {}, "Véhicule réparé et nettoyé.") }, icon("i-tool"), "Réparer"),
                h("button", { class: "btn small", onclick: () => act("vehicle.flip", {}, "Véhicule retourné.") }, icon("i-undo"), "Retourner"),
                h("button", { class: "btn small danger", onclick: () => act("vehicle.delete", { radius: 0 }, "Véhicule supprimé.") }, icon("i-trash"), "Supprimer le mien")
            ),
            h("div", { class: "btn-row", style: "margin-top:10px;align-items:center" },
                radius,
                h("button", { class: "btn small danger", onclick: deleteAround }, icon("i-trash"), "Supprimer les véhicules vides autour")
            )
        ));
    }

    toolsDom.right.replaceChildren(...cards);
}

async function deleteAround() {
    const yes = await confirmBox("Supprimer les véhicules autour ?", `Tous les véhicules vides dans un rayon de ${deleteRadius} m seront supprimés.`, "Supprimer", true);
    if (!yes) return;
    const res = await act("vehicle.delete", { radius: deleteRadius }, null);
    if (res) toast(`${res.count || 0} véhicule(s) supprimé(s).`, "ok");
}

// ---------- Coordonnées ----------

let lastCoords = null;

function startCoordsPolling() {
    if (coordsTimer || !toolsDom.coords) return;
    const poll = async () => {
        if (view !== "tools" || document.body.classList.contains("hidden") || !toolsDom || !toolsDom.coords) {
            clearInterval(coordsTimer);
            coordsTimer = null;
            return;
        }
        try {
            const c = await nui("getCoords");
            if (c && typeof c.x === "number") {
                lastCoords = c;
                toolsDom.coords.replaceChildren(
                    ...[["x", c.x], ["y", c.y], ["z", c.z], ["h", c.h]].map(([label, value]) => h("div", null, h("span", null, label), h("b", null, value.toFixed(2))))
                );
            }
        } catch (e) {
            // panel fermé entre-temps
        }
    };
    poll();
    coordsTimer = setInterval(poll, 500);
}

function copyText(text) {
    // navigator.clipboard n'est pas disponible dans l'interface FiveM : copie par zone de texte
    const area = document.createElement("textarea");
    area.value = text;
    document.body.append(area);
    area.select();
    document.execCommand("copy");
    area.remove();
    toast(`Copié : ${text}`, "ok");
}

function copyCoords(withHeading) {
    if (!lastCoords) return toast("Coordonnées pas encore disponibles.", "error");
    const c = lastCoords;
    copyText(withHeading
        ? `vector4(${c.x.toFixed(2)}, ${c.y.toFixed(2)}, ${c.z.toFixed(2)}, ${c.h.toFixed(2)})`
        : `vector3(${c.x.toFixed(2)}, ${c.y.toFixed(2)}, ${c.z.toFixed(2)})`);
}
