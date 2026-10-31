"use strict";

// Poste de craft (doc Vision) : trois colonnes. Recettes ; table de craft (recette choisie, durée, quantité, ingrédients
// possédés / nécessaires, « Fabriquer ») et file d'attente ; objets du joueur (ingrédients de la recette en évidence).
// La file tourne côté serveur ; l'écran affiche l'état qu'il reçoit. $, h et nui viennent de app.js.

let craftData = null;
let craftSelected = null; // index de la recette
let craftQty = 1;
let craftBusy = false;
let craftReceived = 0;    // heure de réception de l'état (avancement de l'unité en cours)

const craftImage = (name) => `nui://ox_inventory/web/images/${name}.png`;

function craftImg(name, label) {
    const img = h("img", { src: craftImage(name), alt: "" });
    img.addEventListener("error", () => img.replaceWith(h("span", { class: "noimg" }, (label || "?").charAt(0).toUpperCase())));
    return img;
}

function craftToast(text) {
    const el = $("craftToast");
    el.textContent = text;
    el.classList.add("on");
    clearTimeout(craftToast.timer);
    craftToast.timer = setTimeout(() => el.classList.remove("on"), 3500);
}

const craftHave = (name) => (craftData.state.inventory.find((i) => i.name === name) || {}).count || 0;
const craftRecipe = () => (craftSelected === null ? null : craftData.recipes[craftSelected]);
const craftTime = (seconds) => (seconds >= 60 ? `${Math.floor(seconds / 60)} min${seconds % 60 ? ` ${seconds % 60} s` : ""}` : `${seconds} s`);

function openCraftView(data) {
    craftData = data;
    craftQty = 1;
    craftBusy = false;
    craftReceived = Date.now();
    const first = data.recipes.findIndex((r) => !r.locked);
    craftSelected = first >= 0 ? first : null;
    $("craftTitle").textContent = data.point ? `${data.label} · ${data.point}` : data.label;
    $("craft").classList.remove("hidden");
    paintCraft();
}

function paintCraft() {
    paintCraftRecipes();
    paintCraftTable();
    paintCraftQueue();
    paintCraftInventory();
}

function paintCraftRecipes() {
    $("craftRecipes").replaceChildren(...craftData.recipes.map((r, index) => h("button", {
        class: `craft-recipe${index === craftSelected ? " on" : ""}${r.locked ? " locked" : ""}`,
        title: r.locked ? `Grade minimum : ${r.minGrade}` : r.catalog,
        onclick: () => { craftSelected = index; craftQty = 1; paintCraft(); },
    }, craftImg(r.item, r.label), h("span", null, `${r.count > 1 ? `${r.count} × ` : ""}${r.label}`), r.locked ? h("i", null, `Grade ${r.minGrade}`) : null)));
}

function paintCraftTable() {
    const recipe = craftRecipe();
    if (!recipe) return $("craftTable").replaceChildren(h("p", { class: "store-empty" }, "Choisissez une recette."));

    const missing = recipe.ingredients.filter((i) => craftHave(i.item) < i.count * craftQty);
    const step = (delta) => { craftQty = Math.max(1, Math.min(craftData.max || 20, craftQty + delta)); paintCraftTable(); paintCraftInventory(); };

    $("craftTable").replaceChildren(
        h("div", { class: "craft-head" },
            craftImg(recipe.item, recipe.label),
            h("div", { class: "craft-name" }, h("b", null, recipe.label), h("small", null, `${recipe.count > 1 ? `${recipe.count} par fabrication · ` : ""}${craftTime(recipe.duration)} par unité`)),
            h("div", { class: "store-step" },
                h("button", { title: "Moins", onclick: () => step(-1) }, "−"), h("b", null, String(craftQty)),
                h("button", { title: "Plus", onclick: () => step(1) }, "+"))),
        h("div", { class: "craft-ingredients" }, recipe.ingredients.map((i) => {
            const need = i.count * craftQty;
            const have = craftHave(i.item);
            return h("div", { class: `craft-ingredient${have < need ? " short" : ""}` }, craftImg(i.item, i.label), h("span", null, i.label), h("b", null, `${have} / ${need}`));
        })),
        h("button", {
            class: "store-btn craft-go", disabled: craftBusy || recipe.locked || missing.length > 0, onclick: addCraft,
        }, recipe.locked ? `Réservé au grade ${recipe.minGrade}` : missing.length ? `Il manque : ${missing.map((i) => i.label).join(", ")}` : `Fabriquer${craftQty > 1 ? ` × ${craftQty}` : ""} · ${craftTime(recipe.duration * craftQty)}`));
}

function paintCraftQueue() {
    const queue = craftData.state.queue || [];
    $("craftQueue").replaceChildren(...(queue.length ? queue.map((job, index) => {
        const bar = h("i", { class: "craft-bar" });
        bar.dataset.first = index === 0 ? "1" : "";
        const status = job.waiting ? "Inventaire plein" : index === 0 ? "En cours" : "En attente";
        return h("div", { class: `craft-job${job.waiting ? " waiting" : ""}` },
            craftImg(job.item, job.label),
            h("div", { class: "craft-job-main" },
                h("div", { class: "craft-job-line" }, h("b", null, job.label), h("small", null, `${job.done} / ${job.qty} · ${status}`)),
                h("div", { class: "gauge" }, bar)),
            h("button", { class: "craft-cancel", title: "Annuler", onclick: () => cancelCraft(index + 1) }, "✕"));
    }) : [h("p", { class: "store-empty" }, "Aucune fabrication en cours.")]));
    tickCraft();
}

function paintCraftInventory() {
    const recipe = craftRecipe();
    const needed = new Set(recipe ? recipe.ingredients.map((i) => i.item) : []);
    const items = craftData.state.inventory || [];
    $("craftInventory").replaceChildren(...(items.length ? items.map((i) => h("div", { class: `craft-item${needed.has(i.name) ? " need" : ""}`, title: i.label },
        h("span", { class: "qty" }, String(i.count)), craftImg(i.name, i.label), h("small", null, i.label))) : [h("p", { class: "store-empty" }, "Inventaire vide.")]));
}

// Avancement de l'unité en cours (temps restant reçu du serveur, décompté ici)
function tickCraft() {
    if (!craftData) return;
    const job = (craftData.state.queue || [])[0];
    const bar = document.querySelector('#craftQueue .craft-bar[data-first="1"]');
    if (!job || !bar || job.left === null || job.left === undefined) return;
    const left = Math.max(0, job.left - (Date.now() - craftReceived));
    bar.style.width = `${Math.min(100, (1 - left / (job.duration * 1000)) * 100)}%`;
}
setInterval(tickCraft, 200);

async function addCraft() {
    const recipe = craftRecipe();
    if (!recipe || craftBusy) return;
    craftBusy = true;
    paintCraftTable();
    const res = inGame ? await nui("craftAdd", { catalogId: recipe.catalogId, lineId: recipe.lineId, qty: craftQty }) : { ok: false, error: "Aperçu : pas de fabrication hors jeu." };
    craftBusy = false;
    if (res && res.state) setCraftState(res.state);
    else paintCraftTable();
    if (!res || !res.ok) return craftToast((res && res.error) || "Fabrication impossible.");
    craftToast(`${recipe.label} ajouté à la file.`);
}

async function cancelCraft(index) {
    const res = inGame ? await nui("craftCancel", { index }) : { ok: false, error: "Aperçu : rien à annuler." };
    if (res && res.state) setCraftState(res.state);
    if (!res || !res.ok) craftToast((res && res.error) || "Annulation impossible.");
}

function setCraftState(state) {
    if (!craftData) return;
    craftData.state = state;
    craftReceived = Date.now();
    paintCraftTable();
    paintCraftQueue();
    paintCraftInventory();
}

function closeCraftView() {
    $("craft").classList.add("hidden");
    craftData = null;
}

$("craftClose").addEventListener("click", () => { closeCraftView(); nui("craftClose"); });

document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && craftData && !$("craft").classList.contains("hidden")) {
        closeCraftView();
        nui("craftClose");
    }
});

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "craftOpen") openCraftView(msg.craft);
    if (msg.action === "craftState") setCraftState(msg.state);
    if (msg.action === "craftClose") closeCraftView();
});

// ---------- Aperçu navigateur (index.html#craft) ----------

if (!inGame && location.hash.includes("craft")) {
    window.postMessage({
        action: "craftOpen", craft: {
            label: "Bahama Mamas", point: "Bar", max: 20,
            recipes: [
                { catalogId: 1, lineId: 1, catalog: "Cocktails", item: "blue_hawaiian", label: "Blue Hawaiian", count: 1, duration: 20, minGrade: 0, locked: false,
                    ingredients: [{ item: "rum", label: "Rhum blanc", count: 1 }, { item: "curacao", label: "Curaçao bleu", count: 1 }, { item: "coconut", label: "Crème de coco", count: 1 }, { item: "pineapple", label: "Jus d'ananas", count: 1 }] },
                { catalogId: 1, lineId: 2, catalog: "Cocktails", item: "blue_lagoon", label: "Blue Lagoon", count: 1, duration: 15, minGrade: 0, locked: false, ingredients: [{ item: "vodka", label: "Vodka", count: 1 }] },
                { catalogId: 1, lineId: 3, catalog: "Snacks", item: "crostini", label: "Crostini", count: 2, duration: 30, minGrade: 2, locked: true, ingredients: [{ item: "bread", label: "Pain", count: 1 }] },
            ],
            state: {
                queue: [{ item: "blue_hawaiian", label: "Blue Hawaiian", count: 1, qty: 3, done: 1, duration: 20, left: 12000 }, { item: "blue_lagoon", label: "Blue Lagoon", count: 1, qty: 1, done: 0, duration: 15 }],
                inventory: [{ name: "rum", label: "Rhum blanc", count: 10 }, { name: "curacao", label: "Curaçao bleu", count: 10 }, { name: "coconut", label: "Crème de coco", count: 2 }, { name: "pineapple", label: "Jus d'ananas", count: 10 }, { name: "bread", label: "Pain", count: 5 }, { name: "tomato", label: "Tomate", count: 6 }],
            },
        },
    }, "*");
}
