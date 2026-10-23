"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, contrats de la page Missions
//  Contrats de la tablette : réglages par type (livraison, vol sur commande, cargaison gardée), points en ville,
//  contrats en cours. Le déroulement en jeu est dans lunatic_illegal.
// ====================================================================

const contractState = { data: null };

const CONTRACT_HELP = {
    delivery: "Récupérer un colis scellé à un point de récupération, le livrer à un point de livraison avant la fin du temps. Le colis ne vaut rien pour un autre crew.",
    theft: "Voler un modèle précis garé à un point « véhicule à voler » et l'amener à un garage. La récompense baisse si le véhicule est abîmé.",
    cargo: "Une caisse gardée par des PNJ armés : les éliminer puis ouvrir la caisse. Les gardes apparaissent à l'arrivée du crew.",
};

async function loadContracts() {
    const res = await nui("action", { action: "contracts.info", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    contractState.data = res;
    if (illegalState.tab === "missions") paintIllegal();
}

async function contractAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) await loadContracts();
    return res;
}


function openContractPoint(kind) {
    const label = h("input", { class: "input", maxlength: "60", placeholder: "Ex. Ruelle de Strawberry, Garage de La Mesa" });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-plus"), "Ajouter à ma position");
        submit.addEventListener("click", async () => {
            const res = await contractAct("contracts.addPoint", { kind: kind.id, label: label.value.trim() }, "Point ajouté à votre position.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, kind.label), h("p", null, kind.id === "car_spawn" ? "Le véhicule apparaîtra là où vous vous tenez, tourné dans votre direction." : "Le point sera là où vous vous tenez. Son nom s'affiche sur la tablette du crew.")),
            h("div", { class: "body" }, label),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    label.focus();
}

async function openContractSettings(t) {
    const items = await loadCatalogItems();
    const known = new Set(items.map((i) => i.name));
    const s = JSON.parse(JSON.stringify(t.settings));
    const d = contractState.data;
    const num = (value, min, max) => h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(value) });
    const duration = num(s.duration, 3, 120);
    const alertChance = num(s.alertChance, 0, 100);
    const vehicles = h("input", { class: "input mono", value: (s.vehicles || []).join(", "), placeholder: "sultan, buffalo, felon" });
    const guards = num(s.guards || 0, 0, 10);
    const guardModel = h("input", { class: "input mono", value: s.guardModel || "", placeholder: "g_m_y_mexgoon_01" });
    const guardWeapon = h("input", { class: "input mono", value: s.guardWeapon || "", placeholder: "WEAPON_PISTOL" });

    const loot = (s.loot || []).map((l) => ({ item: l.item, min: l.min, max: l.max, chance: l.chance }));
    const list = h("div", { class: "ingredient-list" });
    const paint = () => list.replaceChildren(...loot.map((entry, index) => {
        const name = itemPicker(items, entry.item);
        const field = (key, min, max, title) => {
            const input = h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(entry[key]), title });
            input.addEventListener("input", () => { entry[key] = Number(input.value || 0); });
            return input;
        };
        name.addEventListener("input", () => { entry.item = name.value.trim(); });
        return h("div", { class: "ingredient-row loot-row" }, name, field("min", 1, 1000, "Minimum"), field("max", 1, 1000, "Maximum"), field("chance", 1, 100, "Chance (%)"),
            h("button", { class: "btn small ghost", onclick: () => { loot.splice(index, 1); paint(); } }, icon("i-trash")));
    }));
    paint();

    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Enregistrer");
        submit.addEventListener("click", async () => {
            if (loot.some((l) => !known.has(l.item))) return toast("Un objet du butin n'existe pas dans ox_inventory.", "error");
            const settings = {
                enabled: s.enabled !== false, minLevel: s.minLevel, rewardMin: s.rewardMin, rewardMax: s.rewardMax, xp: s.xp,
                duration: Number(duration.value), alertChance: Number(alertChance.value), loot,
            };
            if (t.id === "theft") settings.vehicles = vehicles.value.split(/[\s,;]+/).map((v) => v.trim()).filter(Boolean);
            if (t.id === "cargo") Object.assign(settings, { guards: Number(guards.value), guardModel: guardModel.value.trim(), guardWeapon: guardWeapon.value.trim() });
            const res = await contractAct("contracts.saveSettings", { type: t.id, settings }, "Réglages enregistrés.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, `Réglages · ${t.label}`), h("p", null, CONTRACT_HELP[t.id])),
            h("div", { class: "body event-form" },
                h("p", { class: "hint-line", style: "margin:0" }, "Statut, gain, XP, influence, policiers et level se règlent dans la page Missions."),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Durée (minutes)"), duration),
                    h("div", { class: "field" }, h("label", null, "Alerte police (%)"), alertChance)),
                t.id === "theft" ? h("div", { class: "field" }, h("label", null, "Modèles de véhicule (séparés par des virgules)"), vehicles) : null,
                t.id === "cargo" ? h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Nombre de gardes"), guards),
                    h("div", { class: "field" }, h("label", null, "Arme des gardes"), guardWeapon)) : null,
                t.id === "cargo" ? h("div", { class: "field" }, h("label", null, "Modèle de PNJ des gardes"), guardModel) : null,
                h("div", { class: "field" }, h("label", null, "Butin possible (objet · min · max · chance %)"), list,
                    h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
                        if (loot.length >= 10) return toast("10 objets maximum.", "error");
                        loot.push({ item: "", min: 1, max: 1, chance: 50 });
                        paint();
                    } }, icon("i-plus"), "Ajouter un objet"))),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
}
