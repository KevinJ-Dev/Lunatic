"use strict";

// ====================================================================
//  lunatic_admin — Menu rapide du staff (menu admin, doc Vision) : ouvert par une touche (F9 par défaut) panel fermé.
//  Mode administration, reports, joueurs, staff, joueurs hors ligne, outils, gestion ; chaque entrée ouvre le panel
//  sur la bonne page. Souris, ou flèches + Entrée ; Échap ou F9 pour fermer.
// ====================================================================

let quickData = null;
let quickIndex = 0;

function quickEntries() {
    const can = quickData.can || {};
    return [
        { id: "adminMode", label: "Mode administration", toggle: true, on: quickData.adminMode },
        can.reports ? { id: "reports", label: "Liste des reports", badge: quickData.reports } : null,
        can.players ? { id: "players", label: "Liste des joueurs" } : null,
        can.staff ? { id: "members", label: "Liste des modérateurs et staff" } : null,
        can.offline ? { id: "offline", label: "Joueurs hors ligne" } : null,
        can.tools ? { id: "tools", label: "Outils de modération" } : null,
        { id: "home", label: "Gestion" },
    ].filter(Boolean);
}

function paintQuick() {
    const entries = quickEntries();
    quickIndex = Math.max(0, Math.min(quickIndex, entries.length - 1));
    const stat = (value, label) => h("span", null, h("b", null, String(value ?? 0)), label);

    $("quick").replaceChildren(
        h("header", { class: "quick-head" }, h("b", null, "Administration"), h("small", null, quickData.name || "")),
        h("div", { class: "quick-stats" }, stat(quickData.online, " en ligne"), stat(quickData.staff, " en service"), stat(quickData.reports, " reports")),
        h("div", { class: "quick-list" }, entries.map((entry, index) => h("button", {
            class: `quick-item${index === quickIndex ? " on" : ""}`,
            onmouseenter: () => { if (quickIndex !== index) { quickIndex = index; paintQuick(); } },
            onclick: () => chooseQuick(entry),
        }, h("span", null, entry.label),
            entry.toggle ? h("i", { class: `quick-switch${entry.on ? " on" : ""}` }, h("i"))
                : entry.badge ? h("i", { class: "quick-badge" }, String(entry.badge)) : h("i", { class: "quick-arrow" }, "›")))),
        h("footer", { class: "quick-foot" }, "Flèches + Entrée · Échap pour fermer"));
}

function chooseQuick(entry) {
    nui("quickAction", { id: entry.id });
}

function closeQuickMenu() {
    if (!quickData) return;
    quickData = null;
    document.body.classList.remove("quick-open");
    nui("quickClose");
}

// Clavier : capté avant les raccourcis du panel tant que le menu rapide est ouvert
document.addEventListener("keydown", (e) => {
    if (!quickData) return;
    const entries = quickEntries();
    if (e.key === "ArrowDown") quickIndex = (quickIndex + 1) % entries.length;
    else if (e.key === "ArrowUp") quickIndex = (quickIndex - 1 + entries.length) % entries.length;
    else if (e.key === "Enter") chooseQuick(entries[quickIndex]);
    else if (e.key === "Escape" || e.key === "F9") closeQuickMenu();
    else return;
    e.preventDefault();
    e.stopImmediatePropagation();
    if (quickData) paintQuick();
}, true);

window.addEventListener("message", (event) => {
    const msg = event.data;
    if (!msg || typeof msg !== "object") return;
    if (msg.action === "quick" && msg.data) {
        quickData = msg.data;
        document.body.classList.add("quick-open");
        paintQuick();
    } else if (msg.action === "quickClose") {
        quickData = null;
        document.body.classList.remove("quick-open");
    }
});

// Aperçu hors jeu : index.html#quick
if (typeof GetParentResourceName !== "function" && location.hash.includes("quick")) {
    window.postMessage({ action: "quick", data: { name: "Kévin", adminMode: true, online: 94, staff: 12, reports: 3, can: { reports: true, players: true, staff: true, offline: true, tools: true } } }, "*");
}
