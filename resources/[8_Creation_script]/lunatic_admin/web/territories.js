"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, page Zones de territoires (fiche à gauche, liste au centre, carte à droite)
//  Zones circulaires : le crew avec le plus d'influence (ventes de drogue) la tient et touche ses bonus.
// ====================================================================

const territoryState = { data: null, staffView: false };

async function loadTerritories() {
    const res = await nui("action", { action: "territories.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    territoryState.data = res;
    if (illegalState.tab === "territories") paintIllegal();
}

async function territoryAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) await loadTerritories();
    return res;
}

function crewDot(color) {
    const el = h("span", { class: "struct-dot" });
    el.style.background = color || "#9650ff";
    return el;
}

function territoriesPage() {
    const d = territoryState.data;
    if (!d) {
        loadTerritories();
        return illegalLoading("Zones de territoires", "i-flag", "Chargement des territoires…");
    }
    const sel = illegalState.territorySel;
    const t = d.territories.find((entry) => entry.id === sel);
    if (sel !== "new" && !t) illegalState.territorySel = null;

    const rows = d.territories.map((entry) => h("button", { class: `list-row zone-row${entry.id === sel ? " active" : ""}${entry.active ? "" : " off"}`, onclick: () => selectTerritory(entry.id) },
        crewDot(entry.owner ? entry.owner.color : "#ffffff"),
        h("div", { class: "who" }, h("b", null, entry.label), h("span", null, entry.owner ? entry.owner.label : entry.active ? "Libre" : "Désactivé")),
        h("span", { class: "cnt" }, `+${entry.priceBonus} %`)));

    const side = [];
    if (t || sel === "new") side.push(territoryForm(t));
    if (t) {
        side.push(sideBlock(`Classement (${d.days} derniers jours)`, null,
            t.ranking.length ? t.ranking.map((r, index) => h("div", { class: "rank-line" },
                h("span", { class: "pid mono" }, String(index + 1)), crewDot(r.color), h("span", { class: "name" }, r.label),
                t.owner && t.owner.id === r.crew ? h("span", { class: "badge ok" }, "tient") : null,
                h("span", { class: "mono score" }, String(r.score))))
                : h("p", { class: "hint-line" }, "Aucune influence ici pour l'instant : elle se gagne en vendant de la drogue dans le cercle.")));
    }

    const map = territoryMap();
    const create = territoryState.createMode;
    const pane = h("div", { class: "map-pane" },
        h("div", { class: "map-head" },
            h("b", null, t ? t.label : sel === "new" ? "Nouveau territoire" : "Los Santos"),
            territoryState.picking ? h("span", { class: "badge warn" }, "Cliquez sur la carte pour placer la zone") : create ? h("span", { class: "badge warn" }, "Cliquez sur la carte pour créer une zone") : null,
            h("button", { class: `btn small${create ? " primary" : ""}`, title: "Un clic sur la carte crée un territoire à cet endroit", onclick: () => {
                territoryState.createMode = !territoryState.createMode;
                territoryState.picking = false;
                paintIllegal();
            } }, icon("i-plus"), "Mode création"),
            h("button", { class: "btn small ghost", title: "Voir toutes les zones", onclick: () => map.fit() }, icon("i-maximize"))),
        map.el);

    return {
        title: "Zones de territoires",
        sub: `Le crew avec le plus d'influence (ventes de drogue des ${d.days} derniers jours) tient la zone dès qu'il atteint le seuil. Recalcul toutes les ${Math.max(1, Math.round(d.refresh / 60))} min.`,
        actions: [
            h("button", { class: `btn small${territoryState.staffView ? " primary" : ""}`, title: "Affiche les zones sur votre carte en jeu, même sans crew", onclick: async () => {
                const enabled = !territoryState.staffView;
                const res = await act("territories.staffView", { enabled }, null);
                if (!res) return;
                territoryState.staffView = enabled;
                paintIllegal();
            } }, icon("i-eye"), territoryState.staffView ? "Masquer en jeu" : "Voir en jeu"),
        ],
        layout: "map-layout",
        side,
        center: h("div", { class: "zone-list" },
            h("div", { class: "section-head" }, "Zones", h("span", { class: "count" }, String(d.territories.length))),
            rows.length ? rows : h("p", { class: "hint-line" }, "Aucun territoire : « Mode création » sur la carte, ou ajoutez-en un à votre position."),
            h("button", { class: "btn small", style: "margin-top:10px", onclick: () => illegalSwitch(() => { illegalState.territorySel = "new"; }) }, icon("i-plus"), "Ajouter à ma position")),
        editor: pane,
        mounted: () => drawTerritories(),
    };
}

function selectTerritory(id) {
    if (id === illegalState.territorySel) return;
    illegalSwitch(() => {
        illegalState.territorySel = id;
        territoryState.picking = false;
    });
}

// Une seule carte, gardée d'un affichage à l'autre (même vue, tuiles déjà chargées)
function territoryMap() {
    if (!territoryState.map) {
        territoryState.map = gtaMap();
        territoryState.fitted = false;
    }
    return territoryState.map;
}

const territoryDraft = () => (illegalState.draft && illegalState.draft.kind === "territory" ? illegalState.draft.data : null);

function drawTerritories() {
    const map = territoryState.map;
    const d = territoryState.data;
    if (!map || !d) return;
    const sel = illegalState.territorySel;
    const draft = territoryDraft();
    map.clear();

    for (const t of d.territories) {
        const editing = t.id === sel && draft;
        const x = editing && draft.x != null ? draft.x : t.x;
        const y = editing && draft.x != null ? draft.y : t.y;
        map.circle(x, y, editing ? draft.radius : t.radius, {
            color: t.owner ? t.owner.color : "#ffffff", weight: t.id === sel ? 3 : 1.5, fill: t.id === sel ? 0.4 : 0.2, dashed: !t.active,
            label: `${t.label}${t.owner ? ` · ${t.owner.label}` : ""}`,
        }, () => selectTerritory(t.id));
    }
    if (sel === "new" && draft && draft.x != null) {
        map.circle(draft.x, draft.y, draft.radius, { color: "#9650ff", weight: 3, fill: 0.35, dashed: true, label: draft.label || "Nouveau territoire" });
    }

    const picking = territoryState.createMode || territoryState.picking;
    map.setClick(picking ? placeOnMap : null, picking);

    // Cadrage : tout au premier affichage, puis la zone choisie quand elle change
    if (!territoryState.fitted) {
        territoryState.fitted = true;
        territoryState.focused = sel;
        requestAnimationFrame(() => map.fit());
    } else if (territoryState.focused !== sel) {
        territoryState.focused = sel;
        const t = d.territories.find((entry) => entry.id === sel);
        if (t) map.focus(t.x, t.y);
    }
}

// Clic sur la carte : place la zone en cours, ou crée une zone (mode création)
function placeOnMap(x, y) {
    if (!insideGtaMap(x, y)) return toast("Position hors de la carte.", "error");
    const position = { x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10 };
    const draft = territoryDraft();
    if (territoryState.picking && draft) {
        Object.assign(draft, position);
        territoryState.picking = false;
        paintIllegal();
        return;
    }
    illegalSwitch(() => {
        illegalState.territorySel = "new";
        illegalState.prefill = position;
    });
}

// Fiche du territoire, dans la colonne de gauche (la carte prend la place de droite)
function territoryForm(t) {
    const d = illegalDraft("territory", t ? t.id : "new", t ? `Territoire ${t.label}` : "Nouveau territoire",
        () => (t ? { label: t.label, radius: t.radius, priceBonus: t.priceBonus, xpBonus: t.xpBonus, minInfluence: t.minInfluence, active: t.active }
            : { label: "", radius: 150, priceBonus: 20, xpBonus: 20, minInfluence: 10, active: true }),
        saveTerritory);
    const radius = draftNumber(d, "radius", 25, 600);
    radius.addEventListener("input", () => drawTerritories());

    const where = d.x != null ? `Position choisie sur la carte : ${d.x.toFixed(0)}, ${d.y.toFixed(0)}`
        : t ? `Centre : ${t.x.toFixed(0)}, ${t.y.toFixed(0)}` : "Centre : votre position en jeu (ou placez-la sur la carte).";

    return sideBlock(t ? "Édition" : "Nouveau territoire", null,
        h("div", { class: "side-form" },
            h("div", { class: "field" }, h("label", null, "Nom"), draftText(d, "label", { placeholder: "Ex. Grove Street" })),
            fieldRow("Rayon (m)", radius),
            fieldRow("Seuil d'influence", draftNumber(d, "minInfluence", 0, 100000)),
            fieldRow("Bonus prix (%)", draftNumber(d, "priceBonus", 0, 200)),
            fieldRow("Bonus XP (%)", draftNumber(d, "xpBonus", 0, 200)),
            h("div", { class: "mode-list" }, draftToggle(d, "active", "Actif", "Désactivé : absent des cartes, plus de bonus.")),
            h("p", { class: "hint-line" }, where),
            h("div", { class: "side-actions" },
                h("button", { class: `btn small${territoryState.picking ? " primary" : ""}`, title: "Le prochain clic sur la carte place le centre de la zone", onclick: () => {
                    territoryState.picking = !territoryState.picking;
                    territoryState.createMode = false;
                    paintIllegal();
                } }, icon("i-crosshair"), "Placer sur la carte"),
                t ? h("button", { class: "btn small ghost", title: "Recentrer la zone sur votre position en jeu", onclick: () => territoryAct("territories.move", { id: t.id }, "Territoire recentré sur votre position.") }, icon("i-player"), "Ma position") : null,
                t ? h("button", { class: "btn small ghost", onclick: () => act("territories.tp", { id: t.id }, null) }, icon("i-goto"), "TP") : null),
            h("div", { class: "side-actions" },
                saveButton(saveTerritory, !t),
                t ? h("button", { class: "btn small ghost", title: "Remettre l'influence à zéro dans cette zone", onclick: async () => {
                    const yes = await confirmBox(`Remettre « ${t.label} » à zéro ?`, "L'influence gagnée jusqu'ici ne compte plus dans cette zone ; le crew qui la tient la perd.", "Remettre à zéro", true);
                    if (yes) territoryAct("territories.reset", { id: t.id }, "Territoire remis à zéro.");
                } }, icon("i-undo"), "Reset") : null,
                t ? h("button", { class: "btn small danger", onclick: async () => {
                    const yes = await confirmBox(`Supprimer « ${t.label} » ?`, "La zone disparaît de la carte des crews.", "Supprimer", true);
                    if (!yes) return;
                    const res = await act("territories.delete", { id: t.id }, "Territoire supprimé.");
                    if (!res) return;
                    illegalSaved();
                    illegalState.territorySel = null;
                    await loadTerritories();
                } }, icon("i-trash")) : null)));
}

async function saveTerritory() {
    const draft = illegalState.draft;
    if (!draft || draft.kind !== "territory") return;
    const d = draft.data;
    const creating = draft.key === "new";
    const res = await act("territories.save", { id: creating ? null : draft.key, ...d },
        creating ? (d.x != null ? "Territoire créé." : "Territoire créé à votre position.") : "Territoire enregistré.");
    if (!res) return;
    illegalSaved();
    territoryState.createMode = false;
    territoryState.picking = false;
    await loadTerritories();
    if (creating) {
        const added = latestOf(territoryState.data.territories.filter((t) => t.label === d.label.trim()));
        illegalState.territorySel = added ? added.id : null;
    }
    paintIllegal();
}
