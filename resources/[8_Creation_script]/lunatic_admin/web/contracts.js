"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, onglet Missions (étape 7a)
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

function contractProblems(type) {
    const problems = [];
    for (const kind of type.kinds) if (!kind.points.length) problems.push(`aucun point « ${kind.label.toLowerCase()} »`);
    const unknown = (type.settings.loot || []).filter((l) => l.missing).length;
    if (unknown) problems.push(`${unknown} objet${unknown > 1 ? "s" : ""} de butin inconnu${unknown > 1 ? "s" : ""}`);
    return problems;
}

function contractsPanel() {
    const d = contractState.data;
    if (!d) {
        loadContracts();
        return h("div", { class: "empty" }, icon("i-flag"), "Chargement des contrats…");
    }

    const active = d.active.length
        ? h("div", { class: "table" }, d.active.map((c) => h("div", { class: "row point-row" },
            h("span", { class: "status on" }),
            h("div", { class: "who" }, h("b", null, `${c.crew} · ${c.title}`), h("span", null, `${c.stageText} · accepté par ${c.acceptedBy} · reste ${Math.max(0, Math.round(c.left / 60))} min`)),
            h("button", { class: "btn small ghost", title: "Annuler le contrat (véhicule et gardes supprimés)", onclick: async () => {
                const yes = await confirmBox(`Annuler le contrat de ${c.crew} ?`, "Le contrat s'arrête sans récompense ; le véhicule et les gardes sont supprimés.", "Annuler le contrat", true);
                if (yes) contractAct("contracts.cancel", { crewId: c.crewId, label: c.crew }, "Contrat annulé.");
            } }, icon("i-x"), "Annuler"))))
        : h("p", { class: "hint-line", style: "margin:0" }, "Aucun contrat en cours.");

    const cards = d.types.map((t) => {
        const s = t.settings;
        const problems = s.enabled ? contractProblems(t) : [];
        const kinds = t.kinds.map((kind) => h("div", null,
            h("div", { class: "section-head", style: "margin-top:14px" }, `${kind.label} (${kind.points.length})`,
                h("button", { class: "btn small", style: "order:1", onclick: () => openContractPoint(kind) }, icon("i-plus"), "Ajouter à ma position")),
            kind.points.length ? h("div", { class: "table" }, kind.points.map((p, i) => h("div", { class: "row point-row" },
                h("span", { class: "pid mono" }, String(i + 1)),
                h("div", { class: "who" }, h("b", null, p.label), h("span", null, `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}`)),
                h("div", { class: "btn-row" },
                    h("button", { class: "btn small", onclick: () => contractAct("contracts.movePoint", { id: p.id }, "Point replacé à votre position.") }, icon("i-crosshair"), "Définir"),
                    h("button", { class: "btn small ghost", onclick: () => act("contracts.tpPoint", { id: p.id }, null) }, icon("i-goto"), "TP"),
                    h("button", { class: "btn small ghost", title: "Supprimer", onclick: () => contractAct("contracts.deletePoint", { id: p.id }, "Point supprimé.") }, icon("i-trash")))))) : null));

        const loot = (s.loot || []).map((l) => `${l.min === l.max ? l.min : `${l.min}-${l.max}`} × ${l.label} (${l.chance} %)`).join(" · ");
        return h("div", { class: "card", style: "margin-top:16px" },
            h("div", { class: "card-head dev-head" },
                h("div", { class: "drug-title" }, h("div", { class: "who" },
                    h("b", null, t.label, s.enabled ? readyBadge(problems) : h("span", { class: "badge muted ready-badge" }, "Désactivé")),
                    h("span", { class: "muted" }, `level ${s.minLevel}+ · ${money(s.rewardMin)} à ${money(s.rewardMax)} · ${s.xp} XP · ${s.duration} min · alerte police ${s.alertChance} %`))),
                h("button", { class: "btn small ghost", onclick: () => openContractSettings(t) }, icon("i-edit"), "Réglages")),
            h("p", { class: "hint-line", style: "margin:0" }, CONTRACT_HELP[t.id]),
            t.id === "theft" ? h("p", { class: "hint-line" }, `Modèles : ${(s.vehicles || []).join(", ")}`) : null,
            t.id === "cargo" ? h("p", { class: "hint-line" }, `Gardes : ${s.guards} × ${s.guardModel} armés de ${s.guardWeapon}`) : null,
            h("p", { class: "hint-line" }, loot ? `Butin possible : ${loot}` : "Pas de butin en plus de l'argent."),
            readyHint(problems),
            kinds);
    });

    return h("div", null,
        h("div", { class: "card" },
            h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, `Contrats en cours (${d.active.length})`)),
            h("p", { class: "hint-line", style: "margin:0 0 10px" }, "Chaque crew reçoit ses propres offres sur sa tablette (onglet Missions), renouvelées régulièrement. Seuls les membres des rangs autorisés acceptent un contrat ; tout le crew peut ensuite y participer. Récompense en argent sale, XP du crew et butin éventuel."),
            active),
        cards);
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
    const minLevel = num(s.minLevel, 1, d.maxLevel);
    const rewardMin = num(s.rewardMin, 0, 1000000);
    const rewardMax = num(s.rewardMax, 0, 1000000);
    const xp = num(s.xp, 0, 10000);
    const duration = num(s.duration, 3, 120);
    const alertChance = num(s.alertChance, 0, 100);
    const vehicles = h("input", { class: "input mono", value: (s.vehicles || []).join(", "), placeholder: "sultan, buffalo, felon" });
    const guards = num(s.guards || 0, 0, 10);
    const guardModel = h("input", { class: "input mono", value: s.guardModel || "", placeholder: "g_m_y_mexgoon_01" });
    const guardWeapon = h("input", { class: "input mono", value: s.guardWeapon || "", placeholder: "WEAPON_PISTOL" });
    let enabled = s.enabled !== false;
    const enabledRow = h("div", { class: `perm${enabled ? " on" : ""}` }, h("span", { class: "switch" }), h("span", { class: "txt" }, h("span", null, "Proposé aux crews"), h("code", null, "Désactivé : plus aucune offre de ce type.")));
    enabledRow.addEventListener("click", () => { enabled = !enabled; enabledRow.classList.toggle("on", enabled); });

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
                enabled, minLevel: Number(minLevel.value), rewardMin: Number(rewardMin.value), rewardMax: Number(rewardMax.value), xp: Number(xp.value),
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
                h("div", { class: "mode-list" }, enabledRow),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Level de crew minimum"), minLevel),
                    h("div", { class: "field" }, h("label", null, "Durée (minutes)"), duration)),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Récompense minimum ($)"), rewardMin),
                    h("div", { class: "field" }, h("label", null, "Récompense maximum ($)"), rewardMax)),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "XP du crew"), xp),
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
