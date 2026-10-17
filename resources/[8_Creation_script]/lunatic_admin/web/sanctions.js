"use strict";

// ====================================================================
//  lunatic_admin — lot 3 : sanctions (fiche joueur, page Sanctions, avertissement reçu)
//  Chargé après app.js, dont il utilise les outils (h, icon, nui, act, can, openModal…).
// ====================================================================

let playerHistory = null; // { license, list } : historique affiché sur la fiche
const sanctionsView = { tab: "history", status: "active", type: "all", search: "", list: null };
let sanctionsDom = null;
let searchTimer = null;

const DURATIONS = [
    { label: "1 h", hours: 1 },
    { label: "6 h", hours: 6 },
    { label: "1 jour", hours: 24 },
    { label: "3 jours", hours: 72 },
    { label: "7 jours", hours: 168 },
    { label: "30 jours", hours: 720 },
];

function fmtDate(ts) {
    if (typeof ts !== "number") return "—";
    return new Date(ts * 1000).toLocaleString("fr-FR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

function ago(ts) {
    const minutes = Math.max(0, Math.round((Date.now() / 1000 - ts) / 60));
    if (minutes < 1) return "à l'instant";
    if (minutes < 60) return `il y a ${minutes} min`;
    const hours = Math.round(minutes / 60);
    return hours < 24 ? `il y a ${hours} h` : `il y a ${Math.round(hours / 24)} j`;
}

// ---------- Affichage d'une sanction ----------

function typeBadge(s) {
    return s.type === "ban"
        ? h("span", { class: "badge ban" }, icon("i-ban"), "Ban")
        : h("span", { class: "badge warn" }, icon("i-warn"), "Avertissement");
}

function statusBadge(s) {
    if (s.revoked) return h("span", { class: "badge muted", title: `Révoqué par ${s.revokedBy || "?"} : ${s.revokeReason || ""}` }, "Révoqué");
    if (s.type === "warn") return h("span", { class: "badge muted" }, "Donné");
    if (!s.active) return h("span", { class: "badge muted" }, "Expiré");
    return h("span", { class: "badge ban" }, s.expires ? `Jusqu'au ${fmtDate(s.expires)}` : "Définitif");
}

function sanctionRow(s, compact) {
    return h("div", { class: `sanction-row${s.active ? "" : " inactive"}` },
        h("span", { class: "ref" }, `#${s.id}`),
        typeBadge(s),
        compact ? null : h("div", { class: "who" }, h("b", null, s.name || "—"), h("span", null, shortLicense(s.license))),
        h("div", { class: "reason", title: s.reason }, s.reason),
        h("div", { class: "when" }, fmtDate(s.created), h("span", null, `par ${s.staff || "?"}`)),
        h("div", { class: "sanction-end" },
            statusBadge(s),
            s.canRevoke ? h("button", { class: "btn small ghost", title: "Révoquer", onclick: () => openRevoke(s) }, icon("i-undo"), "Révoquer") : null
        )
    );
}

// ---------- Historique sur la fiche joueur ----------

async function loadPlayerHistory(license) {
    try {
        const res = await nui("action", { action: "sanctions.history", payload: { license } });
        playerHistory = { license, list: res && res.ok ? list(res.sanctions) : [] };
    } catch (e) {
        return;
    }
    if (view === "players" && playersDom) paintFiche();
}

function historyCard(info) {
    const loaded = playerHistory && playerHistory.license === info.license;
    const items = loaded ? playerHistory.list : [];
    return h("div", { class: "card", style: "margin-top:16px" },
        h("h3", { class: "card-title" }, `Sanctions${loaded ? ` (${items.length})` : ""}`),
        !loaded ? h("span", { class: "muted" }, "Chargement…")
            : items.length ? h("div", { class: "history" }, items.map((s) => sanctionRow(s, true)))
                : h("span", { class: "muted" }, "Aucune sanction.")
    );
}

// ---------- Page Sanctions ----------

function renderSanctions() {
    const root = $("view-sanctions");

    // Structure gardée entre deux rafraîchissements (recherche conservée)
    if (!sanctionsDom || !root.contains(sanctionsDom.body)) {
        const search = h("input", { placeholder: "Nom ou référence (#42)", value: sanctionsView.search });
        search.addEventListener("input", () => {
            sanctionsView.search = search.value;
            clearTimeout(searchTimer);
            searchTimer = setTimeout(fetchSanctions, 300);
        });
        sanctionsDom = {
            sub: h("div", { class: "page-sub" }),
            tabs: h("div", { class: "segmented", role: "radiogroup" }),
            filters: h("div", { class: "filters" }),
            search: h("label", { class: "search" }, icon("i-search"), search),
            body: h("div", { class: "table" }),
        };
        root.replaceChildren(h("div", { class: "content" },
            h("div", { class: "page-head" }, h("div", { class: "grow" }, h("h1", { class: "page-title" }, "Sanctions"), sanctionsDom.sub)),
            h("div", { class: "toolbar" }, sanctionsDom.tabs, sanctionsDom.filters, h("span", { class: "grow" }), sanctionsDom.search),
            h("div", { class: "scroll" }, sanctionsDom.body)
        ));
        fetchSanctions();
    }

    if (sanctionsView.tab === "recent" && !can("sanctions.ban")) sanctionsView.tab = "history";
    paintSanctions();
}

function segmentedButtons(options, current, onChange) {
    return options.map((o) => h("button", { "aria-checked": String(current === o.value), onclick: () => onChange(o.value) }, o.label));
}

function paintSanctions() {
    const v = sanctionsView;
    const tabs = [{ value: "history", label: "Historique" }];
    if (can("sanctions.ban")) tabs.push({ value: "recent", label: `Déconnexions récentes (${(state.recent || []).length})` });
    sanctionsDom.tabs.replaceChildren(...segmentedButtons(tabs, v.tab, (value) => { v.tab = value; paintSanctions(); }));

    const history = v.tab === "history";
    sanctionsDom.filters.style.display = history ? "flex" : "none";
    sanctionsDom.search.style.display = history ? "" : "none";
    sanctionsDom.filters.replaceChildren(
        h("div", { class: "segmented" }, ...segmentedButtons([{ value: "active", label: "Actives" }, { value: "all", label: "Toutes" }], v.status, (value) => { v.status = value; paintSanctions(); fetchSanctions(); })),
        h("div", { class: "segmented" }, ...segmentedButtons([{ value: "all", label: "Tout" }, { value: "warn", label: "Avertissements" }, { value: "ban", label: "Bans" }], v.type, (value) => { v.type = value; paintSanctions(); fetchSanctions(); }))
    );

    if (history) {
        sanctionsDom.sub.textContent = v.list ? `${v.list.length} résultat${v.list.length > 1 ? "s" : ""}${v.list.length === 100 ? " (les 100 plus récents)" : ""}` : "Chargement…";
        sanctionsDom.body.replaceChildren(...(!v.list ? [h("div", { class: "empty" }, "Chargement…")]
            : v.list.length ? v.list.map((s) => sanctionRow(s, false))
                : [h("div", { class: "empty" }, icon("i-gavel"), "Aucune sanction ne correspond.")]));
        return;
    }

    const recent = state.recent || [];
    sanctionsDom.sub.textContent = "Joueurs partis récemment : bannissables même hors ligne";
    sanctionsDom.body.replaceChildren(...(recent.length ? recent.map((r) => h("div", { class: "recent-row" },
        h("div", { class: "who" }, h("b", null, r.name), h("span", { class: "muted mono" }, shortLicense(r.license))),
        h("span", { class: "muted" }, `ID ${r.serverId} · parti ${ago(r.droppedAt)}`),
        r.banned ? h("span", { class: "badge ban" }, "Déjà banni") : h("span"),
        r.banned ? h("span") : h("button", { class: "btn small danger", onclick: () => openBan({ license: r.license, name: r.name }) }, icon("i-ban"), "Bannir")
    )) : [h("div", { class: "empty" }, icon("i-door"), "Aucune déconnexion depuis le démarrage du serveur.")]));
}

async function fetchSanctions() {
    const v = sanctionsView;
    try {
        const res = await nui("action", { action: "sanctions.list", payload: { status: v.status, type: v.type, search: v.search } });
        if (res && res.ok) {
            v.list = list(res.sanctions);
        } else {
            v.list = [];
            if (res && res.error) toast(res.error, "error");
        }
    } catch (e) {
        return;
    }
    if (view === "sanctions" && sanctionsDom) paintSanctions();
}

// Après une sanction : rafraîchit la page Sanctions et l'historique de la fiche
function afterSanction() {
    if (view === "sanctions") fetchSanctions();
    if (playerHistory) loadPlayerHistory(playerHistory.license);
}

// ---------- Fenêtres : avertir, bannir, révoquer ----------

function reasonField(placeholder, onChange) {
    const textarea = h("textarea", { class: "input textarea", maxlength: "200", placeholder });
    textarea.addEventListener("input", () => onChange(textarea.value.trim()));
    return textarea;
}

function openWarn(info) {
    let reason = "";
    const confirmBtn = h("button", { class: "btn primary", disabled: true }, icon("i-warn"), "Avertir");
    const field = reasonField("Raison affichée au joueur (3 caractères minimum)", (value) => { reason = value; confirmBtn.disabled = reason.length < 3; });

    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await act("sanction.warn", { serverId: info.serverId, reason }, `${info.name} a été averti.`);
            if (res) { close(); afterSanction(); }
        });
        return [
            h("header", null, h("h3", null, `Avertir ${info.name}`), h("p", null, "Le joueur voit une fenêtre en plein écran avec la raison. L'avertissement reste dans son historique.")),
            h("div", { class: "body" }, field),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    field.focus();
}

// target : { serverId, name } (joueur connecté) ou { license, name } (déconnexion récente)
function openBan(target) {
    let reason = "";
    let duration = 24;
    const confirmBtn = h("button", { class: "btn danger", disabled: true }, icon("i-ban"), "Bannir");
    const chips = h("div", { class: "durations" });
    const customValue = h("input", { class: "input", type: "number", min: "1", value: "2" });
    const customUnit = h("select", { class: "input" }, h("option", { value: "24" }, "jours"), h("option", { value: "1" }, "heures"));
    const custom = h("div", { class: "custom-duration" }, customValue, customUnit);

    const hours = () => (duration === "custom" ? Math.round(Number(customValue.value) * Number(customUnit.value)) : duration);
    const valid = () => reason.length >= 3 && (duration === "permanent" || (Number.isInteger(hours()) && hours() >= 1 && hours() <= 8760));
    const update = () => { confirmBtn.disabled = !valid(); };

    const options = [...DURATIONS.map((d) => ({ label: d.label, value: d.hours })), { label: "Personnalisée", value: "custom" }];
    if (can("sanctions.ban_permanent")) options.push({ label: "Définitif", value: "permanent", danger: true });

    function paintChips() {
        chips.replaceChildren(...options.map((o) => {
            const chip = h("button", { class: `${o.danger ? "danger " : ""}${duration === o.value ? "on" : ""}` }, o.label);
            chip.addEventListener("click", () => {
                duration = o.value;
                custom.classList.toggle("on", duration === "custom");
                paintChips();
                update();
            });
            return chip;
        }));
    }
    paintChips();
    customValue.addEventListener("input", update);
    customUnit.addEventListener("change", update);
    const field = reasonField("Raison affichée au joueur banni (3 caractères minimum)", (value) => { reason = value; update(); });

    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const payload = { reason, duration: duration === "permanent" ? "permanent" : hours() };
            if (target.serverId) payload.serverId = target.serverId;
            else payload.license = target.license;
            const res = await act("sanction.ban", payload, null);
            if (!res) return;
            toast(`${target.name} a été banni (référence #${res.id}).`, "ok");
            close();
            afterSanction();
        });
        return [
            h("header", null, h("h3", null, `Bannir ${target.name}`),
                h("p", null, target.serverId
                    ? "Le joueur est expulsé immédiatement et ne pourra plus se connecter, même avec un autre compte sur le même PC."
                    : "Le joueur est déjà parti : il ne pourra plus se reconnecter.")),
            h("div", { class: "body" },
                h("div", { class: "field" }, h("label", null, "Durée"), chips, custom),
                h("div", { class: "field" }, h("label", null, "Raison"), field)
            ),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    field.focus();
}

function openRevoke(s) {
    let reason = "";
    const confirmBtn = h("button", { class: "btn primary", disabled: true }, icon("i-undo"), "Révoquer");
    const field = reasonField("Pourquoi révoquer cette sanction ?", (value) => { reason = value; confirmBtn.disabled = reason.length < 3; });

    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await act("sanction.revoke", { id: s.id, reason }, `Sanction #${s.id} révoquée.`);
            if (res) { close(); afterSanction(); }
        });
        return [
            h("header", null, h("h3", null, `Révoquer la sanction #${s.id}`),
                h("p", null, `${s.type === "ban" ? "Le ban est levé immédiatement." : "L'avertissement est annulé."} Elle reste visible dans l'historique, marquée « révoquée ».`)),
            h("div", { class: "body" }, field),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    field.focus();
}

// ---------- Avertissement reçu par ce joueur (affiché même panel fermé) ----------

function showWarning(w) {
    if (!w || typeof w.reason !== "string") return;
    $("warning-reason").textContent = w.reason;
    $("warning-meta").textContent = `Référence #${w.id} · ${fmtDate(w.date)}`;
    $("warning").classList.add("on");
    $("warning-ack").focus();
}

$("warning-ack").addEventListener("click", () => {
    $("warning").classList.remove("on");
    nui("warningAck");
});
