"use strict";

// Menu contextuel : affiché à la souris, sous-menus ouverts au survol (à droite, ou à gauche s'il n'y a pas la place).
// Le jeu envoie les entrées (sans leurs actions) ; un clic renvoie l'id de l'entrée choisie.
// La page n'a jamais le focus (le clavier reste au jeu) : le jeu envoie la position de la souris ("mouse") et les clics
// ("click"), la page retrouve l'entrée sous le pointeur. Après une action, le jeu renvoie les entrées à jour ("update").

const layer = document.getElementById("layer");
const resource = typeof GetParentResourceName === "function" ? GetParentResourceName() : null;

let origin = { x: 0, y: 0 }; // position du menu principal, en pixels
let openPath = []; // index de l'entrée ouverte à chaque profondeur (rouverte après une mise à jour)
let hovered = null; // entrée sous le pointeur
const pointer = document.getElementById("pointer");

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
        row.choose = () => {
            if (item.header || item.disabled || item.children) return;
            row.classList.add("pressed");
            setTimeout(() => row.classList.remove("pressed"), 120);
            nui("select", { id: item.id });
        };
        row.addEventListener("click", (e) => { e.stopPropagation(); row.choose(); });
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
    hovered = null;
    pointer.classList.remove("on");
}

// Entrée sous le point (x, y en fraction de l'écran) ; survol comme avec une vraie souris
function rowAt(x, y) {
    const target = document.elementFromPoint(x * window.innerWidth, y * window.innerHeight);
    return target ? target.closest(".item") : null;
}

function mouse(x, y) {
    pointer.style.transform = `translate(${x * window.innerWidth}px, ${y * window.innerHeight}px)`;
    const row = rowAt(x, y);
    // Pointeur dessiné seulement sur le menu (celui du jeu passe dessous)
    pointer.classList.toggle("on", !!(row || (document.elementFromPoint(x * window.innerWidth, y * window.innerHeight) || layer).closest(".menu")));
    if (row === hovered) return;
    if (hovered) hovered.classList.remove("hover");
    hovered = row;
    if (row) { row.classList.add("hover"); if (row.open) row.open(); }
}

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "open") { open(msg); hovered = null; }
    if (msg.action === "update" && layer.classList.contains("on")) { render(msg.items || [], true); hovered = null; }
    if (msg.action === "close") close();
    if (msg.action === "mouse" && layer.classList.contains("on")) mouse(msg.x, msg.y);
    if (msg.action === "click" && layer.classList.contains("on")) {
        const row = rowAt(msg.x, msg.y);
        if (row && row.choose) row.choose();
    }
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
