"use strict";

// ====================================================================
//  lunatic_admin — tuile Illégal, onglet Tablette (étape 6)
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

function marketPanel() {
    const d = marketState.data;
    if (!d) {
        loadMarket();
        return h("div", { class: "empty" }, icon("i-store"), "Chargement du marché noir…");
    }
    const problems = marketProblems(d);
    const minutes = (s) => Math.round(s / 60);

    const items = d.items.map((i) => h("div", { class: "row catalog-row" },
        itemImage(i.item),
        h("div", { class: "who" },
            h("b", null, i.label, i.missing ? h("span", { class: "badge ban", style: "margin-left:6px" }, "objet inconnu") : null,
                h("span", { class: "badge muted ready-badge" }, `level ${i.minLevel}+`)),
            h("span", null, `${i.item} · ${money(i.price)} l'unité · stock du jour ${i.stock}/${i.stockMax}`)),
        h("div", { class: "btn-row" },
            h("button", { class: "btn small ghost", onclick: () => openMarketItem(i) }, icon("i-edit"), "Modifier"),
            h("button", { class: "btn small ghost", title: "Retirer", onclick: async () => {
                const yes = await confirmBox(`Retirer « ${i.label} » du marché ?`, "Il ne sera plus proposé sur la tablette.", "Retirer", true);
                if (yes) marketAct("market.deleteItem", { id: i.id }, "Article retiré.");
            } }, icon("i-trash")))));

    const dropoffs = d.dropoffs.map((p, index) => h("div", { class: "row point-row" },
        h("span", { class: "pid mono" }, String(index + 1)),
        h("div", { class: "who" }, h("b", null, p.label), h("span", null, `${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}`)),
        h("div", { class: "btn-row" },
            h("button", { class: "btn small", onclick: () => marketAct("market.moveDropoff", { id: p.id }, "Point replacé à votre position.") }, icon("i-crosshair"), "Définir"),
            h("button", { class: "btn small ghost", onclick: () => act("market.tpDropoff", { id: p.id }, null) }, icon("i-goto"), "TP"),
            h("button", { class: "btn small ghost", title: "Supprimer", onclick: () => marketAct("market.deleteDropoff", { id: p.id }, "Point supprimé.") }, icon("i-trash")))));

    const orders = d.orders.map((o) => h("div", { class: "row point-row" },
        h("span", { class: "pid mono" }, `#${o.id}`),
        h("div", { class: "who" }, h("b", null, `${o.count} × ${o.label} · ${money(o.total)}`),
            h("span", null, `${o.crew} · commandé par ${o.buyer}${o.collectedBy ? ` · récupéré par ${o.collectedBy}` : ""} · ${new Date(o.createdAt * 1000).toLocaleString("fr-FR")}`)),
        h("span", { class: `badge ${o.status === "collected" ? "ok" : o.status === "expired" ? "ban" : "warn"}` }, MARKET_STATUS[o.status] || o.status)));

    return h("div", null,
        h("div", { class: "card" },
            h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, "Marché noir de la tablette", readyBadge(problems)),
                h("div", { class: "btn-row" },
                    h("button", { class: "btn small", title: "Ajoute les pièces d'armes et les ingrédients des drogues de départ", onclick: async () => {
                        const res = await marketAct("market.seed", {}, null);
                        if (res) toast(`${res.created} article(s) ajouté(s) au marché.`, "ok");
                    } }, icon("i-sparkle"), "Catalogue de départ"),
                    h("button", { class: "btn small primary", onclick: () => openMarketItem(null) }, icon("i-plus"), "Ajouter un article"))),
            readyHint(problems),
            h("p", { class: "hint-line", style: "margin:0" }, `Les membres de crew ouvrent la tablette depuis leur inventaire (objet « Tablette »). Paiement immédiat en argent sale ; la commande arrive entre ${minutes(d.delay[0])} et ${minutes(d.delay[1])} min plus tard à un point de livraison tiré au hasard, puis est perdue si personne ne la récupère dans les ${minutes(d.expire)} min. Le stock de chaque article revient au maximum chaque jour.`),
            items.length ? h("div", { class: "table", style: "margin-top:12px" }, items) : null),
        h("div", { class: "card", style: "margin-top:16px" },
            h("div", { class: "card-head dev-head" }, h("h3", { class: "card-title" }, `Points de livraison (${d.dropoffs.length})`),
                h("button", { class: "btn small", onclick: () => openMarketDropoff() }, icon("i-plus"), "Ajouter à ma position")),
            dropoffs.length ? h("div", { class: "table" }, dropoffs) : h("p", { class: "hint-line", style: "margin:0" }, "Aucun point : les commandes sont impossibles."),
            h("p", { class: "hint-line" }, "Sans blip : seul le crew qui attend une commande voit son point (sur la tablette et au sol quand elle est prête).")),
        h("div", { class: "card", style: "margin-top:16px" },
            h("h3", { class: "card-title" }, "Dernières commandes"),
            orders.length ? h("div", { class: "table" }, orders) : h("p", { class: "hint-line", style: "margin:0" }, "Aucune commande pour l'instant."))
    );
}

async function openMarketItem(entry) {
    const items = await loadCatalogItems();
    const known = new Set(items.map((i) => i.name));
    const d = marketState.data;
    const item = itemPicker(items, entry ? entry.item : "");
    const num = (value, min, max) => h("input", { class: "input mono", type: "number", min: String(min), max: String(max), value: String(value) });
    const price = num(entry ? entry.price : 100, 0, 1000000);
    const minLevel = num(entry ? entry.minLevel : 1, 1, d.maxLevel);
    const stockMax = num(entry ? entry.stockMax : 20, 1, 10000);

    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), entry ? "Enregistrer" : "Ajouter");
        submit.addEventListener("click", async () => {
            const name = item.value.trim();
            if (!known.has(name)) return toast(`L'objet « ${name} » n'existe pas dans ox_inventory.`, "error");
            const res = await marketAct("market.saveItem", { id: entry ? entry.id : null, item: name, price: Number(price.value), minLevel: Number(minLevel.value), stockMax: Number(stockMax.value) },
                entry ? "Article enregistré." : "Article ajouté.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, entry ? `Modifier ${entry.label}` : "Ajouter un article"), h("p", null, "Prix payé en argent sale, à l'unité.")),
            h("div", { class: "body event-form" },
                h("div", { class: "field" }, h("label", null, "Objet"), item),
                h("div", { class: "event-form-row" },
                    h("div", { class: "field" }, h("label", null, "Prix à l'unité ($)"), price),
                    h("div", { class: "field" }, h("label", null, "Level de crew minimum"), minLevel)),
                h("div", { class: "field" }, h("label", null, "Stock du jour (remis au maximum chaque jour)"), stockMax)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    item.focus();
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
