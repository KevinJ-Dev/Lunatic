"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, onglet Territoires (étape 4)
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

function territoriesPanel() {
    const d = territoryState.data;
    if (!d) {
        loadTerritories();
        return h("div", { class: "empty" }, icon("i-flag"), "Chargement des territoires…");
    }

    const cards = d.territories.map((t) => {
        const ranking = t.ranking.length
            ? h("div", { class: "table" }, t.ranking.map((r, index) => h("div", { class: "row point-row" },
                h("span", { class: "pid mono" }, String(index + 1)),
                h("div", { class: "who" }, h("b", null, crewDot(r.color), " ", r.label), h("span", null, `${r.score} d'influence`)),
                t.owner && t.owner.id === r.crew ? h("span", { class: "badge ok" }, "Tient la zone")
                    : index === 0 && r.score < t.minInfluence ? h("span", { class: "badge muted" }, `seuil : ${t.minInfluence}`) : null)))
            : h("p", { class: "hint-line", style: "margin:0" }, "Aucune influence dans la zone pour l'instant : elle se gagne en vendant de la drogue dans le cercle.");

        const owner = t.owner
            ? h("span", { class: "badge ok ready-badge" }, crewDot(t.owner.color), `Tenu par ${t.owner.label}`)
            : h("span", { class: "badge muted ready-badge" }, "Libre");

        return h("div", { class: "card", style: "margin-top:16px" },
            h("div", { class: "card-head dev-head" },
                h("div", { class: "drug-title" },
                    h("div", { class: "who" },
                        h("b", null, t.label, owner, t.active ? null : h("span", { class: "badge muted ready-badge" }, "Désactivé")),
                        h("span", { class: "muted" }, `Rayon ${t.radius} m · bonus +${t.priceBonus} % au prix, +${t.xpBonus} % d'XP · seuil ${t.minInfluence} · ${t.x.toFixed(1)}, ${t.y.toFixed(1)}`))),
                h("div", { class: "btn-row" },
                    h("button", { class: "btn small", title: "Recentrer la zone sur votre position", onclick: () => territoryAct("territories.move", { id: t.id }, "Territoire recentré sur votre position.") }, icon("i-crosshair"), "Définir"),
                    h("button", { class: "btn small ghost", onclick: () => act("territories.tp", { id: t.id }, null) }, icon("i-goto"), "TP"),
                    h("button", { class: "btn small ghost", onclick: () => openTerritory(t) }, icon("i-edit"), "Modifier"),
                    h("button", { class: "btn small ghost", title: "Remettre l'influence à zéro dans cette zone", onclick: async () => {
                        const yes = await confirmBox(`Remettre « ${t.label} » à zéro ?`, "L'influence gagnée jusqu'ici ne compte plus dans cette zone ; le crew qui la tient la perd.", "Remettre à zéro", true);
                        if (yes) territoryAct("territories.reset", { id: t.id }, "Territoire remis à zéro.");
                    } }, icon("i-undo")),
                    h("button", { class: "btn small ghost", title: "Supprimer", onclick: async () => {
                        const yes = await confirmBox(`Supprimer « ${t.label} » ?`, "La zone disparaît de la carte des crews.", "Supprimer", true);
                        if (yes) territoryAct("territories.delete", { id: t.id }, "Territoire supprimé.");
                    } }, icon("i-trash")))),
            ranking);
    });

    return h("div", null,
        h("div", { class: "card" },
            h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, `Territoires (${d.territories.length})`),
                h("div", { class: "btn-row" },
                    h("button", { class: `btn small${territoryState.staffView ? " primary" : ""}`, title: "Affiche les zones sur votre carte, même sans crew", onclick: async () => {
                        const enabled = !territoryState.staffView;
                        const res = await act("territories.staffView", { enabled }, null);
                        if (!res) return;
                        territoryState.staffView = enabled;
                        paintIllegal();
                    } }, icon("i-eye"), territoryState.staffView ? "Masquer sur ma carte" : "Voir sur ma carte"),
                    h("button", { class: "btn small primary", onclick: () => openTerritory(null) }, icon("i-plus"), "Nouveau à ma position"))),
            h("p", { class: "hint-line", style: "margin:0" },
                `Le crew qui a le plus d'influence dans un cercle la tient dès qu'il atteint le seuil. L'influence se gagne en vendant de la drogue ; seuls les ${d.days} derniers jours comptent, l'ancienne de moins en moins. Recalcul toutes les ${Math.max(1, Math.round(d.refresh / 60))} min et juste après chaque vente dans la zone. Les membres de crews voient les zones sur leur carte : à eux en vert, aux autres en rouge, libres en blanc.`)),
        d.territories.length ? cards : h("div", { class: "card", style: "margin-top:16px" }, h("p", { class: "hint-line", style: "margin:0" }, "Aucun territoire : placez-vous au centre de la zone en jeu, puis « Nouveau à ma position »."))
    );
}

function openTerritory(t) {
    const num = (value, min, max) => h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(value) });
    const label = h("input", { class: "input", maxlength: "60", placeholder: "Ex. Grove Street, Port de Los Santos", value: t ? t.label : "" });
    const radius = num(t ? t.radius : 150, 25, 600);
    const priceBonus = num(t ? t.priceBonus : 20, 0, 200);
    const xpBonus = num(t ? t.xpBonus : 20, 0, 200);
    const minInfluence = num(t ? t.minInfluence : 10, 0, 100000);
    let active = t ? t.active : true;
    const activeRow = h("div", { class: `perm${active ? " on" : ""}` }, h("span", { class: "switch" }), h("span", { class: "txt" }, h("span", null, "Actif"), h("code", null, "Désactivé : absent de la carte, plus de bonus.")));
    activeRow.addEventListener("click", () => { active = !active; activeRow.classList.toggle("on", active); });

    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), t ? "Enregistrer" : "Créer à ma position");
        submit.addEventListener("click", async () => {
            const res = await territoryAct("territories.save", {
                id: t ? t.id : null, label: label.value.trim(), radius: Number(radius.value), priceBonus: Number(priceBonus.value),
                xpBonus: Number(xpBonus.value), minInfluence: Number(minInfluence.value), active,
            }, t ? "Territoire enregistré." : "Territoire créé à votre position.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, t ? `Modifier ${t.label}` : "Nouveau territoire"), h("p", null, t ? "« Définir » recentre la zone sur votre position." : "Le centre de la zone sera votre position actuelle en jeu.")),
            h("div", { class: "body event-form" },
                h("div", { class: "field" }, h("label", null, "Nom"), label),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Rayon (25 à 600 m)"), radius),
                    h("div", { class: "field" }, h("label", null, "Seuil d'influence pour tenir la zone"), minInfluence)),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Bonus de prix des ventes (%)"), priceBonus),
                    h("div", { class: "field" }, h("label", null, "Bonus d'XP du crew (%)"), xpBonus)),
                h("p", { class: "hint-line" }, "Les bonus s'appliquent aux ventes de drogue du crew qui tient la zone, faites dans la zone."),
                h("div", { class: "mode-list" }, activeRow)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    label.focus();
}
