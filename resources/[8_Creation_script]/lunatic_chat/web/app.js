"use strict";

// ====================================================================
//  lunatic_chat — interface du tchat
//  Le texte est toujours inséré avec textContent : aucun HTML venant d'un joueur n'est interprété.
// ====================================================================

const IN_GAME = typeof GetParentResourceName === "function";
const RESOURCE = IN_GAME ? GetParentResourceName() : "lunatic_chat";
const MAX_MESSAGES = 100;
const FADE_AFTER = 10000;
const ANNOUNCE_FADE = 16000;
const MAX_HISTORY = 30;

const $ = (id) => document.getElementById(id);
const chat = $("chat");
const messages = $("messages");
const input = $("input");
const counter = $("counter");
const suggBox = $("suggestions");

let maxLength = 200;
let isOpen = false;
let access = {};
const suggestions = new Map();
const templates = {};
const history = [];
let historyIndex = -1;
let suggestionIndex = 0;

function post(name, data) {
    if (!IN_GAME) return Promise.resolve();
    return fetch(`https://${RESOURCE}/${name}`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
}

// ---------- Mise en forme ----------

const stripCodes = (text) => String(text ?? "").replace(/\^[0-9*_~=r]/g, "");

// Codes couleur ^0 à ^9 des scripts FiveM, rendus en <span> (texte brut uniquement)
function colored(text) {
    const fragment = document.createDocumentFragment();
    const parts = String(text ?? "").replace(/\^[*_~=r]/g, "").split(/\^([0-9])/);
    let color = null;
    parts.forEach((part, i) => {
        if (i % 2 === 1) {
            color = `c${part}`;
            return;
        }
        if (!part) return;
        fragment.append(el("span", color, part));
    });
    return fragment;
}

// "[12] Jean Dupont" -> id en police mono + nom
function authorNode(author, rgb) {
    const node = el("span", "author");
    const match = /^\[(\d+)\]\s*(.*)$/.exec(stripCodes(author));
    if (match) {
        node.append(el("span", "id", `[${match[1]}]`), match[2]);
    } else {
        node.textContent = stripCodes(author);
    }
    if (Array.isArray(rgb) && rgb.length === 3) node.style.color = `rgb(${rgb.map((n) => Number(n) || 0).join(",")})`;
    return node;
}

// Modèle HTML d'un script (chat:addMessage avec template) -> texte brut, sans exécuter de HTML
function templateToText(template, args) {
    const filled = String(template).replace(/\{(\d+)\}/g, (_, i) => stripCodes(args[Number(i)] ?? ""));
    return new DOMParser().parseFromString(filled, "text/html").body.textContent || "";
}

// ---------- Messages ----------

function pushMessage(node, fadeAfter) {
    messages.append(node);
    while (messages.children.length > MAX_MESSAGES) messages.firstChild.remove();

    setTimeout(() => {
        node.classList.add("old");
        setTimeout(() => node.classList.add("gone"), 650);
    }, fadeAfter || FADE_AFTER);

    const nearBottom = messages.scrollHeight - messages.scrollTop - messages.clientHeight < 80;
    if (!isOpen || nearBottom) messages.scrollTop = messages.scrollHeight;
}

function addMessage(message) {
    if (!message || typeof message !== "object") return;
    const kind = ["hrp", "staff", "announce", "system", "error"].includes(message.kind) ? message.kind : "system";
    const node = el("div", `msg ${kind}`);

    if (kind === "announce") {
        // L'auteur n'est pas montré aux joueurs (il reste dans la console et l'historique)
        const head = el("div", "head");
        head.append(el("span", "tag", "Annonce"));
        node.append(head, el("div", "text", message.text));
        return pushMessage(node, ANNOUNCE_FADE);
    }

    if (kind === "hrp") node.append(el("span", "tag", "HRP"));
    if (kind === "staff") node.append(el("span", "tag", "Staff"));
    if (kind === "error") node.append(el("span", "tag", "!"));

    if (message.author) node.append(authorNode(message.author));

    if (kind === "staff" && message.rank) {
        const rank = el("span", "rank");
        const dot = el("i");
        dot.style.background = /^#[0-9a-f]{6}$/i.test(message.rank.color) ? message.rank.color : "#9650ff";
        rank.append(dot, message.rank.name);
        node.append(rank);
    }

    node.append(el("span", "text", message.text));
    pushMessage(node);
}

// Format de la resource "chat" de FiveM : { color, args, template, templateId, multiline } ou texte
function addLegacy(message) {
    if (typeof message === "string") message = { args: [message] };
    if (!message || typeof message !== "object") return;

    const args = Array.isArray(message.args) ? message.args : [];
    const node = el("div", "msg system legacy");
    const template = message.template || (message.templateId && templates[message.templateId]);

    if (template) {
        node.append(el("span", "text", templateToText(template, args)));
    } else if (args.length >= 2 && stripCodes(args[0]) !== "") {
        node.append(authorNode(args[0], message.color));
        const text = el("span", "text");
        text.append(colored(args.slice(1).join(" ")));
        node.append(text);
    } else {
        const text = el("span", "text");
        text.append(colored(args.join(" ")));
        node.append(text);
    }
    node.classList.remove("system");
    pushMessage(node);
}

// ---------- Suggestions de commandes ----------

function addSuggestions(list) {
    if (!Array.isArray(list)) list = list && typeof list === "object" ? Object.values(list) : [];
    for (const s of list) {
        if (!s || typeof s.name !== "string") continue;
        const name = (s.name.startsWith("/") ? s.name : `/${s.name}`).toLowerCase();
        if (name.startsWith("/+") || name.startsWith("/-")) continue;
        suggestions.set(name, {
            name,
            help: typeof s.help === "string" ? s.help : "",
            params: Array.isArray(s.params) ? s.params : [],
            access: s.access,
        });
    }
    renderSuggestions();
}

function visibleSuggestions() {
    const value = input.value;
    if (!value.startsWith("/")) return { list: [], typingArgs: false };
    const typingArgs = value.includes(" ");
    const typed = value.split(" ")[0].toLowerCase();
    const list = [...suggestions.values()]
        .filter((s) => !s.access || access[s.access])
        .filter((s) => (typingArgs ? s.name === typed : s.name.startsWith(typed)))
        .sort((a, b) => a.name.localeCompare(b.name))
        .slice(0, 6);
    return { list, typingArgs };
}

function renderSuggestions() {
    const { list, typingArgs } = visibleSuggestions();
    suggBox.classList.toggle("on", isOpen && list.length > 0);
    if (!list.length) return suggBox.replaceChildren();

    suggestionIndex = Math.min(suggestionIndex, list.length - 1);
    const currentParam = typingArgs ? input.value.trim().split(/\s+/).length - 1 + (input.value.endsWith(" ") ? 1 : 0) - 1 : -1;

    suggBox.replaceChildren(...list.map((s, i) => {
        const row = el("div", `sugg${i === suggestionIndex && !typingArgs ? " active" : ""}`);
        const cmd = el("span", "cmd", s.name);
        s.params.forEach((p, index) => {
            cmd.append(" ", el("span", `p${index === currentParam ? " cur" : ""}`, `<${stripCodes(p && p.name) || "valeur"}>`));
        });
        row.append(cmd, el("span", "hint", i === suggestionIndex && !typingArgs ? "Tab" : ""));
        if (s.help) row.append(el("span", "help", stripCodes(s.help)));
        return row;
    }));
}

function completeSuggestion() {
    const { list, typingArgs } = visibleSuggestions();
    if (!list.length || typingArgs) return;
    input.value = `${list[suggestionIndex].name} `;
    suggestionIndex = 0;
    onInput();
}

// ---------- Saisie ----------

function updateCounter() {
    const value = input.value;
    if (value.startsWith("/") || value.length < maxLength * 0.7) {
        counter.textContent = "";
        return;
    }
    counter.textContent = `${value.length}/${maxLength}`;
    counter.classList.toggle("full", value.length >= maxLength);
}

function onInput() {
    if (!input.value.startsWith("/") && input.value.length > maxLength) input.value = input.value.slice(0, maxLength);
    updateCounter();
    renderSuggestions();
}

function setOpen(open) {
    isOpen = open;
    chat.classList.toggle("open", open);
    input.value = "";
    historyIndex = -1;
    suggestionIndex = 0;
    updateCounter();
    renderSuggestions();
    if (open) setTimeout(() => input.focus(), 0);
    else input.blur();
    messages.scrollTop = messages.scrollHeight;
}

function send() {
    const text = input.value.trim();
    if (text) {
        if (history[history.length - 1] !== text) history.push(text);
        if (history.length > MAX_HISTORY) history.shift();
        post("send", { text });
    } else {
        post("close");
    }
    setOpen(false);
}

function browseHistory(direction) {
    if (!history.length) return;
    if (historyIndex === -1) historyIndex = history.length;
    historyIndex = Math.max(0, Math.min(history.length, historyIndex + direction));
    input.value = historyIndex === history.length ? "" : history[historyIndex];
    onInput();
    input.setSelectionRange(input.value.length, input.value.length);
}

input.addEventListener("input", () => {
    suggestionIndex = 0;
    onInput();
});

input.addEventListener("keydown", (e) => {
    const { list, typingArgs } = visibleSuggestions();
    const browsingSuggestions = list.length > 1 && !typingArgs;

    switch (e.key) {
        case "Enter":
            e.preventDefault();
            send();
            break;
        case "Escape":
            e.preventDefault();
            post("close");
            setOpen(false);
            break;
        case "Tab":
            e.preventDefault();
            completeSuggestion();
            break;
        case "ArrowUp":
            e.preventDefault();
            if (browsingSuggestions) { suggestionIndex = (suggestionIndex - 1 + list.length) % list.length; renderSuggestions(); }
            else browseHistory(-1);
            break;
        case "ArrowDown":
            e.preventDefault();
            if (browsingSuggestions) { suggestionIndex = (suggestionIndex + 1) % list.length; renderSuggestions(); }
            else browseHistory(1);
            break;
        case "PageUp":
            e.preventDefault();
            messages.scrollTop -= messages.clientHeight * 0.8;
            break;
        case "PageDown":
            e.preventDefault();
            messages.scrollTop += messages.clientHeight * 0.8;
            break;
    }
});

// ---------- Messages venant du client Lua ----------

window.addEventListener("message", (event) => {
    const data = event.data;
    if (!data || typeof data !== "object") return;

    switch (data.type) {
        case "open": setOpen(true); break;
        case "close": setOpen(false); break;
        case "message": addMessage(data.message); break;
        case "legacy": addLegacy(data.message); break;
        case "template": if (typeof data.id === "string" && typeof data.html === "string") templates[data.id] = data.html; break;
        case "suggestions": addSuggestions(data.list); break;
        case "removeSuggestion": if (typeof data.name === "string") { suggestions.delete((data.name.startsWith("/") ? data.name : `/${data.name}`).toLowerCase()); renderSuggestions(); } break;
        case "clear": messages.replaceChildren(); break;
        case "access": access = data.flags && typeof data.flags === "object" ? data.flags : {}; renderSuggestions(); break;
        case "visible": document.body.classList.toggle("paused", !data.visible); break;
        case "config": if (Number(data.maxLength) > 0) maxLength = Number(data.maxLength); break;
    }
});

post("ready");

// ---------- Aperçu hors jeu (navigateur) ----------

if (!IN_GAME) {
    document.body.style.background = "linear-gradient(160deg, #56606b, #2b3036)"; // fond simulant le jeu
    const demo = (data) => window.postMessage(data, "*");
    demo({ type: "suggestions", list: [
        { name: "/hrp", help: "Message hors RP aux joueurs proches", params: [{ name: "message" }] },
        { name: "/me", help: "Action de votre personnage (texte au-dessus de la tête)", params: [{ name: "action" }] },
        { name: "/do", help: "Description de la scène (texte au-dessus de la tête)", params: [{ name: "description" }] },
        { name: "/sc", help: "Tchat staff privé", params: [{ name: "message" }], access: "staff" },
        { name: "/annonce", help: "Annonce à tout le serveur", params: [{ name: "message" }], access: "announce" },
    ] });
    demo({ type: "access", flags: { staff: true, announce: true } });
    demo({ type: "legacy", message: { color: [255, 200, 80], args: ["^3ESX", "Bienvenue sur ^5Lunatic^0 !"] } });
    demo({ type: "message", message: { kind: "hrp", author: "[12] Jean Dupont", text: "Quelqu'un sait où est le garage central ?" } });
    demo({ type: "message", message: { kind: "hrp", author: "[4] Léa Martin", text: "Juste derrière le commissariat, tout droit." } });
    demo({ type: "message", message: { kind: "staff", author: "[1] Kévin Rider", rank: { name: "Fondateur", color: "#9650ff" }, text: "Reboot prévu à 22 h, prévenez les joueurs." } });
    demo({ type: "message", message: { kind: "announce", author: "[1] Kévin Rider", rank: { name: "Fondateur", color: "#9650ff" }, text: "Redémarrage du serveur dans 10 minutes." } });
    demo({ type: "message", message: { kind: "error", text: "Doucement : attendez un peu avant d’envoyer un autre message." } });
    if (new URLSearchParams(location.search).get("open")) {
        setTimeout(() => { demo({ type: "open" }); setTimeout(() => { input.value = "/"; onInput(); }, 50); }, 50);
    }
}
