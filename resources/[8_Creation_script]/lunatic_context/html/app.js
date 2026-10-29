"use strict";

// Menu contextuel : affiché à la souris, sous-menus ouverts au survol (à droite, ou à gauche s'il n'y a pas la place).
// Le jeu envoie les entrées (sans leurs actions) ; un clic renvoie l'id de l'entrée choisie.

const layer = document.getElementById("layer");
const resource = typeof GetParentResourceName === "function" ? GetParentResourceName() : null;

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
    for (const item of items) {
        if (item.separator) { menu.append(el("div", "sep")); continue; }
        const row = el("div", ["item", item.color, item.header && "header", item.disabled && "disabled"].filter(Boolean).join(" "));
        row.append(el("span", null, item.label));
        if (item.children) row.append(el("i", "arrow", "›"));
        else if (item.right) row.append(el("small", null, item.right));

        row.addEventListener("mouseenter", () => {
            closeDeeper(depth);
            menu.querySelectorAll(".item.open").forEach((r) => r.classList.remove("open"));
            if (item.children && !item.disabled) {
                row.classList.add("open");
                openSubmenu(item.children, row, depth + 1);
            }
        });
        row.addEventListener("click", (e) => {
            e.stopPropagation();
            if (item.header || item.disabled || item.children) return;
            close();
            nui("select", { id: item.id });
        });
        menu.append(row);
    }
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
}

function open(msg) {
    layer.replaceChildren();
    layer.classList.add("on");
    place(buildMenu(msg.items || [], 0), msg.x * window.innerWidth, msg.y * window.innerHeight);
}

function close() {
    layer.classList.remove("on");
    layer.replaceChildren();
}

// Clic en dehors, clic droit ou Échap : fermé
layer.addEventListener("mousedown", (e) => {
    if (!e.target.closest(".menu")) { close(); nui("close"); }
});
document.addEventListener("contextmenu", (e) => { e.preventDefault(); if (!e.target.closest(".menu")) { close(); nui("close"); } });
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && layer.classList.contains("on")) { close(); nui("close"); } });

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "open") open(msg);
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
