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

// Fiche du joueur (comme dans le panel) à côté du menu ; repeinte seulement si elle change
let quickSheetKey = "";

function paintQuickSheet(info) {
    const box = $("quickSheet");
    if (!info) {
        quickSheetKey = "";
        return box.classList.remove("on");
    }
    const key = JSON.stringify(info);
    box.classList.add("on");
    if (key === quickSheetKey) return;
    quickSheetKey = key;
    const health = typeof info.health === "number" ? info.health : null;
    const maxHealth = info.maxHealth || 200;
    const healthPct = health === null ? 0 : ((health - 100) / Math.max(1, maxHealth - 100)) * 100;
    const down = health !== null && health <= 100;
    box.replaceChildren(
        h("div", { class: "crew-col-head" }, icon("i-player"), "Fiche du joueur"),
        h("div", { class: "quick-sheet-body" },
            h("div", { class: "crew-id player-id" },
                h("div", { class: "crew-pic" }, mugshotImg(info.identifier, "mug-head")),
                h("div", { class: "crew-id-text" },
                    h("b", null, info.name),
                    h("span", { class: "muted" }, info.serverId ? `ID ${info.serverId} · ${info.pseudo || "—"}` : "Hors ligne"),
                    h("span", { class: "mono muted" }, shortLicense(info.license)),
                    h("div", { class: "btn-row" }, info.rank ? rankPill(info.rank) : null, info.isSelf ? h("span", { class: "you" }, "Vous") : null,
                        info.premium ? h("span", { class: "badge ok" }, info.premium.label) : null))),
            info.serverId ? h("div", { class: "card" },
                bar("Santé", health === null ? "—" : down ? "Au sol" : `${Math.round(healthPct)} %`, healthPct, down ? "var(--danger)" : "var(--ok)"),
                bar("Armure", typeof info.armor === "number" ? `${info.armor} %` : "—", info.armor || 0, "var(--info)"),
                h("div", { class: "info-cols" }, infoRow("Ping", `${info.ping} ms`), infoRow("Figé", info.frozen ? "Oui" : "Non"),
                    info.jail ? infoRow("Prison", `${Math.ceil(info.jail.remaining / 60)} min`) : null)) : null,
            profileCard(info)));
}

window.addEventListener("message", (event) => {
    const msg = event.data;
    if (!msg || typeof msg !== "object") return;
    if (msg.action === "quick" && msg.data) {
        document.body.classList.add("quick-open");
        paintQuick(msg.data);
        paintQuickSheet(msg.data.sheet || null);
    } else if (msg.action === "quickClose") {
        document.body.classList.remove("quick-open");
        paintQuickSheet(null);
    }
});

// Aperçu hors jeu : index.html#quick
if (typeof GetParentResourceName !== "function" && location.hash.includes("quick")) {
    window.postMessage({ action: "quick", data: {
        title: "Administration", subtitle: "7 · RiderCool", index: 2, depth: 2, stats: { online: 94, staff: 12, reports: 3 },
        sheet: { serverId: 7, name: "RiderCool", pseudo: "RiderCool", license: "license:25c26900000000000000000000000000000009be3", identifier: "char1:aaa", rank: { name: "Fondateur", color: "#9650ff" }, isSelf: true,
            health: 200, maxHealth: 200, armor: 0, ping: 32, frozen: false, money: 90, bank: 169625, job: { label: "Burger Shot", grade: "Patron" }, onDuty: true,
            dateofbirth: "16/12/1987", sex: "m", height: 194, profile: { discord: "327980186615488328", firstSeen: 1792873740, playtime: 1179, warns: 0, crew: { label: "Ballas", rank: "Rang S" }, linked: [] } },
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
