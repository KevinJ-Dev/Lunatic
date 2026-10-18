"use strict";

// ====================================================================
//  lunatic_admin — lot H : page Serveur (Gestion Global)
//  Redémarrage planifié, maintenance, actions de masse.
// ====================================================================

let globalDom = null;
let restartEndsAt = 0; // horodatage local de fin, recalculé depuis le temps restant envoyé par le serveur
let restartTicker = null;
let restartMinutes = 15;

// Action qui modifie l'état de la page : on redessine avec l'état renvoyé par le serveur
async function serverAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res && view === "server") render();
    return res;
}

function renderGlobal() {
    const root = $("view-server");
    const server = state.server || {};

    if (!globalDom || !root.contains(globalDom.restartBody)) {
        const reason = h("input", { class: "input", maxlength: "100", placeholder: "Raison affichée (facultative), ex. mise à jour" });
        const message = h("textarea", { class: "input textarea", maxlength: "200" });
        message.value = server.maintenanceMessage || "";

        globalDom = {
            restartBody: h("div", { class: "restart-body" }),
            maintenanceRow: h("div", { class: "mode-list" }),
            maintenanceBanner: h("div"),
            reason,
            message,
        };

        root.replaceChildren(h("div", { class: "content" },
            h("div", { class: "page-head" }, h("div", { class: "grow" },
                h("h1", { class: "page-title" }, "Serveur"),
                h("div", { class: "page-sub" }, "Gestion globale : redémarrage, maintenance et actions sur tous les joueurs")
            )),
            h("div", { class: "scroll" }, h("div", { class: "world-grid" },
                h("div", { class: "tools-col" },
                    h("div", { class: "card" }, h("h3", { class: "card-title" }, "Redémarrage planifié"), globalDom.restartBody),
                    h("div", { class: "card" },
                        h("h3", { class: "card-title" }, "Actions de masse"),
                        h("div", { class: "btn-row" },
                            h("button", { class: "btn", onclick: healAll }, icon("i-heart"), "Soigner tout le serveur"),
                            h("button", { class: "btn", onclick: bringAll }, icon("i-bring"), "Téléporter tout le monde à moi"),
                            h("button", { class: "btn danger", onclick: openKickAll }, icon("i-door"), "Expulser tout le monde")
                        ),
                        h("p", { class: "hint-line" }, "« Expulser tout le monde » garde les membres du staff connectés.")
                    )
                ),
                h("div", { class: "card" },
                    h("h3", { class: "card-title" }, "Mode maintenance"),
                    globalDom.maintenanceBanner,
                    globalDom.maintenanceRow,
                    h("div", { class: "field", style: "margin-top:12px" }, h("label", null, "Message affiché aux joueurs refusés"), message),
                    h("div", { class: "btn-row", style: "margin-top:10px" },
                        h("button", { class: "btn", onclick: () => serverAct("server.maintenance", { enabled: !!(state.server || {}).maintenance, message: message.value.trim() }, "Message de maintenance enregistré.") }, icon("i-save"), "Enregistrer le message"))
                )
            ))
        ));
    }

    paintGlobal(server);
}

function paintGlobal(server) {
    // Maintenance
    globalDom.maintenanceBanner.replaceChildren(server.maintenance
        ? h("div", { class: "banner" }, icon("i-lock"), "Maintenance active : seuls les membres du staff peuvent se connecter.")
        : h("span"));
    const row = h("div", { class: `perm${server.maintenance ? " on" : ""}` },
        h("span", { class: "switch" }),
        h("span", { class: "txt" }, h("span", null, "Maintenance"), h("code", null, "Les joueurs hors staff voient le message ci-dessous et ne peuvent pas entrer.")));
    row.addEventListener("click", () => serverAct("server.maintenance", { enabled: !server.maintenance }, server.maintenance ? "Maintenance désactivée." : "Maintenance activée."));
    globalDom.maintenanceRow.replaceChildren(row);

    // Redémarrage
    clearInterval(restartTicker);
    if (server.restart) {
        restartEndsAt = Date.now() + Math.max(0, server.restart.remaining || 0) * 1000;
        const clock = h("div", { class: "world-clock mono" });
        const tick = () => {
            const left = Math.max(0, Math.round((restartEndsAt - Date.now()) / 1000));
            clock.textContent = `${String(Math.floor(left / 60)).padStart(2, "0")}:${String(left % 60).padStart(2, "0")}`;
        };
        tick();
        restartTicker = setInterval(tick, 1000);
        globalDom.restartBody.replaceChildren(
            h("div", { class: "world-time" }, clock, h("div", { class: "muted" }, `Programmé par ${server.restart.by}${server.restart.reason ? ` · ${server.restart.reason}` : ""}`)),
            h("p", { class: "hint-line" }, "Annonces automatiques jusqu'à la fin, puis tous les joueurs sont expulsés (sauvegarde ESX à la déconnexion). Relancez ensuite le serveur depuis le panel de votre hébergeur."),
            h("button", { class: "btn danger", onclick: async () => {
                const yes = await confirmBox("Annuler le redémarrage ?", "Une annonce prévient les joueurs de l'annulation.", "Annuler le redémarrage", true);
                if (yes) serverAct("server.cancelRestart", {}, "Redémarrage annulé.");
            } }, icon("i-x"), "Annuler le redémarrage")
        );
        return;
    }

    const chips = h("div", { class: "durations" });
    const paintChips = () => chips.replaceChildren(...[1, 5, 10, 15, 30].map((m) => {
        const chip = h("button", { class: restartMinutes === m ? "on" : "" }, `${m} min`);
        chip.addEventListener("click", () => { restartMinutes = m; paintChips(); });
        return chip;
    }));
    paintChips();
    globalDom.restartBody.replaceChildren(
        h("div", { class: "field" }, h("label", null, "Délai avant l'expulsion"), chips),
        h("div", { class: "field", style: "margin-top:10px" }, h("label", null, "Raison"), globalDom.reason),
        h("p", { class: "hint-line" }, `${server.players ?? 0} joueur(s) connecté(s). Annonces à 15, 10, 5, 2 et 1 min, puis 30 et 10 s.`),
        h("button", { class: "btn primary", onclick: async () => {
            const yes = await confirmBox(`Redémarrer dans ${restartMinutes} min ?`, "Tous les joueurs seront prévenus puis expulsés à la fin du compte à rebours.", "Programmer", false);
            if (yes) serverAct("server.restart", { minutes: restartMinutes, reason: globalDom.reason.value.trim() }, "Redémarrage programmé.");
        } }, icon("i-undo"), "Programmer le redémarrage")
    );
}

async function healAll() {
    const yes = await confirmBox("Soigner tout le serveur ?", "Tous les joueurs sont relevés, soignés et nourris.", "Soigner tout le monde", false);
    if (!yes) return;
    const res = await act("server.healAll", {}, null);
    if (res) toast(`${res.count || 0} joueur(s) soigné(s).`, "ok");
}

async function bringAll() {
    const yes = await confirmBox("Téléporter tout le monde à vous ?", "Tous les joueurs connectés sont amenés autour de votre position.", "Téléporter", true);
    if (!yes) return;
    const res = await act("server.bringAll", {}, null);
    if (res) toast(`${res.count || 0} joueur(s) téléporté(s).`, "ok");
}

function openKickAll() {
    let reason = "";
    const confirmBtn = h("button", { class: "btn danger", disabled: true }, icon("i-door"), "Expulser tout le monde");
    const field = reasonField("Raison affichée aux joueurs (3 caractères minimum)", (value) => { reason = value; confirmBtn.disabled = reason.length < 3; });
    openModal((close) => {
        confirmBtn.addEventListener("click", async () => {
            const res = await serverAct("server.kickAll", { reason }, null);
            if (!res) return;
            toast(`${res.count || 0} joueur(s) expulsé(s).`, "ok");
            close();
        });
        return [
            h("header", null, h("h3", null, "Expulser tout le monde ?"), h("p", null, "Tous les joueurs hors staff sont déconnectés avec la raison indiquée.")),
            h("div", { class: "body" }, field),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), confirmBtn),
        ];
    });
    field.focus();
}
