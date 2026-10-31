"use strict";

// Magasins d'articles (LTD, Ammunation…) : catalogue, recherche, panier par quantités, paiement en liquide ou par carte.
// Mode « catalog » : catalogue de vente d'une entreprise (doc Vision « Catalogues ») : la carte, des onglets s'il y en a
// plusieurs, un choix avec le total, puis « Commander » (liquide ou carte) : les employés sont prévenus, l'un d'eux prend
// la commande et sert le client, qui paie à ce moment-là. Le suivi de la commande remplace le panier.
// La page n'affiche que ce que le serveur envoie ; il revérifie prix, permis, place et solde à l'achat.
// $, h et nui viennent de app.js.

let shopData = null;
let basket = {};      // article (clé) -> quantité
let buying = false;
let shopTab = "all";  // catalogue affiché (mode catalog)

const shopMoney = (n) => `${Math.round(n).toLocaleString("fr-FR")} ${shopData.currency || "$"}`;
const shopImage = (name) => `nui://ox_inventory/web/images/${name}.png`;
const shopKey = (i) => i.key || i.item;
const shopItem = (key) => shopData.items.find((i) => shopKey(i) === key);
const isCatalog = () => shopData && shopData.mode === "catalog";

// Catalogues de vente -> liste d'articles (une clé par ligne : le même objet peut figurer dans deux catalogues)
function catalogItems(catalogs) {
    return (catalogs || []).flatMap((c) => c.lines.map((l) => ({
        key: `${c.id}:${l.id}`, catalog: String(c.id), item: l.item, label: l.label, count: l.count || 1,
        price: l.price, weight: (l.weight || 0) * (l.count || 1), description: l.description,
    })));
}
const shopWeight = (grams) => (grams >= 1000 ? `${(grams / 1000).toLocaleString("fr-FR", { maximumFractionDigits: 1 })} kg` : `${grams} g`);

function shopToast(text) {
    const el = $("storeToast");
    el.textContent = text;
    el.classList.add("on");
    clearTimeout(shopToast.timer);
    shopToast.timer = setTimeout(() => el.classList.remove("on"), 3500);
}

function openStore(msg) {
    if (msg.mode === "catalog") msg.items = catalogItems(msg.catalogs);
    shopData = msg;
    basket = {};
    buying = false;
    shopTab = "all";
    const theme = msg.theme || {};
    const banner = $("storeBanner");
    $("store").style.setProperty("--store", theme.color || "");
    banner.style.backgroundImage = msg.header ? `linear-gradient(180deg, #0000 40%, #0008), url("${msg.header}")` : "";
    banner.classList.toggle("with-image", !!msg.header);
    $("storeTitle").textContent = theme.title || msg.label;
    $("storeTitle").style.color = theme.textColor || "";
    $("storeSub").textContent = isCatalog() ? theme.sub || "" : theme.title ? msg.label : theme.sub || "";
    $("storeLogo").classList.toggle("hidden", !msg.logo);
    if (msg.logo) $("storeLogo").src = msg.logo;
    $("storeToolsTitle").textContent = isCatalog() ? "Catalogues" : "Catalogue";
    $("storeSearch").value = "";
    $("store").classList.remove("hidden");
    paintStore();
}

// Onglets : un par catalogue de vente, s'il y en a plusieurs
function paintStoreTabs() {
    const catalogs = isCatalog() ? shopData.catalogs : [];
    $("storeTabs").classList.toggle("hidden", catalogs.length < 2);
    if (catalogs.length < 2) return;
    const tabs = [{ id: "all", label: "Tout" }, ...catalogs.map((c) => ({ id: String(c.id), label: c.label }))];
    $("storeTabs").replaceChildren(...tabs.map((t) => h("button", { class: t.id === shopTab ? "on" : "", onclick: () => { shopTab = t.id; paintStore(); } }, t.label)));
}

function paintStore() {
    paintStoreTabs();
    paintStoreGrid();
    paintStoreCart();
}

function paintStoreGrid() {
    const q = $("storeSearch").value.trim().toLowerCase();
    const list = shopData.items.filter((i) => (!q || i.label.toLowerCase().includes(q)) && (shopTab === "all" || i.catalog === shopTab));
    const scroll = $("storeGrid").scrollTop;
    $("storeGrid").replaceChildren(...(list.length ? list.map((i) => {
        const img = h("img", { src: shopImage(i.item), alt: "" });
        img.addEventListener("error", () => img.replaceWith(h("span", { class: "noimg" }, i.label.charAt(0).toUpperCase())));
        return h("button", {
            class: `store-item${i.locked ? " locked" : ""}`, title: i.locked ? `Permis requis : ${i.license}` : i.description || i.label,
            onclick: () => addToBasket(i, 1),
        }, i.locked ? h("span", { class: "lock" }, "Permis") : i.count > 1 ? h("span", { class: "count" }, `par ${i.count}`) : null,
            basket[shopKey(i)] ? h("span", { class: "qty" }, `×${basket[shopKey(i)]}`) : null,
            img, h("small", null, i.label), h("i", null, i.price > 0 ? shopMoney(i.price) : "Gratuit"));
    }) : [h("p", { class: "store-empty" }, shopData.items.length ? "Aucun article trouvé." : isCatalog() ? "Rien à la carte pour le moment." : "Ce magasin n'a rien à vendre pour le moment.")]));
    $("storeGrid").scrollTop = scroll;
}

function addToBasket(item, delta) {
    if (item.locked) return shopToast(`Permis requis : ${item.license}.`);
    if (isCatalog() && shopData.order) return shopToast("Commande en cours : annulez-la pour en passer une autre.");
    const key = shopKey(item);
    const next = (basket[key] || 0) + delta;
    if (next > (shopData.max || 50)) return shopToast(`${shopData.max || 50} au maximum par article.`);
    if (next <= 0) delete basket[key];
    else basket[key] = next;
    paintStore();
}

function paintStoreCart() {
    const lines = Object.entries(basket).map(([key, count]) => ({ item: shopItem(key), count })).filter((l) => l.item);
    if (isCatalog()) return paintCatalogCart(lines);
    const total = lines.reduce((sum, l) => sum + l.item.price * l.count, 0);
    const weight = lines.reduce((sum, l) => sum + (l.item.weight || 0) * l.count, 0);
    $("storeCart").replaceChildren(...[
        h("div", { class: "store-cart-head" }, h("span", null, lines.length ? `Panier · ${shopWeight(weight)}` : "Panier vide"), h("b", null, shopMoney(total))),
        lines.length ? h("div", { class: "store-lines" }, lines.map((l) => h("div", { class: "store-line" },
            h("span", null, `${l.item.count > 1 ? `${l.item.count * l.count} × ` : ""}${l.item.label}`), h("i", null, shopMoney(l.item.price * l.count)),
            h("div", { class: "store-step" },
                h("button", { title: "Retirer un", onclick: () => addToBasket(l.item, -1) }, "−"), h("b", null, String(l.count)),
                h("button", { title: "Ajouter un", onclick: () => addToBasket(l.item, 1) }, "+"))))) : null,
        h("div", { class: "store-wallet" }, h("span", null, `Liquide : ${shopMoney(shopData.cash || 0)}`), h("span", null, `Banque : ${shopMoney(shopData.bank || 0)}`)),
        h("div", { class: "store-pay" },
            lines.length ? h("button", { class: "store-btn", disabled: buying, onclick: () => buyBasket("money") }, total > 0 ? "Payer en liquide" : "Prendre") : null,
            lines.length && total > 0 ? h("button", { class: "store-btn", disabled: buying, onclick: () => buyBasket("bank") }, "Payer par carte") : null,
            h("button", { class: "store-btn ghost", onclick: closeStoreView }, "Quitter le magasin")),
    ].filter(Boolean));
}

// Boutons du bas en mode catalog : équipement et commandes pour les membres, fermeture pour tous
function catalogFooter() {
    const leave = (action) => () => { $("store").classList.add("hidden"); shopData = null; nui(action); };
    const buttons = [
        shopData.equipment ? h("button", { class: "store-btn ghost", onclick: leave("catalogEquipment") }, "Équipement") : null,
        shopData.member ? h("button", { class: "store-btn ghost", onclick: leave("catalogOrders") }, "Commandes") : null,
        h("button", { class: "store-btn ghost", onclick: closeStoreView }, "Fermer"),
    ].filter(Boolean);
    return h("div", { class: "store-foot" }, buttons);
}

// Mode catalog : le choix du client et son total, puis la commande ; une commande en cours remplace le panier
function paintCatalogCart(lines) {
    if (shopData.order) return paintCatalogOrder();
    const total = lines.reduce((sum, l) => sum + l.item.price * l.count, 0);
    $("storeCart").replaceChildren(...[
        h("div", { class: "store-cart-head" }, h("span", null, lines.length ? "Votre choix" : "Touchez un article pour le choisir"), h("b", null, shopMoney(total))),
        lines.length ? h("div", { class: "store-lines" }, lines.map((l) => h("div", { class: "store-line" },
            h("span", null, `${l.item.count > 1 ? `${l.item.count} × ` : ""}${l.item.label}`), h("i", null, shopMoney(l.item.price * l.count)),
            h("div", { class: "store-step" },
                h("button", { title: "Retirer un", onclick: () => addToBasket(l.item, -1) }, "−"), h("b", null, String(l.count)),
                h("button", { title: "Ajouter un", onclick: () => addToBasket(l.item, 1) }, "+"))))) : null,
        lines.length ? h("div", { class: "store-wallet" }, h("span", null, `Liquide : ${shopMoney(shopData.cash || 0)}`), h("span", null, `Banque : ${shopMoney(shopData.bank || 0)}`)) : null,
        lines.length ? h("div", { class: "store-pay" },
            h("button", { class: "store-btn", disabled: buying, style: total > 0 ? "" : "grid-column: 1 / -1", onclick: () => orderBasket("money") }, total > 0 ? "Commander · liquide" : "Commander"),
            total > 0 ? h("button", { class: "store-btn", disabled: buying, onclick: () => orderBasket("bank") }, "Commander · carte") : null)
            : h("p", { class: "store-note" }, "Choisissez vos articles puis commandez : un employé les prépare et vous sert. Vous payez au service."),
        catalogFooter(),
    ].filter(Boolean));
}

// Suivi de la commande en cours
function paintCatalogOrder() {
    const order = shopData.order;
    $("storeCart").replaceChildren(...[
        h("div", { class: "store-cart-head" }, h("span", null, `Commande n°${order.id} · ${order.account === "bank" ? "carte" : "liquide"}`), h("b", null, shopMoney(order.total))),
        h("div", { class: `store-status${order.status === "taken" ? " taken" : ""}` }, h("i"), h("span", null, order.statusLabel)),
        h("div", { class: "store-lines" }, order.lines.map((l) => h("div", { class: "store-line" },
            h("span", null, `${l.qty * l.count} × ${l.label}`), h("i", null, shopMoney(l.price * l.qty)), h("span")))),
        h("p", { class: "store-note" }, "Restez près du comptoir : l'employé vous servira, vous paierez à ce moment-là."),
        h("div", { class: "store-pay" }, h("button", { class: "store-btn ghost", style: "grid-column: 1 / -1", disabled: buying, onclick: cancelOrder }, "Annuler la commande")),
        catalogFooter(),
    ]);
}

async function orderBasket(account) {
    if (buying) return;
    buying = true;
    paintStoreCart();
    const res = inGame ? await nui("catalogOrder", { cart: basket, account }) : { ok: true, order: demoOrder(account) };
    buying = false;
    if (!res || !res.ok) {
        paintStoreCart();
        return shopToast((res && res.error) || "Commande impossible.");
    }
    basket = {};
    shopData.order = res.order;
    paintStore();
}

async function cancelOrder() {
    if (buying) return;
    buying = true;
    const res = inGame ? await nui("catalogCancel") : { ok: true };
    buying = false;
    if (!res || !res.ok) return shopToast((res && res.error) || "Annulation impossible.");
    shopData.order = null;
    shopToast("Commande annulée.");
    paintStore();
}

// Aperçu : commande fictive à partir du panier
function demoOrder(account) {
    const lines = Object.entries(basket).map(([key, qty]) => ({ item: shopItem(key), qty })).filter((l) => l.item)
        .map((l) => ({ label: l.item.label, count: l.item.count, qty: l.qty, price: l.item.price }));
    return { id: 7, account, lines, total: lines.reduce((s, l) => s + l.price * l.qty, 0), status: "pending", statusLabel: "En attente d'un employé" };
}

async function buyBasket(account) {
    if (buying) return;
    buying = true;
    paintStoreCart();
    const res = inGame ? await nui("storeBuy", { cart: basket, account }) : { ok: false, error: "Aperçu : pas d'achat hors jeu." };
    buying = false;
    if (!res || !res.ok) {
        paintStoreCart();
        return shopToast((res && res.error) || "Achat impossible.");
    }
    basket = {};
    shopData.cash = res.cash;
    shopData.bank = res.bank;
    shopToast(res.refunded ? "Achat réglé (une partie remboursée : inventaire plein)." : "Achat réglé.");
    paintStore();
}

function closeStoreView() {
    $("store").classList.add("hidden");
    shopData = null;
    nui("storeClose");
}

$("storeSearch").addEventListener("input", () => { if (shopData) paintStoreGrid(); });

document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && shopData && !$("store").classList.contains("hidden")) closeStoreView();
});

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "storeOpen") openStore(msg);
    if (msg.action === "catalogOrder" && isCatalog()) {
        shopData.order = msg.order || null;
        paintStore();
    }
    if (msg.action === "storeClose") {
        shopData = null;
        $("store").classList.add("hidden");
    }
});

// ---------- Aperçu navigateur (index.html#store, index.html#catalog) ----------

if (!inGame && location.hash.includes("catalog")) {
    window.postMessage({
        action: "storeOpen", mode: "catalog", label: "Burger Shot", currency: "$", max: 50, header: null, logo: null, equipment: true, member: true, cash: 120, bank: 4200,
        theme: { color: "#d3122a", title: "Burger Shot", sub: "Catalogue" },
        catalogs: [
            { id: 1, label: "Menus", lines: [{ id: 1, item: "burger", label: "Bleeder", price: 18 }, { id: 2, item: "burger", label: "Heart Stopper", price: 25 }, { id: 3, item: "sandwich", label: "Wrap poulet", price: 14 }] },
            { id: 2, label: "Boissons", lines: [{ id: 4, item: "cola", label: "eCola", price: 6 }, { id: 5, item: "water", label: "Eau", price: 4, count: 2 }] },
        ],
    }, "*");
}

if (!inGame && location.hash.includes("store")) {
    window.postMessage({
        action: "storeOpen", label: "LTD de Grove Street", currency: "$", cash: 420, bank: 15800, max: 50, header: null,
        theme: { color: "#d3122a", title: "LTD", sub: "Limited Gasoline" },
        items: [
            { item: "water", label: "Bouteille d'eau", price: 5, weight: 500 },
            { item: "sandwich", label: "Sandwich", price: 8, weight: 300 },
            { item: "cola", label: "eCola", price: 6, weight: 350 },
            { item: "burger", label: "Burger", price: 12, weight: 400 },
            { item: "phone", label: "Téléphone", price: 450, weight: 190 },
            { item: "lockpick", label: "Crochet", price: 120, weight: 160 },
            { item: "WEAPON_KNIFE", label: "Couteau", price: 300, weight: 1000, license: "Port d'arme", locked: true },
        ],
    }, "*");
}
