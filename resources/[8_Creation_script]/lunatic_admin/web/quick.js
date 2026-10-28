"use strict";

// ====================================================================
//  lunatic_admin — Menu rapide du staff (menu admin, doc Vision) : affichage seulement. Le jeu (client/quickmenu.lua)
//  gère le clavier pendant que le personnage reste libre, et envoie le menu à afficher : titre, entrées, sélection,
//  description. Au plus 10 entrées visibles, la liste défile avec la sélection.
// ====================================================================

const QUICK_VISIBLE = 10;

function paintQuick(data) {
    const items = data.items || [];
    const start = Math.max(0, Math.min(data.index - 1 - Math.floor(QUICK_VISIBLE / 2), items.length - QUICK_VISIBLE));
    const visible = items.slice(start, start + QUICK_VISIBLE);
    const stats = data.stats;

    $("quick").replaceChildren(...[
        h("header", { class: "quick-head" }, h("b", null, data.title || "Administration")),
        h("div", { class: "quick-sub" }, h("span", null, data.subtitle || ""), h("span", null, `${data.index}/${items.length}`)),
        stats && data.depth === 1 ? h("div", { class: "quick-stats" },
            h("span", null, h("b", null, String(stats.online ?? 0)), " en ligne"),
            h("span", null, h("b", null, String(stats.staff ?? 0)), " en service"),
            h("span", null, h("b", null, String(stats.reports ?? 0)), " reports")) : null,
        h("div", { class: "quick-list" }, visible.map((item, i) => {
            const index = start + i + 1;
            return h("div", { class: `quick-item${index === data.index ? " on" : ""}${item.disabled ? " disabled" : ""}${item.info ? " info" : ""}` },
                h("span", null, item.label),
                item.toggle ? h("i", { class: `quick-switch${item.on ? " on" : ""}` }, h("i"))
                    : item.right ? h("i", { class: "quick-right" }, item.right)
                    : item.info ? null : h("i", { class: "quick-arrow" }, "›"));
        })),
        items.length > QUICK_VISIBLE ? h("div", { class: "quick-more" }, start > 0 ? "▲" : "", start + QUICK_VISIBLE < items.length ? "▼" : "") : null,
        data.desc ? h("div", { class: "quick-desc" }, data.desc) : null,
        h("footer", { class: "quick-foot" }, data.depth > 1 ? "Flèches · Entrée · Retour arrière : revenir" : "Flèches · Entrée · Retour arrière ou F9 : fermer"),
    ].filter(Boolean));
}

window.addEventListener("message", (event) => {
    const msg = event.data;
    if (!msg || typeof msg !== "object") return;
    if (msg.action === "quick" && msg.data) {
        document.body.classList.add("quick-open");
        paintQuick(msg.data);
    } else if (msg.action === "quickClose") {
        document.body.classList.remove("quick-open");
    }
});

// Aperçu hors jeu : index.html#quick
if (typeof GetParentResourceName !== "function" && location.hash.includes("quick")) {
    window.postMessage({ action: "quick", data: {
        title: "Administration", subtitle: "Kévin", index: 2, depth: 1, stats: { online: 94, staff: 12, reports: 3 },
        desc: null,
        items: [
            { label: "Mode administration", toggle: true, on: true },
            { label: "Liste des reports", right: "3" },
            { label: "Liste des joueurs", right: "94" },
            { label: "Liste des modérateurs et staff" },
            { label: "Joueurs hors ligne" },
            { label: "Outils de modération" },
            { label: "Gestion" },
        ],
    } }, "*");
}
