"use strict";

// ====================================================================
//  lunatic_admin — carte « Personnages » des fiches joueur (en ligne et hors ligne)
//  Personnages du compte (lunatic_characters) : emplacements en plus, archivage et récupération.
//  La carte est construite une fois par compte et se recharge seule après chaque action.
// ====================================================================

let charactersPanel = null; // { key, node }

// target : { serverId } (en ligne) ou { license } (hors ligne)
function charactersCard(info, target) {
    if (!can("players.view") || !info.license) return null;
    const key = info.license;
    if (!charactersPanel || charactersPanel.key !== key) charactersPanel = buildCharacters(info, { ...target, license: info.license }, key);
    return charactersPanel.node;
}

function buildCharacters(info, target, key) {
    const body = h("div", { class: "chars-body" }, h("span", { class: "muted" }, "Chargement…"));
    const manage = can("players.characters") && !info.protected;

    const load = async () => {
        const res = await nui("action", { action: "characters.get", payload: target }).catch(() => null);
        if (!res || !res.ok) return body.replaceChildren(h("span", { class: "muted" }, (res && res.error) || "Personnages indisponibles."));
        paint(res);
    };

    const archive = async (character) => {
        const reason = await reasonBox(`Archiver ${character.name || "ce personnage"} ?`, "Il disparaît de la sélection du joueur ; toutes ses données sont gardées et il peut être récupéré ici.");
        if (!reason) return;
        const res = await act("characters.archive", { ...target, identifier: character.identifier, reason }, "Personnage archivé.");
        if (res) load();
    };

    const paint = (data) => {
        const used = new Set(data.characters.map((c) => c.slot));
        const free = Array.from({ length: data.max }, (_, i) => i + 1).filter((slot) => !used.has(slot));

        const rows = data.characters.map((c) => h("div", { class: "char-row" },
            h("span", { class: "char-slot mono" }, String(c.slot)),
            h("div", { class: "char-text" }, h("b", null, c.name || "Sans identité"),
                h("span", { class: "muted" }, `${c.job || "—"} · ${c.online ? "en jeu" : `vu le ${fmtDate(c.lastSeen)}`}`)),
            manage ? h("button", { class: "btn small ghost sq-btn", disabled: c.online, title: c.online ? "Personnage en jeu : impossible de l'archiver" : "Archiver ce personnage", onclick: () => archive(c) }, icon("i-trash")) : null));

        const archived = data.archived.map((c) => {
            const select = h("select", { class: "input" }, free.map((slot) => h("option", { value: String(slot) }, `Emplacement ${slot}`)));
            return h("div", { class: "char-row archived" },
                h("span", { class: "char-slot mono" }, "—"),
                h("div", { class: "char-text" }, h("b", null, c.name || "Sans identité"), h("span", { class: "muted" }, `${c.job || "—"} · archivé le ${fmtDate(c.archivedAt)}`)),
                manage && free.length ? h("div", { class: "btn-row" }, select, h("button", { class: "btn small primary", onclick: async () => {
                    const res = await act("characters.restore", { ...target, identifier: c.identifier, slot: Number(select.value) }, "Personnage récupéré.");
                    if (res) load();
                } }, icon("i-undo"), "Récupérer")) : null);
        });

        const extra = h("input", { class: "input mono", type: "number", min: "0", max: String(data.max), value: String(data.extra || 0) });
        const slots = manage ? h("div", { class: "eco-form chars-slots" },
            h("span", null, "Emplacements en plus (en plus de l'abonnement)"), extra,
            h("button", { class: "btn small primary", onclick: async () => {
                const res = await act("characters.slots", { ...target, extra: Number(extra.value) }, "Emplacements enregistrés.");
                if (res) load();
            } }, icon("i-save"), "Enregistrer")) : null;

        body.replaceChildren(...[
            rows.length ? h("div", { class: "char-list" }, rows) : h("span", { class: "muted" }, "Aucun personnage."),
            archived.length ? [h("div", { class: "crew-sub" }, "Personnages archivés"), h("div", { class: "char-list" }, archived)] : null,
            slots,
        ].flat().filter(Boolean));
    };

    load();
    return { key, node: h("div", { class: "card chars-card" }, h("h3", { class: "card-title" }, "Personnages"), body) };
}

// Raison obligatoire avant une action irréversible pour le joueur ; renvoie le texte ou null
function reasonBox(title, text) {
    return new Promise((resolve) => {
        const input = h("input", { class: "input", maxlength: "200", placeholder: "Raison (obligatoire)" });
        openModal((close) => [
            h("header", null, h("h3", null, title), h("p", null, text)),
            h("div", { style: "padding:0 22px" }, input),
            h("footer", null,
                h("button", { class: "btn ghost", onclick: () => close(false) }, "Annuler"),
                h("button", { class: "btn danger", onclick: () => {
                    if (input.value.trim().length < 3) return toast("La raison doit faire au moins 3 caractères.", "error");
                    close(true);
                } }, "Archiver")),
        ]);
        // Fermeture (bouton, clic à côté) : la raison si validée, sinon null
        modalResolve = (validated) => resolve(validated ? input.value.trim() : null);
        setTimeout(() => input.focus(), 50);
    });
}
