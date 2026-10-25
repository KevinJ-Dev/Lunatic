// Auto-école : accueil (code puis examens), code de la route en questions, HUD de l'examen pratique.
// Tout est vérifié par le serveur : la page ne fait qu'afficher et transmettre les choix.

const $ = (id) => document.getElementById(id);
const resource = typeof GetParentResourceName === "function" ? GetParentResourceName() : "lunatic_driving";
const post = (name, data) => fetch(`https://${resource}/${name}`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data || {}),
}).then((r) => r.json()).catch(() => null);

function h(tag, attrs, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
        if (value === null || value === undefined || value === false) continue;
        if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
        else if (key === "html") el.innerHTML = value;
        else el.setAttribute(key, value === true ? "" : value);
    }
    el.append(...children.flat().filter((c) => c !== null && c !== undefined && c !== false));
    return el;
}

const svg = (path) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${path}</svg>`;
const ICONS = {
    theory: svg('<path d="M4 5a2 2 0 0 1 2-2h12v16H6a2 2 0 0 0-2 2z"/><path d="M4 21V5"/><path d="M9 8h6M9 12h5"/>'),
    car: svg('<path d="M5 16V11l2-5h10l2 5v5"/><path d="M3 16h18v3H3z"/><circle cx="7.5" cy="13.5" r="1"/><circle cx="16.5" cy="13.5" r="1"/>'),
    bike: svg('<circle cx="5.5" cy="16" r="3.5"/><circle cx="18.5" cy="16" r="3.5"/><path d="M5.5 16l4-7h5l4 7M9.5 9L8 6h3"/>'),
    truck: svg('<path d="M2 6h11v10H2zM13 9h5l3 4v3h-8z"/><circle cx="6" cy="17.5" r="1.8"/><circle cx="17" cy="17.5" r="1.8"/>'),
    boat: svg('<path d="M3 15l2 4h14l2-4z"/><path d="M12 3v12M12 4l6 9H12"/>'),
    plane: svg('<path d="M10.5 3.5c0-.8.7-1.5 1.5-1.5s1.5.7 1.5 1.5V9l8 5v2l-8-2.5V18l2.5 2v1.5L12 20.5l-4 1V20l2.5-2v-4.5L2.5 16v-2l8-5z"/>'),
    heli: svg('<path d="M3 5h18M12 5v4"/><path d="M5 9h10a4 4 0 0 1 4 4v1H9a4 4 0 0 1-4-4z"/><path d="M19 13h3M8 18h10M10 14v4M15 14v4"/>'),
};

const pad = (n) => String(n).padStart(2, "0");
const clock = (seconds) => `${pad(Math.floor(Math.max(0, seconds) / 60))}:${pad(Math.max(0, seconds) % 60)}`;

// ---------- Accueil ----------

let school = null;

function showSchool(data) {
    school = data;
    const cur = data.currency || "$";
    const t = data.theory;

    $("theory").className = `theory${t.owned ? " owned" : ""}`;
    $("theory").replaceChildren(
        h("div", { class: "ico", html: ICONS.theory }),
        h("div", null, h("b", null, "Code de la route"),
            h("p", null, t.owned ? "Obtenu : vous pouvez passer les examens pratiques." : `${t.count} questions · ${t.pass} bonnes réponses requises · ${t.minutes} min`)),
        t.owned ? h("span", { class: "tag", style: "color:var(--ok);font-weight:700" }, "✓ Obtenu")
            : h("button", { class: "btn", onclick: startTheory }, `Passer le code · ${t.price} ${cur}`));

    $("exams").replaceChildren(...data.exams.map((e) => {
        const locked = !e.open || !t.owned;
        const state = e.owned ? "owned" : locked ? "locked" : "";
        const tag = e.owned ? "✓ Permis obtenu" : !e.open ? "Fermé pour le moment" : !t.owned ? "Code requis" : `${e.price} ${cur}`;
        return h("div", { class: `exam ${state}` },
            h("div", { class: "ico", html: ICONS[e.id] || ICONS.car }), h("b", null, e.label), h("span", { class: "tag" }, tag),
            e.owned ? null : h("button", { class: "btn", disabled: locked, onclick: () => post("exam", { id: e.id }) }, "Passer l'examen"));
    }));

    $("rules").replaceChildren(
        h("span", null, `${data.maxErrors} faute${data.maxErrors > 1 ? "s" : ""} maximum à l'examen`),
        h("span", null, "Excès de vitesse et chocs comptent comme fautes"),
        data.majorFail ? h("span", null, "Accident ou faute grave : échec immédiat") : null,
        h("span", null, "Marquez l'arrêt complet aux STOP"));

    $("school").classList.remove("hidden");
}

function closeSchool() {
    $("school").classList.add("hidden");
    post("close");
}

$("close").addEventListener("click", closeSchool);

// ---------- Code de la route ----------

let quiz = null;

async function startTheory() {
    const res = await post("theory");
    if (!res || !res.ok) return;

    $("school").classList.add("hidden");
    quiz = { questions: res.questions, answers: [], index: 0, pass: res.pass, endsAt: Date.now() + res.seconds * 1000 };
    quiz.timer = setInterval(tick, 250);
    $("quiz").classList.remove("hidden");
    paintQuestion();
    tick();
}

function tick() {
    if (!quiz) return;
    const left = Math.ceil((quiz.endsAt - Date.now()) / 1000);
    $("qClock").textContent = clock(left);
    $("qClock").classList.toggle("low", left <= 60);
    if (left <= 0) submitTheory();
}

function paintQuestion() {
    const q = quiz.questions[quiz.index];
    const total = quiz.questions.length;
    $("qCount").textContent = `Question ${quiz.index + 1} / ${total}`;
    $("qBar").style.width = `${(quiz.index / total) * 100}%`;
    $("qText").textContent = q.q;
    $("qNext").textContent = quiz.index === total - 1 ? "Terminer" : "Suivant";
    $("qNext").disabled = !quiz.answers[quiz.index];
    $("qAnswers").replaceChildren(...q.a.map((answer, i) => h("button", {
        class: `answer${quiz.answers[quiz.index] === i + 1 ? " on" : ""}`,
        onclick: () => { quiz.answers[quiz.index] = i + 1; paintQuestion(); },
    }, h("span", null, "ABCD"[i]), answer)));
}

$("qNext").addEventListener("click", () => {
    if (!quiz || !quiz.answers[quiz.index]) return;
    if (quiz.index < quiz.questions.length - 1) {
        quiz.index += 1;
        paintQuestion();
    } else {
        submitTheory();
    }
});

// Abandon en deux clics : les questions sans réponse comptent fausses
$("qQuit").addEventListener("click", () => {
    if (!quiz) return;
    if (quiz.quitting) return submitTheory();
    quiz.quitting = true;
    $("qQuit").textContent = "Confirmer l'abandon";
    setTimeout(() => { if (quiz) { quiz.quitting = false; $("qQuit").textContent = "Abandonner"; } }, 3000);
});

async function submitTheory() {
    if (!quiz || quiz.sending) return;
    quiz.sending = true;
    clearInterval(quiz.timer);
    const questions = quiz.questions;
    const answers = questions.map((_, i) => quiz.answers[i] || 0);
    const res = await post("submitTheory", { answers });
    quiz = null;
    $("quiz").classList.add("hidden");
    showResult(res, questions);
}

function showResult(res, questions) {
    const ok = !!(res && res.ok && res.passed);
    $("rBadge").className = `badge ${ok ? "ok" : "ko"}`;
    $("rBadge").textContent = ok ? "✓" : "✕";

    if (!res || !res.ok) {
        $("rTitle").textContent = "Code non validé";
        $("rText").textContent = (res && res.error) || "Correction impossible.";
        $("rList").replaceChildren();
    } else {
        $("rTitle").textContent = ok ? "Code de la route obtenu !" : "Code de la route raté";
        $("rText").textContent = `${res.score} / ${res.total} bonnes réponses (il en fallait ${res.pass}).`;
        $("rList").replaceChildren(...questions.map((q, i) => {
            const good = res.results && res.results[i];
            return h("div", { class: good ? "ok" : "ko" }, h("i", null, good ? "✓" : "✕"), q.q);
        }));
    }

    $("result").classList.remove("hidden");
}

$("rClose").addEventListener("click", () => {
    $("result").classList.add("hidden");
    post("back");
});

// ---------- Examen pratique ----------

let flashTimer = null;
let bannerTimer = null;

function paintHud(d) {
    $("hud").classList.remove("hidden");
    $("hLabel").textContent = `Examen ${d.label}`;
    $("hClock").textContent = clock(d.left);
    $("hSpeed").textContent = d.speed;
    $("hSpeedBox").classList.toggle("over", d.speed > d.limit);
    $("hLimit").textContent = d.limit;
    $("hPoint").textContent = `${d.index} / ${d.total}`;
    $("hErrors").textContent = `${d.errors} / ${d.maxErrors}`;
    $("hErrors").classList.toggle("warn", d.errors > 0);
    $("hStop").classList.toggle("hidden", !d.stop);
    $("hStop").classList.toggle("done", d.stop === "done");
    $("hStop").querySelector("span").textContent = d.stop === "done" ? "Arrêt marqué, repartez" : "Marquez l'arrêt complet";
}

function flash(text) {
    $("hFlash").textContent = text;
    $("hFlash").classList.remove("hidden");
    clearTimeout(flashTimer);
    flashTimer = setTimeout(() => $("hFlash").classList.add("hidden"), 3500);
}

function banner(d) {
    $("hud").classList.add("hidden");
    $("banner").className = `banner ${d.passed ? "ok" : "ko"}`;
    $("bTitle").textContent = d.passed ? `Examen ${d.label} réussi !` : `Examen ${d.label} échoué`;
    $("bText").textContent = d.passed ? "Le permis est à vous." : d.reason || "Réessayez quand vous serez prêt.";
    clearTimeout(bannerTimer);
    bannerTimer = setTimeout(() => $("banner").classList.add("hidden"), 7000);
}

// ---------- Messages du jeu ----------

window.addEventListener("message", (event) => {
    const msg = event.data || {};
    if (msg.action === "school") showSchool(msg.data);
    else if (msg.action === "hud") paintHud(msg.data);
    else if (msg.action === "fault") flash(msg.text);
    else if (msg.action === "hudHide") $("hud").classList.add("hidden");
    else if (msg.action === "examEnded") banner(msg.data);
});

window.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    if (!$("school").classList.contains("hidden")) closeSchool();
    else if (!$("result").classList.contains("hidden")) $("rClose").click();
});
