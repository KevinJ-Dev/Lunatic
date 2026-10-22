"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, onglet Braquages (étape 7b)
//  Supérettes, bijouterie, banques Fleeca : réglages, cibles détectées par modèle, points ajoutés à la main,
//  lieux braqués récemment. Le déroulement en jeu est dans lunatic_illegal.
// ====================================================================

const heistState = { data: null, staffView: false };

const HEIST_HELP = {
    store: "Toutes les supérettes de la carte : caisses et coffres détectés par leur modèle. Crochetage de la caisse, perçage du coffre.",
    jewelry: "Vangelico : vitrines détectées par leur modèle, à briser une par une avec une arme en main.",
    fleeca: "Banques Fleeca : porte du coffre détectée par son modèle, à pirater ; ensuite, casiers à percer dans le coffre.",
};

async function loadHeists() {
    const res = await nui("action", { action: "heists.info", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    heistState.data = res;
    if (illegalState.tab === "heists") paintIllegal();
}

async function heistAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) await loadHeists();
    return res;
}

function heistActionSummary(a) {
    const loot = (a.loot || []).map((l) => `${l.min === l.max ? l.min : `${l.min}-${l.max}`} × ${l.label}${l.chance < 100 ? ` (${l.chance} %)` : ""}`).join(", ");
    return [
        `${a.duration} s`,
        a.tool ? `outil : ${a.toolLabel}${a.breakChance ? ` (casse ${a.breakChance} % en cas d'échec)` : ""}` : "sans outil",
        `alerte ${a.alert} %`,
        a.count ? `${a.count} casiers` : null,
        loot ? `butin : ${loot}` : null,
    ].filter(Boolean).join(" · ");
}

function heistsPanel() {
    const d = heistState.data;
    if (!d) {
        loadHeists();
        return h("div", { class: "empty" }, icon("i-lock"), "Chargement des braquages…");
    }

    const states = d.states.length
        ? h("div", { class: "table" }, d.states.map((s) => h("div", { class: "row point-row" },
            h("span", { class: `status${s.active ? " on" : ""}` }),
            h("div", { class: "who" }, h("b", null, `${s.typeLabel} · ${s.x.toFixed(0)}, ${s.y.toFixed(0)}`),
                h("span", null, `${s.active ? "braquage en cours" : "déjà braqué"} · ${s.done} cible(s) prise(s)${s.doorOpen ? " · porte du coffre ouverte" : ""} · disponible dans ${Math.max(1, Math.round(s.left / 60))} min`)),
            h("button", { class: "btn small ghost", title: "Rendre le lieu disponible tout de suite", onclick: () => heistAct("heists.reset", { key: s.key, label: s.typeLabel }, "Lieu à nouveau disponible.") }, icon("i-undo"), "Rendre disponible"))))
        : h("p", { class: "hint-line", style: "margin:0" }, "Aucun lieu braqué récemment.");

    const cards = d.types.map((t) => {
        const s = t.settings;
        const actions = t.actions.map((a) => h("div", null,
            h("div", { class: "section-head", style: "margin-top:14px" }, a.label,
                a.points ? h("button", { class: "btn small", style: "order:1", onclick: () => openHeistPoint(a) }, icon("i-plus"), "Point à ma position") : null),
            h("p", { class: "hint-line", style: "margin:0 0 6px" }, heistActionSummary(a)),
            h("p", { class: "hint-line", style: "margin:0 0 6px" }, a.models.length ? `Détection automatique : ${a.models.join(", ")}` : (a.id === "locker" ? "Dans le coffre, une fois la porte ouverte (pas de point)." : "Pas de détection automatique : points à placer.")),
            a.points && a.points.length ? h("div", { class: "table" }, a.points.map((p, i) => h("div", { class: "row point-row" },
                h("span", { class: "pid mono" }, String(i + 1)),
                h("div", { class: "who" }, h("b", null, p.label), h("span", null, `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}`)),
                h("div", { class: "btn-row" },
                    h("button", { class: "btn small", onclick: () => heistAct("heists.movePoint", { id: p.id }, "Point replacé à votre position.") }, icon("i-crosshair"), "Définir"),
                    h("button", { class: "btn small ghost", onclick: () => act("heists.tpPoint", { id: p.id }, null) }, icon("i-goto"), "TP"),
                    h("button", { class: "btn small ghost", title: "Supprimer", onclick: () => heistAct("heists.deletePoint", { id: p.id }, "Point supprimé.") }, icon("i-trash")))))) : null));

        return h("div", { class: "card", style: "margin-top:16px" },
            h("div", { class: "card-head dev-head" },
                h("div", { class: "drug-title" }, h("div", { class: "who" },
                    h("b", null, t.label, s.enabled ? h("span", { class: "badge ok ready-badge" }, "Actif") : h("span", { class: "badge muted ready-badge" }, "Désactivé")),
                    h("span", { class: "muted" }, `${s.police} policier${s.police > 1 ? "s" : ""} en service minimum · ${s.cooldown} min avant de rebraquer le même lieu · ${s.crewOnly ? `crews level ${s.minLevel}+` : "ouvert à tous"}`))),
                h("button", { class: "btn small ghost", onclick: () => openHeistSettings(t) }, icon("i-edit"), "Réglages")),
            h("p", { class: "hint-line", style: "margin:0" }, HEIST_HELP[t.id]),
            actions);
    });

    return h("div", null,
        h("div", { class: "card" },
            h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, "Lieux braqués récemment"),
                h("div", { class: "btn-row" },
                    h("button", { class: `btn small${heistState.staffView ? " primary" : ""}`, title: "Affiche en jeu, en orange, les cibles détectées autour de vous et les points ajoutés", onclick: async () => {
                        const enabled = !heistState.staffView;
                        const res = await act("heists.staffView", { enabled }, null);
                        if (!res) return;
                        heistState.staffView = enabled;
                        paintIllegal();
                    } }, icon("i-eye"), heistState.staffView ? "Masquer les cibles en jeu" : "Voir les cibles en jeu"),
                    d.fenceMissing.length ? h("button", { class: "btn small", title: `Ajoute au recelleur : ${d.fenceMissing.join(", ")}`, onclick: async () => {
                        const res = await heistAct("heists.seedFence", {}, null);
                        if (res) toast(`${res.created} objet(s) de butin ajouté(s) au recelleur.`, "ok");
                    } }, icon("i-sparkle"), "Ajouter le butin au recelleur") : null)),
            d.fenceMissing.length ? readyHint([`le recelleur ne rachète pas encore : ${d.fenceMissing.join(", ")}`]) : null,
            h("p", { class: "hint-line", style: "margin:0 0 10px" }, "Les billets marqués et les bijoux s'écoulent chez le recelleur. Un lieu braqué ne peut plus l'être pendant son délai ; la porte d'une Fleeca se referme à la fin du délai."),
            states),
        cards);
}

function openHeistPoint(action) {
    const label = h("input", { class: "input", maxlength: "60", placeholder: "Ex. LTD de Grove Street, Fleeca Route 68" });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-plus"), "Ajouter à ma position");
        submit.addEventListener("click", async () => {
            const res = await heistAct("heists.addPoint", { kind: action.id, label: label.value.trim() }, "Point ajouté à votre position.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, `Point : ${action.label}`), h("p", null, "Pour une cible que la détection automatique ne trouve pas : placez-vous juste devant, face à elle.")),
            h("div", { class: "body" }, label),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    label.focus();
}

async function openHeistSettings(t) {
    const items = await loadCatalogItems();
    const known = new Set(items.map((i) => i.name));
    const d = heistState.data;
    const s = JSON.parse(JSON.stringify(t.settings));
    const num = (value, min, max) => h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(value) });
    const police = num(s.police, 0, 20);
    const cooldown = num(s.cooldown, 5, 1440);
    const minLevel = num(s.minLevel, 1, d.maxLevel);
    let enabled = s.enabled !== false;
    let crewOnly = s.crewOnly === true;
    const toggle = (label, hint, get, set) => {
        const row = h("div", { class: `perm${get() ? " on" : ""}` }, h("span", { class: "switch" }), h("span", { class: "txt" }, h("span", null, label), h("code", null, hint)));
        row.addEventListener("click", () => { set(!get()); row.classList.toggle("on", get()); });
        return row;
    };

    // Un bloc par action (caisse, coffre, vitrine, porte, casier)
    const blocks = t.actions.map((a) => {
        const draft = { duration: a.duration, tool: a.tool || "", breakChance: a.breakChance, alert: a.alert, count: a.count, models: a.models.slice(), loot: (a.loot || []).map((l) => ({ item: l.item, min: l.min, max: l.max, chance: l.chance })) };
        const duration = num(draft.duration, 3, 300);
        const tool = itemPicker(items, draft.tool);
        tool.placeholder = "aucun outil";
        const breakChance = num(draft.breakChance, 0, 100);
        const alert = num(draft.alert, 0, 100);
        const count = a.id === "locker" ? num(draft.count || 4, 1, 20) : null;
        const models = h("input", { class: "input mono", value: draft.models.join(", "), placeholder: "aucun (points à placer)" });
        const list = h("div", { class: "ingredient-list" });
        const paint = () => list.replaceChildren(...draft.loot.map((entry, index) => {
            const name = itemPicker(items, entry.item);
            const field = (key, min, max, title) => {
                const input = h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(entry[key]), title });
                input.addEventListener("input", () => { entry[key] = Number(input.value || 0); });
                return input;
            };
            name.addEventListener("input", () => { entry.item = name.value.trim(); });
            return h("div", { class: "ingredient-row loot-row" }, name, field("min", 1, 1000, "Minimum"), field("max", 1, 1000, "Maximum"), field("chance", 1, 100, "Chance (%)"),
                h("button", { class: "btn small ghost", onclick: () => { draft.loot.splice(index, 1); paint(); } }, icon("i-trash")));
        }));
        paint();

        const read = () => ({
            duration: Number(duration.value), tool: tool.value.trim(), breakChance: Number(breakChance.value), alert: Number(alert.value),
            count: count ? Number(count.value) : undefined, models: models.value.split(/[\s,;]+/).map((m) => m.trim()).filter(Boolean), loot: draft.loot,
        });

        const node = h("div", { class: "card", style: "margin:0" },
            h("h3", { class: "card-title" }, a.label),
            h("div", { class: "event-form-row" },
                h("div", { class: "field" }, h("label", null, "Durée (secondes)"), duration),
                h("div", { class: "field" }, h("label", null, "Alerte police (%)"), alert)),
            h("div", { class: "event-form-row" },
                h("div", { class: "field" }, h("label", null, "Outil nécessaire"), tool),
                h("div", { class: "field" }, h("label", null, "Casse de l'outil si échec (%)"), breakChance)),
            count ? h("div", { class: "field" }, h("label", null, "Casiers par braquage"), count) : null,
            a.id === "locker" ? null : h("div", { class: "field" }, h("label", null, "Modèles détectés (noms ou hash 0x… lus avec « Infos entité » de l'onglet Développeur)"), models),
            h("div", { class: "field" }, h("label", null, "Butin (objet · min · max · chance %)"), list,
                h("button", { class: "btn small ghost", style: "justify-self:start", onclick: () => {
                    if (draft.loot.length >= 8) return toast("8 objets maximum.", "error");
                    draft.loot.push({ item: "", min: 1, max: 1, chance: 100 });
                    paint();
                } }, icon("i-plus"), "Ajouter un objet")));
        return { id: a.id, node, read, draft };
    });

    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Enregistrer");
        submit.addEventListener("click", async () => {
            const actions = {};
            for (const b of blocks) {
                const value = b.read();
                if (value.tool && !known.has(value.tool)) return toast(`L'outil « ${value.tool} » n'existe pas dans ox_inventory.`, "error");
                if (value.loot.some((l) => !known.has(l.item))) return toast("Un objet du butin n'existe pas dans ox_inventory.", "error");
                actions[b.id] = value;
            }
            const res = await heistAct("heists.saveSettings", { type: t.id, settings: { enabled, police: Number(police.value), cooldown: Number(cooldown.value), crewOnly, minLevel: Number(minLevel.value), actions } }, "Réglages enregistrés.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, `Réglages · ${t.label}`), h("p", null, HEIST_HELP[t.id])),
            h("div", { class: "body event-form" },
                h("div", { class: "mode-list" },
                    toggle("Braquage actif", "Désactivé : plus aucune cible de ce type.", () => enabled, (v) => { enabled = v; }),
                    toggle("Réservé aux crews", "Sinon : ouvert à tout le monde.", () => crewOnly, (v) => { crewOnly = v; })),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Policiers en service minimum"), police),
                    h("div", { class: "field" }, h("label", null, "Délai avant de rebraquer le lieu (min)"), cooldown)),
                h("div", { class: "field" }, h("label", null, "Level de crew minimum (si réservé aux crews)"), minLevel),
                blocks.map((b) => b.node)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
}
