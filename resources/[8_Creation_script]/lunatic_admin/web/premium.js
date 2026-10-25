"use strict";

// ====================================================================
//  lunatic_admin — lot G : carte « VIP et boutique » des fiches joueur (en ligne et hors ligne)
//  La carte est construite une fois par joueur et mise à jour sans perdre la saisie en cours.
// ====================================================================

const PREMIUM_TIERS = [
    { value: "premium", label: "VIP" },
    { value: "premium_plus", label: "VIP+" },
];
const PREMIUM_DURATIONS = [
    { value: 7, label: "7 jours" },
    { value: 30, label: "30 jours" },
    { value: 90, label: "90 jours" },
    { value: 365, label: "1 an" },
    { value: "lifetime", label: "À vie" },
];

let premiumPanel = null; // { key, node, refresh(info) }

// target : { serverId } (en ligne) ou { identifier } (hors ligne) ; reload : recharge la fiche
function premiumCard(info, target, reload) {
    if (!can("premium.manage") && !can("shop.manage")) return null;
    if (info.protected) return null;

    const key = target.serverId ? `s:${target.serverId}` : `i:${target.identifier}`;
    if (!premiumPanel || premiumPanel.key !== key) premiumPanel = buildPremium(info, target, reload, key);
    premiumPanel.refresh(info);
    return premiumPanel.node;
}

function buildPremium(info, target, reload, key) {
    const columns = [];
    const refreshers = [];

    // ---------- Abonnement ----------
    if (can("premium.manage")) {
        let tier = "premium";
        let days = 30;
        const current = h("div", { class: "premium-current" });
        const tierSeg = h("div", { class: "segmented" });
        const chips = h("div", { class: "durations" });
        const removeBtn = h("button", { class: "btn small danger" }, icon("i-trash"), "Retirer l'abonnement");

        const paint = () => {
            tierSeg.replaceChildren(...segmentedButtons(PREMIUM_TIERS, tier, (v) => { tier = v; paint(); }));
            chips.replaceChildren(...PREMIUM_DURATIONS.map((d) => {
                const chip = h("button", { class: days === d.value ? "on" : "" }, d.label);
                chip.addEventListener("click", () => { days = d.value; paint(); });
                return chip;
            }));
        };
        paint();

        const grant = h("button", { class: "btn primary" }, icon("i-crown"), "Attribuer");
        grant.addEventListener("click", async () => {
            const res = await act("premium.set", { ...target, tier, days }, "Abonnement attribué.");
            if (res) reload();
        });
        removeBtn.addEventListener("click", async () => {
            const yes = await confirmBox("Retirer l'abonnement ?", `${info.name} perd immédiatement ses avantages.`, "Retirer", true);
            if (!yes) return;
            const res = await act("premium.remove", { ...target }, "Abonnement retiré.");
            if (res) reload();
        });

        refreshers.push((next) => {
            const premium = next.premium;
            if (premium) {
                const badge = h("span", { class: "rank-pill" }, dot(premium.color), premium.label);
                current.replaceChildren(badge, h("span", { class: "muted" }, premium.expires ? ` jusqu'au ${fmtDate(premium.expires)}` : " à vie"));
                removeBtn.style.display = "";
            } else {
                current.replaceChildren(h("span", { class: "muted" }, "Aucun abonnement"));
                removeBtn.style.display = "none";
            }
        });

        columns.push(h("div", { class: "premium-col" },
            h("h3", { class: "card-title" }, "Abonnement"),
            current,
            h("div", { class: "eco-line" }, tierSeg),
            chips,
            h("p", { class: "hint-line" }, "Même abonnement encore actif : la durée s'ajoute au temps restant."),
            h("div", { class: "btn-row" }, grant, removeBtn)
        ));
    }

    // ---------- Crédits boutique ----------
    if (can("shop.manage")) {
        let operation = "add";
        const balance = h("b", { class: "credits-balance mono" });
        const operationSeg = h("div", { class: "segmented" });
        const amount = h("input", { class: "input mono", type: "number", min: "1", placeholder: "Montant" });
        const reason = h("input", { class: "input", maxlength: "200", placeholder: "Raison (obligatoire)" });
        const history = h("div", { class: "credit-history" }, h("span", { class: "muted" }, "Chargement…"));
        const paintSeg = () => operationSeg.replaceChildren(...segmentedButtons([{ value: "add", label: "Donner" }, { value: "remove", label: "Retirer" }], operation, (v) => { operation = v; paintSeg(); }));
        paintSeg();

        const loadHistory = async () => {
            const res = await nui("action", { action: "credits.history", payload: { license: info.license } });
            const rows = res && res.ok && Array.isArray(res.history) ? res.history : [];
            history.replaceChildren(...(rows.length ? rows.map((r) => h("div", { class: "credit-row" },
                h("span", { class: `mono ${r.amount > 0 ? "plus" : "minus"}` }, `${r.amount > 0 ? "+" : ""}${r.amount}`),
                h("span", { class: "reason" }, r.reason),
                h("span", { class: "muted" }, `${r.staff} · ${fmtDate(r.created)}`)
            )) : [h("span", { class: "muted" }, "Aucun mouvement.")]));
        };

        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Valider");
        submit.addEventListener("click", async () => {
            const value = Number(amount.value);
            if (!Number.isInteger(value) || value < 1) return toast("Montant invalide.", "error");
            if (reason.value.trim().length < 3) return toast("La raison doit faire au moins 3 caractères.", "error");
            const res = await act("credits.change", { ...target, amount: operation === "add" ? value : -value, reason: reason.value.trim() }, null);
            if (!res) return;
            toast(`Crédits : ${res.before} → ${res.after}.`, "ok");
            amount.value = "";
            reason.value = "";
            loadHistory();
            reload();
        });

        refreshers.push((next) => { balance.textContent = `${next.credits ?? 0} crédits`; });
        loadHistory();

        columns.push(h("div", { class: "premium-col" },
            h("h3", { class: "card-title" }, "Crédits boutique"),
            balance,
            h("div", { class: "eco-line" }, operationSeg),
            h("div", { class: "eco-form" }, amount, reason, submit),
            history
        ));
    }

    return {
        key,
        node: h("div", { class: "card premium-card" }, h("div", { class: "premium-grid" }, columns)),
        refresh: (next) => refreshers.forEach((fn) => fn(next)),
    };
}
