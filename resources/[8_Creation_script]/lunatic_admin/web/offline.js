"use strict";

// ====================================================================
//  lunatic_admin — lot F : joueurs hors ligne (onglet de la page Joueurs)
//  Recherche en base, fiche et actions : argent, métier, permis, ban, recréer, wipe.
// ====================================================================

let playersTab = "online"; // "online" | "offline"
let offlineResults = null;
let offlineSelected = null; // identifiant ESX (licence sans « license: »)
let offlineInfo = null;
let offlineSearchTimer = null;
let offlineForms = null; // { identifier, node } : formulaires gardés entre deux rafraîchissements

function switchPlayersTab(tab) {
    if (playersTab === tab) return;
    playersTab = tab;
    playerFilter.text = "";
    if (playersDom) playersDom.search.value = "";
    renderPlayers();
}

function scheduleOfflineSearch(text) {
    clearTimeout(offlineSearchTimer);
    offlineSearchTimer = setTimeout(async () => {
        const query = text.trim();
        if (query.length < 2) {
            offlineResults = null;
            return paintPlayerList();
        }
        const res = await nui("action", { action: "offline.search", payload: { query } });
        offlineResults = res && res.ok && Array.isArray(res.players) ? res.players : [];
        paintPlayerList();
    }, 300);
}

function paintOfflineList() {
    playersDom.count.textContent = offlineResults ? String(offlineResults.length) : "";
    if (!offlineResults) {
        return playersDom.list.replaceChildren(h("div", { class: "muted side-empty" }, "Tapez au moins 2 caractères : nom RP ou licence d'un joueur déjà venu sur le serveur."));
    }
    playersDom.list.replaceChildren(...(offlineResults.length ? offlineResults.map((p) => {
        const row = h("button", { class: `list-row player-row${p.identifier === offlineSelected ? " active" : ""}`, onclick: () => selectOffline(p.identifier) },
            h("span", { class: "who" },
                h("b", null, p.name),
                h("span", null, p.online ? `En ligne (ID ${p.online})` : p.lastSeen ? `Vu ${ago(p.lastSeen)}` : "Jamais revu")
            ),
            p.online ? h("span", { class: "status on" }) : null
        );
        return row;
    }) : [h("div", { class: "muted side-empty" }, "Aucun joueur trouvé.")]));
}

async function selectOffline(identifier) {
    offlineSelected = identifier;
    offlineInfo = null;
    offlineForms = null;
    premiumPanel = null;
    playerHistory = null;
    playerLogs = null;
    paintPlayerList();
    paintOfflineFiche();
    await loadOfflineInfo();
}

async function loadOfflineInfo() {
    const identifier = offlineSelected;
    if (!identifier) return;
    const res = await nui("action", { action: "offline.info", payload: { identifier } });
    if (identifier !== offlineSelected) return;
    offlineInfo = res && res.ok ? res.info : false;
    if (offlineInfo) {
        offlineInfo.licenses = Array.isArray(offlineInfo.licenses) ? offlineInfo.licenses : [];
        if (can("sanctions.view")) loadPlayerHistory(offlineInfo.license);
    }
    paintOfflineFiche();
}

// Action hors ligne : rechargement de la fiche après succès
async function offlineAction(action, okMessage, payload) {
    const res = await act(action, { identifier: offlineSelected, ...(payload || {}) }, okMessage);
    if (res) {
        offlineForms = null;
        await loadOfflineInfo();
    }
    return res;
}

function paintOfflineFiche() {
    const fiche = playersDom.fiche;

    if (!offlineSelected) {
        return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-search"), "Recherchez un joueur, connecté ou non, pour voir sa fiche en base."));
    }
    if (offlineInfo === false) {
        return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-door"), "Joueur introuvable en base."));
    }
    if (!offlineInfo) {
        return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-player"), "Chargement de la fiche…"));
    }

    const info = offlineInfo;
    const locked = info.online || info.protected;
    const reason = (perm) => {
        if (!can(perm)) return "Permission manquante";
        if (info.online) return "Joueur connecté : utilisez l'onglet En ligne";
        if (info.protected) return "Rang égal ou supérieur au vôtre";
        return null;
    };
    const button = (label, iconName, perm, danger, onclick) => {
        const blocked = reason(perm);
        return h("button", { class: `btn action${danger ? " danger" : ""}`, disabled: !!blocked, title: blocked, onclick }, icon(iconName), label);
    };
    const actions = [
        !info.hasIdentity ? h("div", { class: "banner" }, icon("i-undo"), "Ce joueur n'a pas d'identité : il passera par la création de personnage à sa prochaine connexion.") : null,
        h("div", { class: "card" }, h("div", { class: "action-groups" },
            h("div", { class: "action-group" }, h("span", { class: "group-title" }, "Sanction"),
                button("Bannir", "i-ban", "sanctions.ban", true, () => openBan({ identifier: info.identifier, name: info.name }))),
            h("div", { class: "action-group" }, h("span", { class: "group-title" }, "Personnage"),
                button("Recréer à la connexion", "i-undo", "players.recreate", true, () => openOfflineRecreate(info)),
                button("Wipe", "i-trash", "players.wipe", true, () => openOfflineWipe(info)))
        )),
    ];

    playerColumns(fiche, info, {
        head: h("div", { class: "crew-id player-id" },
            h("div", { class: "crew-pic" }, mugshotImg(info.identifier, "mug-head")),
            h("div", { class: "crew-id-text" },
                h("b", null, info.name),
                h("span", { class: `badge ${info.online ? "ok" : "muted"}` }, info.online ? `En ligne · ID ${info.online}` : "Hors ligne"),
                h("span", { class: "mono muted" }, shortLicense(info.license)),
                info.rank ? rankPill(info.rank) : null)),
        actions: [info.online ? h("div", { class: "banner info" }, icon("i-player"), "Ce joueur est connecté : ses données se modifient depuis sa fiche en ligne.") : null, ...actions],
        money: [moneyCards(info), locked ? null : offlineFormsNode(info)],
        extra: [offlineLicensesCard(info, locked), info.online ? null : premiumCard(info, { identifier: info.identifier }, () => loadOfflineInfo())],
        sanctions: { ban: reason("sanctions.ban") ? null : () => openBan({ identifier: info.identifier, name: info.name }), warn: null },
    });
}

function offlineLicensesCard(info, locked) {
    const editable = can("players.licenses") && !locked;
    return h("div", { class: "card", style: "margin-top:16px" },
        h("h3", { class: "card-title" }, `Permis (${info.licenses.filter((l) => l.owned).length}/${info.licenses.length})`),
        h("div", { class: "perm-grid" }, info.licenses.map((license) => {
            const row = h("div", { class: `perm${license.owned ? " on" : ""}${editable ? "" : " locked"}` },
                h("span", { class: "switch" }),
                h("span", { class: "txt" }, h("span", null, license.label), h("code", null, license.type)));
            if (editable) row.addEventListener("click", () => offlineAction("offline.license", `${license.label} ${license.owned ? "retiré" : "donné"}.`, { type: license.type, owned: !license.owned }));
            return row;
        }))
    );
}

// Formulaires argent et métier, gardés tant que la même fiche est affichée (saisie conservée)
function offlineFormsNode(info) {
    if (offlineForms && offlineForms.identifier === info.identifier) return offlineForms.node;

    const cards = [];
    const accounts = ACCOUNT_OPTIONS.filter((a) => can(a.permission));

    if (accounts.length) {
        let account = accounts[0].value;
        let operation = "add";
        const accountSeg = h("div", { class: "segmented" });
        const operationSeg = h("div", { class: "segmented" });
        const amount = h("input", { class: "input mono", type: "number", min: "0", placeholder: "Montant" });
        const reasonInput = h("input", { class: "input", maxlength: "200", placeholder: "Raison (obligatoire)" });
        const paint = () => {
            accountSeg.replaceChildren(...segmentedButtons(accounts.map((a) => ({ value: a.value, label: a.label })), account, (v) => { account = v; paint(); }));
            operationSeg.replaceChildren(...segmentedButtons(OPERATIONS, operation, (v) => { operation = v; paint(); }));
        };
        paint();
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Valider");
        submit.addEventListener("click", async () => {
            const value = Number(amount.value);
            if (!Number.isInteger(value) || value < (operation === "set" ? 0 : 1)) return toast("Montant invalide.", "error");
            if (reasonInput.value.trim().length < 3) return toast("La raison doit faire au moins 3 caractères.", "error");
            const res = await offlineAction("offline.money", null, { account, operation, amount: value, reason: reasonInput.value.trim() });
            if (res) toast(`Nouveau solde : ${money(res.after)} (avant : ${money(res.before)}).`, "ok");
        });
        cards.push(h("div", { class: "card" },
            h("h3", { class: "card-title" }, "Argent (hors ligne)"),
            h("div", { class: "eco-line" }, accountSeg),
            h("div", { class: "eco-line" }, operationSeg),
            h("div", { class: "eco-form" }, amount, reasonInput, submit)
        ));
    }

    if (can("economy.job")) {
        const jobSelect = h("select", { class: "input" }, h("option", { value: "" }, "Chargement des métiers…"));
        const gradeSelect = h("select", { class: "input" });
        const paintGrades = (selectedLevel) => {
            const job = (jobsCache || []).find((j) => j.name === jobSelect.value);
            gradeSelect.replaceChildren(...(job ? job.grades : []).map((g) =>
                h("option", { value: String(g.grade), selected: g.grade === selectedLevel }, `${g.grade} - ${g.label}`)));
        };
        jobSelect.addEventListener("change", () => paintGrades(0));
        loadJobs().then(() => {
            jobSelect.replaceChildren(...(jobsCache || []).map((j) => h("option", { value: j.name, selected: info.job && info.job.name === j.name }, j.label)));
            paintGrades(info.job ? info.job.level : 0);
        });
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Appliquer");
        submit.addEventListener("click", () => offlineAction("offline.setJob", "Métier modifié.", { job: jobSelect.value, grade: Number(gradeSelect.value) }));
        cards.push(h("div", { class: "card" }, h("h3", { class: "card-title" }, "Métier (hors ligne)"), h("div", { class: "eco-form job" }, jobSelect, gradeSelect, submit)));
    }

    offlineForms = { identifier: info.identifier, node: cards.length ? h("div", { class: "eco-grid" }, cards) : null };
    return offlineForms.node;
}

function openOfflineRecreate(info) {
    let reason = "";
    const confirmBtn = h("button", { class: "btn danger", disabled: true }, icon("i-undo"), "Effacer l'identité");
    const field = reasonField("Raison (3 caractères minimum)", (value) => { reason = value; confirmBtn.disabled = reason.length < 3; });
    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await offlineAction("offline.recreate", `${info.name} recréera son personnage à sa prochaine connexion.`, { reason });
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, `Recréer ${info.name} à sa prochaine connexion ?`),
                h("p", null, "Son identité et son apparence sont effacées. À sa prochaine connexion, il repasse par l'écran d'identité puis la création d'apparence. Argent, inventaire et métier sont conservés.")),
            h("div", { class: "body" }, field),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    field.focus();
}

function openOfflineWipe(info) {
    const confirmInput = h("input", { class: "input", placeholder: info.name });
    const reasonInput = h("textarea", { class: "input textarea", maxlength: "200", placeholder: "Raison (3 caractères minimum)" });
    const confirmBtn = h("button", { class: "btn danger", disabled: true }, icon("i-trash"), "Wipe définitif");
    const update = () => {
        confirmBtn.disabled = confirmInput.value.trim().toLowerCase() !== info.name.toLowerCase() || reasonInput.value.trim().length < 3;
    };
    confirmInput.addEventListener("input", update);
    reasonInput.addEventListener("input", update);
    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await offlineAction("offline.wipe", `${info.name} a été wipe.`, { confirm: confirmInput.value.trim(), reason: reasonInput.value.trim() });
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, `Wipe de ${info.name} (hors ligne)`),
                h("p", null, "Argent (montant de départ), inventaire, métier, véhicules, permis, identité et apparence sont réinitialisés en base. Il recrée son personnage à sa prochaine connexion. L'état avant wipe est gardé dans les logs.")),
            h("div", { class: "body" },
                h("div", { class: "field" }, h("label", null, `Tapez « ${info.name} » pour confirmer`), confirmInput),
                h("div", { class: "field" }, h("label", null, "Raison"), reasonInput)
            ),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    confirmInput.focus();
}
