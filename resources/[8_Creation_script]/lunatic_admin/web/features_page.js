"use strict";

// ====================================================================
//  lunatic_admin — tuile Fonctionnalités
//  Onglets (Fonctionnalités, Gameplay, Nouveaux joueurs, Discord, puis ceux des systèmes ajoutés). Chaque section est
//  décrite ici (libellés, aides, groupes) ; les types et bornes viennent du serveur (server/features.lua).
//  Enregistrement par la barre du bas, appliqué en jeu tout de suite.
// ====================================================================

const ftState = { data: null, tab: "features", section: null, draft: null, saved: "" };

// Onglets : sections affichées (une liste à gauche s'il y en a plusieurs)
const FEATURE_TABS = [
    { id: "features", label: "Fonctionnalités", icon: "i-tool", sections: ["toggles"] },
    { id: "gameplay", label: "Gameplay", icon: "i-pulse", sections: ["needs", "inventory", "death", "deathScreen", "fuel", "misc", "population", "time"] },
    { id: "effects", label: "Effets", icon: "i-sparkle", sections: ["effects_cocaine", "effects_fentanyl", "effects_cannabis", "effects_meth", "effects_alcohol"] },
    { id: "idcard", label: "Carte d'identité", icon: "i-player", sections: ["idcard"] },
    { id: "weights", label: "Poids", icon: "i-box", sections: ["trunks"] },
    { id: "newPlayers", label: "Nouveaux joueurs", icon: "i-user-plus", sections: ["newPlayers"] },
    { id: "discord", label: "Discord", icon: "i-users", sections: ["discord"] },
];

// Sections : libellés et aides des champs ; groups = colonnes d'interrupteurs
const FEATURE_SECTIONS = {
    toggles: {
        label: "Fonctionnalités",
        groups: [{ label: "Gameplay", keys: ["pvp", "needs", "chat"] }, { label: "HUD", keys: ["hud", "minimap", "speedometer"] }],
        fields: {
            pvp: { label: "PvP", hint: "Dégâts entre joueurs" },
            needs: { label: "Faim / Soif", hint: "Désactivé : faim et soif en pause" },
            chat: { label: "Chat textuel", hint: "Désactivé : seul le staff peut écrire" },
            hud: { label: "HUD", hint: "Cercles de vie, faim, soif…" },
            minimap: { label: "Minimap", hint: "Carte en bas à gauche" },
            speedometer: { label: "Infos véhicule", hint: "Nom et classe du véhicule à l'écran" },
        },
    },
    needs: {
        label: "Faim & Soif", icon: "i-food",
        fields: {
            hunger: { label: "Perte de faim", hint: "Points perdus à chaque cycle (jauge pleine : 1 000 000)" },
            thirst: { label: "Perte de soif", hint: "Points perdus à chaque cycle" },
            sprint: { label: "Multiplicateur sprint", hint: "La perte est multipliée en courant", unit: "×" },
        },
    },
    inventory: {
        label: "Inventaire", icon: "i-box",
        fields: {
            weight: { label: "Poids maximum", hint: "Inventaire des joueurs (grammes)", unit: "g" },
            slots: { label: "Emplacements", hint: "Nombre de cases de l'inventaire" },
        },
    },
    death: {
        label: "Mort & Respawn", icon: "i-heart",
        fields: {
            enabled: { label: "Inconscience", hint: "Désactivé : réveil automatique à l'hôpital après 10 secondes, sans frais" },
            delay: { label: "Délai avant le réveil à l'hôpital", hint: "Avec au moins un secouriste en service : temps pendant lequel on peut être réanimé", unit: "s" },
            delayNoMedic: { label: "Délai sans secouriste", hint: "Quand aucun secouriste n'est en service (réduit pour garder le jeu fluide)", unit: "s" },
            fee: { label: "Frais d'hôpital", hint: "Retirés de la banque au réveil (sans aller sous 0)", money: true },
            clearInventory: { label: "Vider l'inventaire au réveil", hint: "Sauf les objets gardés ci-dessous" },
            keepCash: { label: "Garder le liquide", hint: "Quand l'inventaire est vidé" },
            keepItems: { label: "Objets gardés", hint: "Noms d'objets séparés par des virgules (ex. phone,id_card)" },
            callMedic: { label: "Appel des secours", hint: "[G] pendant l'inconscience : alerte et GPS pour les secouristes en service" },
            callCooldown: { label: "Délai entre deux appels", hint: "Un même joueur ne peut pas rappeler avant ce délai", unit: "s" },
            takeCallSeconds: { label: "Durée pour prendre un appel", hint: "Temps pendant lequel un secouriste peut prendre l'appel reçu ([Y] par défaut)", unit: "s" },
            medicRevive: { label: "Réanimation par les médecins", hint: "/reanimer, réservé aux services publics listés ci-dessous" },
            reviveDistance: { label: "Distance de réanimation", hint: "Distance maximale entre le secouriste et la personne", unit: "m" },
            medicTypes: { label: "Services qui réaniment", hint: "Types de services publics (tuile Services publics) séparés par des virgules, ex. medic" },
            eventRespawnDelay: { label: "Respawn dans un event", hint: "Délai avant la réapparition dans une zone d'event avec la règle « Respawn »", unit: "s" },
        },
    },
    deathScreen: {
        label: "Écran de mort", icon: "i-heart",
        fields: {
            title: { label: "Titre", hint: "En bas à droite ; le dernier mot s'affiche en rouge" },
            showMedics: { label: "Nombre de secouristes", hint: "Afficher combien de secouristes sont en service" },
            showDistance: { label: "Distance de l'EMS", hint: "« Un EMS a pris votre appel · à 1,2 km »" },
            responderRefresh: { label: "Mise à jour de la distance", hint: "Quand un EMS a pris l'appel", unit: "s" },
            freeCamera: { label: "Caméra libre", hint: "Tourner autour du personnage à la souris, zoom à la molette" },
            voice: { label: "Parler", hint: "Le vocal reste actif pendant l'inconscience (rien d'autre n'est possible)" },
            effect: { label: "Effet de mort GTA", hint: "Image sombre et grisée de GTA ; désactivé : on voit le jeu normalement" },
            shade: { label: "Assombrir les bords", hint: "Léger voile sombre autour de l'écran" },
        },
    },
    effects_cocaine: { label: "Cocaïne", icon: "i-sparkle", ...{
        fields: {
            enabled: { label: "Effet actif", hint: "Désactivé : la cocaïne se consomme sans effet" },
            duration: { label: "Durée de l'effet", hint: "Une nouvelle prise prolonge l'effet", unit: "s" },
            speed: { label: "Boost sprint", hint: "1 = normal, 1,49 au maximum", unit: "×" },
            shake: { label: "Tremblement de caméra", hint: "0 = aucun" },
            blur: { label: "Flou de mouvement", hint: "Pendant l'effet" },
            visual: { label: "Filtre visuel", hint: "Couleurs et animation à l'écran" },
            walk: { label: "Démarche", hint: "Démarche titubante (si prévue pour cette substance)" },
        },
    } },
    effects_fentanyl: { label: "Fentanyl", icon: "i-sparkle", ...{
        fields: {
            enabled: { label: "Effet actif", hint: "Désactivé : le fentanyl se consomme sans effet" },
            duration: { label: "Durée de l'effet", hint: "Une nouvelle prise prolonge l'effet", unit: "s" },
            speed: { label: "Boost sprint", hint: "1 = normal, 1,49 au maximum", unit: "×" },
            shake: { label: "Tremblement de caméra", hint: "0 = aucun" },
            blur: { label: "Flou de mouvement", hint: "Pendant l'effet" },
            visual: { label: "Filtre visuel", hint: "Couleurs et animation à l'écran" },
            walk: { label: "Démarche", hint: "Démarche titubante (si prévue pour cette substance)" },
        },
    } },
    effects_cannabis: { label: "Cannabis", icon: "i-sparkle", ...{
        fields: {
            enabled: { label: "Effet actif", hint: "Désactivé : joints et blunts se fument sans effet" },
            duration: { label: "Durée de l'effet", hint: "Une nouvelle prise prolonge l'effet", unit: "s" },
            speed: { label: "Boost sprint", hint: "1 = normal, 1,49 au maximum", unit: "×" },
            shake: { label: "Tremblement de caméra", hint: "0 = aucun" },
            blur: { label: "Flou de mouvement", hint: "Pendant l'effet" },
            visual: { label: "Filtre visuel", hint: "Couleurs et animation à l'écran" },
            walk: { label: "Démarche", hint: "Démarche titubante (si prévue pour cette substance)" },
        },
    } },
    effects_meth: { label: "Méthamphétamine", icon: "i-sparkle", ...{
        fields: {
            enabled: { label: "Effet actif", hint: "Désactivé : la meth se consomme sans effet" },
            duration: { label: "Durée de l'effet", hint: "Une nouvelle prise prolonge l'effet", unit: "s" },
            speed: { label: "Boost sprint", hint: "1 = normal, 1,49 au maximum", unit: "×" },
            shake: { label: "Tremblement de caméra", hint: "0 = aucun" },
            blur: { label: "Flou de mouvement", hint: "Pendant l'effet" },
            visual: { label: "Filtre visuel", hint: "Couleurs et animation à l'écran" },
            walk: { label: "Démarche", hint: "Démarche titubante (si prévue pour cette substance)" },
        },
    } },
    effects_alcohol: { label: "Alcool", icon: "i-food", ...{
        fields: {
            enabled: { label: "Effet actif", hint: "Désactivé : l'alcool se boit sans effet" },
            duration: { label: "Durée de l'effet", hint: "Une nouvelle prise prolonge l'effet", unit: "s" },
            speed: { label: "Boost sprint", hint: "1 = normal, 1,49 au maximum", unit: "×" },
            shake: { label: "Tremblement de caméra", hint: "0 = aucun" },
            blur: { label: "Flou de mouvement", hint: "Pendant l'effet" },
            visual: { label: "Filtre visuel", hint: "Couleurs et animation à l'écran" },
            walk: { label: "Démarche", hint: "Démarche titubante (si prévue pour cette substance)" },
        },
    } },
    trunks: {
        label: "Coffres des véhicules", icon: "i-car",
        fields: {
            trunkWeight: { label: "Poids des coffres", hint: "Multiplie le poids maximum de chaque classe (ox_inventory, data/vehicles.lua)", unit: "×" },
            trunkSlots: { label: "Emplacements des coffres", hint: "Multiplie le nombre de cases", unit: "×" },
            gloveWeight: { label: "Poids des boîtes à gants", hint: "Multiplie le poids maximum", unit: "×" },
            gloveSlots: { label: "Emplacements des boîtes à gants", hint: "Multiplie le nombre de cases. S'applique aux coffres ouverts ensuite (après un redémarrage d'ox_inventory pour ceux déjà chargés).", unit: "×" },
        },
    },
    fuel: {
        label: "Carburant", icon: "i-car",
        fields: {
            enabled: { label: "Consommation de carburant", hint: "Désactivé : les véhicules ne consomment rien" },
            consumption: { label: "Multiplicateur de consommation", hint: "1 = environ 12 % par minute à fond, 1,5 % au ralenti (selon la classe)", unit: "×" },
            startLevel: { label: "Niveau de départ", hint: "Réservoir d'un véhicule jamais utilisé", unit: "%" },
            price: { label: "Prix du litre", hint: "Aux pompes des stations-service (liquide, sinon banque)", money: true },
        },
    },
    idcard: {
        label: "Carte d'identité", icon: "i-player",
        fields: {
            delivery: { label: "Remise de la carte", hint: "Au guichet (Autres → Guichets de documents) ou automatique à la connexion", options: [
                { value: "police", label: "À retirer au guichet (poste de police)" }, { value: "auto", label: "Remise automatique à la connexion" }] },
            guide: { label: "Guider les nouveaux joueurs", hint: "Point GPS vers le guichet le plus proche tant que la carte n'a jamais été retirée" },
            firstFree: { label: "Premier document gratuit", hint: "Carte et permis : le premier est gratuit, ensuite c'est un duplicata payant (le permis est aussi remis à la réussite de l'auto-école)" },
            duplicatePrice: { label: "Prix du duplicata de carte", hint: "Carte perdue ou volée", money: true },
            licensePrice: { label: "Prix du duplicata de permis", hint: "Permis perdu ou volé (au guichet)", money: true },
            duration: { label: "Durée d'affichage", hint: "La carte disparaît ensuite (Retour arrière pour la fermer avant)", unit: "s" },
            showRadius: { label: "Rayon pour montrer la carte", hint: "Tous les joueurs à cette distance la voient", unit: "m" },
        },
    },
    misc: {
        label: "Confort & sécurité", icon: "i-shield",
        fields: {
            weaponBack: { label: "Arme dans le dos", hint: "Fusils, pompes, SMG visibles sur le dos quand ils ne sont pas en main" },
            safeZones: { label: "Zones sécurisées", hint: "Hôpitaux et commissariat : pas de tir ni de coups (config lunatic_gameplay)" },
            afk: { label: "Anti-AFK", hint: "Expulse les joueurs inactifs (jamais le staff)" },
            afkMinutes: { label: "Délai d'inactivité", hint: "Avertissement une minute avant", unit: "min" },
            afkOffDutyOnly: { label: "Seulement hors service", hint: "Les joueurs en service ne sont pas expulsés" },
        },
    },
    population: {
        label: "Densité population", icon: "i-users",
        fields: {
            peds: { label: "Densité piétons", hint: "0 = aucun, 1 = normal" },
            vehicles: { label: "Densité véhicules", hint: "Circulation" },
            parked: { label: "Véhicules garés", hint: "Voitures stationnées" },
            scenario: { label: "Scénarios PNJ", hint: "PNJ occupés (bancs, cafés…)" },
        },
    },
    time: {
        label: "Temps en jeu", icon: "i-clock",
        fields: { minute: { label: "Durée d'une minute de jeu", hint: "2 000 ms : une journée dure 48 minutes réelles", unit: "ms" } },
    },
    newPlayers: {
        label: "Économie de départ", icon: "i-coins",
        fields: {
            bank: { label: "Argent de départ (banque)", hint: "À la création du personnage", money: true },
            money: { label: "Argent de départ (liquide)", hint: "À la création du personnage", money: true },
            offDuty: { label: "Multiplicateur hors service", hint: "0,5 = 50 % du salaire hors service", unit: "×" },
        },
    },
    discord: {
        label: "Rich Presence", icon: "i-users",
        fields: {
            enabled: { label: "Activer", hint: "Affiche le serveur sur le profil Discord des joueurs" },
            appId: { label: "App ID", hint: "Application créée sur discord.com/developers" },
            asset: { label: "Asset Name", hint: "Nom de l'image dans l'application (Rich Presence → Art Assets)" },
            assetText: { label: "Asset Text", hint: "Texte au survol de l'image" },
            presence: { label: "Presence", hint: "{player_rp_name} {player_id} {player_street} {server_name} {server_players} {server_maxplayers}" },
        },
        preview: true,
    },
};

function renderFeatures() {
    if (ftState.data && $("view-features").childElementCount) return;
    paintFeatures();
    loadFeatures();
}

async function loadFeatures() {
    const res = await nui("action", { action: "features.get", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    ftState.data = res;
    paintFeatures();
}

function ftTabs() {
    // Onglets des systèmes ajoutés : seulement si le serveur connaît leurs sections
    return FEATURE_TABS.filter((t) => t.sections.some((s) => ftState.data.schema[s]));
}

function ftGo(changes) {
    guardUnsaved("features", () => {
        untrackUnsaved("features");
        Object.assign(ftState, changes, { draft: null });
        paintFeatures();
    });
}

function ftDraft(section) {
    if (ftState.draft && ftState.draft.section === section) return ftState.draft;
    const base = { section, values: { ...ftState.data.settings[section] } };
    ftState.draft = base;
    ftState.saved = JSON.stringify(base);
    trackUnsaved("features", {
        label: (FEATURE_SECTIONS[section] || {}).label || section,
        isDirty: () => !!ftState.draft && JSON.stringify(ftState.draft) !== ftState.saved,
        save: () => saveFeatures(),
        reset: () => { ftState.draft = null; paintFeatures(); },
    });
    return base;
}

async function saveFeatures() {
    const d = ftState.draft;
    if (!d) return;
    const res = await act("features.save", { section: d.section, values: d.values }, "Réglages enregistrés.");
    if (!res) return;
    untrackUnsaved("features");
    ftState.draft = null;
    await loadFeatures();
}

// ---------- Champs ----------

function ftField(section, key, values) {
    const schema = ftState.data.schema[section][key] || {};
    const meta = (FEATURE_SECTIONS[section].fields || {})[key] || { label: key };
    if (schema.type === "bool") {
        return h("div", { class: "mode-list" }, draftToggle(values, key, meta.label, meta.hint || ""));
    }
    if (meta.options) {
        const select = h("select", { class: "input" }, meta.options.map((o) => h("option", { value: o.value, selected: o.value === values[key] }, o.label)));
        select.addEventListener("change", () => { values[key] = select.value; });
        return h("div", { class: "ft-row" }, h("span", { class: "ft-label" }, h("b", null, meta.label), meta.hint ? h("small", null, meta.hint) : null), select);
    }
    if (schema.type === "string") {
        const input = h("input", { class: "input", maxlength: String(schema.maxLength || 120), value: values[key] ?? "" });
        input.addEventListener("input", () => { values[key] = input.value; paintDiscordPreview(); });
        return h("div", { class: "ft-row" }, h("span", { class: "ft-label" }, h("b", null, meta.label), meta.hint ? h("small", null, meta.hint) : null), input);
    }
    const unit = meta.money ? currencySymbol() : meta.unit || "";
    const number = h("input", { class: "input mono", type: "number", min: String(schema.min), max: String(schema.max), step: String(schema.step || 1), value: String(values[key]) });
    const range = h("input", { type: "range", min: String(schema.min), max: String(schema.max), step: String(schema.step || 1), value: String(values[key]) });
    range.addEventListener("input", () => { values[key] = Number(range.value); number.value = range.value; });
    number.addEventListener("input", () => { values[key] = number.value === "" ? "" : Number(number.value); range.value = number.value; });
    return h("div", { class: "ft-row" },
        h("span", { class: "ft-label" }, h("b", null, meta.label), meta.hint ? h("small", null, meta.hint) : null),
        h("span", { class: "ft-value" }, range, h("label", { class: "eco-amount" }, number, unit ? h("span", { class: "muted" }, unit) : null)));
}

function ftDefaults(section) {
    const d = ftDraft(section);
    for (const [key, schema] of Object.entries(ftState.data.schema[section])) d.values[key] = schema.default;
    paintFeatures();
}

// ---------- Mise en page ----------

function paintFeatures() {
    const root = $("view-features");
    if (!ftState.data) return root.replaceChildren(h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-tool"), "Chargement des fonctionnalités…")));

    const tabs = ftTabs();
    const tab = tabs.find((t) => t.id === ftState.tab) || tabs[0];
    const sections = tab.sections.filter((s) => ftState.data.schema[s]);
    const section = sections.includes(ftState.section) ? ftState.section : sections[0];
    const d = ftDraft(section);
    const meta = FEATURE_SECTIONS[section] || { label: section, fields: {} };

    const tabBar = h("div", { class: "img-tabs" }, tabs.map((t) => h("button", { class: `img-tab${t.id === tab.id ? " on" : ""}`, onclick: () => t.id !== tab.id && ftGo({ tab: t.id, section: null }) }, icon(t.icon), h("span", null, t.label))));

    let body;
    if (meta.groups) {
        body = h("div", { class: "ft-columns" }, meta.groups.map((g) => h("div", { class: "ft-column" },
            h("div", { class: "crew-sub", style: "text-align:left" }, g.label), g.keys.map((key) => ftField(section, key, d.values)))));
    } else {
        body = h("div", { class: "ft-list" }, Object.keys(meta.fields).filter((key) => ftState.data.schema[section][key]).map((key) => ftField(section, key, d.values)));
    }

    const content = h("section", { class: "crew-col ft-main" },
        h("div", { class: "crew-col-head" }, icon(meta.icon || tab.icon), meta.label,
            h("button", { class: "btn small ghost", style: "margin-left:auto", onclick: () => ftDefaults(section) }, icon("i-undo"), "Valeurs par défaut")),
        h("div", { class: "crew-scroll crew-col-body" }, body,
            meta.preview ? h("div", { class: "ft-preview", id: "ftDiscordPreview" }) : null,
            h("p", { class: "hint-line" }, "Enregistrez avec la barre du bas : appliqué en jeu tout de suite, sans redémarrage.")));

    const side = sections.length > 1 ? h("aside", { class: "sidebar crew-nav crew-scroll" },
        h("div", { class: "crew-block" }, h("div", { class: "crew-block-head" }, icon(tab.icon), tab.label),
            sections.map((s) => h("button", { class: `list-row${s === section ? " active" : ""}`, onclick: () => s !== section && ftGo({ section: s }) },
                icon((FEATURE_SECTIONS[s] || {}).icon || "i-tool"), h("span", { class: "name" }, (FEATURE_SECTIONS[s] || {}).label || s))))) : null;

    root.replaceChildren(h("div", { class: "img-page" }, tabBar, h("div", { class: `ft-body${side ? "" : " single"}` }, side, content)));
    paintDiscordPreview();
}

// Aperçu du Rich Presence (valeurs d'exemple pour les variables)
function paintDiscordPreview() {
    const box = document.getElementById("ftDiscordPreview");
    if (!box || !ftState.draft || ftState.draft.section !== "discord") return;
    const v = ftState.draft.values;
    const sample = { player_rp_name: "Jean Dupont", player_id: "12", player_street: "Grove Street", server_name: "Lunatic RP", server_players: "42", server_maxplayers: "64" };
    const text = String(v.presence || "").replace(/\{([\w_]+)\}/g, (all, key) => sample[key] ?? all);
    box.replaceChildren(
        h("div", { class: "ft-discord" },
            h("div", { class: "ft-discord-banner" }),
            h("div", { class: "ft-discord-body" },
                h("b", null, "Joueur"),
                h("small", null, "JOUE À"),
                h("div", { class: "ft-discord-game" },
                    h("span", { class: "ft-discord-asset" }, v.asset ? v.asset.slice(0, 2).toUpperCase() : "FM"),
                    h("span", null, h("b", null, "FiveM"), h("span", null, text || "—"), h("span", { class: "muted" }, v.assetText || ""))))),
        h("p", { class: "hint-line" }, v.enabled ? "Actif : mis à jour toutes les 15 secondes chez chaque joueur." : "Désactivé."));
}
