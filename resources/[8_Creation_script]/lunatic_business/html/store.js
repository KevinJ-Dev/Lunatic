"use strict";

// Magasins d'articles (LTD, Ammunation…) : catalogue, recherche, panier par quantités, paiement en liquide ou par carte.
// La page n'affiche que ce que le serveur envoie ; il revérifie prix, permis, place et solde à l'achat.
// $, h et nui viennent de app.js.

let shopData = null;
let basket = {};      // article -> quantité
let buying = false;

const shopMoney = (n) => `${Math.round(n).toLocaleString("fr-FR")} ${shopData.currency || "$"}`;
const shopImage = (name) => `nui://ox_inventory/web/images/${name}.png`;
const shopItem = (name) => shopData.items.find((i) => i.item === name);
const shopWeight = (grams) => (grams >= 1000 ? `${(grams / 1000).toLocaleString("fr-FR", { maximumFractionDigits: 1 })} kg` : `${grams} g`);

function shopToast(text) {
    const el = $("storeToast");
    el.textContent = text;
    el.classList.add("on");
    clearTimeout(shopToast.timer);
    shopToast.timer = setTimeout(() => el.classList.remove("on"), 3500);
}

function openStore(msg) {
    shopData = msg;
    basket = {};
    buying = false;
    const theme = msg.theme || {};
    const banner = $("storeBanner");
    $("store").style.setProperty("--store", theme.color || "");
    banner.style.backgroundImage = msg.header ? `linear-gradient(180deg, #0000 40%, #0008), url("${msg.header}")` : "";
    banner.classList.toggle("with-image", !!msg.header);
    $("storeTitle").textContent = theme.title || msg.label;
    $("storeTitle").style.color = theme.textColor || "";
    $("storeSub").textContent = theme.title ? msg.label : theme.sub || "";
    $("storeSearch").value = "";
    $("store").classList.remove("hidden");
    paintStore();
}

function paintStore() {
    paintStoreGrid();
    paintStoreCart();
}

function paintStoreGrid() {
    const q = $("storeSearch").value.trim().toLowerCase();
    const list = shopData.items.filter((i) => !q || i.label.toLowerCase().includes(q));
    const scroll = $("storeGrid").scrollTop;
    $("storeGrid").replaceChildren(...(list.length ? list.map((i) => {
        const img = h("img", { src: shopImage(i.item), alt: "" });
        img.addEventListener("error", () => img.replaceWith(h("span", { class: "noimg" }, i.label.charAt(0).toUpperCase())));
        return h("button", {
            class: `store-item${i.locked ? " locked" : ""}`, title: i.locked ? `Permis requis : ${i.license}` : i.description || i.label,
            onclick: () => addToBasket(i, 1),
        }, i.locked ? h("span", { class: "lock" }, "Permis") : null, basket[i.item] ? h("span", { class: "qty" }, `×${basket[i.item]}`) : null,
            img, h("small", null, i.label), h("i", null, i.price > 0 ? shopMoney(i.price) : "Gratuit"));
    }) : [h("p", { class: "store-empty" }, shopData.items.length ? "Aucun article trouvé." : "Ce magasin n'a rien à vendre pour le moment.")]));
    $("storeGrid").scrollTop = scroll;
}

function addToBasket(item, delta) {
    if (item.locked) return shopToast(`Permis requis : ${item.license}.`);
    const next = (basket[item.item] || 0) + delta;
    if (next > (shopData.max || 50)) return shopToast(`${shopData.max || 50} au maximum par article.`);
    if (next <= 0) delete basket[item.item];
    else basket[item.item] = next;
    paintStore();
}

function paintStoreCart() {
    const lines = Object.entries(basket).map(([name, count]) => ({ item: shopItem(name), count })).filter((l) => l.item);
    const total = lines.reduce((sum, l) => sum + l.item.price * l.count, 0);
    const weight = lines.reduce((sum, l) => sum + (l.item.weight || 0) * l.count, 0);
    $("storeCart").replaceChildren(...[
        h("div", { class: "store-cart-head" }, h("span", null, lines.length ? `Panier · ${shopWeight(weight)}` : "Panier vide"), h("b", null, shopMoney(total))),
        lines.length ? h("div", { class: "store-lines" }, lines.map((l) => h("div", { class: "store-line" },
            h("span", null, l.item.label), h("i", null, shopMoney(l.item.price * l.count)),
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
    if (msg.action === "storeClose") {
        shopData = null;
        $("store").classList.add("hidden");
    }
});

// ---------- Aperçu navigateur (index.html#store) ----------

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
