"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, page Missions
//  Catalogue de toutes les missions : catégories à gauche, liste au centre, réglages communs à droite
//  (statut, XP, influence, policiers, bypass, gain, limite par jour, level du crew).
//  Les réglages avancés des braquages et contrats déjà en jeu s'ouvrent depuis la fiche.
// ====================================================================

const missionState = { data: null, category: null };

const MISSION_SHORT = { heist: "BRAQ", contract: "CONT", traffic: "TRAF", street: "RUE" };

async function loadMissions() {
    const res = await nui("action", { action: "missions.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    missionState.data = res;
    if (illegalState.tab === "missions") paintIllegal();
}

function missionsPage() {
    const d = missionState.data;
    if (!d) {
        loadMissions();
        return illegalLoading("Missions", "i-crosshair", "Chargement des missions…");
    }
    // Réglages avancés et points des contrats : chargés en même temps
    if (!contractState.data) loadContracts();
    if (!heistState.data) loadHeists();

    const category = d.categories.some((c) => c.id === missionState.category) ? missionState.category : null;
    const sel = illegalState.missionSel;
    const selected = d.missions.find((m) => m.id === sel);
    const count = (id) => d.missions.filter((m) => !id || m.category === id).length;

    const categories = [{ id: null, label: "Toutes" }, ...d.categories].map((c) => h("button", { class: `list-row${c.id === category ? " active" : ""}`, onclick: () => { missionState.category = c.id; paintIllegal(); } },
        h("span", { class: "name" }, c.label), h("span", { class: "cnt" }, String(count(c.id)))));

    const rows = d.missions.filter((m) => !category || m.category === category).map((m) => h("button", {
        class: `list-row mission-row${m.id === sel ? " active" : ""}${m.ready ? "" : " soon"}`,
        onclick: () => m.id !== sel && illegalSwitch(() => { illegalState.missionSel = m.id; }),
    },
        h("span", { class: "mission-tag" }, MISSION_SHORT[m.category] || m.category),
        h("span", { class: "name" }, m.label),
        !m.ready ? h("span", { class: "badge muted" }, "à venir")
            : m.settings.enabled ? h("span", { class: "badge ok" }, "active") : h("span", { class: "badge ban" }, "désactivée")));

    const side = [sideBlock("Catégories", null, categories)];
    const contract = selected && selected.link && selected.link.kind === "contract" && contractState.data && contractState.data.types.find((t) => t.id === selected.link.type);

    // Points en ville du contrat choisi
    if (contract) {
        for (const kind of contract.kinds) {
            side.push(sideBlock(`${kind.label} (${kind.points.length})`, iconButton("i-plus", "Ajouter un point à votre position", () => openContractPoint(kind)),
                kind.points.length ? kind.points.map((p, i) => pointLine(i + 1, p.label, p, [
                    iconButton("i-crosshair", "Replacer à votre position", () => contractAct("contracts.movePoint", { id: p.id }, "Point replacé à votre position.")),
                    iconButton("i-goto", "TP", () => act("contracts.tpPoint", { id: p.id }, null)),
                    iconButton("i-trash", "Supprimer", () => contractAct("contracts.deletePoint", { id: p.id }, "Point supprimé.")),
                ])) : h("p", { class: "hint-line" }, "Aucun point : le contrat ne sera pas proposé.")));
        }
    }

    // Lieux de la mission, avec TP : magasins de la page Braquages, ou lieux fixes (banques, bijouterie)
    if (selected && selected.holdup) {
        if (!holdupState.data) loadHoldups();
        const points = holdupState.data ? holdupState.data.points.filter((p) => p.type === selected.holdup) : [];
        side.push(sideBlock(`Lieux (${points.length})`, iconButton("i-edit", "Gérer les points dans la page Braquages", () => illegalSwitch(() => { illegalState.tab = "heists"; illegalState.holdupType = selected.holdup; illegalState.holdupSel = null; })),
            points.length ? points.map((p, i) => pointLine(i + 1, p.label, p, [iconButton("i-goto", "TP", () => act("holdups.tp", { id: p.id }, null))]))
                : h("p", { class: "hint-line" }, holdupState.data ? "Aucun point : ajoutez-en dans la page Braquages." : "Chargement…")));
    } else if (selected && selected.places.length) {
        side.push(sideBlock(`Lieux (${selected.places.length})`, null,
            selected.places.map((p) => pointLine(p.index, p.label, p, [iconButton("i-goto", "TP", () => act("missions.tp", { id: selected.id, index: p.index }, null))]))));
    }

    // Contrats en cours, sous la liste
    const active = contractState.data ? contractState.data.active : [];
    const running = active.length ? h("div", null,
        h("div", { class: "section-head", style: "margin-top:22px" }, "Contrats en cours", h("span", { class: "count" }, String(active.length))),
        h("div", { class: "table" }, active.map((c) => h("div", { class: "row point-row" },
            h("span", { class: "status on" }),
            h("div", { class: "who" }, h("b", null, `${c.crew} · ${c.title}`), h("span", null, `${c.stageText} · accepté par ${c.acceptedBy} · reste ${Math.max(0, Math.round(c.left / 60))} min`)),
            h("button", { class: "btn small ghost", title: "Annuler le contrat (véhicule et gardes supprimés)", onclick: async () => {
                const yes = await confirmBox(`Annuler le contrat de ${c.crew} ?`, "Le contrat s'arrête sans récompense ; le véhicule et les gardes sont supprimés.", "Annuler le contrat", true);
                if (yes) contractAct("contracts.cancel", { crewId: c.crewId, label: c.crew }, "Contrat annulé.");
            } }, icon("i-x"), "Annuler"))))) : null;

    return {
        title: "Missions",
        sub: "Toutes les activités illégales et leurs réglages communs, appliqués en jeu tout de suite. Les missions « à venir » sont déjà réglables.",
        side,
        center: h("div", null, h("div", { class: "zone-list" }, rows), running),
        editor: missionEditor(selected),
    };
}

function missionEditor(m) {
    if (!m) return emptySelection("i-crosshair", "Choisissez une mission.");
    const max = missionState.data.maxLevel;
    const d = illegalDraft("mission", m.id, `Mission ${m.label}`, () => ({ ...m.settings }), saveMission);

    const status = h("select", { class: "input" }, h("option", { value: "1", selected: d.enabled }, "Active"), h("option", { value: "0", selected: !d.enabled }, "Désactivée"));
    status.addEventListener("change", () => { d.enabled = status.value === "1"; });

    // Réglages avancés : fenêtre des braquages ou des contrats déjà en jeu
    const advanced = () => {
        if (m.link.kind === "heist") {
            const t = heistState.data && heistState.data.types.find((entry) => entry.id === m.link.type);
            return t ? openHeistSettings(t) : toast("Chargement des braquages…", "info");
        }
        const t = contractState.data && contractState.data.types.find((entry) => entry.id === m.link.type);
        return t ? openContractSettings(t) : toast("Chargement des contrats…", "info");
    };

    const head = h("div", { class: "item-head" }, h("div", { class: "pic" }, icon("i-crosshair")),
        h("div", { class: "who" }, h("b", null, m.label), h("span", { class: "mono" }, m.id),
            m.ready ? null : h("span", { class: "badge warn", style: "justify-self:start" }, "pas encore disponible")));

    return h("aside", { class: "item-editor" }, head,
        h("div", { class: "item-scroll" },
            h("p", { class: "hint-line", style: "margin:0" }, m.description),
            m.ready ? null : h("p", { class: "ready-hint" }, icon("i-warn"), h("span", null, "Pas encore en jeu : ces réglages serviront dès que la mission arrivera.")),
            h("div", { class: "section-head", style: "margin-top:6px" }, "Informations"),
            fieldRow("Statut", status),
            fieldRow("XP du crew", draftNumber(d, "xp", 0, 10000)),
            fieldRow("Influence", draftNumber(d, "influence", 0, 1000)),
            fieldRow("Policiers requis", draftNumber(d, "police", 0, 20)),
            m.reward ? fieldRow("Gain ($)", draftNumber(d, "reward", 0, 1000000)) : null,
            fieldRow("Limite / jour", draftNumber(d, "dailyLimit", 0, 500)),
            h("p", { class: "hint-line", style: "margin:0" }, `0 = sans limite, pour tout le serveur · aujourd'hui : ${m.today}`),
            h("div", { class: "mode-list" },
                draftToggle(d, "bypass", "Bypass police", "Lançable même sans policier en service."),
                draftToggle(d, "levelRequired", "Level du crew", m.category === "heist" ? "Activé : réservé aux crews du level requis. Sinon : ouvert à tous." : "Activé : level de crew minimum requis.")),
            fieldRow(`Level requis (1 à ${max})`, draftNumber(d, "minLevel", 1, max)),
            h("p", { class: "hint-line", style: "margin:0" },
                m.reward ? (m.category === "contract" ? "Chaque offre paie entre 80 % et 120 % du gain, en argent sale."
                    : m.category === "street" ? "Gain en argent sale, entre 60 % et 140 % selon la victime. Ouvert à tous : XP et influence si le joueur a un crew."
                        : "Gain en argent sale (entre 80 % et 120 %) quand le vendeur a rempli le sac.")
                    : "Butin en objets (billets marqués, bijoux…), réglé dans les réglages avancés."),
            h("p", { class: "hint-line", style: "margin:0" }, "XP et influence : au crew, une fois par mission réussie ; l'influence compte pour le territoire où elle a lieu.")),
        h("div", { class: `item-actions${m.holdup && m.link ? " three" : ""}` },
            m.holdup ? h("button", { class: "btn small", title: "Arme exigée, durée, délai, alarme, résistance du vendeur, butin", onclick: () => (holdupState.data ? openHoldupSettings(m.holdup) : loadHoldups()) }, icon("i-tool"), m.link ? "Vendeur" : "Réglages avancés") : null,
            m.link ? h("button", { class: "btn small", onclick: advanced }, icon("i-tool"), m.holdup ? "Coffre" : "Réglages avancés") : null,
            m.advanced ? h("button", { class: "btn small", onclick: () => openMissionAdvanced(m) }, icon("i-tool"), "Réglages avancés") : null,
            saveButton(saveMission, false)));
}

// Réglages propres à une mission (champs décrits par le serveur) et son butin
async function openMissionAdvanced(m) {
    const items = await loadCatalogItems();
    const known = new Set(items.map((i) => i.name));
    const fields = m.advanced.map((f) => ({ ...f, input: f.options
        ? h("select", { class: "input" }, f.options.map((o) => h("option", { value: o.value, selected: o.value === f.value }, o.label)))
        : h("input", { class: "input mono", type: "number", min: String(f.min), max: String(f.max), value: String(f.value) }) }));

    const loot = (m.loot || []).map((l) => ({ item: l.item, min: l.min, max: l.max, chance: l.chance }));
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
            const advanced = {};
            for (const f of fields) advanced[f.key] = f.options ? f.input.value : Number(f.input.value);
            const res = await act("missions.saveAdvanced", { id: m.id, advanced, loot }, "Réglages enregistrés.");
            if (!res) return;
            close();
            await loadMissions();
        });
        return [
            h("header", null, h("h3", null, `Réglages · ${m.label}`), h("p", null, m.description)),
            h("div", { class: "body event-form" },
                fields.map((f) => h("div", { class: "field" }, h("label", null, f.label), f.input)),
                h("div", { class: "field" }, h("label", null, "Butin en plus du gain (objet · min · max · chance %)"), list,
                    h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
                        if (loot.length >= 8) return toast("8 objets maximum.", "error");
                        loot.push({ item: "", min: 1, max: 1, chance: 20 });
                        paint();
                    } }, icon("i-plus"), "Ajouter un objet"))),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
}

async function saveMission() {
    const draft = illegalState.draft;
    if (!draft || draft.kind !== "mission") return;
    const res = await act("missions.save", { id: draft.key, settings: draft.data }, "Mission enregistrée.");
    if (!res) return;
    illegalSaved();
    await loadMissions();
    paintIllegal();
}
