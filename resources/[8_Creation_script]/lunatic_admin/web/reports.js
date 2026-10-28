"use strict";

// ====================================================================
//  lunatic_admin — Reports (menu admin, doc Vision) : reports envoyés par les joueurs avec /report.
//  Onglets En attente / Pris en charge / Fermés ; actions Prendre, Aller vers, Ramener, Fermer (réponse au joueur).
//  La liste arrive avec l'état du panel (state.reports) et se rafraîchit à chaque nouveau report.
// ====================================================================

const reportsView = { tab: "open" };
const REPORT_TABS = [
    { value: "open", label: "En attente" },
    { value: "taken", label: "Pris en charge" },
    { value: "closed", label: "Fermés" },
];

function renderReports() {
    const root = $("view-reports");
    const reports = state.reports || [];
    const counts = { open: 0, taken: 0, closed: 0 };
    for (const r of reports) counts[r.status] = (counts[r.status] || 0) + 1;
    const list = reports.filter((r) => r.status === reportsView.tab);

    const tabs = h("div", { class: "segmented", role: "radiogroup" }, segmentedButtons(
        REPORT_TABS.map((t) => ({ value: t.value, label: `${t.label} (${counts[t.value] || 0})` })),
        reportsView.tab, (value) => { reportsView.tab = value; renderReports(); }));

    root.replaceChildren(h("div", { class: "content" },
        h("div", { class: "page-head" }, h("div", { class: "grow" },
            h("h1", { class: "page-title" }, "Reports"),
            h("div", { class: "page-sub" }, counts.open ? `${counts.open} report${counts.open > 1 ? "s" : ""} en attente` : "Aucun report en attente"))),
        h("div", { class: "toolbar" }, tabs),
        h("div", { class: "scroll" }, list.length
            ? h("div", { class: "table" }, list.map(reportRow))
            : h("div", { class: "empty" }, icon("i-flag"), reportsView.tab === "open" ? "Aucun report en attente. Les joueurs en envoient avec /report." : "Rien ici pour le moment."))));
}

function reportRow(r) {
    const when = r.status === "closed" ? `fermé ${ago(r.closed)}` : r.status === "taken" ? `pris ${ago(r.taken)} par ${r.staff}` : ago(r.created);
    const who = h("span", { class: "who" },
        h("b", null, `#${r.id} · ${r.name}`, r.online ? h("span", { class: "muted" }, ` (ID ${r.serverId})`) : h("span", { class: "badge ban", style: "margin-left:6px" }, "hors ligne")),
        h("span", null, r.message),
        h("span", { class: "muted" }, when),
        r.answer ? h("span", { class: "muted" }, `Réponse : ${r.answer}`) : null);
    const actions = r.status === "closed" ? [] : [
        r.status === "open" ? h("button", { class: "btn small primary", onclick: () => act("reports.take", { id: r.id }, `Report #${r.id} pris en charge.`) }, "Prendre") : null,
        h("button", { class: "btn small ghost", disabled: !r.online, title: "Aller vers le joueur", onclick: () => act("reports.goto", { id: r.id }, null) }, icon("i-goto"), "Aller vers"),
        h("button", { class: "btn small ghost", disabled: !r.online, title: "Ramener le joueur à vous", onclick: () => act("reports.bring", { id: r.id }, null) }, icon("i-bring"), "Ramener"),
        h("button", { class: "btn small", onclick: () => closeReport(r) }, icon("i-x"), "Fermer"),
    ].filter(Boolean);
    return h("div", { class: "row report-row" }, who, h("div", { class: "btn-row" }, actions));
}

function closeReport(r) {
    const answer = h("textarea", { class: "input", rows: "3", maxlength: "300", placeholder: "Réponse envoyée au joueur (facultative)" });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-x"), "Fermer le report");
        submit.addEventListener("click", async () => {
            const res = await act("reports.close", { id: r.id, answer: answer.value.trim() }, `Report #${r.id} fermé.`);
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, `Fermer le report #${r.id}`), h("p", null, `${r.name} : ${r.message}`)),
            h("div", { class: "body" }, h("div", { class: "field" }, h("label", null, "Réponse"), answer)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    answer.focus();
}
