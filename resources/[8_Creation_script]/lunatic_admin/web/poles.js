"use strict";

// ====================================================================
//  lunatic_admin — lot I : page Pôles (métiers ESX)
//  Liste des métiers, grades et salaires, membres, création et suppression.
// ====================================================================

let polesDom = null;
let polesList = null;
let polesLoadedAt = 0;
let poleFilter = "";
let selectedPole = null; // nom du métier, "__new" pour le formulaire de création
let poleInfo = null;

const NEW_POLE = "__new";

// Nom technique proposé à partir du nom affiché (« Agent immobilier » -> « agent_immobilier »)
function poleSlug(text) {
    return text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
        .replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").replace(/^[0-9_]+/, "").slice(0, 30);
}

function renderPoles() {
    const root = $("view-poles");

    // Structure gardée : un rafraîchissement de l'état ne doit pas effacer les saisies en cours
    if (!polesDom || !root.contains(polesDom.list)) {
        const search = h("input", { placeholder: "Rechercher un métier", value: poleFilter });
        search.addEventListener("input", () => { poleFilter = search.value; paintPolesList(); });
        polesDom = {
            count: h("span", { class: "muted mono" }),
            list: h("div", { class: "side-scroll" }),
            fiche: h("div", { class: "content" }),
        };
        root.replaceChildren(
            h("aside", { class: "sidebar" },
                h("div", { class: "side-head" }, h("h3", null, "Métiers"), polesDom.count),
                h("div", { class: "side-search" }, h("label", { class: "search" }, icon("i-search"), search)),
                polesDom.list,
                h("div", { class: "side-foot" }, h("button", { class: "btn primary", style: "width:100%", onclick: () => selectPole(NEW_POLE) }, icon("i-plus"), "Créer un métier"))
            ),
            polesDom.fiche
        );
        paintPolesList();
        paintPoleFiche();
    }

    if (Date.now() - polesLoadedAt > 10000) loadPoles();
}

async function loadPoles() {
    polesLoadedAt = Date.now();
    const res = await nui("action", { action: "poles.list", payload: {} }).catch(() => null);
    if (!res || !res.ok) return;
    polesList = res.jobs || [];
    if (polesDom) paintPolesList();
}

function paintPolesList() {
    if (!polesList) {
        polesDom.list.replaceChildren(h("div", { class: "muted side-empty" }, "Chargement…"));
        return;
    }
    const text = poleFilter.trim().toLowerCase();
    const rows = polesList.filter((j) => !text || (j.label || "").toLowerCase().includes(text) || j.name.includes(text));
    polesDom.count.textContent = String(polesList.length);
    polesDom.list.replaceChildren(...(rows.length ? rows.map((j) =>
        h("button", { class: `list-row player-row${j.name === selectedPole ? " active" : ""}`, onclick: () => selectPole(j.name) },
            h("span", { class: "who" },
                h("b", null, j.label || j.name),
                h("span", null, `${j.online} en ligne · ${j.total} membre${j.total > 1 ? "s" : ""} · ${j.grades} grade${j.grades > 1 ? "s" : ""}`)),
            j.whitelisted ? icon("i-lock") : null)
    ) : [h("div", { class: "muted side-empty" }, "Aucun métier ne correspond.")]));
}

function selectPole(name) {
    selectedPole = name;
    poleInfo = null;
    paintPolesList();
    paintPoleFiche();
    if (name !== NEW_POLE) loadPoleInfo();
}

async function loadPoleInfo() {
    const name = selectedPole;
    if (!name || name === NEW_POLE) return;
    const res = await nui("action", { action: "poles.info", payload: { job: name } }).catch(() => null);
    if (name !== selectedPole) return;
    poleInfo = res && res.ok ? res.job : false;
    paintPoleFiche();
}

// Action sur un métier : recharge la fiche et la liste après succès
async function poleAct(action, payload, okMessage) {
    const res = await act(action, payload, okMessage);
    if (res) {
        loadPoles();
        loadPoleInfo();
    }
    return res;
}

function paintPoleFiche() {
    const fiche = polesDom.fiche;

    if (selectedPole === NEW_POLE) return fiche.replaceChildren(...newPoleForm());
    if (!selectedPole) {
        return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-briefcase"), "Choisissez un métier ou créez-en un nouveau."));
    }
    if (poleInfo === false) {
        return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-briefcase"), "Ce métier n'existe plus."));
    }
    if (!poleInfo) {
        return fiche.replaceChildren(h("div", { class: "empty" }, icon("i-briefcase"), "Chargement du métier…"));
    }

    const job = poleInfo;
    const previous = fiche.querySelector(".scroll");
    const keepScroll = previous && fiche.dataset.pole === job.name ? previous.scrollTop : 0;
    fiche.dataset.pole = job.name;

    const total = job.grades.reduce((sum, g) => sum + g.members, 0);
    const online = job.members.filter((m) => m.online).length;
    const deleteBlocked = job.protected ? "Indispensable à ESX" : total > 0 ? "Renvoyez d'abord tous les membres" : null;

    fiche.replaceChildren(
        h("div", { class: "page-head" },
            h("div", { class: "grow" },
                h("h1", { class: "page-title" }, job.label || job.name, job.whitelisted ? h("span", { class: "badge muted" }, icon("i-lock"), "Liste blanche") : null),
                h("div", { class: "page-sub" }, h("span", { class: "mono" }, job.name),
                    job.membersHidden ? null : [h("span", { class: "sep" }), `${total} membre${total > 1 ? "s" : ""}`, h("span", { class: "sep" }), `${online} en ligne`])
            ),
            h("div", { class: "btn-row" },
                h("button", { class: "btn ghost", onclick: () => openRenamePole(job) }, icon("i-edit"), "Renommer"),
                h("button", { class: "btn danger", disabled: !!deleteBlocked, title: deleteBlocked, onclick: () => deletePole(job) }, icon("i-trash"), "Supprimer")
            )
        ),
        h("div", { class: "scroll" },
            whitelistCard(job),
            gradesCard(job),
            membersCard(job)
        )
    );

    const scroller = fiche.querySelector(".scroll");
    if (scroller) scroller.scrollTop = keepScroll;
}

function whitelistCard(job) {
    const row = h("div", { class: `perm${job.whitelisted ? " on" : ""}` },
        h("span", { class: "switch" }),
        h("span", { class: "txt" }, h("span", null, "Liste blanche"),
            h("code", null, "Le métier n'est pas proposé au pôle emploi : recrutement par le patron ou le staff uniquement.")));
    row.addEventListener("click", () => poleAct("poles.whitelist", { job: job.name, enabled: !job.whitelisted }, job.whitelisted ? "Liste blanche retirée." : "Métier passé en liste blanche."));
    return h("div", { class: "card" }, h("div", { class: "mode-list" }, row));
}

// doAct : action qui recharge la page appelante (Pôle emploi par défaut, fiche d'une structure sinon)
function gradesCard(job, doAct = poleAct) {
    const top = job.grades[job.grades.length - 1];
    const rows = job.grades.map((g) => {
        const label = h("input", { class: "input", maxlength: "50", value: g.label });
        const salary = h("input", { class: "input mono", type: "number", min: "0", value: String(g.salary) });
        const save = h("button", { class: "btn small", disabled: true }, icon("i-save"), "Enregistrer");
        const dirty = () => { save.disabled = label.value.trim() === g.label && Number(salary.value) === g.salary; };
        label.addEventListener("input", dirty);
        salary.addEventListener("input", dirty);
        save.addEventListener("click", () => doAct("poles.setGrade", { job: job.name, grade: g.grade, label: label.value.trim(), salary: Number(salary.value) }, `Grade « ${label.value.trim()} » enregistré.`));
        return h("div", { class: "row grade-row" },
            h("span", { class: "pid mono" }, String(g.grade)),
            label,
            h("label", { class: "salary" }, salary, h("span", { class: "muted" }, "$")),
            h("span", { class: "muted" }, job.membersHidden ? (g === top && !job.protected ? "Patron" : "") : `${g.members} membre${g.members > 1 ? "s" : ""}${g === top && !job.protected ? " · Patron" : ""}`),
            save
        );
    });

    let footer = null;
    if (!job.protected) {
        const label = h("input", { class: "input", maxlength: "50", placeholder: "Nouveau grade (au-dessus des autres)" });
        const salary = h("input", { class: "input mono", type: "number", min: "0", placeholder: "Salaire" });
        const removeBlocked = job.grades.length <= 1 ? "Un métier garde au moins un grade" : top.members > 0 ? "Ce grade a encore des membres" : null;
        footer = h("div", { class: "grade-add" },
            label, salary,
            h("button", { class: "btn", onclick: () => {
                if (!label.value.trim()) return toast("Indiquez le nom du grade.", "error");
                doAct("poles.addGrade", { job: job.name, label: label.value.trim(), salary: Number(salary.value || 0) }, `Grade « ${label.value.trim()} » ajouté.`);
            } }, icon("i-plus"), "Ajouter"),
            h("button", { class: "btn ghost", disabled: !!removeBlocked, title: removeBlocked, onclick: async () => {
                const yes = await confirmBox(`Supprimer le grade « ${top.label} » ?`, "Le grade juste en dessous devient le grade de patron.", "Supprimer", true);
                if (yes) doAct("poles.removeGrade", { job: job.name }, "Grade supprimé.");
            } }, icon("i-trash"), "Retirer le plus haut")
        );
    }

    return h("div", { class: "card", style: "margin-top:16px" },
        h("h3", { class: "card-title" }, `Grades et salaires (${job.grades.length})`),
        h("p", { class: "hint-line", style: "margin:0 0 12px" }, "Salaire versé à chaque paie ESX. Un changement s'applique tout de suite aux membres connectés."),
        h("div", { class: "table" }, rows),
        footer
    );
}

// Temps de jeu (minutes) -> « 12 h 05 »
function playtimeText(minutes) {
    if (!minutes) return "0 min";
    return minutes < 60 ? `${minutes} min` : `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, "0")}`;
}

function membersCard(job, doAct = poleAct, emptyText = "Aucun membre. Pour recruter, changez le métier d'un joueur depuis sa fiche (Joueurs).") {
    if (job.membersHidden) {
        return h("div", { class: "card", style: "margin-top:16px" }, h("h3", { class: "card-title" }, "Membres"),
            h("p", { class: "hint-line", style: "margin:0" }, "Les joueurs sans emploi ne sont pas listés."));
    }

    const rows = job.members.map((m) => {
        const select = h("select", { class: "input", disabled: m.protected, title: m.protected ? "Rang égal ou supérieur au vôtre" : null },
            [...job.grades].reverse().map((g) => h("option", { value: String(g.grade), selected: g.grade === m.grade }, g.label)));
        select.addEventListener("change", async () => {
            const grade = Number(select.value);
            const res = await doAct("poles.setMember", { job: job.name, identifier: m.identifier, grade }, `${m.name} : ${job.grades.find((g) => g.grade === grade)?.label || "grade modifié"}.`);
            if (!res) select.value = String(m.grade);
        });
        return h("div", { class: "row member-job-row" },
            h("span", { class: `status${m.online ? " on" : ""}`, title: m.online ? "En ligne" : "Hors ligne" }),
            h("div", { class: "who" }, h("b", null, m.name), h("span", null, [
                m.online ? `ID ${m.online}` : "Hors ligne",
                `perso ${m.identifier.slice(0, 8)}…`,
                m.playtime !== undefined ? `${playtimeText(m.playtime)} de service` : null,
            ].filter(Boolean).join(" · "))),
            select,
            h("button", { class: "btn small ghost", disabled: m.protected, title: m.protected ? "Rang égal ou supérieur au vôtre" : "Renvoyer (sans emploi)", onclick: async () => {
                const yes = await confirmBox(`Renvoyer ${m.name} ?`, `Il quitte le poste ${job.label} et devient sans emploi.`, "Renvoyer", true);
                if (yes) doAct("poles.fire", { job: job.name, identifier: m.identifier }, `${m.name} a été renvoyé.`);
            } }, icon("i-door"), "Renvoyer")
        );
    });

    return h("div", { class: "card", style: "margin-top:16px" },
        h("h3", { class: "card-title" }, `Membres (${job.members.length})`),
        rows.length ? h("div", { class: "table" }, rows) : h("p", { class: "hint-line", style: "margin:0" }, emptyText));
}

function openRenamePole(job) {
    const input = h("input", { class: "input", maxlength: "50", value: job.label || "" });
    openModal((close) => {
        const submit = h("button", { class: "btn primary" }, icon("i-save"), "Renommer");
        submit.addEventListener("click", async () => {
            const res = await poleAct("poles.rename", { job: job.name, label: input.value.trim() }, "Métier renommé.");
            if (res) close();
        });
        return [
            h("header", null, h("h3", null, "Renommer le métier"), h("p", null, `Nom affiché aux joueurs. Le nom technique « ${job.name} » ne change pas.`)),
            h("div", { class: "body" }, h("div", { class: "field" }, h("label", null, "Nom affiché"), input)),
            h("footer", null, h("button", { class: "btn ghost", onclick: () => close() }, "Annuler"), submit),
        ];
    });
    input.focus();
}

async function deletePole(job) {
    const yes = await confirmBox(`Supprimer le métier « ${job.label} » ?`, "Le métier et tous ses grades sont effacés de la base. Action définitive.", "Supprimer", true);
    if (!yes) return;
    const res = await act("poles.delete", { job: job.name }, "Métier supprimé.");
    if (!res) return;
    selectedPole = null;
    poleInfo = null;
    loadPoles();
    paintPoleFiche();
}

// ---------- Création d'un métier ----------

function newPoleForm() {
    const label = h("input", { class: "input", maxlength: "50", placeholder: "Ex. Agent immobilier" });
    const name = h("input", { class: "input mono", maxlength: "30", placeholder: "agent_immobilier" });
    let nameTouched = false;
    let whitelisted = true;
    label.addEventListener("input", () => { if (!nameTouched) name.value = poleSlug(label.value); });
    name.addEventListener("input", () => { nameTouched = true; });

    const grades = [{ label: "Recrue", salary: 200 }, { label: "Employé", salary: 300 }, { label: "Patron", salary: 500 }];
    const gradeList = h("div", { class: "table" });
    const paintGrades = () => gradeList.replaceChildren(...grades.map((g, index) => {
        const gLabel = h("input", { class: "input", maxlength: "50", value: g.label });
        const gSalary = h("input", { class: "input mono", type: "number", min: "0", value: String(g.salary) });
        gLabel.addEventListener("input", () => { g.label = gLabel.value; });
        gSalary.addEventListener("input", () => { g.salary = Number(gSalary.value || 0); });
        return h("div", { class: "row grade-row" },
            h("span", { class: "pid mono" }, String(index)),
            gLabel,
            h("label", { class: "salary" }, gSalary, h("span", { class: "muted" }, "$")),
            h("span", { class: "muted" }, index === grades.length - 1 ? "Patron" : index === 0 ? "Embauche" : ""),
            h("button", { class: "btn small ghost", disabled: grades.length <= 1, title: "Retirer ce grade", onclick: () => { grades.splice(index, 1); paintGrades(); } }, icon("i-trash"))
        );
    }));
    paintGrades();

    const whitelistRow = h("div", { class: "perm on" },
        h("span", { class: "switch" }),
        h("span", { class: "txt" }, h("span", null, "Liste blanche"), h("code", null, "Pas proposé au pôle emploi : recrutement par le patron ou le staff.")));
    whitelistRow.addEventListener("click", () => { whitelisted = !whitelisted; whitelistRow.classList.toggle("on", whitelisted); });

    const submit = h("button", { class: "btn primary" }, icon("i-plus"), "Créer le métier");
    submit.addEventListener("click", async () => {
        const res = await act("poles.create", {
            name: name.value.trim(), label: label.value.trim(), whitelisted,
            grades: grades.map((g) => ({ label: g.label.trim(), salary: g.salary })),
        }, `Métier « ${label.value.trim()} » créé.`);
        if (!res) return;
        await loadPoles();
        selectPole(res.name);
    });

    return [
        h("div", { class: "page-head" }, h("div", { class: "grow" },
            h("h1", { class: "page-title" }, "Nouveau métier"),
            h("div", { class: "page-sub" }, "Disponible tout de suite, sans redémarrage"))),
        h("div", { class: "scroll" },
            h("div", { class: "card" },
                h("div", { class: "fields pole-fields" },
                    h("div", { class: "field" }, h("label", null, "Nom affiché"), label),
                    h("div", { class: "field" }, h("label", null, "Nom technique (minuscules, chiffres, _)"), name)),
                h("div", { class: "mode-list", style: "margin-top:12px" }, whitelistRow)),
            h("div", { class: "card", style: "margin-top:16px" },
                h("h3", { class: "card-title" }, "Grades, du plus bas au plus haut"),
                h("p", { class: "hint-line", style: "margin:0 0 12px" }, "Le premier grade est celui de l'embauche, le dernier celui du patron."),
                gradeList,
                h("div", { class: "btn-row", style: "margin-top:12px" },
                    h("button", { class: "btn ghost", onclick: () => {
                        if (grades.length >= 20) return toast("20 grades maximum.", "error");
                        grades.push({ label: "", salary: 0 });
                        paintGrades();
                    } }, icon("i-plus"), "Ajouter un grade"),
                    submit))
        ),
    ];
}
