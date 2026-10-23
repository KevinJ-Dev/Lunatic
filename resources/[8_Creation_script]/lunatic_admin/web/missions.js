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
                m.reward ? (m.category === "contract" ? "Chaque offre paie entre 80 % et 120 % du gain, en argent sale." : "Gain payé en argent sale.")
                    : "Butin en objets (billets marqués, bijoux…), réglé dans les réglages avancés."),
            h("p", { class: "hint-line", style: "margin:0" }, "XP et influence : au crew, une fois par mission réussie ; l'influence compte pour le territoire où elle a lieu.")),
        h("div", { class: "item-actions" },
            m.ready ? h("button", { class: "btn small", onclick: advanced }, icon("i-tool"), "Réglages avancés") : null,
            saveButton(saveMission, false)));
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
