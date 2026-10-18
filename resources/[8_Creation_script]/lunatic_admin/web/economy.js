"use strict";

// ====================================================================
//  lunatic_admin — lot 5 : économie, métier et inventaire (section de la fiche joueur)
//  La section est construite une fois par joueur et réinsérée à chaque rafraîchissement
//  de la fiche : les champs en cours de saisie ne sont pas effacés.
// ====================================================================

const ACCOUNT_OPTIONS = [
    { value: "money", label: "Liquide", permission: "economy.money", field: "money" },
    { value: "bank", label: "Banque", permission: "economy.money", field: "bank" },
    { value: "black_money", label: "Argent sale", permission: "economy.black_money", field: "blackMoney" },
];
const OPERATIONS = [
    { value: "add", label: "Donner" },
    { value: "remove", label: "Retirer" },
    { value: "set", label: "Fixer" },
];

let economyPanel = null; // { serverId, node, refreshBalances, loadInventory }
let jobsCache = null;
let itemsCache = null;

function hasEconomy() {
    return ["economy.money", "economy.black_money", "economy.job", "economy.items", "economy.clear"].some(can);
}

// Appelée par paintFiche (app.js) : renvoie la section économie du joueur affiché
function economySection(info) {
    if (!hasEconomy() || info.protected) return null;

    if (!economyPanel || economyPanel.serverId !== info.serverId) {
        economyPanel = buildEconomy(info);
    }

    economyPanel.refreshBalances(info);
    return economyPanel.node;
}

function buildEconomy(info) {
    const panel = { serverId: info.serverId, refreshBalances: () => {}, loadInventory: () => {} };
    const cards = [];

    // ---------- Argent ----------
    const accounts = ACCOUNT_OPTIONS.filter((a) => can(a.permission));
    if (accounts.length) {
        let account = accounts[0].value;
        let operation = "add";
        const balance = h("b", { class: "mono" });
        const accountSeg = h("div", { class: "segmented" });
        const operationSeg = h("div", { class: "segmented" });
        const amount = h("input", { class: "input mono", type: "number", min: "0", placeholder: "Montant" });
        const reason = h("input", { class: "input", maxlength: "200", placeholder: "Raison (obligatoire)" });
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Valider");
        let lastInfo = info;

        const paint = () => {
            accountSeg.replaceChildren(...segmentedButtons(accounts.map((a) => ({ value: a.value, label: a.label })), account, (v) => { account = v; paint(); }));
            operationSeg.replaceChildren(...segmentedButtons(OPERATIONS, operation, (v) => { operation = v; paint(); }));
            const field = ACCOUNT_OPTIONS.find((a) => a.value === account).field;
            balance.textContent = money(lastInfo[field]);
        };
        panel.refreshBalances = (next) => { lastInfo = next; paint(); };

        submit.addEventListener("click", async () => {
            const value = Number(amount.value);
            if (!Number.isInteger(value) || value < (operation === "set" ? 0 : 1)) return toast("Montant invalide.", "error");
            if (reason.value.trim().length < 3) return toast("La raison doit faire au moins 3 caractères.", "error");
            submit.disabled = true;
            const res = await act("economy.money", { serverId: panel.serverId, account, operation, amount: value, reason: reason.value.trim() }, null);
            submit.disabled = false;
            if (!res) return;
            toast(`Nouveau solde : ${money(res.after)} (avant : ${money(res.before)}).`, "ok");
            amount.value = "";
            reason.value = "";
            loadPlayerInfo();
        });

        paint();
        cards.push(h("div", { class: "card" },
            h("h3", { class: "card-title" }, "Argent"),
            h("div", { class: "eco-line" }, accountSeg, h("span", { class: "muted" }, "Solde : "), balance),
            h("div", { class: "eco-line" }, operationSeg),
            h("div", { class: "eco-form" }, amount, reason, submit)
        ));
    }

    // ---------- Métier ----------
    if (can("economy.job")) {
        const jobSelect = h("select", { class: "input" }, h("option", { value: "" }, "Chargement des métiers…"));
        const gradeSelect = h("select", { class: "input" });
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Appliquer");

        const paintGrades = (selectedLevel) => {
            const job = (jobsCache || []).find((j) => j.name === jobSelect.value);
            gradeSelect.replaceChildren(...(job ? job.grades : []).map((g) =>
                h("option", { value: String(g.grade), selected: g.grade === selectedLevel }, `${g.grade} - ${g.label}`)));
        };
        jobSelect.addEventListener("change", () => paintGrades(0));

        loadJobs().then(() => {
            jobSelect.replaceChildren(...(jobsCache || []).map((j) =>
                h("option", { value: j.name, selected: info.job && info.job.name === j.name }, j.label)));
            paintGrades(info.job ? info.job.level : 0);
        });

        submit.addEventListener("click", async () => {
            if (!jobSelect.value) return;
            const res = await act("economy.setJob", { serverId: panel.serverId, job: jobSelect.value, grade: Number(gradeSelect.value) }, "Métier modifié.");
            if (res) loadPlayerInfo();
        });

        cards.push(h("div", { class: "card" },
            h("h3", { class: "card-title" }, "Métier"),
            h("div", { class: "eco-form job" }, jobSelect, gradeSelect, submit)
        ));
    }

    // ---------- Inventaire ----------
    if (can("economy.items") || can("economy.clear")) {
        const list = h("div", { class: "inv-list" }, h("span", { class: "muted" }, "Chargement…"));
        const weight = h("span", { class: "muted mono" });
        const actions = h("div", { class: "btn-row" });

        panel.loadInventory = async () => {
            if (!can("economy.items")) {
                list.replaceChildren(h("span", { class: "muted" }, "Vous ne pouvez pas voir l'inventaire."));
                return;
            }
            const res = await nui("action", { action: "economy.inventory", payload: { serverId: panel.serverId } });
            if (!res || !res.ok) {
                list.replaceChildren(h("span", { class: "muted" }, (res && res.error) || "Inventaire indisponible."));
                return;
            }
            const items = Array.isArray(res.items) ? res.items : [];
            weight.textContent = typeof res.weight === "number" ? `${(res.weight / 1000).toFixed(1)} / ${((res.maxWeight || 0) / 1000).toFixed(1)} kg` : "";
            list.replaceChildren(...(items.length ? items.map((item) => h("div", { class: "inv-row" },
                h("b", null, item.label),
                h("span", { class: "muted mono" }, item.name),
                h("span", { class: "mono" }, `x${item.count}`),
                h("button", { class: "btn small ghost", title: "Retirer", onclick: () => openRemoveItem(panel, item) }, icon("i-trash"))
            )) : [h("span", { class: "muted" }, "Inventaire vide.")]));
        };

        if (can("economy.items") && !info.isSelf) {
            // Le vrai inventaire ox_inventory s'ouvre à l'écran : le panel se ferme pour le laisser apparaître
            actions.append(h("button", { class: "btn small", onclick: async () => {
                const res = await act("economy.inspect", { serverId: panel.serverId }, null);
                if (res) closePanel();
            } }, icon("i-eye"), "Ouvrir son inventaire"));
        }
        if (can("economy.items")) actions.append(h("button", { class: "btn small primary", onclick: () => openGiveItem(panel, info) }, icon("i-plus"), "Donner un objet"));
        if (can("economy.clear")) actions.append(h("button", { class: "btn small danger", onclick: () => openClearInventory(panel, info) }, icon("i-trash"), "Vider l'inventaire"));
        actions.append(h("button", { class: "btn small ghost", onclick: () => panel.loadInventory() }, icon("i-undo"), "Actualiser"));

        cards.push(h("div", { class: "card eco-inventory" },
            h("div", { class: "card-head" }, h("h3", { class: "card-title" }, "Inventaire"), weight),
            actions,
            list
        ));
        panel.loadInventory();
    }

    panel.node = h("div", { class: "eco-grid" }, cards);
    return panel;
}

async function loadJobs() {
    if (jobsCache) return;
    const res = await nui("action", { action: "economy.jobs", payload: {} });
    jobsCache = res && res.ok && Array.isArray(res.jobs) ? res.jobs.map((j) => ({ ...j, grades: Array.isArray(j.grades) ? j.grades : [] })) : [];
}

async function loadItems() {
    if (itemsCache) return;
    const res = await nui("action", { action: "economy.itemList", payload: {} });
    itemsCache = res && res.ok && Array.isArray(res.items) ? res.items : [];
}

function openGiveItem(panel, info) {
    let chosen = null;
    let filter = "";
    const listBox = h("div", { class: "pick-list" }, h("span", { class: "muted" }, "Chargement des objets…"));
    const search = h("input", { placeholder: "Nom de l'objet (ex. bread)" });
    const count = h("input", { class: "input mono", type: "number", min: "1", value: "1" });
    const confirmBtn = h("button", { class: "btn primary", disabled: true }, icon("i-plus"), "Donner");

    const paint = () => {
        const text = filter.toLowerCase();
        const matches = (itemsCache || []).filter((it) => !text || it.name.toLowerCase().includes(text) || String(it.label).toLowerCase().includes(text)).slice(0, 40);
        listBox.replaceChildren(...(matches.length ? matches.map((it) => {
            const row = h("button", { class: `pick${chosen === it.name ? " on" : ""}` }, h("span", { class: "id" }, it.name), it.label);
            row.addEventListener("click", () => { chosen = it.name; confirmBtn.disabled = false; paint(); });
            return row;
        }) : [h("span", { class: "muted" }, "Aucun objet ne correspond.")]));
    };
    search.addEventListener("input", () => { filter = search.value.trim(); paint(); });
    loadItems().then(paint);

    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await act("economy.giveItem", { serverId: panel.serverId, item: chosen, count: Number(count.value) }, `Objet donné à ${info.name}.`);
            if (res) { close(); panel.loadInventory(); }
        });
        return [
            h("header", null, h("h3", null, `Donner un objet à ${info.name}`), h("p", null, "Choisissez l'objet puis la quantité.")),
            h("div", { class: "body" },
                h("label", { class: "search" }, icon("i-search"), search),
                listBox,
                h("div", { class: "field" }, h("label", null, "Quantité"), count)
            ),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    search.focus();
}

function openRemoveItem(panel, item) {
    const count = h("input", { class: "input mono", type: "number", min: "1", max: String(item.count), value: "1" });

    openModal((close) => {
        const remove = async (value) => {
            const res = await act("economy.removeItem", { serverId: panel.serverId, item: item.name, count: value }, `${item.label} retiré.`);
            if (res) { close(); panel.loadInventory(); }
        };
        return [
            h("header", null, h("h3", null, `Retirer ${item.label}`), h("p", null, `Le joueur en possède ${item.count}.`)),
            h("div", { class: "body" }, h("div", { class: "field" }, h("label", null, "Quantité"), count)),
            h("footer", null,
                h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"),
                h("button", { class: "btn", onclick: () => remove("all") }, "Tout retirer"),
                h("button", { class: "btn danger", onclick: () => remove(Number(count.value)) }, icon("i-trash"), "Retirer")
            ),
        ];
    });
    count.focus();
}

function openClearInventory(panel, info) {
    let reason = "";
    const confirmBtn = h("button", { class: "btn danger", disabled: true }, icon("i-trash"), "Vider");
    const field = reasonField("Raison (3 caractères minimum)", (value) => { reason = value; confirmBtn.disabled = reason.length < 3; });

    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await act("economy.clearInventory", { serverId: panel.serverId, reason }, null);
            if (!res) return;
            toast(`Inventaire de ${info.name} vidé (${res.removed || 0} emplacement(s)).`, "ok");
            close();
            panel.loadInventory();
        });
        return [
            h("header", null, h("h3", null, `Vider l'inventaire de ${info.name} ?`),
                h("p", null, "Tous les objets sont supprimés. La liste de ce qui a été retiré est gardée dans les logs.")),
            h("div", { class: "body" }, field),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    field.focus();
}
