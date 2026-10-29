"use strict";

// Menu contextuel : affiché à la souris, sous-menus ouverts au survol (à droite, ou à gauche s'il n'y a pas la place).
// Le jeu envoie les entrées (sans leurs actions) ; un clic renvoie l'id de l'entrée choisie.
// Le menu reste affiché tant qu'Alt est maintenu : après une action, le jeu renvoie les entrées à jour ("update"),
// un clic droit ailleurs vise autre chose ("retarget"), relâcher Alt ou Échap ferme.

const layer = document.getElementById("layer");
const resource = typeof GetParentResourceName === "function" ? GetParentResourceName() : null;

let origin = { x: 0, y: 0 }; // position du menu principal, en pixels
let openPath = []; // index de l'entrée ouverte à chaque profondeur (rouverte après une mise à jour)

function nui(name, payload) {
    if (!resource) return Promise.resolve({});
    return fetch(`https://${resource}/${name}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload || {}) }).catch(() => null);
}

function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
}

// Menu d'un niveau ; depth = profondeur (les sous-menus plus profonds se ferment quand on change d'entrée)
function buildMenu(items, depth) {
    const menu = el("div", "menu");
    menu.dataset.depth = String(depth);
    menu.rows = [];
    items.forEach((item, index) => {
        if (item.separator) { menu.append(el("div", "sep")); menu.rows.push(null); return; }
        const row = el("div", ["item", item.color, item.header && "header", item.disabled && "disabled"].filter(Boolean).join(" "));
        row.append(el("span", null, item.label));
        if (item.children) row.append(el("i", "arrow", "›"));
        else if (item.right) row.append(el("small", null, item.right));

        row.open = () => {
            closeDeeper(depth);
            menu.querySelectorAll(".item.open").forEach((r) => r.classList.remove("open"));
            openPath.length = depth;
            if (item.children && !item.disabled) {
                row.classList.add("open");
                openPath[depth] = index;
                openSubmenu(item.children, row, depth + 1);
            }
        };
        row.addEventListener("mouseenter", row.open);
        row.addEventListener("click", (e) => {
            e.stopPropagation();
            if (item.header || item.disabled || item.children) return;
            nui("select", { id: item.id });
        });
        menu.append(row);
        menu.rows.push(row);
    });
    return menu;
}

function closeDeeper(depth) {
    layer.querySelectorAll(".menu").forEach((m) => { if (Number(m.dataset.depth) > depth) m.remove(); });
}

// Position dans l'écran : décalé à gauche ou vers le haut s'il dépasse
function place(menu, x, y) {
    layer.append(menu);
    const w = menu.offsetWidth, h = menu.offsetHeight;
    menu.style.left = `${Math.max(6, Math.min(x, window.innerWidth - w - 6))}px`;
    menu.style.top = `${Math.max(6, Math.min(y, window.innerHeight - h - 6))}px`;
}

function openSubmenu(items, row, depth) {
    const menu = buildMenu(items, depth);
    const rect = row.getBoundingClientRect();
    layer.append(menu);
    const fitsRight = rect.right + menu.offsetWidth + 4 < window.innerWidth;
    const x = fitsRight ? rect.right + 4 : rect.left - menu.offsetWidth - 4;
    place(menu, x, rect.top - 4);
    return menu;
}

// Menu principal à la position retenue ; keepPath : rouvre les sous-menus ouverts avant la mise à jour
function render(items, keepPath) {
    const path = keepPath ? openPath.slice() : [];
    layer.replaceChildren();
    openPath = [];
    if (!items.length) return;
    let menu = buildMenu(items, 0);
    place(menu, origin.x, origin.y);
    for (const index of path) {
        const row = menu.rows[index];
        if (!row) break;
        row.open();
        menu = layer.querySelector(`.menu[data-depth="${Number(menu.dataset.depth) + 1}"]`);
        if (!menu) break;
    }
}

function open(msg) {
    origin = { x: msg.x * window.innerWidth, y: msg.y * window.innerHeight };
    layer.classList.add("on");
    render(msg.items || [], false);
}

function close() {
    layer.classList.remove("on");
    layer.replaceChildren();
    openPath = [];
}

function closeAndTell() {
    if (!layer.classList.contains("on")) return;
    close();
    nui("close");
}

// Clic droit hors du menu : nouvelle cible à cet endroit ; clic gauche hors du menu : rien
document.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    if (!layer.classList.contains("on") || e.target.closest(".menu")) return;
    nui("retarget", { x: e.clientX / window.innerWidth, y: e.clientY / window.innerHeight });
});

// Alt relâché ou Échap : fermé
document.addEventListener("keyup", (e) => { if (e.key === "Alt") { e.preventDefault(); closeAndTell(); } });
document.addEventListener("keydown", (e) => {
    if (e.key === "Alt") e.preventDefault();
    if (e.key === "Escape") closeAndTell();
});
window.addEventListener("blur", closeAndTell);

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "open") open(msg);
    if (msg.action === "update" && layer.classList.contains("on")) render(msg.items || [], true);
    if (msg.action === "close") close();
});

// Aperçu hors jeu
if (!resource) {
    window.postMessage({ action: "open", x: 0.35, y: 0.4, items: [
        { id: "1", label: "ID 12 · Jean Dupont", header: true },
        { id: "2", label: "Emotes rapides", children: [{ id: "21", label: "Saluer" }, { id: "22", label: "Applaudir" }, { id: "23", label: "Croiser les bras" }] },
        { id: "3", label: "Arrêter l'animation" },
        { id: "4", label: "Montrer ma carte d'identité" },
        { separator: true },
        { id: "5", label: "Action joueur", color: "red", children: [{ id: "51", label: "Ouvrir la fiche" }, { id: "52", label: "Aller vers" }, { id: "53", label: "Ramener" }] },
        { id: "6", label: "Action développeur", color: "blue", children: [{ id: "61", label: "Copier vector3" }] },
    ] }, "*");
}
