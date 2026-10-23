"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, page Tablette (points de livraison à gauche, articles au centre, fiche à droite)
//  Marché noir de la tablette des crews : catalogue, points de livraison, dernières commandes.
// ====================================================================

const marketState = { data: null };

const MARKET_STATUS = { pending: "En attente", collected: "Récupérée", expired: "Perdue" };

async function loadMarket() {
    const res = await nui("action", { action: "market.info", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    marketState.data = res;
    if (illegalState.tab === "tablet") paintIllegal();
}

async function marketAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) await loadMarket();
    return res;
}

function marketProblems(d) {
    const problems = [];
    if (!d.items.length) problems.push("catalogue vide");
    if (!d.dropoffs.length) problems.push("aucun point de livraison (le marché est fermé)");
    const unknown = d.items.filter((i) => i.missing).length;
    if (unknown) problems.push(`${unknown} objet${unknown > 1 ? "s" : ""} inconnu${unknown > 1 ? "s" : ""}`);
    return problems;
}

function marketPage() {
    const d = marketState.data;
    if (!d) {
        loadMarket();
        return illegalLoading("Tablette", "i-box", "Chargement du marché noir…");
    }
    const problems = marketProblems(d);
    const minutes = (s) => Math.round(s / 60);
    const sel = illegalState.marketSel;

    const tiles = d.items.map((i) => illegalTile({
        item: i.item, label: i.label, badge: `Lv ${i.minLevel}`, active: i.id === sel, warn: i.missing, off: i.stock <= 0,
        onclick: () => i.id !== sel && illegalSwitch(() => { illegalState.marketSel = i.id; }),
    }));

    const dropoffs = d.dropoffs.map((p, index) => pointLine(index + 1, p.label, p, [
        iconButton("i-crosshair", "Replacer à votre position", () => marketAct("market.moveDropoff", { id: p.id }, "Point replacé à votre position.")),
        iconButton("i-goto", "TP", () => act("market.tpDropoff", { id: p.id }, null)),
        iconButton("i-trash", "Supprimer", () => marketAct("market.deleteDropoff", { id: p.id }, "Point supprimé.")),
    ]));

    const orders = d.orders.map((o) => h("div", { class: "row point-row" },
        h("span", { class: "pid mono" }, `#${o.id}`),
        h("div", { class: "who" }, h("b", null, `${o.count} × ${o.label} · ${money(o.total)}`),
            h("span", null, `${o.crew} · commandé par ${o.buyer}${o.collectedBy ? ` · récupéré par ${o.collectedBy}` : ""} · ${new Date(o.createdAt * 1000).toLocaleString("fr-FR")}`)),
        h("span", { class: `badge ${o.status === "collected" ? "ok" : o.status === "expired" ? "ban" : "warn"}` }, MARKET_STATUS[o.status] || o.status)));

    return {
        title: "Tablette",
        sub: `Marché noir des crews : paiement en argent sale, livraison entre ${minutes(d.delay[0])} et ${minutes(d.delay[1])} min à un point tiré au hasard, perdue après ${minutes(d.expire)} min. Stock remis au maximum chaque jour.`,
        actions: [
            readyBadge(problems),
            h("button", { class: "btn small", title: "Ajoute les pièces d'armes et les ingrédients des drogues de départ", onclick: async () => {
                const res = await marketAct("market.seed", {}, null);
                if (res) toast(`${res.created} article(s) ajouté(s) au marché.`, "ok");
            } }, icon("i-sparkle"), "Catalogue de départ"),
        ],
        side: [sideBlock(`Points de livraison (${d.dropoffs.length})`, iconButton("i-plus", "Ajouter un point à votre position", () => openMarketDropoff()),
            dropoffs.length ? dropoffs : h("p", { class: "hint-line" }, "Aucun point : les commandes sont impossibles."),
            h("p", { class: "hint-line" }, "Sans blip : seul le crew qui attend une commande voit son point."))],
        center: h("div", null,
            readyHint(problems),
            h("div", { class: "items-grid" }, newTile("Ajouter un article", () => illegalSwitch(() => { illegalState.marketSel = "new"; }), sel === "new"), tiles),
            h("div", { class: "section-head", style: "margin-top:22px" }, "Dernières commandes"),
            orders.length ? h("div", { class: "table" }, orders) : h("p", { class: "hint-line", style: "margin:0" }, "Aucune commande pour l'instant.")),
        editor: marketEditor(d.items.find((i) => i.id === sel)),
    };
}

function marketEditor(entry) {
    if (!entry && illegalState.marketSel !== "new") return emptySelection("i-box", "Choisissez un article ou ajoutez-en un.");
    const max = marketState.data.maxLevel;
    const d = illegalDraft("market", entry ? entry.id : "new", entry ? `Article ${entry.label}` : "Nouvel article",
        () => (entry ? { item: entry.item, price: entry.price, minLevel: entry.minLevel, stockMax: entry.stockMax } : { item: "", price: 100, minLevel: 1, stockMax: 20 }),
        saveMarketItem);

    return selectionPanel({
        item: d.item, title: entry ? entry.label : "Nouvel article", sub: d.item || "objet à choisir",
        badges: entry ? h("span", { class: `badge ${entry.stock > 0 ? "muted" : "warn"}`, style: "justify-self:start" }, `stock du jour ${entry.stock}/${entry.stockMax}`) : null,
        body: [
            h("div", { class: "section-head" }, "Informations"),
            fieldRow("Objet", draftItem(d, "item", () => paintIllegal())),
            fieldRow("Prix à l'unité ($)", draftNumber(d, "price", 0, 1000000)),
            fieldRow(`Level min (1 à ${max})`, draftNumber(d, "minLevel", 1, max)),
            fieldRow("Stock du jour", draftNumber(d, "stockMax", 1, 10000)),
            h("p", { class: "hint-line" }, "Prix payé en argent sale. Le stock revient au maximum chaque jour."),
        ],
        actions: [
            entry ? deleteButton(async () => {
                const yes = await confirmBox(`Retirer « ${entry.label} » du marché ?`, "Il ne sera plus proposé sur la tablette.", "Retirer", true);
                if (!yes) return;
                const res = await act("market.deleteItem", { id: entry.id }, "Article retiré.");
                if (!res) return;
                illegalSaved();
                illegalState.marketSel = null;
                await loadMarket();
            }) : null,
            entry ? duplicateButton(() => illegalSwitch(() => { illegalState.marketSel = "new"; illegalState.prefill = { ...d }; })) : null,
            saveButton(saveMarketItem, !entry),
        ],
    });
}

async function saveMarketItem() {
    const draft = illegalState.draft;
    if (!draft || draft.kind !== "market") return;
    const d = draft.data;
    if (!knownItem(d.item)) return toast(`L'objet « ${d.item} » n'existe pas dans ox_inventory.`, "error");
    const creating = draft.key === "new";
    const res = await act("market.saveItem", { id: creating ? null : draft.key, ...d }, creating ? "Article ajouté." : "Article enregistré.");
    if (!res) return;
    illegalSaved();
    await loadMarket();
    if (creating) {
        const added = latestOf(marketState.data.items.filter((i) => i.item === d.item));
        illegalState.marketSel = added ? added.id : null;
    }
    paintIllegal();
}

function openMarketDropoff() {
    const label = h("input", { class: "input", maxlength: "60", placeholder: "Ex. Hangar abandonné, Docks" });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-plus"), "Ajouter à ma position");
        submit.addEventListener("click", async () => {
            const res = await marketAct("market.addDropoff", { label: label.value.trim() }, "Point de livraison ajouté à votre position.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, "Point de livraison"), h("p", null, "Le colis apparaîtra là où vous vous tenez. Le nom s'affiche sur la tablette du crew.")),
            h("div", { class: "body" }, label),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    label.focus();
}
