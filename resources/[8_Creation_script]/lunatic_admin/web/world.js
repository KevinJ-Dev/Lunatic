"use strict";

// ====================================================================
//  lunatic_admin — lot D : page Monde (météo et heure de lunatic_world)
// ====================================================================

const WEATHER_ICONS = {
    EXTRASUNNY: "☀", CLEAR: "🌤", CLOUDS: "⛅", OVERCAST: "☁", CLEARING: "🌦", RAIN: "🌧", THUNDER: "⛈",
    FOGGY: "🌫", SMOG: "🌁", SNOWLIGHT: "🌨", SNOW: "❄", BLIZZARD: "🌬", XMAS: "🎄", HALLOWEEN: "🎃",
};
const QUICK_TIMES = [
    { label: "Aube", hour: 6, minute: 0 },
    { label: "Midi", hour: 12, minute: 0 },
    { label: "Soir", hour: 18, minute: 30 },
    { label: "Nuit", hour: 22, minute: 0 },
    { label: "3 h", hour: 3, minute: 0 },
];

let worldDom = null;

function hasWorld() {
    return can("world.weather") || can("world.time");
}

const pad2 = (n) => String(n).padStart(2, "0");

function renderWorld() {
    const root = $("view-world");
    const world = state.world || {};

    if (!world.available) {
        worldDom = null;
        root.replaceChildren(h("div", { class: "content" }, h("div", { class: "empty" }, icon("i-sun"),
            "La resource lunatic_world n'est pas démarrée : météo et heure indisponibles.")));
        return;
    }

    // Structure gardée entre deux rafraîchissements (champ d'heure conservé)
    if (!worldDom || !root.contains(worldDom.weatherGrid)) {
        const hourInput = h("input", { class: "input mono", type: "time", value: `${pad2(world.hour)}:${pad2(world.minute)}` });
        worldDom = {
            clock: h("div", { class: "world-clock mono" }),
            clockSub: h("div", { class: "muted" }),
            weatherGrid: h("div", { class: "weather-grid" }),
            weatherToggles: h("div", { class: "mode-list" }),
            timeToggles: h("div", { class: "mode-list" }),
            hourInput,
        };

        const cards = [];

        if (can("world.time")) {
            cards.push(h("div", { class: "card" },
                h("h3", { class: "card-title" }, "Heure"),
                h("div", { class: "world-time" }, worldDom.clock, worldDom.clockSub),
                h("div", { class: "durations" }, QUICK_TIMES.map((t) => {
                    const chip = h("button", null, `${t.label} · ${pad2(t.hour)}:${pad2(t.minute)}`);
                    chip.addEventListener("click", () => setWorldTime(t.hour, t.minute));
                    return chip;
                })),
                h("div", { class: "spawn-row" }, hourInput, h("button", { class: "btn primary", onclick: () => {
                    const [hour, minute] = hourInput.value.split(":").map(Number);
                    if (Number.isInteger(hour) && Number.isInteger(minute)) setWorldTime(hour, minute);
                } }, icon("i-save"), "Appliquer")),
                worldDom.timeToggles
            ));
        }

        if (can("world.weather")) {
            cards.push(h("div", { class: "card" },
                h("h3", { class: "card-title" }, "Météo"),
                worldDom.weatherGrid,
                worldDom.weatherToggles
            ));
        }

        root.replaceChildren(h("div", { class: "content" },
            h("div", { class: "page-head" }, h("div", { class: "grow" },
                h("h1", { class: "page-title" }, "Météo et heure"),
                h("div", { class: "page-sub" }, "Météo et heure identiques pour tous les joueurs")
            )),
            h("div", { class: "scroll" }, h("div", { class: "world-grid" }, cards))
        ));
    }

    paintWorld(world);
}

function worldToggle(label, help, on, action) {
    const row = h("div", { class: `perm${on ? " on" : ""}` },
        h("span", { class: "switch" }),
        h("span", { class: "txt" }, h("span", null, label), h("code", null, help))
    );
    row.addEventListener("click", () => act(action, { enabled: !on }, null));
    return row;
}

function paintWorld(world) {
    worldDom.clock.textContent = `${pad2(world.hour)}:${pad2(world.minute)}`;
    worldDom.clockSub.textContent = world.frozen ? "Heure figée" : "L'heure avance normalement (1 min de jeu = 2 s)";

    if (can("world.time")) {
        worldDom.timeToggles.replaceChildren(
            worldToggle("Figer l'heure", "L'heure reste bloquée jusqu'à ce que vous la relanciez.", world.frozen, "world.freeze")
        );
    }

    if (can("world.weather")) {
        const weathers = Array.isArray(world.weathers) ? world.weathers : [];
        worldDom.weatherGrid.replaceChildren(...weathers.map((w) => {
            const tile = h("button", { class: `weather-tile${w.id === world.weather ? " on" : ""}`, title: w.id },
                h("span", { class: "weather-icon" }, WEATHER_ICONS[w.id] || "•"),
                h("span", null, w.label));
            tile.addEventListener("click", () => {
                if (w.id !== world.weather) act("world.weather", { weather: w.id }, `Météo : ${w.label} (transition en cours).`);
            });
            return tile;
        }));
        worldDom.weatherToggles.replaceChildren(
            worldToggle("Cycle météo automatique", `Change de météo toutes les ${world.cycleMinutes || 30} minutes, de façon réaliste.`, world.cycle, "world.cycle"),
            worldToggle("Panne de courant", "Coupe l'éclairage de la ville (les phares des véhicules restent allumés).", world.blackout, "world.blackout")
        );
    }
}

function setWorldTime(hour, minute) {
    act("world.time", { hour, minute }, `Heure réglée sur ${pad2(hour)}:${pad2(minute)}.`);
}
